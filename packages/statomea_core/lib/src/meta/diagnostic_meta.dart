/// Métaanalyse diagnostique bivariée (Reitsma et al. 2005) : logit(Se) et
/// logit(taux de faux positifs) suivent une loi normale bivariée entre
/// études ; variances intra-étude 1/VP + 1/FN et 1/FP + 1/VN. Estimation par
/// REML. Conventions alignées sur `mada::reitsma` (via `mvmeta`) :
/// correction de 0,5 de toutes les cellules de toutes les études dès qu'une
/// cellule est nulle ; log-vraisemblance REML + terme jacobien ; courbe SROC
/// de Rutter-Gatsonis et AUC par trapèzes sur FPR = 0,01…0,99.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import 'meta.dart';

double _logit(double p) => math.log(p / (1 - p));
double _expit(double x) => 1 / (1 + math.exp(-x));

class BivariateFit {
  final double mu1, mu2; // logit(Se), logit(FPR)
  final List<List<double>> vcov; // 2 × 2
  final double tau1, tau2, rho;
  final double remlLogLik, madaLogLik;
  final bool converged, boundary;
  final int k;
  BivariateFit(this.mu1, this.mu2, this.vcov, this.tau1, this.tau2, this.rho, this.remlLogLik, this.madaLogLik, this.converged,
      this.boundary, this.k);
}

class _Data {
  final List<double> y1, y2, s1, s2, sens, fpr;
  _Data(this.y1, this.y2, this.s1, this.s2, this.sens, this.fpr);
}

/// Inverse et log-déterminant d'une matrice 2 × 2 symétrique.
({double a, double b, double c, double logDet}) _inv2(double a, double b, double c) {
  final det = a * c - b * b;
  return (a: c / det, b: -b / det, c: a / det, logDet: math.log(det));
}

({double ll, double m1, double m2, List<List<double>> vcov}) _reml(_Data d, double t1, double t2, double r) {
  final p11 = t1 * t1, p22 = t2 * t2, p12 = r * t1 * t2;
  var sa = 0.0, sb = 0.0, sc = 0.0, z1 = 0.0, z2 = 0.0, logDetSum = 0.0;
  final invs = <({double a, double b, double c, double logDet})>[];
  for (var i = 0; i < d.y1.length; i++) {
    final inv = _inv2(p11 + d.s1[i], p12, p22 + d.s2[i]);
    invs.add(inv);
    logDetSum += inv.logDet;
    sa += inv.a;
    sb += inv.b;
    sc += inv.c;
    z1 += inv.a * d.y1[i] + inv.b * d.y2[i];
    z2 += inv.b * d.y1[i] + inv.c * d.y2[i];
  }
  final tot = _inv2(sa, sb, sc);
  final m1 = tot.a * z1 + tot.b * z2, m2 = tot.b * z1 + tot.c * z2;
  var quad = 0.0;
  for (var i = 0; i < d.y1.length; i++) {
    final e1 = d.y1[i] - m1, e2 = d.y2[i] - m2;
    quad += invs[i].a * e1 * e1 + 2 * invs[i].b * e1 * e2 + invs[i].c * e2 * e2;
  }
  final n = 2 * d.y1.length;
  // tot.logDet = log|Σ XᵀV⁻¹X| (déterminant de la matrice d'entrée de _inv2).
  final ll = -0.5 * (n - 2) * math.log(2 * math.pi) - 0.5 * logDetSum - 0.5 * tot.logDet - 0.5 * quad;
  return (ll: ll, m1: m1, m2: m2, vcov: [[tot.a, tot.b], [tot.b, tot.c]]);
}

/// Nelder-Mead pour minimiser f.
List<double> _nelderMead(double Function(List<double>) f, List<double> x0, {double step = 0.5, int maxIter = 5000, double tol = 1e-14}) {
  final n = x0.length;
  var pts = <List<double>>[x0, for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) x0[j] + (i == j ? step : 0)]];
  var vals = [for (final p in pts) f(p)];
  for (var it = 0; it < maxIter; it++) {
    final idx = List<int>.generate(n + 1, (i) => i)..sort((a, b) => vals[a].compareTo(vals[b]));
    pts = [for (final i in idx) pts[i]];
    vals = [for (final i in idx) vals[i]];
    if ((vals.last - vals.first).abs() < tol * (1 + vals.first.abs())) break;
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

/// Raffinement de Newton par différences finies (gradient et hessien numériques).
List<double> _newtonRefine(double Function(List<double>) f, List<double> x, {int iters = 50}) {
  final n = x.length;
  var cur = List<double>.of(x);
  for (var it = 0; it < iters; it++) {
    const h = 1e-4;
    double fx(List<double> p) => f(p);
    final g = List<double>.filled(n, 0);
    final hm = List.generate(n, (_) => List<double>.filled(n, 0));
    final f0 = fx(cur);
    for (var i = 0; i < n; i++) {
      final up = List<double>.of(cur)..[i] += h;
      final dn = List<double>.of(cur)..[i] -= h;
      final fu = fx(up), fd = fx(dn);
      g[i] = (fu - fd) / (2 * h);
      hm[i][i] = (fu - 2 * f0 + fd) / (h * h);
      for (var j = 0; j < i; j++) {
        final pp = List<double>.of(cur)..[i] += h..[j] += h;
        final pm = List<double>.of(cur)..[i] += h..[j] -= h;
        final mp = List<double>.of(cur)..[i] -= h..[j] += h;
        final mm = List<double>.of(cur)..[i] -= h..[j] -= h;
        hm[i][j] = hm[j][i] = (fx(pp) - fx(pm) - fx(mp) + fx(mm)) / (4 * h * h);
      }
    }
    // Résolution H δ = −g (Gauss).
    final a = [for (var i = 0; i < n; i++) [...hm[i], -g[i]]];
    var ok = true;
    for (var c = 0; c < n; c++) {
      var piv = c;
      for (var r = c + 1; r < n; r++) {
        if (a[r][c].abs() > a[piv][c].abs()) piv = r;
      }
      if (a[piv][c].abs() < 1e-14) {
        ok = false;
        break;
      }
      final tmp = a[c];
      a[c] = a[piv];
      a[piv] = tmp;
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        final fct = a[r][c] / a[c][c];
        for (var k = c; k <= n; k++) {
          a[r][k] -= fct * a[c][k];
        }
      }
    }
    if (!ok) break;
    var delta = [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
    var next = [for (var i = 0; i < n; i++) cur[i] + delta[i]];
    var tries = 0;
    while (f(next) > f0 && tries < 20) {
      delta = [for (final d in delta) d / 2];
      next = [for (var i = 0; i < n; i++) cur[i] + delta[i]];
      tries++;
    }
    if (f(next) > f0) break;
    cur = next;
    if (delta.map((d) => d.abs()).reduce(math.max) < 1e-10) break;
  }
  return cur;
}

({_Data data, bool corrected}) _prepare(List<List<double>> counts) {
  final anyZero = counts.any((c) => c.contains(0));
  final add = anyZero ? 0.5 : 0.0;
  final y1 = <double>[], y2 = <double>[], s1 = <double>[], s2 = <double>[], sens = <double>[], fpr = <double>[];
  for (final c in counts) {
    final tp = c[0] + add, fp = c[1] + add, fn = c[2] + add, tn = c[3] + add;
    final se = tp / (tp + fn), fr = fp / (fp + tn);
    sens.add(se);
    fpr.add(fr);
    y1.add(_logit(se));
    y2.add(_logit(fr));
    s1.add(1 / tp + 1 / fn);
    s2.add(1 / fp + 1 / tn);
  }
  return (data: _Data(y1, y2, s1, s2, sens, fpr), corrected: anyZero);
}

/// Ajustement du modèle bivarié. [counts] : (VP, FP, FN, VN) par étude.
BivariateFit fitBivariate(List<List<double>> counts) {
  final prep = _prepare(counts);
  final d = prep.data;
  // Départ : τ² de DerSimonian-Laird univariés, ρ = 0.
  final t1 = math.sqrt(math.max(1e-4, poolInverseVariance(d.y1, d.s1, method: TauMethod.dl).tau2));
  final t2 = math.sqrt(math.max(1e-4, poolInverseVariance(d.y2, d.s2, method: TauMethod.dl).tau2));
  double negLl(List<double> p) {
    final a = p[0].clamp(-12.0, 5.0), b = p[1].clamp(-12.0, 5.0), c = p[2].clamp(-8.0, 8.0);
    return -_reml(d, math.exp(a), math.exp(b), _tanh(c)).ll;
  }

  var par = _nelderMead(negLl, [math.log(t1), math.log(t2), 0]);
  par = _nelderMead(negLl, par, step: 0.05);
  par = _newtonRefine(negLl, par);
  final tau1 = math.exp(par[0].clamp(-12.0, 5.0)), tau2 = math.exp(par[1].clamp(-12.0, 5.0)), rho = _tanh(par[2].clamp(-8.0, 8.0));
  final fit = _reml(d, tau1, tau2, rho);
  var jac = 0.0;
  for (var i = 0; i < d.sens.length; i++) {
    jac += math.log(1 / (d.sens[i] * (1 - d.sens[i]))) + math.log(1 / (d.fpr[i] * (1 - d.fpr[i])));
  }
  final boundary = tau1 < 1e-4 || tau2 < 1e-4 || rho.abs() > 0.999;
  return BivariateFit(fit.m1, fit.m2, fit.vcov, tau1, tau2, rho, fit.ll, fit.ll + jac, true, boundary, counts.length);
}

double _tanh(double z) {
  final e = math.exp(2 * z);
  return (e - 1) / (e + 1);
}

/// Courbe SROC de Rutter-Gatsonis déduite des paramètres bivariés (comme mada).
double Function(double) srocFunction(BivariateFit f) {
  final s1 = f.tau1, s2 = f.tau2;
  final lambda = math.sqrt(s2 / s1) * f.mu1 - math.sqrt(s1 / s2) * f.mu2;
  final beta = math.log(s2 / s1);
  return (fpr) => _expit(lambda * math.exp(-beta / 2) + math.exp(-beta) * _logit(fpr));
}

/// AUC de la SROC (trapèzes sur FPR = 0,01 … 0,99, convention de mada).
double srocAuc(BivariateFit f) {
  final g = srocFunction(f);
  final s = [for (var i = 1; i <= 99; i++) g(i / 100)];
  var sum = s.first / 2 + s.last / 2;
  for (var i = 1; i < 98; i++) {
    sum += s[i];
  }
  return sum / 99;
}

/// Ellipse (logit) transformée en points (FPR, Se).
List<List<double>> _ellipse(double m1, double m2, double v11, double v12, double v22, double level) {
  final r = math.sqrt(chiSquareQuantile(level, 2));
  // Cholesky de [[v22, v12], [v12, v11]] dans l'ordre (x = logit FPR, y = logit Se).
  final a = math.sqrt(v22);
  final b = v12 / a;
  final c = math.sqrt(math.max(0.0, v11 - b * b));
  return [
    for (var i = 0; i <= 72; i++)
      () {
        final t = 2 * math.pi * i / 72;
        final u = r * math.cos(t), w = r * math.sin(t);
        return [_expit(m2 + a * u), _expit(m1 + b * u + c * w)];
      }()
  ];
}

/// Analyse complète. Les études portent les valeurs « tp », « fp », « fn », « tn ».
AnalysisResult diagnosticMetaAnalysis(List<Study> all, {double level = 0.95}) {
  final used = <Study>[];
  final excluded = <List<String>>[];
  for (final s in all) {
    final v = [s.v('tp'), s.v('fp'), s.v('fn'), s.v('tn')];
    if (s.excluded) {
      excluded.add([s.label, tr("exclue par l'utilisateur : ${s.exclusionReason}", 'excluded by the user: ${s.exclusionReason}')]);
    } else if (v.contains(null) || v.any((x) => x! < 0)) {
      excluded.add([s.label, tr('VP, FP, FN ou VN manquant ou négatif', 'TP, FP, FN or TN missing or negative')]);
    } else if (v[0]! + v[2]! == 0 || v[1]! + v[3]! == 0) {
      excluded.add([s.label, tr('aucun malade ou aucun non-malade selon la référence', 'no diseased or no non-diseased subject according to the reference')]);
    } else {
      used.add(s);
    }
  }
  final k = used.length;
  if (k < 3) throw StatInputError('diag_meta_few', tr('Au moins 3 études exploitables sont nécessaires (ici $k) ; 5 ou plus sont recommandées.', 'At least 3 usable studies are needed (here $k); 5 or more are recommended.'));
  final counts = [for (final s in used) [s.v('tp')!, s.v('fp')!, s.v('fn')!, s.v('tn')!]];
  final prep = _prepare(counts);
  final f = fitBivariate(counts);
  final z = normalQuantile(1 - (1 - level) / 2);
  final se1 = math.sqrt(f.vcov[0][0]), se2 = math.sqrt(f.vcov[1][1]);
  final sens = _expit(f.mu1), fpr = _expit(f.mu2);
  final sensLo = _expit(f.mu1 - z * se1), sensHi = _expit(f.mu1 + z * se1);
  final fprLo = _expit(f.mu2 - z * se2), fprHi = _expit(f.mu2 + z * se2);
  final logDor = f.mu1 - f.mu2;
  final seDor = math.sqrt(f.vcov[0][0] + f.vcov[1][1] - 2 * f.vcov[0][1]);
  final auc = srocAuc(f);
  final pct = (level * 100).round();
  final alerts = <Alert>[
    if (prep.corrected)
      Alert('diag_meta_correction', Severity.caution,
          tr('Au moins une cellule nulle : 0,5 ajouté à toutes les cellules de toutes les études (convention de mada).', 'At least one zero cell: 0.5 added to all cells of all studies (mada convention).')),
    if (k < 5) Alert('diag_meta_few', Severity.serious, tr('Seulement $k études : τ² et ρ sont très imprécis ; le modèle bivarié peut être instable.', 'Only $k studies: τ² and ρ are very imprecise; the bivariate model may be unstable.')),
    if (f.boundary)
      Alert('diag_meta_boundary', Severity.caution,
          tr('Estimation à la frontière (τ ≈ 0 ou |ρ| ≈ 1) : interpréter la corrélation et la courbe SROC avec prudence.', 'Estimate on the boundary (τ ≈ 0 or |ρ| ≈ 1): interpret the correlation and the SROC curve with caution.')),
    Alert('diag_meta_quality', Severity.info,
        tr("La qualité des études (QUADAS-2 : spectre des patients, référence, aveugle, flux) conditionne la validité de Se et Sp combinées ; l'évaluer étude par étude.",
            'Study quality (QUADAS-2: patient spectrum, reference, blinding, flow) determines the validity of pooled Se and Sp; assess it study by study.')),
    if (excluded.isNotEmpty) Alert('excluded_studies', Severity.caution, tr('${excluded.length} étude(s) non incluse(s).', '${excluded.length} study(ies) not included.')),
  ];
  final incompatible = [for (final s in used) if (s.compatibility.all.contains(Compat.no)) s.label];
  if (incompatible.isNotEmpty) {
    alerts.add(Alert('incompatible_studies', Severity.serious, tr('Études jugées incompatibles combinées : ${incompatible.join(", ")}.', 'Studies judged incompatible are combined: ${incompatible.join(", ")}.')));
  }
  final g = srocFunction(f);
  final fprMin = math.max(0.01, prep.data.fpr.reduce(math.min)), fprMax = math.min(0.99, prep.data.fpr.reduce(math.max));
  return AnalysisResult(
    methodId: 'meta_diagnostic',
    methodName: tr('Métaanalyse diagnostique bivariée (Reitsma)', 'Bivariate diagnostic meta-analysis (Reitsma)'),
    inputs: {'k': k, 'level': level, 'studies': [for (final s in all) s.toJson()], 'corrected': prep.corrected},
    formula: tr("(logit Se_i, logit FPR_i) ~ N₂(μ, Σ + S_i), S_i = diag(1/VP + 1/FN, 1/FP + 1/VN) ; Σ = [[τ₁², ρτ₁τ₂], [ρτ₁τ₂, τ₂²]] estimée par REML ; Se = expit(μ₁), Sp = 1 − expit(μ₂), IC de Wald sur l'échelle logit ; SROC de Rutter-Gatsonis (Λ = √(τ₂/τ₁)μ₁ − √(τ₁/τ₂)μ₂, β = log(τ₂/τ₁)).",
        '(logit Se_i, logit FPR_i) ~ N₂(μ, Σ + S_i), S_i = diag(1/TP + 1/FN, 1/FP + 1/TN); Σ = [[τ₁², ρτ₁τ₂], [ρτ₁τ₂, τ₂²]] estimated by REML; Se = expit(μ₁), Sp = 1 − expit(μ₂), Wald CI on the logit scale; Rutter-Gatsonis SROC (Λ = √(τ₂/τ₁)μ₁ − √(τ₁/τ₂)μ₂, β = log(τ₂/τ₁)).'),
    estimates: [
      Estimate(tr('Sensibilité combinée', 'Pooled sensitivity'), sens, lower: sensLo, upper: sensHi, level: level),
      Estimate(tr('Spécificité combinée', 'Pooled specificity'), 1 - fpr, lower: 1 - fprHi, upper: 1 - fprLo, level: level),
      Estimate(tr('Odds ratio diagnostique', 'Diagnostic odds ratio'), math.exp(logDor), lower: math.exp(logDor - z * seDor), upper: math.exp(logDor + z * seDor), level: level),
      Estimate(tr('RV+ (au point combiné, estimation ponctuelle)', 'LR+ (at the pooled point, point estimate)'), sens / fpr),
      Estimate(tr('RV− (au point combiné, estimation ponctuelle)', 'LR− (at the pooled point, point estimate)'), (1 - sens) / (1 - fpr)),
      Estimate(tr('AUC de la courbe SROC', 'AUC of the SROC curve'), auc),
      Estimate('τ (logit Se)', f.tau1),
      Estimate('τ (logit FPR)', f.tau2),
      Estimate(tr('ρ (corrélation entre études)', 'ρ (between-study correlation)'), f.rho),
    ],
    statistics: {
      'k': k.toDouble(),
      'mu_sens': f.mu1,
      'mu_fpr': f.mu2,
      'se_mu_sens': se1,
      'se_mu_fpr': se2,
      'cov_mu': f.vcov[0][1],
      'tau2_sens': f.tau1 * f.tau1,
      'tau2_fpr': f.tau2 * f.tau2,
      'rho': f.rho,
      'loglik_reml': f.remlLogLik,
      'loglik_mada': f.madaLogLik,
      'auc': auc,
    },
    checks: [
      Check('heterogeneity', tr('Hétérogénéité entre études', 'Between-study heterogeneity'), (f.tau1 > 0.5 || f.tau2 > 0.5) ? CheckStatus.warning : CheckStatus.ok,
          tr('τ = ${fmt(f.tau1)} (logit Se), ${fmt(f.tau2)} (logit FPR) : ${(f.tau1 > 0.5 || f.tau2 > 0.5) ? "variabilité importante ; les valeurs combinées sont des moyennes, la région de prédiction montre la dispersion." : "variabilité modérée."}',
              'τ = ${fmt(f.tau1)} (logit Se), ${fmt(f.tau2)} (logit FPR): ${(f.tau1 > 0.5 || f.tau2 > 0.5) ? "considerable variability; the pooled values are averages, the prediction region shows the spread." : "moderate variability."}')),
      Check('threshold_effect', tr('Effet de seuil', 'Threshold effect'), f.rho > 0.3 ? CheckStatus.warning : CheckStatus.ok,
          tr("ρ = ${fmt(f.rho)} entre logit Se et logit FPR. ${f.rho > 0.3 ? "Corrélation positive : effet de seuil probable (seuils de positivité différents) ; la courbe SROC résume mieux le test qu'un point unique." : ""}",
              'ρ = ${fmt(f.rho)} between logit Se and logit FPR. ${f.rho > 0.3 ? "Positive correlation: threshold effect likely (different positivity thresholds); the SROC curve summarizes the test better than a single point." : ""}')),
      Check('quadas', tr('Risque de biais des études (QUADAS-2)', 'Risk of bias of studies (QUADAS-2)'), CheckStatus.notAssessed, tr('Non évaluable par le calcul.', 'Not assessable by computation.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Études${prep.corrected ? " (après correction 0,5)" : ""}', 'Studies${prep.corrected ? " (after 0.5 correction)" : ""}'), [tr('Étude', 'Study'), tr('VP', 'TP'), 'FP', 'FN', tr('VN', 'TN'), 'Se', 'Sp'], [
        for (var i = 0; i < k; i++)
          [
            used[i].label,
            fmt(counts[i][0]),
            fmt(counts[i][1]),
            fmt(counts[i][2]),
            fmt(counts[i][3]),
            fmtPct(prep.data.sens[i]),
            fmtPct(1 - prep.data.fpr[i]),
          ]
      ]),
      ResultTable(tr('Paramètres du modèle (échelle logit)', 'Model parameters (logit scale)'), [tr('Paramètre', 'Parameter'), tr('Estimation', 'Estimate'), tr('ES', 'SE'), tr('IC $pct %', '$pct% CI')], [
        ['μ logit(Se)', fmt(f.mu1, digits: 4), fmt(se1), '${fmt(f.mu1 - z * se1)} – ${fmt(f.mu1 + z * se1)}'],
        ['μ logit(FPR)', fmt(f.mu2, digits: 4), fmt(se2), '${fmt(f.mu2 - z * se2)} – ${fmt(f.mu2 + z * se2)}'],
        ['τ logit(Se)', fmt(f.tau1), '—', '—'],
        ['τ logit(FPR)', fmt(f.tau2), '—', '—'],
        ['ρ', fmt(f.rho), '—', '—'],
      ]),
      if (excluded.isNotEmpty) ResultTable(tr('Études non incluses', 'Studies not included'), [tr('Étude', 'Study'), tr('Raison', 'Reason')], excluded),
    ],
    figures: {
      'sroc': {
        'studies': [
          for (var i = 0; i < k; i++) {'fpr': prep.data.fpr[i], 'sens': prep.data.sens[i], 'n': counts[i].fold(0.0, (a, b) => a + b)}
        ],
        'summary': {'fpr': fpr, 'sens': sens},
        'curve': [for (var i = 0; i <= 60; i++) () {
          final x = fprMin + (fprMax - fprMin) * i / 60;
          return [x, g(x)];
        }()],
        'confidence': _ellipse(f.mu1, f.mu2, f.vcov[0][0], f.vcov[0][1], f.vcov[1][1], level),
        'prediction': _ellipse(f.mu1, f.mu2, f.vcov[0][0] + f.tau1 * f.tau1, f.vcov[0][1] + f.rho * f.tau1 * f.tau2,
            f.vcov[1][1] + f.tau2 * f.tau2, level),
      },
    },
    interpretation: Interpretation(
      whyThisMethod: tr("Synthèse de la performance d'un test : Se et Sp sont corrélées entre études (seuils, populations) ; le modèle bivarié les combine conjointement en tenant compte de cette corrélation et de l'hétérogénéité.",
          'Synthesis of test performance: Se and Sp are correlated across studies (thresholds, populations); the bivariate model pools them jointly, accounting for this correlation and for heterogeneity.'),
      whatItMeans: tr('Sensibilité combinée ${fmtPct(sens)} (IC ${fmtPct(sensLo)} à ${fmtPct(sensHi)}), spécificité combinée ${fmtPct(1 - fpr)} (IC ${fmtPct(1 - fprHi)} à ${fmtPct(1 - fprLo)}), k = $k. AUC de la SROC = ${fmt(auc)}. La région de prédiction (figure) indique où se situerait le couple (Se, Sp) dans une nouvelle étude.',
          'Pooled sensitivity ${fmtPct(sens)} (CI ${fmtPct(sensLo)} to ${fmtPct(sensHi)}), pooled specificity ${fmtPct(1 - fpr)} (CI ${fmtPct(1 - fprHi)} to ${fmtPct(1 - fprLo)}), k = $k. SROC AUC = ${fmt(auc)}. The prediction region (figure) shows where the (Se, Sp) pair would lie in a new study.'),
      notJustified: tr('Utiliser Se et Sp combinées comme si elles valaient dans tout contexte malgré une hétérogénéité importante ; déduire des VPP/VPN sans préciser la prévalence ; combiner séparément Se et Sp par deux métaanalyses univariées ; ignorer le risque de biais des études.',
          'Using pooled Se and Sp as if valid in every setting despite considerable heterogeneity; deriving PPV/NPV without stating the prevalence; pooling Se and Sp separately with two univariate meta-analyses; ignoring the risk of bias of studies.'),
    ),
  );
}

/// Log-vraisemblance REML (avec terme jacobien de mada) en un point (τ₁, τ₂, ρ).
double bivariateLogLik(List<List<double>> counts, double tau1, double tau2, double rho) {
  final d = _prepare(counts).data;
  var jac = 0.0;
  for (var i = 0; i < d.sens.length; i++) {
    jac += math.log(1 / (d.sens[i] * (1 - d.sens[i]))) + math.log(1 / (d.fpr[i] * (1 - d.fpr[i])));
  }
  return _reml(d, tau1, tau2, rho).ll + jac;
}
