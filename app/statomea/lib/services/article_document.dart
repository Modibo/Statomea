import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart' hide Step;

import 'protocol_document.dart' show packDocx;

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Article prérédigé au format Word : titres de section (Titre 1, Titre 2), paragraphes, tableaux (Tableau 1,
/// résultats principaux) ; les éléments « à compléter » sont surlignés en jaune.
Uint8List articleDocx(Project p) {
  String run(String t, {bool highlight = false, bool bold = false, int? size}) {
    final props = [if (bold) '<w:b/>', if (highlight) '<w:highlight w:val="yellow"/>', if (size != null) '<w:sz w:val="$size"/>'].join();
    return '<w:r>${props.isEmpty ? '' : '<w:rPr>$props</w:rPr>'}<w:t xml:space="preserve">${_esc(t)}</w:t></w:r>';
  }

  String para(String t, {String? style}) {
    final runs = StringBuffer();
    var i = 0;
    for (final m in RegExp(r'\[(?:À compléter|To complete)[^\]]*\]').allMatches(t)) {
      if (m.start > i) runs.write(run(t.substring(i, m.start)));
      runs.write(run(m.group(0)!, highlight: true));
      i = m.end;
    }
    if (i < t.length) runs.write(run(t.substring(i)));
    return '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}$runs</w:p>';
  }

  String table(ResultTable t) {
    String cell(String v, {bool bold = false}) => '<w:tc><w:p><w:pPr><w:spacing w:after="0"/></w:pPr>${run(v, bold: bold, size: 18)}</w:p></w:tc>';
    final b = StringBuffer()
      ..write(para(t.title).replaceFirst('<w:r>', '<w:r><w:rPr><w:b/></w:rPr>'))
      ..write('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="8" w:color="000000"/><w:bottom w:val="single" w:sz="8" w:color="000000"/>'
          '<w:insideH w:val="single" w:sz="2" w:color="BFBFBF"/></w:tblBorders></w:tblPr>')
      ..write('<w:tr><w:trPr><w:tblHeader/></w:trPr>${[for (final h in t.header) cell(h, bold: true)].join()}</w:tr>');
    for (final r in t.rows) {
      b.write('<w:tr>${[for (var i = 0; i < t.header.length; i++) cell(i < r.length ? r[i] : '')].join()}</w:tr>');
    }
    b.write('</w:tbl>${para('')}');
    return b.toString();
  }

  final body = StringBuffer()
    ..write(para(p.title, style: 'Title'))
    ..write(para(tr('Article prérédigé par Statoméa ($engineName $engineVersion) à partir du projet ; les passages surlignés sont à rédiger par les auteurs.',
        'Article pre-drafted by Statoméa ($engineName $engineVersion) from the project; highlighted passages are for the authors to write.')))
    ..write(para(tr('Auteurs : [À compléter : auteurs et affiliations]', 'Authors: [To complete: authors and affiliations]')));
  for (final s in articleOutline(p)) {
    body.write(para(s.title, style: s.sub ? 'Heading2' : 'Heading1'));
    for (final l in s.paragraphs) {
      body.write(para(l));
    }
    for (final t in s.tables) {
      body.write(table(t));
    }
  }
  return packDocx(body.toString());
}
