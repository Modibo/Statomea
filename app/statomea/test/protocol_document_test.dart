import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/protocol_annotate.dart';
import 'package:statomea/services/protocol_document.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Project _project() {
  const t = 'Essai randomisé : la vitamine D réduit-elle la pression artérielle à 12 mois chez les adultes hypertendus ?';
  final p = Project(id: 'pr', title: 'Vitamine D & HTA', createdAt: '', question: applyInference(const ResearchQuestion(text: t), inferQuestion(t)).$1);
  p.analysisPlan = draftAnalysisPlan(p.question);
  return p;
}

void main() {
  test('protocole Word : paquet .docx complet, XML bien formé (vérifié par Python), relu à l\'identique', () async {
    final bytes = protocolDocx(_project());
    final zip = ZipDecoder().decodeBytes(bytes);
    expect([for (final f in zip.files) f.name], containsAll(['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/_rels/document.xml.rels', 'word/styles.xml']));
    final dir = await Directory.systemTemp.createTemp('statomea_docx');
    final file = File('${dir.path}/protocole.docx')..writeAsBytesSync(bytes);
    final check = await Process.run('python3', ['-c', 'import sys,zipfile,xml.dom.minidom as m\nz=zipfile.ZipFile(sys.argv[1])\n[m.parseString(z.read(n)) for n in z.namelist()]\nprint("ok")', file.path]);
    expect('${check.stdout}'.trim(), 'ok', reason: '${check.stderr}');
    final text = docxText(bytes);
    expect(text, contains('Protocole de recherche'));
    expect(text, contains('Vitamine D & HTA'));
    expect(text, contains('1. Identification'));
    expect(text, contains('[À compléter : critères d\'inclusion]'));
    expect(text.indexOf('Nombre de sujets nécessaires'), lessThan(text.indexOf('Plan d\'analyse statistique')));
    await dir.delete(recursive: true);
  });

  test('protocole PDF : rubriques dans l\'ordre (relu par l\'extracteur)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = pdfText(await buildProtocolPdf(_project())).replaceAll(RegExp(r'\s+'), ' ');
    var last = -1;
    final titles = protocolOutline(_project()).map((s) => s.title).toList();
    for (var k = 0; k < titles.length; k++) {
      final h = '${k + 1}. ${titles[k]}';
      final i = text.indexOf(h);
      expect(i, greaterThan(last), reason: h);
      last = i;
    }
    expect(text, contains('[À compléter'));
  });

  test('Word : une zone de texte (forme moderne + repli VML) n\'est lue qu\'une fois', () {
    const body = '<w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><w:txbxContent><w:p><w:r><w:t>Réalisé par</w:t></w:r></w:p></w:txbxContent></w:drawing></mc:Choice>'
        '<mc:Fallback><w:pict><w:txbxContent><w:p><w:r><w:t>Réalisé par</w:t></w:r></w:p></w:txbxContent></w:pict></mc:Fallback></mc:AlternateContent></w:r></w:p>'
        '<w:p><w:r><w:t>Objectif</w:t></w:r></w:p>';
    final xml = utf8.encode('<?xml version="1.0"?><w:document xmlns:w="w" xmlns:mc="mc"><w:body>$body</w:body></w:document>');
    final zip = Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml));
    final text = docxText(Uint8List.fromList(ZipEncoder().encode(zip)));
    expect('Réalisé par'.allMatches(text).length, 1);
    expect(text, contains('Objectif'));
  });

  test('protocole Word d\'origine annoté : commentaires ancrés aux passages, récapitulatif, commentaires existants conservés', () async {
    String esc(String t) => t.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll("'", '&apos;');
    final paragraphs = [
      'Thème : Anémie chez les femmes enceintes à l\'hôpital régional.',
      'Objectif général :',
      'Rechercher les facteurs associés à l\'anémie chez les femmes enceintes.',
      'Type d\'étude : Étude transversale.',
      'Taille de l\'échantillon',
      'Avec une prévalence attendue de 40 %, une marge d\'erreur de 5 % et un niveau de confiance de 95 %, il faut 369 femmes. En ajoutant 10 % pour les refus, nous inclurons 406 femmes.',
      'Analyse statistique',
      'Les variables quantitatives seront comparées par le test de Student ou le Kruskall Wallis au seuil de 5 %.',
    ];
    final body = [for (final l in paragraphs) '<w:p><w:pPr><w:jc w:val="both"/></w:pPr><w:r><w:t xml:space="preserve">${esc(l)}</w:t></w:r></w:p>'].join();
    const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final files = <String, String>{
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/></Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
      'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/></Relationships>',
      'word/comments.xml': '<?xml version="1.0" encoding="UTF-8"?><w:comments xmlns:w="$w"><w:comment w:id="0" w:author="Directeur"><w:p><w:r><w:t>Revoir le titre</w:t></w:r></w:p></w:comment></w:comments>',
      'word/document.xml': '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="$w"><w:body>$body<w:sectPr/></w:body></w:document>',
    };
    final zip = Archive();
    for (final e in files.entries) {
      final b = utf8.encode(e.value);
      zip.addFile(ArchiveFile(e.key, b.length, b));
    }
    final original = Uint8List.fromList(ZipEncoder().encode(zip));
    final d = protocolFromText(docxText(original));
    final p = Project(id: 'a', title: d.title, createdAt: '')
      ..question = d.toQuestion()
      ..protocol = Map.of(d.fullSections)
      ..analysisPlan = d.sections['analysis']!;
    p.inferred['plannedSampleSize'] = '${d.sampleSize}';
    applyAllCorrections(p, date: '2026-10-19');
    final a = annotateProtocolDocx(original, p, now: DateTime.utc(2026, 10, 19, 9));
    expect(a.anchored, greaterThanOrEqualTo(3), reason: 'pertes et tests (corrigés), précision');
    final out = ZipDecoder().decodeBytes(a.bytes);
    String part(String n) => utf8.decode(out.findFile(n)!.content as List<int>);
    final doc = part('word/document.xml'), com = part('word/comments.xml');
    expect(com, contains('Revoir le titre'), reason: 'commentaire existant conservé');
    expect(RegExp(r'<w:comment ').allMatches(com).length, a.anchored + 2, reason: 'constats ancrés + commentaire d\'ensemble + commentaire existant');
    expect(com, contains('w:id="0" w:author="Directeur"'));
    expect(com, isNot(contains('w:id="0" w:author="Statoméa"')), reason: 'identifiants nouveaux, sans collision');
    for (final m in RegExp(r'<w:comment w:id="(\d+)" w:author="Statoméa"').allMatches(com)) {
      final id = m.group(1);
      expect(doc, contains('<w:commentRangeStart w:id="$id"/>'));
      expect(doc, contains('<w:commentReference w:id="$id"/>'));
    }
    expect(com, contains('Majoration pour les pertes mal calculée'));
    expect(com, contains('corrigé dans Statoméa'));
    expect(doc, contains('</w:pPr><w:commentRangeStart'), reason: 'après les propriétés du paragraphe (ordre du schéma)');
    expect(RegExp('relationships/comments"').allMatches(part('word/_rels/document.xml.rels')).length, 1);
    expect(RegExp('/word/comments.xml').allMatches(part('[Content_Types].xml')).length, 1);
    final text = docxText(a.bytes);
    for (final l in paragraphs) {
      expect(text, contains(l), reason: 'texte d\'origine inchangé');
    }
    expect(text, contains('Relecture méthodologique Statoméa'));
    expect(text, contains('Points corrigés dans Statoméa'));
    expect(text, contains('Paragraphes à ajouter au plan d\'analyse'));
    expect(text.indexOf('Relecture méthodologique Statoméa'), greaterThan(text.indexOf(paragraphs.last)));
    final dir = await Directory.systemTemp.createTemp('statomea_annot');
    final file = File('${dir.path}/annote.docx')..writeAsBytesSync(a.bytes);
    final check = await Process.run('python3', ['-c', 'import sys,zipfile,xml.dom.minidom as m\nz=zipfile.ZipFile(sys.argv[1])\n[m.parseString(z.read(n)) for n in z.namelist()]\nprint("ok")', file.path]);
    expect('${check.stdout}'.trim(), 'ok', reason: '${check.stderr}');
    await dir.delete(recursive: true);
  });
}
