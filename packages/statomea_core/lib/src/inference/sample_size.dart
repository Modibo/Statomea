/// Calculs de taille d'échantillon.
///
/// - Estimation d'une proportion avec une précision donnée (Wald, avec
///   correction pour population finie facultative).
/// - Comparaison de deux proportions : formule de `power.prop.test` (R).
/// - Comparaison de deux moyennes : loi de Student non centrale, comme
///   `power.t.test` (R) ; fonction de répartition par l'algorithme AS 243
///   (Lenth 1989).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/special.dart';
import '../model/result.dart';
import '../prediction/performance.dart' show rileySampleSize;

/// P(T ≤ t) pour T ~ t non centrale (df, delta) — AS 243.
double noncentralTCdf(double t, double df, double delta) {
  if (delta == 0) return tCdf(t, df);
  var negdel = false;
  var tt = t, del = delta;
  if (t < 0) {
    negdel = true;
    tt = -t;
    del = -delta;
  }
  final x = tt * tt / (tt * tt + df);
  var tnc = 0.0;
  if (x > 0) {
    final lambda = del * del;
    var p = 0.5 * math.exp(-0.5 * lambda);
    var q = math.sqrt(2 / math.pi) * p * del;
    var s = 0.5 - p;
    if (s < 1e-7) s = -0.5 * _expm1(-0.5 * lambda);
    var a = 0.5;
    final b = 0.5 * df;
    final rxb = math.pow(1 - x, b).toDouble();
    final albeta = lnGamma(0.5) + lnGamma(b) - lnGamma(0.5 + b);
    var xodd = betaI(a, b, x);
    var godd = 2 * rxb * math.exp(a * math.log(x) - albeta);
    tnc = b * x;
    var xeven = tnc < 2.2e-16 ? tnc : 1 - rxb;
    var geven = tnc * rxb;
    tnc = p * xodd + q * xeven;
    for (var it = 1; it <= 5000; it++) {
      a += 1;
      xodd -= godd;
      xeven -= geven;
      godd *= x * (a + b - 1) / a;
      geven *= x * (a + b - 0.5) / (a + 0.5);
      p *= lambda / (2 * it);
      q *= lambda / (2 * it + 1);
      s -= p;
      tnc += p * xodd + q * xeven;
      final err = 2 * s * (xodd - godd);
      if (err.abs() < 1e-14 && it > 2) break;
    }
  }
  tnc += normalCdf(-del);
  if (negdel) return 1 - tnc;
  return math.min(1.0, math.max(0.0, tnc));
}

double _expm1(double x) => x.abs() < 1e-5 ? x + x * x / 2 + x * x * x / 6 : math.exp(x) - 1;

double _powerTwoMeans(double n, double delta, double sd, double alpha) {
  final df = 2 * (n - 1);
  final qu = tQuantile(1 - alpha / 2, df);
  return 1 - noncentralTCdf(qu, df, math.sqrt(n / 2) * delta / sd);
}

double _powerTwoProps(double n, double p1, double p2, double alpha) {
  final qu = normalQuantile(1 - alpha / 2);
  final d = (p1 - p2).abs();
  final q1 = 1 - p1, q2 = 1 - p2;
  return normalCdf((math.sqrt(n) * d - qu * math.sqrt((p1 + p2) * (q1 + q2) / 2)) /
      math.sqrt(p1 * q1 + p2 * q2));
}

double _solveN(double Function(double) power, double target) {
  var hi = 4.0;
  while (power(hi) < target) {
    hi *= 2;
    if (hi > 1e9) throw StatInputError('n_unreachable', tr('Puissance cible inatteignable.', 'Target power unreachable.'));
  }
  return brentRoot((n) => power(n) - target, 2, hi, tol: 1e-10);
}

AnalysisResult sampleSizeTwoMeans(
    {required double delta, required double sd, double alpha = 0.05, double power = 0.8, double dropout = 0}) {
  if (delta <= 0 || sd <= 0) {
    throw StatInputError('bad_param', tr("La différence à détecter et l'ÉT doivent être > 0.", 'The difference to detect and the SD must be > 0.'));
  }
  final n = _solveN((n) => _powerTwoMeans(n, delta, sd, alpha), power);
  final nInt = n.ceil();
  final nAdj = (nInt / (1 - dropout)).ceil();
  return AnalysisResult(
    methodId: 'sample_size_two_means',
    methodName: tr("Taille d'échantillon : comparaison de deux moyennes", 'Sample size: comparison of two means'),
    inputs: {'delta': delta, 'sd': sd, 'alpha': alpha, 'power': power, 'dropout': dropout},
    formula: tr('n par groupe tel que P(T′ > t(1−α/2 ; 2n−2)) = puissance, T′ ~ t non centrale de paramètre √(n/2)·Δ/σ (équivalent de power.t.test, test bilatéral).',
        'n per group such that P(T′ > t(1−α/2; 2n−2)) = power, T′ ~ non-central t with parameter √(n/2)·Δ/σ (equivalent to power.t.test, two-sided test).'),
    estimates: [Estimate(tr('n par groupe (exact, non arrondi)', 'n per group (exact, unrounded)'), n), Estimate(tr('n par groupe', 'n per group'), nInt.toDouble()),
      if (dropout > 0) Estimate(tr('n par groupe après perdus de vue (${fmtPct(dropout)})', 'n per group after loss to follow-up (${fmtPct(dropout)})'), nAdj.toDouble())],
    statistics: {'n_exact': n, 'n_per_group': nInt.toDouble(), 'n_total': 2.0 * (dropout > 0 ? nAdj : nInt)},
    checks: [
      Check('delta_justified', tr('Différence à détecter justifiée cliniquement', 'Difference to detect clinically justified'), CheckStatus.notAssessed,
          tr("Doit reposer sur une différence minimale cliniquement pertinente, non sur l'effet espéré.", 'Must rest on a minimal clinically important difference, not on the hoped-for effect.')),
      Check('sd_source', tr("ÉT issu d'une source documentée", 'SD from a documented source'), CheckStatus.notAssessed,
          tr('Un ÉT sous-estimé conduit à un essai sous-dimensionné.', 'An underestimated SD leads to an underpowered trial.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Critère principal quantitatif, deux groupes indépendants, test t bilatéral.', 'Quantitative primary outcome, two independent groups, two-sided t-test.'),
      whatItMeans: tr('$nInt sujets par groupe (${2 * nInt} au total) donnent une puissance de ${fmtPct(power, decimals: 0)} pour détecter une différence de ${fmt(delta)} (ÉT ${fmt(sd)}) au risque α = ${fmt(alpha)}.',
          '$nInt subjects per group (${2 * nInt} in total) give ${fmtPct(power, decimals: 0)} power to detect a difference of ${fmt(delta)} (SD ${fmt(sd)}) at α = ${fmt(alpha)}.'),
      notJustified: tr("Calculer la puissance a posteriori à partir de l'effet observé ; présenter ce nombre comme suffisant pour des analyses secondaires ou de sous-groupes.",
          'Computing post hoc power from the observed effect; presenting this number as sufficient for secondary or subgroup analyses.'),
    ),
  );
}

AnalysisResult sampleSizeTwoProportions(
    {required double p1, required double p2, double alpha = 0.05, double power = 0.8, double dropout = 0}) {
  if (p1 <= 0 || p1 >= 1 || p2 <= 0 || p2 >= 1 || p1 == p2) {
    throw StatInputError('bad_param', tr('Proportions attendues strictement entre 0 et 1, et différentes.', 'Expected proportions strictly between 0 and 1, and different.'));
  }
  final n = _solveN((n) => _powerTwoProps(n, p1, p2, alpha), power);
  final nInt = n.ceil();
  final nAdj = (nInt / (1 - dropout)).ceil();
  return AnalysisResult(
    methodId: 'sample_size_two_proportions',
    methodName: tr("Taille d'échantillon : comparaison de deux proportions", 'Sample size: comparison of two proportions'),
    inputs: {'p1': p1, 'p2': p2, 'alpha': alpha, 'power': power, 'dropout': dropout},
    formula: tr('Puissance = Φ{[√n|p1−p2| − z(1−α/2)√((p1+p2)(q1+q2)/2)] / √(p1q1+p2q2)}, résolue en n (équivalent de power.prop.test, sans correction de continuité).',
        'Power = Φ{[√n|p1−p2| − z(1−α/2)√((p1+p2)(q1+q2)/2)] / √(p1q1+p2q2)}, solved for n (equivalent to power.prop.test, without continuity correction).'),
    estimates: [Estimate(tr('n par groupe (exact, non arrondi)', 'n per group (exact, unrounded)'), n), Estimate(tr('n par groupe', 'n per group'), nInt.toDouble()),
      if (dropout > 0) Estimate(tr('n par groupe après perdus de vue', 'n per group after loss to follow-up'), nAdj.toDouble())],
    statistics: {'n_exact': n, 'n_per_group': nInt.toDouble()},
    alerts: [
      if (math.min(p1, p2) * nInt < 5)
        Alert('few_expected_events', Severity.caution,
            tr("Moins de 5 événements attendus dans un groupe : l'approximation normale est fragile ; vérifier par un calcul exact ou une simulation.",
                'Fewer than 5 expected events in a group: the normal approximation is fragile; check with an exact calculation or a simulation.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Critère principal binaire, deux groupes indépendants.', 'Binary primary outcome, two independent groups.'),
      whatItMeans: tr('$nInt sujets par groupe pour détecter ${fmtPct(p1)} vs ${fmtPct(p2)} avec une puissance de ${fmtPct(power, decimals: 0)} (α = ${fmt(alpha)}, bilatéral).',
          '$nInt subjects per group to detect ${fmtPct(p1)} vs ${fmtPct(p2)} with ${fmtPct(power, decimals: 0)} power (α = ${fmt(alpha)}, two-sided).'),
      notJustified: tr("Choisir p1 et p2 pour obtenir un effectif faisable plutôt qu'à partir de données.", 'Choosing p1 and p2 to obtain a feasible sample size rather than from data.'),
    ),
  );
}

/// n pour estimer une proportion avec une demi-largeur d'IC [precision].
AnalysisResult sampleSizeProportion(
    {required double expected, required double precision, double level = 0.95, int? population, double designEffect = 1}) {
  if (expected <= 0 || expected >= 1 || precision <= 0) {
    throw StatInputError('bad_param', tr('Proportion attendue entre 0 et 1, précision > 0.', 'Expected proportion between 0 and 1, precision > 0.'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  var n0 = z * z * expected * (1 - expected) / (precision * precision) * designEffect;
  var n = n0;
  if (population != null) n = n0 / (1 + (n0 - 1) / population);
  final nInt = n.ceil();
  return AnalysisResult(
    methodId: 'sample_size_proportion',
    methodName: tr("Taille d'échantillon : estimation d'une proportion", 'Sample size: estimating a proportion'),
    inputs: {'expected': expected, 'precision': precision, 'level': level, 'population': population, 'designEffect': designEffect},
    formula: tr('n0 = z²·p(1−p)/d² × effet de plan ; population finie N : n = n0/[1 + (n0−1)/N].', 'n0 = z²·p(1−p)/d² × design effect; finite population N: n = n0/[1 + (n0−1)/N].'),
    estimates: [Estimate(tr('n requis', 'n required'), nInt.toDouble()), Estimate(tr('n non arrondi', 'n unrounded'), n)],
    statistics: {'n': nInt.toDouble(), 'n_exact': n},
    alerts: [
      if (precision >= expected)
        Alert('precision_vs_p', Severity.serious,
            tr("La précision demandée est ≥ à la proportion attendue : l'IC pourrait inclure 0 ; pour une proportion rare, viser une précision relative (p. ex. d = p/4).",
                'The requested precision is ≥ the expected proportion: the CI could include 0; for a rare proportion, aim for a relative precision (e.g. d = p/4).')),
      if (expected * nInt < 10)
        Alert('few_events', Severity.caution,
            tr("Moins de 10 événements attendus : la formule normale est approximative ; l'IC final sera calculé par une méthode exacte ou de Wilson.",
                'Fewer than 10 expected events: the normal formula is approximate; the final CI will be computed by an exact or Wilson method.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Objectif descriptif : estimer une prévalence avec une précision fixée.', 'Descriptive aim: estimate a prevalence with a set precision.'),
      whatItMeans: tr('$nInt sujets donnent un IC à ${(level * 100).round()} % de demi-largeur ≈ ${fmtPct(precision)} si la proportion vaut ${fmtPct(expected)}${designEffect != 1 ? " (effet de plan ${fmt(designEffect)})" : ""}.',
          '$nInt subjects give a ${(level * 100).round()}% CI with half-width ≈ ${fmtPct(precision)} if the proportion is ${fmtPct(expected)}${designEffect != 1 ? " (design effect ${fmt(designEffect)})" : ""}.'),
      notJustified: tr("Utiliser ce calcul pour une comparaison de groupes ; ignorer l'effet de plan d'un sondage en grappes.", 'Using this calculation for a group comparison; ignoring the design effect of a cluster survey.'),
    ),
  );
}

/// n pour mettre en évidence une corrélation [r] (test bilatéral, transformation z de Fisher) :
/// n = ((z₁₋α/2 + z₁₋β) / atanh r)² + 3, majoré pour les pertes : n / (1 − perdus).
AnalysisResult sampleSizeCorrelation({required double r, double alpha = 0.05, double power = 0.8, double dropout = 0}) {
  if (r == 0 || r.abs() >= 1 || alpha <= 0 || alpha >= 1 || power <= 0 || power >= 1 || dropout < 0 || dropout >= 1) {
    throw StatInputError('bad_param', tr('Corrélation entre −1 et 1 (non nulle), α et puissance entre 0 et 1, perdus de vue entre 0 et 1.', 'Correlation between −1 and 1 (non-zero), α and power between 0 and 1, losses between 0 and 1.'));
  }
  final za = normalQuantile(1 - alpha / 2), zb = normalQuantile(power);
  final z = 0.5 * math.log((1 + r.abs()) / (1 - r.abs()));
  final n = math.pow((za + zb) / z, 2) + 3;
  final nAdj = n / (1 - dropout);
  final nInt = (nAdj - 1e-9).ceil();
  return AnalysisResult(
    methodId: 'sample_size_correlation',
    methodName: tr("Taille d'échantillon : mettre en évidence une corrélation", 'Sample size: detecting a correlation'),
    inputs: {'r': r, 'alpha': alpha, 'power': power, 'dropout': dropout},
    formula: tr('n = ((z₁₋α/2 + z₁₋β) / atanh r)² + 3 (transformation de Fisher) ; avec pertes : n / (1 − perdus).', 'n = ((z₁₋α/2 + z₁₋β) / atanh r)² + 3 (Fisher transformation); with losses: n / (1 − losses).'),
    estimates: [Estimate(tr('n requis', 'n required'), nInt.toDouble()), Estimate(tr('n non arrondi (sans pertes)', 'n unrounded (no losses)'), n.toDouble())],
    statistics: {'n': nInt.toDouble(), 'n_exact': n.toDouble()},
    alerts: [
      if (r.abs() >= 0.5)
        Alert('large_r', Severity.caution,
            tr('Une corrélation attendue ≥ 0,5 est forte : un effectif calculé sur une valeur optimiste manquera de puissance si la corrélation réelle est plus faible.',
                'An expected correlation ≥ 0.5 is strong: a sample size based on an optimistic value will lack power if the true correlation is weaker.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Objectif : montrer qu\'une corrélation au moins égale à ${fmt(r)} existe (test bilatéral).', 'Aim: show that a correlation of at least ${fmt(r)} exists (two-sided test).'),
      whatItMeans: tr('$nInt sujets donnent une puissance de ${fmtPct(power)} pour mettre en évidence r = ${fmt(r)} au seuil α = ${fmt(alpha)}${dropout > 0 ? ' avec ${fmtPct(dropout)} de pertes' : ''}.',
          '$nInt subjects give ${fmtPct(power)} power to detect r = ${fmt(r)} at α = ${fmt(alpha)}${dropout > 0 ? ' with ${fmtPct(dropout)} losses' : ''}.'),
      notJustified: tr('Choisir r d\'après ce qui rend l\'effectif faisable plutôt que la plus petite corrélation cliniquement pertinente ; utiliser une corrélation pour juger l\'accord entre deux méthodes.',
          'Choosing r from what makes the sample size feasible rather than the smallest clinically relevant correlation; using a correlation to judge agreement between two methods.'),
    ),
  );
}

/// Effectif minimal d'un modèle de prédiction à issue binaire (Riley et al., critères i à iii, comme pmsampsize),
/// majoré pour les pertes : n / (1 − perdus).
AnalysisResult sampleSizePredictionModel(
    {required int parameters, required double prevalence, required double r2CoxSnell, double shrinkage = 0.9, double dropout = 0}) {
  if (parameters < 1 || prevalence <= 0 || prevalence >= 1 || r2CoxSnell <= 0 || shrinkage <= 0 || shrinkage >= 1 || r2CoxSnell >= shrinkage || dropout < 0 || dropout >= 1) {
    throw StatInputError('bad_param', tr('Paramètres ≥ 1 ; prévalence entre 0 et 1 ; 0 < R² de Cox-Snell < facteur de rétrécissement < 1 ; perdus de vue entre 0 et 1.', 'Parameters ≥ 1; prevalence between 0 and 1; 0 < Cox-Snell R² < shrinkage factor < 1; losses between 0 and 1.'));
  }
  final rl = rileySampleSize(parameters: parameters, prevalence: prevalence, r2CoxSnell: r2CoxSnell, shrinkage: shrinkage);
  final need = rl.n.ceil();
  final nInt = (need / (1 - dropout) - 1e-9).ceil();
  final epp = need * prevalence / parameters;
  final lnLnull = prevalence * math.log(prevalence) + (1 - prevalence) * math.log(1 - prevalence);
  final maxR2 = 1 - math.exp(2 * lnLnull);
  return AnalysisResult(
    methodId: 'sample_size_prediction',
    methodName: tr("Taille d'échantillon : modèle de prédiction (Riley)", 'Sample size: prediction model (Riley)'),
    inputs: {'parameters': parameters, 'prevalence': prevalence, 'r2CoxSnell': r2CoxSnell, 'shrinkage': shrinkage, 'dropout': dropout},
    formula: tr('(i) rétrécissement : n = p / ((S − 1) ln(1 − R²/S)) ; (ii) optimisme du R² de Nagelkerke ≤ 0,05 ; (iii) intercept : n = (1,96/0,05)² φ(1 − φ) ; n = max(i, ii, iii).',
        '(i) shrinkage: n = p / ((S − 1) ln(1 − R²/S)); (ii) Nagelkerke R² optimism ≤ 0.05; (iii) intercept: n = (1.96/0.05)² φ(1 − φ); n = max(i, ii, iii).'),
    estimates: [
      Estimate(tr('n requis', 'n required'), nInt.toDouble()),
      Estimate(tr('critère (i)', 'criterion (i)'), rl.n1.ceilToDouble()),
      Estimate(tr('critère (ii)', 'criterion (ii)'), rl.n2.ceilToDouble()),
      Estimate(tr('critère (iii)', 'criterion (iii)'), rl.n3.ceilToDouble()),
      Estimate(tr('événements par paramètre', 'events per parameter'), epp),
    ],
    statistics: {'n': nInt.toDouble(), 'n1': rl.n1, 'n2': rl.n2, 'n3': rl.n3, 'events': need * prevalence, 'epp': epp},
    alerts: [
      if (r2CoxSnell > 0.75 * maxR2)
        Alert('r2_high', Severity.caution,
            tr('R² de Cox-Snell attendu proche de son maximum (${fmt(maxR2)} pour cette prévalence) : hypothèse très optimiste.', 'Expected Cox-Snell R² close to its maximum (${fmt(maxR2)} for this prevalence): a very optimistic assumption.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Objectif prédictif : assez de sujets pour limiter le sur-ajustement (rétrécissement ≤ ${fmtPct(1 - shrinkage)}), l\'optimisme et estimer précisément le risque moyen.',
          'Predictive aim: enough subjects to limit overfitting (shrinkage ≤ ${fmtPct(1 - shrinkage)}), optimism, and to estimate the average risk precisely.'),
      whatItMeans: tr('Au moins $need sujets analysables (${fmt(need * prevalence)} événements, ${fmt(epp)} par paramètre)${dropout > 0 ? ', soit $nInt à inclure avec ${fmtPct(dropout)} de pertes' : ''}.',
          'At least $need analysable subjects (${fmt(need * prevalence)} events, ${fmt(epp)} per parameter)${dropout > 0 ? ', i.e. $nInt to include with ${fmtPct(dropout)} losses' : ''}.'),
      notJustified: tr('Compter les variables plutôt que les paramètres (une variable à k modalités ou une spline en coûte plusieurs) ; se fier à la seule règle des 10 événements par variable.',
          'Counting variables rather than parameters (a k-level variable or a spline costs several); relying only on the 10 events-per-variable rule.'),
    ),
  );
}
