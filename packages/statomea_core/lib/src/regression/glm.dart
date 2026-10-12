/// Modèles linéaires généralisés pour issue binaire :
///  - régression logistique (maximum de vraisemblance, IRLS, comme `glm`) ;
///  - régression de Poisson à variance robuste (Zou 2004), sandwich HC0 ;
///  - régression logistique pénalisée de Firth (1993), comme `logistf`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';
import 'firth_profile.dart';

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

double _expit(double e) => e >= 0 ? 1 / (1 + math.exp(-e)) : math.exp(e) / (1 + math.exp(e));

class GlmFit {
  final List<double> beta;
  final Matrix cov; // covariance (modèle, ou robuste pour Poisson)
  final List<double> mu;
  final double deviance, nullDeviance, logLik;
  final int iterations;
  final bool converged;
  final List<String> trace;
  GlmFit(this.beta, this.cov, this.mu, this.deviance, this.nullDeviance, this.logLik, this.iterations,
      this.converged, this.trace);
}

double _binDev(List<double> y, List<double> mu) {
  var d = 0.0;
  for (var i = 0; i < y.length; i++) {
    final m = mu[i].clamp(1e-300, 1 - 1e-16);
    d += y[i] == 1 ? -2 * math.log(m) : -2 * math.log(1 - m);
  }
  return d;
}

/// IRLS logistique (critère de `glm.fit` : |Δdev|/(|dev|+0,1) < tol ; tol =
/// 1e-12 ici, plus strict que le 1e-8 de R, pour des ES calculés au point de
/// convergence et non à l'itération précédente).
GlmFit fitLogistic(List<List<double>> x, List<double> y, {int maxIter = 50, List<double>? weights, double tol = 1e-12, bool keepTrace = true}) {
  // [keepTrace] = false : pas de journal des itérations (balayages de milliers de variants). Vecteurs de travail en
  // Float64List (doubles non boxés) ; arithmétique inchangée.
  final n = x.length, p = x.first.length;
  final w0 = weights ?? List<double>.filled(n, 1);
  // x aplati par lignes (accès non polymorphes) : mêmes valeurs, mêmes sommes dans le même ordre.
  final xs = Float64List(n * p);
  for (var i = 0; i < n; i++) {
    final xi = x[i];
    for (var j = 0; j < p; j++) {
      xs[i * p + j] = xi[j];
    }
  }
  var mu = Float64List(n), eta = Float64List(n);
  for (var i = 0; i < n; i++) {
    mu[i] = (y[i] + 0.5) / 2;
    eta[i] = math.log(mu[i] / (1 - mu[i]));
  }
  var beta = List<double>.filled(p, 0);
  var devOld = double.infinity;
  var converged = false;
  var it = 0;
  final trace = <String>[];
  Matrix? info;
  final w = Float64List(n), z = Float64List(n);
  for (it = 1; it <= maxIter; it++) {
    for (var i = 0; i < n; i++) {
      w[i] = w0[i] * mu[i] * (1 - mu[i]);
      z[i] = eta[i] + (y[i] - mu[i]) / (mu[i] * (1 - mu[i]));
    }
    info = _crossprodFlat(xs, n, p, w);
    final rhs = Float64List(p);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < p; j++) {
        rhs[j] += xs[i * p + j] * w[i] * z[i];
      }
    }
    final b = solveSpd(info, rhs);
    if (b == null) {
      trace.add(tr("Itération $it : matrice d'information singulière.", 'Iteration $it: singular information matrix.'));
      break;
    }
    beta = b;
    for (var i = 0; i < n; i++) {
      var e = 0.0;
      for (var j = 0; j < p; j++) {
        e += xs[i * p + j] * beta[j];
      }
      eta[i] = e;
      // Borne explicite (même valeur que clamp, sans passer par num).
      final m = _expit(eta[i]);
      mu[i] = m < 2.220446e-16 ? 2.220446e-16 : (m > 1 - 2.220446e-16 ? 1 - 2.220446e-16 : m);
    }
    var dev = 0.0;
    for (var i = 0; i < n; i++) {
      dev += w0[i] * (y[i] == 1 ? -2 * math.log(mu[i]) : -2 * math.log(1 - mu[i]));
    }
    if (keepTrace) trace.add(tr('Itération $it : déviance = ${dev.toStringAsFixed(8)}', 'Iteration $it: deviance = ${dev.toStringAsFixed(8)}'));
    if ((dev - devOld).abs() / (dev.abs() + 0.1) < tol) {
      converged = true;
      devOld = dev;
      break;
    }
    devOld = dev;
  }
  final wF = Float64List(n);
  for (var i = 0; i < n; i++) {
    wF[i] = w0[i] * mu[i] * (1 - mu[i]);
  }
  final cov = invertSpd(_crossprodFlat(xs, n, p, wF)) ?? Matrix(p, p);
  final ybar = y.fold(0.0, (a, b) => a + b) / n;
  final nullDev = _binDev(y, List<double>.filled(n, ybar));
  return GlmFit(beta, cov, mu, devOld, nullDev, -devOld / 2, math.min(it, maxIter), converged, trace);
}

/// Même calcul que [crossprodWeighted] (mêmes sauts des zéros, même ordre) sur une matrice aplatie.
Matrix _crossprodFlat(Float64List xs, int n, int p, Float64List w) {
  final m = Matrix(p, p);
  final md = m.data as Float64List;
  for (var i = 0; i < n; i++) {
    final wi = w[i];
    if (wi == 0) continue;
    final o = i * p;
    for (var a = 0; a < p; a++) {
      final xa = xs[o + a] * wi;
      if (xa == 0) continue;
      for (var b = a; b < p; b++) {
        md[a * p + b] += xa * xs[o + b];
      }
    }
  }
  for (var a = 0; a < p; a++) {
    for (var b = 0; b < a; b++) {
      md[a * p + b] = md[b * p + a];
    }
  }
  return m;
}

/// Poisson log-linéaire avec variance sandwich HC0 (pour estimer un RR/RP
/// sur une issue binaire).
GlmFit fitPoissonRobust(List<List<double>> x, List<double> y, {int maxIter = 50}) {
  final n = x.length, p = x.first.length;
  var mu = [for (final v in y) v + 0.1];
  var eta = [for (final m in mu) math.log(m)];
  var beta = List<double>.filled(p, 0);
  var devOld = double.infinity;
  var converged = false;
  var it = 0;
  final trace = <String>[];
  for (it = 1; it <= maxIter; it++) {
    final z = [for (var i = 0; i < n; i++) eta[i] + (y[i] - mu[i]) / mu[i]];
    final info = crossprodWeighted(x, mu);
    final rhs = List<double>.filled(p, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < p; j++) {
        rhs[j] += x[i][j] * mu[i] * z[i];
      }
    }
    final b = solveSpd(info, rhs);
    if (b == null) break;
    beta = b;
    eta = [for (final row in x) _dot(row, beta)];
    mu = [for (final e in eta) math.exp(e)];
    var dev = 0.0;
    for (var i = 0; i < n; i++) {
      dev += 2 * ((y[i] > 0 ? y[i] * math.log(y[i] / mu[i]) : 0) - (y[i] - mu[i]));
    }
    trace.add(tr('Itération $it : déviance = ${dev.toStringAsFixed(8)}', 'Iteration $it: deviance = ${dev.toStringAsFixed(8)}'));
    if ((dev - devOld).abs() / (dev.abs() + 0.1) < 1e-10) {
      converged = true;
      devOld = dev;
      break;
    }
    devOld = dev;
  }
  final bread = invertSpd(crossprodWeighted(x, mu)) ?? Matrix(p, p);
  final meat = crossprodWeighted(x, [for (var i = 0; i < n; i++) math.pow(y[i] - mu[i], 2).toDouble()]);
  final cov = bread * meat * bread;
  return GlmFit(beta, cov, mu, devOld, double.nan, double.nan, math.min(it, maxIter), converged, trace);
}

/// Régression logistique de Firth : score modifié U* = Xᵀ(y − π + h(½ − π)),
/// Newton-Raphson avec pas maximal 5 et demi-pas si la log-vraisemblance
/// pénalisée diminue (schéma de `logistf`).
GlmFit fitFirth(List<List<double>> x, List<double> y, {int maxIter = 100, double xconv = 1e-10, double gconv = 1e-10}) {
  final n = x.length, p = x.first.length;
  var beta = List<double>.filled(p, 0);
  final trace = <String>[];

  ({double pl, List<double> pi, Matrix? cov, List<double> h}) eval(List<double> b) {
    final pi = [for (final row in x) _expit(_dot(row, b))];
    final w = [for (final v in pi) v * (1 - v)];
    final info = crossprodWeighted(x, w);
    final cov = invertSpd(info);
    final ld = logDetSpd(info);
    var ll = 0.0;
    for (var i = 0; i < n; i++) {
      ll += y[i] == 1 ? math.log(math.max(pi[i], 1e-300)) : math.log(math.max(1 - pi[i], 1e-300));
    }
    final h = <double>[];
    if (cov != null) {
      for (var i = 0; i < n; i++) {
        h.add(w[i] * _dot(x[i], cov.multiplyVector(x[i])));
      }
    }
    return (pl: ll + 0.5 * (ld ?? double.negativeInfinity), pi: pi, cov: cov, h: h);
  }

  var cur = eval(beta);
  var converged = false;
  var it = 0;
  for (it = 1; it <= maxIter; it++) {
    if (cur.cov == null) break;
    final u = List<double>.filled(p, 0);
    for (var i = 0; i < n; i++) {
      final r = y[i] - cur.pi[i] + cur.h[i] * (0.5 - cur.pi[i]);
      for (var j = 0; j < p; j++) {
        u[j] += x[i][j] * r;
      }
    }
    var delta = cur.cov!.multiplyVector(u);
    final mx = delta.map((d) => d.abs()).reduce(math.max);
    if (mx > 5) delta = [for (final d in delta) d * 5 / mx];
    var next = [for (var j = 0; j < p; j++) beta[j] + delta[j]];
    var ev = eval(next);
    var halvings = 0;
    // Demi-pas seulement si la vraisemblance pénalisée baisse au-delà du
    // bruit d'arrondi (sinon, près de l'optimum, les pas seraient annulés).
    while ((ev.pl < cur.pl - 1e-10 * (1 + cur.pl.abs()) || ev.cov == null) && halvings < 25) {
      delta = [for (final d in delta) d / 2];
      next = [for (var j = 0; j < p; j++) beta[j] + delta[j]];
      ev = eval(next);
      halvings++;
    }
    beta = next;
    cur = ev;
    final gmax = u.map((v) => v.abs()).reduce(math.max);
    final dmax = delta.map((v) => v.abs()).reduce(math.max);
    trace.add(tr('Itération $it : log-vraisemblance pénalisée = ${cur.pl.toStringAsFixed(8)}, |Δβ|max = ${dmax.toStringAsExponential(2)}${halvings > 0 ? ", $halvings demi-pas" : ""}',
        'Iteration $it: penalized log-likelihood = ${cur.pl.toStringAsFixed(8)}, |Δβ|max = ${dmax.toStringAsExponential(2)}${halvings > 0 ? ", $halvings step-halving(s)" : ""}'));
    if (dmax <= xconv && gmax <= gconv) {
      converged = true;
      break;
    }
    if (dmax <= xconv * 1e-3) {
      converged = true;
      break;
    }
  }
  // Variance : inverse de l'information « augmentée » Xᵀ diag(w(1+h)) X,
  // convention de logistf ≥ 1.24 (représentation par pseudo-observations).
  // L'inverse de l'information de Fisher XᵀWX (Heinze & Schemper 2002) donne
  // des ES un peu plus grands ; les deux sont asymptotiquement équivalents.
  Matrix? cov;
  if (cur.cov != null) {
    final wa = [for (var i = 0; i < n; i++) cur.pi[i] * (1 - cur.pi[i]) * (1 + cur.h[i])];
    cov = invertSpd(crossprodWeighted(x, wa));
  }
  final ybar = y.fold(0.0, (a, b) => a + b) / n;
  return GlmFit(beta, cov ?? Matrix(p, p), cur.pi, _binDev(y, cur.pi), _binDev(y, List.filled(n, ybar)),
      cur.pl, math.min(it, maxIter), converged, trace);
}

/// Indicatrices dont une modalité ne contient que des événements ou que des
/// non-événements (séparation quasi complète « visible »).
List<String> _zeroCellColumns(DesignMatrix d) {
  final out = <String>[];
  for (var j = 1; j < d.p; j++) {
    final col = [for (final r in d.x) r[j]];
    if (col.toSet().length != 2 || !col.every((v) => v == 0 || v == 1)) continue;
    var e1 = 0, n1 = 0;
    for (var i = 0; i < d.n; i++) {
      if (col[i] == 1) {
        n1++;
        if (d.y[i] == 1) e1++;
      }
    }
    if (n1 > 0 && (e1 == 0 || e1 == n1)) out.add(d.columns[j]);
  }
  return out;
}

/// Diagnostic de séparation après un ajustement par maximum de vraisemblance.
({bool suspected, String detail}) separationDiagnostic(DesignMatrix d, GlmFit fit) {
  final extreme = fit.mu.where((m) => m < 1e-8 || m > 1 - 1e-8).length;
  final big = <String>[];
  for (var j = 1; j < d.p; j++) {
    final se = math.sqrt(fit.cov.get(j, j));
    if (fit.beta[j].abs() > 10 || se > 1e3 || se.isNaN) big.add(d.columns[j]);
  }
  final zc = _zeroCellColumns(d);
  final suspected = (extreme > 0 && big.isNotEmpty) || zc.isNotEmpty || (!fit.converged && big.isNotEmpty);
  final parts = <String>[
    if (extreme > 0) tr('$extreme probabilité(s) ajustée(s) numériquement égale(s) à 0 ou 1', '$extreme fitted probability(ies) numerically equal to 0 or 1'),
    if (big.isNotEmpty) tr('coefficient(s) ou ES démesuré(s) : ${big.join(", ")}', 'excessive coefficient(s) or SE(s): ${big.join(", ")}'),
    if (zc.isNotEmpty) tr('modalité(s) sans événement ou sans non-événement : ${zc.join(", ")}', 'level(s) with no event or no non-event: ${zc.join(", ")}'),
    if (!fit.converged) tr('absence de convergence', 'no convergence'),
  ];
  return (suspected: suspected, detail: parts.isEmpty ? tr('Aucun signe de séparation.', 'No sign of separation.') : parts.join(tr(' ; ', '; ')));
}

List<Coefficient> _waldCoefs(DesignMatrix d, GlmFit fit, double level) {
  final z = normalQuantile(1 - (1 - level) / 2);
  return [
    for (var j = 0; j < d.p; j++)
      () {
        final se = math.sqrt(fit.cov.get(j, j));
        final st = fit.beta[j] / se;
        return Coefficient(d.columns[j], fit.beta[j], se, st, normalTwoSidedP(st), fit.beta[j] - z * se, fit.beta[j] + z * se);
      }()
  ];
}

({int events, int nonEvents}) _events(DesignMatrix d) {
  final e = d.y.where((v) => v == 1).length;
  return (events: e, nonEvents: d.n - e);
}

/// Régression logistique binaire par maximum de vraisemblance.
AnalysisResult logisticRegression(DesignMatrix d, {double level = 0.95, StudyDesign design = StudyDesign.unknown}) {
  final fit = fitLogistic(d.x, d.y);
  final coefs = _waldCoefs(d, fit, level);
  final ev = _events(d);
  final alerts = <Alert>[...d.alerts];
  final checks = <Check>[];
  final sep = separationDiagnostic(d, fit);
  checks.add(Check('convergence', tr("Convergence de l'algorithme (IRLS)", 'Algorithm convergence (IRLS)'),
      fit.converged ? CheckStatus.ok : CheckStatus.violated,
      tr('${fit.iterations} itération(s) ; ${fit.converged ? "convergé" : "NON convergé"}.', '${fit.iterations} iteration(s); ${fit.converged ? "converged" : "NOT converged"}.')));
  checks.add(Check('separation', tr('Absence de séparation (complète ou quasi complète)', 'No (complete or quasi-complete) separation'),
      sep.suspected ? CheckStatus.violated : CheckStatus.ok, sep.detail));
  if (sep.suspected || !fit.converged) {
    alerts.add(Alert('separation', Severity.critical,
        tr('Séparation suspectée ou non-convergence : les estimations du maximum de vraisemblance des termes concernés sont infinies ou arbitraires et ne doivent pas être rapportées.',
            'Suspected separation or non-convergence: the maximum likelihood estimates of the terms involved are infinite or arbitrary and must not be reported.'),
        suggestion: tr('Utiliser la régression pénalisée de Firth, regrouper des modalités justifiées a priori, ou présenter des données descriptives.',
            "Use Firth's penalized regression, merge levels justified a priori, or present descriptive data.")));
  }
  final params = d.p - 1;
  alerts.addAll(smallEventsAlerts(events: ev.events, nonEvents: ev.nonEvents, parameters: params));
  final g = gvif(d);
  checks.add(collinearityCheck(g));
  final lr = fit.nullDeviance - fit.deviance;
  final lrP = params > 0 ? chiSquareUpper(lr, params.toDouble()) : double.nan;
  final prev = ev.events / d.n;
  if (designAllowsRisk(design) && prev > 0.1) {
    alerts.add(Alert('or_not_rr', Severity.caution,
        tr("Issue fréquente (${fmtPct(prev)}) : les OR ajustés surestiment l'ampleur des RR. Ne pas les rédiger comme des « risques multipliés par ».",
            'Common outcome (${fmtPct(prev)}): adjusted ORs overstate the size of RRs. Do not write them up as "risk multiplied by".'),
        suggestion: tr('Pour un RR ou RP ajusté, utiliser la régression de Poisson à variance robuste.', 'For an adjusted RR or PR, use Poisson regression with robust variance.')));
  }
  // Linéarité sur l'échelle logit : terme quadratique pour chaque prédicteur continu.
  final linNotes = <String>[];
  var nonLin = false;
  for (var j = 1; j < d.p; j++) {
    final col = [for (final r in d.x) r[j]];
    if (col.toSet().length <= 2) continue;
    final mu = col.fold(0.0, (a, b) => a + b) / d.n;
    final xq = [for (var i = 0; i < d.n; i++) [...d.x[i], math.pow(col[i] - mu, 2).toDouble()]];
    final fq = fitLogistic(xq, d.y);
    final se = math.sqrt(fq.cov.get(d.p, d.p));
    final pq = normalTwoSidedP(fq.beta.last / se);
    if (pq < 0.05) nonLin = true;
    linNotes.add(tr('${d.columns[j]} : terme quadratique ${fmtP(pq)}', '${d.columns[j]}: quadratic term ${fmtP(pq)}'));
  }
  checks.add(Check('linearity_logit', tr("Linéarité sur l'échelle logit (prédicteurs continus)", 'Linearity on the logit scale (continuous predictors)'),
      linNotes.isEmpty ? CheckStatus.notAssessed : (nonLin ? CheckStatus.warning : CheckStatus.ok),
      linNotes.isEmpty ? tr('Aucun prédicteur continu.', 'No continuous predictor.') : linNotes.join(tr(' ; ', '; '))));
  // Observations influentes : distance de Cook approchée (Pregibon).
  final h = [for (var i = 0; i < d.n; i++) fit.mu[i] * (1 - fit.mu[i]) * _dot(d.x[i], fit.cov.multiplyVector(d.x[i]))];
  final cook = [
    for (var i = 0; i < d.n; i++)
      () {
        final pr = (d.y[i] - fit.mu[i]) / math.sqrt(fit.mu[i] * (1 - fit.mu[i]));
        return pr * pr * h[i] / (d.p * math.pow(1 - h[i], 2));
      }()
  ];
  final maxCook = cook.reduce(math.max);
  checks.add(Check('influence', tr("Pas d'observation exagérément influente", 'No unduly influential observation'),
      maxCook > 1 ? CheckStatus.violated : (maxCook > 4 / d.n * 5 ? CheckStatus.warning : CheckStatus.ok),
      tr('Distance de Cook maximale ≈ ${fmt(maxCook)} (ligne ${d.rows[cook.indexOf(maxCook)] + 1}).', "Maximum Cook's distance ≈ ${fmt(maxCook)} (row ${d.rows[cook.indexOf(maxCook)] + 1}).")));
  final reliable = fit.converged && !sep.suspected;
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  return AnalysisResult(
    methodId: 'logistic_regression',
    methodName: tr('Régression logistique binaire', 'Binary logistic regression'),
    inputs: {'model': d.describe(), 'level': level, 'design': design.name},
    formula: tr('logit P(Y=1|X) = Xβ ; estimation par maximum de vraisemblance (IRLS) ; OR = exp(β) ; IC de Wald = exp(β ± z·ES) ; test global du rapport de vraisemblance.',
        'logit P(Y=1|X) = Xβ; maximum likelihood estimation (IRLS); OR = exp(β); Wald CI = exp(β ± z·SE); global likelihood ratio test.'),
    estimates: [
      for (final c in coefs.skip(1))
        Estimate('OR — ${c.name}', math.exp(c.estimate),
            lower: math.exp(c.lower), upper: math.exp(c.upper), level: level, pValue: c.p, se: c.se),
    ],
    statistics: {
      'n': d.n.toDouble(),
      'events': ev.events.toDouble(),
      'epv': math.min(ev.events, ev.nonEvents) / math.max(1, params),
      'deviance': fit.deviance,
      'null_deviance': fit.nullDeviance,
      'aic': fit.deviance + 2 * d.p,
      'lr_chi2': lr,
      'lr_p': lrP,
      'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < d.p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < d.p; j++) 'se_${d.columns[j]}': coefs[j].se,
    },
    checks: checks,
    alerts: alerts,
    tables: [
      coefficientTable(coefs, effectLabel: 'OR', exponentiate: true, level: level),
      ResultTable(tr('Codage et observations', 'Coding and observations'), [tr('Élément', 'Item'), tr('Détail', 'Detail')], [
        [tr('Modèle', 'Model'), d.formula],
        [tr('Observations / événements', 'Observations / events'), '${d.n} / ${ev.events}'],
        [tr('Exclues (manquants)', 'Excluded (missing)'), d.excludedBy.isEmpty ? '0' : d.excludedBy.entries.map((e) => tr('${e.key} : ${e.value}', '${e.key}: ${e.value}')).join(tr(' ; ', '; '))],
        for (final c in d.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    log: fit.trace,
    figures: {'fitted': fit.mu},
    interpretation: Interpretation(
      whyThisMethod: tr("Issue binaire ; on modélise le logit de la probabilité de l'événement. L'OR est la mesure naturelle de ce modèle et la seule estimable en cas-témoins.",
          'Binary outcome; the logit of the event probability is modelled. The OR is the natural measure of this model and the only one estimable in a case-control study.'),
      whatItMeans: !reliable
          ? tr('Les estimations ne sont pas fiables (séparation ou non-convergence) : voir les alertes.', 'The estimates are not reliable (separation or non-convergence): see the alerts.')
          : coefs.length > 1
              ? tr("À autres variables fixées, « ${main.name} » est associé à un OR de ${fmt(math.exp(main.estimate))} (IC ${fmt(math.exp(main.lower))} à ${fmt(math.exp(main.upper))}). L'OR multiplie la cote (odds), pas le risque.",
                  'Holding the other variables fixed, "${main.name}" is associated with an OR of ${fmt(math.exp(main.estimate))} (CI ${fmt(math.exp(main.lower))} to ${fmt(math.exp(main.upper))}). The OR multiplies the odds, not the risk.')
              : tr('Modèle sans prédicteur.', 'Model without predictors.'),
      notJustified: tr("Présenter l'OR comme un risque relatif quand l'issue est fréquente ; donner une interprétation causale à un OR ajusté ; interpréter les OR de covariables d'ajustement comme des effets (« sophisme de la table 2 »).",
          'Presenting the OR as a risk ratio when the outcome is common; giving a causal interpretation to an adjusted OR; interpreting the ORs of adjustment covariates as effects ("Table 2 fallacy").'),
    ),
  );
}

/// Régression de Poisson à variance robuste : RR (ou RP) ajusté.
AnalysisResult poissonRobustRegression(DesignMatrix d, {double level = 0.95, StudyDesign design = StudyDesign.unknown}) {
  if (design == StudyDesign.caseControl) {
    throw StatInputError('poisson_case_control',
        tr("Plan cas-témoins : les risques ne sont pas estimables, la régression de Poisson pour RR n'est pas appropriée. Utiliser la régression logistique (OR).",
            'Case-control design: risks are not estimable, Poisson regression for RR is not appropriate. Use logistic regression (OR).'));
  }
  if (!d.y.every((v) => v == 0 || v == 1)) {
    throw StatInputError('poisson_binary', tr('Cette méthode est proposée ici pour une issue binaire (0/1).', 'This method is offered here for a binary (0/1) outcome.'));
  }
  final fit = fitPoissonRobust(d.x, d.y);
  final coefs = _waldCoefs(d, fit, level);
  final ev = _events(d);
  final alerts = <Alert>[...d.alerts];
  final over1 = fit.mu.where((m) => m > 1).length;
  if (over1 > 0) {
    alerts.add(Alert('mu_over_one', Severity.caution,
        tr("$over1 probabilité(s) prédite(s) > 1 : sans conséquence pour l'estimation du RR, mais le modèle ne doit pas servir à prédire des risques individuels.",
            '$over1 predicted probability(ies) > 1: no consequence for estimating the RR, but the model must not be used to predict individual risks.')));
  }
  if (design == StudyDesign.unknown) {
    alerts.add(Alert('design_unknown', Severity.caution,
        tr("Plan non précisé : un RR n'est interprétable qu'en cohorte, essai ou transversal (RP).", 'Design not specified: an RR is interpretable only in a cohort, trial or cross-sectional study (PR).')));
  }
  alerts.addAll(smallEventsAlerts(events: ev.events, nonEvents: ev.nonEvents, parameters: d.p - 1));
  final prevalence = design == StudyDesign.crossSectional;
  final name = prevalence ? tr('RP', 'PR') : 'RR';
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  return AnalysisResult(
    methodId: 'poisson_robust',
    methodName: tr('Régression de Poisson à variance robuste (RR/RP ajusté)', 'Poisson regression with robust variance (adjusted RR/PR)'),
    inputs: {'model': d.describe(), 'level': level, 'design': design.name},
    formula: tr('log E(Y|X) = Xβ (Poisson, IRLS) ; variance sandwich HC0 : (XᵀWX)⁻¹ [Σ (y−μ)² xxᵀ] (XᵀWX)⁻¹ ; $name = exp(β).',
        'log E(Y|X) = Xβ (Poisson, IRLS); HC0 sandwich variance: (XᵀWX)⁻¹ [Σ (y−μ)² xxᵀ] (XᵀWX)⁻¹; $name = exp(β).'),
    estimates: [
      for (final c in coefs.skip(1))
        Estimate('$name — ${c.name}', math.exp(c.estimate),
            lower: math.exp(c.lower), upper: math.exp(c.upper), level: level, pValue: c.p, se: c.se),
    ],
    statistics: {
      'n': d.n.toDouble(),
      'events': ev.events.toDouble(),
      'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < d.p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < d.p; j++) 'se_${d.columns[j]}': coefs[j].se,
    },
    checks: [
      Check('convergence', 'Convergence', fit.converged ? CheckStatus.ok : CheckStatus.violated,
          tr('${fit.iterations} itération(s).', '${fit.iterations} iteration(s).')),
      collinearityCheck(gvif(d)),
    ],
    alerts: alerts,
    tables: [coefficientTable(coefs, effectLabel: name, exponentiate: true, level: level)],
    log: fit.trace,
    interpretation: Interpretation(
      whyThisMethod: tr("Issue binaire fréquente en cohorte, essai ou transversal : on souhaite un ${prevalence ? "rapport de prévalences" : "risque relatif"} ajusté, plus lisible que l'OR ; la variance robuste corrige la mauvaise spécification de la loi de Poisson.",
          'Common binary outcome in a cohort, trial or cross-sectional study: an adjusted ${prevalence ? "prevalence ratio" : "risk ratio"} is wanted, easier to read than the OR; the robust variance corrects the misspecification of the Poisson distribution.'),
      whatItMeans: coefs.length > 1
          ? tr('« ${main.name} » : $name ajusté = ${fmt(math.exp(main.estimate))} (IC ${fmt(math.exp(main.lower))} à ${fmt(math.exp(main.upper))}).',
              '"${main.name}": adjusted $name = ${fmt(math.exp(main.estimate))} (CI ${fmt(math.exp(main.lower))} to ${fmt(math.exp(main.upper))}).')
          : tr('Modèle sans prédicteur.', 'Model without predictors.'),
      notJustified: tr('Utiliser ce modèle en cas-témoins ; interpréter le RR ajusté comme causal ; utiliser les probabilités prédites (parfois > 1).',
          'Using this model in a case-control study; interpreting the adjusted RR as causal; using the predicted probabilities (sometimes > 1).'),
    ),
  );
}

/// Régression logistique pénalisée de Firth. Les IC sont de Wald ; les IC par
/// vraisemblance profilée pénalisée (défaut de `logistf`) sont en développement.
AnalysisResult firthRegression(DesignMatrix d, {double level = 0.95}) {
  final fit = fitFirth(d.x, d.y);
  final coefs = _waldCoefs(d, fit, level);
  final ev = _events(d);
  final ml = fitLogistic(d.x, d.y);
  final sep = separationDiagnostic(d, ml);
  final plHat = firthEval(d.x, d.y, fit.beta)?.pl ?? fit.logLik;
  final profiles = [for (var j = 0; j < d.p; j++) firthProfile(d.x, d.y, fit.beta, plHat, j, coefs[j].se, level: level)];
  final unbounded = [for (var j = 1; j < d.p; j++) if (!profiles[j].lowerFound || !profiles[j].upperFound) d.columns[j]];
  return AnalysisResult(
    methodId: 'firth_logistic',
    methodName: tr('Régression logistique pénalisée de Firth', "Firth's penalized logistic regression"),
    inputs: {'model': d.describe(), 'level': level},
    formula: tr('Maximisation de l*(β) = l(β) + ½ log|I(β)| (pénalité de Jeffreys) ; score modifié U*(β) = Xᵀ[y − π + h(½ − π)], h = diag(W½X(XᵀWX)⁻¹XᵀW½). IC par vraisemblance profilée pénalisée : {b : 2[l*(β̂) − max l*(β | β_j = b)] ≤ χ²₁(1−α)} ; p par rapport de vraisemblance pénalisé.',
        'Maximization of l*(β) = l(β) + ½ log|I(β)| (Jeffreys penalty); modified score U*(β) = Xᵀ[y − π + h(½ − π)], h = diag(W½X(XᵀWX)⁻¹XᵀW½). Penalized profile likelihood CI: {b: 2[l*(β̂) − max l*(β | β_j = b)] ≤ χ²₁(1−α)}; p from the penalized likelihood ratio.'),
    estimates: [
      for (var j = 1; j < d.p; j++)
        Estimate('OR — ${d.columns[j]}', math.exp(fit.beta[j]),
            lower: math.exp(profiles[j].lower),
            upper: math.exp(profiles[j].upper),
            level: level,
            pValue: profiles[j].pValue,
            se: coefs[j].se),
    ],
    statistics: {
      'n': d.n.toDouble(),
      'events': ev.events.toDouble(),
      'penalized_loglik': fit.logLik,
      'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < d.p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < d.p; j++) 'se_${d.columns[j]}': coefs[j].se,
      for (var j = 0; j < d.p; j++) 'pl_lower_${d.columns[j]}': profiles[j].lower,
      for (var j = 0; j < d.p; j++) 'pl_upper_${d.columns[j]}': profiles[j].upper,
      for (var j = 0; j < d.p; j++) 'pl_p_${d.columns[j]}': profiles[j].pValue,
      for (var j = 0; j < d.p; j++) 'pl_chi2_${d.columns[j]}': profiles[j].chi2,
    },
    checks: [
      Check('convergence', tr('Convergence (Newton-Raphson pénalisé)', 'Convergence (penalized Newton-Raphson)'), fit.converged ? CheckStatus.ok : CheckStatus.violated,
          tr('${fit.iterations} itération(s).', '${fit.iterations} iteration(s).')),
      Check('separation_ml', tr('Séparation dans le modèle non pénalisé', 'Separation in the unpenalized model'), sep.suspected ? CheckStatus.warning : CheckStatus.ok,
          '${sep.detail}${sep.suspected ? tr(" — Firth fournit des estimations finies malgré la séparation.", " — Firth gives finite estimates despite separation.") : ""}'),
      Check('profile_bounds', tr('Bornes des IC profilés trouvées', 'Profile CI bounds found'), unbounded.isEmpty ? CheckStatus.ok : CheckStatus.warning,
          unbounded.isEmpty ? tr('Toutes les bornes ont été atteintes.', 'All bounds were reached.') : tr('Borne non atteinte (IC ouvert) pour : ${unbounded.join(", ")}.', 'Bound not reached (open CI) for: ${unbounded.join(", ")}.')),
    ],
    alerts: [
      ...d.alerts,
      ...smallEventsAlerts(events: ev.events, nonEvents: ev.nonEvents, parameters: d.p - 1),
      Alert('firth_profile', Severity.info,
          tr("IC par vraisemblance profilée pénalisée et p du rapport de vraisemblance pénalisé (recommandés pour Firth). Les IC de Wald figurent dans le tableau des coefficients pour comparaison ; avec peu d'événements ils peuvent être trop étroits ou mal centrés.",
              'CIs by penalized profile likelihood and p from the penalized likelihood ratio (recommended for Firth). Wald CIs appear in the coefficient table for comparison; with few events they can be too narrow or off-centre.')),
    ],
    tables: [
      ResultTable(tr('OR pénalisés et IC profilés', 'Penalized ORs and profile CIs'), [tr('Terme', 'Term'), 'OR', tr('IC profilé ${(level * 100).round()} %', '${(level * 100).round()}% profile CI'), tr('χ² (RV pénalisé)', 'χ² (penalized LR)'), 'p'], [
        for (var j = 1; j < d.p; j++)
          [
            d.columns[j],
            fmt(math.exp(fit.beta[j])),
            '${fmt(math.exp(profiles[j].lower))} – ${fmt(math.exp(profiles[j].upper))}',
            fmt(profiles[j].chi2),
            fmtP(profiles[j].pValue),
          ]
      ]),
      coefficientTable(coefs, effectLabel: 'OR (Wald)', exponentiate: true, level: level),
    ],
    log: fit.trace,

    interpretation: Interpretation(
      whyThisMethod: tr("Issue binaire avec peu d'événements ou séparation : la pénalité de Firth réduit le biais de petit échantillon et donne des estimations finies.",
          "Binary outcome with few events or separation: Firth's penalty reduces small-sample bias and gives finite estimates."),
      whatItMeans: (d.p > 1
              ? tr('« ${d.columns[1]} » : OR pénalisé = ${fmt(math.exp(fit.beta[1]))} (IC profilé ${fmt(math.exp(profiles[1].lower))} à ${fmt(math.exp(profiles[1].upper))}), ${fmtP(profiles[1].pValue)}. ',
                  '"${d.columns[1]}": penalized OR = ${fmt(math.exp(fit.beta[1]))} (profile CI ${fmt(math.exp(profiles[1].lower))} to ${fmt(math.exp(profiles[1].upper))}), ${fmtP(profiles[1].pValue)}. ')
              : '') +
          smallEventsLesson,
      notJustified: tr("Croire que Firth « corrige » le manque d'événements : l'incertitude reste grande ; interpréter les OR comme des RR ou comme causaux.",
          'Believing that Firth "corrects" the lack of events: uncertainty remains large; interpreting the ORs as RRs or as causal.'),
    ),
  );
}
