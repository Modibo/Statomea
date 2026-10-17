/// Régression de comptages : Poisson (offset de temps d'exposition facultatif), quasi-Poisson et binomiale négative
/// (NB2 : Var = μ + μ²/θ, θ au maximum de vraisemblance comme MASS::glm.nb). Validé contre
/// validation/r/45_comptages.R (stats::glm, MASS 7.3).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../math/special.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

enum CountModel { poisson, quasiPoisson, negativeBinomial }

class CountFit {
  final List<double> beta, se, mu;
  final double deviance, pearson, logLik;
  final double? theta, seTheta;
  final bool converged;
  const CountFit(this.beta, this.se, this.mu, this.deviance, this.pearson, this.logLik, this.theta, this.seTheta, this.converged);
}

/// IRLS (lien log) pour Poisson (θ = null) ou binomiale négative à θ fixé. Renvoie β, (XᵀWX)⁻¹ et μ.
({List<double> beta, Matrix inv, List<double> mu, bool ok}) _irls(List<List<double>> x, List<double> y, List<double> offset, double? theta, List<double>? start) {
  final n = y.length, p = x.first.length;
  var beta = start ?? List<double>.filled(p, 0);
  if (start == null) {
    final ybar = y.reduce((a, b) => a + b) / n;
    final obar = offset.reduce((a, b) => a + b) / n;
    beta[0] = math.log(math.max(ybar, 1e-8)) - obar;
  }
  Matrix? inv;
  var mu = List<double>.filled(n, 0);
  var ok = false;
  for (var it = 0; it < 100; it++) {
    final xtwx = Matrix(p, p);
    final xtwz = List<double>.filled(p, 0);
    for (var i = 0; i < n; i++) {
      var eta = offset[i];
      for (var j = 0; j < p; j++) {
        eta += x[i][j] * beta[j];
      }
      final m = math.exp(eta);
      mu[i] = m;
      final w = theta == null ? m : m / (1 + m / theta);
      final z = eta - offset[i] + (y[i] - m) / m;
      for (var j = 0; j < p; j++) {
        xtwz[j] += x[i][j] * w * z;
        for (var l = 0; l < p; l++) {
          xtwx.data[j * p + l] += x[i][j] * w * x[i][l];
        }
      }
    }
    final next = solveSpd(xtwx, xtwz);
    if (next == null) break;
    final change = [for (var j = 0; j < p; j++) (next[j] - beta[j]).abs()].reduce(math.max);
    beta = next;
    if (change < 1e-12) {
      ok = true;
      break;
    }
  }
  // μ et (XᵀWX)⁻¹ aux β finaux.
  final xtwx = Matrix(p, p);
  for (var i = 0; i < n; i++) {
    var eta = offset[i];
    for (var j = 0; j < p; j++) {
      eta += x[i][j] * beta[j];
    }
    mu[i] = math.exp(eta);
    final w = theta == null ? mu[i] : mu[i] / (1 + mu[i] / theta);
    for (var j = 0; j < p; j++) {
      for (var l = 0; l < p; l++) {
        xtwx.data[j * p + l] += x[i][j] * w * x[i][l];
      }
    }
  }
  inv = invertSpd(xtwx) ?? Matrix(p, p);
  return (beta: beta, inv: inv, mu: mu, ok: ok);
}

double _poisLogLik(List<double> y, List<double> mu) {
  var s = 0.0;
  for (var i = 0; i < y.length; i++) {
    s += (y[i] > 0 ? y[i] * math.log(mu[i]) : 0) - mu[i] - lnGamma(y[i] + 1);
  }
  return s;
}

double _nbLogLik(List<double> y, List<double> mu, double th) {
  var s = 0.0;
  for (var i = 0; i < y.length; i++) {
    s += lnGamma(y[i] + th) - lnGamma(th) - lnGamma(y[i] + 1) + th * math.log(th / (th + mu[i])) + (y[i] > 0 ? y[i] * math.log(mu[i] / (th + mu[i])) : 0);
  }
  return s;
}

double _poisDev(List<double> y, List<double> mu) {
  var d = 0.0;
  for (var i = 0; i < y.length; i++) {
    d += 2 * ((y[i] > 0 ? y[i] * math.log(y[i] / mu[i]) : 0) - (y[i] - mu[i]));
  }
  return d;
}

double _nbDev(List<double> y, List<double> mu, double th) {
  var d = 0.0;
  for (var i = 0; i < y.length; i++) {
    d += 2 * ((y[i] > 0 ? y[i] * math.log(y[i] / mu[i]) : 0) - (y[i] + th) * math.log((y[i] + th) / (mu[i] + th)));
  }
  return d;
}

/// Score et information de θ (MASS::theta.ml).
({double score, double info}) _thetaScore(List<double> y, List<double> mu, double th) {
  var s = 0.0, inf = 0.0;
  for (var i = 0; i < y.length; i++) {
    s += digamma(th + y[i]) - digamma(th) + math.log(th) + 1 - math.log(th + mu[i]) - (y[i] + th) / (mu[i] + th);
    inf += -trigamma(th + y[i]) + trigamma(th) - 1 / th + 2 / (mu[i] + th) - (y[i] + th) / ((mu[i] + th) * (mu[i] + th));
  }
  return (score: s, info: inf);
}

/// θ au-delà duquel la binomiale négative est indiscernable de Poisson (pas de surdispersion).
const negBinThetaMax = 1e7;

/// Ajustement d'un modèle de comptage ; [offset] = log du temps d'exposition (0 sinon).
CountFit fitCounts(List<List<double>> x, List<double> y, {List<double>? offset, CountModel model = CountModel.poisson}) {
  final n = y.length, p = x.first.length;
  final off = offset ?? List<double>.filled(n, 0);
  final pois = _irls(x, y, off, null, null);
  var pearson = 0.0;
  for (var i = 0; i < n; i++) {
    pearson += (y[i] - pois.mu[i]) * (y[i] - pois.mu[i]) / pois.mu[i];
  }
  if (model != CountModel.negativeBinomial) {
    final scale = model == CountModel.quasiPoisson ? pearson / (n - p) : 1.0;
    return CountFit(pois.beta, [for (var j = 0; j < p; j++) math.sqrt(pois.inv.get(j, j) * scale)], pois.mu, _poisDev(y, pois.mu), pearson, _poisLogLik(y, pois.mu), null, null, pois.ok);
  }
  // Binomiale négative : départ θ par les moments (theta.ml), puis alternance jusqu'au maximum de vraisemblance.
  var mu = pois.mu, beta = pois.beta;
  var th = n / [for (var i = 0; i < n; i++) (y[i] / mu[i] - 1) * (y[i] / mu[i] - 1)].reduce((a, b) => a + b);
  var ll = _nbLogLik(y, mu, th);
  var ok = false;
  var fit = pois;
  for (var outer = 0; outer < 200; outer++) {
    for (var k = 0; k < 100 && th < negBinThetaMax; k++) {
      final sc = _thetaScore(y, mu, th);
      final del = sc.score / sc.info;
      th = (th + del).abs();
      if (del.abs() < 1e-13 * (1 + th)) break;
    }
    th = math.min(th, negBinThetaMax);
    fit = _irls(x, y, off, th, beta);
    beta = fit.beta;
    mu = fit.mu;
    final l2 = _nbLogLik(y, mu, th);
    if ((l2 - ll).abs() < 1e-13 * (1 + l2.abs())) {
      ok = true;
      ll = l2;
      break;
    }
    ll = l2;
  }
  final info = _thetaScore(y, mu, th).info;
  pearson = 0;
  for (var i = 0; i < n; i++) {
    pearson += (y[i] - mu[i]) * (y[i] - mu[i]) / (mu[i] + mu[i] * mu[i] / th);
  }
  return CountFit(beta, [for (var j = 0; j < p; j++) math.sqrt(fit.inv.get(j, j))], mu, _nbDev(y, mu, th), pearson, ll, th, info > 0 ? math.sqrt(1 / info) : null, ok);
}

/// Analyse d'un comptage : [exposure] = colonne du temps d'exposition (personnes-temps), utilisé en offset log.
AnalysisResult countRegression(Dataset ds, ModelFormula f, {CountModel model = CountModel.negativeBinomial, String? exposure, double level = 0.95}) {
  final d = buildDesign(ds, f);
  final expo = exposure == null ? null : ds.numeric(exposure);
  final keep = [for (var k = 0; k < d.n; k++) if (expo == null || (expo[d.rows[k]] != null && expo[d.rows[k]]! > 0)) k];
  final y = [for (final k in keep) d.y[k]];
  if (y.any((v) => v < 0 || v != v.roundToDouble())) {
    throw StatInputError('not_counts', tr('L\'issue doit être un comptage (entier ≥ 0).', 'The outcome must be a count (integer ≥ 0).'));
  }
  if (y.every((v) => v == 0)) throw StatInputError('all_zero', tr('Aucun événement : tous les comptages sont nuls.', 'No event: all counts are zero.'));
  final x = [for (final k in keep) d.x[k]];
  final off = expo == null ? null : [for (final k in keep) math.log(expo[d.rows[k]]!)];
  final n = y.length, p = x.first.length;
  final pois = fitCounts(x, y, offset: off);
  final fit = model == CountModel.poisson ? pois : fitCounts(x, y, offset: off, model: model);
  final dispersion = pois.pearson / (n - p);
  final z = normalQuantile(1 - (1 - level) / 2);
  final useT = model == CountModel.quasiPoisson;
  final crit = useT ? tQuantile(1 - (1 - level) / 2, (n - p).toDouble()) : z;
  final coefs = [
    for (var j = 0; j < p; j++)
      () {
        final b = fit.beta[j], se = fit.se[j], st = b / se;
        final pv = useT ? 2 * (1 - tCdf(st.abs(), (n - p).toDouble())) : normalTwoSidedP(st);
        return Coefficient(d.columns[j], b, se, st, pv, b - crit * se, b + crit * se);
      }()
  ];
  final nbFit = model == CountModel.negativeBinomial ? fit : null;
  final noOverdispersion = nbFit != null && nbFit.theta! >= negBinThetaMax * 0.999;
  final lrt = nbFit == null ? null : math.max(0.0, 2 * (nbFit.logLik - pois.logLik));
  final lrtP = lrt == null ? null : chiSquareUpper(lrt, 1) / 2;
  final pct = (level * 100).round();
  final modelName = switch (model) {
    CountModel.poisson => tr('Poisson', 'Poisson'),
    CountModel.quasiPoisson => tr('quasi-Poisson', 'quasi-Poisson'),
    CountModel.negativeBinomial => tr('binomiale négative', 'negative binomial'),
  };
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  String irr(Coefficient c) => '${fmt(math.exp(c.estimate))} (${fmt(math.exp(c.lower))} – ${fmt(math.exp(c.upper))})';
  return AnalysisResult(
    methodId: 'count_regression',
    methodName: tr('Régression de comptages : $modelName${exposure == null ? '' : ' (taux par unité de « $exposure »)'}', 'Count regression: $modelName${exposure == null ? '' : ' (rate per unit of "$exposure")'}'),
    inputs: {'model': d.describe(), 'family': model.name, 'exposure': exposure, 'level': level},
    formula: tr(
        'log E[y] = ${exposure == null ? '' : 'log($exposure) + '}xᵀβ ; IRR = exp(β) (rapport de taux d\'incidence). Poisson : IRLS, ES = (XᵀWX)⁻¹ ; dispersion φ = χ²_Pearson/(n − p). Quasi-Poisson : ES × √φ, tests t. Binomiale négative : Var = μ + μ²/θ, θ au maximum de vraisemblance (score de MASS::theta.ml), ES des β à θ fixé ; rapport de vraisemblance contre Poisson (frontière : p/2).',
        'log E[y] = ${exposure == null ? '' : 'log($exposure) + '}xᵀβ; IRR = exp(β) (incidence rate ratio). Poisson: IRLS, SE = (XᵀWX)⁻¹; dispersion φ = Pearson χ²/(n − p). Quasi-Poisson: SE × √φ, t tests. Negative binomial: Var = μ + μ²/θ, θ by maximum likelihood (MASS::theta.ml score), SEs of β at fixed θ; likelihood ratio against Poisson (boundary: p/2).'),
    estimates: [
      for (final c in coefs.skip(1)) Estimate('IRR — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), pValue: c.p, se: c.se, level: level),
      if (nbFit != null && !noOverdispersion) Estimate('θ', nbFit.theta!, se: nbFit.seTheta),
    ],
    statistics: {
      'n': n.toDouble(), 'deviance': fit.deviance, 'pearson': fit.pearson, 'loglik': fit.logLik, 'dispersion_poisson': dispersion,
      'theta': ?nbFit?.theta, 'se_theta': ?nbFit?.seTheta, 'lrt_nb': ?lrt, 'lrt_nb_p': ?lrtP,
      for (var j = 0; j < p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d.columns[j]}': fit.se[j],
    },
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), fit.converged ? CheckStatus.ok : CheckStatus.violated, ''),
      Check('overdispersion', tr('Surdispersion (variance > moyenne)', 'Overdispersion (variance > mean)'),
          model == CountModel.poisson && dispersion > 1.5 ? CheckStatus.violated : CheckStatus.ok,
          tr('Dispersion de Poisson φ = ${fmt(dispersion, digits: 3)}${dispersion > 1.5 ? (model == CountModel.poisson ? ' : surdispersion, les ES de Poisson sont trop petits ; utiliser la binomiale négative ou la quasi-Poisson.' : ' : surdispersion prise en compte par le modèle choisi.') : ' : pas de surdispersion notable.'}${lrt == null ? '' : ' Binomiale négative contre Poisson : RV = ${fmt(lrt)}, ${fmtP(lrtP!)}.'}',
              'Poisson dispersion φ = ${fmt(dispersion, digits: 3)}${dispersion > 1.5 ? (model == CountModel.poisson ? ': overdispersion, Poisson SEs are too small; use the negative binomial or quasi-Poisson.' : ': overdispersion accounted for by the chosen model.') : ': no notable overdispersion.'}${lrt == null ? '' : ' Negative binomial versus Poisson: LR = ${fmt(lrt)}, ${fmtP(lrtP!)}.'}')),
      if (exposure == null)
        Check('exposure', tr('Temps d\'exposition comparable entre sujets', 'Comparable exposure time between subjects'), CheckStatus.notAssessed,
            tr('Sans offset, les comptages doivent porter sur des durées (ou populations) égales ; sinon indiquer la colonne du temps d\'exposition.', 'Without an offset, counts must refer to equal durations (or populations); otherwise give the exposure time column.')),
    ],
    alerts: [
      ...d.alerts,
      if (noOverdispersion)
        Alert('theta_infinite', Severity.info,
            tr('θ tend vers l\'infini : aucune surdispersion, la binomiale négative se ramène à Poisson (utiliser Poisson).', 'θ tends to infinity: no overdispersion, the negative binomial reduces to Poisson (use Poisson).')),
      if (model == CountModel.poisson && dispersion > 1.5)
        Alert('overdispersion', Severity.serious,
            tr('Surdispersion (φ = ${fmt(dispersion, digits: 3)}) : les IC et p de Poisson sont trop optimistes.', 'Overdispersion (φ = ${fmt(dispersion, digits: 3)}): Poisson CIs and p-values are too optimistic.'),
            suggestion: tr('Choisir la binomiale négative.', 'Choose the negative binomial.')),
    ],
    tables: [
      ResultTable(tr('Coefficients', 'Coefficients'), [tr('Terme', 'Term'), 'β', 'ES', useT ? 't' : 'z', 'p', 'IRR (IC $pct %)'], [
        for (final c in coefs) [c.name, fmt(c.estimate), fmt(c.se), fmt(c.statistic), fmtP(c.p), irr(c)]
      ]),
      ResultTable(tr('Ajustement', 'Fit'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('Modèle', 'Model'), '${d.formula}${exposure == null ? '' : ' + offset(log($exposure))'}'],
        [tr('Observations', 'Observations'), '$n'],
        [tr('Déviance', 'Deviance'), fmt(fit.deviance, digits: 5)],
        [tr('Log-vraisemblance', 'Log-likelihood'), fmt(fit.logLik, digits: 6)],
        [tr('Dispersion de Poisson (χ²/ddl)', 'Poisson dispersion (χ²/df)'), fmt(dispersion, digits: 4)],
        if (nbFit != null) ['θ (ES)', noOverdispersion ? '∞' : '${fmt(nbFit.theta, digits: 4)} (${fmt(nbFit.seTheta, digits: 3)})'],
        for (final c in d.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Issue de comptage (nombre d\'événements) : la régression log-linéaire estime des rapports de taux (IRR). La binomiale négative tolère une variance supérieure à la moyenne (surdispersion), fréquente en pratique ; un offset log(temps) transforme les comptages en taux.',
          'Count outcome (number of events): log-linear regression estimates rate ratios (IRR). The negative binomial allows a variance greater than the mean (overdispersion), common in practice; a log(time) offset turns counts into rates.'),
      whatItMeans: tr('« ${main.name} » : IRR = ${irr(main)}, ${fmtP(main.p)} — le taux est multiplié par ${fmt(math.exp(main.estimate))}, à autres variables fixées.',
          '"${main.name}": IRR = ${irr(main)}, ${fmtP(main.p)} — the rate is multiplied by ${fmt(math.exp(main.estimate))}, holding other variables fixed.'),
      notJustified: tr('Garder Poisson malgré une surdispersion ; oublier l\'offset quand les durées d\'observation diffèrent ; analyser un comptage comme une variable normale.',
          'Keeping Poisson despite overdispersion; forgetting the offset when observation times differ; analysing a count as a normal variable.'),
    ),
  );
}
