/// Statistiques descriptives d'une variable quantitative ou qualitative.
library;

import 'dart:math' as math;

import '../inference/common.dart';
import '../math/distributions.dart';
import '../i18n.dart';
import '../model/result.dart';

double mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;

/// Variance non biaisée (dénominateur n − 1), algorithme en deux passes.
double variance(List<double> x) {
  if (x.length < 2) return double.nan;
  final m = mean(x);
  var s = 0.0, c = 0.0;
  for (final v in x) {
    s += (v - m) * (v - m);
    c += v - m;
  }
  return (s - c * c / x.length) / (x.length - 1);
}

double sd(List<double> x) => math.sqrt(variance(x));

/// Quantile empirique de type 7 (défaut de R et des tableurs).
double quantile(List<double> sorted, double p) {
  if (sorted.isEmpty) return double.nan;
  final h = (sorted.length - 1) * p;
  final lo = h.floor();
  final hi = h.ceil();
  return sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo]);
}

double median(List<double> x) => quantile([...x]..sort(), 0.5);

/// Rangs moyens (gestion des ex aequo), plus la taille de chaque groupe d'ex aequo.
({List<double> ranks, List<int> tieSizes}) rankWithTies(List<double> x) {
  final idx = List<int>.generate(x.length, (i) => i)..sort((a, b) => x[a].compareTo(x[b]));
  final ranks = List<double>.filled(x.length, 0);
  final ties = <int>[];
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && x[idx[j + 1]] == x[idx[i]]) {
      j++;
    }
    final r = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      ranks[idx[k]] = r;
    }
    if (j > i) ties.add(j - i + 1);
    i = j + 1;
  }
  return (ranks: ranks, tieSizes: ties);
}

class NumericSummary {
  final int n, missing;
  final double mean, sd, median, q1, q3, min, max, skewness;
  final double ciLow, ciHigh;
  NumericSummary(this.n, this.missing, this.mean, this.sd, this.median, this.q1, this.q3,
      this.min, this.max, this.skewness, this.ciLow, this.ciHigh);
}

NumericSummary summarize(List<double?> raw, {double level = 0.95}) {
  final x = finiteValues(raw);
  final missing = raw.length - x.length;
  if (x.isEmpty) {
    throw StatInputError('no_data', tr('Aucune valeur numérique exploitable.', 'No usable numeric value.'));
  }
  final s = [...x]..sort();
  final m = mean(x);
  final dev = x.length > 1 ? sd(x) : double.nan;
  double skew = double.nan;
  if (x.length > 2 && dev > 0) {
    final n = x.length;
    final m3 = x.fold(0.0, (a, v) => a + math.pow(v - m, 3)) / n;
    final m2 = x.fold(0.0, (a, v) => a + (v - m) * (v - m)) / n;
    // Coefficient d'asymétrie ajusté (type 2, comme SAS/SPSS).
    skew = (m3 / math.pow(m2, 1.5)) * math.sqrt(n * (n - 1.0)) / (n - 2);
  }
  var lo = double.nan, hi = double.nan;
  if (x.length > 1) {
    final t = tQuantile(1 - (1 - level) / 2, x.length - 1.0);
    lo = m - t * dev / math.sqrt(x.length);
    hi = m + t * dev / math.sqrt(x.length);
  }
  return NumericSummary(x.length, missing, m, dev, quantile(s, 0.5), quantile(s, 0.25),
      quantile(s, 0.75), s.first, s.last, skew, lo, hi);
}

/// Description complète d'une variable quantitative, avec IC de la moyenne.
AnalysisResult describeNumeric(List<double?> raw, {String variable = 'variable', String unit = '', double level = 0.95}) {
  final s = summarize(raw, level: level);
  final alerts = <Alert>[];
  final checks = <Check>[];
  if (s.missing > 0) {
    alerts.add(Alert('missing_values', Severity.caution,
        tr('${s.missing} valeur(s) manquante(s) sur ${s.n + s.missing} (${fmtPct(s.missing / (s.n + s.missing))}) exclue(s) du calcul.',
            '${s.missing} missing value(s) out of ${s.n + s.missing} (${fmtPct(s.missing / (s.n + s.missing))}) excluded from the calculation.'),
        suggestion: tr('Décrire le mécanisme probable des données manquantes et vérifier que les observations exclues ne diffèrent pas des incluses.',
            'Describe the likely missing-data mechanism and check that excluded observations do not differ from included ones.')));
  }
  final skewed = s.skewness.isFinite && s.skewness.abs() > 1;
  checks.add(Check(
      'symmetry',
      tr('Distribution approximativement symétrique (pour lire moyenne ± ÉT)', 'Approximately symmetric distribution (to report mean ± SD)'),
      s.skewness.isNaN ? CheckStatus.notAssessed : (skewed ? CheckStatus.warning : CheckStatus.ok),
      tr('Asymétrie = ${fmt(s.skewness)}. ${skewed ? "Distribution asymétrique : préférer médiane [Q1–Q3]." : "Moyenne et médiane proches."}',
          'Skewness = ${fmt(s.skewness)}. ${skewed ? "Skewed distribution: prefer median [Q1–Q3]." : "Mean and median are close."}')));
  if (s.n < 2) {
    alerts.add(Alert('n_too_small', Severity.serious,
        tr('Une seule observation : aucune mesure de dispersion ni IC calculable.', 'A single observation: no dispersion measure or CI can be computed.')));
  }
  final u = unit.isEmpty ? '' : ' $unit';
  return AnalysisResult(
    methodId: 'describe_numeric',
    methodName: tr('Statistiques descriptives (variable quantitative)', 'Descriptive statistics (quantitative variable)'),
    inputs: {'variable': variable, 'n': s.n, 'missing': s.missing, 'unit': unit, 'level': level},
    formula: tr('moyenne = Σx/n ; ÉT = √[Σ(x − x̄)²/(n − 1)] ; IC de la moyenne = x̄ ± t(1−α/2 ; n−1)·ÉT/√n ; quantiles de type 7.',
        'mean = Σx/n; SD = √[Σ(x − x̄)²/(n − 1)]; CI of the mean = x̄ ± t(1−α/2; n−1)·SD/√n; type 7 quantiles.'),
    estimates: [
      Estimate(tr('Moyenne', 'Mean'), s.mean, lower: s.ciLow, upper: s.ciHigh, level: level),
      Estimate(tr('Écart-type', 'Standard deviation'), s.sd),
      Estimate(tr('Médiane', 'Median'), s.median),
      Estimate(tr('1er quartile', '1st quartile'), s.q1),
      Estimate(tr('3e quartile', '3rd quartile'), s.q3),
      Estimate('Minimum', s.min),
      Estimate('Maximum', s.max),
    ],
    statistics: {'n': s.n.toDouble(), 'missing': s.missing.toDouble(), 'skewness': s.skewness},
    checks: checks,
    alerts: alerts,
    tables: [
      ResultTable(tr('Résumé de $variable', 'Summary of $variable'), [
        'n',
        tr('Manquants', 'Missing'),
        tr('Moyenne (ÉT)', 'Mean (SD)'),
        tr('Médiane [Q1–Q3]', 'Median [Q1–Q3]'),
        'Min–Max'
      ], [
        ['${s.n}', '${s.missing}', '${fmt(s.mean)} (${fmt(s.sd)})$u', '${fmt(s.median)} [${fmt(s.q1)}–${fmt(s.q3)}]$u', '${fmt(s.min)}–${fmt(s.max)}$u']
      ])
    ],
    log: [tr('${s.n} valeurs utilisées, ${s.missing} manquantes exclues.', '${s.n} values used, ${s.missing} missing excluded.')],
    interpretation: Interpretation(
      whyThisMethod: tr('Décrire une variable quantitative avant toute comparaison : position, dispersion, forme de la distribution et données manquantes.',
          'Describe a quantitative variable before any comparison: location, spread, shape of the distribution and missing data.'),
      whatItMeans: skewed
          ? tr("La distribution est asymétrique : la médiane (${fmt(s.median)}$u) et l'intervalle interquartile décrivent mieux la valeur typique que la moyenne (${fmt(s.mean)}$u).",
              'The distribution is skewed: the median (${fmt(s.median)}$u) and the interquartile range describe the typical value better than the mean (${fmt(s.mean)}$u).')
          : tr("Valeur moyenne ${fmt(s.mean)}$u (ÉT ${fmt(s.sd)}). L'IC de la moyenne mesure la précision de l'estimation de la moyenne, pas la dispersion des individus.",
              'Mean ${fmt(s.mean)}$u (SD ${fmt(s.sd)}). The CI of the mean measures the precision of the estimated mean, not the spread of individuals.'),
      notJustified: tr(
          "L'IC de la moyenne ne contient pas « 95 % des patients » : c'est l'ÉT (ou les percentiles) qui décrit la variabilité individuelle. Aucune comparaison ni normalité ne peut être déduite de ce seul tableau.",
          'The CI of the mean does not contain "95% of patients": the SD (or percentiles) describes individual variability. No comparison or normality can be inferred from this table alone.'),
    ),
  );
}

/// Effectifs et pourcentages d'une variable qualitative.
AnalysisResult describeCategorical(List<String?> raw, {String variable = 'variable'}) {
  final counts = <String, int>{};
  var missing = 0;
  for (final v in raw) {
    if (v == null || v.trim().isEmpty) {
      missing++;
    } else {
      counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  final n = raw.length - missing;
  if (n == 0) throw StatInputError('no_data', tr('Aucune valeur renseignée.', 'No value provided.'));
  final keys = counts.keys.toList()..sort();
  final alerts = <Alert>[
    if (missing > 0)
      Alert('missing_values', Severity.caution,
          tr('$missing valeur(s) manquante(s) : les pourcentages sont calculés sur $n observations.', '$missing missing value(s): percentages are computed on $n observations.')),
    for (final k in keys)
      if (counts[k]! < 5)
        Alert('sparse_category', Severity.info, tr('Catégorie « $k » : effectif faible (${counts[k]}).', 'Category "$k": small count (${counts[k]}).'),
            suggestion: tr('Envisager un regroupement justifié a priori si elle doit servir de covariable.',
                'Consider grouping, justified a priori, if it is to be used as a covariate.')),
  ];
  return AnalysisResult(
    methodId: 'describe_categorical',
    methodName: tr('Statistiques descriptives (variable qualitative)', 'Descriptive statistics (categorical variable)'),
    inputs: {'variable': variable, 'n': n, 'missing': missing},
    formula: tr('pourcentage = effectif de la catégorie / effectif renseigné.', 'percentage = category count / number of non-missing observations.'),
    estimates: [for (final k in keys) Estimate(k, counts[k]! / n)],
    statistics: {'n': n.toDouble(), 'missing': missing.toDouble()},
    alerts: alerts,
    tables: [
      ResultTable(tr('Répartition de $variable', 'Distribution of $variable'), [tr('Catégorie', 'Category'), tr('Effectif', 'Count'), '%'],
          [for (final k in keys) [k, '${counts[k]}', fmtPct(counts[k]! / n)]])
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Décrire une variable qualitative par ses effectifs et pourcentages.', 'Describe a categorical variable by its counts and percentages.'),
      whatItMeans: tr('Le dénominateur est de $n observations renseignées.', 'The denominator is $n non-missing observations.'),
      notJustified: tr("Un pourcentage sans son dénominateur ni son IC ne permet pas de juger de sa précision ; pour une proportion d'intérêt, utiliser le calcul d'IC.",
          'A percentage without its denominator or CI does not show its precision; for a proportion of interest, use the CI calculation.'),
    ),
  );
}
