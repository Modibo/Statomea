import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

/// Texte d'un document Word (.docx) ou PDF, extrait hors connexion pour lire un protocole de recherche.
String documentText(Uint8List bytes, String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  return switch (ext) {
    'docx' => docxText(bytes),
    'pdf' => pdfText(bytes),
    _ => throw StatInputError('doc_format', tr('Format non pris en charge : .$ext (Word .docx ou PDF attendus ; un ancien .doc doit être réenregistré en .docx).', 'Unsupported format: .$ext (Word .docx or PDF expected; an old .doc must be re-saved as .docx).')),
  };
}

/// Texte d'un .docx : paragraphes de word/document.xml (un paragraphe par ligne, tabulations et sauts conservés).
String docxText(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw StatInputError('docx_invalid', tr('Fichier Word illisible (un .doc ancien doit être réenregistré en .docx).', 'Unreadable Word file (an old .doc must be re-saved as .docx).'));
  }
  final doc = zip.findFile('word/document.xml');
  if (doc == null) throw StatInputError('docx_invalid', tr('Ce fichier n\'est pas un document Word (.docx).', 'This file is not a Word document (.docx).'));
  final xml = utf8.decode(doc.content as List<int>, allowMalformed: true);
  final out = StringBuffer();
  for (final p in RegExp(r'<w:p[ >][\s\S]*?</w:p>|<w:p/>').allMatches(xml)) {
    final para = StringBuffer();
    for (final t in RegExp(r'<w:t(?: [^>]*)?>([\s\S]*?)</w:t>|<w:tab/>|<w:br/>').allMatches(p.group(0)!)) {
      final g = t.group(0)!;
      if (g == '<w:tab/>') {
        para.write('\t');
      } else if (g == '<w:br/>') {
        para.write('\n');
      } else {
        para.write(_xmlUnescape(t.group(1)!));
      }
    }
    out.writeln(para.toString());
  }
  return out.toString();
}

String _xmlUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16)))
    .replaceAll('&amp;', '&');

// ------------------------------------------------------------------ PDF

/// Texte d'un PDF « texte » (produit par un traitement de texte) : flux de contenu décompressés, opérateurs de texte
/// (Tj, TJ, ', "), polices simples (WinAnsi) et composites (CMap ToUnicode), flux d'objets compris. Un PDF numérisé
/// (images) ne contient pas de texte : il est refusé avec un message.
String pdfText(Uint8List bytes) {
  final latin = latin1.decode(bytes, allowInvalid: true);
  if (!latin.startsWith('%PDF')) throw StatInputError('pdf_invalid', tr('Ce fichier n\'est pas un PDF.', 'This file is not a PDF.'));
  final objs = _PdfObjects(bytes, latin);
  // Polices : nom de ressource → table de correspondance (ToUnicode) et largeur des codes.
  final fontMaps = <String, _CMap>{};
  for (final e in objs.dicts.entries) {
    for (final m in RegExp(r'/([A-Za-z0-9_.+\-]+)\s+(\d+)\s+0\s+R').allMatches(e.value)) {
      final target = objs.dicts[int.parse(m.group(2)!)];
      if (target == null || !target.contains('/Type') || !RegExp(r'/Type\s*/Font').hasMatch(target)) continue;
      final tu = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R').firstMatch(target);
      final composite = RegExp(r'/Subtype\s*/Type0').hasMatch(target);
      _CMap cmap = _CMap(composite ? 2 : 1, {});
      if (tu != null) {
        final data = objs.stream(int.parse(tu.group(1)!));
        if (data != null) cmap = _CMap.parse(latin1.decode(data, allowInvalid: true), composite ? 2 : 1);
      }
      fontMaps[m.group(1)!] = cmap;
    }
  }
  final out = StringBuffer();
  for (final id in objs.contentStreams()) {
    final data = objs.stream(id);
    if (data == null) continue;
    _extractText(latin1.decode(data, allowInvalid: true), fontMaps, out);
    out.writeln();
  }
  final text = out.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.replaceAll(RegExp(r'\s'), '').length < 20) {
    throw StatInputError('pdf_no_text', tr('Ce PDF ne contient pas de texte lisible (document numérisé en image ?). Utiliser le fichier Word d\'origine ou un PDF exporté depuis un traitement de texte.',
        'This PDF contains no readable text (scanned image?). Use the original Word file or a PDF exported from a word processor.'));
  }
  return text;
}

class _CMap {
  final int width; // octets par code
  final Map<int, String> map;
  _CMap(this.width, this.map);

  static _CMap parse(String s, int defaultWidth) {
    final map = <int, String>{};
    var width = defaultWidth;
    final cs = RegExp(r'begincodespacerange\s*<([0-9A-Fa-f]+)>').firstMatch(s);
    if (cs != null) width = cs.group(1)!.length ~/ 2;
    String hex16(String h) {
      final b = StringBuffer();
      for (var i = 0; i + 4 <= h.length; i += 4) {
        b.writeCharCode(int.parse(h.substring(i, i + 4), radix: 16));
      }
      return b.toString();
    }

    for (final blk in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(s)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(blk.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = hex16(m.group(2)!);
      }
    }
    for (final blk in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(s)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])').allMatches(blk.group(1)!)) {
        final lo = int.parse(m.group(1)!, radix: 16), hi = int.parse(m.group(2)!, radix: 16);
        if (m.group(4) != null) {
          final base = m.group(4)!;
          final start = int.parse(base.substring(base.length - 4), radix: 16);
          final prefix = hex16(base.substring(0, base.length - 4));
          for (var c = lo; c <= hi && c - lo < 65536; c++) {
            map[c] = prefix + String.fromCharCode(start + c - lo);
          }
        } else {
          final arr = RegExp(r'<([0-9A-Fa-f]+)>').allMatches(m.group(5)!).toList();
          for (var k = 0; k < arr.length && lo + k <= hi; k++) {
            map[lo + k] = hex16(arr[k].group(1)!);
          }
        }
      }
    }
    return _CMap(width, map);
  }

  String decode(List<int> b) {
    final out = StringBuffer();
    for (var i = 0; i + width <= b.length; i += width) {
      var code = 0;
      for (var k = 0; k < width; k++) {
        code = code * 256 + b[i + k];
      }
      final u = map[code];
      if (u != null) {
        out.write(u);
      } else if (width == 1) {
        out.write(_winAnsi(code));
      }
    }
    return out.toString();
  }
}

String _winAnsi(int c) {
  const special = {0x80: '€', 0x82: '‚', 0x85: '…', 0x91: '‘', 0x92: '’', 0x93: '“', 0x94: '”', 0x95: '•', 0x96: '–', 0x97: '—', 0x9C: 'œ', 0x8C: 'Œ'};
  return special[c] ?? String.fromCharCode(c);
}

/// Opérateurs de texte d'un flux de contenu. La position verticale de la ligne de texte (Td, TD, Tm, T*) décide des
/// sauts de ligne : même hauteur → même ligne (espace entre blocs), hauteur différente → nouvelle ligne.
void _extractText(String s, Map<String, _CMap> fonts, StringBuffer out) {
  var cmap = _CMap(1, {});
  var lineY = 0.0, leading = 0.0;
  double? lastY;
  var newBlock = true;
  void emit(String txt) {
    if (txt.isEmpty) return;
    if (lastY != null && (lineY - lastY!).abs() > 1.0) {
      out.write('\n');
    } else if (lastY != null && newBlock) {
      out.write(' ');
    }
    out.write(txt);
    lastY = lineY;
    newBlock = false;
  }

  final tok = RegExp(r'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|\[|\]|/[^\s/\[\]()<>]+|-?\d*\.?\d+|[A-Za-z*\x27"]+');
  final stack = <String>[];
  final arr = <String>[];
  var inArr = false;
  double num(int fromEnd) => stack.length >= fromEnd ? double.tryParse(stack[stack.length - fromEnd]) ?? 0 : 0;
  for (final m in tok.allMatches(s)) {
    final t = m.group(0)!;
    if (t == '[') {
      inArr = true;
      arr.clear();
      continue;
    }
    if (t == ']') {
      inArr = false;
      stack.add('__ARR__');
      continue;
    }
    if (inArr) {
      arr.add(t);
      continue;
    }
    switch (t) {
      case 'BT':
        lineY = 0;
        newBlock = true;
      case 'Tf':
        if (stack.length >= 2) cmap = fonts[stack[stack.length - 2].substring(1)] ?? _CMap(1, {});
      case 'TL':
        leading = num(1);
      case 'Td':
        lineY += num(1);
      case 'TD':
        lineY += num(1);
        leading = -num(1);
      case 'Tm':
        lineY = num(1);
      case 'T*':
        lineY -= leading == 0 ? 12 : leading;
      case 'Tj':
        if (stack.isNotEmpty) emit(cmap.decode(_strBytes(stack.last)));
      case "'" || '"':
        lineY -= leading == 0 ? 12 : leading;
        if (stack.isNotEmpty) emit(cmap.decode(_strBytes(stack.last)));
      case 'TJ':
        final b = StringBuffer();
        for (final a in arr) {
          if (a.startsWith('(') || a.startsWith('<')) {
            b.write(cmap.decode(_strBytes(a)));
          } else if ((double.tryParse(a) ?? 0) < -180) {
            b.write(' ');
          }
        }
        emit(b.toString());
    }
    if (RegExp(r'^[A-Za-z*\x27"]+$').hasMatch(t)) {
      stack.clear();
    } else {
      stack.add(t);
    }
  }
}

/// Octets d'une chaîne PDF littérale « (…) » ou hexadécimale « <…> ».
List<int> _strBytes(String t) {
  if (t.startsWith('<')) {
    var h = t.substring(1, t.length - 1).replaceAll(RegExp(r'\s'), '');
    if (h.length.isOdd) h += '0';
    return [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
  }
  final b = <int>[];
  final s = t.substring(1, t.length - 1);
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c != 0x5C) {
      b.add(c);
      continue;
    }
    i++;
    if (i >= s.length) break;
    final e = s[i];
    switch (e) {
      case 'n':
        b.add(10);
      case 'r':
        b.add(13);
      case 't':
        b.add(9);
      case 'b':
        b.add(8);
      case 'f':
        b.add(12);
      case '\n':
      case '\r':
        break;
      default:
        if (RegExp(r'[0-7]').hasMatch(e)) {
          var oct = e;
          while (oct.length < 3 && i + 1 < s.length && RegExp(r'[0-7]').hasMatch(s[i + 1])) {
            oct += s[++i];
          }
          b.add(int.parse(oct, radix: 8) & 0xFF);
        } else {
          b.add(e.codeUnitAt(0));
        }
    }
  }
  return b;
}

/// Objets d'un PDF : dictionnaires (y compris ceux des flux d'objets) et flux décompressés.
class _PdfObjects {
  final Uint8List bytes;
  final String latin;
  final dicts = <int, String>{};
  final _streamPos = <int, (int, int, String)>{}; // id → (début, longueur, dictionnaire)

  _PdfObjects(this.bytes, this.latin) {
    for (final m in RegExp(r'(\d+)\s+\d+\s+obj\b').allMatches(latin)) {
      final id = int.parse(m.group(1)!);
      final end = latin.indexOf('endobj', m.end);
      if (end < 0) continue;
      final body = latin.substring(m.end, end);
      final si = body.indexOf('stream');
      final dict = si >= 0 ? body.substring(0, si) : body;
      dicts[id] = dict;
      if (si >= 0) {
        var start = m.end + si + 6;
        if (latin.codeUnitAt(start) == 13) start++;
        if (latin.codeUnitAt(start) == 10) start++;
        final lenM = RegExp(r'/Length\s+(\d+)(\s+\d+\s+R)?').firstMatch(dict);
        var len = -1;
        if (lenM != null && lenM.group(2) == null) len = int.parse(lenM.group(1)!);
        if (len < 0 || start + len > bytes.length) {
          final es = latin.indexOf('endstream', start);
          len = (es < 0 ? end : es) - start;
        }
        _streamPos[id] = (start, len, dict);
      }
    }
    // Flux d'objets (PDF 1.5+) : dictionnaires compressés.
    for (final e in _streamPos.entries.toList()) {
      if (!RegExp(r'/Type\s*/ObjStm').hasMatch(e.value.$3)) continue;
      final data = stream(e.key);
      if (data == null) continue;
      final s = latin1.decode(data, allowInvalid: true);
      final first = int.tryParse(RegExp(r'/First\s+(\d+)').firstMatch(e.value.$3)?.group(1) ?? '') ?? 0;
      final head = s.substring(0, first.clamp(0, s.length)).trim().split(RegExp(r'\s+'));
      final pairs = <(int, int)>[for (var k = 0; k + 1 < head.length; k += 2) (int.tryParse(head[k]) ?? -1, int.tryParse(head[k + 1]) ?? 0)];
      for (var k = 0; k < pairs.length; k++) {
        final a = first + pairs[k].$2, b = k + 1 < pairs.length ? first + pairs[k + 1].$2 : s.length;
        if (pairs[k].$1 >= 0 && a < b && b <= s.length) dicts.putIfAbsent(pairs[k].$1, () => s.substring(a, b));
      }
    }
  }

  Uint8List? stream(int id) {
    final p = _streamPos[id];
    if (p == null) return null;
    final raw = Uint8List.sublistView(bytes, p.$1, p.$1 + p.$2);
    if (!p.$3.contains('/FlateDecode')) return p.$3.contains('/Filter') ? null : raw;
    try {
      return Uint8List.fromList(const ZLibDecoder().decodeBytes(raw));
    } catch (_) {
      try {
        return Uint8List.fromList(Inflate(raw.sublist(2)).getBytes());
      } catch (_) {
        return null;
      }
    }
  }

  /// Flux de contenu des pages, dans l'ordre des pages quand il est connu.
  List<int> contentStreams() {
    final ids = <int>[];
    for (final d in dicts.values) {
      if (!RegExp(r'/Type\s*/Page\b').hasMatch(d)) continue;
      final c = RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+0\s+R)').firstMatch(d);
      if (c == null) continue;
      for (final r in RegExp(r'(\d+)\s+0\s+R').allMatches(c.group(1)!)) {
        ids.add(int.parse(r.group(1)!));
      }
    }
    return ids;
  }
}
