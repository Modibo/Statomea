/// PCR quantitative :
///  - courbe standard : Ct = a + b·log10(quantité) ; efficacité E = 10^(−1/b) − 1 (IC depuis l'IC de la pente) ;
///    quantification des inconnues ;
///  - quantification relative : ΔΔCt (Livak et Schmittgen 2001), IC par le test t de Welch sur les ΔCt ;
///    méthode de Pfaffl (2001), corrigée des efficacités ;
///  - limite de détection : régression probit du taux de détection sur log10(concentration), LOD95 et IC
///    (méthode delta, comme MASS::dose.p).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';

double _mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;
double _var(List<double> x) {
  final m = _mean(x);
  return x.fold(0.0, (a, b) => a + (b - m) * (b - m)) / (x.length - 1);
}

/// Courbe standard et quantification d'inconnues.
AnalysisResult qpcrStandardCurve(List<double> log10Quantity, List<double> ct, {List<double> unknownCt = const [], double level = 0.95}) {
  if (log10Quantity.length != ct.length || ct.length < 3) {
    throw StatInputError('n_too_small', tr('Au moins 3 points (log10 quantité, Ct) appariés sont requis.', 'At least 3 paired points (log10 quantity, Ct) are required.'));
  }
  final n = ct.length;
  final mx = _mean(log10Quantity), my = _mean(ct);
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (log10Quantity[i] - mx) * (log10Quantity[i] - mx);
    sxy += (log10Quantity[i] - mx) * (ct[i] - my);
    syy += (ct[i] - my) * (ct[i] - my);
  }
  if (sxx == 0) throw StatInputError('constant', tr('Une seule quantité : la pente n\'est pas estimable.', 'A single quantity: the slope cannot be estimated.'));
  final b = sxy / sxx, a = my - b * mx;
  final rss = syy - b * sxy;
  final s2 = rss / (n - 2);
  final seB = math.sqrt(s2 / sxx);
  final q = tQuantile(1 - (1 - level) / 2, n - 2.0);
  final bLo = b - q * seB, bHi = b + q * seB;
  double eff(double slope) => math.pow(10, -1 / slope) - 1.0;
  final e = eff(b);
  final eCi = [eff(bLo), eff(bHi)]..sort();
  final r2 = 1 - rss / syy;
  final unknown = [for (final c in unknownCt) (c - a) / b];
  final effOk = e >= 0.9 && e <= 1.1;
  return AnalysisResult(
    methodId: 'qpcr_standard_curve',
    methodName: tr('qPCR : courbe standard et efficacité', 'qPCR: standard curve and efficiency'),
    inputs: {'points': n, 'unknowns': unknownCt.length, 'level': level},
    formula: tr('Ct = a + b·log10(quantité) (moindres carrés) ; efficacité E = 10^(−1/b) − 1 (100 % ⇔ b = −3,32) ; IC de E par transformation de l\'IC de b ; inconnue : log10 q = (Ct − a)/b.',
        'Ct = a + b·log10(quantity) (least squares); efficiency E = 10^(−1/b) − 1 (100% ⇔ b = −3.32); CI of E by transforming the CI of b; unknown: log10 q = (Ct − a)/b.'),
    estimates: [
      Estimate(tr('Efficacité d\'amplification', 'Amplification efficiency'), e, lower: eCi[0], upper: eCi[1], level: level),
      Estimate(tr('Pente', 'Slope'), b, lower: bLo, upper: bHi, level: level, se: seB),
      Estimate('R²', r2),
    ],
    statistics: {
      'slope': b,
      'intercept': a,
      'slope_se': seB,
      'r2': r2,
      'efficiency': e,
      'efficiency_lower': eCi[0],
      'efficiency_upper': eCi[1],
      for (var i = 0; i < unknown.length; i++) 'unknown_log10q_$i': unknown[i],
    },
    checks: [
      Check('efficiency', tr('Efficacité entre 90 % et 110 % (repère MIQE)', 'Efficiency between 90% and 110% (MIQE benchmark)'), effOk ? CheckStatus.ok : CheckStatus.warning,
          tr('E = ${fmtPct(e)} (IC ${fmtPct(eCi[0])} à ${fmtPct(eCi[1])}).', 'E = ${fmtPct(e)} (CI ${fmtPct(eCi[0])} to ${fmtPct(eCi[1])}).')),
      Check('linearity', tr('Linéarité (R² ≥ 0,98)', 'Linearity (R² ≥ 0.98)'), r2 >= 0.98 ? CheckStatus.ok : CheckStatus.warning, 'R² = ${fmt(r2, digits: 4)}.'),
      Check('range', tr('Inconnues dans la gamme étalonnée', 'Unknowns within the calibrated range'),
          unknown.every((u) => u >= log10Quantity.reduce(math.min) && u <= log10Quantity.reduce(math.max)) ? CheckStatus.ok : CheckStatus.violated,
          tr('Une extrapolation hors gamme n\'est pas validée.', 'Extrapolation outside the range is not validated.')),
    ],
    alerts: [
      if (!effOk)
        Alert('efficiency', Severity.caution,
            tr('Efficacité hors de 90–110 % : la méthode ΔΔCt (qui suppose 100 %) n\'est pas appropriée ; utiliser Pfaffl avec cette efficacité.',
                'Efficiency outside 90–110%: the ΔΔCt method (which assumes 100%) is not appropriate; use Pfaffl with this efficiency.')),
    ],
    tables: [
      if (unknown.isNotEmpty)
        ResultTable(tr('Inconnues', 'Unknowns'), ['Ct', 'log10 q', tr('Quantité', 'Quantity')], [
          for (var i = 0; i < unknown.length; i++) [fmt(unknownCt[i]), fmt(unknown[i]), fmt(math.pow(10, unknown[i]).toDouble())]
        ]),
    ],
    figures: {
      'standardCurve': {'x': log10Quantity, 'y': ct, 'intercept': a, 'slope': b},
    },
    interpretation: Interpretation(
      whyThisMethod: tr('Étalonner une qPCR : la pente de la droite Ct ~ log10(quantité) donne l\'efficacité d\'amplification.', 'Calibrating a qPCR: the slope of Ct ~ log10(quantity) gives the amplification efficiency.'),
      whatItMeans: tr('Pente ${fmt(b)}, efficacité ${fmtPct(e)} (IC ${fmtPct(eCi[0])} à ${fmtPct(eCi[1])}), R² ${fmt(r2, digits: 4)}.',
          'Slope ${fmt(b)}, efficiency ${fmtPct(e)} (CI ${fmtPct(eCi[0])} to ${fmtPct(eCi[1])}), R² ${fmt(r2, digits: 4)}.'),
      notJustified: tr('Quantifier hors de la gamme étalonnée ; juger la linéarité sur le seul R².', 'Quantifying outside the calibrated range; judging linearity on R² alone.'),
    ),
  );
}

/// Quantification relative ΔΔCt (Livak) et Pfaffl.
/// [eTarget], [eRef] : facteurs d'amplification (1 + efficacité), 2 = efficacité de 100 %.
AnalysisResult qpcrRelativeQuantification(List<double> targetControl, List<double> refControl, List<double> targetTreated, List<double> refTreated,
    {double eTarget = 2, double eRef = 2, double level = 0.95, String controlName = '', String treatedName = ''}) {
  if (targetControl.length != refControl.length || targetTreated.length != refTreated.length) {
    throw StatInputError('unpaired', tr('Ct cible et Ct de référence doivent être appariés échantillon par échantillon.', 'Target and reference Ct must be paired sample by sample.'));
  }
  if (targetControl.length < 2 || targetTreated.length < 2) {
    throw StatInputError('n_too_small', tr('Au moins 2 échantillons biologiques par groupe sont requis.', 'At least 2 biological samples per group are required.'));
  }
  final ctl = controlName.isEmpty ? tr('témoin', 'control') : controlName;
  final trt = treatedName.isEmpty ? tr('traité', 'treated') : treatedName;
  final dc = [for (var i = 0; i < targetControl.length; i++) targetControl[i] - refControl[i]];
  final dt = [for (var i = 0; i < targetTreated.length; i++) targetTreated[i] - refTreated[i]];
  final ddct = _mean(dt) - _mean(dc);
  final v1 = _var(dt) / dt.length, v2 = _var(dc) / dc.length;
  final se = math.sqrt(v1 + v2);
  final df = (v1 + v2) * (v1 + v2) / (v1 * v1 / (dt.length - 1) + v2 * v2 / (dc.length - 1));
  final q = tQuantile(1 - (1 - level) / 2, df);
  final lo = ddct - q * se, hi = ddct + q * se;
  final p = tTwoSidedP(ddct / se, df);
  final fold = math.pow(2, -ddct).toDouble();
  final foldLo = math.pow(2, -hi).toDouble(), foldHi = math.pow(2, -lo).toDouble();
  final pfaffl = math.pow(eTarget, _mean(targetControl) - _mean(targetTreated)) / math.pow(eRef, _mean(refControl) - _mean(refTreated));
  final assumes100 = eTarget == 2 && eRef == 2;
  return AnalysisResult(
    methodId: 'qpcr_relative',
    methodName: tr('qPCR : quantification relative (ΔΔCt, Pfaffl)', 'qPCR: relative quantification (ΔΔCt, Pfaffl)'),
    inputs: {'n_control': dc.length, 'n_treated': dt.length, 'eTarget': eTarget, 'eRef': eRef, 'level': level},
    formula: tr(
        'ΔCt = Ct cible − Ct référence par échantillon ; ΔΔCt = moyenne ΔCt($trt) − moyenne ΔCt($ctl) ; rapport = 2^(−ΔΔCt), IC = 2^(−bornes de l\'IC de Welch du ΔΔCt). Pfaffl : rapport = E_cible^(ΔCt cible témoin−traité) / E_réf^(ΔCt réf témoin−traité).',
        'ΔCt = target Ct − reference Ct per sample; ΔΔCt = mean ΔCt($trt) − mean ΔCt($ctl); ratio = 2^(−ΔΔCt), CI = 2^(−bounds of the Welch CI of ΔΔCt). Pfaffl: ratio = E_target^(target ΔCt control−treated) / E_ref^(reference ΔCt control−treated).'),
    estimates: [
      Estimate(tr('Rapport d\'expression $trt / $ctl (2^−ΔΔCt)', 'Expression ratio $trt / $ctl (2^−ΔΔCt)'), fold, lower: foldLo, upper: foldHi, level: level, pValue: p),
      Estimate('ΔΔCt', ddct, lower: lo, upper: hi, level: level, pValue: p, se: se),
      Estimate(tr('Rapport de Pfaffl (efficacités ${fmt(eTarget)} et ${fmt(eRef)})', 'Pfaffl ratio (efficiencies ${fmt(eTarget)} and ${fmt(eRef)})'), pfaffl.toDouble()),
    ],
    statistics: {'ddct': ddct, 'ddct_lower': lo, 'ddct_upper': hi, 'df': df, 'p': p, 'fold': fold, 'fold_lower': foldLo, 'fold_upper': foldHi, 'pfaffl': pfaffl.toDouble()},
    checks: [
      Check('efficiency', tr('Efficacités proches de 100 % pour ΔΔCt', 'Efficiencies close to 100% for ΔΔCt'), CheckStatus.notAssessed,
          assumes100
              ? tr('ΔΔCt suppose une efficacité de 100 % pour les deux gènes ; la vérifier par une courbe standard.', 'ΔΔCt assumes 100% efficiency for both genes; check it with a standard curve.')
              : tr('Efficacités fournies : préférer le rapport de Pfaffl.', 'Efficiencies supplied: prefer the Pfaffl ratio.')),
      Check('reference_gene', tr('Gène de référence stable entre les conditions', 'Reference gene stable across conditions'), CheckStatus.notAssessed,
          tr('Un gène de référence qui varie avec le traitement fausse le rapport (MIQE : plusieurs gènes de référence validés).', 'A reference gene that varies with treatment distorts the ratio (MIQE: several validated reference genes).')),
      Check('biological_replicates', tr('Réplicats biologiques (pas seulement techniques)', 'Biological (not only technical) replicates'), CheckStatus.notAssessed,
          tr('Les réplicats techniques d\'un même échantillon doivent être moyennés avant l\'analyse.', 'Technical replicates of the same sample must be averaged before the analysis.')),
    ],
    tables: [
      ResultTable('ΔCt', [tr('Groupe', 'Group'), 'n', tr('Moyenne ΔCt', 'Mean ΔCt'), tr('ÉT', 'SD')], [
        [ctl, '${dc.length}', fmt(_mean(dc)), fmt(math.sqrt(_var(dc)))],
        [trt, '${dt.length}', fmt(_mean(dt)), fmt(math.sqrt(_var(dt)))],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Comparer l\'expression d\'un gène entre deux conditions, normalisée par un gène de référence ; le test porte sur les ΔCt (échelle logarithmique).',
          'Comparing the expression of a gene between two conditions, normalized by a reference gene; the test is on the ΔCt (log scale).'),
      whatItMeans: tr('Expression $trt / $ctl : × ${fmt(fold)} (IC ${fmt(foldLo)} à ${fmt(foldHi)}), ${fmtP(p)} ; rapport de Pfaffl ${fmt(pfaffl.toDouble())}.',
          'Expression $trt / $ctl: × ${fmt(fold)} (CI ${fmt(foldLo)} to ${fmt(foldHi)}), ${fmtP(p)}; Pfaffl ratio ${fmt(pfaffl.toDouble())}.'),
      notJustified: tr('Traiter les réplicats techniques comme indépendants ; appliquer ΔΔCt sans vérifier les efficacités ; conclure sur la protéine à partir de l\'ARN messager.',
          'Treating technical replicates as independent; applying ΔΔCt without checking efficiencies; concluding about the protein from messenger RNA.'),
    ),
  );
}

/// Limite de détection (LOD) par régression probit : P(détection) = Φ(β₀ + β₁·log10 c).
AnalysisResult qpcrLimitOfDetection(List<double> concentration, List<int> detected, List<int> total, {double probability = 0.95, double level = 0.95}) {
  final k = concentration.length;
  if (k < 3 || detected.length != k || total.length != k) {
    throw StatInputError('n_too_small', tr('Au moins 3 concentrations avec détectés et réplicats sont requises.', 'At least 3 concentrations with detected and replicate counts are required.'));
  }
  final x = [for (final c in concentration) math.log(c) / math.ln10];
  final y = [for (var i = 0; i < k; i++) detected[i] / total[i]];
  // IRLS probit.
  var b0 = 0.0, b1 = 1.0;
  var cov = [0.0, 0.0, 0.0];
  for (var it = 0; it < 100; it++) {
    var s00 = 0.0, s01 = 0.0, s11 = 0.0, r0 = 0.0, r1 = 0.0;
    for (var i = 0; i < k; i++) {
      final eta = b0 + b1 * x[i];
      final mu = normalCdf(eta).clamp(1e-12, 1 - 1e-12);
      final d = normalPdf(eta);
      final w = total[i] * d * d / (mu * (1 - mu));
      final z = eta + (y[i] - mu) / d;
      s00 += w;
      s01 += w * x[i];
      s11 += w * x[i] * x[i];
      r0 += w * z;
      r1 += w * x[i] * z;
    }
    final det = s00 * s11 - s01 * s01;
    final n0 = (s11 * r0 - s01 * r1) / det, n1 = (s00 * r1 - s01 * r0) / det;
    cov = [s11 / det, -s01 / det, s00 / det];
    final done = (n0 - b0).abs() < 1e-12 && (n1 - b1).abs() < 1e-12;
    b0 = n0;
    b1 = n1;
    if (done) break;
  }
  if (!(b1 > 0)) {
    throw StatInputError('no_dose_response', tr('La détection n\'augmente pas avec la concentration : LOD non estimable.', 'Detection does not increase with concentration: LOD not estimable.'));
  }
  final zp = normalQuantile(probability);
  final x95 = (zp - b0) / b1;
  final g0 = -1 / b1, g1 = -(zp - b0) / (b1 * b1);
  final se = math.sqrt(g0 * g0 * cov[0] + 2 * g0 * g1 * cov[1] + g1 * g1 * cov[2]);
  final zq = normalQuantile(1 - (1 - level) / 2);
  final lod = math.pow(10, x95).toDouble();
  final lo = math.pow(10, x95 - zq * se).toDouble(), hi = math.pow(10, x95 + zq * se).toDouble();
  final pct = (probability * 100).round();
  final above = [for (var i = 0; i < k; i++) if (concentration[i] >= lod) i];
  return AnalysisResult(
    methodId: 'qpcr_lod',
    methodName: tr('Limite de détection (probit)', 'Limit of detection (probit)'),
    inputs: {'concentration': concentration, 'detected': detected, 'total': total, 'probability': probability, 'level': level},
    formula: tr('P(détection) = Φ(β₀ + β₁·log10 c), maximum de vraisemblance (probit) ; LOD$pct = 10^[(Φ⁻¹($probability) − β₀)/β₁], IC par la méthode delta sur l\'échelle log10 (comme MASS::dose.p).',
        'P(detection) = Φ(β₀ + β₁·log10 c), maximum likelihood (probit); LOD$pct = 10^[(Φ⁻¹($probability) − β₀)/β₁], CI by the delta method on the log10 scale (as MASS::dose.p).'),
    estimates: [
      Estimate(tr('LOD$pct (concentration détectée dans $pct % des cas)', 'LOD$pct (concentration detected $pct% of the time)'), lod, lower: lo, upper: hi, level: level),
    ],
    statistics: {'b0': b0, 'b1': b1, 'log10_lod': x95, 'log10_lod_se': se, 'lod': lod, 'lod_lower': lo, 'lod_upper': hi},
    checks: [
      Check('replicates', tr('Au moins 20 réplicats par concentration (repère CLSI EP17)', 'At least 20 replicates per concentration (CLSI EP17 benchmark)'),
          total.every((t) => t >= 20) ? CheckStatus.ok : CheckStatus.warning, tr('Réplicats : ${total.join(", ")}.', 'Replicates: ${total.join(", ")}.')),
      Check('bracketing', tr('Concentrations encadrant la LOD', 'Concentrations bracketing the LOD'),
          above.isNotEmpty && above.length < k ? CheckStatus.ok : CheckStatus.warning,
          tr('Une LOD extrapolée hors des concentrations testées est peu fiable.', 'An LOD extrapolated outside the tested concentrations is unreliable.')),
    ],
    tables: [
      ResultTable(tr('Détection', 'Detection'), [tr('Concentration', 'Concentration'), tr('Détectés / réplicats', 'Detected / replicates'), tr('Taux', 'Rate'), tr('Probit ajusté', 'Fitted probit')], [
        for (var i = 0; i < k; i++) [fmt(concentration[i]), '${detected[i]} / ${total[i]}', fmtPct(y[i]), fmtPct(normalCdf(b0 + b1 * x[i]))]
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Estimer la plus petite concentration détectée avec une probabilité donnée, à partir de réplicats à plusieurs dilutions.', 'Estimating the lowest concentration detected with a given probability, from replicates at several dilutions.'),
      whatItMeans: tr('LOD$pct = ${fmt(lod)} (IC ${fmt(lo)} à ${fmt(hi)}).', 'LOD$pct = ${fmt(lod)} (CI ${fmt(lo)} to ${fmt(hi)}).'),
      notJustified: tr('Confondre limite de détection et limite de quantification ; transposer la LOD à une autre matrice ou un autre lot de réactifs.',
          'Confusing the limit of detection with the limit of quantification; transferring the LOD to another matrix or reagent lot.'),
    ),
  );
}
