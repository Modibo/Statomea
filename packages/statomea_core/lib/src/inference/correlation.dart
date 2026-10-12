/// Corrélations (Pearson, Spearman) et accord entre deux méthodes de mesure
/// (Bland & Altman 1986, 1999).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../descriptive/descriptive.dart';
import '../math/distributions.dart';
import '../model/result.dart';

({List<double> x, List<double> y, int dropped}) _complete(List<double?> x, List<double?> y) {
  if (x.length != y.length) {
    throw StatInputError('unpaired_lengths', tr("Les deux variables n'ont pas le même nombre de lignes.", 'The two variables do not have the same number of rows.'));
  }
  final a = <double>[], b = <double>[];
  for (var i = 0; i < x.length; i++) {
    final u = x[i], v = y[i];
    if (u != null && v != null && u.isFinite && v.isFinite) {
      a.add(u);
      b.add(v);
    }
  }
  return (x: a, y: b, dropped: x.length - a.length);
}

double pearsonR(List<double> x, List<double> y) {
  final mx = mean(x), my = mean(y);
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < x.length; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  return sxy / math.sqrt(sxx * syy);
}

AnalysisResult correlation(List<double?> xr, List<double?> yr,
    {bool spearman = false, double level = 0.95, String xName = 'X', String yName = 'Y'}) {
  final c = _complete(xr, yr);
  final n = c.x.length;
  if (n < 3) throw StatInputError('n_too_small', tr('Au moins 3 paires complètes sont requises.', 'At least 3 complete pairs are required.'));
  final xs = spearman ? rankWithTies(c.x).ranks : c.x;
  final ys = spearman ? rankWithTies(c.y).ranks : c.y;
  final r = pearsonR(xs, ys);
  if (r.isNaN) throw StatInputError('constant', tr('Une variable est constante : corrélation indéfinie.', 'A variable is constant: correlation undefined.'));
  final df = n - 2.0;
  final t = r * math.sqrt(df / (1 - r * r));
  final p = r.abs() >= 1 ? 0.0 : tTwoSidedP(t, df);
  double? lo, hi;
  if (!spearman && n > 3) {
    final z = 0.5 * math.log((1 + r) / (1 - r));
    final q = normalQuantile(1 - (1 - level) / 2) / math.sqrt(n - 3);
    lo = _tanh(z - q);
    hi = _tanh(z + q);
  }
  final name = spearman ? tr('ρ de Spearman', "Spearman's ρ") : tr('r de Pearson', "Pearson's r");
  final e = Estimate(name, r, lower: lo, upper: hi, level: level, pValue: p);
  return AnalysisResult(
    methodId: spearman ? 'spearman' : 'pearson',
    methodName: spearman ? tr('Corrélation de Spearman', 'Spearman correlation') : tr('Corrélation de Pearson', 'Pearson correlation'),
    inputs: {'n': n, 'dropped': c.dropped, 'level': level},
    formula: spearman
        ? tr('ρ = corrélation de Pearson des rangs ; t = ρ√[(n−2)/(1−ρ²)] (approximation de Student).', "ρ = Pearson correlation of ranks; t = ρ√[(n−2)/(1−ρ²)] (Student approximation).")
        : tr('r = Σ(x−x̄)(y−ȳ)/√[Σ(x−x̄)²Σ(y−ȳ)²] ; t = r√[(n−2)/(1−r²)] ; IC par z de Fisher = atanh(r) ± z/√(n−3).',
            "r = Σ(x−x̄)(y−ȳ)/√[Σ(x−x̄)²Σ(y−ȳ)²]; t = r√[(n−2)/(1−r²)]; CI by Fisher's z = atanh(r) ± z/√(n−3)."),
    estimates: [e, if (!spearman) Estimate(tr('r² (part de variance commune)', 'r² (shared variance)'), r * r)],
    statistics: {'t': t, 'df': df, 'p': p},
    checks: [
      Check('linearity', spearman ? tr('Relation monotone', 'Monotonic relationship') : tr('Relation linéaire, sans valeur aberrante', 'Linear relationship, no outliers'),
          CheckStatus.notAssessed, tr('À vérifier sur le nuage de points.', 'To be checked on the scatter plot.')),
      Check('independence', tr('Paires indépendantes', 'Independent pairs'), CheckStatus.notAssessed,
          tr('Une seule paire par sujet.', 'A single pair per subject.')),
    ],
    alerts: [
      if (c.dropped > 0) Alert('missing_pairs', Severity.caution, tr('${c.dropped} ligne(s) incomplète(s) exclue(s).', '${c.dropped} incomplete row(s) excluded.')),
    ],
    figures: {'scatter': {'x': c.x, 'y': c.y}},
    interpretation: Interpretation(
      whyThisMethod: spearman
          ? tr('Deux variables ordinales ou quantitatives liées de façon monotone non linéaire, ou avec valeurs extrêmes.', 'Two ordinal or quantitative variables with a monotonic non-linear relationship, or with extreme values.')
          : tr('Deux variables quantitatives liées linéairement.', 'Two linearly related quantitative variables.'),
      whatItMeans: '$name = ${fmtCi(e)}, ${fmtP(p)} (n = $n).',
      notJustified: tr("Conclure à l'accord entre deux méthodes de mesure à partir d'une corrélation élevée (utiliser Bland-Altman) ; conclure à une causalité ; extrapoler hors de la plage observée.",
          'Concluding agreement between two measurement methods from a high correlation (use Bland-Altman); concluding causality; extrapolating beyond the observed range.'),
    ),
  );
}

double _tanh(double z) {
  final e2 = math.exp(2 * z);
  return (e2 - 1) / (e2 + 1);
}

/// Accord entre deux méthodes de mesure : biais et limites d'accord, avec
/// les IC du biais et des limites (Bland & Altman 1999, ES(LdA) ≈ √(3s²/n)).
AnalysisResult blandAltman(List<double?> m1, List<double?> m2,
    {double level = 0.95, String? name1, String? name2, String unit = '', double? acceptableLimit}) {
  name1 ??= tr('Méthode A', 'Method A');
  name2 ??= tr('Méthode B', 'Method B');
  final c = _complete(m1, m2);
  final n = c.x.length;
  if (n < 3) throw StatInputError('n_too_small', tr('Au moins 3 paires complètes sont requises.', 'At least 3 complete pairs are required.'));
  final d = [for (var i = 0; i < n; i++) c.x[i] - c.y[i]];
  final avg = [for (var i = 0; i < n; i++) (c.x[i] + c.y[i]) / 2];
  final bias = mean(d), s = sd(d);
  final z = normalQuantile(0.975); // limites d'accord à 95 % des différences
  final loa1 = bias - z * s, loa2 = bias + z * s;
  final tq = tQuantile(1 - (1 - level) / 2, n - 1.0);
  final seBias = s / math.sqrt(n);
  final seLoa = math.sqrt(3 * s * s / n);
  // Tendance proportionnelle : pente de la différence sur la moyenne.
  final rTrend = pearsonR(avg, d);
  final tTrend = rTrend * math.sqrt((n - 2) / (1 - rTrend * rTrend));
  final pTrend = tTwoSidedP(tTrend, n - 2.0);
  final u = unit.isEmpty ? '' : ' $unit';
  final biasE = Estimate(tr('Biais moyen ($name1 − $name2)', 'Mean bias ($name1 − $name2)'), bias,
      lower: bias - tq * seBias, upper: bias + tq * seBias, level: level);
  final lowE = Estimate(tr("Limite d'accord inférieure", 'Lower limit of agreement'), loa1,
      lower: loa1 - tq * seLoa, upper: loa1 + tq * seLoa, level: level);
  final highE = Estimate(tr("Limite d'accord supérieure", 'Upper limit of agreement'), loa2,
      lower: loa2 - tq * seLoa, upper: loa2 + tq * seLoa, level: level);
  final alerts = <Alert>[];
  if (pTrend < 0.05) {
    alerts.add(Alert('proportional_bias', Severity.caution,
        tr("La différence varie avec le niveau mesuré (r = ${fmt(rTrend)}, ${fmtP(pTrend)}) : des limites d'accord constantes sont trompeuses.",
            'The difference varies with the measured level (r = ${fmt(rTrend)}, ${fmtP(pTrend)}): constant limits of agreement are misleading.'),
        suggestion: tr('Envisager une analyse sur le rapport ou le log, ou des limites dépendant du niveau.', 'Consider an analysis on the ratio or log scale, or level-dependent limits.')));
  }
  String acceptability = '';
  if (acceptableLimit != null) {
    final ok = highE.upper! <= acceptableLimit && lowE.lower! >= -acceptableLimit;
    acceptability = ok
        ? tr(" Les IC des limites d'accord restent dans ±${fmt(acceptableLimit)}$u : accord jugé acceptable selon le critère fixé a priori.",
            ' The CIs of the limits of agreement stay within ±${fmt(acceptableLimit)}$u: agreement judged acceptable by the a priori criterion.')
        : tr(" Les IC des limites d'accord dépassent ±${fmt(acceptableLimit)}$u : l'accord acceptable n'est pas démontré.",
            ' The CIs of the limits of agreement exceed ±${fmt(acceptableLimit)}$u: acceptable agreement is not demonstrated.');
  }
  return AnalysisResult(
    methodId: 'bland_altman',
    methodName: tr('Accord entre deux méthodes (Bland-Altman)', 'Agreement between two methods (Bland-Altman)'),
    inputs: {'n': n, 'dropped': c.dropped, 'level': level, 'acceptableLimit': ?acceptableLimit},
    formula: tr("d = A − B ; biais = d̄ ; limites d'accord à 95 % = d̄ ± 1,96 s_d ; IC du biais = d̄ ± t·s_d/√n ; IC de chaque limite = LdA ± t·√(3s_d²/n).",
        'd = A − B; bias = d̄; 95% limits of agreement = d̄ ± 1.96 s_d; CI of bias = d̄ ± t·s_d/√n; CI of each limit = LoA ± t·√(3s_d²/n).'),
    estimates: [biasE, lowE, highE, Estimate(tr('ÉT des différences', 'SD of differences'), s)],
    statistics: {'r_trend': rTrend, 'p_trend': pTrend},
    checks: [
      Check('no_trend', tr('Différences indépendantes du niveau mesuré', 'Differences independent of the measured level'),
          pTrend < 0.05 ? CheckStatus.violated : CheckStatus.ok, tr('r(moyenne, différence) = ${fmt(rTrend)}, ${fmtP(pTrend)}.', 'r(mean, difference) = ${fmt(rTrend)}, ${fmtP(pTrend)}.')),
      Check('a_priori_limit', tr('Limite acceptable fixée a priori (critère clinique)', 'Acceptable limit set a priori (clinical criterion)'),
          CheckStatus.notAssessed, tr("Sans critère clinique, l'accord ne peut pas être jugé acceptable.", 'Without a clinical criterion, agreement cannot be judged acceptable.')),
    ],
    alerts: alerts,
    figures: {'blandAltman': {'mean': avg, 'diff': d, 'bias': bias, 'loaLow': loa1, 'loaHigh': loa2}},
    interpretation: Interpretation(
      whyThisMethod: tr('Deux méthodes mesurant la même grandeur sur les mêmes sujets : on étudie leurs différences, non leur corrélation.',
          'Two methods measuring the same quantity on the same subjects: we study their differences, not their correlation.'),
      whatItMeans: tr(
          "Biais = ${fmtCi(biasE)}$u. 95 % des différences entre méthodes sont attendues entre ${fmt(loa1)} et ${fmt(loa2)}$u (limites d'accord). Ces limites sont elles-mêmes estimées avec incertitude : IC de la limite inférieure ${fmt(lowE.lower)} à ${fmt(lowE.upper)}, de la limite supérieure ${fmt(highE.lower)} à ${fmt(highE.upper)}.$acceptability",
          'Bias = ${fmtCi(biasE)}$u. 95% of differences between methods are expected between ${fmt(loa1)} and ${fmt(loa2)}$u (limits of agreement). These limits are themselves estimated with uncertainty: CI of the lower limit ${fmt(lowE.lower)} to ${fmt(lowE.upper)}, of the upper limit ${fmt(highE.lower)} to ${fmt(highE.upper)}.$acceptability'),
      notJustified: tr(
          "Confondre les limites d'accord (dispersion des différences individuelles) avec l'IC du biais (précision de la moyenne des différences) ; conclure à l'interchangeabilité sans critère clinique fixé a priori.",
          'Confusing the limits of agreement (spread of individual differences) with the CI of the bias (precision of the mean difference); concluding interchangeability without a clinical criterion set a priori.'),
    ),
  );
}
