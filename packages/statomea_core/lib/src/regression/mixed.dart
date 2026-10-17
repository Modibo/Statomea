/// Modèle linéaire mixte pour mesures répétées : intercept (et pente) aléatoires par sujet, REML profilé comme lme4 :
///  θ = facteur de Cholesky relatif Λ de la covariance des effets aléatoires (G = σ²ΛΛᵀ) ;
///  d(θ) = Σᵢ log|Mᵢ| + log|XᵀV⁻¹X| + (N − p)(1 + log(2π r²/(N − p))), Mᵢ = ΛᵀZᵢᵀZᵢΛ + I (identité de Woodbury) ;
///  σ̂² = r²/(N − p), vcov(β̂) = σ̂²(XᵀV⁻¹X)⁻¹, BLUP bᵢ = ΛMᵢ⁻¹ΛᵀZᵢᵀ(yᵢ − Xᵢβ̂) ;
///  degrés de liberté de nlme (un niveau) : terme constant dans chaque sujet → m − p_inter − 1, autres → N − m − p_intra.
/// Validé contre validation/r/43_lmm_longitudinal.R (lme4 1.1, nlme 3.1).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

/// Données groupées : X (avec constante), y, sujet de chaque ligne (0 … m − 1), Z (1, ou 1 et temps).
class LmmData {
  final List<List<double>> x, z;
  final List<double> y;
  final List<int> group;
  final int m, p, q;
  late final List<List<int>> rowsOf = [for (var g = 0; g < m; g++) <int>[]];
  // Produits croisés par sujet.
  late final List<Matrix> ztz, ztx, xtx;
  late final List<List<double>> zty, xty;
  late final List<double> yty;
  LmmData(this.x, this.y, this.group, this.z)
      : m = group.reduce(math.max) + 1,
        p = x.first.length,
        q = z.first.length {
    for (var i = 0; i < y.length; i++) {
      rowsOf[group[i]].add(i);
    }
    ztz = [];
    ztx = [];
    xtx = [];
    zty = [];
    xty = [];
    yty = [];
    for (final rows in rowsOf) {
      final a = Matrix(q, q), b = Matrix(q, p), c = Matrix(p, p);
      final zy = List<double>.filled(q, 0), xy = List<double>.filled(p, 0);
      var yy = 0.0;
      for (final i in rows) {
        for (var r = 0; r < q; r++) {
          zy[r] += z[i][r] * y[i];
          for (var s = 0; s < q; s++) {
            a.data[r * q + s] += z[i][r] * z[i][s];
          }
          for (var s = 0; s < p; s++) {
            b.data[r * p + s] += z[i][r] * x[i][s];
          }
        }
        for (var r = 0; r < p; r++) {
          xy[r] += x[i][r] * y[i];
          for (var s = 0; s < p; s++) {
            c.data[r * p + s] += x[i][r] * x[i][s];
          }
        }
        yy += y[i] * y[i];
      }
      ztz.add(a);
      ztx.add(b);
      xtx.add(c);
      zty.add(zy);
      xty.add(xy);
      yty.add(yy);
    }
  }

  /// Λ (q × q, triangulaire inférieure) à partir de θ (ordre de lme4 : colonne par colonne).
  Matrix lambda(List<double> theta) {
    final l = Matrix(q, q);
    var k = 0;
    for (var j = 0; j < q; j++) {
      for (var i = j; i < q; i++) {
        l.set(i, j, theta[k++]);
      }
    }
    return l;
  }
}

class _Eval {
  final double deviance, r2, logDetM, logDetA;
  final Matrix a; // XᵀV⁻¹X (V/σ²)
  final List<double> beta;
  const _Eval(this.deviance, this.r2, this.logDetM, this.logDetA, this.a, this.beta);
}

double _logDetChol(Matrix l) {
  var s = 0.0;
  for (var i = 0; i < l.rows; i++) {
    s += 2 * math.log(l.get(i, i));
  }
  return s;
}

_Eval? _evaluate(LmmData d, List<double> theta) {
  final p = d.p, q = d.q;
  final lam = d.lambda(theta), lamT = lam.transpose();
  final a = Matrix(p, p);
  final b = List<double>.filled(p, 0);
  var yvy = 0.0, logDetM = 0.0;
  for (var g = 0; g < d.m; g++) {
    // M = ΛᵀZᵀZΛ + I ; termes de Woodbury : (ΛᵀZᵀX), (ΛᵀZᵀy).
    final mm = lamT * d.ztz[g] * lam;
    for (var i = 0; i < q; i++) {
      mm.data[i * q + i] += 1;
    }
    final lc = cholesky(mm);
    if (lc == null) return null;
    logDetM += _logDetChol(lc);
    final lzx = lamT * d.ztx[g]; // q × p
    final lzy = lamT.multiplyVector(d.zty[g]);
    final mInv = invertSpd(mm)!;
    final mx = mInv * lzx; // q × p
    final my = mInv.multiplyVector(lzy);
    for (var r = 0; r < p; r++) {
      var s = d.xty[g][r];
      for (var k = 0; k < q; k++) {
        s -= lzx.get(k, r) * my[k];
      }
      b[r] += s;
      for (var c = 0; c < p; c++) {
        var t = d.xtx[g].get(r, c);
        for (var k = 0; k < q; k++) {
          t -= lzx.get(k, r) * mx.get(k, c);
        }
        a.data[r * p + c] += t;
      }
    }
    var t = d.yty[g];
    for (var k = 0; k < q; k++) {
      t -= lzy[k] * my[k];
    }
    yvy += t;
  }
  final la = cholesky(a);
  if (la == null) return null;
  final beta = solveSpd(a, b)!;
  var r2 = yvy;
  for (var r = 0; r < p; r++) {
    r2 -= b[r] * beta[r];
  }
  final n = d.y.length, nu = (n - p).toDouble();
  final logDetA = _logDetChol(la);
  final dev = logDetM + logDetA + nu * (1 + math.log(2 * math.pi * r2 / nu));
  return _Eval(dev, r2, logDetM, logDetA, a, beta);
}

/// Déviance REML profilée de lme4 en θ (null si non définie).
double? lmmRemlDeviance(LmmData d, List<double> theta) => _evaluate(d, theta)?.deviance;

List<double> _nelderMead(double Function(List<double>) f, List<double> x0, {double step = 0.3, int maxIter = 20000, double tol = 1e-15}) {
  final n = x0.length;
  var pts = <List<double>>[x0, for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) x0[j] + (i == j ? step : 0)]];
  var vals = [for (final p in pts) f(p)];
  for (var it = 0; it < maxIter; it++) {
    final idx = List<int>.generate(n + 1, (i) => i)..sort((a, b) => vals[a].compareTo(vals[b]));
    pts = [for (final i in idx) pts[i]];
    vals = [for (final i in idx) vals[i]];
    var spread = 0.0;
    for (var i = 1; i <= n; i++) {
      for (var j = 0; j < n; j++) {
        spread = math.max(spread, (pts[i][j] - pts[0][j]).abs());
      }
    }
    if ((vals.last - vals.first).abs() < tol * (1 + vals.first.abs()) && spread < 1e-10) break;
    final c = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        c[j] += pts[i][j] / n;
      }
    }
    List<double> at(double t) => [for (var j = 0; j < n; j++) c[j] + t * (pts[n][j] - c[j])];
    final xr = at(-1), fr = f(xr);
    if (fr < vals.first) {
      final xe = at(-2), fe = f(xe);
      if (fe < fr) {
        pts[n] = xe;
        vals[n] = fe;
      } else {
        pts[n] = xr;
        vals[n] = fr;
      }
    } else if (fr < vals[n - 1]) {
      pts[n] = xr;
      vals[n] = fr;
    } else {
      final xc = fr < vals[n] ? at(-0.5) : at(0.5);
      final fc = f(xc);
      if (fc < math.min(fr, vals[n])) {
        pts[n] = xc;
        vals[n] = fc;
      } else {
        for (var i = 1; i <= n; i++) {
          pts[i] = [for (var j = 0; j < n; j++) pts[0][j] + 0.5 * (pts[i][j] - pts[0][j])];
          vals[i] = f(pts[i]);
        }
      }
    }
  }
  final best = List<int>.generate(n + 1, (i) => i).reduce((a, b) => vals[a] <= vals[b] ? a : b);
  return pts[best];
}

class LmmLongFit {
  final List<double> beta, theta;
  final Matrix cov, g; // vcov(β̂), covariance des effets aléatoires
  final double sigma2, reml;
  final List<List<double>> blups;
  final bool singular;
  const LmmLongFit(this.beta, this.theta, this.cov, this.g, this.sigma2, this.reml, this.blups, this.singular);
}

/// Ajustement REML : Nelder-Mead sur θ (départ de lme4 : Λ = I), relancé jusqu'à stabilité de la déviance.
LmmLongFit fitLongitudinalLmm(LmmData d) {
  final q = d.q;
  final nTheta = q * (q + 1) ~/ 2;
  double f(List<double> t) => _evaluate(d, t)?.deviance ?? double.infinity;
  var theta = [for (var j = 0; j < q; j++) for (var i = j; i < q; i++) i == j ? 1.0 : 0.0];
  var best = f(theta);
  for (var restart = 0; restart < 8; restart++) {
    final t = _nelderMead(f, theta, step: restart == 0 ? 0.5 : 0.05);
    final v = f(t);
    final improved = best - v;
    theta = t;
    best = v;
    if (restart > 0 && improved.abs() < 1e-12) break;
  }
  // Colonnes de Λ au signe positif sur la diagonale (G inchangé).
  final lam0 = d.lambda(theta);
  for (var j = 0; j < q; j++) {
    if (lam0.get(j, j) < 0) {
      for (var i = j; i < q; i++) {
        lam0.set(i, j, -lam0.get(i, j));
      }
    }
  }
  theta = [for (var j = 0; j < q; j++) for (var i = j; i < q; i++) lam0.get(i, j)];
  final e = _evaluate(d, theta)!;
  final n = d.y.length;
  final sigma2 = e.r2 / (n - d.p);
  final aInv = invertSpd(e.a)!;
  final cov = Matrix(d.p, d.p);
  for (var i = 0; i < d.p * d.p; i++) {
    cov.data[i] = sigma2 * aInv.data[i];
  }
  final lam = d.lambda(theta);
  final g = lam * lam.transpose();
  for (var i = 0; i < q * q; i++) {
    g.data[i] *= sigma2;
  }
  final blups = <List<double>>[];
  final lamT = lam.transpose();
  for (var gi = 0; gi < d.m; gi++) {
    final mm = lamT * d.ztz[gi] * lam;
    for (var i = 0; i < q; i++) {
      mm.data[i * q + i] += 1;
    }
    // Zᵀ(y − Xβ) = Zᵀy − ZᵀXβ
    final zr = [for (var k = 0; k < q; k++) d.zty[gi][k] - [for (var c = 0; c < d.p; c++) d.ztx[gi].get(k, c) * e.beta[c]].fold(0.0, (s, v) => s + v)];
    final u = solveSpd(mm, lamT.multiplyVector(zr))!;
    blups.add(lam.multiplyVector(u));
  }
  final singular = [for (var j = 0; j < q; j++) lam.get(j, j)].any((v) => v.abs() < 1e-6);
  assert(nTheta == theta.length);
  return LmmLongFit(e.beta, theta, cov, g, sigma2, e.deviance, blups, singular);
}

/// Degrés de liberté de nlme pour chaque colonne de X (la première est la constante).
List<double> nlmeDf(LmmData d) {
  final n = d.y.length;
  final between = [
    for (var c = 1; c < d.p; c++)
      d.rowsOf.every((rows) => rows.every((i) => d.x[i][c] == d.x[rows.first][c]))
  ];
  final pB = between.where((b) => b).length, pW = between.length - pB;
  return [(n - d.m - pW).toDouble(), for (final b in between) b ? (d.m - pB - 1).toDouble() : (n - d.m - pW).toDouble()];
}

/// Analyse complète d'un jeu de données longitudinal : [subject] identifie le sujet ; [slope] (variable numérique,
/// p. ex. le temps) ajoute une pente aléatoire par sujet.
AnalysisResult longitudinalMixedModel(Dataset ds, ModelFormula f, {required String subject, String? slope, double level = 0.95}) {
  final d0 = buildDesign(ds, f);
  final subj = ds.text(subject);
  final slopeVals = slope == null ? null : ds.numeric(slope);
  final keep = [
    for (var k = 0; k < d0.n; k++)
      if (subj[d0.rows[k]] != null && (slopeVals == null || slopeVals[d0.rows[k]] != null)) k
  ];
  final ids = <String, int>{};
  final group = [for (final k in keep) ids.putIfAbsent(subj[d0.rows[k]]!, () => ids.length)];
  if (ids.length < 3) throw StatInputError('few_subjects', tr('Au moins 3 sujets sont nécessaires.', 'At least 3 subjects are required.'));
  final x = [for (final k in keep) d0.x[k]], y = [for (final k in keep) d0.y[k]];
  final z = [for (final k in keep) [1.0, if (slopeVals != null) slopeVals[d0.rows[k]]!]];
  final data = LmmData(x, y, group, z);
  final fit = fitLongitudinalLmm(data);
  final df = nlmeDf(data);
  final n = y.length, m = data.m, p = data.p;
  final coefs = [
    for (var j = 0; j < p; j++)
      () {
        final se = math.sqrt(fit.cov.get(j, j)), t = fit.beta[j] / se;
        final tq = tQuantile(1 - (1 - level) / 2, df[j]);
        return Coefficient(d0.columns[j], fit.beta[j], se, t, 2 * (1 - tCdf(t.abs(), df[j])), fit.beta[j] - tq * se, fit.beta[j] + tq * se);
      }()
  ];
  final sdInt = math.sqrt(fit.g.get(0, 0)), sigma = math.sqrt(fit.sigma2);
  final sdSlope = slope == null ? null : math.sqrt(fit.g.get(1, 1));
  final corr = slope == null || sdSlope == 0 || sdInt == 0 ? null : fit.g.get(0, 1) / (sdInt * sdSlope!);
  final icc = slope == null ? fit.g.get(0, 0) / (fit.g.get(0, 0) + fit.sigma2) : null;
  final perSubject = [for (final r in data.rowsOf) r.length]..sort();
  final pct = (level * 100).round();
  final u = ds.dictionary[f.outcome]?.unit ?? '';
  // Trajectoires : observations par sujet (60 au plus) et moyenne ajustée (partie fixe) par temps et par groupe.
  Map<String, Object?>? traj;
  if (slope != null) {
    final cat = [for (final t in f.terms) if (t.categorical) t.variable];
    final grpText = cat.isEmpty ? null : ds.text(cat.first);
    final fitted = <String, Map<double, List<double>>>{};
    for (var k = 0; k < keep.length; k++) {
      var xb = 0.0;
      for (var j = 0; j < p; j++) {
        xb += x[k][j] * fit.beta[j];
      }
      final gl = grpText?[d0.rows[keep[k]]] ?? tr('ensemble', 'overall');
      fitted.putIfAbsent(gl, () => {}).putIfAbsent(z[k][1], () => []).add(xb);
    }
    traj = {
      'xLabel': slope,
      'yLabel': f.outcome,
      'subjects': [
        for (var g = 0; g < math.min(m, 60); g++)
          {
            'x': [for (final i in data.rowsOf[g]) z[i][1]],
            'y': [for (final i in data.rowsOf[g]) y[i]],
          }
      ],
      'mean': [
        for (final e in fitted.entries)
          {
            'group': e.key,
            'x': (e.value.keys.toList()..sort()),
            'y': [for (final t in (e.value.keys.toList()..sort())) e.value[t]!.reduce((a, b) => a + b) / e.value[t]!.length],
          }
      ],
    };
  }
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  return AnalysisResult(
    methodId: 'lmm_longitudinal',
    methodName: tr('Modèle mixte pour mesures répétées (${slope == null ? 'intercept aléatoire' : 'intercept et pente aléatoires'})',
        'Mixed model for repeated measures (${slope == null ? 'random intercept' : 'random intercept and slope'})'),
    inputs: {'model': d0.describe(), 'subject': subject, 'slope': slope, 'level': level},
    formula: tr(
        'yᵢⱼ = xᵢⱼᵀβ + b₀ᵢ${slope == null ? '' : ' + b₁ᵢ·$slope'} + εᵢⱼ ; bᵢ ~ N(0, G), ε ~ N(0, σ²). REML profilé (comme lme4) : déviance d(θ) en fonction du facteur de Cholesky relatif de G, minimisée par Nelder-Mead ; vcov(β̂) = σ̂²(XᵀV⁻¹X)⁻¹ ; tests t avec les degrés de liberté de nlme (terme constant au sein des sujets : m − p_inter − 1, sinon N − m − p_intra) ; BLUP des effets individuels.',
        'yᵢⱼ = xᵢⱼᵀβ + b₀ᵢ${slope == null ? '' : ' + b₁ᵢ·$slope'} + εᵢⱼ; bᵢ ~ N(0, G), ε ~ N(0, σ²). Profiled REML (as lme4): deviance d(θ) as a function of the relative Cholesky factor of G, minimized by Nelder-Mead; vcov(β̂) = σ̂²(XᵀV⁻¹X)⁻¹; t tests with nlme degrees of freedom (term constant within subjects: m − p_between − 1, otherwise N − m − p_within); BLUPs of individual effects.'),
    estimates: [
      for (final c in coefs.skip(1)) Estimate(c.name, c.estimate, lower: c.lower, upper: c.upper, se: c.se, pValue: c.p, level: level),
      Estimate(tr('ÉT de l\'intercept aléatoire', 'SD of the random intercept'), sdInt),
      if (sdSlope != null) Estimate(tr('ÉT de la pente aléatoire ($slope)', 'SD of the random slope ($slope)'), sdSlope),
      Estimate(tr('ÉT résiduel', 'Residual SD'), sigma),
      if (icc != null) Estimate(tr('Corrélation intra-sujet (CCI)', 'Intra-subject correlation (ICC)'), icc),
    ],
    statistics: {
      'n': n.toDouble(), 'subjects': m.toDouble(), 'reml': fit.reml, 'sigma': sigma, 'sd_intercept': sdInt,
      'sd_slope': ?sdSlope, 'corr': ?corr, 'icc': ?icc,
      for (var j = 0; j < p; j++) 'beta_${d0.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d0.columns[j]}': coefs[j].se,
      for (var j = 0; j < p; j++) 'df_${d0.columns[j]}': df[j],
      for (var j = 0; j < p; j++) 'p_${d0.columns[j]}': coefs[j].p,
      for (var i = 0; i < fit.theta.length; i++) 'theta_$i': fit.theta[i],
    },
    checks: [
      Check('subjects', tr('Nombre de sujets suffisant pour estimer la variance entre sujets', 'Enough subjects to estimate the between-subject variance'), m >= 10 ? CheckStatus.ok : CheckStatus.warning,
          tr('$m sujets, $n mesures (${perSubject.first} à ${perSubject.last} par sujet).', '$m subjects, $n measurements (${perSubject.first} to ${perSubject.last} per subject).')),
      Check('singular', tr('Variances des effets aléatoires non nulles', 'Non-zero random-effect variances'), fit.singular ? CheckStatus.warning : CheckStatus.ok,
          fit.singular
              ? tr('Ajustement singulier : une variance (ou une corrélation) est estimée à la frontière ; simplifier les effets aléatoires (p. ex. sans pente aléatoire).',
                  'Singular fit: a variance (or a correlation) is estimated at the boundary; simplify the random effects (e.g. without random slope).')
              : ''),
      Check('missing_mar', tr('Données manquantes ignorables (MAR)', 'Ignorable missing data (MAR)'), CheckStatus.notAssessed,
          tr('Le modèle mixte utilise toutes les mesures disponibles et reste valide si les sorties d\'étude dépendent des valeurs déjà observées (MAR), pas si elles dépendent de la valeur manquante elle-même.',
              'The mixed model uses all available measurements and remains valid if dropout depends on values already observed (MAR), not if it depends on the missing value itself.')),
    ],
    alerts: [...d0.alerts],
    tables: [
      ResultTable(tr('Effets fixes', 'Fixed effects'), [tr('Terme', 'Term'), tr('Estimation', 'Estimate'), 'ES', 't', tr('ddl', 'df'), 'p', tr('IC $pct %', '$pct% CI')], [
        for (var j = 0; j < p; j++)
          [coefs[j].name, fmt(coefs[j].estimate), fmt(coefs[j].se), fmt(coefs[j].statistic), fmt(df[j], digits: 0), fmtP(coefs[j].p), '${fmt(coefs[j].lower)} – ${fmt(coefs[j].upper)}']
      ]),
      ResultTable(tr('Effets aléatoires (sujet : $subject)', 'Random effects (subject: $subject)'), [tr('Composante', 'Component'), tr('Écart-type', 'Standard deviation'), tr('Corrélation', 'Correlation')], [
        [tr('Intercept', 'Intercept'), fmt(sdInt), ''],
        if (sdSlope != null) [slope!, fmt(sdSlope), corr == null ? '' : fmt(corr)],
        [tr('Résidu', 'Residual'), fmt(sigma), ''],
      ]),
      ResultTable(tr('Codage et observations', 'Coding and observations'), [tr('Élément', 'Item'), tr('Détail', 'Detail')], [
        [tr('Modèle', 'Model'), '${d0.formula} + (${slope == null ? '1' : '1 + $slope'} | $subject)'],
        [tr('Mesures / sujets', 'Measurements / subjects'), '$n / $m'],
        [tr('Critère REML', 'REML criterion'), fmt(fit.reml, digits: 2)],
        for (final c in d0.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    figures: {'trajectories': ?traj},
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Mesures répétées chez les mêmes sujets : elles ne sont pas indépendantes. Le modèle mixte sépare la variabilité entre sujets (effets aléatoires) de la variabilité intra-sujet, utilise toutes les mesures disponibles, même incomplètes, et donne des erreurs types correctes pour les effets fixes.',
          'Repeated measurements on the same subjects are not independent. The mixed model separates between-subject variability (random effects) from within-subject variability, uses all available measurements, even incomplete ones, and gives correct standard errors for the fixed effects.'),
      whatItMeans: tr('« ${main.name} » : ${fmt(main.estimate)}$u (IC ${fmt(main.lower)} à ${fmt(main.upper)}), ${fmtP(main.p)}. Variabilité entre sujets : ÉT ${fmt(sdInt)}${sdSlope == null ? '' : ' (intercept), ${fmt(sdSlope)} (pente)'} ; résiduelle : ${fmt(sigma)}.',
          '"${main.name}": ${fmt(main.estimate)}$u (CI ${fmt(main.lower)} to ${fmt(main.upper)}), ${fmtP(main.p)}. Between-subject variability: SD ${fmt(sdInt)}${sdSlope == null ? '' : ' (intercept), ${fmt(sdSlope)} (slope)'}; residual: ${fmt(sigma)}.'),
      notJustified: tr(
          'Analyser les mesures répétées comme indépendantes (ES trop petits) ; comparer les groupes visite par visite en multipliant les tests ; exclure les sujets incomplets ; lire l\'interaction temps × traitement comme un effet causal hors essai randomisé.',
          'Analysing repeated measurements as independent (SEs too small); comparing groups visit by visit with multiple tests; excluding incomplete subjects; reading the time × treatment interaction as a causal effect outside a randomized trial.'),
    ),
  );
}
