import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart';

/// Ouvre un classeur Excel (.xlsx) : décompactage par le paquet archive, lecture des XML internes par le moteur.
XlsxWorkbook openXlsx(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw FormatException(tr('Fichier Excel illisible (ce n\'est pas un .xlsx ; les anciens .xls ne sont pas pris en charge : les enregistrer en .xlsx ou .csv).',
        'Unreadable Excel file (not an .xlsx; old .xls files are not supported: save them as .xlsx or .csv).'));
  }
  final parts = <String, String>{
    for (final f in zip.files)
      if (f.isFile && (f.name.endsWith('.xml') || f.name.endsWith('.rels'))) f.name: utf8.decode(f.content, allowMalformed: true)
  };
  return readXlsxParts(parts);
}

/// Feuille d'un classeur qui ressemble à un dictionnaire de variables (nom « dictionnaire », « dictionary »…).
String? dictionarySheet(XlsxWorkbook wb) {
  for (final n in wb.sheetNames) {
    final l = n.toLowerCase();
    if (l.contains('diction') || l.contains('codebook') || l.contains('variables')) return n;
  }
  return null;
}

/// Jeu de données d'un fichier CSV ou Excel ([sheet] : feuille choisie, défaut la première qui n'est pas un dictionnaire).
({Dataset dataset, List<String> warnings, XlsxWorkbook? workbook}) datasetFromFile(String name, List<int> bytes, {String? sheet}) {
  if (name.toLowerCase().endsWith('.xlsx')) {
    final wb = openXlsx(bytes);
    final dict = dictionarySheet(wb);
    final sh = sheet ?? wb.sheetNames.firstWhere((s) => s != dict, orElse: () => wb.sheetNames.first);
    return (dataset: wb.sheet(name: sh, source: name), warnings: [tr('Feuille Excel « $sh » importée.', 'Excel sheet "$sh" imported.')], workbook: wb);
  }
  String text;
  final w = <String>[];
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes);
    w.add(tr('Fichier non UTF-8 : lu en Latin-1 (vérifier les accents).', 'File not in UTF-8: read as Latin-1 (check accented characters).'));
  }
  final res = parseCsv(text, source: name);
  return (dataset: res.dataset, warnings: [...w, ...res.warnings], workbook: null);
}
