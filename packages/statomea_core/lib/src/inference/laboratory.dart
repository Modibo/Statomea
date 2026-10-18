/// Laboratoire : intervalles de référence (CLSI EP28-A3c) et fidélité (CLSI EP05-A3, EP15-A3).
///  - intervalle de référence : non paramétrique (quantiles de type 6, IC à 90 % des bornes par rangs binomiaux si
///    n ≥ 120), paramétrique (m ± z·s, IC des bornes), robuste (Horn et Pesce 2005, bipoids) ; valeurs aberrantes
///    par la méthode de Horn (Box-Cox puis barrières de Tukey) ; partition par sous-groupe (Harris et Boyd 1990) ;
///  - fidélité : composantes de la variance par ANOVA d'un plan équilibré (jour, ou jour/série), répétabilité et
///    fidélité intermédiaire (intralaboratoire), ÉT, CV, IC ; vérification d'une fidélité annoncée (EP15).
/// Validé contre validation/r/54_laboratoire.R (referenceIntervals 1.3.0, MASS, VCA 1.4.5).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';

enum ReferenceMethod { nonparametric, parametric, robust }

double _mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;
double _var(List<double> x) {
  final m = _mean(x);
  return x.fold(0.0, (a, v) => a + (v - m) * (v - m)) / (x.length - 1);
}

/// Quantile de type 7 (R), sur données triées.
double _q7(List<double> s, double p) {
  final h = (s.length - 1) * p, lo = h.floor(), hi = h.ceil();
  return s[lo] + (h - lo) * (s[hi] - s[lo]);
}

/// Quantile de type 6 (R, recommandé par la CLSI), sur données triées.
double quantileType6(List<double> s, double p) {
  final n = s.length;
  final h = (n + 1) * p;
  if (h < 1) return s.first;
  if (h >= n) return s.last;
  final j = h.floor(), g = h - j;
  return s[j - 1] + g * (s[j] - s[j - 1]);
}

/// Rangs (1-indexés) de l'IC des bornes non paramétriques : inférieur = max{k : P(X ≤ k) ≤ α} + 1, supérieur =
/// min{k : P(X ≤ k) ≥ 1 − α} + 1, X ~ Bin(n ; (1 − refConf)/2), α = (1 − limitConf)/2 (table de la CLSI EP28).
(int, int) nonparametricCiRanks(int n, {double refConf = 0.95, double limitConf = 0.90}) {
  final p = (1 - refConf) / 2, a = (1 - limitConf) / 2;
  var lo = -1, up = n;
  for (var k = 0; k <= n; k++) {
    final c = binomialCdf(k, n, p);
    if (c <= a) lo = k;
    if (c >= 1 - a) {
      up = k;
      break;
    }
  }
  return (lo + 1, up + 1);
}

/// λ de Box-Cox maximisant la vraisemblance d'un modèle sans covariable, sur la grille −2…2 par 0,1 (MASS::boxcox).
double boxCoxLambda(List<double> y) {
  final n = y.length;
  final logy = [for (final v in y) math.log(v)];
  final ydot = math.exp(logy.fold(0.0, (a, b) => a + b) / n);
  var best = double.negativeInfinity, bestL = 0.0;
  for (var k = 0; k <= 40; k++) {
    final la = -2 + k * 0.1;
    final z = <double>[];
    for (var i = 0; i < n; i++) {
      final yt = la.abs() > 1 / 50
          ? (math.pow(y[i], la) - 1) / la
          : logy[i] * (1 + (la * logy[i]) / 2 * (1 + (la * logy[i]) / 3 * (1 + (la * logy[i]) / 4)));
      z.add(yt / math.pow(ydot, la - 1));
    }
    final m = _mean(z);
    final rss = z.fold(0.0, (a, v) => a + (v - m) * (v - m));
    final ll = -n / 2 * math.log(rss);
    if (ll > best) {
      best = ll;
      bestL = la;
    }
  }
  return bestL;
}

/// Valeurs aberrantes de Horn : Box-Cox puis barrières de Tukey (Q1 − 1,5·EIQ, Q3 + 1,5·EIQ, bornes incluses).
({List<double> outliers, List<double> kept, double lambda}) hornOutliers(List<double> x) {
  if (x.any((v) => v <= 0)) {
    throw StatInputError('ri_positive', tr('La méthode de Horn (Box-Cox) exige des valeurs strictement positives.', 'Horn\'s method (Box-Cox) requires strictly positive values.'));
  }
  final la = boxCoxLambda(x);
  double t(double v) => la == 0 ? math.log(v) : (math.pow(v, la) - 1) / la;
  final tr0 = [for (final v in x) t(v)]..sort();
  final q1 = _q7(tr0, 0.25), q3 = _q7(tr0, 0.75), iqr = q3 - q1;
  final out = <double>[], kept = <double>[];
  for (final v in x) {
    final u = t(v);
    (u <= q1 - 1.5 * iqr || u >= q3 + 1.5 * iqr ? out : kept).add(v);
  }
  return (outliers: out..sort(), kept: kept, lambda: la);
}

/// Intervalle robuste de Horn et Pesce (bipoids, c = 3,7), comme referenceIntervals::robust.
(double, double) robustReferenceInterval(List<double> data, {double refConf = 0.95}) {
  final x = [...data]..sort();
  final n = x.length;
  final med = n.isOdd ? x[n ~/ 2] : (x[n ~/ 2 - 1] + x[n ~/ 2]) / 2;
  final dev = [for (final v in x) (v - med).abs()]..sort();
  final mad = (n.isOdd ? dev[n ~/ 2] : (dev[n ~/ 2 - 1] + dev[n ~/ 2]) / 2) / 0.6745;
  var tbi = med;
  for (var it = 0; it < 1000; it++) {
    var sw = 0.0, sxw = 0.0;
    for (final v in x) {
      var u = (v - tbi) / (3.7 * mad);
      if (u < -1 || u > 1) u = 1;
      final w = (1 - u * u) * (1 - u * u);
      sw += w;
      sxw += v * w;
    }
    final next = sxw / sw;
    if (!next.isFinite || (next - tbi).abs() < 1e-6) break;
    tbi = next;
  }
  double spread(double c, double scale, double center, {bool withN = true}) {
    var num = 0.0, den = 0.0;
    for (final v in x) {
      final u = (v - center) / (c * scale);
      if (u <= -1 || u >= 1) continue;
      final a = 1 - u * u;
      num += a * a * a * a * u * u;
      den += a * (1 - 5 * u * u);
    }
    return c * scale * math.sqrt(((withN ? n : 1) * num) / (den * math.max(1, -1 + den)));
  }

  final sbi205 = spread(205.6, mad, med), sbi37 = spread(3.7, mad, med);
  final st37 = spread(3.7, sbi37, tbi, withN: false);
  final margin = tQuantile(1 - (1 - refConf) / 2, n - 1.0) * math.sqrt(sbi205 * sbi205 + st37 * st37);
  return (tbi - margin, tbi + margin);
}

/// Bornes (et IC éventuels) d'un intervalle de référence pour un échantillon.
({double lower, double upper, List<double>? ci, String? ciNote}) _interval(List<double> x, ReferenceMethod m, double refConf, double limitConf) {
  final n = x.length;
  switch (m) {
    case ReferenceMethod.parametric:
      final mu = _mean(x), s = math.sqrt(_var(x));
      final z = normalQuantile(1 - (1 - refConf) / 2), zl = normalQuantile(1 - (1 - limitConf) / 2);
      final lo = mu - z * s, hi = mu + z * s;
      final se = math.sqrt(s * s / n + z * z * s * s / (2 * n));
      return (lower: lo, upper: hi, ci: [lo - zl * se, lo + zl * se, hi - zl * se, hi + zl * se], ciNote: null);
    case ReferenceMethod.robust:
      final (lo, hi) = robustReferenceInterval(x, refConf: refConf);
      return (lower: lo, upper: hi, ci: null, ciNote: tr('IC des bornes robustes : par bootstrap (non fourni ici).', 'CIs of the robust limits: by bootstrap (not provided here).'));
    case ReferenceMethod.nonparametric:
      final s = [...x]..sort();
      final lo = quantileType6(s, (1 - refConf) / 2), hi = quantileType6(s, 1 - (1 - refConf) / 2);
      if (n < 120 || refConf != 0.95) {
        return (lower: lo, upper: hi, ci: null, ciNote: tr('IC non paramétriques des bornes : au moins 120 valeurs requises (n = $n).', 'Nonparametric CIs of the limits: at least 120 values required (n = $n).'));
      }
      final (r1, r2) = nonparametricCiRanks(n, refConf: refConf, limitConf: limitConf);
      return (lower: lo, upper: hi, ci: [s[r1 - 1], s[r2 - 1], s[n - r2], s[n - r1]], ciNote: null);
  }
}

/// Partition de Harris et Boyd : z, seuil z* = 3·√(n̄/120) et rapport des écarts-types (partition si z > z* ou > 1,5).
({double z, double zStar, double sdRatio, bool partition}) harrisBoyd(List<double> a, List<double> b) {
  final va = _var(a), vb = _var(b);
  final z = (_mean(a) - _mean(b)).abs() / math.sqrt(va / a.length + vb / b.length);
  final zStar = 3 * math.sqrt(((a.length + b.length) / 2) / 120);
  final r = math.max(math.sqrt(va), math.sqrt(vb)) / math.min(math.sqrt(va), math.sqrt(vb));
  return (z: z, zStar: zStar, sdRatio: r, partition: z > zStar || r > 1.5);
}

String _methodLabel(ReferenceMethod m) => switch (m) {
      ReferenceMethod.nonparametric => tr('non paramétrique', 'nonparametric'),
      ReferenceMethod.parametric => tr('paramétrique (loi normale)', 'parametric (normal distribution)'),
      ReferenceMethod.robust => tr('robuste (Horn et Pesce)', 'robust (Horn and Pesce)'),
    };

AnalysisResult referenceInterval(List<double?> raw,
    {ReferenceMethod method = ReferenceMethod.nonparametric,
    bool removeOutliers = false,
    List<String?>? groups,
    String? groupName,
    double refConf = 0.95,
    double limitConf = 0.90,
    String variable = '',
    String unit = ''}) {
  groupName ??= tr('Sous-groupe', 'Subgroup');
  final x = <double>[], g = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final v = raw[i];
    if (v == null || !v.isFinite) continue;
    if (groups != null && groups[i] == null) continue;
    x.add(v);
    if (groups != null) g.add(groups[i]!);
  }
  final n0 = x.length;
  if (n0 < 20) throw StatInputError('ri_n', tr('Au moins 20 valeurs sont requises (120 recommandées, CLSI EP28).', 'At least 20 values are required (120 recommended, CLSI EP28).'));
  final ho = hornOutliers(x);
  var data = x, labels = g;
  if (removeOutliers && ho.outliers.isNotEmpty) {
    final keep = [for (var i = 0; i < x.length; i++) if (!ho.outliers.contains(x[i])) i];
    data = [for (final i in keep) x[i]];
    if (groups != null) labels = [for (final i in keep) g[i]];
  }
  final n = data.length;
  final res = _interval(data, method, refConf, limitConf);
  final u = unit.isEmpty ? '' : ' $unit';
  final pct = (refConf * 100).round(), lpct = (limitConf * 100).round();
  final stats = <String, double>{
    'n': n.toDouble(),
    'lower': res.lower,
    'upper': res.upper,
    'boxcox_lambda': ho.lambda,
    'outliers': ho.outliers.length.toDouble(),
    if (res.ci != null) ...{'lower_ci_low': res.ci![0], 'lower_ci_high': res.ci![1], 'upper_ci_low': res.ci![2], 'upper_ci_high': res.ci![3]},
  };
  final tables = <ResultTable>[
    ResultTable(tr('Intervalle de référence ($pct %)', 'Reference interval ($pct%)'), [tr('Borne', 'Limit'), tr('Valeur', 'Value'), tr('IC $lpct %', '$lpct% CI')], [
      [tr('Inférieure', 'Lower'), fmt(res.lower), res.ci == null ? '—' : '${fmt(res.ci![0])} – ${fmt(res.ci![1])}'],
      [tr('Supérieure', 'Upper'), fmt(res.upper), res.ci == null ? '—' : '${fmt(res.ci![2])} – ${fmt(res.ci![3])}'],
    ]),
  ];
  // Partition par sous-groupe.
  ({double z, double zStar, double sdRatio, bool partition})? hb;
  if (groups != null) {
    final levels = labels.toSet().toList()..sort();
    if (levels.length != 2) throw StatInputError('ri_groups', tr('La partition de Harris et Boyd compare exactement 2 sous-groupes.', 'The Harris and Boyd partition compares exactly 2 subgroups.'));
    final a = [for (var i = 0; i < n; i++) if (labels[i] == levels[0]) data[i]], b = [for (var i = 0; i < n; i++) if (labels[i] == levels[1]) data[i]];
    hb = harrisBoyd(a, b);
    stats.addAll({'hb_z': hb.z, 'hb_zstar': hb.zStar, 'hb_sd_ratio': hb.sdRatio});
    final rows = <List<String>>[];
    for (final (lv, sub) in [(levels[0], a), (levels[1], b)]) {
      final r = _interval(sub, method, refConf, limitConf);
      stats['lower_$lv'] = r.lower;
      stats['upper_$lv'] = r.upper;
      rows.add([lv, '${sub.length}', fmt(r.lower), fmt(r.upper), r.ci == null ? '—' : '${fmt(r.ci![0])} – ${fmt(r.ci![1])}${tr(' ; ', '; ')}${fmt(r.ci![2])} – ${fmt(r.ci![3])}']);
    }
    tables.add(ResultTable(tr('Par $groupName (Harris et Boyd : z = ${fmt(hb.z)}, seuil ${fmt(hb.zStar)}, rapport des ÉT ${fmt(hb.sdRatio)})', 'By $groupName (Harris and Boyd: z = ${fmt(hb.z)}, threshold ${fmt(hb.zStar)}, SD ratio ${fmt(hb.sdRatio)})'),
        [groupName, 'n', tr('Inférieure', 'Lower'), tr('Supérieure', 'Upper'), tr('IC $lpct %', '$lpct% CI')], rows));
  }
  final alerts = <Alert>[];
  if (n < 120) {
    alerts.add(Alert('ri_small_n', Severity.caution,
        tr('$n valeurs : la CLSI recommande au moins 120 sujets de référence par partition ; les bornes sont imprécises.', '$n values: CLSI recommends at least 120 reference subjects per partition; the limits are imprecise.'),
        suggestion: tr('Avec 20 à 120 valeurs, préférer la méthode robuste, ou paramétrique après transformation ; ou vérifier un intervalle existant (transfert, 20 sujets).', 'With 20 to 120 values, prefer the robust method, or parametric after transformation; or verify an existing interval (transference, 20 subjects).')));
  }
  if (ho.outliers.isNotEmpty) {
    alerts.add(Alert('ri_outliers', removeOutliers ? Severity.info : Severity.caution,
        tr('${ho.outliers.length} valeur(s) aberrante(s) selon Horn : ${ho.outliers.map(fmt).join(" ; ")}${removeOutliers ? " (retirées)" : " (conservées)"}.', '${ho.outliers.length} outlier(s) by Horn\'s method: ${ho.outliers.map(fmt).join("; ")}${removeOutliers ? " (removed)" : " (kept)"}.'),
        suggestion: tr('Ne retirer une valeur qu\'après avoir vérifié le sujet (critères d\'exclusion) ou une erreur pré-analytique.', 'Remove a value only after checking the subject (exclusion criteria) or a pre-analytical error.')));
  }
  if (method == ReferenceMethod.parametric && (ho.lambda - 1).abs() > 0.5) {
    alerts.add(Alert('ri_not_normal', Severity.caution,
        tr('Distribution asymétrique (λ de Box-Cox = ${fmt(ho.lambda)}) : la méthode paramétrique sur l\'échelle brute est inadaptée.', 'Skewed distribution (Box-Cox λ = ${fmt(ho.lambda)}): the parametric method on the raw scale is inappropriate.'),
        suggestion: tr('Utiliser la méthode non paramétrique (n ≥ 120) ou robuste, ou transformer les données.', 'Use the nonparametric (n ≥ 120) or robust method, or transform the data.')));
  }
  if (hb != null && hb.partition) {
    alerts.add(Alert('ri_partition', Severity.caution, tr('Harris et Boyd : des intervalles distincts par $groupName sont justifiés.', 'Harris and Boyd: separate intervals by $groupName are justified.')));
  }
  // Histogramme (30 classes) et bornes, pour la figure.
  final sorted = [...data]..sort();
  final w = (sorted.last - sorted.first) / 30;
  final counts = List<int>.filled(30, 0);
  for (final v in data) {
    counts[w == 0 ? 0 : math.min(29, ((v - sorted.first) / w).floor())]++;
  }
  return AnalysisResult(
    figures: {
      'referenceInterval': {'min': sorted.first, 'width': w, 'counts': counts, 'lower': res.lower, 'upper': res.upper, 'ci': ?res.ci, 'variable': variable, 'unit': unit},
    },
    methodId: 'reference_interval',
    methodName: tr('Intervalle de référence (${_methodLabel(method)})', 'Reference interval (${_methodLabel(method)})'),
    inputs: {'n': n0, 'method': method.name, 'removeOutliers': removeOutliers, 'refConf': refConf, 'limitConf': limitConf, 'variable': variable},
    formula: tr(
        'Non paramétrique : quantiles 2,5 % et 97,5 % de type 6 ; IC à 90 % des bornes par les rangs binomiaux de la CLSI (n ≥ 120). Paramétrique : m ± 1,96·s, IC ± z₀.₉₀·√(s²/n + 1,96²s²/2n). Robuste : bipoids de Tukey (c = 3,7) centré par itération, marge t(n − 1)·√(s_bi(205,6)² + S_T(3,7)²). Valeurs aberrantes (Horn) : Box-Cox puis barrières de Tukey. Partition (Harris et Boyd) : z = |m₁ − m₂|/√(s₁²/n₁ + s₂²/n₂) > 3·√(n̄/120), ou rapport des ÉT > 1,5.',
        'Nonparametric: type 6 quantiles 2.5% and 97.5%; 90% CIs of the limits by the CLSI binomial ranks (n ≥ 120). Parametric: m ± 1.96·s, CI ± z₀.₉₀·√(s²/n + 1.96²s²/2n). Robust: Tukey biweight (c = 3.7) centred iteratively, margin t(n − 1)·√(s_bi(205.6)² + S_T(3.7)²). Outliers (Horn): Box-Cox then Tukey fences. Partition (Harris and Boyd): z = |m₁ − m₂|/√(s₁²/n₁ + s₂²/n₂) > 3·√(n̄/120), or SD ratio > 1.5.'),
    estimates: [
      Estimate(tr('Borne inférieure', 'Lower limit'), res.lower, lower: res.ci?[0], upper: res.ci?[1], level: limitConf),
      Estimate(tr('Borne supérieure', 'Upper limit'), res.upper, lower: res.ci?[2], upper: res.ci?[3], level: limitConf),
    ],
    statistics: stats,
    checks: [
      Check('ri_sample_size', tr('Au moins 120 sujets de référence (CLSI EP28)', 'At least 120 reference subjects (CLSI EP28)'), n >= 120 ? CheckStatus.ok : CheckStatus.warning, 'n = $n.'),
      Check('ri_selection', tr('Sujets de référence sélectionnés selon des critères définis a priori', 'Reference subjects selected by criteria defined a priori'), CheckStatus.notAssessed,
          tr('Population saine, conditions pré-analytiques et méthode identiques à celles de l\'usage prévu.', 'Healthy population, pre-analytical conditions and method identical to those of the intended use.')),
      Check('ri_outliers', tr('Valeurs aberrantes examinées', 'Outliers examined'), ho.outliers.isEmpty ? CheckStatus.ok : CheckStatus.warning, tr('${ho.outliers.length} valeur(s) selon Horn.', '${ho.outliers.length} value(s) by Horn.')),
    ],
    alerts: alerts,
    tables: tables,
    log: [if (res.ciNote != null) res.ciNote!, tr('λ de Box-Cox : ${fmt(ho.lambda)}.', 'Box-Cox λ: ${fmt(ho.lambda)}.')],
    interpretation: Interpretation(
      whyThisMethod: tr('L\'intervalle de référence décrit les valeurs de 95 % des sujets d\'une population de référence ; la méthode non paramétrique est la référence de la CLSI quand n ≥ 120.',
          'The reference interval describes the values of 95% of the subjects of a reference population; the nonparametric method is the CLSI standard when n ≥ 120.'),
      whatItMeans: tr('Intervalle de référence à $pct % : ${fmt(res.lower)} à ${fmt(res.upper)}$u (n = $n).${res.ci == null ? '' : ' Incertitude des bornes (IC à $lpct %) : inférieure ${fmt(res.ci![0])} à ${fmt(res.ci![1])}, supérieure ${fmt(res.ci![2])} à ${fmt(res.ci![3])}.'}',
          '$pct% reference interval: ${fmt(res.lower)} to ${fmt(res.upper)}$u (n = $n).${res.ci == null ? '' : ' Uncertainty of the limits ($lpct% CI): lower ${fmt(res.ci![0])} to ${fmt(res.ci![1])}, upper ${fmt(res.ci![2])} to ${fmt(res.ci![3])}.'}'),
      notJustified: tr('Lire une valeur hors de l\'intervalle comme pathologique (5 % des sujets sains en sortent) ; confondre intervalle de référence et seuil de décision clinique ; transférer l\'intervalle à une autre méthode ou population sans vérification.',
          'Reading a value outside the interval as pathological (5% of healthy subjects fall outside); confusing a reference interval with a clinical decision threshold; transferring the interval to another method or population without verification.'),
    ),
  );
}

/// Fidélité d'une méthode (plan équilibré) : [day] obligatoire, [run] facultatif (séries emboîtées dans les jours).
/// [claimRepeatability] et [claimWithinLab] : ÉT annoncés par le fabricant (vérification EP15, [levels] niveaux).
AnalysisResult precisionAnalysis(List<double?> yRaw, List<String?> dayRaw,
    {List<String?>? runRaw, double? claimRepeatability, double? claimWithinLab, int levels = 1, double level = 0.95, String unit = ''}) {
  final y = <double>[], d = <String>[], r = <String>[];
  for (var i = 0; i < yRaw.length; i++) {
    final v = yRaw[i];
    if (v == null || !v.isFinite || dayRaw[i] == null || (runRaw != null && runRaw[i] == null)) continue;
    y.add(v);
    d.add(dayRaw[i]!);
    r.add(runRaw == null ? '' : '${dayRaw[i]}|${runRaw[i]}');
  }
  final days = d.toSet().toList(), cells = runRaw == null ? days : r.toSet().toList();
  final nested = runRaw != null;
  // Plan équilibré : même nombre de séries par jour et de répétitions par cellule.
  final perCell = <String, List<double>>{};
  for (var i = 0; i < y.length; i++) {
    perCell.putIfAbsent(nested ? r[i] : d[i], () => []).add(y[i]);
  }
  final nRep = perCell.values.first.length;
  final runsPerDay = nested ? cells.length ~/ days.length : 1;
  if (perCell.values.any((c) => c.length != nRep) || (nested && days.any((dd) => cells.where((c) => c.startsWith('$dd|')).length != runsPerDay))) {
    throw StatInputError('precision_unbalanced', tr('Plan déséquilibré (nombre de répétitions ou de séries différent) : la fidélité est calculée ici pour un plan équilibré (EP05 : 20 × 2 × 2 ; EP15 : 5 × 5).', 'Unbalanced design (different numbers of replicates or runs): precision is computed here for a balanced design (EP05: 20 × 2 × 2; EP15: 5 × 5).'));
  }
  if (days.length < 3 || nRep < 2) throw StatInputError('precision_small', tr('Au moins 3 jours et 2 répétitions sont requis.', 'At least 3 days and 2 replicates are required.'));
  final a = days.length, b = runsPerDay, n = nRep, total = y.length;
  final grand = _mean(y);
  final cellMean = {for (final e in perCell.entries) e.key: _mean(e.value)};
  final dayMean = {for (final dd in days) dd: _mean([for (var i = 0; i < y.length; i++) if (d[i] == dd) y[i]])};
  var ssE = 0.0;
  for (var i = 0; i < y.length; i++) {
    final c = cellMean[nested ? r[i] : d[i]]!;
    ssE += (y[i] - c) * (y[i] - c);
  }
  final ssD = b * n * dayMean.values.fold(0.0, (s, m) => s + (m - grand) * (m - grand));
  final ssR = nested ? n * cellMean.entries.fold(0.0, (s, e) => s + math.pow(e.value - dayMean[e.key.split('|').first]!, 2)) : 0.0;
  final dfD = a - 1.0, dfR = nested ? a * (b - 1.0) : 0.0, dfE = total - a * b * 1.0;
  final msD = ssD / dfD, msR = nested ? ssR / dfR : 0.0, msE = ssE / dfE;
  // Composantes (bornées à 0 comme VCA) puis carrés moyens attendus reconstruits (ddl de Satterthwaite du total).
  final vcE = msE;
  final vcR = nested ? math.max(0.0, (msR - msE) / n) : 0.0;
  final vcD = math.max(0.0, (msD - (nested ? msR : msE)) / (b * n));
  final vcT = vcD + vcR + vcE;
  final emsE = vcE, emsR = vcE + n * vcR, emsD = vcE + n * vcR + b * n * vcD;
  final cD = 1 / (b * n), cR = nested ? 1 / n - 1 / (b * n) : 0.0, cE = 1 - 1 / n;
  final dfT = vcT * vcT / (math.pow(cD * emsD, 2) / dfD + (nested ? math.pow(cR * emsR, 2) / dfR : 0) + math.pow(cE * emsE, 2) / dfE);
  final z = normalQuantile(1 - (1 - level) / 2);
  List<double>? chiCi(double vc, double df) => vc <= 0 ? null : [df * vc / chiSquareQuantile(1 - (1 - level) / 2, df), df * vc / chiSquareQuantile((1 - level) / 2, df)];
  List<double>? waldCi(double vc, double var0) => vc <= 0 ? null : [math.max(0, vc - z * math.sqrt(var0)), vc + z * math.sqrt(var0)];
  final varD = nested ? 2 / math.pow(b * n, 2) * (msD * msD / dfD + msR * msR / dfR) : 2 / (n * n) * (msD * msD / dfD + msE * msE / dfE);
  final varR = nested ? 2 / (n * n) * (msR * msR / dfR + msE * msE / dfE) : 0.0;
  final comps = <(String, String, double, double, List<double>?)>[
    ('total', tr('Fidélité intermédiaire (intralaboratoire)', 'Within-laboratory precision'), dfT, vcT, chiCi(vcT, dfT)),
    ('day', tr('Entre jours', 'Between days'), dfD, vcD, waldCi(vcD, varD)),
    if (nested) ('run', tr('Entre séries', 'Between runs'), dfR, vcR, waldCi(vcR, varR)),
    ('error', tr('Répétabilité', 'Repeatability'), dfE, vcE, chiCi(vcE, dfE)),
  ];
  final u = unit.isEmpty ? '' : ' $unit';
  final pct = (level * 100).round();
  final stats = <String, double>{'mean': grand, 'n': total.toDouble(), 'days': a.toDouble()};
  for (final (k, _, df, vc, ci) in comps) {
    stats['df_$k'] = df;
    stats['vc_$k'] = vc;
    stats['sd_$k'] = math.sqrt(vc);
    stats['cv_$k'] = math.sqrt(vc) / grand * 100;
    if (ci != null) {
      stats['sd_${k}_lower'] = math.sqrt(ci[0]);
      stats['sd_${k}_upper'] = math.sqrt(ci[1]);
    }
  }
  // Vérification EP15 d'une fidélité annoncée.
  final verifRows = <List<String>>[];
  final checks = <Check>[];
  final q = 1 - 0.05 / levels;
  for (final (key, label, claim, df) in [('error', tr('Répétabilité', 'Repeatability'), claimRepeatability, dfE), ('total', tr('Intralaboratoire', 'Within-laboratory'), claimWithinLab, dfT)]) {
    if (claim == null) continue;
    final uvl = claim * math.sqrt(chiSquareQuantile(q, df) / df);
    final sd = stats['sd_$key']!;
    final ok = sd <= uvl;
    stats['uvl_$key'] = uvl;
    verifRows.add([label, fmt(claim), fmt(sd), fmt(uvl), ok ? tr('vérifiée', 'verified') : tr('non vérifiée', 'not verified')]);
    checks.add(Check('verify_$key', tr('$label annoncée vérifiée (EP15)', 'Claimed $label verified (EP15)'), ok ? CheckStatus.ok : CheckStatus.violated,
        tr('ÉT ${fmt(sd)} contre limite de vérification ${fmt(uvl)} (annoncé ${fmt(claim)}).', 'SD ${fmt(sd)} against verification limit ${fmt(uvl)} (claimed ${fmt(claim)}).')));
  }
  checks.add(Check('balanced_design', tr('Plan équilibré', 'Balanced design'), CheckStatus.ok,
      nested ? tr('$a jours × $b séries × $n répétitions.', '$a days × $b runs × $n replicates.') : tr('$a jours × $n répétitions.', '$a days × $n replicates.')));
  final alerts = <Alert>[
    if (vcD == 0 || (nested && vcR == 0))
      Alert('vc_zero', Severity.info, tr('Une composante estimée négative a été fixée à 0 (variabilité inférieure à celle attendue par la répétabilité seule).', 'A component estimated as negative was set to 0 (variability lower than expected from repeatability alone).')),
  ];
  final rep = comps.last, wl = comps.first;
  return AnalysisResult(
    methodId: 'precision',
    methodName: tr('Fidélité de la méthode (${nested ? 'EP05 : jour/série' : 'EP15 : jour'})', 'Method precision (${nested ? 'EP05: day/run' : 'EP15: day'})'),
    inputs: {'n': total, 'days': a, 'runsPerDay': b, 'replicates': n, 'level': level, 'claimRepeatability': ?claimRepeatability, 'claimWithinLab': ?claimWithinLab, 'levels': levels},
    formula: tr(
        'ANOVA emboîtée (plan équilibré) : composantes = (CM_niveau − CM_niveau inférieur)/effectif par niveau, bornées à 0 ; répétabilité = CM résiduel ; fidélité intermédiaire = somme des composantes, ddl de Satterthwaite. IC : χ² pour la répétabilité et le total, Wald (borné à 0) pour les autres. CV = ÉT/moyenne. EP15 : limite de vérification = σ annoncé × √(χ²(1 − 0,05/l ; ddl)/ddl).',
        'Nested ANOVA (balanced design): components = (MS_level − MS_lower level)/count per level, bounded at 0; repeatability = residual MS; within-laboratory precision = sum of components, Satterthwaite df. CIs: χ² for repeatability and total, Wald (bounded at 0) for the others. CV = SD/mean. EP15: verification limit = claimed σ × √(χ²(1 − 0.05/l; df)/df).'),
    estimates: [
      Estimate(tr('ÉT de répétabilité', 'Repeatability SD'), math.sqrt(rep.$4), lower: rep.$5 == null ? null : math.sqrt(rep.$5![0]), upper: rep.$5 == null ? null : math.sqrt(rep.$5![1]), level: level),
      Estimate(tr('ÉT intralaboratoire', 'Within-laboratory SD'), math.sqrt(wl.$4), lower: wl.$5 == null ? null : math.sqrt(wl.$5![0]), upper: wl.$5 == null ? null : math.sqrt(wl.$5![1]), level: level),
    ],
    statistics: stats,
    checks: checks,
    alerts: alerts,
    tables: [
      ResultTable(tr('Composantes de la variance (moyenne ${fmt(grand)}$u)', 'Variance components (mean ${fmt(grand)}$u)'),
          [tr('Composante', 'Component'), tr('ddl', 'df'), tr('Variance', 'Variance'), tr('ÉT', 'SD'), tr('IC $pct % de l\'ÉT', '$pct% CI of SD'), 'CV %'], [
        for (final (_, label, df, vc, ci) in comps)
          [label, fmt(df), fmt(vc, digits: 4), fmt(math.sqrt(vc)), ci == null ? '—' : '${fmt(math.sqrt(ci[0]))} – ${fmt(math.sqrt(ci[1]))}', fmt(math.sqrt(vc) / grand * 100)]
      ]),
      if (verifRows.isNotEmpty)
        ResultTable(tr('Vérification de la fidélité annoncée (EP15, $levels niveau(x))', 'Verification of the claimed precision (EP15, $levels level(s))'),
            [tr('Fidélité', 'Precision'), tr('ÉT annoncé', 'Claimed SD'), tr('ÉT observé', 'Observed SD'), tr('Limite de vérification', 'Verification limit'), tr('Conclusion', 'Conclusion')], verifRows),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('La fidélité sépare la variabilité de répétabilité (même série) de celle entre séries et entre jours ; la fidélité intermédiaire est celle que voit le laboratoire au quotidien.',
          'Precision separates repeatability variability (same run) from between-run and between-day variability; within-laboratory precision is what the laboratory sees day to day.'),
      whatItMeans: tr('Répétabilité : ÉT ${fmt(math.sqrt(rep.$4))}$u (CV ${fmt(math.sqrt(rep.$4) / grand * 100)} %). Intralaboratoire : ÉT ${fmt(math.sqrt(wl.$4))}$u (CV ${fmt(math.sqrt(wl.$4) / grand * 100)} %).',
          'Repeatability: SD ${fmt(math.sqrt(rep.$4))}$u (CV ${fmt(math.sqrt(rep.$4) / grand * 100)}%). Within-laboratory: SD ${fmt(math.sqrt(wl.$4))}$u (CV ${fmt(math.sqrt(wl.$4) / grand * 100)}%).'),
      notJustified: tr('Juger la fidélité sur un seul niveau de concentration ; comparer un CV à l\'objectif sans tenir compte de son IC ; conclure sur 5 jours comme sur 20 (EP15 vérifie, EP05 établit).',
          'Judging precision at a single concentration level; comparing a CV with the goal without its CI; concluding from 5 days as from 20 (EP15 verifies, EP05 establishes).'),
    ),
  );
}
