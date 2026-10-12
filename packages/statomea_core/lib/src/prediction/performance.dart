/// Mesures de performance d'un modèle de prédiction d'une issue binaire :
/// discrimination (AUC, DeLong), calibration (intercept, pente, courbe),
/// score de Brier, bénéfice net (courbe de décision).
library;

import 'dart:math' as math;

import '../descriptive/descriptive.dart';
import '../inference/proportion.dart';
import '../math/distributions.dart';
import '../regression/glm.dart';

/// AUC par la statistique de Mann-Whitney (rangs moyens), O(n log n).
double aucFast(List<double> score, List<double> y) {
  final r = rankWithTies(score).ranks;
  var n1 = 0, sumR = 0.0;
  for (var i = 0; i < y.length; i++) {
    if (y[i] == 1) {
      n1++;
      sumR += r[i];
    }
  }
  final n0 = y.length - n1;
  return (sumR - n1 * (n1 + 1) / 2) / (n1 * n0);
}

/// Composantes structurelles de DeLong (DeLong, DeLong & Clarke-Pearson 1988).
({double auc, List<double> v10, List<double> v01}) _delongComponents(List<double> score, List<double> y) {
  final cases = [for (var i = 0; i < y.length; i++) if (y[i] == 1) score[i]];
  final controls = [for (var i = 0; i < y.length; i++) if (y[i] != 1) score[i]];
  // Calcul par rangs : V10_i = [R_i(tous) − R_i(cas)] / n0, V01_j = 1 − [R_j(tous) − R_j(témoins)] / n1.
  final n1 = cases.length, n0 = controls.length;
  final all = [...cases, ...controls];
  final rAll = rankWithTies(all).ranks;
  final rCases = rankWithTies(cases).ranks;
  final rCtrl = rankWithTies(controls).ranks;
  final v10 = [for (var i = 0; i < n1; i++) (rAll[i] - rCases[i]) / n0];
  final v01 = [for (var j = 0; j < n0; j++) 1 - (rAll[n1 + j] - rCtrl[j]) / n1];
  final auc = v10.fold(0.0, (a, b) => a + b) / n1;
  return (auc: auc, v10: v10, v01: v01);
}

double _cov(List<double> a, List<double> b) {
  final ma = mean(a), mb = mean(b);
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - ma) * (b[i] - mb);
  }
  return s / (a.length - 1);
}

class AucResult {
  final double auc, se, lower, upper;
  AucResult(this.auc, this.se, this.lower, this.upper);
}

/// AUC avec IC de DeLong (échelle de l'AUC, bornée à [0, 1], comme pROC).
AucResult aucDeLong(List<double> score, List<double> y, {double level = 0.95}) {
  final c = _delongComponents(score, y);
  final v = _cov(c.v10, c.v10) / c.v10.length + _cov(c.v01, c.v01) / c.v01.length;
  final se = math.sqrt(v);
  final z = normalQuantile(1 - (1 - level) / 2);
  return AucResult(c.auc, se, math.max(0, c.auc - z * se), math.min(1, c.auc + z * se));
}

/// Comparaison de deux AUC appariées (même sujets) : test de DeLong.
({double diff, double se, double lower, double upper, double z, double p}) compareAucDeLong(
    List<double> s1, List<double> s2, List<double> y,
    {double level = 0.95}) {
  final a = _delongComponents(s1, y), b = _delongComponents(s2, y);
  final n1 = a.v10.length, n0 = a.v01.length;
  final var1 = _cov(a.v10, a.v10) / n1 + _cov(a.v01, a.v01) / n0;
  final var2 = _cov(b.v10, b.v10) / n1 + _cov(b.v01, b.v01) / n0;
  final cov = _cov(a.v10, b.v10) / n1 + _cov(a.v01, b.v01) / n0;
  final d = a.auc - b.auc;
  final se = math.sqrt(var1 + var2 - 2 * cov);
  final zq = normalQuantile(1 - (1 - level) / 2);
  return (diff: d, se: se, lower: d - zq * se, upper: d + zq * se, z: d / se, p: normalTwoSidedP(d / se));
}

double brierScore(List<double> p, List<double> y) {
  var s = 0.0;
  for (var i = 0; i < y.length; i++) {
    s += (p[i] - y[i]) * (p[i] - y[i]);
  }
  return s / y.length;
}

double _logit(double p) {
  final q = p.clamp(1e-12, 1 - 1e-12);
  return math.log(q / (1 - q));
}

/// Pente de calibration (régression logistique de y sur le logit prédit) et
/// intercept de calibration « dans l'ensemble » (logit prédit en offset).
({double slope, double slopeSe, double intercept, double interceptSe}) calibrationSlopeIntercept(List<double> p, List<double> y) {
  final lp = [for (final v in p) _logit(v)];
  final fit = fitLogistic([for (final v in lp) [1.0, v]], y);
  // Intercept avec offset : IRLS à un paramètre.
  var a = 0.0;
  var info = 0.0;
  for (var it = 0; it < 100; it++) {
    var score = 0.0;
    info = 0.0;
    for (var i = 0; i < y.length; i++) {
      final m = 1 / (1 + math.exp(-(a + lp[i])));
      score += y[i] - m;
      info += m * (1 - m);
    }
    final step = score / info;
    a += step;
    if (step.abs() < 1e-12) break;
  }
  return (
    slope: fit.beta[1],
    slopeSe: math.sqrt(fit.cov.get(1, 1)),
    intercept: a,
    interceptSe: math.sqrt(1 / info),
  );
}

/// Courbe de calibration par groupes de risque prédit (quantiles).
List<Map<String, double>> calibrationGroups(List<double> p, List<double> y, {int groups = 10}) {
  // Tri stable (ex aequo dans l'ordre des lignes, comme order() de R).
  final idx = List<int>.generate(p.length, (i) => i)..sort((a, b) {
      final c = p[a].compareTo(p[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final out = <Map<String, double>>[];
  for (var g = 0; g < groups; g++) {
    final from = (g * p.length / groups).floor();
    final to = ((g + 1) * p.length / groups).floor();
    if (to <= from) continue;
    final sel = idx.sublist(from, to);
    final ev = sel.where((i) => y[i] == 1).length;
    final ci = wilsonCi(ev, sel.length);
    out.add({
      'predicted': sel.fold(0.0, (a, i) => a + p[i]) / sel.length,
      'observed': ev / sel.length,
      'lower': ci.lower,
      'upper': ci.upper,
      'n': sel.length.toDouble(),
    });
  }
  return out;
}

/// Bénéfice net (Vickers & Elkin 2006) aux seuils de probabilité donnés.
List<Map<String, double>> decisionCurve(List<double> p, List<double> y, List<double> thresholds) {
  final n = y.length;
  final prev = y.where((v) => v == 1).length / n;
  return [
    for (final t in thresholds)
      () {
        var tp = 0, fp = 0;
        for (var i = 0; i < n; i++) {
          if (p[i] >= t) {
            if (y[i] == 1) {
              tp++;
            } else {
              fp++;
            }
          }
        }
        final w = t / (1 - t);
        return {
          'threshold': t,
          'model': tp / n - fp / n * w,
          'treatAll': prev - (1 - prev) * w,
          'treatNone': 0.0,
        };
      }()
  ];
}

/// R² de Cox-Snell et de Nagelkerke d'un modèle logistique.
({double coxSnell, double nagelkerke, double maxCoxSnell}) pseudoR2(double logLikModel, double logLikNull, int n) {
  final cs = 1 - math.exp(2 * (logLikNull - logLikModel) / n);
  final mx = 1 - math.exp(2 * logLikNull / n);
  return (coxSnell: cs, nagelkerke: cs / mx, maxCoxSnell: mx);
}

/// Taille d'échantillon minimale d'un modèle de prédiction binaire (Riley et
/// al., Stat Med 2019 ; BMJ 2020), critères (i) à (iii).
({double n1, double n2, double n3, double n}) rileySampleSize(
    {required int parameters, required double prevalence, required double r2CoxSnell, double shrinkage = 0.9, double delta = 0.05, double marginPrevalence = 0.05}) {
  final p = parameters.toDouble();
  final phi = prevalence;
  final lnLnull = phi * math.log(phi) + (1 - phi) * math.log(1 - phi);
  final maxR2 = 1 - math.exp(2 * lnLnull);
  final n1 = p / ((shrinkage - 1) * math.log(1 - r2CoxSnell / shrinkage));
  final sReq = r2CoxSnell / (r2CoxSnell + delta * maxR2);
  final n2 = p / ((sReq - 1) * math.log(1 - r2CoxSnell / sReq));
  final n3 = math.pow(normalQuantile(0.975) / marginPrevalence, 2) * phi * (1 - phi);
  return (n1: n1, n2: n2, n3: n3.toDouble(), n: [n1, n2, n3.toDouble()].reduce(math.max));
}
