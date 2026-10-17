/// Construction de la matrice de plan d'un modèle de régression : codage des
/// variables qualitatives (indicatrices contre une référence explicite),
/// transformations, interactions, observations incluses et exclues.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../model/result.dart';

enum TermTransform { none, log, log2, center, perUnit, rcs3, rcs4, rcs5 }

/// Nombre de nœuds d'une spline cubique restreinte (0 si la transformation n'en est pas une).
int splineKnotCount(TermTransform t) => switch (t) { TermTransform.rcs3 => 3, TermTransform.rcs4 => 4, TermTransform.rcs5 => 5, _ => 0 };

/// Nœuds d'une spline cubique restreinte, comme Hmisc::rcspline.eval (rms::rcs) : quantiles (type 7) aux proportions
/// régulières entre 0,05 et 0,95 (0,10 et 0,90 pour 3 nœuds) ; valeurs extrêmes très fréquentes (≥ 5 %) remplacées par
/// la valeur suivante ; avec moins de 100 valeurs, nœuds extrêmes = 5ᵉ plus petite et 5ᵉ plus grande valeur.
List<double> rcsKnots(List<double> values, int nk) {
  var xx = [...values]..sort();
  final n = xx.length;
  if (n < 6) throw StatInputError('spline_few', tr('Moins de 6 valeurs : spline impossible.', 'Fewer than 6 values: spline impossible.'));
  final xu = xx.toSet().toList()..sort();
  List<double> knots;
  if (xu.length - 2 <= nk) {
    knots = xu.sublist(1, xu.length - 1);
  } else {
    var outer = nk > 3 ? 0.05 : 0.1;
    if (nk > 6) outer = 0.025;
    var nke = nk;
    final first = <double>[], last = <double>[];
    var overFirst = false, overLast = false;
    final freq = <double, int>{};
    for (final v in xx) {
      freq[v] = (freq[v] ?? 0) + 1;
    }
    final inner = [for (var k = 1; k < xu.length - 1; k++) freq[xu[k]]! / n];
    if (inner.reduce(math.max) < 0.05) {
      if (freq[xu.first]! / n >= 0.05) {
        final f = xx.firstWhere((v) => v > xu.first);
        first.add(f);
        xx = [for (final v in xx) if (v > f) v];
        nke--;
        overFirst = true;
      }
      if (freq[xu.last]! / n >= 0.05) {
        final l = xx.lastWhere((v) => v < xu.last);
        last.add(l);
        xx = [for (final v in xx) if (v < l) v];
        nke--;
        overLast = true;
      }
    }
    final xs = xx; // trié
    double q(double p) {
      final h = (xs.length - 1) * p, lo = h.floor(), hi = h.ceil();
      return xs[lo] + (h - lo) * (xs[hi] - xs[lo]);
    }

    if (nke == 1) {
      knots = [q(0.5)];
    } else {
      final ps = nke == 2 ? [for (var k = 0; k < nke; k++) 0.5 + k * (0.5 - outer) / (nke - 1)] : [for (var k = 0; k < nke; k++) outer + k * (1 - 2 * outer) / (nke - 1)];
      knots = [for (final p in ps) q(p)];
      if (knots.toSet().length < math.min(nke, 3)) {
        throw StatInputError('spline_ties', tr('Trop de valeurs identiques pour placer $nk nœuds distincts : réduire le nombre de nœuds.', 'Too many tied values to place $nk distinct knots: reduce the number of knots.'));
      }
      if (xs.length < 100) {
        if (!overFirst) knots[0] = xs[4];
        if (!overLast) knots[nke - 1] = xs[xs.length - 5];
      }
    }
    knots = [...first, ...knots, ...last];
  }
  knots = knots.toSet().toList()..sort();
  if (knots.length < 3) throw StatInputError('spline_ties', tr('Moins de 3 nœuds distincts : spline impossible.', 'Fewer than 3 distinct knots: spline impossible.'));
  return knots;
}

/// Base de la spline cubique restreinte (normalisation de rms : division par (t_k − t_1)^(2/3) avant le cube) :
/// x, puis k − 2 termes non linéaires.
List<double> rcsBasis(double x, List<double> t) {
  final k = t.length, kd = math.pow(t[k - 1] - t[0], 2 / 3).toDouble();
  double c(double u) => u > 0 ? u * u * u : 0;
  return [
    x,
    for (var j = 0; j < k - 2; j++)
      c((x - t[j]) / kd) + ((t[k - 2] - t[j]) * c((x - t[k - 1]) / kd) - (t[k - 1] - t[j]) * c((x - t[k - 2]) / kd)) / (t[k - 1] - t[k - 2])
  ];
}

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

  /// Spline : nœuds figés (équation réappliquée à d'autres données) ; null = calculés sur les données.
  final List<double>? knots;

  const TermSpec(this.variable,
      {this.categorical = false, this.reference, this.transform = TermTransform.none, this.unitStep, this.centerAt, this.knots});

  /// Même terme avec les nœuds de spline utilisés par [d] (pour réappliquer une équation sans les recalculer).
  TermSpec withKnotsFrom(DesignMatrix d) => d.splineKnots[variable] == null || knots != null
      ? this
      : TermSpec(variable, categorical: categorical, reference: reference, transform: transform, unitStep: unitStep, centerAt: centerAt, knots: d.splineKnots[variable]);

  Map<String, Object?> toJson() => {
        'variable': variable,
        'categorical': categorical,
        'reference': reference,
        'transform': transform.name,
        'unitStep': unitStep,
        'centerAt': centerAt,
        if (knots != null) 'knots': knots,
      };

  factory TermSpec.fromJson(Map<String, Object?> j) => TermSpec(j['variable'] as String,
      categorical: (j['categorical'] as bool?) ?? false,
      reference: j['reference'] as String?,
      transform: TermTransform.values.byName((j['transform'] as String?) ?? 'none'),
      unitStep: (j['unitStep'] as num?)?.toDouble(),
      centerAt: (j['centerAt'] as num?)?.toDouble(),
      knots: (j['knots'] as List?)?.map((e) => (e as num).toDouble()).toList());
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
        '${t.transform == TermTransform.log ? "log(${t.variable})" : t.transform == TermTransform.log2 ? "log2(${t.variable})" : splineKnotCount(t.transform) > 0 ? "rcs(${t.variable}, ${splineKnotCount(t.transform)})" : t.variable}'
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

  /// Splines cubiques restreintes : variable → nœuds ; colonnes = [splineColumns].
  final Map<String, List<double>> splineKnots;
  final Map<String, List<int>> splineColumns;

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
      this.eventLevel,
      this.splineKnots = const {},
      this.splineColumns = const {}});

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
        if (splineKnots.isNotEmpty) 'splineKnots': splineKnots,
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
  final splineKnots = <String, List<double>>{};
  final splineColumns = <String, List<int>>{};

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
    } else if (splineKnotCount(t.transform) > 0) {
      final raw = ds.numeric(t.variable);
      final knots = t.knots ?? rcsKnots([for (var i = 0; i < ds.rowCount; i++) if (!excludedRows.contains(i) && raw[i] != null && raw[i]!.isFinite) raw[i]!], splineKnotCount(t.transform));
      final idx = <int>[];
      for (var j = 0; j < knots.length - 1; j++) {
        idx.add(cols.length);
        cols.add(j == 0 ? t.variable : '${t.variable}${"'" * j}');
        termOf.add(t.variable);
        getters.add((i) => raw[i] == null ? null : rcsBasis(raw[i]!, knots)[j]);
      }
      termColumns[t.variable] = idx;
      splineKnots[t.variable] = knots;
      splineColumns[t.variable] = idx;
      notes.add(tr('${t.variable} : spline cubique restreinte à ${knots.length} nœuds (${knots.map(fmt).join(" ; ")}), ${knots.length - 1} coefficients (${t.variable} puis ${knots.length - 2} terme(s) non linéaire(s) ${[for (var j = 1; j < knots.length - 1; j++) "${t.variable}${"'" * j}"].join(", ")}) ; les coefficients isolés ne s\'interprètent pas : lire la courbe et les tests.',
          '${t.variable}: restricted cubic spline with ${knots.length} knots (${knots.map(fmt).join("; ")}), ${knots.length - 1} coefficients (${t.variable} then ${knots.length - 2} nonlinear term(s) ${[for (var j = 1; j < knots.length - 1; j++) "${t.variable}${"'" * j}"].join(", ")}); individual coefficients are not interpretable: read the curve and the tests.'));
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
        case TermTransform.rcs3:
        case TermTransform.rcs4:
        case TermTransform.rcs5:
          g = (i) => raw[i];
      }
      termColumns[t.variable] = [cols.length];
      cols.add(name);
      termOf.add(t.variable);
      getters.add(g);
    }
  }
  for (final (a, b) in f.interactions) {
    if (splineKnots.containsKey(a) || splineKnots.containsKey(b)) {
      throw StatInputError('interaction_spline', tr('Interaction $a × $b : non prise en charge avec une spline ; utiliser la forme linéaire ou stratifier.', 'Interaction $a × $b: not supported with a spline; use the linear form or stratify.'));
    }
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
      eventLevel: eventLevel,
      splineKnots: splineKnots,
      splineColumns: splineColumns);
}
