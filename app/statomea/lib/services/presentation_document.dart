import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _w = 12192000, _h = 6858000; // 16:9
const _emu = 914400; // 1 pouce

/// Diaporama PowerPoint (.pptx, 16:9) : une diapositive par élément de [presentationSlides] ; zones de texte, tableaux
/// natifs (modifiables dans PowerPoint), éléments « à compléter » en orange.
Uint8List presentationPptx(Project p, {String date = ''}) {
  final slides = presentationSlides(p, date: date);
  final lang = tr('fr-FR', 'en-GB');
  var shapeId = 1;

  String runs(String t, {int size = 2000, bool bold = false, String color = '262626'}) {
    final out = StringBuffer();
    var i = 0;
    void run(String s, String c) {
      if (s.isEmpty) return;
      out.write('<a:r><a:rPr lang="$lang" sz="$size"${bold ? ' b="1"' : ''} dirty="0"><a:solidFill><a:srgbClr val="$c"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>${_x(s)}</a:t></a:r>');
    }

    for (final m in RegExp(r'\[(?:À compléter|To complete)[^\]]*\]').allMatches(t)) {
      run(t.substring(i, m.start), color);
      run(m.group(0)!, 'C55A11');
      i = m.end;
    }
    run(t.substring(i), color);
    return out.toString();
  }

  String textBox(String name, int x, int y, int cx, int cy, List<String> paras, {int size = 2000, bool bold = false, String color = '262626', bool bullets = false, String algn = 'l', String anchor = 't'}) {
    final id = ++shapeId;
    final ps = [
      for (final t in paras)
        '<a:p><a:pPr algn="$algn"${bullets ? ' marL="342900" indent="-342900"' : ''}>${bullets ? '<a:buFont typeface="Arial"/><a:buChar char="•"/>' : '<a:buNone/>'}<a:spcAft><a:spcPts val="600"/></a:spcAft></a:pPr>'
            '${runs(t, size: size, bold: bold, color: color)}<a:endParaRPr lang="$lang" sz="$size" dirty="0"/></a:p>'
    ].join();
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="${_x(name)} $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square" lIns="91440" tIns="45720" rIns="91440" bIns="45720" anchor="$anchor"><a:normAutofit/></a:bodyPr><a:lstStyle/>${ps.isEmpty ? '<a:p><a:endParaRPr lang="$lang" dirty="0"/></a:p>' : ps}</p:txBody></p:sp>';
  }

  String band() {
    final id = ++shapeId;
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Bandeau $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$_w" cy="${(0.12 * _emu).round()}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="1F4E79"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="$lang" dirty="0"/></a:p></p:txBody></p:sp>';
  }

  String table(ResultTable t, int x, int y, int cx, int maxCy) {
    final id = ++shapeId;
    final nCol = t.header.length;
    final rows = [t.header, ...t.rows];
    final rowH = (maxCy / rows.length).clamp(260000, 420000).round();
    final size = rows.length > 9 ? 1100 : (rows.length > 6 ? 1200 : 1400);
    final first = (cx * (nCol > 2 ? 0.34 : 0.5)).round();
    final rest = nCol > 1 ? ((cx - first) / (nCol - 1)).floor() : 0;
    final grid = [for (var c = 0; c < nCol; c++) '<a:gridCol w="${c == 0 ? first : rest}"/>'].join();
    String cell(String v, bool head) => '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>${runs(v, size: size, bold: head)}<a:endParaRPr lang="$lang" sz="$size" dirty="0"/></a:p></a:txBody>'
        '<a:tcPr marL="45720" marR="45720" marT="22860" marB="22860">${head ? '<a:solidFill><a:srgbClr val="DDEBF7"/></a:solidFill>' : '<a:noFill/>'}</a:tcPr></a:tc>';
    final trs = [
      for (var k = 0; k < rows.length; k++) '<a:tr h="$rowH">${[for (var c = 0; c < nCol; c++) cell(c < rows[k].length ? rows[k][c] : '', k == 0)].join()}</a:tr>'
    ].join();
    return '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Tableau $id"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
        '<p:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="${rowH * rows.length}"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
        '<a:tbl><a:tblPr firstRow="1" bandRow="1"/><a:tblGrid>$grid</a:tblGrid>$trs</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
  }

  final m = (0.5 * _emu).round();
  final slideXml = <String>[];
  for (var k = 0; k < slides.length; k++) {
    final s = slides[k];
    shapeId = 1;
    final shapes = StringBuffer();
    if (s.titleSlide) {
      shapes
        ..write(band())
        ..write(textBox('Titre', m, (1.9 * _emu).round(), _w - 2 * m, (1.6 * _emu).round(), [s.title], size: 3600, bold: true, color: '1F4E79', algn: 'ctr', anchor: 'b'))
        ..write(textBox('Sous-titre', m, (3.7 * _emu).round(), _w - 2 * m, (1.4 * _emu).round(), s.bullets, size: 2000, algn: 'ctr'));
    } else {
      shapes
        ..write(band())
        ..write(textBox('Titre', m, (0.3 * _emu).round(), _w - 2 * m, (0.9 * _emu).round(), [s.title], size: 3000, bold: true, color: '1F4E79', anchor: 'ctr'));
      var top = (1.35 * _emu).round();
      if (s.bullets.isNotEmpty) {
        final h = s.table == null ? (_h - top - m) : (0.5 * _emu * s.bullets.length).round().clamp((0.5 * _emu).round(), (1.6 * _emu).round());
        shapes.write(textBox('Texte', m, top, _w - 2 * m, h, s.bullets, size: s.table == null ? 2000 : 1600, bullets: s.table == null));
        top += h + (0.1 * _emu).round();
      }
      if (s.highlight != null) {
        shapes.write(textBox('Message', m, (2.2 * _emu).round(), _w - 2 * m, (2.6 * _emu).round(), [s.highlight!], size: 2800, bold: true, color: '1F4E79', algn: 'ctr', anchor: 'ctr'));
      }
      if (s.table != null) {
        shapes
          ..write(textBox('Légende', m, top, _w - 2 * m, (0.4 * _emu).round(), [s.table!.title], size: 1400, bold: true))
          ..write(table(s.table!, m, top + (0.45 * _emu).round(), _w - 2 * m, _h - top - (0.45 * _emu).round() - m));
      }
    }
    shapes.write(textBox('Numéro', _w - (1.5 * _emu).round(), _h - (0.45 * _emu).round(), (1.2 * _emu).round(), (0.35 * _emu).round(), ['${k + 1}'], size: 1000, color: '7F7F7F', algn: 'r'));
    slideXml.add('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '$shapes</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>');
  }

  const emptyTree = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
  const level = '<a:lvl1pPr><a:defRPr sz="1800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/></a:defRPr></a:lvl1pPr>';
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
        '<Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>'
        '<Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>'
        '${[for (var k = 0; k < slideXml.length; k++) '<Override PartName="/ppt/slides/slide${k + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'].join()}</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="ppt/presentation.xml"/></Relationships>',
    'ppt/presentation.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p" saveSubsetFonts="1">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>${[for (var k = 0; k < slideXml.length; k++) '<p:sldId id="${256 + k}" r:id="rId${10 + k}"/>'].join()}</p:sldIdLst>'
        '<p:sldSz cx="$_w" cy="$_h"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle>$level</p:defaultTextStyle></p:presentation>',
    'ppt/_rels/presentation.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="$_rel/theme" Target="theme/theme1.xml"/>'
        '<Relationship Id="rId3" Type="$_rel/presProps" Target="presProps.xml"/><Relationship Id="rId4" Type="$_rel/viewProps" Target="viewProps.xml"/>'
        '<Relationship Id="rId5" Type="$_rel/tableStyles" Target="tableStyles.xml"/>'
        '${[for (var k = 0; k < slideXml.length; k++) '<Relationship Id="rId${10 + k}" Type="$_rel/slide" Target="slides/slide${k + 1}.xml"/>'].join()}</Relationships>',
    'ppt/presProps.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentationPr xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p"/>',
    'ppt/viewProps.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:viewPr xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p"><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>',
    'ppt/tableStyles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:tblStyleLst xmlns:a="$_a" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>',
    'ppt/slideMasters/slideMaster1.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p">'
        '<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>$emptyTree</p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        '<p:txStyles><p:titleStyle>$level</p:titleStyle><p:bodyStyle>$level</p:bodyStyle><p:otherStyle>$level</p:otherStyle></p:txStyles></p:sldMaster>',
    'ppt/slideMasters/_rels/slideMaster1.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="$_rel/theme" Target="../theme/theme1.xml"/></Relationships>',
    'ppt/slideLayouts/slideLayout1.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p" type="blank" preserve="1">'
        '<p:cSld name="Blank"><p:spTree>$emptyTree</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>',
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>',
    'ppt/theme/theme1.xml': _theme,
  };
  for (var k = 0; k < slideXml.length; k++) {
    files['ppt/slides/slide${k + 1}.xml'] = slideXml[k];
    files['ppt/slides/_rels/slide${k + 1}.xml.rels'] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>';
  }
  final zip = Archive();
  for (final e in files.entries) {
    final d = utf8.encode(e.value);
    zip.addFile(ArchiveFile(e.key, d.length, d));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

const _theme = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="$_a" name="Statoméa"><a:themeElements>'
    '<a:clrScheme name="Statoméa"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F4E79"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
    '<a:accent1><a:srgbClr val="2E75B6"/></a:accent1><a:accent2><a:srgbClr val="C55A11"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>'
    '<a:fontScheme name="Statoméa"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
    '<a:fmtScheme name="Statoméa"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
    '<a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>'
    '</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>';
