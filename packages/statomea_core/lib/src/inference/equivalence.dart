/// Équivalence, non-infériorité et valeur E.
///  - TOST (deux tests unilatéraux, Schuirmann) : deux moyennes indépendantes (Welch ou Student) ou appariées, deux
///    proportions (différence, ES non poolée, tests z) ; équivalence démontrée si l'IC à 1 − 2α est dans les marges ;
///  - non-infériorité : un seul test unilatéral contre la marge ;
///  - valeur E (VanderWeele et Ding 2017) : force minimale d'association (sur l'échelle du RR) qu'un facteur de
///    confusion non mesuré devrait avoir avec le traitement et l'issue pour annuler l'effet observé ou la borne de son IC.
/// Validé contre validation/r/55_equivalence_evalue.R (TOSTER 0.8.0, EValue 4.1.3).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';

enum EquivalenceHypothesis { equivalence, nonInferiorityHigherBetter, nonInferiorityLowerBetter }

List<double> _clean(List<double?> x) => [for (final v in x) if (v != null && v.isFinite) v];
double _mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;
double _var(List<double> x) {
  final m = _mean(x);
  return x.fold(0.0, (a, v) => a + (v - m) * (v - m)) / (x.length - 1);
}

double _tUpper(double t, double df) => tCdf(-t, df);

/// Équivalence ou non-infériorité de deux moyennes ([y] = groupe de comparaison) ; différence = moyenne(x) − moyenne(y).
/// [paired] : x et y appariés (différences x − y). Marges [low] < 0 < [high] (équivalence) ; pour la non-infériorité,
/// [margin] > 0.
AnalysisResult equivalenceMeans(List<double?> xr, List<double?> yr,
    {bool paired = false,
    bool varEqual = false,
    EquivalenceHypothesis hypothesis = EquivalenceHypothesis.equivalence,
    double? low,
    double? high,
    double? margin,
    double alpha = 0.05,
    String xName = 'A',
    String yName = 'B',
    String unit = ''}) {
  late double d, se, df;
  late int n1, n2;
  if (paired) {
    final diffs = <double>[];
    for (var i = 0; i < math.min(xr.length, yr.length); i++) {
      final a = xr[i], b = yr[i];
      if (a != null && b != null && a.isFinite && b.isFinite) diffs.add(a - b);
    }
    if (diffs.length < 3) throw StatInputError('n_too_small', tr('Au moins 3 paires complètes sont requises.', 'At least 3 complete pairs are required.'));
    d = _mean(diffs);
    se = math.sqrt(_var(diffs) / diffs.length);
    df = diffs.length - 1.0;
    n1 = n2 = diffs.length;
  } else {
    final x = _clean(xr), y = _clean(yr);
    if (x.length < 2 || y.length < 2) throw StatInputError('n_too_small', tr('Au moins 2 valeurs par groupe sont requises.', 'At least 2 values per group are required.'));
    n1 = x.length;
    n2 = y.length;
    final v1 = _var(x), v2 = _var(y);
    d = _mean(x) - _mean(y);
    if (varEqual) {
      final sp = ((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2);
      se = math.sqrt(sp * (1 / n1 + 1 / n2));
      df = n1 + n2 - 2.0;
    } else {
      final a = v1 / n1, b = v2 / n2;
      se = math.sqrt(a + b);
      df = (a + b) * (a + b) / (a * a / (n1 - 1) + b * b / (n2 - 1));
    }
  }
  final u = unit.isEmpty ? '' : ' $unit';
  final label = paired ? tr('Différence moyenne appariée $xName − $yName', 'Mean paired difference $xName − $yName') : tr('Différence de moyennes $xName − $yName', 'Difference in means $xName − $yName');
  final tq = tQuantile(1 - alpha, df);
  final ciLo = d - tq * se, ciHi = d + tq * se;
  final stats = <String, double>{'diff': d, 'se': se, 'df': df, 'ci_lower': ciLo, 'ci_upper': ciHi};
  late final bool shown;
  late final String conclusion, formula;
  late final List<List<String>> rows;
  if (hypothesis == EquivalenceHypothesis.equivalence) {
    if (low == null || high == null || !(low < high)) throw StatInputError('margins', tr('Indiquer des marges d\'équivalence inférieure < supérieure.', 'Give equivalence margins lower < upper.'));
    final t1 = (d - low) / se, t2 = (d - high) / se;
    final p1 = _tUpper(t1, df), p2 = tCdf(t2, df);
    final p = math.max(p1, p2);
    shown = p < alpha;
    stats.addAll({'t_lower': t1, 'p_lower': p1, 't_upper': t2, 'p_upper': p2, 'p': p, 't_nhst': d / se, 'p_nhst': tTwoSidedP(d / se, df)});
    rows = [
      [tr('Borne inférieure (H₀ : d ≤ ${fmt(low)})', 'Lower bound (H₀: d ≤ ${fmt(low)})'), fmt(t1), fmt(df), fmtP(p1)],
      [tr('Borne supérieure (H₀ : d ≥ ${fmt(high)})', 'Upper bound (H₀: d ≥ ${fmt(high)})'), fmt(t2), fmt(df), fmtP(p2)],
      [tr('Test classique (H₀ : d = 0)', 'Classical test (H₀: d = 0)'), fmt(d / se), fmt(df), fmtP(stats['p_nhst']!)],
    ];
    conclusion = shown
        ? tr('équivalence démontrée : l\'IC à ${((1 - 2 * alpha) * 100).round()} % (${fmt(ciLo)} à ${fmt(ciHi)}) est entièrement dans les marges [${fmt(low)} ; ${fmt(high)}]$u.',
            'equivalence shown: the ${((1 - 2 * alpha) * 100).round()}% CI (${fmt(ciLo)} to ${fmt(ciHi)}) lies entirely within the margins [${fmt(low)}; ${fmt(high)}]$u.')
        : tr('équivalence non démontrée : l\'IC à ${((1 - 2 * alpha) * 100).round()} % (${fmt(ciLo)} à ${fmt(ciHi)}) déborde des marges [${fmt(low)} ; ${fmt(high)}]$u.',
            'equivalence not shown: the ${((1 - 2 * alpha) * 100).round()}% CI (${fmt(ciLo)} to ${fmt(ciHi)}) extends beyond the margins [${fmt(low)}; ${fmt(high)}]$u.');
    formula = tr('TOST : t₁ = (d − Δ_inf)/ES (unilatéral, H₀ : d ≤ Δ_inf), t₂ = (d − Δ_sup)/ES (H₀ : d ≥ Δ_sup) ; p = max(p₁, p₂) ; équivalent si p < α, soit IC à 1 − 2α inclus dans [Δ_inf ; Δ_sup].',
        'TOST: t₁ = (d − Δ_low)/SE (one-sided, H₀: d ≤ Δ_low), t₂ = (d − Δ_high)/SE (H₀: d ≥ Δ_high); p = max(p₁, p₂); equivalent if p < α, i.e. 1 − 2α CI within [Δ_low; Δ_high].');
  } else {
    if (margin == null || margin <= 0) throw StatInputError('margins', tr('Indiquer une marge de non-infériorité > 0.', 'Give a non-inferiority margin > 0.'));
    final higher = hypothesis == EquivalenceHypothesis.nonInferiorityHigherBetter;
    final t = higher ? (d + margin) / se : (d - margin) / se;
    final p = higher ? _tUpper(t, df) : tCdf(t, df);
    shown = p < alpha;
    stats.addAll({'t': t, 'p': p});
    rows = [
      [higher ? tr('H₀ : d ≤ −${fmt(margin)}', 'H₀: d ≤ −${fmt(margin)}') : tr('H₀ : d ≥ ${fmt(margin)}', 'H₀: d ≥ ${fmt(margin)}'), fmt(t), fmt(df), fmtP(p)],
    ];
    final bound = higher ? ciLo : ciHi;
    conclusion = shown
        ? tr('non-infériorité démontrée : la borne ${higher ? 'inférieure' : 'supérieure'} de l\'IC unilatéral (${fmt(bound)}) ne franchit pas la marge (${higher ? '−' : ''}${fmt(margin)})$u.',
            'non-inferiority shown: the ${higher ? 'lower' : 'upper'} bound of the one-sided CI (${fmt(bound)}) does not cross the margin (${higher ? '−' : ''}${fmt(margin)})$u.')
        : tr('non-infériorité non démontrée : la borne ${higher ? 'inférieure' : 'supérieure'} de l\'IC unilatéral (${fmt(bound)}) franchit la marge (${higher ? '−' : ''}${fmt(margin)})$u.',
            'non-inferiority not shown: the ${higher ? 'lower' : 'upper'} bound of the one-sided CI (${fmt(bound)}) crosses the margin (${higher ? '−' : ''}${fmt(margin)})$u.');
    formula = tr('Non-infériorité : un test unilatéral, t = (d + Δ)/ES si une valeur plus élevée est meilleure (H₀ : d ≤ −Δ), t = (d − Δ)/ES sinon (H₀ : d ≥ Δ).',
        'Non-inferiority: one one-sided test, t = (d + Δ)/SE if a higher value is better (H₀: d ≤ −Δ), t = (d − Δ)/SE otherwise (H₀: d ≥ Δ).');
  }
  final cpct = ((1 - 2 * alpha) * 100).round();
  final isEq = hypothesis == EquivalenceHypothesis.equivalence;
  return AnalysisResult(
    methodId: isEq ? 'equivalence_tost' : 'non_inferiority',
    methodName: isEq
        ? tr('Test d\'équivalence (TOST, ${paired ? 'apparié' : varEqual ? 'Student' : 'Welch'})', 'Equivalence test (TOST, ${paired ? 'paired' : varEqual ? 'Student' : 'Welch'})')
        : tr('Test de non-infériorité (${paired ? 'apparié' : varEqual ? 'Student' : 'Welch'})', 'Non-inferiority test (${paired ? 'paired' : varEqual ? 'Student' : 'Welch'})'),
    inputs: {'n1': n1, 'n2': n2, 'paired': paired, 'varEqual': varEqual, 'hypothesis': hypothesis.name, 'low': ?low, 'high': ?high, 'margin': ?margin, 'alpha': alpha},
    formula: formula,
    estimates: [Estimate(label, d, lower: ciLo, upper: ciHi, se: se, level: 1 - 2 * alpha, pValue: stats['p'])],
    statistics: stats,
    checks: [
      Check('margin_prespecified', tr('Marge fixée a priori sur une base clinique', 'Margin set a priori on clinical grounds'), CheckStatus.notAssessed,
          tr('La marge doit être justifiée avant l\'étude (différence cliniquement négligeable, effet du comparateur contre placebo) ; la choisir au vu des données invalide la conclusion.',
              'The margin must be justified before the study (clinically negligible difference, effect of the comparator versus placebo); choosing it from the data invalidates the conclusion.')),
      if (!paired) Check('normality', tr('Moyennes approximativement normales', 'Approximately normal means'), n1 >= 30 && n2 >= 30 ? CheckStatus.ok : CheckStatus.notAssessed, 'n = $n1${tr(' ; ', '; ')}$n2.'),
    ],
    tables: [
      ResultTable(tr('Tests unilatéraux', 'One-sided tests'), [tr('Hypothèse nulle', 'Null hypothesis'), 't', tr('ddl', 'df'), 'p'], rows),
      ResultTable(tr('Estimation', 'Estimate'), [tr('Différence', 'Difference'), tr('ES', 'SE'), tr('IC $cpct %', '$cpct% CI')], [
        [fmt(d), fmt(se), '${fmt(ciLo)} – ${fmt(ciHi)}']
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Montrer qu\'une différence est cliniquement négligeable exige un test d\'équivalence ou de non-infériorité : un test classique non significatif ne prouve pas l\'absence de différence.',
          'Showing that a difference is clinically negligible requires an equivalence or non-inferiority test: a non-significant classical test does not prove the absence of a difference.'),
      whatItMeans: '${tr('Différence ${fmt(d)}$u : ', 'Difference ${fmt(d)}$u: ')}$conclusion',
      notJustified: tr('Conclure à l\'équivalence à partir d\'un p > 0,05 d\'un test classique ; élargir la marge après coup ; conclure à la supériorité à partir d\'un test de non-infériorité sans test dédié.',
          'Concluding equivalence from a classical test with p > 0.05; widening the margin afterwards; concluding superiority from a non-inferiority test without a dedicated test.'),
    ),
  );
}

/// Équivalence de deux proportions (différence p₁ − p₂, ES non poolée, tests z), comme TOSTER::twoprop_test.
AnalysisResult equivalenceProportions(int x1, int n1, int x2, int n2, {required double low, required double high, double alpha = 0.05, String name1 = 'A', String name2 = 'B'}) {
  if (n1 < 10 || n2 < 10 || x1 < 0 || x2 < 0 || x1 > n1 || x2 > n2) throw StatInputError('prop_input', tr('Effectifs invalides (au moins 10 par groupe).', 'Invalid counts (at least 10 per group).'));
  return equivalenceProportionsFromRates(x1 / n1, n1, x2 / n2, n2, low: low, high: high, alpha: alpha, name1: name1, name2: name2, counts: (x1, x2));
}

/// Même test à partir des proportions observées (p₁, n₁, p₂, n₂).
AnalysisResult equivalenceProportionsFromRates(double p1, int n1, double p2, int n2,
    {required double low, required double high, double alpha = 0.05, String name1 = 'A', String name2 = 'B', (int, int)? counts}) {
  if (!(low < high)) throw StatInputError('margins', tr('Indiquer des marges inférieure < supérieure.', 'Give margins lower < upper.'));
  if (p1 < 0 || p1 > 1 || p2 < 0 || p2 > 1 || n1 < 10 || n2 < 10) throw StatInputError('prop_input', tr('Proportions entre 0 et 1, au moins 10 sujets par groupe.', 'Proportions between 0 and 1, at least 10 subjects per group.'));
  final x1 = counts?.$1 ?? (p1 * n1).round(), x2 = counts?.$2 ?? (p2 * n2).round();
  final d = p1 - p2;
  final se = math.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2);
  final z1 = (d - low) / se, z2 = (d - high) / se;
  final pl = normalUpper(z1), pu = normalCdf(z2);
  final p = math.max(pl, pu);
  final zq = normalQuantile(1 - alpha);
  final lo = d - zq * se, hi = d + zq * se;
  final cpct = ((1 - 2 * alpha) * 100).round();
  final shown = p < alpha;
  return AnalysisResult(
    methodId: 'equivalence_proportions',
    methodName: tr('Test d\'équivalence de deux proportions (TOST)', 'Equivalence test of two proportions (TOST)'),
    inputs: {'x1': x1, 'n1': n1, 'x2': x2, 'n2': n2, 'low': low, 'high': high, 'alpha': alpha},
    formula: tr('d = p₁ − p₂, ES = √(p₁(1 − p₁)/n₁ + p₂(1 − p₂)/n₂) ; z₁ = (d − Δ_inf)/ES, z₂ = (d − Δ_sup)/ES ; p = max des deux p unilatéraux ; IC à 1 − 2α.',
        'd = p₁ − p₂, SE = √(p₁(1 − p₁)/n₁ + p₂(1 − p₂)/n₂); z₁ = (d − Δ_low)/SE, z₂ = (d − Δ_high)/SE; p = max of the two one-sided p-values; 1 − 2α CI.'),
    estimates: [Estimate(tr('Différence de proportions $name1 − $name2', 'Difference in proportions $name1 − $name2'), d, lower: lo, upper: hi, se: se, level: 1 - 2 * alpha, pValue: p)],
    statistics: {'diff': d, 'se': se, 'z_lower': z1, 'p_lower': pl, 'z_upper': z2, 'p_upper': pu, 'p': p, 'z': pl >= pu ? z1 : z2, 'ci_lower': lo, 'ci_upper': hi},
    checks: [
      Check('margin_prespecified', tr('Marge fixée a priori sur une base clinique', 'Margin set a priori on clinical grounds'), CheckStatus.notAssessed, ''),
      Check('normal_approx', tr('Approximation normale (≥ 10 événements et non-événements par groupe)', 'Normal approximation (≥ 10 events and non-events per group)'),
          [x1, n1 - x1, x2, n2 - x2].every((c) => c >= 10) ? CheckStatus.ok : CheckStatus.warning, '$x1/$n1${tr(' ; ', '; ')}$x2/$n2.'),
    ],
    tables: [
      ResultTable(tr('Tests unilatéraux', 'One-sided tests'), [tr('Hypothèse nulle', 'Null hypothesis'), 'z', 'p'], [
        [tr('d ≤ ${fmt(low)}', 'd ≤ ${fmt(low)}'), fmt(z1), fmtP(pl)],
        [tr('d ≥ ${fmt(high)}', 'd ≥ ${fmt(high)}'), fmt(z2), fmtP(pu)],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Montrer que deux proportions diffèrent de moins qu\'une marge cliniquement négligeable.', 'Showing that two proportions differ by less than a clinically negligible margin.'),
      whatItMeans: tr('Différence ${fmtPct(d)} (IC $cpct % ${fmtPct(lo)} à ${fmtPct(hi)}) : ${shown ? 'équivalence démontrée' : 'équivalence non démontrée'} pour les marges [${fmtPct(low)} ; ${fmtPct(high)}], ${fmtP(p)}.',
          'Difference ${fmtPct(d)} ($cpct% CI ${fmtPct(lo)} to ${fmtPct(hi)}): ${shown ? 'equivalence shown' : 'equivalence not shown'} for the margins [${fmtPct(low)}; ${fmtPct(high)}], ${fmtP(p)}.'),
      notJustified: tr('Conclure à l\'équivalence à partir d\'un test classique non significatif.', 'Concluding equivalence from a non-significant classical test.'),
    ),
  );
}

enum EValueScale { riskRatio, oddsRatioRare, oddsRatioCommon, hazardRatioRare, hazardRatioCommon, standardizedMeanDifference }

double _threshold(double rr) {
  final x = rr <= 1 ? 1 / rr : rr;
  return x + math.sqrt(x * (x - 1));
}

/// Valeur E d'une estimation et de la borne de son IC la plus proche de 1 (VanderWeele et Ding 2017, paquet EValue).
/// Pour une différence standardisée, [estimate] = d et [se] son ES (les bornes sont alors calculées).
AnalysisResult eValue(double estimate, {double? lower, double? upper, double? se, EValueScale scale = EValueScale.riskRatio}) {
  late double rr;
  double? rrLo, rrHi;
  double conv(double v) => switch (scale) {
        EValueScale.oddsRatioCommon => math.sqrt(v),
        EValueScale.hazardRatioCommon => (1 - math.pow(0.5, math.sqrt(v))) / (1 - math.pow(0.5, math.sqrt(1 / v))),
        _ => v,
      };
  if (scale == EValueScale.standardizedMeanDifference) {
    if (se == null || se <= 0) throw StatInputError('evalue_se', tr('Indiquer l\'erreur type de la différence standardisée.', 'Give the standard error of the standardized difference.'));
    rr = math.exp(0.91 * estimate);
    rrLo = math.exp(0.91 * estimate - 1.78 * se);
    rrHi = math.exp(0.91 * estimate + 1.78 * se);
  } else {
    if (estimate <= 0 || (lower != null && lower <= 0) || (upper != null && upper <= 0)) {
      throw StatInputError('evalue_positive', tr('Les rapports (RR, OR, HR) et leurs bornes doivent être > 0.', 'Ratios (RR, OR, HR) and their bounds must be > 0.'));
    }
    if ((lower != null && lower > estimate) || (upper != null && upper < estimate)) {
      throw StatInputError('evalue_ci', tr('L\'estimation doit être comprise dans son intervalle de confiance.', 'The estimate must lie within its confidence interval.'));
    }
    rr = conv(estimate);
    rrLo = lower == null ? null : conv(lower);
    rrHi = upper == null ? null : conv(upper);
  }
  final ePoint = rr == 1 ? 1.0 : _threshold(rr);
  // Borne la plus proche de 1 ; valeur E de 1 si l'IC contient 1.
  double? eCi;
  final closest = rr >= 1 ? rrLo : rrHi;
  if (closest != null) eCi = (rr >= 1 ? closest <= 1 : closest >= 1) ? 1.0 : _threshold(closest);
  final scaleLabel = switch (scale) {
    EValueScale.riskRatio => 'RR',
    EValueScale.oddsRatioRare => tr('OR (issue rare, ≈ RR)', 'OR (rare outcome, ≈ RR)'),
    EValueScale.oddsRatioCommon => tr('OR (issue fréquente, RR ≈ √OR)', 'OR (common outcome, RR ≈ √OR)'),
    EValueScale.hazardRatioRare => tr('HR (issue rare, ≈ RR)', 'HR (rare outcome, ≈ RR)'),
    EValueScale.hazardRatioCommon => tr('HR (issue fréquente, conversion de VanderWeele)', 'HR (common outcome, VanderWeele conversion)'),
    EValueScale.standardizedMeanDifference => tr('différence standardisée (RR ≈ exp(0,91·d))', 'standardized difference (RR ≈ exp(0.91·d))'),
  };
  return AnalysisResult(
    methodId: 'e_value',
    methodName: tr('Valeur E (confusion non mesurée)', 'E-value (unmeasured confounding)'),
    inputs: {'estimate': estimate, 'lower': ?lower, 'upper': ?upper, 'se': ?se, 'scale': scale.name},
    formula: tr('E = RR* + √(RR*(RR* − 1)), RR* = RR si RR ≥ 1, 1/RR sinon ; même calcul pour la borne de l\'IC la plus proche de 1 (E = 1 si l\'IC contient 1). OR fréquent : RR ≈ √OR ; HR fréquent : RR ≈ (1 − 0,5^√HR)/(1 − 0,5^√(1/HR)) ; différence standardisée : RR ≈ exp(0,91·d), IC exp(0,91·d ± 1,78·ES).',
        'E = RR* + √(RR*(RR* − 1)), RR* = RR if RR ≥ 1, 1/RR otherwise; same for the CI bound closest to 1 (E = 1 if the CI contains 1). Common OR: RR ≈ √OR; common HR: RR ≈ (1 − 0.5^√HR)/(1 − 0.5^√(1/HR)); standardized difference: RR ≈ exp(0.91·d), CI exp(0.91·d ± 1.78·SE).'),
    estimates: [
      Estimate(tr('Valeur E de l\'estimation', 'E-value of the estimate'), ePoint),
      if (eCi != null) Estimate(tr('Valeur E de la borne de l\'IC', 'E-value of the CI bound'), eCi),
    ],
    statistics: {'rr': rr, 'rr_lower': ?rrLo, 'rr_upper': ?rrHi, 'e_point': ePoint, 'e_ci': ?eCi},
    checks: [
      Check('evalue_scope', tr('La valeur E ne remplace pas la discussion des facteurs de confusion connus', 'The E-value does not replace discussing known confounders'), CheckStatus.notAssessed,
          tr('Elle indique la force nécessaire, pas l\'existence ni la plausibilité d\'un tel facteur ; la comparer aux associations des facteurs connus.', 'It indicates the strength required, not the existence or plausibility of such a factor; compare it with the associations of known factors.')),
    ],
    tables: [
      ResultTable(tr('Valeur E ($scaleLabel)', 'E-value ($scaleLabel)'), ['', tr('Échelle RR', 'RR scale'), tr('Valeur E', 'E-value')], [
        [tr('Estimation', 'Estimate'), fmt(rr), fmt(ePoint)],
        if (closest != null) [tr('Borne de l\'IC la plus proche de 1', 'CI bound closest to 1'), fmt(closest), fmt(eCi!)],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Dans une étude observationnelle, la valeur E chiffre la robustesse d\'une association à un facteur de confusion non mesuré.',
          'In an observational study, the E-value quantifies how robust an association is to an unmeasured confounder.'),
      whatItMeans: tr(
          'Pour annuler l\'association observée, un facteur de confusion non mesuré devrait être associé à la fois au traitement et à l\'issue par un RR d\'au moins ${fmt(ePoint)}, au-delà des facteurs déjà pris en compte${eCi == null ? '' : eCi == 1 ? ' ; l\'IC contient déjà 1 (valeur E de la borne = 1)' : ' ; pour ramener la borne de l\'IC à 1, un RR d\'au moins ${fmt(eCi)} suffirait'}.',
          'To explain away the observed association, an unmeasured confounder would need to be associated with both the treatment and the outcome by an RR of at least ${fmt(ePoint)}, beyond the factors already accounted for${eCi == null ? '' : eCi == 1 ? '; the CI already contains 1 (E-value of the bound = 1)' : '; to move the CI bound to 1, an RR of at least ${fmt(eCi)} would suffice'}.'),
      notJustified: tr('Présenter une grande valeur E comme une preuve de causalité ; l\'utiliser à la place d\'un ajustement sur les facteurs de confusion connus.',
          'Presenting a large E-value as proof of causality; using it instead of adjusting for known confounders.'),
    ),
  );
}
