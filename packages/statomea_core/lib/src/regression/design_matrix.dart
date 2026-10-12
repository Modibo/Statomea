/// Construction de la matrice de plan d'un modèle de régression : codage des
/// variables qualitatives (indicatrices contre une référence explicite),
/// transformations, interactions, observations incluses et exclues.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../model/result.dart';

enum TermTransform { none, log, log2, center, perUnit }

/// Nom de la colonne constante dans la langue courante.
String get interceptName => tr('Constante', 'Intercept');

/// Vrai pour la constante (ou son terme), quelle que soit la langue de calcul.
bool isIntercept(String name) => const {'Constante', 'Intercept', '(Constante)', '(Intercept)'}.contains(name);

/// Nom de colonne exprimé dans la langue courante, quelle que soit la langue
/// dans laquelle il a été produit (équation enregistrée en français puis
/// appliquée en anglais, ou l'inverse).
String localizeColumn(String c) {
  if (c.contains(' × ')) return c.split(' × ').map(localizeColumn).join(' × ');
  if (isIntercept(c)) return interceptName;
  String num(String v) => currentLang == Lang.fr ? v.replaceAll('.', ',') : v.replaceAll(',', '.');
  final centred = RegExp(r'^(.*) \((?:centrée sur|centred at) (.+)\)$').firstMatch(c);
  if (centred != null) {
    final v = num(centred[2]!);
    return tr('${centred[1]} (centrée sur $v)', '${centred[1]} (centred at $v)');
  }
  final perUnit = RegExp(r'^(.*) \((?:par|per) (.+) (?:unités|units)\)$').firstMatch(c);
  if (perUnit != null) {
    final v = num(perUnit[2]!);
    return tr('${perUnit[1]} (par $v unités)', '${perUnit[1]} (per $v units)');
  }
  return c;
}

class TermSpec {
  final String variable;
  final bool categorical;

  /// Catégorie de référence (obligatoire pour une variable qualitative ; si
  /// absente, la première modalité triée est prise ET signalée).
  final String? reference;
  final TermTransform transform;

  /// Pour [TermTransform.perUnit] : coefficient exprimé pour [unitStep] unités
  /// (p. ex. 10 mmHg). Pour [TermTransform.center] : valeur de centrage (moyenne si null).
  final double? unitStep;
  final double? centerAt;

  const TermSpec(this.variable,
      {this.categorical = false, this.reference, this.transform = TermTransform.none, this.unitStep, this.centerAt});

  Map<String, Object?> toJson() => {
        'variable': variable,
        'categorical': categorical,
        'reference': reference,
        'transform': transform.name,
        'unitStep': unitStep,
        'centerAt': centerAt,
      };

  factory TermSpec.fromJson(Map<String, Object?> j) => TermSpec(j['variable'] as String,
      categorical: (j['categorical'] as bool?) ?? false,
      reference: j['reference'] as String?,
      transform: TermTransform.values.byName((j['transform'] as String?) ?? 'none'),
      unitStep: (j['unitStep'] as num?)?.toDouble(),
      centerAt: (j['centerAt'] as num?)?.toDouble());
}

class ModelFormula {
  final String outcome;
  final List<TermSpec> terms;
  final List<(String, String)> interactions;

  /// Pour une issue binaire : modalité considérée comme « événement ».
  final String? eventLevel;

  const ModelFormula(this.outcome, this.terms, {this.interactions = const [], this.eventLevel});

  Map<String, Object?> toJson() => {
        'outcome': outcome,
        'terms': [for (final t in terms) t.toJson()],
        'interactions': [for (final i in interactions) [i.$1, i.$2]],
        'eventLevel': eventLevel,
      };

  factory ModelFormula.fromJson(Map<String, Object?> j) => ModelFormula(j['outcome'] as String,
      [for (final t in j['terms'] as List) TermSpec.fromJson((t as Map).cast<String, Object?>())],
      interactions: [for (final i in (j['interactions'] as List? ?? [])) ((i as List)[0] as String, i[1] as String)],
      eventLevel: j['eventLevel'] as String?);

  String describe() {
    final parts = [
      for (final t in terms)
        '${t.transform == TermTransform.log ? "log(${t.variable})" : t.transform == TermTransform.log2 ? "log2(${t.variable})" : t.variable}'
            '${t.categorical ? tr(" [réf. ${t.reference ?? "?"}]", " [ref. ${t.reference ?? "?"}]") : ""}',
      for (final i in interactions) '${i.$1} × ${i.$2}',
    ];
    return '$outcome ~ ${parts.join(" + ")}';
  }
}

/// Matrice de plan prête pour l'ajustement.
class DesignMatrix {
  final List<String> columns; // 'Constante', puis termes
  final List<String> termOfColumn; // terme d'origine de chaque colonne (pour GVIF)
  final List<List<double>> x;
  final List<double> y;
  final List<int> rows; // index des lignes utilisées dans le jeu de données
  final Map<String, int> excludedBy; // variable → nb de lignes exclues pour valeur manquante
  final int excludedByCorrection;
  final List<String> codingNotes;
  final List<Alert> alerts;
  final String? eventLevel;
  final String formula;

  DesignMatrix(
      {required this.columns,
      required this.termOfColumn,
      required this.x,
      required this.y,
      required this.rows,
      required this.excludedBy,
      required this.excludedByCorrection,
      required this.codingNotes,
      required this.alerts,
      required this.formula,
      this.eventLevel});

  int get n => y.length;
  int get p => columns.length;

  Map<String, Object?> describe() => {
        'formula': formula,
        'columns': columns,
        'n': n,
        'excludedMissing': excludedBy,
        'excludedByCorrection': excludedByCorrection,
        'coding': codingNotes,
        if (eventLevel != null) 'eventLevel': eventLevel,
      };
}

/// Construit la matrice de plan. [binaryOutcome] : l'issue est codée 1 pour
/// [ModelFormula.eventLevel] (ou pour la valeur numérique 1), 0 sinon.
DesignMatrix buildDesign(Dataset ds, ModelFormula f, {bool binaryOutcome = false}) {
  final alerts = <Alert>[];
  final notes = <String>[];
  final excludedBy = <String, int>{};
  final excludedRows = ds.excludedRows;

  // Issue
  List<double?> yRaw;
  String? eventLevel;
  if (binaryOutcome) {
    final lv = ds.levels(f.outcome);
    if (lv.length != 2) {
      throw StatInputError('outcome_not_binary',
          tr("L'issue « ${f.outcome} » a ${lv.length} modalité(s) observée(s) ; une régression logistique ou de Poisson pour issue binaire en exige exactement 2.",
              'The outcome "${f.outcome}" has ${lv.length} observed level(s); a logistic or Poisson regression for a binary outcome requires exactly 2.'));
    }
    eventLevel = f.eventLevel ?? (lv.contains('1') ? '1' : lv.last);
    if (!lv.contains(eventLevel)) {
      throw StatInputError('event_level', tr('Modalité « $eventLevel » absente de « ${f.outcome} ».', 'Level "$eventLevel" not found in "${f.outcome}".'));
    }
    if (f.eventLevel == null) {
      alerts.add(Alert('event_level_default', Severity.caution,
          tr('Modalité « événement » non précisée pour « ${f.outcome} » : « $eventLevel » retenue.', 'Event level not specified for "${f.outcome}": "$eventLevel" used.'),
          suggestion: tr("Déclarer explicitement la modalité qui correspond à l'événement.", 'Explicitly declare the level that corresponds to the event.')));
    }
    notes.add(tr('Issue ${f.outcome} : 1 = « $eventLevel », 0 = « ${lv.firstWhere((l) => l != eventLevel)} ».', 'Outcome ${f.outcome}: 1 = "$eventLevel", 0 = "${lv.firstWhere((l) => l != eventLevel)}".'));
    yRaw = [for (final v in ds.text(f.outcome)) v == null ? null : (v == eventLevel ? 1.0 : 0.0)];
  } else {
    yRaw = ds.numeric(f.outcome);
  }

  // Termes : préparation des colonnes.
  final cols = <String>[interceptName];
  final termOf = <String>['($interceptName)'];
  final getters = <double? Function(int)>[(_) => 1.0];
  final termColumns = <String, List<int>>{};

  for (final t in f.terms) {
    if (t.categorical) {
      final lv = ds.levels(t.variable);
      if (lv.length < 2) {
        throw StatInputError('constant_term', tr("La variable « ${t.variable} » n'a qu'une modalité.", 'The variable "${t.variable}" has only one level.'));
      }
      var ref = t.reference;
      if (ref == null) {
        ref = lv.first;
        alerts.add(Alert('reference_default', Severity.caution,
            tr('Catégorie de référence de « ${t.variable} » non définie : « $ref » prise par défaut.', 'Reference category of "${t.variable}" not defined: "$ref" used by default.'),
            suggestion: tr('Choisir une référence ayant un sens clinique et un effectif suffisant.', 'Choose a clinically meaningful reference with a sufficient count.')));
      } else if (!lv.contains(ref)) {
        throw StatInputError('bad_reference', tr('Référence « $ref » absente de « ${t.variable} ».', 'Reference "$ref" not found in "${t.variable}".'));
      }
      final txt = ds.text(t.variable);
      final idx = <int>[];
      for (final l in lv) {
        if (l == ref) continue;
        idx.add(cols.length);
        cols.add('${t.variable} = $l (vs $ref)');
        termOf.add(t.variable);
        getters.add((i) => txt[i] == null ? null : (txt[i] == l ? 1.0 : 0.0));
      }
      termColumns[t.variable] = idx;
      notes.add(tr('${t.variable} : indicatrices pour ${lv.where((l) => l != ref).join(", ")} ; référence « $ref ».', '${t.variable}: indicators for ${lv.where((l) => l != ref).join(", ")}; reference "$ref".'));
    } else {
      final raw = ds.numeric(t.variable);
      double? Function(int) g;
      String name = t.variable;
      switch (t.transform) {
        case TermTransform.log:
        case TermTransform.log2:
          final bad = raw.where((v) => v != null && v <= 0).length;
          if (bad > 0) {
            throw StatInputError('log_nonpositive',
                tr('$bad valeur(s) ≤ 0 dans « ${t.variable} » : transformation logarithmique impossible.', '$bad value(s) ≤ 0 in "${t.variable}": log transformation impossible.'));
          }
          final base = t.transform == TermTransform.log ? math.e : 2.0;
          g = (i) => raw[i] == null ? null : math.log(raw[i]!) / math.log(base);
          name = t.transform == TermTransform.log ? 'log(${t.variable})' : 'log2(${t.variable})';
          notes.add(tr('$name : coefficient par multiplication de ${t.variable} par ${t.transform == TermTransform.log ? "e" : "2"}.', '$name: coefficient per multiplication of ${t.variable} by ${t.transform == TermTransform.log ? "e" : "2"}.'));
        case TermTransform.center:
          final vals = [for (final v in raw) ?v];
          final c = t.centerAt ?? vals.fold(0.0, (a, b) => a + b) / vals.length;
          g = (i) => raw[i] == null ? null : raw[i]! - c;
          name = tr('${t.variable} (centrée sur ${fmt(c)})', '${t.variable} (centred at ${fmt(c)})');
          notes.add(tr('$name : la constante correspond à ${t.variable} = ${fmt(c)}.', '$name: the intercept corresponds to ${t.variable} = ${fmt(c)}.'));
        case TermTransform.perUnit:
          final k = t.unitStep ?? 1;
          g = (i) => raw[i] == null ? null : raw[i]! / k;
          name = tr('${t.variable} (par ${fmt(k)} unités)', '${t.variable} (per ${fmt(k)} units)');
          notes.add(tr('$name : coefficient pour une augmentation de ${fmt(k)} unités.', '$name: coefficient for an increase of ${fmt(k)} units.'));
        case TermTransform.none:
          g = (i) => raw[i];
      }
      termColumns[t.variable] = [cols.length];
      cols.add(name);
      termOf.add(t.variable);
      getters.add(g);
    }
  }
  for (final (a, b) in f.interactions) {
    final ia = termColumns[a], ib = termColumns[b];
    if (ia == null || ib == null) {
      throw StatInputError('interaction_term',
          tr('Interaction $a × $b : les deux variables doivent figurer comme effets principaux.', 'Interaction $a × $b: both variables must be included as main effects.'));
    }
    final idx = <int>[];
    for (final ca in ia) {
      for (final cb in ib) {
        final ga = getters[ca], gb = getters[cb];
        idx.add(cols.length);
        cols.add('${cols[ca]} × ${cols[cb]}');
        termOf.add('$a × $b');
        getters.add((i) {
          final u = ga(i), v = gb(i);
          return u == null || v == null ? null : u * v;
        });
      }
    }
    notes.add(tr("Interaction $a × $b : les effets principaux s'interprètent quand l'autre variable vaut sa référence ou 0.", 'Interaction $a × $b: main effects are interpreted when the other variable is at its reference or 0.'));
  }

  // Lignes complètes
  final x = <List<double>>[];
  final y = <double>[];
  final used = <int>[];
  var byCorr = 0;
  for (var i = 0; i < ds.rowCount; i++) {
    if (excludedRows.contains(i)) {
      byCorr++;
      continue;
    }
    var ok = true;
    if (yRaw[i] == null) {
      excludedBy[f.outcome] = (excludedBy[f.outcome] ?? 0) + 1;
      ok = false;
    }
    final row = <double>[];
    for (var j = 0; j < getters.length; j++) {
      final v = getters[j](i);
      if (v == null || !v.isFinite) {
        final name = termOf[j];
        if (ok) excludedBy[name] = (excludedBy[name] ?? 0) + 1;
        ok = false;
        break;
      }
      row.add(v);
    }
    if (!ok) continue;
    x.add(row);
    y.add(yRaw[i]!);
    used.add(i);
  }
  final nMissing = excludedBy.values.fold<int>(0, (a, b) => a + b);
  if (nMissing > 0) {
    final share = nMissing / (ds.rowCount - byCorr);
    alerts.add(Alert('complete_case', share > 0.1 ? Severity.serious : Severity.caution,
        tr('Analyse en cas complets : $nMissing ligne(s) exclue(s) (${fmtPct(share)}) pour valeur manquante (${excludedBy.entries.map((e) => "${e.key} : ${e.value}").join(" ; ")}).',
            'Complete-case analysis: $nMissing row(s) excluded (${fmtPct(share)}) for missing values (${excludedBy.entries.map((e) => "${e.key}: ${e.value}").join("; ")}).'),
        suggestion: share > 0.1
            ? tr("Plus de 10 % d'exclusions : un biais est possible si les données ne sont pas manquantes complètement au hasard ; envisager l'imputation multiple (option des ateliers).",
                'More than 10% excluded: bias is possible if data are not missing completely at random; consider multiple imputation (workshop option).')
            : tr('Comparer les caractéristiques des observations exclues et incluses.', 'Compare the characteristics of excluded and included observations.')));
  }
  if (x.length <= cols.length) {
    throw StatInputError('too_few_rows',
        tr('Seulement ${x.length} observations complètes pour ${cols.length} paramètres : modèle non estimable.', 'Only ${x.length} complete observations for ${cols.length} parameters: model not estimable.'));
  }
  return DesignMatrix(
      columns: cols,
      termOfColumn: termOf,
      x: x,
      y: y,
      rows: used,
      excludedBy: excludedBy,
      excludedByCorrection: byCorr,
      codingNotes: notes,
      alerts: alerts,
      formula: f.describe(),
      eventLevel: eventLevel);
}
