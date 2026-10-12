/// Randomisation mendélienne à partir de statistiques résumées : pour chaque variant instrumental, association avec
/// l'exposition (βX, se_X) et avec l'issue (βY, se_Y). Méthodes et réglages par défaut de MendelianRandomization 0.9 :
///  - IVW, pondération simple (poids 1/se_Y²) : régression de βY sur βX sans constante ; effets aléatoires
///    multiplicatifs (ES / min(σ̂, 1)) dès 4 variants, effets fixes (ES / σ̂) sinon ; hétérogénéité Q = (k − 1)·σ̂² ;
///  - MR-Egger : variants orientés (βX > 0), régression pondérée avec constante ; ES × max(1, σ̂) ; l'intercept mesure la
///    pléiotropie directionnelle ; Q de Rücker ; I²_GX (dilution si < 0,9) ;
///  - médiane pondérée : rapports βY/βX, poids (βX/se_Y)², ES par bootstrap paramétrique (poids fixes) ;
///  - loi normale pour les IC et les p ; F moyen = moyenne de (βX/se_X)².
/// Validé contre R (`validation/r/36_mr.R`).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../math/random.dart';
import '../model/result.dart';

/// Médiane pondérée (interpolation linéaire des poids cumulés centrés), comme MendelianRandomization.
double weightedMedian(List<double> theta, List<double> weights) {
  final order = [for (var i = 0; i < theta.length; i++) i]..sort((a, b) {
      final c = theta[a].compareTo(theta[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final t = [for (final i in order) theta[i]], w = [for (final i in order) weights[i]];
  final total = w.fold(0.0, (s, x) => s + x);
  final cum = <double>[];
  var run = 0.0;
  for (final x in w) {
    run += x;
    cum.add((run - 0.5 * x) / total);
  }
  var k = 0;
  for (final c in cum) {
    if (c < 0.5) k++;
  }
  // k (nombre de positions < 0,5) est un rang à partir de 1 dans R : indices k − 1 et k ici.
  if (k == 0) return t.first;
  if (k >= t.length) return t.last;
  final ratio = (0.5 - cum[k - 1]) / (cum[k] - cum[k - 1]);
  return t[k - 1] + (t[k] - t[k - 1]) * ratio;
}

/// ES de la médiane pondérée par bootstrap paramétrique. [draws] (facultatif) : tirages imposés, une ligne par itération
/// [βX*₁…βX*ₖ, βY*₁…βY*ₖ] ; sinon [iterations] tirages normaux à partir de [seed].
double weightedMedianBootstrapSe(List<double> bx, List<double> bxse, List<double> by, List<double> byse, List<double> weights,
    {int iterations = 10000, int seed = 314159265, List<List<double>>? draws}) {
  final k = bx.length;
  final med = <double>[];
  if (draws != null) {
    for (final d in draws) {
      med.add(weightedMedian([for (var j = 0; j < k; j++) d[k + j] / d[j]], weights));
    }
  } else {
    final r = SeededRandom(seed);
    double gauss() {
      final u1 = 1 - r.nextDouble(), u2 = r.nextDouble();
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }

    for (var it = 0; it < iterations; it++) {
      final xb = [for (var j = 0; j < k; j++) bx[j] + bxse[j] * gauss()];
      final yb = [for (var j = 0; j < k; j++) by[j] + byse[j] * gauss()];
      med.add(weightedMedian([for (var j = 0; j < k; j++) yb[j] / xb[j]], weights));
    }
  }
  final m = med.fold(0.0, (s, x) => s + x) / med.length;
  return math.sqrt(med.fold(0.0, (s, x) => s + (x - m) * (x - m)) / (med.length - 1));
}

class MrEstimate {
  final double estimate, se, lower, upper, p;
  const MrEstimate(this.estimate, this.se, this.lower, this.upper, this.p);
  factory MrEstimate.normal(double est, double se) {
    const z = 1.959963984540054;
    return MrEstimate(est, se, est - z * se, est + z * se, normalTwoSidedP(est / se));
  }
}

class MrFit {
  final MrEstimate ivw, ivwFixed, egger, eggerIntercept, median, mode;
  final List<MrEstimate> leaveOneOut;
  final bool randomEffects;
  final double q, qP, rse, eggerQ, eggerQP, eggerRse, i2gx, meanF;
  final AnalysisResult result;
  MrFit(this.ivw, this.ivwFixed, this.egger, this.eggerIntercept, this.median, this.mode, this.leaveOneOut, this.randomEffects, this.q, this.qP, this.rse, this.eggerQ, this.eggerQP,
      this.eggerRse, this.i2gx, this.meanF, this.result);
}

/// [outcomeLogOdds] : βY sur l'échelle des log-odds (effet causal présenté aussi en OR par unité d'exposition).
MrFit mendelianRandomization(List<double> bx, List<double> bxse, List<double> by, List<double> byse,
    {List<String>? names, String exposure = '', String outcome = '', bool outcomeLogOdds = true, int iterations = 10000, int seed = 314159265,
    List<List<double>>? bootstrapDraws, List<List<double>>? modeDraws}) {
  final k = bx.length;
  if (k < 3) throw StatInputError('mr_few', tr('Au moins 3 variants instrumentaux sont requis (MR-Egger, médiane).', 'At least 3 instrumental variants are required (MR-Egger, median).'));
  if (bxse.length != k || by.length != k || byse.length != k) throw StatInputError('mr_lengths', tr('Colonnes de longueurs différentes.', 'Columns of different lengths.'));
  if ([...bxse, ...byse].any((s) => !(s > 0)) || bx.any((b) => b == 0)) {
    throw StatInputError('mr_values', tr('Erreurs types strictement positives et βX non nuls requis.', 'Strictly positive standard errors and non-zero βX required.'));
  }
  final w = [for (final s in byse) 1 / (s * s)];
  // IVW : moindres carrés pondérés sans constante.
  var sxx = 0.0, sxy = 0.0;
  for (var j = 0; j < k; j++) {
    sxx += w[j] * bx[j] * bx[j];
    sxy += w[j] * bx[j] * by[j];
  }
  final theta = sxy / sxx;
  var rss = 0.0;
  for (var j = 0; j < k; j++) {
    rss += w[j] * (by[j] - theta * bx[j]) * (by[j] - theta * bx[j]);
  }
  final sigma = math.sqrt(rss / (k - 1));
  final seLm = sigma / math.sqrt(sxx);
  final randomEffects = k >= 4;
  final ivwFixed = MrEstimate.normal(theta, seLm / sigma);
  final ivw = randomEffects ? MrEstimate.normal(theta, seLm / math.min(sigma, 1)) : ivwFixed;
  final q = (k - 1) * sigma * sigma;
  final qP = chiSquareUpper(q, (k - 1).toDouble());
  // MR-Egger : orientation βX > 0, moindres carrés pondérés avec constante.
  final ex = [for (final b in bx) b.abs()];
  final ey = [for (var j = 0; j < k; j++) bx[j] < 0 ? -by[j] : by[j]];
  var s0 = 0.0, s1 = 0.0, s11 = 0.0, sy = 0.0, s1y = 0.0;
  for (var j = 0; j < k; j++) {
    s0 += w[j];
    s1 += w[j] * ex[j];
    s11 += w[j] * ex[j] * ex[j];
    sy += w[j] * ey[j];
    s1y += w[j] * ex[j] * ey[j];
  }
  final det = s0 * s11 - s1 * s1;
  final slope = (s0 * s1y - s1 * sy) / det, inter = (sy - slope * s1) / s0;
  var rssE = 0.0;
  for (var j = 0; j < k; j++) {
    final r = ey[j] - inter - slope * ex[j];
    rssE += w[j] * r * r;
  }
  final sigmaE = math.sqrt(rssE / (k - 2));
  final fE = sigmaE / math.min(sigmaE, 1); // ES du lm (σ̂·√(XᵀWX)⁻¹) divisé par min(σ̂, 1)
  final egger = MrEstimate.normal(slope, math.sqrt(s0 / det) * fE);
  final eggerInt = MrEstimate.normal(inter, math.sqrt(s11 / det) * fE);
  final eggerQ = rssE;
  final eggerQP = chiSquareUpper(eggerQ, (k - 2).toDouble());
  // I²_GX sur βX/se_Y, poids (se_X/se_Y)⁻².
  final gx = [for (var j = 0; j < k; j++) ex[j] / byse[j]];
  final gw = [for (var j = 0; j < k; j++) math.pow(bxse[j] / byse[j], -2).toDouble()];
  final gm = [for (var j = 0; j < k; j++) gx[j] * gw[j]].fold(0.0, (s, x) => s + x) / gw.fold(0.0, (s, x) => s + x);
  var qgx = 0.0;
  for (var j = 0; j < k; j++) {
    qgx += gw[j] * (gx[j] - gm) * (gx[j] - gm);
  }
  final i2gx = math.max(0.0, (qgx - (k - 1)) / qgx);
  // Médiane pondérée.
  final wm = [for (var j = 0; j < k; j++) (bx[j] / byse[j]) * (bx[j] / byse[j])];
  final ratio = [for (var j = 0; j < k; j++) by[j] / bx[j]];
  final med = weightedMedian(ratio, wm);
  final medSe = weightedMedianBootstrapSe(bx, bxse, by, byse, wm, iterations: iterations, seed: seed, draws: bootstrapDraws);
  final median = MrEstimate.normal(med, medSe);
  // Mode pondéré (ES delta) et leave-one-out (IVW).
  final seDelta = [for (var j = 0; j < k; j++) mrDeltaSe(bx[j], bxse[j], by[j], byse[j])];
  final mode = MrEstimate.normal(modeBasedEstimate(ratio, seDelta), modeBasedBootstrapSe(ratio, seDelta, iterations: iterations, seed: seed, draws: modeDraws));
  final loo = k >= 4 ? leaveOneOutIvw(bx, by, byse) : const <MrEstimate>[];
  final influential = [for (var j = 0; j < loo.length; j++) if (loo[j].estimate.sign != ivw.estimate.sign || loo[j].estimate < ivw.lower || loo[j].estimate > ivw.upper) j];
  final meanF = [for (var j = 0; j < k; j++) (bx[j] / bxse[j]) * (bx[j] / bxse[j])].fold(0.0, (s, x) => s + x) / k;

  final ex0 = exposure.isEmpty ? tr('l\'exposition', 'the exposure') : exposure, out0 = outcome.isEmpty ? tr('l\'issue', 'the outcome') : outcome;
  String f3(double v) => fmt(v, digits: 3);
  String ci(MrEstimate e) => tr('${f3(e.estimate)} (IC 95 % ${f3(e.lower)} à ${f3(e.upper)})', '${f3(e.estimate)} (95% CI ${f3(e.lower)} to ${f3(e.upper)})');
  final consistent = [ivw, egger, median, mode].every((e) => e.estimate.sign == ivw.estimate.sign) &&
      [egger, median, mode].every((e) => e.lower <= ivw.upper && ivw.lower <= e.upper);
  final rowNames = names ?? [for (var j = 0; j < k; j++) 'v${j + 1}'];
  final result = AnalysisResult(
    methodId: 'mendelian_randomization',
    methodName: tr('Randomisation mendélienne : effet de $ex0 sur $out0 ($k variants)', 'Mendelian randomization: effect of $ex0 on $out0 ($k variants)'),
    inputs: {'variants': k, 'exposure': ex0, 'outcome': out0, 'outcomeLogOdds': outcomeLogOdds, 'iterations': bootstrapDraws?.length ?? iterations},
    formula: tr(
        'Rapport de Wald par variant βY/βX. IVW : régression pondérée (1/se_Y²) de βY sur βX sans constante${randomEffects ? ', effets aléatoires multiplicatifs (ES / min(σ̂, 1))' : ', effets fixes'}. '
            'MR-Egger : βX orientés positifs, régression pondérée avec constante (intercept = pléiotropie directionnelle), ES × max(1, σ̂). '
            'Médiane pondérée : poids (βX/se_Y)², ES par bootstrap paramétrique. Mode pondéré : maximum de la densité gaussienne pondérée des rapports (ES delta), ES = MAD bootstrap. '
            'Leave-one-out : IVW sans chaque variant. IC et p par la loi normale. F moyen = moyenne de (βX/se_X)².',
        'Wald ratio per variant βY/βX. IVW: weighted (1/se_Y²) regression of βY on βX without intercept${randomEffects ? ', multiplicative random effects (SE / min(σ̂, 1))' : ', fixed effects'}. '
            'MR-Egger: βX oriented positive, weighted regression with intercept (intercept = directional pleiotropy), SE × max(1, σ̂). '
            'Weighted median: weights (βX/se_Y)², SE by parametric bootstrap. Weighted mode: maximum of the weighted Gaussian density of the ratios (delta SE), SE = bootstrap MAD. '
            'Leave-one-out: IVW without each variant. CIs and p-values from the normal distribution. Mean F = mean of (βX/se_X)².'),
    estimates: [
      Estimate(tr('Effet causal — IVW', 'Causal effect — IVW'), ivw.estimate, lower: ivw.lower, upper: ivw.upper, se: ivw.se, pValue: ivw.p),
      if (outcomeLogOdds) Estimate(tr('OR par unité de $ex0 — IVW', 'OR per unit of $ex0 — IVW'), math.exp(ivw.estimate), lower: math.exp(ivw.lower), upper: math.exp(ivw.upper), pValue: ivw.p),
      Estimate(tr('Effet causal — MR-Egger', 'Causal effect — MR-Egger'), egger.estimate, lower: egger.lower, upper: egger.upper, se: egger.se, pValue: egger.p),
      Estimate(tr('Intercept MR-Egger (pléiotropie)', 'MR-Egger intercept (pleiotropy)'), eggerInt.estimate, lower: eggerInt.lower, upper: eggerInt.upper, se: eggerInt.se, pValue: eggerInt.p),
      Estimate(tr('Effet causal — médiane pondérée', 'Causal effect — weighted median'), median.estimate, lower: median.lower, upper: median.upper, se: median.se, pValue: median.p),
      Estimate(tr('Effet causal — mode pondéré', 'Causal effect — weighted mode'), mode.estimate, lower: mode.lower, upper: mode.upper, se: mode.se, pValue: mode.p),
    ],
    statistics: {
      'ivw': ivw.estimate, 'ivw_se': ivw.se, 'ivw_p': ivw.p,
      'ivw_fixed_se': ivwFixed.se,
      'egger': egger.estimate, 'egger_se': egger.se, 'egger_p': egger.p,
      'egger_intercept': eggerInt.estimate, 'egger_intercept_se': eggerInt.se, 'egger_intercept_p': eggerInt.p,
      'weighted_median': median.estimate, 'weighted_median_se': median.se, 'weighted_median_p': median.p,
      'weighted_mode': mode.estimate, 'weighted_mode_se': mode.se, 'weighted_mode_p': mode.p,
      if (loo.isNotEmpty) ...{'loo_min': loo.map((e) => e.estimate).reduce(math.min), 'loo_max': loo.map((e) => e.estimate).reduce(math.max)},
      'q': q, 'q_p': qP, 'rse': sigma, 'egger_q': eggerQ, 'egger_q_p': eggerQP, 'i2_gx': i2gx, 'mean_f': meanF,
    },
    checks: [
      Check('weak_instruments', tr('Instruments assez forts (F moyen ≥ 10)', 'Strong enough instruments (mean F ≥ 10)'), meanF >= 10 ? CheckStatus.ok : CheckStatus.warning,
          tr('F moyen = ${fmt(meanF, digits: 3)}.${meanF < 10 ? ' Instruments faibles : biais vers l\'association observationnelle (même échantillon) ou vers 0 (échantillons distincts).' : ''}',
              'Mean F = ${fmt(meanF, digits: 3)}.${meanF < 10 ? ' Weak instruments: bias towards the observational association (same sample) or towards 0 (separate samples).' : ''}')),
      Check('heterogeneity', tr('Homogénéité des estimations par variant (Q de Cochran)', 'Homogeneity of per-variant estimates (Cochran\'s Q)'), qP >= 0.05 ? CheckStatus.ok : CheckStatus.warning,
          tr('Q = ${fmt(q, digits: 3)}, ${k - 1} ddl, ${fmtP(qP)}${qP < 0.05 ? ' : hétérogénéité, signe possible de pléiotropie (l\'IVW à effets aléatoires en tient compte dans l\'ES)' : ''}.',
              'Q = ${fmt(q, digits: 3)}, ${k - 1} df, ${fmtP(qP)}${qP < 0.05 ? ': heterogeneity, possible sign of pleiotropy (random-effects IVW accounts for it in the SE)' : ''}.')),
      Check('pleiotropy', tr('Pas de pléiotropie directionnelle (intercept MR-Egger)', 'No directional pleiotropy (MR-Egger intercept)'), eggerInt.p >= 0.05 ? CheckStatus.ok : CheckStatus.warning,
          tr('Intercept ${f3(eggerInt.estimate)}, ${fmtP(eggerInt.p)}${eggerInt.p < 0.05 ? ' : pléiotropie directionnelle probable ; l\'IVW est biaisé, privilégier MR-Egger et la médiane pondérée' : ''}.',
              'Intercept ${f3(eggerInt.estimate)}, ${fmtP(eggerInt.p)}${eggerInt.p < 0.05 ? ': directional pleiotropy likely; IVW is biased, prefer MR-Egger and the weighted median' : ''}.')),
      Check('i2gx', tr('MR-Egger non dilué (I²_GX ≥ 0,9)', 'MR-Egger not diluted (I²_GX ≥ 0.9)'), i2gx >= 0.9 ? CheckStatus.ok : CheckStatus.warning,
          tr('I²_GX = ${fmt(i2gx, digits: 3)}${i2gx < 0.9 ? ' : l\'estimation MR-Egger est biaisée vers 0 (hypothèse NOME mal vérifiée)' : ''}.',
              'I²_GX = ${fmt(i2gx, digits: 3)}${i2gx < 0.9 ? ': the MR-Egger estimate is biased towards 0 (NOME assumption poorly met)' : ''}.')),
      if (loo.isNotEmpty)
        Check('influence', tr('Aucun variant ne porte seul l\'effet (leave-one-out)', 'No variant drives the effect alone (leave-one-out)'), influential.isEmpty ? CheckStatus.ok : CheckStatus.warning,
            influential.isEmpty
                ? tr('Sans chaque variant, l\'IVW reste dans l\'IC de l\'analyse complète (${f3(loo.map((e) => e.estimate).reduce(math.min))} à ${f3(loo.map((e) => e.estimate).reduce(math.max))}).',
                    'Without each variant, IVW stays within the CI of the full analysis (${f3(loo.map((e) => e.estimate).reduce(math.min))} to ${f3(loo.map((e) => e.estimate).reduce(math.max))}).')
                : tr('Variant(s) influent(s) : ${[for (final j in influential) rowNames[j]].join(', ')} ; vérifier leur pléiotropie.', 'Influential variant(s): ${[for (final j in influential) rowNames[j]].join(', ')}; check their pleiotropy.')),
      Check('consistency', tr('Cohérence des méthodes', 'Consistency of the methods'), consistent ? CheckStatus.ok : CheckStatus.warning,
          consistent
              ? tr('IVW, MR-Egger, médiane et mode pondérés vont dans le même sens avec des IC qui se recouvrent.', 'IVW, MR-Egger, weighted median and mode point the same way with overlapping CIs.')
              : tr('Les méthodes divergent : l\'effet causal dépend des hypothèses sur la pléiotropie.', 'The methods diverge: the causal effect depends on assumptions about pleiotropy.')),
      Check('assumptions', tr('Hypothèses non testables des instruments', 'Untestable instrument assumptions'), CheckStatus.notAssessed,
          tr('Indépendance des variants vis-à-vis des facteurs de confusion et absence d\'effet sur l\'issue autrement que par l\'exposition : à argumenter (biologie, PhenoScanner).',
              'Independence of the variants from confounders and no effect on the outcome other than through the exposure: to be argued (biology, PhenoScanner).')),
    ],
    tables: [
      ResultTable(tr('Estimations de l\'effet causal', 'Causal effect estimates'), [tr('Méthode', 'Method'), tr('Effet (IC 95 %)', 'Effect (95% CI)'), if (outcomeLogOdds) 'OR', 'p'], [
        for (final (lab, e) in [('IVW', ivw), ('MR-Egger', egger), (tr('Médiane pondérée', 'Weighted median'), median), (tr('Mode pondéré', 'Weighted mode'), mode)])
          [lab, ci(e), if (outcomeLogOdds) f3(math.exp(e.estimate)), fmtP(e.p).replaceFirst(RegExp(r'^p\s*=?\s*'), '')],
      ]),
      if (loo.isNotEmpty)
        ResultTable(tr('Leave-one-out (IVW sans le variant)', 'Leave-one-out (IVW without the variant)'), [tr('Variant retiré', 'Variant removed'), tr('Effet (IC 95 %)', 'Effect (95% CI)')], [
          for (var j = 0; j < loo.length; j++) [rowNames[j], ci(loo[j])],
        ]),
      ResultTable(tr('Variants instrumentaux', 'Instrumental variants'), [tr('Variant', 'Variant'), 'βX', 'se X', 'βY', 'se Y', tr('Rapport βY/βX', 'Ratio βY/βX'), 'F'], [
        for (var j = 0; j < k; j++) [rowNames[j], fmt(bx[j], digits: 4), fmt(bxse[j], digits: 3), fmt(by[j], digits: 4), fmt(byse[j], digits: 3), f3(ratio[j]), fmt((bx[j] / bxse[j]) * (bx[j] / bxse[j]), digits: 3)]
      ]),
    ],
    figures: {
      'mr': {
        'bx': ex, 'by': ey, 'bxse': bxse, 'byse': byse,
        'ivw': ivw.estimate, 'egger': egger.estimate, 'eggerIntercept': eggerInt.estimate, 'median': median.estimate, 'mode': mode.estimate,
        'exposure': ex0, 'outcome': out0,
      },
    },
    log: [
      tr('$k variants ; bootstrap de la médiane pondérée : ${bootstrapDraws?.length ?? iterations} itérations.', '$k variants; weighted median bootstrap: ${bootstrapDraws?.length ?? iterations} iterations.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Les allèles sont répartis au hasard à la conception : des variants associés à $ex0 servent d\'instruments, comme une randomisation naturelle, et permettent d\'estimer son effet causal sur $out0 sans la plupart des confusions des études observationnelles.',
          'Alleles are allocated at random at conception: variants associated with $ex0 serve as instruments, like a natural randomization, and allow estimating its causal effect on $out0 without most of the confounding of observational studies.'),
      whatItMeans: tr(
          'Par unité de $ex0 : effet IVW ${ci(ivw)}${outcomeLogOdds ? ', soit un OR de ${f3(math.exp(ivw.estimate))}' : ''} ; MR-Egger ${ci(egger)} ; médiane pondérée ${ci(median)}.',
          'Per unit of $ex0: IVW effect ${ci(ivw)}${outcomeLogOdds ? ', i.e. an OR of ${f3(math.exp(ivw.estimate))}' : ''}; MR-Egger ${ci(egger)}; weighted median ${ci(median)}.'),
      notJustified: tr(
          'Conclure à une causalité sans argumenter l\'absence de pléiotropie horizontale ; extrapoler l\'effet d\'une exposition à vie (génétique) à une intervention brève à l\'âge adulte ; utiliser des instruments faibles ou des échantillons d\'ascendances différentes.',
          'Concluding causality without arguing the absence of horizontal pleiotropy; extrapolating the effect of a lifelong (genetic) exposure to a brief intervention in adulthood; using weak instruments or samples of different ancestries.'),
    ),
  );
  return MrFit(ivw, ivwFixed, egger, eggerInt, median, mode, loo, randomEffects, q, qP, sigma, eggerQ, eggerQP, sigmaE, i2gx, meanF, result);
}

// ------------------------------------------------------------------ analyses de sensibilité

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _sd(List<double> v) {
  final m = v.fold(0.0, (s, x) => s + x) / v.length;
  return math.sqrt(v.fold(0.0, (s, x) => s + (x - m) * (x - m)) / (v.length - 1));
}

/// MAD de R (constante 1,4826).
double _mad(List<double> v) {
  final med = _median(v);
  return 1.4826 * _median([for (final x in v) (x - med).abs()]);
}

/// Abscisse du maximum de la densité gaussienne pondérée calculée comme `density()` de R (n = 512, cut = 3) :
/// discrétisation linéaire (BinDist) sur 2 × 512 cases de [lo ; up], convolution circulaire avec le noyau (somme directe,
/// équivalente à la FFT de R), interpolation linéaire sur 512 points de [min − 3·bw ; max + 3·bw].
double _densityMode(List<double> x, List<double> w, double bw) {
  const n = 512;
  final xmin = x.reduce(math.min), xmax = x.reduce(math.max);
  final from = xmin - 3 * bw, to = xmax + 3 * bw;
  final lo = from - 4 * bw, up = to + 4 * bw;
  final y = List<double>.filled(2 * n, 0);
  final xdelta = (up - lo) / (n - 1);
  for (var i = 0; i < x.length; i++) {
    final xpos = (x[i] - lo) / xdelta;
    final ix = xpos.floor();
    final fx = xpos - ix;
    if (ix >= 0 && ix <= n - 2) {
      y[ix] += w[i] * (1 - fx);
      y[ix + 1] += w[i] * fx;
    } else if (ix == -1) {
      y[0] += w[i] * fx;
    } else if (ix == n - 1) {
      y[ix] += w[i] * (1 - fx);
    }
  }
  // Noyau aux décalages kords (0 … 2(up − lo), partie haute repliée en négatif), loi normale d'ET bw.
  final step = 2 * (up - lo) / (2 * n - 1);
  final kern = List<double>.generate(2 * n, (m) {
    final d = m <= n ? m * step : -((2 * n - m) * step);
    return math.exp(-0.5 * (d / bw) * (d / bw)) / (bw * math.sqrt(2 * math.pi));
  });
  final nz = [for (var j = 0; j < 2 * n; j++) if (y[j] != 0) j];
  final dens = List<double>.generate(n, (m) {
    var s = 0.0;
    for (final j in nz) {
      s += y[j] * kern[((j - m) % (2 * n) + 2 * n) % (2 * n)];
    }
    return math.max(0.0, s);
  });
  // Interpolation sur la grille de sortie et maximum (premier en cas d'égalité).
  final dx = (up - lo) / (n - 1), gx = (to - from) / (n - 1);
  var best = from, bestY = -1.0;
  for (var q = 0; q < n; q++) {
    final xq = from + q * gx;
    var i = ((xq - lo) / dx).floor();
    if (i >= n - 1) i = n - 2;
    if (i < 0) i = 0;
    final x0 = lo + i * dx, x1 = lo + (i + 1) * dx;
    final yq = dens[i] + (dens[i + 1] - dens[i]) * (xq - x0) / (x1 - x0);
    if (yq > bestY) {
      bestY = yq;
      best = xq;
    }
  }
  return best;
}

/// ES du rapport de Wald par la méthode delta au second terme (défaut de mr_mbe) : √(se_Y²/βX² + βY²·se_X²/βX⁴).
double mrDeltaSe(double bx, double bxse, double by, double byse) => math.sqrt(byse * byse / (bx * bx) + by * by * bxse * bxse / (bx * bx * bx * bx));

/// Estimation du mode pondéré (MBE) : rapports [ratio], ES [se] (poids se⁻² normalisés), facteur de lissage [phi].
double modeBasedEstimate(List<double> ratio, List<double> se, {double phi = 1}) {
  final s = 0.9 * math.min(_sd(ratio), _mad(ratio)) / math.pow(ratio.length, 0.2);
  final w = [for (final v in se) 1 / (v * v)];
  final tw = w.fold(0.0, (a, b) => a + b);
  return _densityMode(ratio, [for (final v in w) v / tw], s * phi);
}

/// ES du mode pondéré : MAD des estimations sur rapports tirés selon N(ratio, se) ([draws] imposés ou [iterations]).
double modeBasedBootstrapSe(List<double> ratio, List<double> se, {double phi = 1, int iterations = 10000, int seed = 314159265, List<List<double>>? draws}) {
  final est = <double>[];
  if (draws != null) {
    for (final d in draws) {
      est.add(modeBasedEstimate(d, se, phi: phi));
    }
  } else {
    final r = SeededRandom(seed);
    double gauss() {
      final u1 = 1 - r.nextDouble(), u2 = r.nextDouble();
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }

    for (var it = 0; it < iterations; it++) {
      est.add(modeBasedEstimate([for (var j = 0; j < ratio.length; j++) ratio[j] + se[j] * gauss()], se, phi: phi));
    }
  }
  return _mad(est);
}

/// IVW (réglages de mr_ivw) en retirant chaque variant tour à tour.
List<MrEstimate> leaveOneOutIvw(List<double> bx, List<double> by, List<double> byse) => [
      for (var j = 0; j < bx.length; j++) _ivw([for (var i = 0; i < bx.length; i++) if (i != j) bx[i]], [for (var i = 0; i < bx.length; i++) if (i != j) by[i]],
          [for (var i = 0; i < bx.length; i++) if (i != j) byse[i]])
    ];

MrEstimate _ivw(List<double> bx, List<double> by, List<double> byse) {
  final k = bx.length;
  var sxx = 0.0, sxy = 0.0;
  for (var j = 0; j < k; j++) {
    final w = 1 / (byse[j] * byse[j]);
    sxx += w * bx[j] * bx[j];
    sxy += w * bx[j] * by[j];
  }
  final theta = sxy / sxx;
  var rss = 0.0;
  for (var j = 0; j < k; j++) {
    final r = by[j] - theta * bx[j];
    rss += r * r / (byse[j] * byse[j]);
  }
  final sigma = math.sqrt(rss / (k - 1));
  final seLm = sigma / math.sqrt(sxx);
  return MrEstimate.normal(theta, k >= 4 ? seLm / math.min(sigma, 1) : seLm / sigma);
}

// ------------------------------------------------------------------ randomisation mendélienne multivariée

class MvMrFit {
  final List<MrEstimate> estimates;
  final bool randomEffects;
  final double q, qP, rse;
  final AnalysisResult result;
  MvMrFit(this.estimates, this.randomEffects, this.q, this.qP, this.rse, this.result);
}

/// IVW multivariée (mr_mvivw) : régression pondérée (1/se_Y²) de βY sur les βX de [exposures] sans constante ; effet
/// direct de chaque exposition, à niveau égal des autres. [bx] et [bxse] : une liste de k valeurs par exposition.
MvMrFit multivariableMendelianRandomization(List<List<double>> bx, List<List<double>> bxse, List<double> by, List<double> byse,
    {required List<String> exposures, String outcome = '', bool outcomeLogOdds = true, List<String>? names}) {
  final p = bx.length, k = by.length;
  if (p < 2) throw StatInputError('mvmr_one', tr('La MR multivariée demande au moins deux expositions.', 'Multivariable MR requires at least two exposures.'));
  if (k <= p + 1) throw StatInputError('mvmr_few', tr('Il faut plus de variants que d\'expositions + 1.', 'More variants than exposures + 1 are needed.'));
  if (bx.any((c) => c.length != k) || byse.length != k || byse.any((s) => !(s > 0))) {
    throw StatInputError('mr_lengths', tr('Colonnes de longueurs différentes ou ES non positives.', 'Columns of different lengths or non-positive SEs.'));
  }
  final w = [for (final s in byse) 1 / (s * s)];
  final a = [for (var r = 0; r < p; r++) [for (var c = 0; c < p; c++) [for (var j = 0; j < k; j++) w[j] * bx[r][j] * bx[c][j]].fold(0.0, (s, x) => s + x)]];
  final b = [for (var r = 0; r < p; r++) [for (var j = 0; j < k; j++) w[j] * bx[r][j] * by[j]].fold(0.0, (s, x) => s + x)];
  final inv = invertSpd(Matrix.fromRows(a)) ?? (throw StatInputError('mvmr_collinear', tr('Expositions colinéaires : effets non estimables.', 'Collinear exposures: effects not estimable.')));
  final theta = [for (var r = 0; r < p; r++) [for (var c = 0; c < p; c++) inv.get(r, c) * b[c]].fold(0.0, (s, x) => s + x)];
  var rss = 0.0;
  for (var j = 0; j < k; j++) {
    var fit = 0.0;
    for (var r = 0; r < p; r++) {
      fit += theta[r] * bx[r][j];
    }
    rss += w[j] * (by[j] - fit) * (by[j] - fit);
  }
  final sigma = math.sqrt(rss / (k - p));
  final randomEffects = k >= 4;
  final est = [
    for (var r = 0; r < p; r++)
      MrEstimate.normal(theta[r], sigma * math.sqrt(inv.get(r, r)) / (randomEffects ? math.min(sigma, 1) : sigma))
  ];
  final q = (k - p) * sigma * sigma, qP = chiSquareUpper(q, (k - p).toDouble());
  final out0 = outcome.isEmpty ? tr('l\'issue', 'the outcome') : outcome;
  String f3(double v) => fmt(v, digits: 3);
  String ci(MrEstimate e) => tr('${f3(e.estimate)} (IC 95 % ${f3(e.lower)} à ${f3(e.upper)})', '${f3(e.estimate)} (95% CI ${f3(e.lower)} to ${f3(e.upper)})');
  final result = AnalysisResult(
    methodId: 'mendelian_randomization_mv',
    methodName: tr('Randomisation mendélienne multivariée : ${exposures.join(', ')} → $out0 ($k variants)', 'Multivariable Mendelian randomization: ${exposures.join(', ')} → $out0 ($k variants)'),
    inputs: {'variants': k, 'exposures': exposures, 'outcome': out0, 'outcomeLogOdds': outcomeLogOdds},
    formula: tr(
        'βY = Σ θ_e·βX_e (régression pondérée 1/se_Y², sans constante) : θ_e = effet direct de l\'exposition e à niveau égal des autres ; '
            '${randomEffects ? 'effets aléatoires multiplicatifs (ES / min(σ̂, 1))' : 'effets fixes'} ; Q = (k − p)·σ̂² ; loi normale.',
        'βY = Σ θ_e·βX_e (weighted regression 1/se_Y², no intercept): θ_e = direct effect of exposure e holding the others fixed; '
            '${randomEffects ? 'multiplicative random effects (SE / min(σ̂, 1))' : 'fixed effects'}; Q = (k − p)·σ̂²; normal distribution.'),
    estimates: [
      for (var r = 0; r < p; r++) ...[
        Estimate(tr('Effet direct — ${exposures[r]}', 'Direct effect — ${exposures[r]}'), est[r].estimate, lower: est[r].lower, upper: est[r].upper, se: est[r].se, pValue: est[r].p),
        if (outcomeLogOdds)
          Estimate(tr('OR par unité — ${exposures[r]}', 'OR per unit — ${exposures[r]}'), math.exp(est[r].estimate), lower: math.exp(est[r].lower), upper: math.exp(est[r].upper), pValue: est[r].p),
      ],
    ],
    statistics: {
      for (var r = 0; r < p; r++) ...{'theta_${exposures[r]}': est[r].estimate, 'se_${exposures[r]}': est[r].se, 'p_${exposures[r]}': est[r].p},
      'q': q, 'q_p': qP, 'rse': sigma,
    },
    checks: [
      Check('heterogeneity', tr('Homogénéité résiduelle (Q)', 'Residual homogeneity (Q)'), qP >= 0.05 ? CheckStatus.ok : CheckStatus.warning,
          tr('Q = ${fmt(q, digits: 3)}, ${k - p} ddl, ${fmtP(qP)}${qP < 0.05 ? ' : pléiotropie résiduelle possible (non expliquée par les expositions incluses)' : ''}.',
              'Q = ${fmt(q, digits: 3)}, ${k - p} df, ${fmtP(qP)}${qP < 0.05 ? ': possible residual pleiotropy (not explained by the included exposures)' : ''}.')),
      Check('conditional_f', tr('Force conditionnelle des instruments', 'Conditional instrument strength'), CheckStatus.notAssessed,
          tr('Le F conditionnel demande les corrélations entre expositions (non fournies) ; des expositions très corrélées génétiquement rendent les effets directs imprécis.',
              'The conditional F requires the correlations between exposures (not provided); genetically highly correlated exposures make direct effects imprecise.')),
    ],
    tables: [
      ResultTable(tr('Effets directs (à niveau égal des autres expositions)', 'Direct effects (holding the other exposures fixed)'),
          [tr('Exposition', 'Exposure'), tr('Effet (IC 95 %)', 'Effect (95% CI)'), if (outcomeLogOdds) 'OR', 'p'], [
        for (var r = 0; r < p; r++) [exposures[r], ci(est[r]), if (outcomeLogOdds) f3(math.exp(est[r].estimate)), fmtP(est[r].p).replaceFirst(RegExp(r'^p\s*=?\s*'), '')],
      ]),
    ],
    log: [tr('$k variants, $p expositions${names == null ? '' : ''}.', '$k variants, $p exposures.')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Des variants agissent souvent sur plusieurs expositions liées (LDL, HDL, triglycérides) : la MR multivariée estime l\'effet propre de chacune, ce qui corrige cette pléiotropie mesurée.',
          'Variants often act on several related exposures (LDL, HDL, triglycerides): multivariable MR estimates the own effect of each, which corrects this measured pleiotropy.'),
      whatItMeans: tr('Effets directs sur $out0 : ${[for (var r = 0; r < p; r++) '${exposures[r]} ${ci(est[r])}'].join(' ; ')}.',
          'Direct effects on $out0: ${[for (var r = 0; r < p; r++) '${exposures[r]} ${ci(est[r])}'].join('; ')}.'),
      notJustified: tr(
          'Interpréter l\'effet direct d\'une exposition comme son effet total ; ignorer une exposition pléiotrope non incluse ; conclure avec des instruments faibles conditionnellement.',
          'Interpreting the direct effect of an exposure as its total effect; ignoring a pleiotropic exposure not included; concluding with conditionally weak instruments.'),
    ),
  );
  return MvMrFit(est, randomEffects, q, qP, sigma, result);
}

// ------------------------------------------------------------------ sens causal : test de Steiger

/// r d'un variant à partir de (β, ES, N), comme TwoSampleMR::get_r_from_bsen : F = (β/ES)², r² = F/(N − 2 + F).
double mrRFromBsen(double b, double se, int n) {
  final f = (b / se) * (b / se);
  return (b < 0 ? -1 : 1) * math.sqrt(f / (n - 2 + f));
}

class MrSteiger {
  final double r2x, r2y, z, p;
  final List<double> r2xSnp, r2ySnp, pSnp;
  final List<bool> correctDirection;
  final MrEstimate? ivwAll, ivwFiltered;
  final AnalysisResult result;
  MrSteiger(this.r2x, this.r2y, this.z, this.p, this.r2xSnp, this.r2ySnp, this.pSnp, this.correctDirection, this.ivwAll, this.ivwFiltered, this.result);
}

/// Test de Steiger (Hemani et al. 2017) : les instruments expliquent-ils davantage la variance de l'exposition ([nX] sujets)
/// que celle de l'issue ([nY]) ? Agrégé (r = √Σr²) et variant par variant (corrélations indépendantes, z de Fisher), avec
/// l'IVW sur tous les variants et sur ceux de sens correct. [outcomeBinary] : r² de l'issue approché à partir des log-odds.
MrSteiger steigerDirectionality(List<double> bx, List<double> bxse, List<double> by, List<double> byse,
    {required int nX, required int nY, List<String>? names, String exposure = '', String outcome = '', bool outcomeBinary = false}) {
  final k = bx.length;
  if (k < 1 || bxse.length != k || by.length != k || byse.length != k) throw StatInputError('mr_lengths', tr('Colonnes de longueurs différentes.', 'Columns of different lengths.'));
  if (nX < 10 || nY < 10) throw StatInputError('steiger_n', tr('Effectifs des deux études requis (au moins 10).', 'Sample sizes of both studies required (at least 10).'));
  final rx = [for (var j = 0; j < k; j++) mrRFromBsen(bx[j], bxse[j], nX)], ry = [for (var j = 0; j < k; j++) mrRFromBsen(by[j], byse[j], nY)];
  final denom = math.sqrt(1 / (nX - 3) + 1 / (nY - 3));
  double atanh(double r) => 0.5 * math.log((1 + r) / (1 - r));
  final r2x = rx.fold(0.0, (s, r) => s + r * r), r2y = ry.fold(0.0, (s, r) => s + r * r);
  final z = (atanh(math.sqrt(r2x)) - atanh(math.sqrt(r2y))) / denom;
  final p = normalTwoSidedP(z);
  final r2xSnp = [for (final r in rx) r * r], r2ySnp = [for (final r in ry) r * r];
  final pSnp = [for (var j = 0; j < k; j++) normalTwoSidedP((atanh(rx[j].abs()) - atanh(ry[j].abs())) / denom)];
  final ok = [for (var j = 0; j < k; j++) r2xSnp[j] > r2ySnp[j]];
  final keep = [for (var j = 0; j < k; j++) if (ok[j]) j];
  final ivwAll = k >= 2 ? _ivw(bx, by, byse) : null;
  final ivwF = keep.length >= 2 && keep.length < k ? _ivw([for (final j in keep) bx[j]], [for (final j in keep) by[j]], [for (final j in keep) byse[j]]) : null;
  final flagged = [for (var j = 0; j < k; j++) if (!ok[j]) j];
  final rowNames = names ?? [for (var j = 0; j < k; j++) 'v${j + 1}'];
  final ex0 = exposure.isEmpty ? tr('l\'exposition', 'the exposure') : exposure, out0 = outcome.isEmpty ? tr('l\'issue', 'the outcome') : outcome;
  final rightWay = r2x > r2y;
  String f3(double v) => fmt(v, digits: 3);
  String pct(double v) => fmtPct(v);
  String ci(MrEstimate e) => tr('${f3(e.estimate)} (IC 95 % ${f3(e.lower)} à ${f3(e.upper)})', '${f3(e.estimate)} (95% CI ${f3(e.lower)} to ${f3(e.upper)})');
  final result = AnalysisResult(
    methodId: 'mr_steiger',
    methodName: tr('Sens causal (test de Steiger) : $ex0 → $out0 ($k variants)', 'Causal direction (Steiger test): $ex0 → $out0 ($k variants)'),
    inputs: {'variants': k, 'nX': nX, 'nY': nY, 'exposure': ex0, 'outcome': out0, 'outcomeBinary': outcomeBinary},
    formula: tr(
        'Pour chaque variant, r² = F/(N − 2 + F) avec F = (β/ES)² (N = effectif de l\'étude) ; r_X = √Σr²_X, r_Y = √Σr²_Y ; z = (atanh r_X − atanh r_Y)/√(1/(N_X − 3) + 1/(N_Y − 3)) ; '
            'sens $ex0 → $out0 si r²_X > r²_Y. Même test variant par variant (filtrage) ; IVW sur tous les variants et sur ceux de sens correct.',
        'For each variant, r² = F/(N − 2 + F) with F = (β/SE)² (N = study sample size); r_X = √Σr²_X, r_Y = √Σr²_Y; z = (atanh r_X − atanh r_Y)/√(1/(N_X − 3) + 1/(N_Y − 3)); '
            'direction $ex0 → $out0 if r²_X > r²_Y. Same test per variant (filtering); IVW on all variants and on those with the correct direction.'),
    estimates: [
      Estimate(tr('Variance de $ex0 expliquée (r²_X)', 'Variance of $ex0 explained (r²_X)'), r2x),
      Estimate(tr('Variance de $out0 expliquée (r²_Y)', 'Variance of $out0 explained (r²_Y)'), r2y, pValue: p),
      if (ivwAll != null) Estimate(tr('Effet causal IVW — tous les variants', 'IVW causal effect — all variants'), ivwAll.estimate, lower: ivwAll.lower, upper: ivwAll.upper, pValue: ivwAll.p),
      if (ivwF != null) Estimate(tr('Effet causal IVW — variants de sens correct', 'IVW causal effect — correctly oriented variants'), ivwF.estimate, lower: ivwF.lower, upper: ivwF.upper, pValue: ivwF.p),
    ],
    statistics: {
      'r2_x': r2x, 'r2_y': r2y, 'z': z, 'p': p, 'variants_flagged': flagged.length.toDouble(),
      if (ivwAll != null) 'ivw_all': ivwAll.estimate,
      if (ivwF != null) 'ivw_filtered': ivwF.estimate,
    },
    checks: [
      Check('direction', tr('Sens $ex0 → $out0 confirmé (r²_X > r²_Y, p < 0,05)', 'Direction $ex0 → $out0 confirmed (r²_X > r²_Y, p < 0.05)'),
          rightWay && p < 0.05 ? CheckStatus.ok : CheckStatus.warning,
          tr('r²_X = ${pct(r2x)}, r²_Y = ${pct(r2y)}, z = ${fmt(z, digits: 3)}, ${fmtP(p)}${rightWay ? '' : ' : les variants expliquent davantage l\'issue que l\'exposition, le sens causal pourrait être inverse'}.',
              'r²_X = ${pct(r2x)}, r²_Y = ${pct(r2y)}, z = ${fmt(z, digits: 3)}, ${fmtP(p)}${rightWay ? '' : ': the variants explain more of the outcome than of the exposure, the causal direction might be reversed'}.')),
      Check('filtering', tr('Aucun variant de sens inverse', 'No reversely oriented variant'), flagged.isEmpty ? CheckStatus.ok : CheckStatus.warning,
          flagged.isEmpty
              ? tr('Chaque variant explique davantage $ex0 que $out0.', 'Each variant explains more of $ex0 than of $out0.')
              : tr('${flagged.length} variant(s) expliquent davantage $out0 : ${[for (final j in flagged) rowNames[j]].join(', ')} ; comparer l\'IVW avec et sans eux.',
                  '${flagged.length} variant(s) explain more of $out0: ${[for (final j in flagged) rowNames[j]].join(', ')}; compare IVW with and without them.')),
      Check('measurement', tr('Précision des r² (erreur de mesure, échelle des issues binaires)', 'Accuracy of r² (measurement error, scale of binary outcomes)'), CheckStatus.notAssessed,
          outcomeBinary
              ? tr('Issue binaire : r² approché à partir des log-odds (échelle observée) ; la conversion sur l\'échelle de liability demande la prévalence et les fréquences alléliques.',
                  'Binary outcome: r² approximated from log-odds (observed scale); conversion to the liability scale requires the prevalence and allele frequencies.')
              : tr('Une exposition mesurée avec erreur sous-estime r²_X et peut fausser le test.', 'An exposure measured with error underestimates r²_X and can bias the test.')),
    ],
    tables: [
      ResultTable(tr('Sens par variant', 'Direction per variant'), [tr('Variant', 'Variant'), 'r²_X', 'r²_Y', 'p', tr('Sens', 'Direction')], [
        for (var j = 0; j < k; j++)
          [rowNames[j], r2xSnp[j].toStringAsExponential(2), r2ySnp[j].toStringAsExponential(2), pSnp[j] < 1e-3 ? pSnp[j].toStringAsExponential(2) : f3(pSnp[j]),
            ok[j] ? '$ex0 → $out0' : tr('inverse', 'reverse')]
      ]),
    ],
    log: [tr('N_X = $nX, N_Y = $nY ; ${flagged.length} variant(s) de sens inverse.', 'N_X = $nX, N_Y = $nY; ${flagged.length} reversely oriented variant(s).')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Un variant choisi pour son association avec $ex0 pourrait agir d\'abord sur $out0, qui modifierait ensuite $ex0 : la MR estimerait alors un effet dans le mauvais sens. Le test de Steiger compare la part de variance expliquée des deux traits.',
          'A variant chosen for its association with $ex0 might act first on $out0, which would then change $ex0: MR would then estimate an effect in the wrong direction. The Steiger test compares the share of variance explained of the two traits.'),
      whatItMeans: tr(
          'Les variants expliquent ${pct(r2x)} de la variance de $ex0 et ${pct(r2y)} de celle de $out0 (${fmtP(p)}) : sens ${rightWay ? '$ex0 → $out0 compatible' : 'inverse possible'}.${ivwF != null && ivwAll != null ? ' IVW : ${ci(ivwAll)} avec tous les variants, ${ci(ivwF)} sans les ${flagged.length} variant(s) de sens inverse.' : ''}',
          'The variants explain ${pct(r2x)} of the variance of $ex0 and ${pct(r2y)} of that of $out0 (${fmtP(p)}): direction ${rightWay ? '$ex0 → $out0 compatible' : 'possibly reversed'}.${ivwF != null && ivwAll != null ? ' IVW: ${ci(ivwAll)} with all variants, ${ci(ivwF)} without the ${flagged.length} reversely oriented variant(s).' : ''}'),
      notJustified: tr(
          'Lire un test de Steiger favorable comme une preuve de causalité (il ne teste que le sens) ; l\'appliquer à une exposition mesurée avec beaucoup d\'erreur ; ignorer une MR inverse significative.',
          'Reading a favorable Steiger test as proof of causality (it only tests the direction); applying it to an exposure measured with much error; ignoring a significant reverse MR.'),
    ),
  );
  return MrSteiger(r2x, r2y, z, p, r2xSnp, r2ySnp, pSnp, ok, ivwAll, ivwF, result);
}
