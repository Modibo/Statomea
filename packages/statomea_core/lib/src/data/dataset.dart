/// Jeu de données tabulaire. Les cellules importées sont conservées sous leur
/// forme texte d'origine et ne sont jamais modifiées : toute correction est
/// une opération journalisée appliquée par [Dataset.applyCorrection], qui
/// renvoie un nouveau jeu de données (cf. data_quality.dart).
library;

import '../i18n.dart';
import 'dart:math' as math;

enum VarType { numeric, binary, categorical, ordinal, date, identifier, text }

String varTypeLabel(VarType t) => switch (t) {
      VarType.numeric => tr('quantitative', 'quantitative'),
      VarType.binary => tr('binaire', 'binary'),
      VarType.categorical => tr('qualitative', 'categorical'),
      VarType.ordinal => tr('ordinale', 'ordinal'),
      VarType.date => 'date',
      VarType.identifier => tr('identifiant', 'identifier'),
      VarType.text => tr('texte libre', 'free text'),
    };

/// Description d'une variable (dictionnaire des données).
class Variable {
  final String name;
  VarType type;
  String unit;
  double? min; // borne plausible
  double? max;
  String? reference; // catégorie de référence
  String label;

  /// Vrai si le type a été déclaré par l'utilisateur (sinon inféré).
  bool declared;

  Variable(this.name,
      {required this.type,
      this.unit = '',
      this.min,
      this.max,
      this.reference,
      this.label = '',
      this.declared = false});

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.name,
        'unit': unit,
        'min': min,
        'max': max,
        'reference': reference,
        'label': label,
        'declared': declared,
      };

  factory Variable.fromJson(Map<String, Object?> j) => Variable(j['name'] as String,
      type: VarType.values.byName(j['type'] as String),
      unit: (j['unit'] as String?) ?? '',
      min: (j['min'] as num?)?.toDouble(),
      max: (j['max'] as num?)?.toDouble(),
      reference: j['reference'] as String?,
      label: (j['label'] as String?) ?? '',
      declared: (j['declared'] as bool?) ?? false);
}

/// Opération de correction journalisée.
class Correction {
  final String id;
  final String variable;
  final String action; // 'set_missing', 'replace', 'exclude_row', 'set_reference', 'recode'
  final List<int> rows; // index de lignes (0-based, dans le jeu importé)
  final String? from;
  final String? to;
  final String reason;
  final String author;
  final String timestamp; // fourni par l'appelant (le moteur n'a pas d'horloge)

  const Correction(
      {required this.id,
      required this.variable,
      required this.action,
      required this.rows,
      this.from,
      this.to,
      required this.reason,
      this.author = '',
      this.timestamp = ''});

  Map<String, Object?> toJson() => {
        'id': id,
        'variable': variable,
        'action': action,
        'rows': rows,
        'from': from,
        'to': to,
        'reason': reason,
        'author': author,
        'timestamp': timestamp,
      };

  factory Correction.fromJson(Map<String, Object?> j) => Correction(
      id: j['id'] as String,
      variable: j['variable'] as String,
      action: j['action'] as String,
      rows: [for (final r in j['rows'] as List) r as int],
      from: j['from'] as String?,
      to: j['to'] as String?,
      reason: j['reason'] as String,
      author: (j['author'] as String?) ?? '',
      timestamp: (j['timestamp'] as String?) ?? '');

  String describe() => switch (action) {
        'set_missing' => tr('$variable : ${rows.length} valeur(s) « $from » mise(s) en manquant — $reason', '$variable: ${rows.length} value(s) "$from" set to missing — $reason'),
        'replace' => tr('$variable : « $from » → « $to » sur ${rows.length} ligne(s) — $reason', '$variable: "$from" → "$to" on ${rows.length} row(s) — $reason'),
        'exclude_row' => tr("${rows.length} ligne(s) exclue(s) de l'analyse — $reason", '${rows.length} row(s) excluded from the analysis — $reason'),
        'recode' => tr('$variable : catégorie « $from » recodée en « $to » — $reason', '$variable: category "$from" recoded as "$to" — $reason'),
        _ => tr('$action sur $variable — $reason', '$action on $variable — $reason'),
      };
}

/// Valeurs textuelles considérées comme manquantes à l'import.
const Set<String> missingTokens = {'', 'na', 'n/a', 'nan', '.', '-', 'nd', 'null', '?', 'manquant', 'missing'};

bool isMissingToken(String? s) => s == null || missingTokens.contains(s.trim().toLowerCase());

/// Lit un nombre en acceptant la virgule décimale. Null si non numérique.
double? parseNumber(String? s) {
  if (isMissingToken(s)) return null;
  var t = s!.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (t.contains(',') && !t.contains('.')) t = t.replaceAll(',', '.');
  return double.tryParse(t);
}

class Dataset {
  final List<String> names;

  /// Cellules importées, jamais modifiées.
  final List<List<String?>> original;
  final Map<String, Variable> dictionary;
  final List<Correction> corrections;

  /// Description de la source (nom de fichier, empreinte), pour l'audit.
  final String source;

  Dataset._(this.names, this.original, this.dictionary, this.corrections, this.source);

  factory Dataset(List<String> names, List<List<String?>> rows,
      {String? source, Map<String, Variable>? dictionary, List<Correction>? corrections}) {
    source ??= tr('saisie manuelle', 'manual entry');
    final dict = dictionary ?? {for (final n in names) n: Variable(n, type: VarType.text)};
    final ds = Dataset._(List.unmodifiable(names),
        List.unmodifiable([for (final r in rows) List<String?>.unmodifiable(r)]), dict, corrections ?? [], source);
    if (dictionary == null) {
      for (final n in names) {
        ds.dictionary[n]!.type = ds.inferType(n);
      }
    }
    return ds;
  }

  /// Construit un jeu de données à partir de colonnes numériques (tests, démonstrations).
  factory Dataset.fromColumns(Map<String, List<Object?>> cols, {String? source}) {
    source ??= tr('données générées', 'generated data');
    final names = cols.keys.toList();
    final n = cols.values.first.length;
    final rows = [
      for (var i = 0; i < n; i++)
        [for (final k in names) cols[k]![i]?.toString()]
    ];
    return Dataset(names, rows, source: source);
  }

  int get rowCount => original.length;

  /// Index des colonnes (les noms sont immuables) : recherche en temps constant, et non linéaire à chaque cellule.
  late final Map<String, int> _colIndex = {for (var i = names.length - 1; i >= 0; i--) names[i]: i};

  int col(String name) {
    final i = _colIndex[name] ?? -1;
    if (i < 0) throw ArgumentError(tr('Variable inconnue : $name', 'Unknown variable: $name'));
    return i;
  }

  /// Lignes exclues par une correction de type « exclude_row ».
  Set<int> get excludedRows => {
        for (final c in corrections)
          if (c.action == 'exclude_row') ...c.rows
      };

  /// Valeur courante d'une cellule après application des corrections.
  String? cell(int row, String name) {
    var v = original[row][col(name)];
    for (final c in corrections) {
      if (c.variable != name || !c.rows.contains(row)) continue;
      switch (c.action) {
        case 'set_missing':
          v = null;
        case 'replace':
        case 'recode':
          v = c.to;
      }
    }
    return v;
  }

  /// Colonne courante (corrigée) sous forme de texte.
  List<String?> text(String name) => [
        for (var i = 0; i < rowCount; i++) isMissingToken(cell(i, name)) ? null : cell(i, name)!.trim()
      ];

  /// Colonne courante sous forme numérique (null si manquant ou non numérique).
  List<double?> numeric(String name) => [for (var i = 0; i < rowCount; i++) parseNumber(cell(i, name))];

  /// Nouveau jeu de données incluant une correction supplémentaire ; les
  /// cellules d'origine restent intactes et la correction est journalisée.
  Dataset applyCorrection(Correction c) =>
      Dataset._(names, original, dictionary, [...corrections, c], source);

  Dataset withoutCorrection(String id) =>
      Dataset._(names, original, dictionary, [for (final c in corrections) if (c.id != id) c], source);

  /// Niveaux observés d'une variable qualitative, triés.
  List<String> levels(String name) {
    final s = <String>{for (final v in text(name)) ?v};
    final l = s.toList();
    final nums = [for (final v in l) parseNumber(v)];
    if (nums.every((x) => x != null)) {
      l.sort((a, b) => parseNumber(a)!.compareTo(parseNumber(b)!));
    } else {
      l.sort();
    }
    return l;
  }

  /// Inférence du type d'une variable à partir de ses valeurs.
  VarType inferType(String name) {
    final vals = [for (final v in text(name)) ?v];
    if (vals.isEmpty) return VarType.text;
    final lower = name.toLowerCase();
    final distinct = vals.toSet();
    final nums = [for (final v in vals) parseNumber(v)];
    final numericShare = nums.where((x) => x != null).length / vals.length;
    if ((lower == 'id' || lower.startsWith('id_') || lower.endsWith('_id') || lower.contains('identifiant')) &&
        distinct.length == vals.length) {
      return VarType.identifier;
    }
    if (distinct.length == 2) return VarType.binary;
    // ≥ 80 % de valeurs numériques : variable quantitative ; les autres
    // valeurs (p. ex. « <0,5 ») seront signalées par le contrôle des données.
    if (numericShare >= 0.8) {
      // Peu de valeurs entières distinctes : probablement un codage qualitatif.
      final allInt = nums.every((x) => x == null || x == x.roundToDouble());
      if (allInt && distinct.length <= 5 && vals.length >= 20) return VarType.categorical;
      return VarType.numeric;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(vals.first) ||
        RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(vals.first)) {
      return VarType.date;
    }
    if (distinct.length <= math.max(10, vals.length ~/ 5)) return VarType.categorical;
    return VarType.text;
  }

  Map<String, Object?> toJson() => {
        'names': names,
        'rows': original,
        'dictionary': {for (final e in dictionary.entries) e.key: e.value.toJson()},
        'corrections': [for (final c in corrections) c.toJson()],
        'source': source,
      };

  factory Dataset.fromJson(Map<String, Object?> j) {
    final names = [for (final n in j['names'] as List) n as String];
    final rows = [
      for (final r in j['rows'] as List) [for (final c in r as List) c as String?]
    ];
    final dict = {
      for (final e in (j['dictionary'] as Map).entries)
        e.key as String: Variable.fromJson((e.value as Map).cast<String, Object?>())
    };
    return Dataset._(names, rows, dict,
        [for (final c in (j['corrections'] as List? ?? [])) Correction.fromJson((c as Map).cast<String, Object?>())],
        (j['source'] as String?) ?? '');
  }
}
