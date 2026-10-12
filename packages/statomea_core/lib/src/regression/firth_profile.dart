/// Intervalles de confiance par vraisemblance profilée pénalisée et test du
/// rapport de vraisemblance pénalisé pour la régression de Firth (Heinze &
/// Schemper 2002), comme `logistf(pl = TRUE)`.
///
/// Pour le coefficient j, la borne b vérifie
///   2 [ l*(β̂) − max_{β : β_j = b} l*(β) ] = χ²₁(1 − α),
/// où l* est la log-vraisemblance pénalisée l(β) + ½ log|I(β)|. Le score
/// modifié de Firth étant le gradient exact de l*, le maximum contraint est
/// obtenu par Newton-Raphson sur les paramètres libres (score modifié nul).
library;

import 'dart:math' as math;

import '../math/distributions.dart';
import '../math/matrix.dart';
import '../math/special.dart';

double _expit(double e) => e >= 0 ? 1 / (1 + math.exp(-e)) : math.exp(e) / (1 + math.exp(e));

/// Log-vraisemblance pénalisée, score modifié et information en β.
({double pl, List<double> score, Matrix info})? firthEval(List<List<double>> x, List<double> y, List<double> beta) {
  final n = x.length, p = beta.length;
  final pi = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var e = 0.0;
    for (var j = 0; j < p; j++) {
      e += x[i][j] * beta[j];
    }
    pi[i] = _expit(e);
  }
  final w = [for (final v in pi) v * (1 - v)];
  final info = crossprodWeighted(x, w);
  final cov = invertSpd(info);
  final ld = logDetSpd(info);
  if (cov == null || ld == null) return null;
  var ll = 0.0;
  final score = List<double>.filled(p, 0);
  for (var i = 0; i < n; i++) {
    ll += y[i] == 1 ? math.log(math.max(pi[i], 1e-300)) : math.log(math.max(1 - pi[i], 1e-300));
    final cx = cov.multiplyVector(x[i]);
    var h = 0.0;
    for (var j = 0; j < p; j++) {
      h += x[i][j] * cx[j];
    }
    h *= w[i];
    final r = y[i] - pi[i] + h * (0.5 - pi[i]);
    for (var j = 0; j < p; j++) {
      score[j] += x[i][j] * r;
    }
  }
  return (pl: ll + 0.5 * ld, score: score, info: info);
}

/// Maximum de l* avec β_j fixé à [b]. Retourne (l*, β).
({double pl, List<double> beta}) constrainedFirth(List<List<double>> x, List<double> y, int j, double b, List<double> start,
    {int maxIter = 200, double tol = 1e-11}) {
  final p = start.length;
  final free = [for (var k = 0; k < p; k++) if (k != j) k];
  var beta = List<double>.of(start)..[j] = b;
  var cur = firthEval(x, y, beta)!;
  for (var it = 0; it < maxIter; it++) {
    if (free.isEmpty) break;
    final sub = Matrix(free.length, free.length);
    for (var a = 0; a < free.length; a++) {
      for (var c = 0; c < free.length; c++) {
        sub.set(a, c, cur.info.get(free[a], free[c]));
      }
    }
    final g = [for (final k in free) cur.score[k]];
    var step = solveSpd(sub, g);
    if (step == null) break;
    final mx = step.map((v) => v.abs()).reduce(math.max);
    if (mx > 5) step = [for (final v in step) v * 5 / mx];
    var next = List<double>.of(beta);
    for (var a = 0; a < free.length; a++) {
      next[free[a]] += step[a];
    }
    var ev = firthEval(x, y, next);
    var halvings = 0;
    while ((ev == null || ev.pl < cur.pl - 1e-10 * (1 + cur.pl.abs())) && halvings < 30) {
      step = [for (final v in step!) v / 2];
      next = List<double>.of(beta);
      for (var a = 0; a < free.length; a++) {
        next[free[a]] += step[a];
      }
      ev = firthEval(x, y, next);
      halvings++;
    }
    if (ev == null) break;
    beta = next;
    cur = ev;
    final gmax = [for (final k in free) cur.score[k].abs()].reduce(math.max);
    final smax = step!.map((v) => v.abs()).reduce(math.max);
    if (gmax < tol && smax < tol) break;
    if (smax < tol * 1e-2) break;
  }
  return (pl: cur.pl, beta: beta);
}

class FirthProfile {
  final double lower, upper, pValue, chi2;
  final bool lowerFound, upperFound;
  FirthProfile(this.lower, this.upper, this.pValue, this.chi2, this.lowerFound, this.upperFound);
}

/// IC profilé pénalisé et p du test du rapport de vraisemblance pénalisé (H0 : β_j = 0).
FirthProfile firthProfile(List<List<double>> x, List<double> y, List<double> betaHat, double plHat, int j, double se,
    {double level = 0.95}) {
  final q = chiSquareQuantile(level, 1);
  double dev(double b) => 2 * (plHat - constrainedFirth(x, y, j, b, betaHat).pl);
  double f(double b) => dev(b) - q;
  final step = (se.isFinite && se > 0) ? se : 1.0;
  ({double v, bool ok}) side(double dir) {
    var inner = betaHat[j];
    var outer = betaHat[j] + dir * step;
    for (var k = 0; k < 40; k++) {
      if (f(outer) > 0) {
        return (v: brentRoot(f, math.min(inner, outer), math.max(inner, outer), tol: 1e-10), ok: true);
      }
      inner = outer;
      outer = betaHat[j] + dir * step * math.pow(2, k + 1);
      if (outer.abs() > 1e3) break;
    }
    return (v: dir > 0 ? double.infinity : double.negativeInfinity, ok: false);
  }

  final lo = side(-1), hi = side(1);
  final chi = math.max(0.0, dev(0));
  return FirthProfile(lo.v, hi.v, gammaQ(0.5, chi / 2), chi, lo.ok, hi.ok);
}
