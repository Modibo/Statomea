import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Tableau Word (.docx) : titre, tableau avec en-tête en gras et bordures, notes en dessous.
Uint8List tableDocx(String title, List<String> header, List<List<String>> rows, {List<String> notes = const []}) {
  String cell(String t, {bool bold = false}) => '<w:tc><w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="18"/></w:rPr>'
      '<w:t xml:space="preserve">${_x(t)}</w:t></w:r></w:p></w:tc>';
  final b = StringBuffer()
    ..write('<w:p><w:r><w:rPr><w:b/><w:sz w:val="24"/></w:rPr><w:t xml:space="preserve">${_x(title)}</w:t></w:r></w:p>')
    ..write('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/><w:tblBorders>'
        '<w:top w:val="single" w:sz="8" w:color="000000"/><w:bottom w:val="single" w:sz="8" w:color="000000"/>'
        '<w:insideH w:val="single" w:sz="2" w:color="BFBFBF"/></w:tblBorders></w:tblPr>')
    ..write('<w:tr><w:trPr><w:tblHeader/></w:trPr>${[for (final h in header) cell(h, bold: true)].join()}</w:tr>');
  for (final r in rows) {
    b.write('<w:tr>${[for (var i = 0; i < header.length; i++) cell(i < r.length ? r[i] : '')].join()}</w:tr>');
  }
  b.write('</w:tbl>');
  for (final n in notes) {
    b.write('<w:p><w:r><w:rPr><w:i/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">${_x(n)}</w:t></w:r></w:p>');
  }
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final files = {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/document.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="$w"><w:body>$b'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>',
  };
  final zip = Archive();
  for (final e in files.entries) {
    final d = utf8.encode(e.value);
    zip.addFile(ArchiveFile(e.key, d.length, d));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

/// Tableau Excel (.xlsx) : en-tête en gras, une ligne par ligne du tableau, notes sous le tableau.
Uint8List tableXlsx(String sheetName, List<String> header, List<List<String>> rows, {List<String> notes = const []}) {
  String col(int i) {
    var s = '';
    var k = i + 1;
    while (k > 0) {
      s = String.fromCharCode(65 + (k - 1) % 26) + s;
      k = (k - 1) ~/ 26;
    }
    return s;
  }

  String c(int r, int i, String v, {bool bold = false}) => '<c r="${col(i)}$r" t="inlineStr"${bold ? ' s="1"' : ''}><is><t xml:space="preserve">${_x(v)}</t></is></c>';
  final data = StringBuffer('<row r="1">${[for (var i = 0; i < header.length; i++) c(1, i, header[i], bold: true)].join()}</row>');
  for (var k = 0; k < rows.length; k++) {
    data.write('<row r="${k + 2}">${[for (var i = 0; i < rows[k].length; i++) if (rows[k][i].isNotEmpty) c(k + 2, i, rows[k][i])].join()}</row>');
  }
  for (var k = 0; k < notes.length; k++) {
    final r = rows.length + 3 + k;
    data.write('<row r="$r">${c(r, 0, notes[k])}</row>');
  }
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  final files = {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="$ns" xmlns:r="$rel"><sheets><sheet name="${_x(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="$ns"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    'xl/worksheets/sheet1.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$ns" xmlns:r="$rel"><cols><col min="1" max="1" width="42" customWidth="1"/>'
        '<col min="2" max="${header.length}" width="20" customWidth="1"/></cols><sheetData>$data</sheetData></worksheet>',
  };
  final zip = Archive();
  for (final e in files.entries) {
    final d = utf8.encode(e.value);
    zip.addFile(ArchiveFile(e.key, d.length, d));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}
