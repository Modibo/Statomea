/// Modèle linéaire mixte généralisé à intercept aléatoire (logistique ou Poisson), comme lme4::glmer :
///  yᵢⱼ | bᵢ ~ Bernoulli(logit⁻¹(ηᵢⱼ + bᵢ)) ou Poisson(exp(ηᵢⱼ + bᵢ)), bᵢ ~ N(0, σ²) ;
///  vraisemblance marginale de chaque sujet par l'approximation de Laplace (nAGQ = 1) ou la quadrature de Gauss-Hermite
///  adaptative (nAGQ = k) au mode conditionnel b̂ᵢ ; maximum sur (σ, β) ; ES des β par la hessienne (différences finies)
///  de la log-vraisemblance approchée en (σ, β), comme vcov de lme4 (use.hessian = TRUE).
/// Validé contre validation/r/47_glmm.R (lme4 1.1).
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

enum GlmmFamily { binomial, poisson }


/// Nœuds et poids de Gauss-Hermite (poids e^{−x²}) par la méthode de Golub-Welsch.
({List<double> nodes, List<double> weights}) gaussHermite(int n) {
  final j = [for (var i = 0; i < n; i++) [for (var k = 0; k < n; k++) (k - i).abs() == 1 ? math.sqrt(math.max(i, k) / 2) : 0.0]];
  final e = symmetricEigen(j);
  final idx = List<int>.generate(n, (i) => i)..sort((a, b) => e.values[a].compareTo(e.values[b]));
  return (nodes: [for (final i in idx) e.values[i]], weights: [for (final i in idx) math.sqrt(math.pi) * e.vectors[0][i] * e.vectors[0][i]]);
}

class GlmmLongFit {
  final List<double> beta, se;
  final double sigma, logLik;
  final int nAgq;
  final bool singular, converged;
  /// Log-vraisemblance du modèle sans effet aléatoire (σ = 0, GLM), pour le test de σ.
  final double logLikGlm;
  const GlmmLongFit(this.beta, this.se, this.sigma, this.logLik, this.nAgq, this.singular, this.converged, this.logLikGlm);
}

class _GlmmData {
  final List<List<double>> x;
  final List<double> y;
  final List<List<int>> rowsOf;
  final GlmmFamily family;
  final int p;
  late final double logFactorial = family == GlmmFamily.poisson ? y.fold(0.0, (s, v) => s + lnGamma(v + 1)) : 0;
  _GlmmData(this.x, this.y, List<int> group, this.family)
      : p = x.first.length,
        rowsOf = List.generate(group.reduce(math.max) + 1, (_) => <int>[]) {
    for (var i = 0; i < y.length; i++) {
      rowsOf[group[i]].add(i);
    }
  }
}

double _ll(GlmmFamily f, double y, double eta) => switch (f) {
      // log p(y | η), sans la constante log(y!) de Poisson (ajoutée globalement).
      GlmmFamily.binomial => y * eta - (eta > 0 ? eta + math.log(1 + math.exp(-eta)) : math.log(1 + math.exp(eta))),
      GlmmFamily.poisson => y * eta - math.exp(eta),
    };
double _mu(GlmmFamily f, double eta) => f == GlmmFamily.binomial ? 1 / (1 + math.exp(-eta)) : math.exp(eta);
double _w(GlmmFamily f, double mu) => f == GlmmFamily.binomial ? mu * (1 - mu) : mu;

/// Log-vraisemblance marginale approchée en (σ, β).
double _logLik(_GlmmData d, List<double> beta, double sigma, ({List<double> nodes, List<double> weights})? gh) {
  final eta0 = [
    for (final r in d.x)
      () {
        var s = 0.0;
        for (var j = 0; j < d.p; j++) {
          s += r[j] * beta[j];
        }
        return s;
      }()
  ];
  var total = -d.logFactorial;
  final s = sigma.abs();
  for (final rows in d.rowsOf) {
    if (s < 1e-10) {
      for (final i in rows) {
        total += _ll(d.family, d.y[i], eta0[i]);
      }
      continue;
    }
    double g(double bb) {
      var v = -bb * bb / (2 * s * s);
      for (final i in rows) {
        v += _ll(d.family, d.y[i], eta0[i] + bb);
      }
      return v;
    }

    // Mode conditionnel b̂ de g(b) = Σ log p(y | η + b) − b²/(2σ²) : Newton amorti sur la DÉRIVÉE (g est concave ; près du
    // mode, comparer des valeurs de g bute sur l'arrondi, d'où un critère sur |g′|).
    ({double d1, double d2}) der(double bb) {
      var d1 = -bb / (s * s), d2 = -1 / (s * s);
      for (final i in rows) {
        final m = _mu(d.family, eta0[i] + bb);
        d1 += d.y[i] - m;
        d2 -= _w(d.family, m);
      }
      return (d1: d1, d2: d2);
    }

    var b = 0.0;
    var cur = der(b);
    for (var it = 0; it < 200 && cur.d1 != 0; it++) {
      var step = -cur.d1 / cur.d2;
      var bn = b + step, nx = der(bn);
      for (var k = 0; k < 60 && nx.d1.abs() >= cur.d1.abs(); k++) {
        step /= 2;
        bn = b + step;
        nx = der(bn);
      }
      if (nx.d1.abs() >= cur.d1.abs()) break; // plus de progrès possible (précision machine)
      b = bn;
      cur = nx;
      if (step.abs() < 1e-14 * (1 + b.abs())) break;
    }
    var h2 = cur.d2;
    // Courbure au mode : cur.d2 (évaluée en b̂).
    final scale = 1 / math.sqrt(-h2);
    final logNorm = -math.log(s) - 0.5 * math.log(2 * math.pi); // log de la densité N(0, σ²) hors exposant
    if (gh == null) {
      total += g(b) + logNorm + 0.5 * math.log(2 * math.pi) + math.log(scale);
    } else {
      // ∫ e^{g} ≈ √2·s·Σ wₖ e^{zₖ²} e^{g(b̂ + √2 s zₖ)}.
      final gb = g(b);
      var acc = 0.0;
      for (var k = 0; k < gh.nodes.length; k++) {
        final z = gh.nodes[k];
        acc += gh.weights[k] * math.exp(z * z + g(b + math.sqrt2 * scale * z) - gb);
      }
      total += gb + math.log(acc * math.sqrt2 * scale) + logNorm;
    }
  }
  return total;
}

/// Gradient et hessienne de f par différences finies centrées, pas absolu [step] (1e-4, comme deriv12 de lme4 : un pas
/// plus petit amplifie l'erreur d'arrondi de f dans la dérivée seconde).
({List<double> g, Matrix h}) _derivs(double Function(List<double>) f, List<double> x, {double step = 1e-4}) {
  final n = x.length;
  final hs = [for (var i = 0; i < n; i++) step];
  List<double> sh(List<(int, double)> d) {
    final y = [...x];
    for (final (i, v) in d) {
      y[i] += v;
    }
    return y;
  }

  final f0 = f(x);
  final g = [for (var i = 0; i < n; i++) (f(sh([(i, hs[i])])) - f(sh([(i, -hs[i])]))) / (2 * hs[i])];
  final h = Matrix(n, n);
  for (var i = 0; i < n; i++) {
    h.set(i, i, (f(sh([(i, hs[i])])) - 2 * f0 + f(sh([(i, -hs[i])]))) / (hs[i] * hs[i]));
    for (var j = 0; j < i; j++) {
      final v = (f(sh([(i, hs[i]), (j, hs[j])])) - f(sh([(i, hs[i]), (j, -hs[j])])) - f(sh([(i, -hs[i]), (j, hs[j])])) + f(sh([(i, -hs[i]), (j, -hs[j])]))) / (4 * hs[i] * hs[j]);
      h.set(i, j, v);
      h.set(j, i, v);
    }
  }
  return (g: g, h: h);
}

/// Log-vraisemblance marginale approchée en (σ, β) (contrôle et tests).
double glmmLongLogLik(List<List<double>> x, List<double> y, List<int> group, List<double> beta, double sigma, {GlmmFamily family = GlmmFamily.binomial, int nAgq = 1}) =>
    _logLik(_GlmmData(x, y, group, family), beta, sigma, nAgq > 1 ? gaussHermite(nAgq) : null);

/// Ajustement ; [nAgq] = 1 : Laplace, > 1 : quadrature adaptative à nAgq points. [x] commence par la constante ; les
/// autres colonnes sont centrées pour l'optimisation (conditionnement), puis β et sa covariance ramenés à l'échelle
/// d'origine.
GlmmLongFit fitGlmmLong(List<List<double>> x, List<double> y, List<int> group, {GlmmFamily family = GlmmFamily.binomial, int nAgq = 1}) {
  final p = x.first.length;
  final m = [for (var j = 0; j < p; j++) j == 0 ? 0.0 : x.fold(0.0, (s, r) => s + r[j]) / x.length];
  final xc = [for (final r in x) [for (var j = 0; j < p; j++) r[j] - m[j]]];
  final c = _fitCore(xc, y, group, family, nAgq);
  final beta = [...c.beta];
  for (var j = 1; j < p; j++) {
    beta[0] -= c.beta[j] * m[j];
  }
  // Var(β₀) = aᵀVa, a = (1, −m₁, …) ; covariances des autres coefficients inchangées.
  final se = [
    for (var j = 0; j < p; j++)
      () {
        if (j > 0) return math.sqrt(c.cov.get(j, j));
        var v = 0.0;
        for (var a = 0; a < p; a++) {
          for (var b = 0; b < p; b++) {
            v += (a == 0 ? 1 : -m[a]) * (b == 0 ? 1 : -m[b]) * c.cov.get(a, b);
          }
        }
        return math.sqrt(v);
      }()
  ];
  return GlmmLongFit(beta, se, c.sigma, c.logLik, nAgq, c.singular || c.logLik - c.logLikGlm < 1e-3, c.converged, c.logLikGlm);
}

({List<double> beta, Matrix cov, double sigma, double logLik, double logLikGlm, bool singular, bool converged}) _fitCore(
    List<List<double>> x, List<double> y, List<int> group, GlmmFamily family, int nAgq) {
  final d = _GlmmData(x, y, group, family);
  final gh = nAgq > 1 ? gaussHermite(nAgq) : null;
  // Paramètres : (σ, β). Départ : β du GLM (σ → 0), σ = 1.
  double negLl(List<double> t) => -_logLik(d, t.sublist(1), t[0], gh);
  var beta = List<double>.filled(d.p, 0);
  final ybar = y.reduce((a, b) => a + b) / y.length;
  beta[0] = family == GlmmFamily.binomial ? math.log(ybar / (1 - ybar)) : math.log(ybar);
  for (var it = 0; it < 50; it++) {
    final xtwx = Matrix(d.p, d.p);
    final u = List<double>.filled(d.p, 0);
    for (var i = 0; i < y.length; i++) {
      var e = 0.0;
      for (var j = 0; j < d.p; j++) {
        e += x[i][j] * beta[j];
      }
      final m = _mu(family, e), w = _w(family, m);
      for (var j = 0; j < d.p; j++) {
        u[j] += x[i][j] * (y[i] - m);
        for (var l = 0; l < d.p; l++) {
          xtwx.data[j * d.p + l] += x[i][j] * w * x[i][l];
        }
      }
    }
    final st = solveSpd(xtwx, u);
    if (st == null) break;
    beta = [for (var j = 0; j < d.p; j++) beta[j] + st[j]];
    if (st.every((v) => v.abs() < 1e-12)) break;
  }
  // Profil en σ : à σ fixé, β par Newton (dérivées par différences finies, problème proche d'une régression logistique,
  // bien conditionné) ; σ par section dorée sur log σ ; puis polissage conjoint.
  ({List<double> beta, double f}) inner(double sigma, List<double> start) {
    double fb(List<double> bb) => -_logLik(d, bb, sigma, gh);
    var bb = [...start];
    var f0 = fb(bb);
    for (var it = 0; it < 50; it++) {
      final dv = _derivs(fb, bb);
      final step = solveSpd(dv.h, [for (final g in dv.g) -g]);
      if (step == null) break;
      var scale = 1.0;
      var bn = bb, fn = f0;
      for (var k = 0; k < 40; k++) {
        bn = [for (var j = 0; j < d.p; j++) bb[j] + scale * step[j]];
        fn = fb(bn);
        if (fn <= f0 + 1e-12) break;
        scale /= 2;
      }
      if (fn > f0 + 1e-12) break;
      final done = (f0 - fn).abs() < 1e-12 && step.every((v) => (scale * v).abs() < 1e-9);
      bb = bn;
      f0 = fn;
      if (done) break;
    }
    return (beta: bb, f: f0);
  }

  var best = inner(1e-12, beta); // σ = 0 : GLM
  final atZero = best;
  var warm = beta;
  ({List<double> beta, double f}) prof(double ls) {
    final r = inner(math.exp(ls), warm);
    warm = r.beta;
    return r;
  }

  // Encadrement grossier puis section dorée sur log σ ∈ [−7, 3].
  var lo = -7.0, hi = 3.0;
  final grid = [for (var k = 0; k <= 10; k++) lo + (hi - lo) * k / 10];
  final vals = [for (final g in grid) prof(g).f];
  var kMin = 0;
  for (var k = 1; k < vals.length; k++) {
    if (vals[k] < vals[kMin]) kMin = k;
  }
  lo = grid[math.max(0, kMin - 1)];
  hi = grid[math.min(grid.length - 1, kMin + 1)];
  const phi = 0.6180339887498949;
  var a1 = hi - phi * (hi - lo), a2 = lo + phi * (hi - lo);
  var r1 = prof(a1), r2 = prof(a2);
  while (hi - lo > 1e-9) {
    if (r1.f < r2.f) {
      hi = a2;
      a2 = a1;
      r2 = r1;
      a1 = hi - phi * (hi - lo);
      r1 = prof(a1);
    } else {
      lo = a1;
      a1 = a2;
      r1 = r2;
      a2 = lo + phi * (hi - lo);
      r2 = prof(a2);
    }
  }
  final lsHat = (lo + hi) / 2;
  final rHat = inner(math.exp(lsHat), r1.beta);
  var t = [math.exp(lsHat), ...rHat.beta];
  var converged = true;
  // σ à la borne basse de la recherche, ou pas meilleur que σ = 0 : ajustement singulier (GLM).
  if (lsHat < -6.5 || atZero.f <= rHat.f + 1e-9) {
    t = [0.0, ...atZero.beta];
  } else {
    // Polissage conjoint (σ, β) par Newton : la vraisemblance est lisse (mode conditionnel convergé sur |g′|).
    converged = false;
    for (var it = 0; it < 20; it++) {
      final f0 = negLl(t);
      final dv = _derivs(negLl, t);
      final step = solveSpd(dv.h, [for (final g in dv.g) -g]);
      if (step == null) break;
      var scale = 1.0;
      var tn = t;
      var ok = false;
      for (var k = 0; k < 30; k++) {
        tn = [for (var i = 0; i < t.length; i++) t[i] + scale * step[i]];
        if (tn[0] > 0 && negLl(tn) <= f0) {
          ok = true;
          break;
        }
        scale /= 2;
      }
      if (!ok) {
        converged = true;
        break;
      }
      final small = [for (final v in step) (scale * v).abs()].reduce(math.max) < 1e-9;
      t = tn;
      if (small) {
        converged = true;
        break;
      }
    }
  }
  best = rHat;
  final singular = t[0] == 0;
  final dv = _derivs(negLl, t);
  final idx = [if (!singular) 0, for (var j = 1; j <= d.p; j++) j];
  final h = Matrix(idx.length, idx.length);
  for (var a = 0; a < idx.length; a++) {
    for (var b = 0; b < idx.length; b++) {
      h.set(a, b, dv.h.get(idx[a], idx[b]));
    }
  }
  final inv = invertSpd(h);
  final off = singular ? 0 : 1;
  final cov = Matrix(d.p, d.p);
  for (var a = 0; a < d.p; a++) {
    for (var b = 0; b < d.p; b++) {
      cov.set(a, b, inv == null ? double.nan : inv.get(a + off, b + off));
    }
  }
  return (beta: t.sublist(1), cov: cov, sigma: t[0], logLik: -negLl(t), logLikGlm: -atZero.f, singular: singular, converged: converged);
}

/// Analyse d'un jeu de données en format long : [subject] identifie le sujet (ou la grappe).
AnalysisResult glmmLongitudinal(Dataset ds, ModelFormula f, {required String subject, GlmmFamily family = GlmmFamily.binomial, int nAgq = 1, double level = 0.95}) {
  final d0 = buildDesign(ds, f, binaryOutcome: family == GlmmFamily.binomial);
  final subj = ds.text(subject);
  final keep = [for (var k = 0; k < d0.n; k++) if (subj[d0.rows[k]] != null) k];
  final ids = <String, int>{};
  final group = [for (final k in keep) ids.putIfAbsent(subj[d0.rows[k]]!, () => ids.length)];
  if (ids.length < 5) throw StatInputError('few_subjects', tr('Au moins 5 sujets (grappes) sont nécessaires.', 'At least 5 subjects (clusters) are required.'));
  final y = [for (final k in keep) d0.y[k]];
  if (family == GlmmFamily.poisson && y.any((v) => v < 0 || v != v.roundToDouble())) {
    throw StatInputError('not_counts', tr('L\'issue de Poisson doit être un comptage (entier ≥ 0).', 'The Poisson outcome must be a count (integer ≥ 0).'));
  }
  final x = [for (final k in keep) d0.x[k]];
  final fit = fitGlmmLong(x, y, group, family: family, nAgq: nAgq);
  final p = d0.p, m = ids.length;
  final z = normalQuantile(1 - (1 - level) / 2);
  final coefs = [
    for (var j = 0; j < p; j++) Coefficient(d0.columns[j], fit.beta[j], fit.se[j], fit.beta[j] / fit.se[j], normalTwoSidedP(fit.beta[j] / fit.se[j]), fit.beta[j] - z * fit.se[j], fit.beta[j] + z * fit.se[j])
  ];
  final effect = family == GlmmFamily.binomial ? 'OR' : 'RR';
  final pct = (level * 100).round();
  // Test de σ = 0 (frontière) : mélange ½χ²₀ + ½χ²₁.
  final lrt = math.max(0.0, 2 * (fit.logLik - fit.logLikGlm));
  final lrtP = 0.5 * chiSquareUpper(lrt, 1);
  final icc = family == GlmmFamily.binomial ? fit.sigma * fit.sigma / (fit.sigma * fit.sigma + math.pi * math.pi / 3) : null;
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  String eff(Coefficient c) => '${fmt(math.exp(c.estimate))} (${fmt(math.exp(c.lower))} – ${fmt(math.exp(c.upper))})';
  final famName = family == GlmmFamily.binomial ? tr('logistique', 'logistic') : tr('de Poisson', 'Poisson');
  return AnalysisResult(
    methodId: 'glmm_longitudinal',
    methodName: tr('Modèle mixte $famName (intercept aléatoire par sujet)', 'Mixed $famName model (random intercept per subject)'),
    inputs: {'model': d0.describe(), 'subject': subject, 'family': family.name, 'nAGQ': nAgq, 'level': level},
    formula: tr(
        'g(E[yᵢⱼ | bᵢ]) = xᵢⱼᵀβ + bᵢ, bᵢ ~ N(0, σ²) ; vraisemblance marginale par ${nAgq == 1 ? 'l\'approximation de Laplace' : 'quadrature de Gauss-Hermite adaptative à $nAgq points'} au mode conditionnel ; maximum sur (σ, β) ; ES par la hessienne de la log-vraisemblance (différences finies), comme lme4 ; $effect = exp(β), propre au sujet (conditionnel), à σ fixé.',
        'g(E[yᵢⱼ | bᵢ]) = xᵢⱼᵀβ + bᵢ, bᵢ ~ N(0, σ²); marginal likelihood by ${nAgq == 1 ? 'the Laplace approximation' : '$nAgq-point adaptive Gauss-Hermite quadrature'} at the conditional mode; maximum over (σ, β); SEs from the Hessian of the log-likelihood (finite differences), as lme4; $effect = exp(β), subject-specific (conditional).'),
    estimates: [
      for (final c in coefs.skip(1)) Estimate('$effect — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), pValue: c.p, se: c.se, level: level),
      Estimate(tr('ÉT de l\'intercept aléatoire', 'SD of the random intercept'), fit.sigma),
      if (icc != null) Estimate(tr('CCI (échelle latente)', 'ICC (latent scale)'), icc),
    ],
    statistics: {
      'n': y.length.toDouble(), 'subjects': m.toDouble(), 'sigma': fit.sigma, 'loglik': fit.logLik, 'icc': ?icc, 'lrt_sigma': lrt, 'lrt_sigma_p': lrtP,
      for (var j = 0; j < p; j++) 'beta_${d0.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d0.columns[j]}': fit.se[j],
    },
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), fit.converged ? CheckStatus.ok : CheckStatus.warning, ''),
      Check('singular', tr('Variance entre sujets non nulle', 'Non-zero between-subject variance'), fit.singular ? CheckStatus.warning : CheckStatus.ok,
          '${fit.singular ? tr('Variance entre sujets nulle ou négligeable : les mesures d\'un même sujet ne sont pas plus semblables que celles de sujets différents ; le modèle se ramène au GLM. ', 'Zero or negligible between-subject variance: measurements of the same subject are no more alike than those of different subjects; the model reduces to the GLM. ') : ''}'
              '${tr('Test de σ = 0 : RV = ${fmt(lrt)}, ${fmtP(lrtP)}.', 'Test of σ = 0: LR = ${fmt(lrt)}, ${fmtP(lrtP)}.')}'),
      Check('subjects', tr('Assez de sujets (≥ 20 conseillé)', 'Enough subjects (≥ 20 advised)'), m >= 20 ? CheckStatus.ok : CheckStatus.warning, tr('$m sujets, ${y.length} mesures.', '$m subjects, ${y.length} measurements.')),
    ],
    alerts: [...d0.alerts],
    tables: [
      ResultTable(tr('Effets fixes', 'Fixed effects'), [tr('Terme', 'Term'), 'β', 'ES', 'z', 'p', '$effect (IC $pct %)'], [
        for (final c in coefs) [c.name, fmt(c.estimate), fmt(c.se), fmt(c.statistic), fmtP(c.p), c == coefs.first ? '' : eff(c)]
      ]),
      ResultTable(tr('Effet aléatoire et ajustement', 'Random effect and fit'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('ÉT de l\'intercept aléatoire ($subject)', 'SD of the random intercept ($subject)'), fmt(fit.sigma, digits: 4)],
        [tr('Log-vraisemblance', 'Log-likelihood'), fmt(fit.logLik, digits: 6)],
        [tr('Approximation', 'Approximation'), nAgq == 1 ? 'Laplace' : 'Gauss-Hermite ($nAgq)'],
        for (final c in d0.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Issue ${family == GlmmFamily.binomial ? 'binaire' : 'de comptage'} mesurée plusieurs fois chez les mêmes sujets : l\'intercept aléatoire tient compte de la ressemblance des mesures d\'un sujet et donne des effets propres au sujet.',
          '${family == GlmmFamily.binomial ? 'Binary' : 'Count'} outcome measured several times on the same subjects: the random intercept accounts for the similarity of a subject\'s measurements and gives subject-specific effects.'),
      whatItMeans: tr('« ${main.name} » : $effect = ${eff(main)}, ${fmtP(main.p)} (pour un même sujet). ÉT entre sujets : ${fmt(fit.sigma)}.',
          '"${main.name}": $effect = ${eff(main)}, ${fmtP(main.p)} (for the same subject). Between-subject SD: ${fmt(fit.sigma)}.'),
      notJustified: tr('Comparer directement un OR de modèle mixte (conditionnel) à un OR de GEE (marginal, plus proche de 1) ; ignorer un ajustement singulier.',
          'Comparing a mixed-model OR (conditional) directly with a GEE OR (marginal, closer to 1); ignoring a singular fit.'),
    ),
  );
}
