import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

/// Protocole Word corrigé : le document d'origine, inchangé, avec
///  - un commentaire Word « Statoméa » sur chaque passage en cause (erreur, point à revoir), ancré au paragraphe qui
///    contient la citation ;
///  - en fin de document, une section « Relecture méthodologique Statoméa » : tous les points (y compris les manques),
///    les corrections appliquées au projet, les paragraphes à ajouter au plan d'analyse (surlignés) et les éléments
///    absents de la grille SPIRIT / STROBE / STARD / TRIPOD.
/// Les commentaires existants du document sont conservés.
class AnnotatedProtocol {
  final Uint8List bytes;
  final int anchored; // constats ancrés à un passage
  final int total; // constats à traiter
  const AnnotatedProtocol(this.bytes, this.anchored, this.total);
}

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _key(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'").replaceAll(RegExp(r'[«»“”…"]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _unescape(String s) =>
    s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

AnnotatedProtocol annotateProtocolDocx(Uint8List original, Project p, {DateTime? now}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(original);
  } catch (_) {
    throw StatInputError('docx_invalid', tr('Fichier Word illisible.', 'Unreadable Word file.'));
  }
  final docFile = zip.findFile('word/document.xml');
  if (docFile == null) throw StatInputError('docx_invalid', tr('Ce fichier n\'est pas un document Word (.docx).', 'This file is not a Word document (.docx).'));
  String read(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);
  var xml = read(docFile);
  final review = reviewProject(p);
  final problems = review.problems;
  final date = (now ?? DateTime.now()).toUtc().toIso8601String().split('.').first;
  final dateZ = '${date}Z';

  // Identifiants de commentaires libres (le document peut déjà en contenir).
  final commentsFile = zip.findFile('word/comments.xml');
  final existingComments = commentsFile == null ? null : read(commentsFile);
  var nextId = 0;
  for (final m in RegExp(r'w:id="(\d+)"').allMatches('${existingComments ?? ''}$xml')) {
    final v = int.parse(m.group(1)!);
    if (v >= nextId) nextId = v + 1;
  }

  // Paragraphes du corps (hors replis VML des zones de texte), avec leur texte.
  final fallback = [for (final m in RegExp(r'<mc:Fallback>[\s\S]*?</mc:Fallback>').allMatches(xml)) (m.start, m.end)];
  final paras = <(int, int, String)>[];
  for (final m in RegExp(r'<w:p[ >][\s\S]*?</w:p>').allMatches(xml)) {
    if (fallback.any((f) => m.start >= f.$1 && m.start < f.$2)) continue;
    final text = [for (final t in RegExp(r'<w:t(?: [^>]*)?>([\s\S]*?)</w:t>').allMatches(m.group(0)!)) _unescape(t.group(1)!)].join();
    paras.add((m.start, m.end, _key(text)));
  }
  int? paragraphOf(String evidence) {
    final e = _key(evidence);
    if (e.length < 8) return null;
    for (final probe in [e.substring(0, e.length.clamp(0, 60)), if (e.length > 40) e.substring(e.length - 40)]) {
      for (var i = 0; i < paras.length; i++) {
        if (paras[i].$3.contains(probe)) return i;
      }
    }
    return null;
  }

  final comments = StringBuffer();
  final inserts = <(int, String)>[]; // position, texte inséré
  String commentXml(int id, List<String> lines) => '<w:comment w:id="$id" w:author="Statoméa" w:date="$dateZ" w:initials="S">'
      '${[for (final l in lines) '<w:p><w:r><w:t xml:space="preserve">${_esc(l)}</w:t></w:r></w:p>'].join()}</w:comment>';
  void anchor(int pi, List<String> lines) {
    final (start, end, _) = paras[pi];
    final seg = xml.substring(start, end);
    var open = seg.indexOf('>') + 1;
    if (seg.substring(open).startsWith('<w:pPr')) {
      final close = seg.indexOf('</w:pPr>', open);
      if (close > 0) open = close + '</w:pPr>'.length;
    }
    final id = nextId++;
    inserts.add((start + open, '<w:commentRangeStart w:id="$id"/>'));
    inserts.add((end - '</w:p>'.length, '<w:commentRangeEnd w:id="$id"/><w:r><w:commentReference w:id="$id"/></w:r>'));
    comments.write(commentXml(id, lines));
  }

  var anchored = 0;
  // Points déjà corrigés dans Statoméa : le document d'origine contient toujours le passage en cause.
  for (final c in p.corrections) {
    final pi = c.evidence == null ? null : paragraphOf(c.evidence!);
    if (pi == null) continue;
    final lvl = ReviewLevel.values.where((l) => l.name == c.level).firstOrNull;
    anchor(pi, [
      '[${lvl == null ? '' : '${reviewLevelLabel(lvl)} — '}${tr('corrigé dans Statoméa', 'corrected in Statoméa')}] ${c.title}',
      if (c.problem.isNotEmpty) c.problem,
      '${tr('Correction appliquée : ', 'Correction applied: ')}${c.detail}',
    ]);
    anchored++;
  }
  for (final f in problems) {
    final pi = f.evidence == null ? null : paragraphOf(f.evidence!);
    if (pi == null) continue;
    anchor(pi, [
      '[${reviewLevelLabel(f.level)}] ${f.title}',
      f.problem,
      if (f.correction.isNotEmpty) '${tr('Correction : ', 'Correction: ')}${f.correction}',
    ]);
    anchored++;
  }
  // Commentaire d'ensemble sur le premier paragraphe non vide.
  final first = paras.indexWhere((x) => x.$3.isNotEmpty);
  if (first >= 0) {
    anchor(first, [
      tr('Relecture méthodologique Statoméa ($engineName $engineVersion) : ${review.count(ReviewLevel.error)} erreur(s), ${review.count(ReviewLevel.warning)} point(s) à revoir, ${review.count(ReviewLevel.missing)} élément(s) manquant(s).',
          'Statoméa methodological review ($engineName $engineVersion): ${review.count(ReviewLevel.error)} error(s), ${review.count(ReviewLevel.warning)} point(s) to review, ${review.count(ReviewLevel.missing)} missing item(s).'),
      tr('Les points sont commentés dans le texte et récapitulés en fin de document, avec les paragraphes proposés pour le plan d\'analyse.', 'Points are commented in the text and summarised at the end of the document, with the paragraphs proposed for the analysis plan.'),
    ]);
  }

  // Section récapitulative en fin de document.
  String run(String t, {bool bold = false, bool highlight = false, int? size, bool italic = false}) {
    final props = [if (bold) '<w:b/>', if (italic) '<w:i/>', if (highlight) '<w:highlight w:val="yellow"/>', if (size != null) '<w:sz w:val="$size"/>'].join();
    return '<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>';
  }

  String para(String runs) => '<w:p>$runs</w:p>';
  final grid = protocolChecklist(p);
  final marker = RegExp(r'(Correction Statoméa|Statoméa correction) — ').firstMatch(p.analysisPlan);
  final blocks = marker == null ? <String>[] : p.analysisPlan.substring(marker.start).split(RegExp(r'\n\s*\n'));
  final sum = StringBuffer()
    ..write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
    ..write(para(run(tr('Relecture méthodologique Statoméa', 'Statoméa methodological review'), bold: true, size: 32)))
    ..write(para(run(tr('Établie le ${date.substring(0, 10)} par $engineName $engineVersion, par des règles explicites ; elle ne remplace pas la relecture d\'un méthodologiste.',
            'Prepared on ${date.substring(0, 10)} by $engineName $engineVersion, by explicit rules; it does not replace review by a methodologist.'),
        italic: true)));
  sum.write(para(run(tr('Points restant à traiter', 'Points still to address'), bold: true, size: 26)));
  if (problems.isEmpty) sum.write(para(run(tr('Aucun.', 'None.'))));
  for (var k = 0; k < problems.length; k++) {
    final f = problems[k];
    sum
      ..write(para(run('${k + 1}. [${reviewLevelLabel(f.level)}] ${f.title}', bold: true)))
      ..write(para(run(f.problem)));
    if (f.evidence != null) sum.write(para(run('« ${f.evidence} »', italic: true)));
    if (f.correction.isNotEmpty) sum.write(para(run(tr('Correction : ', 'Correction: '), bold: true) + run(f.correction)));
  }
  if (p.corrections.isNotEmpty) {
    sum.write(para(run(tr('Points corrigés dans Statoméa', 'Points corrected in Statoméa'), bold: true, size: 26)));
    for (final c in p.corrections) {
      sum.write(para(run('• ${c.title}', bold: true)));
      if (c.problem.isNotEmpty) sum.write(para(run(c.problem)));
      if (c.evidence != null) sum.write(para(run('« ${c.evidence} »', italic: true)));
      sum.write(para(run(tr('Correction appliquée : ', 'Correction applied: '), bold: true) + run(c.detail)));
    }
  }
  if (blocks.isNotEmpty) {
    sum.write(para(run(tr('Paragraphes à ajouter au plan d\'analyse', 'Paragraphs to add to the analysis plan'), bold: true, size: 26)));
    for (final b in blocks) {
      for (final l in b.split('\n')) {
        if (l.trim().isNotEmpty) sum.write(para(run(l.trim(), highlight: true)));
      }
    }
  }
  if (grid != null && grid.missing.isNotEmpty) {
    sum.write(para(run(tr('Grille ${grid.name} : éléments non trouvés (${grid.missing.length} sur ${grid.items.length})', '${grid.name} checklist: items not found (${grid.missing.length} of ${grid.items.length})'), bold: true, size: 26)));
    for (final it in grid.missing) {
      sum.write(para(run('• ${it.code} — ${it.label}')));
    }
  }
  final sect = xml.lastIndexOf('<w:sectPr');
  final bodyEnd = xml.lastIndexOf('</w:body>');
  final at = sect > 0 && sect < bodyEnd ? sect : bodyEnd;
  inserts.add((at, sum.toString()));

  inserts.sort((a, b) => b.$1.compareTo(a.$1));
  final out = StringBuffer();
  var cursor = xml.length;
  final pieces = <String>[];
  for (final (pos, text) in inserts) {
    pieces.add(xml.substring(pos, cursor));
    pieces.add(text);
    cursor = pos;
  }
  pieces.add(xml.substring(0, cursor));
  for (final s in pieces.reversed) {
    out.write(s);
  }
  xml = out.toString();

  final commentsXml = existingComments == null
      ? '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:comments xmlns:w="$_w">$comments</w:comments>'
      : existingComments.replaceFirst('</w:comments>', '$comments</w:comments>');

  final files = <String, List<int>>{
    'word/document.xml': utf8.encode(xml),
    'word/comments.xml': utf8.encode(commentsXml),
  };
  final relsFile = zip.findFile('word/_rels/document.xml.rels');
  var rels = relsFile == null ? '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>' : read(relsFile);
  if (!rels.contains('relationships/comments"')) {
    rels = rels.replaceFirst('</Relationships>', '<Relationship Id="rIdStatomeaComments" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/></Relationships>');
  }
  files['word/_rels/document.xml.rels'] = utf8.encode(rels);
  final ctFile = zip.findFile('[Content_Types].xml');
  if (ctFile != null) {
    var ct = read(ctFile);
    if (!ct.contains('/word/comments.xml')) {
      ct = ct.replaceFirst('</Types>', '<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/></Types>');
    }
    files['[Content_Types].xml'] = utf8.encode(ct);
  }

  final outZip = Archive();
  final done = <String>{};
  for (final f in zip.files) {
    if (!f.isFile) continue;
    final repl = files[f.name];
    final data = repl ?? (f.content as List<int>);
    outZip.addFile(ArchiveFile(f.name, data.length, data));
    done.add(f.name);
  }
  for (final e in files.entries) {
    if (!done.contains(e.key)) outZip.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return AnnotatedProtocol(Uint8List.fromList(ZipEncoder().encode(outZip)), anchored, problems.length + p.corrections.length);
}
