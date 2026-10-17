/// Atelier de puissance et de taille d'échantillon : pour chaque plan, n pour une puissance visée OU puissance pour un
/// n donné, avec courbe de puissance. Validé contre validation/r/42_puissance.R (pwr 1.3, powerSurvEpi 0.1.3, stats).
///  - deux moyennes indépendantes (groupes éventuellement inégaux) : pwr.t2n.test ; apparié / un échantillon :
///    power.t.test(strict = TRUE) — t non centrale, deux queues ;
///  - deux proportions : power.prop.test ;
///  - cas-témoins non apparié (OR, exposition chez les témoins, k témoins par cas) : pwr.2p2n.test (arcsinus) ;
///  - survie, essai à deux bras : Freedman (powerSurvEpi::ssizeCT.default, powerCT.default) et événements de
///    Schoenfeld ;
///  - GWAS, test allélique cas-témoins : χ² non central à 1 ddl, α = 5e-8.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/special.dart';
import '../model/result.dart';
import 'sample_size.dart' show noncentralTCdf;

// ------------------------------------------------------------------ fonctions de puissance (validées contre R)

/// Deux moyennes, n1 et n2 sujets, effet standardisé d = Δ/σ (pwr.t2n.test, bilatéral, deux queues).
double powerTwoMeansD(double n1, double n2, double d, {double alpha = 0.05}) {
  final nu = n1 + n2 - 2, ncp = d.abs() / math.sqrt(1 / n1 + 1 / n2);
  final qu = tQuantile(1 - alpha / 2, nu);
  return (1 - noncentralTCdf(qu, nu, ncp)) + noncentralTCdf(-qu, nu, ncp);
}

/// Un échantillon ou différences appariées, n sujets (power.t.test strict = TRUE).
double powerOneSampleD(double n, double d, {double alpha = 0.05}) {
  final nu = n - 1, ncp = math.sqrt(n) * d.abs();
  final qu = tQuantile(1 - alpha / 2, nu);
  return (1 - noncentralTCdf(qu, nu, ncp)) + noncentralTCdf(-qu, nu, ncp);
}

/// Deux proportions, n par groupe (power.prop.test).
double powerTwoProportionsN(double n, double p1, double p2, {double alpha = 0.05}) {
  final qu = normalQuantile(1 - alpha / 2);
  final q1 = 1 - p1, q2 = 1 - p2;
  return normalCdf((math.sqrt(n) * (p1 - p2).abs() - qu * math.sqrt((p1 + p2) * (q1 + q2) / 2)) / math.sqrt(p1 * q1 + p2 * q2));
}

/// Fréquence de l'exposition (ou de l'allèle) chez les cas, d'après l'OR et la fréquence chez les témoins.
double exposureInCases(double or, double p0) => or * p0 / (1 + p0 * (or - 1));

/// Arcsinus (Cohen) : h = 2 asin √p1 − 2 asin √p0, puissance bilatérale à deux queues (pwr.2p2n.test).
double powerArcsine(double h, double n1, double n2, {double alpha = 0.05}) {
  final z = normalQuantile(1 - alpha / 2), s = h.abs() * math.sqrt(n1 * n2 / (n1 + n2));
  return normalCdf(s - z) + normalCdf(-z - s);
}

/// Survie, Freedman : nombre total d'événements requis m et puissance pour m événements (k = nE/nC).
double freedmanEvents(double hr, double k, {double alpha = 0.05, double power = 0.8}) {
  final za = normalQuantile(1 - alpha / 2), zb = normalQuantile(power);
  final r = (k * hr + 1) / (hr - 1);
  return r * r * (za + zb) * (za + zb) / k;
}

double freedmanPower(double hr, double k, double events, {double alpha = 0.05}) =>
    normalCdf(math.sqrt(k * events) * (hr - 1).abs() / (k * hr + 1) - normalQuantile(1 - alpha / 2));

/// Événements requis selon Schoenfeld : (z₁₋α/₂ + z₁₋β)²(1 + k)²/(k·log²HR).
double schoenfeldEvents(double hr, double k, {double alpha = 0.05, double power = 0.8}) {
  final za = normalQuantile(1 - alpha / 2), zb = normalQuantile(power);
  final l = math.log(hr);
  return (za + zb) * (za + zb) * (1 + k) * (1 + k) / (k * l * l);
}

/// GWAS, test allélique : non-centralité λ et puissance P(χ²₁(λ) > χ²₁;₁₋α) = Φ(√λ − z) + Φ(−√λ − z).
({double lambda, double power}) gwasAllelicPower(double maf, double or, double cases, double controls, {double alpha = 5e-8}) {
  final q1 = exposureInCases(or, maf);
  final pbar = (q1 * cases + maf * controls) / (cases + controls);
  final lam = (q1 - maf) * (q1 - maf) / (pbar * (1 - pbar) * (1 / (2 * cases) + 1 / (2 * controls)));
  final z = normalQuantile(1 - alpha / 2), s = math.sqrt(lam);
  return (lambda: lam, power: normalCdf(s - z) + normalCdf(-z - s));
}

/// n (continu) tel que power(n) = target ; n ≥ [lo].
double solveSampleSize(double Function(double) power, double target, {double lo = 2}) {
  if (power(lo) >= target) return lo;
  var hi = lo * 2;
  while (power(hi) < target) {
    hi *= 2;
    if (hi > 1e10) throw StatInputError('n_unreachable', tr('Puissance cible inatteignable.', 'Target power unreachable.'));
  }
  return brentRoot((n) => power(n) - target, lo, hi, tol: 1e-10);
}

// ------------------------------------------------------------------ résultats

void _check(bool ok, String fr, String en) {
  if (!ok) throw StatInputError('bad_param', tr(fr, en));
}

/// Courbe de puissance : puissance selon l'effectif de référence (cas, sujets du groupe 1, ou événements).
Map<String, Object?> _curve(double Function(double) power, double nRef, double target, String xLabel) {
  final lo = math.max(2.0, nRef * 0.2), hi = math.max(lo + 4, nRef * 2.2);
  final xs = [for (var i = 0; i <= 60; i++) lo + (hi - lo) * i / 60];
  return {'n': xs, 'power': [for (final x in xs) power(x)], 'target': target, 'nStar': nRef, 'xLabel': xLabel};
}

AnalysisResult _result({
  required String methodId,
  required String name,
  required Map<String, Object?> inputs,
  required String formula,
  required bool solveN,
  required double nExact,
  required double achieved,
  required String unitFr,
  required String unitEn,
  required List<(String, String, double)> sizes, // (libellé FR, libellé EN, effectif)
  required Map<String, Object?> curve,
  required String effectFr,
  required String effectEn,
  required double alpha,
  Map<String, double> extra = const {},
  List<Check> checks = const [],
  List<Alert> alerts = const [],
  String? whyFr,
  String? whyEn,
}) {
  final total = sizes.fold(0.0, (s, e) => s + e.$3);
  final pctP = fmtPct(achieved, decimals: 1);
  return AnalysisResult(
    methodId: methodId,
    methodName: name,
    inputs: inputs,
    formula: formula,
    estimates: [
      if (solveN) Estimate(tr('$unitFr (exact, non arrondi)', '$unitEn (exact, unrounded)'), nExact),
      for (final s in sizes) Estimate(tr(s.$1, s.$2), s.$3),
      Estimate(tr('Puissance', 'Power'), achieved),
    ],
    statistics: {'n_exact': nExact, 'power': achieved, 'n_total': total, for (var i = 0; i < sizes.length; i++) 'n_$i': sizes[i].$3, ...extra},
    checks: [
      Check('effect_justified', tr('Effet à détecter justifié (pertinence clinique, données antérieures)', 'Effect to detect justified (clinical relevance, prior data)'), CheckStatus.notAssessed,
          tr('L\'effet doit être la plus petite différence qui changerait la pratique, pas l\'effet espéré ni celui d\'une petite étude pilote (souvent surestimé).',
              'The effect must be the smallest difference that would change practice, not the hoped-for effect nor that of a small pilot study (often overestimated).')),
      ...checks,
    ],
    alerts: [
      if (achieved < 0.8 && !solveN)
        Alert('low_power', achieved < 0.5 ? Severity.serious : Severity.caution,
            tr('Puissance de $pctP : un résultat non significatif ne permettrait pas de conclure à l\'absence d\'effet.', 'Power of $pctP: a non-significant result would not allow concluding that there is no effect.')),
      ...alerts,
    ],
    tables: [
      ResultTable(tr('Effectifs', 'Sample sizes'), [tr('Groupe', 'Group'), 'n'], [
        for (final s in sizes) [tr(s.$1, s.$2), fmt(s.$3, digits: 0)],
        [tr('Total', 'Total'), fmt(total, digits: 0)],
      ]),
      ResultTable(tr('Hypothèses du calcul', 'Calculation assumptions'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('Effet à détecter', 'Effect to detect'), tr(effectFr, effectEn)],
        ['α (${tr('bilatéral', 'two-sided')})', fmt(alpha, digits: 3)],
        [tr('Puissance', 'Power'), pctP],
      ]),
    ],
    figures: {'powerCurve': curve},
    interpretation: Interpretation(
      whyThisMethod: tr(whyFr ?? '', whyEn ?? ''),
      whatItMeans: tr('${[for (final s in sizes) '${s.$1} : ${fmt(s.$3, digits: 0)}'].join(' ; ')} (total ${fmt(total, digits: 0)}) donnent une puissance de $pctP pour détecter $effectFr au risque α = ${fmt(alpha, digits: 3)} (bilatéral).',
          '${[for (final s in sizes) '${s.$2}: ${fmt(s.$3, digits: 0)}'].join('; ')} (total ${fmt(total, digits: 0)}) give $pctP power to detect $effectEn at α = ${fmt(alpha, digits: 3)} (two-sided).'),
      notJustified: tr('Calculer la puissance a posteriori à partir de l\'effet observé ; présenter cet effectif comme suffisant pour des analyses secondaires ou de sous-groupes ; oublier les perdus de vue et les données manquantes.',
          'Computing post hoc power from the observed effect; presenting this sample size as sufficient for secondary or subgroup analyses; forgetting loss to follow-up and missing data.'),
    ),
  );
}

/// Plan de comparaison de moyennes.
enum MeansDesign { twoGroups, paired, oneSample }

/// Moyennes : [delta] (différence, ou différence moyenne appariée), [sd] (ÉT, ou ÉT des différences) ; [n] = sujets du
/// groupe 1 (ou paires, ou sujets) pour calculer la puissance, sinon n pour [power] ; [ratio] = n2/n1.
AnalysisResult powerMeans({required double delta, required double sd, MeansDesign design = MeansDesign.twoGroups, double ratio = 1, double alpha = 0.05, double power = 0.8, double? n}) {
  _check(delta > 0 && sd > 0, 'Différence et ÉT doivent être > 0.', 'Difference and SD must be > 0.');
  _check(alpha > 0 && alpha < 1 && power > 0 && power < 1 && ratio > 0, 'α, puissance entre 0 et 1, ratio > 0.', 'α and power between 0 and 1, ratio > 0.');
  final d = delta / sd;
  final two = design == MeansDesign.twoGroups;
  double pw(double n1) => two ? powerTwoMeansD(n1, ratio * n1, d, alpha: alpha) : powerOneSampleD(n1, d, alpha: alpha);
  final solveN = n == null;
  final nExact = solveN ? solveSampleSize(pw, power, lo: 2.0001) : n;
  final n1 = solveN ? nExact.ceilToDouble() : n;
  final n2 = two ? (solveN ? (ratio * nExact).ceilToDouble() : (ratio * n).roundToDouble()) : 0.0;
  final achieved = two ? powerTwoMeansD(n1, n2, d, alpha: alpha) : powerOneSampleD(n1, d, alpha: alpha);
  final label = switch (design) {
    MeansDesign.twoGroups => (tr('deux moyennes indépendantes', 'two independent means'), 'pwr.t2n.test'),
    MeansDesign.paired => (tr('mesures appariées', 'paired measurements'), 'power.t.test(type = "paired", strict = TRUE)'),
    MeansDesign.oneSample => (tr('une moyenne contre une valeur de référence', 'one mean against a reference value'), 'power.t.test(type = "one.sample", strict = TRUE)'),
  };
  return _result(
    methodId: 'power_means',
    name: tr('Puissance et effectif : ${label.$1}', 'Power and sample size: ${label.$1}'),
    inputs: {'delta': delta, 'sd': sd, 'design': design.name, 'ratio': ratio, 'alpha': alpha, 'power': power, 'n': n},
    formula: two
        ? tr('Effet standardisé d = Δ/σ ; t non centrale à n1 + n2 − 2 ddl, paramètre d/√(1/n1 + 1/n2) ; puissance bilatérale (deux queues) comme ${label.$2}.',
            'Standardized effect d = Δ/σ; non-central t with n1 + n2 − 2 df, parameter d/√(1/n1 + 1/n2); two-sided power (both tails) as ${label.$2}.')
        : tr('d = Δ/σ (σ des différences si apparié) ; t non centrale à n − 1 ddl, paramètre √n·d ; deux queues comme ${label.$2}.',
            'd = Δ/σ (SD of the differences if paired); non-central t with n − 1 df, parameter √n·d; both tails as ${label.$2}.'),
    solveN: solveN,
    nExact: nExact,
    achieved: achieved,
    unitFr: two ? 'n du groupe 1' : (design == MeansDesign.paired ? 'Nombre de paires' : 'n'),
    unitEn: two ? 'n of group 1' : (design == MeansDesign.paired ? 'Number of pairs' : 'n'),
    sizes: two
        ? [('Groupe 1', 'Group 1', n1), ('Groupe 2', 'Group 2', n2)]
        : [(design == MeansDesign.paired ? 'Paires' : 'Sujets', design == MeansDesign.paired ? 'Pairs' : 'Subjects', n1)],
    curve: _curve(pw, nExact, power, two ? tr('Sujets du groupe 1', 'Subjects in group 1') : tr('Sujets', 'Subjects')),
    effectFr: 'une différence de ${fmt(delta)} (ÉT ${fmt(sd)}, d = ${fmt(d, digits: 2)})',
    effectEn: 'a difference of ${fmt(delta)} (SD ${fmt(sd)}, d = ${fmt(d, digits: 2)})',
    alpha: alpha,
    extra: {'d': d},
    checks: [
      Check('sd_source', tr('ÉT issu d\'une source documentée', 'SD from a documented source'), CheckStatus.notAssessed,
          tr('Un ÉT sous-estimé conduit à une étude sous-dimensionnée ; en apparié, c\'est l\'ÉT des différences qui compte.', 'An underestimated SD leads to an underpowered study; when paired, the SD of the differences is what matters.')),
    ],
    whyFr: 'Critère quantitatif ; test t de Student bilatéral.',
    whyEn: 'Quantitative outcome; two-sided Student t-test.',
  );
}

/// Deux proportions (groupes égaux) : n par groupe pour [power], ou puissance pour [n] par groupe.
AnalysisResult powerProportions({required double p1, required double p2, double alpha = 0.05, double power = 0.8, double? n}) {
  _check(p1 > 0 && p1 < 1 && p2 > 0 && p2 < 1 && p1 != p2, 'Proportions strictement entre 0 et 1, et différentes.', 'Proportions strictly between 0 and 1, and different.');
  double pw(double x) => powerTwoProportionsN(x, p1, p2, alpha: alpha);
  final solveN = n == null;
  final nExact = solveN ? solveSampleSize(pw, power) : n;
  final nn = solveN ? nExact.ceilToDouble() : n;
  return _result(
    methodId: 'power_proportions',
    name: tr('Puissance et effectif : deux proportions', 'Power and sample size: two proportions'),
    inputs: {'p1': p1, 'p2': p2, 'alpha': alpha, 'power': power, 'n': n},
    formula: tr('Puissance = Φ{[√n|p1 − p2| − z₁₋α/₂√((p1 + p2)(q1 + q2)/2)] / √(p1q1 + p2q2)} (power.prop.test, sans correction de continuité).',
        'Power = Φ{[√n|p1 − p2| − z₁₋α/₂√((p1 + p2)(q1 + q2)/2)] / √(p1q1 + p2q2)} (power.prop.test, without continuity correction).'),
    solveN: solveN,
    nExact: nExact,
    achieved: pw(nn),
    unitFr: 'n par groupe',
    unitEn: 'n per group',
    sizes: [('Groupe 1', 'Group 1', nn), ('Groupe 2', 'Group 2', nn)],
    curve: _curve(pw, nExact, power, tr('Sujets par groupe', 'Subjects per group')),
    effectFr: '${fmtPct(p1)} contre ${fmtPct(p2)}',
    effectEn: '${fmtPct(p1)} versus ${fmtPct(p2)}',
    alpha: alpha,
    alerts: [
      if (math.min(p1, p2) * nn < 5)
        Alert('few_expected_events', Severity.caution, tr('Moins de 5 événements attendus dans un groupe : approximation normale fragile.', 'Fewer than 5 expected events in a group: fragile normal approximation.')),
    ],
    whyFr: 'Critère binaire, deux groupes indépendants de même taille.',
    whyEn: 'Binary outcome, two independent groups of equal size.',
  );
}

/// Cas-témoins non apparié : OR à détecter, fréquence de l'exposition chez les témoins [p0], [ratio] témoins par cas ;
/// nombre de cas pour [power], ou puissance pour [nCases].
AnalysisResult powerCaseControl({required double or, required double p0, double ratio = 1, double alpha = 0.05, double power = 0.8, double? nCases}) {
  _check(or > 0 && or != 1 && p0 > 0 && p0 < 1 && ratio > 0, 'OR > 0 et ≠ 1, exposition des témoins entre 0 et 1, ratio > 0.', 'OR > 0 and ≠ 1, exposure in controls between 0 and 1, ratio > 0.');
  final p1 = exposureInCases(or, p0);
  final h = 2 * math.asin(math.sqrt(p1)) - 2 * math.asin(math.sqrt(p0));
  double pw(double n) => powerArcsine(h, n, ratio * n, alpha: alpha);
  final solveN = nCases == null;
  final nExact = solveN ? solveSampleSize(pw, power) : nCases;
  final n1 = solveN ? nExact.ceilToDouble() : nCases;
  final n2 = solveN ? (ratio * nExact).ceilToDouble() : (ratio * nCases).roundToDouble();
  return _result(
    methodId: 'power_case_control',
    name: tr('Puissance et effectif : étude cas-témoins', 'Power and sample size: case-control study'),
    inputs: {'or': or, 'p0': p0, 'ratio': ratio, 'alpha': alpha, 'power': power, 'nCases': nCases},
    formula: tr('Exposition chez les cas p1 = OR·p0/(1 + p0(OR − 1)) ; h = 2 asin √p1 − 2 asin √p0 ; puissance = Φ(|h|√(n1n2/(n1 + n2)) − z₁₋α/₂) + Φ(−z₁₋α/₂ − |h|√(…)) (pwr.2p2n.test).',
        'Exposure in cases p1 = OR·p0/(1 + p0(OR − 1)); h = 2 asin √p1 − 2 asin √p0; power = Φ(|h|√(n1n2/(n1 + n2)) − z₁₋α/₂) + Φ(−z₁₋α/₂ − |h|√(…)) (pwr.2p2n.test).'),
    solveN: solveN,
    nExact: nExact,
    achieved: powerArcsine(h, n1, n2, alpha: alpha),
    unitFr: 'Nombre de cas',
    unitEn: 'Number of cases',
    sizes: [('Cas', 'Cases', n1), ('Témoins', 'Controls', n2)],
    curve: _curve(pw, nExact, power, tr('Nombre de cas', 'Number of cases')),
    effectFr: 'un OR de ${fmt(or)} (exposition : ${fmtPct(p0)} chez les témoins, ${fmtPct(p1)} attendue chez les cas)',
    effectEn: 'an OR of ${fmt(or)} (exposure: ${fmtPct(p0)} in controls, ${fmtPct(p1)} expected in cases)',
    alpha: alpha,
    extra: {'p1': p1, 'h': h},
    alerts: [
      if (ratio > 4)
        Alert('ratio_gain', Severity.info, tr('Au-delà de 4 témoins par cas, le gain de puissance devient faible.', 'Beyond 4 controls per case, the gain in power becomes small.')),
    ],
    whyFr: 'Étude cas-témoins : on compare la fréquence de l\'exposition entre cas et témoins.',
    whyEn: 'Case-control study: the frequency of exposure is compared between cases and controls.',
  );
}

/// Survie, essai à deux bras : HR à détecter, probabilité d'événement sur l'étude dans le bras contrôle [pC], [ratio] =
/// nE/nC ; effectifs pour [power] (Freedman), ou puissance pour [nControl] patients du bras contrôle.
AnalysisResult powerSurvival({required double hr, required double pC, double ratio = 1, double alpha = 0.05, double power = 0.8, double? nControl}) {
  _check(hr > 0 && hr != 1 && pC > 0 && pC < 1 && ratio > 0, 'HR > 0 et ≠ 1, probabilité d\'événement entre 0 et 1, ratio > 0.', 'HR > 0 and ≠ 1, event probability between 0 and 1, ratio > 0.');
  final pE = 1 - math.pow(1 - pC, hr).toDouble();
  final denom = ratio * pE + pC;
  double pw(double nC) => freedmanPower(hr, ratio, nC * denom, alpha: alpha);
  final solveN = nControl == null;
  final m = freedmanEvents(hr, ratio, alpha: alpha, power: power);
  final nExact = solveN ? m / denom : nControl;
  final nC = solveN ? (m / denom).ceilToDouble() : nControl;
  final nE = solveN ? (m * ratio / denom).ceilToDouble() : (ratio * nControl).roundToDouble();
  final events = nE * pE + nC * pC;
  final achieved = freedmanPower(hr, nE / nC, events, alpha: alpha);
  final sch = schoenfeldEvents(hr, ratio, alpha: alpha, power: power);
  return _result(
    methodId: 'power_survival',
    name: tr('Puissance et effectif : survie (essai à deux bras)', 'Power and sample size: survival (two-arm trial)'),
    inputs: {'hr': hr, 'pC': pC, 'ratio': ratio, 'alpha': alpha, 'power': power, 'nControl': nControl},
    formula: tr(
        'Freedman (1982) : événements m = [(k·HR + 1)/(HR − 1)]²(z₁₋α/₂ + z₁₋β)²/k, k = nE/nC ; nC = m/(k·pE + pC), nE = k·nC (powerSurvEpi::ssizeCT) ; puissance Φ(√(k·m)|HR − 1|/(k·HR + 1) − z₁₋α/₂). '
            'pE = 1 − (1 − pC)^HR (risques proportionnels). En regard : événements de Schoenfeld (z₁₋α/₂ + z₁₋β)²(1 + k)²/(k·log²HR).',
        'Freedman (1982): events m = [(k·HR + 1)/(HR − 1)]²(z₁₋α/₂ + z₁₋β)²/k, k = nE/nC; nC = m/(k·pE + pC), nE = k·nC (powerSurvEpi::ssizeCT); power Φ(√(k·m)|HR − 1|/(k·HR + 1) − z₁₋α/₂). '
            'pE = 1 − (1 − pC)^HR (proportional hazards). Alongside: Schoenfeld events (z₁₋α/₂ + z₁₋β)²(1 + k)²/(k·log²HR).'),
    solveN: solveN,
    nExact: nExact,
    achieved: achieved,
    unitFr: 'n du bras contrôle',
    unitEn: 'n of the control arm',
    sizes: [('Bras expérimental', 'Experimental arm', nE), ('Bras contrôle', 'Control arm', nC)],
    curve: _curve(pw, nExact, power, tr('Patients du bras contrôle', 'Patients in the control arm')),
    effectFr: 'un HR de ${fmt(hr)} (événements sur l\'étude : ${fmtPct(pC)} en contrôle, ${fmtPct(pE)} attendus en expérimental)',
    effectEn: 'an HR of ${fmt(hr)} (events over the study: ${fmtPct(pC)} in control, ${fmtPct(pE)} expected in experimental)',
    alpha: alpha,
    extra: {'pE': pE, 'events_freedman': solveN ? m : events, 'events_schoenfeld': sch, 'events_expected': events},
    checks: [
      Check('event_probability', tr('Probabilité d\'événement réaliste (durée de recrutement et de suivi)', 'Realistic event probability (accrual and follow-up duration)'), CheckStatus.notAssessed,
          tr('C\'est le nombre d\'ÉVÉNEMENTS qui fait la puissance : ${fmt(solveN ? m : events, digits: 0)} attendus (Schoenfeld : ${fmt(sch, digits: 0)}). Un suivi plus court ou moins d\'événements que prévu réduit la puissance.',
              'It is the number of EVENTS that drives power: ${fmt(solveN ? m : events, digits: 0)} expected (Schoenfeld: ${fmt(sch, digits: 0)}). A shorter follow-up or fewer events than planned reduces power.')),
    ],
    whyFr: 'Critère de délai jusqu\'à un événement ; comparaison par le log-rank sous risques proportionnels.',
    whyEn: 'Time-to-event outcome; comparison by the log-rank test under proportional hazards.',
  );
}

/// GWAS : test allélique cas-témoins à [alpha] (5e-8 par défaut), OR par allèle, fréquence de l'allèle chez les témoins
/// [maf], [ratio] témoins par cas ; nombre de cas pour [power], ou puissance pour [nCases].
AnalysisResult powerGwas({required double maf, required double or, double ratio = 1, double alpha = 5e-8, double power = 0.8, double? nCases}) {
  _check(maf > 0 && maf < 1 && or > 0 && or != 1 && ratio > 0, 'Fréquence allélique entre 0 et 1, OR > 0 et ≠ 1, ratio > 0.', 'Allele frequency between 0 and 1, OR > 0 and ≠ 1, ratio > 0.');
  double pw(double n) => gwasAllelicPower(maf, or, n, ratio * n, alpha: alpha).power;
  final solveN = nCases == null;
  final nExact = solveN ? solveSampleSize(pw, power) : nCases;
  final n1 = solveN ? nExact.ceilToDouble() : nCases;
  final n2 = solveN ? (ratio * nExact).ceilToDouble() : (ratio * nCases).roundToDouble();
  final g = gwasAllelicPower(maf, or, n1, n2, alpha: alpha);
  final nominal = gwasAllelicPower(maf, or, n1, n2, alpha: 0.05).power;
  return _result(
    methodId: 'power_gwas',
    name: tr('Puissance et effectif : étude pangénomique (GWAS)', 'Power and sample size: genome-wide association study (GWAS)'),
    inputs: {'maf': maf, 'or': or, 'ratio': ratio, 'alpha': alpha, 'power': power, 'nCases': nCases},
    formula: tr('Fréquence chez les cas q1 = OR·p0/(1 + p0(OR − 1)) (OR par allèle) ; non-centralité λ = (q1 − p0)²/[p̄(1 − p̄)(1/(2Nca) + 1/(2Nco))] ; puissance = P(χ²₁(λ) > χ²₁;₁₋α) = Φ(√λ − z) + Φ(−√λ − z), z = z₁₋α/₂.',
        'Frequency in cases q1 = OR·p0/(1 + p0(OR − 1)) (per-allele OR); non-centrality λ = (q1 − p0)²/[p̄(1 − p̄)(1/(2Nca) + 1/(2Nco))]; power = P(χ²₁(λ) > χ²₁;₁₋α) = Φ(√λ − z) + Φ(−√λ − z), z = z₁₋α/₂.'),
    solveN: solveN,
    nExact: nExact,
    achieved: g.power,
    unitFr: 'Nombre de cas',
    unitEn: 'Number of cases',
    sizes: [('Cas', 'Cases', n1), ('Témoins', 'Controls', n2)],
    curve: _curve(pw, nExact, power, tr('Nombre de cas', 'Number of cases')),
    effectFr: 'un OR par allèle de ${fmt(or)} (fréquence allélique ${fmtPct(maf)} chez les témoins)',
    effectEn: 'a per-allele OR of ${fmt(or)} (allele frequency ${fmtPct(maf)} in controls)',
    alpha: alpha,
    extra: {'lambda': g.lambda, 'power_nominal': nominal},
    checks: [
      Check('winners_curse', tr('OR réaliste (malédiction du vainqueur)', 'Realistic OR (winner\'s curse)'), CheckStatus.notAssessed,
          tr('Les OR publiés lors de la découverte sont surestimés ; pour un caractère complexe, la plupart des OR sont < 1,2. À α = 0,05, la puissance serait de ${fmtPct(nominal)}.',
              'ORs published at discovery are overestimated; for a complex trait, most ORs are < 1.2. At α = 0.05, power would be ${fmtPct(nominal)}.')),
    ],
    whyFr: 'Balayage du génome : seuil de significativité pangénomique (5e-8) pour environ un million de tests indépendants.',
    whyEn: 'Genome scan: genome-wide significance threshold (5e-8) for about one million independent tests.',
  );
}
