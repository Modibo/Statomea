/// Lecture des classeurs Excel (.xlsx) à partir de leurs fichiers XML internes (le décompactage du zip est fait par
/// l'application) : feuilles, chaînes partagées ou en ligne, nombres, booléens, dates (formats de date intégrés ou
/// personnalisés, système 1900 ou 1904). Pur Dart, sans dépendance. Validé contre validation/r/49_excel.R (readxl 1.4).
library;

import 'dart:math' as math;

import '../i18n.dart';
import 'dataset.dart';

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&');

String? _attr(String tag, String name) {
  final m = RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(tag);
  return m == null ? null : _unescape(m[1]!);
}

/// Texte d'un élément (concatène les éléments `t` d'un texte enrichi).
String _texts(String xml) => [for (final m in RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>').allMatches(xml)) _unescape(m[1]!)].join();

class XlsxWorkbook {
  final List<String> sheetNames;
  final Map<String, String> _sheetPath;
  final Map<String, String> _parts;
  final List<String> _shared;
  final Set<int> _dateStyles;
  final bool _date1904;
  XlsxWorkbook._(this.sheetNames, this._sheetPath, this._parts, this._shared, this._dateStyles, this._date1904);

  /// Feuille [name] (défaut : la première) en jeu de données : la première ligne non vide donne les noms de colonnes.
  Dataset sheet({String? name, String source = 'Excel'}) {
    final sn = name ?? sheetNames.first;
    final xml = _parts[_sheetPath[sn]];
    if (xml == null) throw FormatException(tr('Feuille « $sn » introuvable.', 'Sheet "$sn" not found.'));
    final grid = <int, Map<int, String?>>{};
    var maxCol = -1;
    for (final row in RegExp(r'<row\b[^>]*>([\s\S]*?)</row>|<row\b[^>]*/>').allMatches(xml)) {
      final body = row[1] ?? '';
      final rTag = row[0]!.substring(0, row[0]!.indexOf('>') + 1);
      final rIdx = int.tryParse(_attr(rTag, 'r') ?? '') ?? (grid.length + 1);
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)').allMatches(body)) {
        final a = c[1]!, inner = c[2] ?? '';
        final ref = _attr(a, 'r');
        final col = ref == null ? (grid[rIdx]?.length ?? 0) : _colIndex(ref);
        final t = _attr(a, 't') ?? 'n';
        final s = int.tryParse(_attr(a, 's') ?? '');
        final vm = RegExp(r'<v>([\s\S]*?)</v>').firstMatch(inner);
        final v = vm == null ? null : _unescape(vm[1]!);
        String? val;
        switch (t) {
          case 's':
            val = v == null ? null : _shared[int.parse(v)];
          case 'inlineStr':
            val = _texts(inner);
          case 'str':
            val = v;
          case 'b':
            val = v == null ? null : (v == '1' ? 'TRUE' : 'FALSE');
          case 'e':
            val = null; // erreur de formule (#N/A…) : valeur manquante
          default:
            if (v != null) {
              final x = double.tryParse(v);
              val = x == null ? v : (s != null && _dateStyles.contains(s) ? _excelDate(x) : _number(x));
            }
        }
        if (val != null && val.isEmpty) val = null;
        (grid[rIdx] ??= {})[col] = val;
        maxCol = math.max(maxCol, col);
      }
    }
    final rows = grid.keys.toList()..sort();
    final first = rows.firstWhere((r) => grid[r]!.values.any((v) => v != null), orElse: () => -1);
    if (first < 0) throw FormatException(tr('Feuille « $sn » vide.', 'Sheet "$sn" is empty.'));
    final header = [for (var c = 0; c <= maxCol; c++) grid[first]![c] ?? tr('colonne_${c + 1}', 'column_${c + 1}')];
    // Colonnes entièrement vides en fin de tableau ignorées ; lignes entièrement vides ignorées.
    final data = <List<String?>>[
      for (final r in rows)
        if (r > first && grid[r]!.values.any((v) => v != null)) [for (var c = 0; c <= maxCol; c++) grid[r]![c]]
    ];
    return Dataset(header, data, source: '$source — $sn');
  }

  String _excelDate(double serial) {
    // Système 1900 : jour 0 = 30/12/1899 (prend en compte le faux 29/02/1900 d'Excel pour les dates ≥ 01/03/1900).
    final base = _date1904 ? DateTime.utc(1904, 1, 1) : (serial < 61 ? DateTime.utc(1899, 12, 31) : DateTime.utc(1899, 12, 30));
    final days = serial.floor();
    final secs = ((serial - days) * 86400).round();
    final dt = base.add(Duration(days: days, seconds: secs));
    String two(int x) => x.toString().padLeft(2, '0');
    final date = '${dt.year}-${two(dt.month)}-${two(dt.day)}';
    return secs == 0 ? date : '$date ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}

int _colIndex(String ref) {
  var c = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    c = c * 26 + (ch - 64);
  }
  return c - 1;
}

/// Nombre sans « .0 » final ; notation décimale (jusqu'à 15 chiffres significatifs).
String _number(double x) {
  if (x == x.roundToDouble() && x.abs() < 1e15) return x.toInt().toString();
  var s = x.toStringAsPrecision(15);
  if (s.contains('e')) return x.toString();
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Formats numériques intégrés d'Excel qui désignent des dates ou heures.
const _builtinDateFormats = {14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47};

/// Classeur à partir de ses fichiers internes ([parts] : chemin dans l'archive → contenu texte).
XlsxWorkbook readXlsxParts(Map<String, String> parts) {
  final wb = parts['xl/workbook.xml'];
  if (wb == null) throw FormatException(tr('Fichier Excel invalide (xl/workbook.xml absent).', 'Invalid Excel file (xl/workbook.xml missing).'));
  final rels = parts['xl/_rels/workbook.xml.rels'] ?? '';
  final relTarget = {
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) _attr(m[0]!, 'Id') ?? '': _attr(m[0]!, 'Target') ?? ''
  };
  final names = <String>[];
  final paths = <String, String>{};
  var i = 0;
  for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wb)) {
    i++;
    final tag = m[0]!;
    final n = _attr(tag, 'name') ?? 'Feuille$i';
    final rid = _attr(tag, 'r:id') ?? '';
    var target = relTarget[rid] ?? 'worksheets/sheet$i.xml';
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    names.add(n);
    paths[n] = target;
  }
  final date1904 = RegExp(r'<workbookPr\b[^>]*date1904="(1|true)"').hasMatch(wb);
  final sst = parts['xl/sharedStrings.xml'] ?? '';
  final shared = [for (final m in RegExp(r'<si>([\s\S]*?)</si>').allMatches(sst)) _texts(m[1]!)];
  final styles = parts['xl/styles.xml'] ?? '';
  final customDate = <int>{};
  for (final m in RegExp(r'<numFmt\b[^>]*>').allMatches(styles)) {
    final id = int.tryParse(_attr(m[0]!, 'numFmtId') ?? '');
    final code = (_attr(m[0]!, 'formatCode') ?? '').replaceAll(RegExp(r'\[[^\]]*\]|"[^"]*"'), '').toLowerCase();
    if (id != null && RegExp(r'[dy]').hasMatch(code)) customDate.add(id);
  }
  final xfs = RegExp(r'<cellXfs\b[^>]*>([\s\S]*?)</cellXfs>').firstMatch(styles)?[1] ?? '';
  final dateStyles = <int>{};
  var k = 0;
  for (final m in RegExp(r'<xf\b[^>]*>').allMatches(xfs)) {
    final id = int.tryParse(_attr(m[0]!, 'numFmtId') ?? '') ?? 0;
    if (_builtinDateFormats.contains(id) || customDate.contains(id)) dateStyles.add(k);
    k++;
  }
  return XlsxWorkbook._(names, paths, parts, shared, dateStyles, date1904);
}
