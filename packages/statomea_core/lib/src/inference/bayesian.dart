/// Bayésien d'introduction.
///  - proportion : a priori Bêta(a, b) conjugué, a posteriori Bêta(a + x, b + n − x) ; intervalle de crédibilité à
///    queues égales, probabilité que la proportion dépasse un seuil ;
///  - effet publié (approche de Spiegelhalter) : vraisemblance normale de l'estimation (échelle log pour un rapport,
///    ES déduit de l'IC à 95 %), a priori normal sceptique, enthousiaste ou vague, a posteriori normal ; probabilité
///    d'un bénéfice et d'un effet au moins égal à la cible clinique.
/// Validé contre validation/r/57_bayesien.R (stats : qbeta, pbeta, qnorm, pnorm).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/special.dart';
import '../model/result.dart';

enum BetaPrior { uniform, jeffreys, informative }

AnalysisResult bayesProportion(int x, int n, {BetaPrior prior = BetaPrior.uniform, double priorMean = 0.5, double priorWeight = 2, double? threshold, double level = 0.95}) {
  if (n <= 0 || x < 0 || x > n) throw StatInputError('bayes_counts', tr('Effectifs invalides (0 ≤ x ≤ n, n > 0).', 'Invalid counts (0 ≤ x ≤ n, n > 0).'));
  if (prior == BetaPrior.informative && (priorMean <= 0 || priorMean >= 1 || priorWeight <= 0)) {
    throw StatInputError('bayes_prior', tr('A priori informatif : moyenne entre 0 et 1 et poids (effectif équivalent) > 0.', 'Informative prior: mean between 0 and 1 and weight (equivalent sample size) > 0.'));
  }
  final (a0, b0) = switch (prior) {
    BetaPrior.uniform => (1.0, 1.0),
    BetaPrior.jeffreys => (0.5, 0.5),
    BetaPrior.informative => (priorMean * priorWeight, (1 - priorMean) * priorWeight),
  };
  final a = a0 + x, b = b0 + n - x;
  final mean = a / (a + b), median = betaQuantile(0.5, a, b);
  final mode = a > 1 && b > 1 ? (a - 1) / (a + b - 2) : double.nan;
  final lo = betaQuantile((1 - level) / 2, a, b), hi = betaQuantile(1 - (1 - level) / 2, a, b);
  final pGt = threshold == null ? null : betaIComplement(a, b, threshold);
  final pct = (level * 100).round();
  final priorLabel = switch (prior) {
    BetaPrior.uniform => tr('uniforme Bêta(1 ; 1)', 'uniform Beta(1, 1)'),
    BetaPrior.jeffreys => tr('de Jeffreys Bêta(0,5 ; 0,5)', 'Jeffreys Beta(0.5, 0.5)'),
    BetaPrior.informative => tr('informatif Bêta(${fmt(a0)} ; ${fmt(b0)}) (moyenne ${fmtPct(priorMean)}, poids ${fmt(priorWeight)} sujets)', 'informative Beta(${fmt(a0)}, ${fmt(b0)}) (mean ${fmtPct(priorMean)}, weight ${fmt(priorWeight)} subjects)'),
  };
  // Densités a priori et a posteriori (figure).
  final grid = [for (var k = 1; k < 200; k++) k / 200];
  double dens(double p, double aa, double bb) => math.exp((aa - 1) * math.log(p) + (bb - 1) * math.log(1 - p) - (lnGamma(aa) + lnGamma(bb) - lnGamma(aa + bb)));
  return AnalysisResult(
    methodId: 'bayes_proportion',
    methodName: tr('Proportion : analyse bayésienne (bêta-binomiale)', 'Proportion: Bayesian analysis (beta-binomial)'),
    inputs: {'x': x, 'n': n, 'prior': prior.name, 'priorMean': priorMean, 'priorWeight': priorWeight, 'threshold': ?threshold, 'level': level},
    formula: tr('A priori Bêta(a, b) ; vraisemblance binomiale ; a posteriori Bêta(a + x, b + n − x). Intervalle de crédibilité : quantiles ${(1 - level) / 2} et ${1 - (1 - level) / 2} de la loi a posteriori ; P(p > seuil) = 1 − F(seuil).',
        'Prior Beta(a, b); binomial likelihood; posterior Beta(a + x, b + n − x). Credible interval: ${(1 - level) / 2} and ${1 - (1 - level) / 2} quantiles of the posterior; P(p > threshold) = 1 − F(threshold).'),
    estimates: [
      Estimate(tr('Proportion (moyenne a posteriori)', 'Proportion (posterior mean)'), mean, lower: lo, upper: hi, level: level),
      if (pGt != null) Estimate(tr('P(proportion > ${fmtPct(threshold!)})', 'P(proportion > ${fmtPct(threshold)})'), pGt),
    ],
    statistics: {'post_a': a, 'post_b': b, 'mean': mean, 'median': median, 'mode': ?(mode.isNaN ? null : mode), 'lower': lo, 'upper': hi, 'p_gt': ?pGt},
    checks: [
      Check('prior_justified', tr('A priori justifié et fixé avant de voir les données', 'Prior justified and set before seeing the data'), CheckStatus.notAssessed,
          tr('Montrer l\'effet du choix de l\'a priori (analyse de sensibilité : uniforme, Jeffreys, informatif).', 'Show the effect of the prior choice (sensitivity analysis: uniform, Jeffreys, informative).')),
    ],
    tables: [
      ResultTable(tr('Loi a posteriori (a priori $priorLabel)', 'Posterior distribution ($priorLabel prior)'), [tr('Résumé', 'Summary'), tr('Valeur', 'Value')], [
        [tr('Loi', 'Distribution'), tr('Bêta(${fmt(a)} ; ${fmt(b)})', 'Beta(${fmt(a)}, ${fmt(b)})')],
        [tr('Moyenne', 'Mean'), fmtPct(mean)],
        [tr('Médiane', 'Median'), fmtPct(median)],
        if (!mode.isNaN) [tr('Mode', 'Mode'), fmtPct(mode)],
        [tr('Intervalle de crédibilité à $pct %', '$pct% credible interval'), '${fmtPct(lo)} – ${fmtPct(hi)}'],
        if (pGt != null) [tr('P(proportion > ${fmtPct(threshold!)})', 'P(proportion > ${fmtPct(threshold)})'), fmt(pGt, digits: 3)],
      ]),
    ],
    figures: {
      'bayes': {
        'x': grid,
        'prior': [for (final p in grid) dens(p, a0, b0)],
        'posterior': [for (final p in grid) dens(p, a, b)],
        'xLabel': tr('Proportion', 'Proportion'),
        'lower': lo,
        'upper': hi,
        'threshold': ?threshold,
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr('L\'approche bayésienne combine une connaissance préalable (a priori) et les données pour donner une distribution de la proportion, d\'où des probabilités directement interprétables.',
          'The Bayesian approach combines prior knowledge and the data into a distribution of the proportion, giving directly interpretable probabilities.'),
      whatItMeans: tr(
          'Avec $x événement(s) sur $n et un a priori $priorLabel, la proportion a $pct % de probabilité de se trouver entre ${fmtPct(lo)} et ${fmtPct(hi)} (moyenne ${fmtPct(mean)}).${pGt == null ? '' : ' Probabilité qu\'elle dépasse ${fmtPct(threshold!)} : ${fmt(pGt, digits: 2)}.'}',
          'With $x event(s) out of $n and a $priorLabel prior, the proportion has a $pct% probability of lying between ${fmtPct(lo)} and ${fmtPct(hi)} (mean ${fmtPct(mean)}).${pGt == null ? '' : ' Probability that it exceeds ${fmtPct(threshold!)}: ${fmt(pGt, digits: 2)}.'}'),
      notJustified: tr('Choisir l\'a priori après avoir vu les données ; présenter un a priori informatif sans le justifier ni montrer l\'analyse avec un a priori vague.',
          'Choosing the prior after seeing the data; presenting an informative prior without justifying it or showing the analysis with a vague prior.'),
    ),
  );
}

enum NormalPrior { sceptical, enthusiastic, vague }

/// Réinterprétation bayésienne d'un effet publié. [ratio] : RR, OR ou HR (échelle log ; bénéfice si < 1) ; sinon
/// différence (bénéfice si < 0 quand [lowerIsBetter], > 0 sinon). [target] : effet cliniquement important (même échelle
/// que l'estimation). A priori sceptique : centré sur l'absence d'effet, 5 % de probabilité de dépasser la cible ;
/// enthousiaste : même largeur, centré sur la cible ; vague : écart-type 10 (échelle log) ou 10 × l'ES.
AnalysisResult bayesEffect(double estimate, double lower, double upper,
    {bool ratio = true, required double target, NormalPrior prior = NormalPrior.sceptical, bool lowerIsBetter = true, double level = 0.95, String label = ''}) {
  if (ratio && (estimate <= 0 || lower <= 0 || upper <= 0 || target <= 0)) throw StatInputError('bayes_ratio', tr('Un rapport et ses bornes doivent être > 0.', 'A ratio and its bounds must be > 0.'));
  if (!(lower < estimate && estimate < upper)) throw StatInputError('bayes_ci', tr('L\'estimation doit être comprise dans son IC.', 'The estimate must lie within its CI.'));
  double tf(double v) => ratio ? math.log(v) : v;
  double back(double v) => ratio ? math.exp(v) : v;
  final th = tf(estimate), se = (tf(upper) - tf(lower)) / (2 * normalQuantile(0.975));
  final null0 = ratio ? 0.0 : 0.0, tgt = tf(target);
  if ((tgt - null0).abs() < 1e-12) throw StatInputError('bayes_target', tr('La cible doit différer de l\'absence d\'effet.', 'The target must differ from no effect.'));
  final tauSk = (tgt - null0).abs() / normalQuantile(0.95);
  final (mu0, tau) = switch (prior) {
    NormalPrior.sceptical => (null0, tauSk),
    NormalPrior.enthusiastic => (tgt, tauSk),
    NormalPrior.vague => (null0, ratio ? 10.0 : 10 * se),
  };
  final prec = 1 / (tau * tau) + 1 / (se * se);
  final m = (mu0 / (tau * tau) + th / (se * se)) / prec, s = math.sqrt(1 / prec);
  final z = normalQuantile(1 - (1 - level) / 2);
  final lo = back(m - z * s), hi = back(m + z * s);
  final benefitBelow = ratio || lowerIsBetter;
  final pBenefit = benefitBelow ? normalCdf((null0 - m) / s) : 1 - normalCdf((null0 - m) / s);
  final pTarget = benefitBelow ? normalCdf((tgt - m) / s) : 1 - normalCdf((tgt - m) / s);
  final pct = (level * 100).round();
  final priorLabel = switch (prior) {
    NormalPrior.sceptical => tr('sceptique (centré sur l\'absence d\'effet, 5 % de chances d\'atteindre la cible)', 'sceptical (centred on no effect, 5% chance of reaching the target)'),
    NormalPrior.enthusiastic => tr('enthousiaste (centré sur la cible)', 'enthusiastic (centred on the target)'),
    NormalPrior.vague => tr('vague', 'vague'),
  };
  final name = label.isEmpty ? (ratio ? tr('Rapport', 'Ratio') : tr('Différence', 'Difference')) : label;
  final grid = [for (var k = 0; k <= 200; k++) m - 5 * math.max(s, se) + k * (10 * math.max(s, se) / 200)];
  double dn(double v, double mu, double sd) => math.exp(-0.5 * math.pow((v - mu) / sd, 2)) / (sd * math.sqrt(2 * math.pi));
  return AnalysisResult(
    methodId: 'bayes_effect',
    methodName: tr('Réinterprétation bayésienne d\'un effet (a priori $priorLabel)', 'Bayesian reinterpretation of an effect ($priorLabel prior)'),
    inputs: {'estimate': estimate, 'lower': lower, 'upper': upper, 'ratio': ratio, 'target': target, 'prior': prior.name, 'level': level},
    formula: tr('θ̂ = ${ratio ? 'log(estimation)' : 'estimation'}, ES = (borne sup − borne inf)/(2 × 1,96) ; a priori N(μ₀, τ²) ; a posteriori N(m, s²), 1/s² = 1/τ² + 1/ES², m = s²(μ₀/τ² + θ̂/ES²). Sceptique : μ₀ = 0, τ = |cible|/1,645.',
        'θ̂ = ${ratio ? 'log(estimate)' : 'estimate'}, SE = (upper − lower)/(2 × 1.96); prior N(μ₀, τ²); posterior N(m, s²), 1/s² = 1/τ² + 1/SE², m = s²(μ₀/τ² + θ̂/SE²). Sceptical: μ₀ = 0, τ = |target|/1.645.'),
    estimates: [
      Estimate(tr('$name a posteriori', 'Posterior $name'), back(m), lower: lo, upper: hi, level: level),
      Estimate(tr('P(bénéfice)', 'P(benefit)'), pBenefit),
      Estimate(tr('P(effet au moins égal à la cible ${fmt(target)})', 'P(effect at least the target ${fmt(target)})'), pTarget),
    ],
    statistics: {'theta': th, 'se': se, 'prior_mean': mu0, 'prior_sd': tau, 'post_mean': m, 'post_sd': s, 'lower': lo, 'upper': hi, 'p_benefit': pBenefit, 'p_target': pTarget},
    checks: [
      Check('prior_justified', tr('A priori justifié et fixé avant de voir les données', 'Prior justified and set before seeing the data'), CheckStatus.notAssessed,
          tr('Présenter côte à côte les a priori sceptique, enthousiaste et vague : une conclusion robuste ne dépend pas du choix.', 'Present sceptical, enthusiastic and vague priors side by side: a robust conclusion does not depend on the choice.')),
      Check('normal_approx', tr('Approximation normale de la vraisemblance', 'Normal approximation of the likelihood'), CheckStatus.notAssessed,
          tr('ES déduit d\'un IC symétrique sur l\'échelle ${ratio ? 'log' : 'd\'origine'} ; inadapté aux très petits essais.', 'SE derived from a CI symmetric on the ${ratio ? 'log' : 'original'} scale; unsuitable for very small trials.')),
    ],
    tables: [
      ResultTable(tr('A priori, vraisemblance, a posteriori', 'Prior, likelihood, posterior'), ['', tr('Centre', 'Centre'), tr('IC / ICr $pct %', '$pct% CI / CrI')], [
        [tr('A priori', 'Prior'), fmt(back(mu0)), '${fmt(back(mu0 - z * tau))} – ${fmt(back(mu0 + z * tau))}'],
        [tr('Données (vraisemblance)', 'Data (likelihood)'), fmt(estimate), '${fmt(lower)} – ${fmt(upper)}'],
        [tr('A posteriori', 'Posterior'), fmt(back(m)), '${fmt(lo)} – ${fmt(hi)}'],
      ]),
    ],
    figures: {
      'bayes': {
        'x': [for (final v in grid) back(v)],
        'prior': [for (final v in grid) dn(v, mu0, tau)],
        'likelihood': [for (final v in grid) dn(v, th, se)],
        'posterior': [for (final v in grid) dn(v, m, s)],
        'xLabel': name,
        'lower': lo,
        'upper': hi,
        'log': ratio,
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr('Un résultat « significatif » ne dit pas quelle est la probabilité d\'un bénéfice cliniquement important ; l\'analyse bayésienne la donne, en rendant explicite la position de départ (sceptique ou enthousiaste).',
          'A "significant" result does not say what the probability of a clinically important benefit is; the Bayesian analysis gives it, making the starting position (sceptical or enthusiastic) explicit.'),
      whatItMeans: tr('Avec un a priori $priorLabel : ${name.toLowerCase()} a posteriori ${fmt(back(m))} (ICr $pct % ${fmt(lo)} à ${fmt(hi)}) ; probabilité d\'un bénéfice ${fmt(pBenefit, digits: 2)}, d\'un effet au moins égal à ${fmt(target)} : ${fmt(pTarget, digits: 2)}.',
          'With a $priorLabel prior: posterior ${name.toLowerCase()} ${fmt(back(m))} ($pct% CrI ${fmt(lo)} to ${fmt(hi)}); probability of benefit ${fmt(pBenefit, digits: 2)}, of an effect at least ${fmt(target)}: ${fmt(pTarget, digits: 2)}.'),
      notJustified: tr('Présenter une seule analyse avec un a priori choisi pour obtenir la conclusion voulue ; confondre intervalle de crédibilité et intervalle de confiance.',
          'Presenting a single analysis with a prior chosen to obtain the desired conclusion; confusing a credible interval with a confidence interval.'),
    ),
  );
}
