import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

/// Décompactage minimal d'un zip (répertoire central + deflate brut), pour le test uniquement : l'application utilise le
/// paquet archive.
Map<String, String> unzipText(Uint8List b) {
  final bd = ByteData.sublistView(b);
  var eocd = b.length - 22;
  while (bd.getUint32(eocd, Endian.little) != 0x06054b50) {
    eocd--;
  }
  final n = bd.getUint16(eocd + 10, Endian.little);
  var p = bd.getUint32(eocd + 16, Endian.little);
  final out = <String, String>{};
  for (var i = 0; i < n; i++) {
    final method = bd.getUint16(p + 10, Endian.little), csize = bd.getUint32(p + 20, Endian.little);
    final nl = bd.getUint16(p + 28, Endian.little), el = bd.getUint16(p + 30, Endian.little), cl = bd.getUint16(p + 32, Endian.little);
    final local = bd.getUint32(p + 42, Endian.little);
    final name = utf8.decode(b.sublist(p + 46, p + 46 + nl));
    final lnl = bd.getUint16(local + 26, Endian.little), lel = bd.getUint16(local + 28, Endian.little);
    final data = b.sublist(local + 30 + lnl + lel, local + 30 + lnl + lel + csize);
    if (name.endsWith('.xml') || name.endsWith('.rels')) {
      out[name] = utf8.decode(method == 8 ? ZLibDecoder(raw: true).convert(data) : data);
    }
    p += 46 + nl + el + cl;
  }
  return out;
}

void main() {
  final ref = loadRef('excel');
  final wb = readXlsxParts(unzipText(File('test/reference/exemple_excel.xlsx').readAsBytesSync()));
  final ds = wb.sheet(name: 'patients', source: 'exemple_excel.xlsx');

  test('feuilles et noms de colonnes = readxl', () {
    expect(wb.sheetNames, [for (final s in ref['sheets'] as List) s as String]);
    expect(ds.names, [for (final s in ref['names'] as List) s as String]);
    expect(ds.rowCount, 40);
  });

  test('valeurs de chaque colonne = readxl (dates AAAA-MM-JJ, nombres, booléens, vides, caractères spéciaux)', () {
    final cols = ref['cols'] as Map;
    for (final n in ds.names) {
      final expected = [for (final v in cols[n] as List) v as String?];
      expect([for (var i = 0; i < ds.rowCount; i++) ds.cell(i, n)], expected, reason: n);
    }
    expect(ds.dictionary['date_inclusion']!.type, VarType.date);
  });

  test('dictionnaire : types déclarés, unités, libellés, codes manquants retirés et journalisés, codes remplacés par leurs libellés, ordre des modalités', () {
    final dict = wb.sheet(name: 'dictionnaire');
    final r = applyDataDictionary(ds, dict, timestamp: 't', author: 'test');
    final out = r.dataset;
    expect(r.applied.length, asD(ref['n_dico'])!.round());
    expect(out.dictionary['poids']!.unit, 'kg');
    expect(out.dictionary['age']!.label, 'Âge à l\'inclusion');
    expect(out.dictionary['score']!.type, VarType.ordinal);
    expect(out.dictionary['score']!.order, ['faible', 'moyen', 'fort']);
    expect(out.dictionary['groupe']!.type, VarType.categorical);
    expect(out.dictionary['groupe']!.reference, 'témoin');
    expect(out.dictionary['fumeur']!.declared, isTrue);
    expect(out.numeric('poids').where((v) => v == null).length, asD(ref['poids_missing_after'])!.round());
    expect(r.missingCodesRemoved, 3);
    expect(out.text('groupe'), [for (final v in ref['groupe_labels'] as List) v as String]);
    // Les cellules d'origine sont intactes ; les opérations sont journalisées.
    expect(out.original.where((row) => row[out.names.indexOf('poids')] == '999').length, 3);
    expect(out.corrections.where((c) => c.action == 'set_missing').single.from, '999');
    expect(out.corrections.where((c) => c.action == 'recode').length, 2);
    expect(r.summary().join(' '), contains('3 valeur(s)'));
  });

  test('erreurs : dictionnaire sans colonne « variable », classeur invalide', () {
    expect(() => applyDataDictionary(ds, Dataset(['x'], [['a']])), throwsFormatException);
    expect(() => readXlsxParts(const {}), throwsFormatException);
  });
}
