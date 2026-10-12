/// Lecture de fichiers CSV (RFC 4180 + usages français : séparateur « ; »,
/// virgule décimale). Détecte le séparateur, retire l'indicateur d'ordre des
/// octets, gère les guillemets et les retours à la ligne dans les champs.
library;

import '../i18n.dart';
import 'dataset.dart';

class CsvParseResult {
  final Dataset dataset;
  final String delimiter;
  final List<String> warnings;
  CsvParseResult(this.dataset, this.delimiter, this.warnings);
}

String detectDelimiter(String text) {
  final firstLines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(5).toList();
  var best = ',';
  var bestScore = -1.0;
  for (final d in [';', ',', '\t', '|']) {
    final counts = [for (final l in firstLines) _countOutsideQuotes(l, d)];
    if (counts.isEmpty || counts.first == 0) continue;
    final consistent = counts.every((c) => c == counts.first);
    final score = counts.first + (consistent ? 100 : 0);
    if (score > bestScore) {
      bestScore = score.toDouble();
      best = d;
    }
  }
  return best;
}

int _countOutsideQuotes(String line, String d) {
  var inQ = false, n = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQ = !inQ;
    if (!inQ && c == d) n++;
  }
  return n;
}

List<List<String>> parseCsvRows(String text, String delimiter) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQ = false;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (inQ) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQ = true;
    } else if (c == delimiter) {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n' || c == '\r') {
      row.add(field.toString());
      field = StringBuffer();
      rows.add(row);
      row = <String>[];
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return [for (final r in rows) if (!(r.length == 1 && r.first.trim().isEmpty)) r];
}

/// Analyse un texte CSV en jeu de données. Les cellules sont conservées
/// telles quelles (texte), seuls les espaces de bord et l'indicateur BOM
/// sont retirés ; les incohérences sont signalées, pas corrigées.
CsvParseResult parseCsv(String text, {String? delimiter, String source = 'import CSV'}) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final d = delimiter ?? detectDelimiter(text);
  final rows = parseCsvRows(text, d);
  if (rows.isEmpty) throw FormatException(tr('Fichier vide.', 'Empty file.'));
  final warnings = <String>[];
  final header = [for (final h in rows.first) h.trim()];
  final names = <String>[];
  for (var j = 0; j < header.length; j++) {
    var h = header[j].isEmpty ? 'V${j + 1}' : header[j];
    if (header[j].isEmpty) warnings.add(tr('Colonne ${j + 1} sans nom : nommée « $h ».', 'Column ${j + 1} has no name: named "$h".'));
    var k = 2;
    final base = h;
    while (names.contains(h)) {
      h = '${base}_$k';
      k++;
    }
    if (h != base) warnings.add(tr('Nom de colonne en double « $base » : renommé « $h ».', 'Duplicate column name "$base": renamed "$h".'));
    names.add(h);
  }
  final data = <List<String?>>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.length != names.length) {
      warnings.add(tr('Ligne ${r + 1} : ${row.length} champ(s) au lieu de ${names.length} (${row.length < names.length ? "complétée par des manquants" : "champs excédentaires ignorés"}).',
          'Row ${r + 1}: ${row.length} field(s) instead of ${names.length} (${row.length < names.length ? "padded with missing values" : "extra fields ignored"}).'));
    }
    data.add([for (var j = 0; j < names.length; j++) j < row.length ? row[j].trim() : null]);
  }
  return CsvParseResult(Dataset(names, data, source: source), d, warnings);
}

/// Sérialisation CSV (séparateur « ; » par défaut pour les tableurs français).
String toCsv(List<String> header, List<List<String>> rows, {String delimiter = ';'}) {
  String q(String s) =>
      (s.contains(delimiter) || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer()..writeln(header.map(q).join(delimiter));
  for (final r in rows) {
    b.writeln(r.map(q).join(delimiter));
  }
  return b.toString();
}
