/// Intervalles de confiance d'une proportion et d'une différence de
/// proportions.
///
/// Wilson (1927) ; Clopper & Pearson (1934) ; règle de trois (Hanley &
/// Lippman-Hand 1983) ; Newcombe (1998) méthode 10 pour la différence.
library;

import 'dart:math' as math;

import '../math/distributions.dart';
import '../i18n.dart';
import '../model/result.dart';
import 'common.dart';

({double lower, double upper}) wilsonCi(int x, int n, {double level = 0.95}) {
  final z = normalQuantile(1 - (1 - level) / 2);
  final p = x / n;
  final denom = 1 + z * z / n;
  final centre = (p + z * z / (2 * n)) / denom;
  final half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom;
  return (lower: math.max(0.0, centre - half), upper: math.min(1.0, centre + half));
}

({double lower, double upper}) clopperPearsonCi(int x, int n, {double level = 0.95}) {
  final a = (1 - level) / 2;
  return (
    lower: x == 0 ? 0.0 : betaQuantile(a, x.toDouble(), (n - x + 1).toDouble()),
    upper: x == n ? 1.0 : betaQuantile(1 - a, (x + 1).toDouble(), (n - x).toDouble()),
  );
}

/// Estimation d'une proportion (prévalence, fréquence) avec IC de Wilson et
/// IC exact de Clopper-Pearson.
AnalysisResult proportionCi(int events, int n, {double level = 0.95, String? label, double? p0}) {
  label ??= 'Proportion';
  if (n <= 0) throw StatInputError('n_zero', tr('Le dénominateur doit être strictement positif.', 'The denominator must be strictly positive.'));
  if (events < 0 || events > n) {
    throw StatInputError('events_out_of_range',
        tr("Le nombre d'événements ($events) doit être compris entre 0 et n ($n).", 'The number of events ($events) must be between 0 and n ($n).'));
  }
  final p = events / n;
  final w = wilsonCi(events, n, level: level);
  final cp = clopperPearsonCi(events, n, level: level);
  final alerts = <Alert>[];
  final stats = <String, double>{'events': events.toDouble(), 'n': n.toDouble()};
  final estimates = <Estimate>[
    Estimate('$label (Wilson)', p, lower: w.lower, upper: w.upper, level: level),
    Estimate(tr('$label (exact de Clopper-Pearson)', '$label (Clopper-Pearson exact)'), p, lower: cp.lower, upper: cp.upper, level: level),
  ];
  final rare = events < 5 || n - events < 5;
  if (events == 0) {
    final rule3 = 3 / n;
    estimates.add(Estimate(tr('Borne supérieure unilatérale 95 % (règle de trois ≈ 3/n)', 'One-sided 95% upper bound (rule of three ≈ 3/n)'), rule3));
    stats['rule_of_three'] = rule3;
    alerts.add(Alert('zero_events', Severity.caution,
        tr("Aucun événement observé sur $n : la proportion vraie n'est pas nulle pour autant. Elle est compatible avec des valeurs jusqu'à "
                '${fmtPct(cp.upper, decimals: 2)} (borne exacte bilatérale) ou ≈ ${fmtPct(rule3, decimals: 2)} (règle de trois).',
            'No event observed out of $n: the true proportion is not zero for all that. It is compatible with values up to '
                '${fmtPct(cp.upper, decimals: 2)} (two-sided exact bound) or ≈ ${fmtPct(rule3, decimals: 2)} (rule of three).'),
        suggestion: tr('Rapporter « 0/$n » avec la borne supérieure, jamais « 0 % » seul.', 'Report "0/$n" with the upper bound, never "0%" alone.')));
  } else if (rare) {
    alerts.add(Alert('rare_events', Severity.caution,
        tr("Peu d'événements ($events/$n) : l'approximation normale (Wald) est inadaptée ; l'IC exact ou de Wilson est retenu.",
            'Few events ($events/$n): the normal (Wald) approximation is unsuitable; the exact or Wilson CI is used.')));
  }
  if (p0 != null) {
    final pv = binomialTestTwoSided(events, n, p0);
    stats['p_exact_vs_p0'] = pv;
    stats['p0'] = p0;
  }
  return AnalysisResult(
    methodId: 'proportion_ci',
    methodName: tr("IC d'une proportion", 'CI of a proportion'),
    inputs: {'events': events, 'n': n, 'level': level, 'p0': ?p0},
    formula: tr('p̂ = x/n. Wilson : [p̂ + z²/2n ± z√(p̂(1−p̂)/n + z²/4n²)] / (1 + z²/n). Clopper-Pearson : bornes = quantiles Bêta(α/2 ; x, n−x+1) et Bêta(1−α/2 ; x+1, n−x).',
        'p̂ = x/n. Wilson: [p̂ + z²/2n ± z√(p̂(1−p̂)/n + z²/4n²)] / (1 + z²/n). Clopper-Pearson: bounds = Beta quantiles (α/2; x, n−x+1) and (1−α/2; x+1, n−x).'),
    estimates: estimates,
    statistics: stats,
    checks: [
      Check('independence', tr('Observations indépendantes (un individu compté une fois)', 'Independent observations (each individual counted once)'),
          CheckStatus.notAssessed,
          tr("Non vérifiable par le calcul : à confirmer par le plan d'échantillonnage (grappes, ménages, prélèvements répétés).",
              'Cannot be checked by calculation: confirm from the sampling design (clusters, households, repeated samples).')),
      Check('representative', tr('Échantillon représentatif de la population cible', 'Sample representative of the target population'), CheckStatus.notAssessed,
          tr("Condition de plan d'étude ; un IC ne corrige pas un biais de sélection.", 'A design condition; a CI does not correct selection bias.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Estimation', 'Estimate'), [tr('Méthode', 'Method'), 'x/n', tr('Estimation', 'Estimate'), tr('IC ${(level * 100).round()} %', '${(level * 100).round()}% CI')], [
        ['Wilson', '$events/$n', fmtPct(p, decimals: 2), '${fmtPct(w.lower, decimals: 2)} – ${fmtPct(w.upper, decimals: 2)}'],
        ['Clopper-Pearson', '$events/$n', fmtPct(p, decimals: 2), '${fmtPct(cp.lower, decimals: 2)} – ${fmtPct(cp.upper, decimals: 2)}'],
      ])
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Une proportion estimée sur un échantillon s'accompagne d'un IC. Les IC de Wilson et exacts restent valides avec peu d'événements, contrairement à l'IC de Wald (p̂ ± 1,96√(p̂(1−p̂)/n)).",
          'A proportion estimated from a sample comes with a CI. Wilson and exact CIs remain valid with few events, unlike the Wald CI (p̂ ± 1.96√(p̂(1−p̂)/n)).'),
      whatItMeans: tr(
          'Proportion observée ${fmtPct(p, decimals: 2)} ($events/$n). Les valeurs de la proportion dans la population compatibles avec les données vont de '
              '${fmtPct(cp.lower, decimals: 2)} à ${fmtPct(cp.upper, decimals: 2)} (IC exact).',
          'Observed proportion ${fmtPct(p, decimals: 2)} ($events/$n). Population values compatible with the data range from '
              '${fmtPct(cp.lower, decimals: 2)} to ${fmtPct(cp.upper, decimals: 2)} (exact CI).'),
      notJustified: tr(
          "Généraliser à une population autre que celle échantillonnée ; présenter une prévalence d'échantillon de convenance (donneurs, consultants) comme une prévalence en population générale ; conclure à une proportion « nulle » si aucun cas n'est vu.",
          'Generalizing to a population other than the one sampled; presenting the prevalence of a convenience sample (donors, outpatients) as a general-population prevalence; concluding that a proportion is "zero" when no case is observed.'),
    ),
  );
}

/// IC hybride de Newcombe (méthode 10) pour p1 − p2, groupes indépendants.
({double lower, double upper}) newcombeDiffCi(int x1, int n1, int x2, int n2,
    {double level = 0.95}) {
  final p1 = x1 / n1, p2 = x2 / n2;
  final a = wilsonCi(x1, n1, level: level);
  final b = wilsonCi(x2, n2, level: level);
  final d = p1 - p2;
  final lower = d - math.sqrt(math.pow(p1 - a.lower, 2) + math.pow(b.upper - p2, 2));
  final upper = d + math.sqrt(math.pow(a.upper - p1, 2) + math.pow(p2 - b.lower, 2));
  return (lower: lower, upper: upper);
}

/// Comparaison de deux proportions indépendantes : différence (Newcombe).
AnalysisResult proportionDifference(int x1, int n1, int x2, int n2, {double level = 0.95, String? group1, String? group2, double? margin}) {
  group1 ??= tr('Groupe 1', 'Group 1');
  group2 ??= tr('Groupe 2', 'Group 2');
  if (n1 <= 0 || n2 <= 0) throw StatInputError('n_zero', tr('Effectifs de groupe nuls.', 'Empty group(s).'));
  final d = x1 / n1 - x2 / n2;
  final ci = newcombeDiffCi(x1, n1, x2, n2, level: level);
  final e = Estimate(tr('Différence de proportions ($group1 − $group2)', 'Difference in proportions ($group1 − $group2)'), d,
      lower: ci.lower, upper: ci.upper, level: level);
  return AnalysisResult(
    methodId: 'proportion_difference',
    methodName: tr('Différence de deux proportions (Newcombe)', 'Difference between two proportions (Newcombe)'),
    inputs: {'x1': x1, 'n1': n1, 'x2': x2, 'n2': n2, 'level': level},
    formula: tr('d = p̂1 − p̂2 ; IC = d − √[(p̂1 − l1)² + (u2 − p̂2)²] à d + √[(u1 − p̂1)² + (p̂2 − l2)²], (l, u) = bornes de Wilson de chaque proportion.',
        'd = p̂1 − p̂2; CI = d − √[(p̂1 − l1)² + (u2 − p̂2)²] to d + √[(u1 − p̂1)² + (p̂2 − l2)²], (l, u) = Wilson bounds of each proportion.'),
    estimates: [e],
    statistics: {'p1': x1 / n1, 'p2': x2 / n2},
    interpretation: Interpretation(
      whyThisMethod: tr('Différence absolue entre deux proportions indépendantes ; la méthode de Newcombe garde une couverture correcte avec des proportions extrêmes.',
          'Absolute difference between two independent proportions; the Newcombe method keeps correct coverage with extreme proportions.'),
      whatItMeans: tr('${fmtPct(x1 / n1)} vs ${fmtPct(x2 / n2)}, différence ${fmtPct(d)} (IC ${fmtPct(ci.lower)} à ${fmtPct(ci.upper)}). ',
              '${fmtPct(x1 / n1)} vs ${fmtPct(x2 / n2)}, difference ${fmtPct(d)} (CI ${fmtPct(ci.lower)} to ${fmtPct(ci.upper)}). ') +
          readInterval(e, nullValue: 0, margin: margin),
      notJustified: tr('Attribuer la différence au facteur qui distingue les groupes sans plan randomisé ni ajustement sur les facteurs de confusion.',
          'Attributing the difference to the factor that distinguishes the groups without randomization or adjustment for confounders.'),
    ),
  );
}
