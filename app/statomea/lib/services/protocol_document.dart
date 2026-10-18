import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

/// Protocole prérédigé au format Word (.docx) : titres de section (styles Titre et Titre 1), paragraphes ; les
/// éléments « à compléter » sont surlignés en jaune.
Uint8List protocolDocx(Project p) {
  final sections = protocolOutline(p);
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  String run(String t, {bool highlight = false}) =>
      '<w:r>${highlight ? '<w:rPr><w:highlight w:val="yellow"/></w:rPr>' : ''}<w:t xml:space="preserve">${esc(t)}</w:t></w:r>';
  String para(String t, {String? style}) {
    // Les marqueurs « [À compléter : …] » sont surlignés, le reste du paragraphe ne l'est pas.
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

  final body = StringBuffer()
    ..write(para(tr('Protocole de recherche', 'Research protocol'), style: 'Title'))
    ..write(para(p.title, style: 'Subtitle'))
    ..write(para(tr('Prérédigé par Statoméa ($engineName $engineVersion) à partir du projet ; les éléments surlignés sont à compléter par l\'investigateur.',
        'Pre-drafted by Statoméa ($engineName $engineVersion) from the project; highlighted items are to be completed by the investigator.')));
  for (var k = 0; k < sections.length; k++) {
    body.write(para('${k + 1}. ${sections[k].title}', style: 'Heading1'));
    for (final l in sections[k].paragraphs) {
      body.write(para(l));
    }
  }
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="$w"><w:body>$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
      '</w:body></w:document>';
  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="$w">'
      '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:after="80"/></w:pPr><w:rPr><w:b/><w:color w:val="1F4E79"/><w:sz w:val="40"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:rPr><w:sz w:val="28"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="1F4E79"/><w:sz w:val="28"/></w:rPr></w:style>'
      '</w:styles>';
  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';
  const docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  final archive = Archive();
  void add(String name, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('word/document.xml', document);
  add('word/_rels/document.xml.rels', docRels);
  add('word/styles.xml', styles);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
