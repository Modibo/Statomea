/// Dictionnaire de variables : une ligne par variable (nom, type, unité, bornes plausibles, référence, libellé, codes de
/// valeur manquante, modalités). Appliqué au jeu de données, il déclare les types et métadonnées, et journalise comme
/// corrections le retrait des codes manquants (999, -9…) et le remplacement des codes par leurs libellés (1=témoin…).
library;

import '../i18n.dart';
import 'dataset.dart';

/// Alias reconnus pour les colonnes du dictionnaire (insensibles à la casse et aux accents simples).
const dictionaryColumnAliases = <String, List<String>>{
  'variable': ['variable', 'nom', 'name', 'var', 'colonne'],
  'type': ['type'],
  'unit': ['unite', 'unité', 'unit', 'units'],
  'min': ['min', 'minimum'],
  'max': ['max', 'maximum'],
  'reference': ['reference', 'référence', 'ref'],
  'label': ['libelle', 'libellé', 'label', 'description'],
  'missing': ['manquants', 'codes_manquants', 'valeurs_manquantes', 'missing', 'na'],
  'levels': ['modalites', 'modalités', 'levels', 'codes', 'categories', 'catégories'],
};

VarType? _type(String? s) {
  final t = (s ?? '').trim().toLowerCase();
  if (t.isEmpty) return null;
  if (const ['quantitative', 'quantitatif', 'numérique', 'numerique', 'numeric', 'continue', 'continuous', 'number'].contains(t)) return VarType.numeric;
  if (const ['binaire', 'binary', 'dichotomique'].contains(t)) return VarType.binary;
  if (const ['qualitative', 'qualitatif', 'catégorielle', 'categorielle', 'categorical', 'nominale', 'nominal', 'facteur', 'factor'].contains(t)) return VarType.categorical;
  if (const ['ordinale', 'ordinal', 'ordonnée', 'ordonnee'].contains(t)) return VarType.ordinal;
  if (const ['date', 'datetime'].contains(t)) return VarType.date;
  if (const ['identifiant', 'id', 'identifier', 'clé', 'cle'].contains(t)) return VarType.identifier;
  if (const ['texte', 'text', 'libre', 'string'].contains(t)) return VarType.text;
  return null;
}

class DictionaryReport {
  final Dataset dataset;
  final List<String> applied, notInData, notInDictionary, warnings;
  final int missingCodesRemoved, valuesRecoded;
  const DictionaryReport(this.dataset, this.applied, this.notInData, this.notInDictionary, this.warnings, this.missingCodesRemoved, this.valuesRecoded);

  List<String> summary() => [
        tr('${applied.length} variable(s) décrite(s) par le dictionnaire.', '${applied.length} variable(s) described by the dictionary.'),
        if (missingCodesRemoved > 0)
          tr('$missingCodesRemoved valeur(s) codée(s) comme manquantes retirée(s) (corrections journalisées).', '$missingCodesRemoved value(s) coded as missing removed (logged corrections).'),
        if (valuesRecoded > 0) tr('$valuesRecoded valeur(s) remplacée(s) par leur libellé.', '$valuesRecoded value(s) replaced by their label.'),
        if (notInData.isNotEmpty) tr('Absentes des données : ${notInData.join(', ')}.', 'Not in the data: ${notInData.join(', ')}.'),
        if (notInDictionary.isNotEmpty) tr('Non décrites : ${notInDictionary.join(', ')}.', 'Not described: ${notInDictionary.join(', ')}.'),
        ...warnings,
      ];
}

/// Applique [dictionary] (un jeu de données, une ligne par variable) à [ds]. [timestamp] et [author] sont journalisés.
DictionaryReport applyDataDictionary(Dataset ds, Dataset dictionary, {String timestamp = '', String author = ''}) {
  final cols = <String, String>{};
  for (final e in dictionaryColumnAliases.entries) {
    for (final n in dictionary.names) {
      if (e.value.contains(n.trim().toLowerCase())) {
        cols[e.key] = n;
        break;
      }
    }
  }
  if (!cols.containsKey('variable')) {
    throw FormatException(tr('Dictionnaire : colonne « variable » introuvable (attendu : variable, type, unité, min, max, référence, libellé, manquants, modalités).',
        'Dictionary: "variable" column not found (expected: variable, type, unit, min, max, reference, label, missing, levels).'));
  }
  String? get(int i, String key) {
    final c = cols[key];
    if (c == null) return null;
    final v = dictionary.cell(i, c)?.trim();
    return v == null || v.isEmpty || v == 'NA' ? null : v;
  }

  var out = ds;
  final applied = <String>[], notInData = <String>[], warnings = <String>[];
  var removed = 0, recoded = 0, k = 0;
  for (var i = 0; i < dictionary.rowCount; i++) {
    final name = get(i, 'variable');
    if (name == null) continue;
    if (!ds.names.contains(name)) {
      notInData.add(name);
      continue;
    }
    applied.add(name);
    final v = out.dictionary[name]!;
    final type = _type(get(i, 'type'));
    if (get(i, 'type') != null && type == null) warnings.add(tr('« $name » : type « ${get(i, 'type')} » non reconnu (ignoré).', '"$name": type "${get(i, 'type')}" not recognized (ignored).'));
    if (get(i, 'unit') != null) v.unit = get(i, 'unit')!;
    if (get(i, 'label') != null) v.label = get(i, 'label')!;
    v.min = parseNumber(get(i, 'min')) ?? v.min;
    v.max = parseNumber(get(i, 'max')) ?? v.max;
    // Codes de valeur manquante : retirés par une correction journalisée (cellules d'origine conservées).
    final miss = get(i, 'missing');
    if (miss != null) {
      for (final code in miss.split(RegExp(r'[;,|]')).map((x) => x.trim()).where((x) => x.isNotEmpty)) {
        final rows = [for (var r = 0; r < out.rowCount; r++) if (_same(out.cell(r, name), code)) r];
        if (rows.isEmpty) continue;
        removed += rows.length;
        out = out.applyCorrection(Correction(id: 'dico-${++k}', variable: name, action: 'set_missing', rows: rows, from: code,
            reason: tr('Code de valeur manquante « $code » déclaré dans le dictionnaire.', 'Missing-value code "$code" declared in the dictionary.'), author: author, timestamp: timestamp));
      }
    }
    // Modalités : « 1=témoin;2=traité » (codes → libellés) ou « faible;moyen;fort » (ordre des modalités).
    final lv = get(i, 'levels');
    if (lv != null) {
      final parts = lv.split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (parts.every((p) => p.contains('='))) {
        final order = <String>[];
        for (final p in parts) {
          final code = p.substring(0, p.indexOf('=')).trim(), label = p.substring(p.indexOf('=') + 1).trim();
          order.add(label);
          final rows = [for (var r = 0; r < out.rowCount; r++) if (_same(out.cell(r, name), code)) r];
          if (rows.isEmpty) continue;
          recoded += rows.length;
          out = out.applyCorrection(Correction(id: 'dico-${++k}', variable: name, action: 'recode', rows: rows, from: code, to: label,
              reason: tr('Code « $code » = « $label » (dictionnaire).', 'Code "$code" = "$label" (dictionary).'), author: author, timestamp: timestamp));
        }
        v.order = order;
      } else {
        v.order = parts;
      }
      final unknown = {for (final x in out.text(name)) ?x}.difference(v.order!.toSet());
      if (unknown.isNotEmpty) {
        warnings.add(tr('« $name » : valeur(s) hors des modalités déclarées : ${unknown.take(5).join(', ')}${unknown.length > 5 ? '…' : ''}.',
            '"$name": value(s) outside the declared levels: ${unknown.take(5).join(', ')}${unknown.length > 5 ? '…' : ''}.'));
      }
    }
    if (type != null) {
      v.type = type;
      v.declared = true;
    }
    final ref = get(i, 'reference');
    if (ref != null) {
      if (out.levels(name).contains(ref)) {
        v.reference = ref;
      } else {
        warnings.add(tr('« $name » : référence « $ref » absente des valeurs observées.', '"$name": reference "$ref" not among the observed values.'));
      }
    }
    // Bornes plausibles : signaler les valeurs hors bornes (le contrôle des données les détaille).
    if (v.min != null || v.max != null) {
      final out0 = [for (final x in out.numeric(name)) if (x != null && ((v.min != null && x < v.min!) || (v.max != null && x > v.max!))) x];
      if (out0.isNotEmpty) warnings.add(tr('« $name » : ${out0.length} valeur(s) hors des bornes [${v.min ?? '−∞'} ; ${v.max ?? '+∞'}].', '"$name": ${out0.length} value(s) outside the bounds [${v.min ?? '−∞'}; ${v.max ?? '+∞'}].'));
    }
  }
  final notInDict = [for (final n in ds.names) if (!applied.contains(n)) n];
  return DictionaryReport(out, applied, notInData, notInDict, warnings, removed, recoded);
}

/// Égalité de valeurs, numérique si possible (« 999 » = « 999.0 »).
bool _same(String? a, String b) {
  if (a == null) return false;
  final x = a.trim();
  if (x == b) return true;
  final na = parseNumber(x), nb = parseNumber(b);
  return na != null && nb != null && na == nb;
}
