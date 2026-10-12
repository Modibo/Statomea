/// Expression différentielle RNA-seq (deux groupes ou plan à plusieurs facteurs), portage de la chaîne de référence edgeR + limma :
///  - filtre des gènes peu exprimés (CPM ≥ seuil dans au moins k échantillons, comme `cpm(y) >= 1`) ;
///  - normalisation TMM (Robinson et Oshlack 2010 ; `edgeR::calcNormFactors`, trim 30 % / 5 %, pondération) ;
///  - transformation voom (Law et al. 2014) : log-CPM, tendance moyenne–variance par `lowess` (portage exact
///    du code C de R), poids d'observation 1/s⁴ ;
///  - modèle linéaire pondéré gène par gène, t modérés par Bayes empirique (Smyth 2004, `eBayes`) ;
///  - taux de fausses découvertes (Benjamini-Hochberg).
/// Validé contre edgeR 3.40 / limma 3.54 (`validation/r/20_expression.R`, `22_expression_plan.R`).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../inference/multiplicity.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../math/special.dart';
import '../model/result.dart';

double _mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;

/// Quantile de type 7 (défaut de R).
double _quantile7(List<double> x, double p) {
  final s = [...x]..sort();
  final index = (s.length - 1) * p;
  final lo = index.floor(), hi = index.ceil();
  final h = index - lo;
  return h == 0 || s[hi] == s[lo] ? s[lo] : (1 - h) * s[lo] + h * s[hi];
}

String _pCell(double p) => p < 1e-3 ? tr(p.toStringAsExponential(2).replaceAll('.', ','), p.toStringAsExponential(2)) : fmt(p, digits: 3);

double _median(List<double> x) => _quantile7(x, 0.5);

/// Rangs moyens en cas d'ex æquo (`rank` de R).
List<double> _rank(List<double> x) {
  final o = [for (var i = 0; i < x.length; i++) i]..sort((a, b) {
      final k = x[a].compareTo(x[b]);
      return k != 0 ? k : a.compareTo(b);
    });
  final r = List<double>.filled(x.length, 0);
  var i = 0;
  while (i < o.length) {
    var j = i;
    while (j + 1 < o.length && x[o[j + 1]] == x[o[i]]) {
      j++;
    }
    final avg = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      r[o[k]] = avg;
    }
    i = j + 1;
  }
  return r;
}

/// Facteur TMM d'un échantillon contre l'échantillon de référence (`.calcFactorTMM`).
double _tmmFactor(List<double> obs, List<double> ref, double nO, double nR, {double logratioTrim = 0.3, double sumTrim = 0.05}) {
  final logR = <double>[], absE = <double>[], v = <double>[];
  for (var g = 0; g < obs.length; g++) {
    final lr = log2((obs[g] / nO) / (ref[g] / nR));
    final ae = (log2(obs[g] / nO) + log2(ref[g] / nR)) / 2;
    if (!lr.isFinite || !ae.isFinite) continue;
    logR.add(lr);
    absE.add(ae);
    v.add((nO - obs[g]) / nO / obs[g] + (nR - ref[g]) / nR / ref[g]);
  }
  if (logR.isEmpty || logR.map((e) => e.abs()).reduce(math.max) < 1e-6) return 1;
  final n = logR.length;
  final loL = (n * logratioTrim).floor() + 1, hiL = n + 1 - loL;
  final loS = (n * sumTrim).floor() + 1, hiS = n + 1 - loS;
  final rl = _rank(logR), ra = _rank(absE);
  var num = 0.0, den = 0.0;
  for (var g = 0; g < n; g++) {
    if (rl[g] >= loL && rl[g] <= hiL && ra[g] >= loS && ra[g] <= hiS) {
      num += logR[g] / v[g];
      den += 1 / v[g];
    }
  }
  final f = num / den;
  return math.pow(2, f.isNaN ? 0 : f).toDouble();
}

/// Facteurs de normalisation TMM (`calcNormFactors(method = "TMM")`), de moyenne géométrique 1.
/// [counts] : gènes × échantillons.
List<double> tmmNormFactors(List<List<double>> counts, List<double> libSize) {
  final ns = libSize.length;
  // Lignes entièrement nulles exclues, comme edgeR.
  final x = [for (final r in counts) if (r.any((c) => c > 0)) r];
  if (x.isEmpty || ns == 1) return List.filled(ns, 1.0);
  final f75 = [for (var j = 0; j < ns; j++) _quantile7([for (final r in x) r[j]], 0.75) / libSize[j]];
  int refCol;
  if (_median(f75) < 1e-20) {
    var best = -1.0;
    refCol = 0;
    for (var j = 0; j < ns; j++) {
      final s = x.fold(0.0, (a, r) => a + math.sqrt(r[j]));
      if (s > best) {
        best = s;
        refCol = j;
      }
    }
  } else {
    final m = _mean(f75);
    refCol = 0;
    for (var j = 1; j < ns; j++) {
      if ((f75[j] - m).abs() < (f75[refCol] - m).abs()) refCol = j;
    }
  }
  final ref = [for (final r in x) r[refCol]];
  final f = [for (var j = 0; j < ns; j++) _tmmFactor([for (final r in x) r[j]], ref, libSize[j], libSize[refCol])];
  final gm = math.exp(f.fold(0.0, (a, b) => a + math.log(b)) / ns);
  return [for (final v in f) v / gm];
}

/// `lowess` de R (Cleveland 1979), portage ligne à ligne de `clowess` (src/library/stats/src/lowess.c).
/// Retourne (x triés, valeurs lissées).
({List<double> x, List<double> y}) lowess(List<double> xIn, List<double> yIn, {double f = 2 / 3, int iter = 3, double? delta}) {
  final n = xIn.length;
  final o = [for (var i = 0; i < n; i++) i]..sort((a, b) {
      final k = xIn[a].compareTo(xIn[b]);
      return k != 0 ? k : a.compareTo(b);
    });
  // Tableaux indexés à partir de 1, comme dans le code C.
  final x = [0.0, for (final i in o) xIn[i]];
  final y = [0.0, for (final i in o) yIn[i]];
  final del = delta ?? 0.01 * (x[n] - x[1]);
  final ys = List<double>.filled(n + 1, 0);
  if (n < 2) return (x: x.sublist(1), y: y.sublist(1));
  final rw = List<double>.filled(n + 1, 0);
  final res = List<double>.filled(n + 1, 0); // sert aussi de tableau de poids de travail
  final ns = math.max(2, math.min(n, (f * n + 1e-7).toInt()));

  double cube(double v) => v * v * v;

  // Ajustement local en xs ; null si tous les poids sont nuls.
  double? lowest(double xs, int nleft, int nright, bool userw) {
    final w = res;
    final range = x[n] - x[1];
    final h = math.max(xs - x[nleft], x[nright] - xs);
    final h9 = 0.999 * h, h1 = 0.001 * h;
    var a = 0.0;
    var j = nleft;
    while (j <= n) {
      w[j] = 0;
      final r = (x[j] - xs).abs();
      if (r <= h9) {
        w[j] = r <= h1 ? 1.0 : cube(1 - cube(r / h));
        if (userw) w[j] *= rw[j];
        a += w[j];
      } else if (x[j] > xs) {
        break;
      }
      j++;
    }
    final nrt = j - 1;
    if (a <= 0) return null;
    for (j = nleft; j <= nrt; j++) {
      w[j] /= a;
    }
    if (h > 0) {
      a = 0;
      for (j = nleft; j <= nrt; j++) {
        a += w[j] * x[j];
      }
      var b = xs - a;
      var c = 0.0;
      for (j = nleft; j <= nrt; j++) {
        c += w[j] * (x[j] - a) * (x[j] - a);
      }
      if (math.sqrt(c) > 0.001 * range) {
        b /= c;
        for (j = nleft; j <= nrt; j++) {
          w[j] *= b * (x[j] - a) + 1;
        }
      }
    }
    var out = 0.0;
    for (j = nleft; j <= nrt; j++) {
      out += w[j] * y[j];
    }
    return out;
  }

  var it = 1;
  while (it <= iter + 1) {
    var nleft = 1, nright = ns, last = 0, i = 1;
    for (;;) {
      if (nright < n) {
        final d1 = x[i] - x[nleft], d2 = x[nright + 1] - x[i];
        if (d1 > d2) {
          nleft++;
          nright++;
          continue;
        }
      }
      ys[i] = lowest(x[i], nleft, nright, it > 1) ?? y[i];
      if (last < i - 1) {
        final denom = x[i] - x[last];
        for (var j = last + 1; j < i; j++) {
          final alpha = (x[j] - x[last]) / denom;
          ys[j] = alpha * ys[i] + (1 - alpha) * ys[last];
        }
      }
      last = i;
      final cut = x[last] + del;
      for (i = last + 1; i <= n; i++) {
        if (x[i] > cut) break;
        if (x[i] == x[last]) {
          ys[i] = ys[last];
          last = i;
        }
      }
      i = math.max(last + 1, i - 1);
      if (last >= n) break;
    }
    final r0 = [for (var k = 1; k <= n; k++) y[k] - ys[k]];
    final sc = r0.fold(0.0, (a, b) => a + b.abs()) / n;
    if (it > iter) break;
    final ar = [for (final r in r0) r.abs()]..sort();
    final m1 = n ~/ 2;
    final cmad = n.isEven ? 3 * (ar[m1] + ar[n - m1 - 1]) : 6 * ar[m1];
    if (cmad < 1e-7 * sc) break;
    final c9 = 0.999 * cmad, c1 = 0.001 * cmad;
    for (var k = 0; k < n; k++) {
      final r = r0[k].abs();
      rw[k + 1] = r <= c1 ? 1.0 : (r <= c9 ? math.pow(1 - (r / cmad) * (r / cmad), 2).toDouble() : 0.0);
    }
    it++;
  }
  return (x: x.sublist(1), y: ys.sublist(1));
}

/// `approxfun(x, y, rule = 2)` avec moyenne des ex æquo ; [x] trié.
double Function(double) _approxfun(List<double> xs, List<double> ys) {
  final ux = <double>[], uy = <double>[];
  var i = 0;
  while (i < xs.length) {
    var j = i, s = 0.0;
    while (j < xs.length && xs[j] == xs[i]) {
      s += ys[j];
      j++;
    }
    ux.add(xs[i]);
    uy.add(s / (j - i));
    i = j;
  }
  return (double v) {
    if (v <= ux.first) return uy.first;
    if (v >= ux.last) return uy.last;
    var lo = 0, hi = ux.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (ux[mid] <= v) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return uy[lo] + (uy[hi] - uy[lo]) * (v - ux[lo]) / (ux[hi] - ux[lo]);
  };
}

/// Inverse de la fonction trigamma (`limma::trigammaInverse`, Newton).
double trigammaInverse(double x) {
  if (x > 1e7) return 1 / math.sqrt(x);
  if (x < 1e-6) return 1 / x;
  var y = 0.5 + 1 / x;
  for (var it = 0; it < 50; it++) {
    final tri = trigamma(y);
    final dif = tri * (1 - tri / x) / tetragamma(y);
    y += dif;
    if (-dif / y < 1e-8) break;
  }
  return y;
}

/// Loi a priori des variances (`limma::fitFDist`, sans covariable) : (s²₀, d₀).
({double s2, double df}) fitFDist(List<double> s2, List<double> df1) {
  final ok = [for (var i = 0; i < s2.length; i++) if (s2[i].isFinite && df1[i].isFinite && s2[i] > -1e-15 && df1[i] > 1e-15) i];
  final n = ok.length;
  if (n < 2) return (s2: double.nan, df: double.nan);
  var x = [for (final i in ok) math.max(s2[i], 0.0)];
  final d = [for (final i in ok) df1[i]];
  var m = _median(x);
  if (m == 0) m = 1;
  x = [for (final v in x) math.max(v, 1e-5 * m)];
  final e = [for (var i = 0; i < n; i++) math.log(x[i]) - digamma(d[i] / 2) + math.log(d[i] / 2)];
  final emean = _mean(e);
  var evar = e.fold(0.0, (a, v) => a + (v - emean) * (v - emean)) / (n - 1);
  evar -= _mean([for (final v in d) trigamma(v / 2)]);
  if (evar > 0) {
    final df2 = 2 * trigammaInverse(evar);
    return (s2: math.exp(emean + digamma(df2 / 2) - math.log(df2 / 2)), df: df2);
  }
  return (s2: math.exp(emean), df: double.infinity);
}

/// Résultat complet de la chaîne voom–limma (gènes retenus, dans l'ordre d'origine).
class ExpressionFit {
  final List<String> genes;
  final List<double> libSize, normFactors;
  final List<List<double>> logCpm, weights;
  final List<double> logFC, aveExpr, se, t, p, adjP;
  final double dfPrior, s2Prior;
  final List<double> dfTotal;
  final int filteredOut;
  ExpressionFit({
    required this.genes,
    required this.libSize,
    required this.normFactors,
    required this.logCpm,
    required this.weights,
    required this.logFC,
    required this.aveExpr,
    required this.se,
    required this.t,
    required this.p,
    required this.adjP,
    required this.dfPrior,
    required this.s2Prior,
    required this.dfTotal,
    required this.filteredOut,
  });
}

/// Plan d'expérience : facteur d'intérêt (groupe, ≥ 2 niveaux), facteurs d'ajustement (lot, sexe…) et covariables
/// quantitatives (RIN, âge…). Modèle : y ~ groupe + facteurs + covariables (codage de traitement, comme R).
class ExpressionDesign {
  final List<String> group;
  final String? reference;
  final Map<String, List<String>> factors;
  final Map<String, List<double>> covariates;

  /// Sujet (ou autre unité de mesures répétées) traité par corrélation intra-bloc et moindres carrés généralisés
  /// (`duplicateCorrelation`) ; null : échantillons indépendants. Pour un sujet observé dans chaque groupe
  /// (avant/après), le placer plutôt dans [factors] (effet fixe), plus simple et exact.
  final List<String>? block;
  const ExpressionDesign(this.group, {this.reference, this.factors = const {}, this.covariates = const {}, this.block});

  /// Niveaux du groupe : la référence d'abord, puis les autres par ordre alphabétique (comme `factor` de R).
  List<String> get levels {
    final l = group.toSet().toList()..sort();
    if (l.isEmpty) return const [];
    final ref = reference != null && l.contains(reference) ? reference! : l.first;
    return [ref, ...l.where((x) => x != ref)];
  }

  /// Écriture du modèle, p. ex. « y ~ groupe + lot + rin ».
  String get formula =>
      ['y ~ ${tr('groupe', 'group')}', ...factors.keys, ...covariates.keys].join(' + ') + (block == null ? '' : tr(' (corrélation intra-sujet)', ' (within-subject correlation)'));
}

/// Prise en compte du sujet (mesures répétées) : en effet fixe si le modèle reste de rang plein en ajoutant le
/// sujet (sujet observé dans plusieurs groupes : avant/après, appariement), sinon par corrélation intra-sujet
/// (sujet emboîté dans le groupe : plusieurs prélèvements par patient et par témoin).
bool subjectAsFixedEffect(ExpressionDesign d, List<String> subject) {
  if (subject.length != d.group.length) return false;
  final m = _buildModel(ExpressionDesign(d.group, reference: d.reference, factors: {...d.factors, '\u0000sujet': subject}, covariates: d.covariates));
  return m.x.length > m.names.length && invertSpd(crossprodWeighted(m.x, List<double>.filled(m.x.length, 1))) != null;
}

/// Noms des contrastes produits par [voomLimmaDesign], dans le même ordre : niveaux contre la référence,
/// puis entre niveaux non de référence (p. ex. « B − A », « C − A », « C − B »).
List<String> expressionContrastNames(ExpressionDesign d) {
  final lv = d.levels;
  return [
    for (var i = 1; i < lv.length; i++) '${lv[i]} − ${lv[0]}',
    for (var i = 1; i < lv.length; i++)
      for (var j = i + 1; j < lv.length; j++) '${lv[j]} − ${lv[i]}',
  ];
}

({List<List<double>> x, List<String> names, List<int> groupCols}) _buildModel(ExpressionDesign d) {
  final n = d.group.length;
  final lv = d.levels;
  final names = ['(intercept)'];
  final cols = <List<double>>[List<double>.filled(n, 1)];
  final gc = <int>[];
  for (final l in lv.skip(1)) {
    gc.add(cols.length);
    names.add(l);
    cols.add([for (final g in d.group) g == l ? 1.0 : 0.0]);
  }
  for (final e in d.factors.entries) {
    if (e.value.length != n) {
      throw StatInputError('shape', tr('« ${e.key} » : une valeur par échantillon est requise.', '"${e.key}": one value per sample is required.'));
    }
    final fl = e.value.toSet().toList()..sort();
    for (final l in fl.skip(1)) {
      names.add('${e.key}=$l');
      cols.add([for (final v in e.value) v == l ? 1.0 : 0.0]);
    }
  }
  for (final e in d.covariates.entries) {
    if (e.value.length != n || e.value.any((v) => !v.isFinite)) {
      throw StatInputError('shape', tr('« ${e.key} » : une valeur numérique par échantillon est requise, sans valeur manquante.',
          '"${e.key}": one numeric value per sample is required, with no missing value.'));
    }
    names.add(e.key);
    cols.add(e.value);
  }
  return (x: [for (var i = 0; i < n; i++) [for (final c in cols) c[i]]], names: names, groupCols: gc);
}

/// Moindres carrés pondérés pour un gène : coefficients, (XᵀWX)⁻¹, σ résiduel, valeurs ajustées.
({List<double> beta, Matrix v, double sigma, List<double> fitted}) _wls(List<List<double>> x, List<double> y, List<double> w) {
  final n = x.length, p = x.first.length;
  final v = invertSpd(crossprodWeighted(x, w))!;
  final xty = List<double>.filled(p, 0);
  for (var i = 0; i < n; i++) {
    for (var a = 0; a < p; a++) {
      xty[a] += x[i][a] * w[i] * y[i];
    }
  }
  final beta = [for (var a = 0; a < p; a++) [for (var b = 0; b < p; b++) v.get(a, b) * xty[b]].fold(0.0, (s, e) => s + e)];
  final fitted = [for (var i = 0; i < n; i++) [for (var a = 0; a < p; a++) x[i][a] * beta[a]].fold(0.0, (s, e) => s + e)];
  var rss = 0.0;
  for (var i = 0; i < n; i++) {
    rss += w[i] * (y[i] - fitted[i]) * (y[i] - fitted[i]);
  }
  return (beta: beta, v: v, sigma: math.sqrt(rss / (n - p)), fitted: fitted);
}

// ------------------------------------------------------------------ corrélation intra-sujet (duplicateCorrelation)

/// Base orthonormée de l'espace résiduel de X (n × (n − p)) : Gram-Schmidt modifié avec réorthogonalisation sur
/// [X | I]. Le résultat de [_mixedModelRho] ne dépend pas du choix de cette base.
List<List<double>> _residualBasis(List<List<double>> x) {
  final n = x.length, p = x.first.length;
  final basis = <List<double>>[];
  void addIfIndependent(List<double> v) {
    for (var pass = 0; pass < 2; pass++) {
      for (final b in basis) {
        var d = 0.0;
        for (var i = 0; i < n; i++) {
          d += b[i] * v[i];
        }
        for (var i = 0; i < n; i++) {
          v[i] -= d * b[i];
        }
      }
    }
    final norm = math.sqrt(v.fold(0.0, (a, e) => a + e * e));
    if (norm > 1e-8) basis.add([for (final e in v) e / norm]);
  }

  for (var a = 0; a < p; a++) {
    addIfIndependent([for (var i = 0; i < n; i++) x[i][a]]);
  }
  final rank = basis.length;
  for (var i = 0; i < n && basis.length < n; i++) {
    addIfIndependent([for (var k = 0; k < n; k++) k == i ? 1.0 : 0.0]);
  }
  return basis.sublist(rank);
}

/// Valeurs et vecteurs propres d'une matrice symétrique (Jacobi cyclique).
({List<double> values, List<List<double>> vectors}) _symEigen(List<List<double>> a0) {
  final n = a0.length;
  final a = [for (final r in a0) [...r]];
  final v = [for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) i == j ? 1.0 : 0.0]];
  for (var sweep = 0; sweep < 100; sweep++) {
    var off = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        off += a[i][j] * a[i][j];
      }
    }
    if (off < 1e-30) break;
    for (var p = 0; p < n; p++) {
      for (var q = p + 1; q < n; q++) {
        if (a[p][q].abs() < 1e-300) continue;
        final theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
        final t = (theta >= 0 ? 1 : -1) / (theta.abs() + math.sqrt(theta * theta + 1));
        final c = 1 / math.sqrt(t * t + 1), s = t * c;
        for (var k = 0; k < n; k++) {
          final akp = a[k][p], akq = a[k][q];
          a[k][p] = c * akp - s * akq;
          a[k][q] = s * akp + c * akq;
        }
        for (var k = 0; k < n; k++) {
          final apk = a[p][k], aqk = a[q][k];
          a[p][k] = c * apk - s * aqk;
          a[q][k] = s * apk + c * aqk;
        }
        for (var k = 0; k < n; k++) {
          final vkp = v[k][p], vkq = v[k][q];
          v[k][p] = c * vkp - s * vkq;
          v[k][q] = s * vkp + c * vkq;
        }
      }
    }
  }
  return (values: [for (var i = 0; i < n; i++) a[i][i]], vectors: [for (var j = 0; j < n; j++) [for (var i = 0; i < n; i++) v[i][j]]]);
}

/// MLE gamma à lien identité amorti (Levenberg-Marquardt), portage ligne à ligne de `statmod::glmgam.fit`
/// pour deux colonnes (résiduelle, bloc).
List<double> _glmgamFit(List<List<double>> x, List<double> y, List<double> start, {double tol = 1e-6, int maxit = 20}) {
  final n = y.length;
  var beta = [...start];
  List<double> fitted(List<double> b) => [for (final r in x) r[0] * b[0] + r[1] * b[1]];
  var mu = fitted(beta);
  double deviance(List<double> mu) {
    if (mu.any((m) => m < 0)) return double.infinity;
    var dev = 0.0;
    var all = true;
    for (var i = 0; i < n; i++) {
      if (y[i] < 1e-15 && mu[i] < 1e-15) continue;
      all = false;
      dev += (y[i] - mu[i]) / mu[i] - math.log(y[i] / mu[i]);
    }
    return all ? 0 : 2 * dev;
  }

  var dev = deviance(mu);
  var iter = 0;
  var lambda = 0.0;
  for (;;) {
    iter++;
    final v0 = [for (final m in mu) m * m];
    final vmax = v0.reduce(math.max);
    final v = [for (final e in v0) math.max(e, vmax / 1e3)];
    var a00 = 0.0, a01 = 0.0, a11 = 0.0, d0 = 0.0, d1 = 0.0;
    for (var i = 0; i < n; i++) {
      a00 += x[i][0] * x[i][0] / v[i];
      a01 += x[i][0] * x[i][1] / v[i];
      a11 += x[i][1] * x[i][1] / v[i];
      d0 += x[i][0] * (y[i] - mu[i]) / v[i];
      d1 += x[i][1] * (y[i] - mu[i]) / v[i];
    }
    final maxinfo = math.max(a00, a11);
    if (iter == 1) lambda = ((a00 + a11) / 2).abs() / 2;
    final betaOld = beta, devOld = dev;
    var lev = 0;
    var db0 = 0.0, db1 = 0.0;
    var tooMuch = false;
    for (;;) {
      lev++;
      final m00 = a00 + lambda, m11 = a11 + lambda, det = m00 * m11 - a01 * a01;
      db0 = (m11 * d0 - a01 * d1) / det;
      db1 = (m00 * d1 - a01 * d0) / det;
      beta = [betaOld[0] + db0, betaOld[1] + db1];
      mu = fitted(beta);
      dev = deviance(mu);
      if (dev <= devOld || dev / mu.reduce(math.max) < 1e-15) break;
      if (lambda / maxinfo > 1e15) {
        beta = betaOld;
        tooMuch = true;
        break;
      }
      lambda *= 2;
    }
    if (tooMuch || lambda / maxinfo > 1e15) break;
    if (lev == 1) lambda /= 10;
    if (d0 * db0 + d1 * db1 < tol || dev / mu.reduce(math.max) < 1e-15) break;
    if (iter > maxit) break;
  }
  return beta;
}

/// Corrélation intra-bloc d'un gène : composantes de variance REML d'un modèle à un effet aléatoire
/// (`statmod::mixedModel2Fit`, poids appliqués à y et X mais pas à Z, comme statmod). NaN si non estimable.
double _mixedModelRho(List<double> y0, List<List<double>> x0, List<List<double>> z, List<double>? w) {
  final n = y0.length, nz = z.first.length;
  final sw = w == null ? null : [for (final e in w) math.sqrt(e)];
  final y = [for (var i = 0; i < n; i++) sw == null ? y0[i] : sw[i] * y0[i]];
  final x = [for (var i = 0; i < n; i++) [for (final e in x0[i]) sw == null ? e : sw[i] * e]];
  final q2 = _residualBasis(x);
  final mq = q2.length;
  if (mq == 0) return double.nan;
  final qz = [for (final b in q2) [for (var c = 0; c < nz; c++) [for (var i = 0; i < n; i++) b[i] * z[i][c]].fold(0.0, (a, e) => a + e)]];
  final qy = [for (final b in q2) [for (var i = 0; i < n; i++) b[i] * y[i]].fold(0.0, (a, e) => a + e)];
  final m = [for (var a = 0; a < mq; a++) [for (var b = 0; b < mq; b++) [for (var c = 0; c < nz; c++) qz[a][c] * qz[b][c]].fold(0.0, (s, e) => s + e)]];
  final eig = _symEigen(m);
  final dmax = eig.values.fold(0.0, (a, e) => math.max(a, e.abs()));
  final d = [for (final e in eig.values) e.abs() < 1e-12 * math.max(1.0, dmax) ? 0.0 : e];
  final dy = [for (final u in eig.vectors) math.pow([for (var k = 0; k < mq; k++) u[k] * qy[k]].fold(0.0, (a, e) => a + e), 2).toDouble()];
  final dx = [for (final e in d) [1.0, e]];
  // Moindres carrés ordinaires (point de départ).
  final md = _mean(d), mdy = _mean(dy);
  var sdd = 0.0, sdy = 0.0;
  for (var k = 0; k < mq; k++) {
    sdd += (d[k] - md) * (d[k] - md);
    sdy += (d[k] - md) * (dy[k] - mdy);
  }
  if (sdd <= 0) return double.nan;
  var b1 = sdy / sdd, b0 = mdy - b1 * md;
  final varD = mq > 1 ? sdd / (mq - 1) : 0.0;
  if (mq > 2 && d.where((e) => e.abs() > 1e-15).length > 1 && varD > 1e-15) {
    final ok = d.every((e) => b0 + b1 * e >= 0);
    final start = ok ? [b0, b1] : [mdy, 0.0];
    final b = _glmgamFit(dx, dy, start);
    b0 = b[0];
    b1 = b[1];
  }
  return b1 / (b0 + b1);
}

/// Corrélation consensuelle intra-bloc (`limma::duplicateCorrelation` avec `block`) : ρ par gène bornée à
/// [1/(1 − taille max) + 0,01 ; 0,99], moyenne tronquée (15 %) des atanh(ρ), puis tanh.
({double consensus, List<double> atanh}) duplicateCorrelation(List<List<double>> e, List<List<double>> x, List<String> block, {List<List<double>>? weights}) {
  final n = block.length, nbeta = x.first.length;
  final levels = <String>[];
  for (final b in block) {
    if (!levels.contains(b)) levels.add(b);
  }
  final sizes = [for (final l in levels) block.where((b) => b == l).length];
  final maxSize = sizes.reduce(math.max);
  if (maxSize == 1) return (consensus: 0.0, atanh: List<double>.filled(e.length, 0));
  final z = [for (final b in block) [for (final l in levels) b == l ? 1.0 : 0.0]];
  final rho = <double>[];
  for (var g = 0; g < e.length; g++) {
    if (n > nbeta + 2 && levels.length > 1 && levels.length < n - 1) {
      rho.add(_mixedModelRho(e[g], x, z, weights?[g]));
    } else {
      rho.add(double.nan);
    }
  }
  final rhoMin = 1 / (1 - maxSize) + 0.01, rhoMax = 0.99;
  final ar = [for (final r in rho) r.isNaN ? double.nan : _atanh(r.clamp(rhoMin, rhoMax))];
  final finite = [for (final a in ar) if (!a.isNaN) a]..sort();
  final lo = (finite.length * 0.15).floor(), hi = finite.length - lo;
  final kept = finite.sublist(lo, hi);
  final mean = kept.fold(0.0, (a, b) => a + b) / kept.length;
  return (consensus: _tanh(mean), atanh: ar);
}

double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));
double _tanh(double x) => (math.exp(2 * x) - 1) / (math.exp(2 * x) + 1);

/// Moindres carrés généralisés par bloc (`limma:::gls.series`) : V = D·C·D, C de corrélation [rho] intra-bloc,
/// D = diag(1/√w) ; coefficients, (XᵀV⁻¹X)⁻¹, σ, valeurs ajustées.
({List<double> beta, Matrix v, double sigma, List<double> fitted}) _gls(List<List<double>> x, List<double> y, List<double> w, List<String> block, double rho) {
  final n = x.length, p = x.first.length;
  final vm = Matrix(n, n);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final c = i == j ? 1.0 : (block[i] == block[j] ? rho : 0.0);
      vm.set(i, j, c / math.sqrt(w[i] * w[j]));
    }
  }
  final vi = invertSpd(vm)!;
  final xtvx = Matrix(p, p);
  final xtvy = List<double>.filled(p, 0);
  for (var a = 0; a < p; a++) {
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (var j = 0; j < n; j++) {
        s += vi.get(i, j) * x[j][a];
      }
      // s = (V⁻¹ X)[i, a]
      xtvy[a] += s * y[i];
      for (var b = 0; b < p; b++) {
        xtvx.set(b, a, xtvx.get(b, a) + x[i][b] * s);
      }
    }
  }
  final cov = invertSpd(xtvx)!;
  final beta = [for (var a = 0; a < p; a++) [for (var b = 0; b < p; b++) cov.get(a, b) * xtvy[b]].fold(0.0, (s, e) => s + e)];
  final fitted = [for (var i = 0; i < n; i++) [for (var a = 0; a < p; a++) x[i][a] * beta[a]].fold(0.0, (s, e) => s + e)];
  final r = [for (var i = 0; i < n; i++) y[i] - fitted[i]];
  var q = 0.0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      q += r[i] * vi.get(i, j) * r[j];
    }
  }
  return (beta: beta, v: cov, sigma: math.sqrt(q / (n - p)), fitted: fitted);
}

/// Contraste entre deux niveaux du groupe (numérateur − dénominateur), gène par gène.
class ExpressionContrast {
  final String numerator, denominator;
  final List<double> logFC, se, t, p, adjP;
  const ExpressionContrast(this.numerator, this.denominator, {required this.logFC, required this.se, required this.t, required this.p, required this.adjP});
  String get name => '$numerator − $denominator';
}

/// Résultat de la chaîne voom–limma sur un plan général (gènes retenus, dans l'ordre d'origine).
class ExpressionDesignFit {
  final List<String> genes, levels, coefficientNames;
  final List<double> libSize, normFactors, aveExpr, dfTotal;
  final List<List<double>> logCpm, weights;
  final double dfResidual, dfPrior, s2Prior;
  final int filteredOut;

  /// Corrélation consensuelle intra-sujet (passes 1 et 2 de duplicateCorrelation) ; null sans bloc.
  final double? blockCorrelation1, blockCorrelation2;

  /// Toutes les comparaisons deux à deux : niveaux contre la référence, puis entre niveaux non de référence.
  final List<ExpressionContrast> contrasts;

  /// F modéré global du facteur groupe (k − 1 ddl au numérateur), exact gène par gène.
  final List<double> fStat, fP, fAdjP;
  ExpressionDesignFit({
    required this.genes,
    required this.levels,
    required this.coefficientNames,
    required this.libSize,
    required this.normFactors,
    required this.aveExpr,
    required this.dfTotal,
    required this.logCpm,
    required this.weights,
    required this.dfResidual,
    required this.dfPrior,
    required this.s2Prior,
    required this.filteredOut,
    required this.contrasts,
    required this.fStat,
    required this.fP,
    required this.fAdjP,
    this.blockCorrelation1,
    this.blockCorrelation2,
  });
}

/// Chaîne complète sur un plan général. Les contrastes et le F global sont calculés EXACTEMENT avec la matrice
/// (XᵀW_gX)⁻¹ propre à chaque gène ; limma (`contrasts.fit`, `topTable` à plusieurs coefficients) emploie la
/// corrélation des coefficients du plan non pondéré, une approximation dès que le plan n'est pas orthogonal.
/// Les contrastes contre la référence sont identiques à `topTable(coef)` de limma.
ExpressionDesignFit voomLimmaDesign(List<String> genes, List<List<double>> counts, ExpressionDesign design, {double minCpm = 1, int? minSamples, double span = 0.5}) {
  final ns = design.group.length;
  final lv = design.levels;
  if (lv.length < 2) throw StatInputError('one_group', tr('Au moins deux groupes sont requis.', 'At least two groups are required.'));
  final sizes = {for (final l in lv) l: design.group.where((g) => g == l).length};
  if (sizes.values.any((s) => s < 2)) {
    throw StatInputError('n_too_small', tr('Au moins 2 échantillons par groupe sont requis.', 'At least 2 samples per group are required.'));
  }
  for (final r in counts) {
    if (r.length != ns) throw StatInputError('shape', tr('Chaque gène doit avoir un comptage par échantillon.', 'Each gene must have one count per sample.'));
    if (r.any((c) => c.isNaN || c < 0)) {
      throw StatInputError('negative', tr('Les comptages doivent être des entiers positifs ou nuls, sans valeur manquante.', 'Counts must be non-negative integers, with no missing value.'));
    }
  }
  final model = _buildModel(design);
  final x = model.x, p = model.names.length;
  if (ns - p < 1) {
    throw StatInputError('no_df', tr('Trop de termes pour le nombre d\'échantillons ($p coefficients pour $ns échantillons) : aucun degré de liberté résiduel.',
        'Too many terms for the number of samples ($p coefficients for $ns samples): no residual degree of freedom.'));
  }
  if (invertSpd(crossprodWeighted(x, List<double>.filled(ns, 1))) == null) {
    throw StatInputError('confounded', tr(
        'Plan de rang incomplet : un facteur d\'ajustement (lot…) est confondu avec le groupe ou avec un autre terme. L\'effet du groupe n\'est pas séparable ; retirer le terme confondu ou revoir le plan expérimental.',
        'Rank-deficient design: an adjustment factor (batch…) is confounded with the group or with another term. The group effect cannot be separated; remove the confounded term or revisit the experimental design.'));
  }
  final k = minSamples ?? sizes.values.reduce(math.min);
  final lib0 = [for (var j = 0; j < ns; j++) counts.fold(0.0, (a, r) => a + r[j])];
  final keep = [
    for (var g = 0; g < counts.length; g++)
      if ([for (var j = 0; j < ns; j++) counts[g][j] / lib0[j] * 1e6 >= minCpm].where((b) => b).length >= k) g
  ];
  if (keep.length < 10) {
    throw StatInputError('too_few_genes', tr('Moins de 10 gènes passent le filtre d\'expression : l\'estimation de la tendance moyenne–variance est impossible.',
        'Fewer than 10 genes pass the expression filter: the mean–variance trend cannot be estimated.'));
  }
  final cnt = [for (final g in keep) counts[g]];
  final lib = [for (var j = 0; j < ns; j++) cnt.fold(0.0, (a, r) => a + r[j])];
  final nf = tmmNormFactors(cnt, lib);
  final libN = [for (var j = 0; j < ns; j++) lib[j] * nf[j]];
  final logCpm = [
    for (final r in cnt) [for (var j = 0; j < ns; j++) log2((r[j] + 0.5) / (libN[j] + 1) * 1e6)]
  ];
  final ones = List<double>.filled(ns, 1);
  final amean = [for (final y in logCpm) _mean(y)];
  final meanLogLib = _mean([for (final l in libN) log2(l + 1)]);
  // Poids voom à partir d'un premier ajustement (valeurs ajustées et σ de chaque gène).
  List<List<double>> voomWeights(List<({List<double> beta, Matrix v, double sigma, List<double> fitted})> fit) {
    final sx = <double>[], sy = <double>[];
    for (var g = 0; g < cnt.length; g++) {
      if (cnt[g].every((c) => c == 0)) continue;
      sx.add(amean[g] + meanLogLib - log2(1e6));
      sy.add(math.sqrt(fit[g].sigma));
    }
    final l = lowess(sx, sy, f: span);
    final trend = _approxfun(l.x, l.y);
    return [
      for (var g = 0; g < cnt.length; g++)
        [
          for (var j = 0; j < ns; j++)
            1 / math.pow(trend(log2(1e-6 * math.pow(2, fit[g].fitted[j]) * (libN[j] + 1))), 4).toDouble()
        ]
    ];
  }

  final block = design.block;
  double? rho1, rho2;
  List<List<double>> weights;
  List<({List<double> beta, Matrix v, double sigma, List<double> fitted})> fits;
  if (block == null) {
    weights = voomWeights([for (final y in logCpm) _wls(x, y, ones)]);
    fits = [for (var g = 0; g < cnt.length; g++) _wls(x, logCpm[g], weights[g])];
  } else {
    if (block.length != ns) throw StatInputError('shape', tr('Sujet : une valeur par échantillon est requise.', 'Subject: one value per sample is required.'));
    final levelsB = block.toSet();
    if (levelsB.length == ns) {
      throw StatInputError('block_size', tr('Chaque sujet n\'a qu\'un échantillon : il n\'y a pas de mesures répétées à prendre en compte.',
          'Each subject has a single sample: there are no repeated measures to account for.'));
    }
    final zb = [for (final b in block) [for (final l in levelsB.skip(1)) b == l ? 1.0 : 0.0]];
    final xz = [for (var i = 0; i < ns; i++) [...x[i], ...zb[i]]];
    final rankXz = _residualBasis(xz).length;
    if (ns - rankXz == p) {
      throw StatInputError('block_in_design', tr(
          'Le sujet est déjà entièrement expliqué par les termes du modèle : retirer le sujet du modèle ou le traiter en effet fixe.',
          'The subject is already fully explained by the model terms: remove the subject from the model or treat it as a fixed effect.'));
    }
    // Chaîne du guide de limma : voom → duplicateCorrelation → voom(bloc) → duplicateCorrelation → lmFit(bloc).
    final w1 = voomWeights([for (final y in logCpm) _wls(x, y, ones)]);
    rho1 = duplicateCorrelation(logCpm, x, block, weights: w1).consensus;
    weights = voomWeights([for (final y in logCpm) _gls(x, y, ones, block, rho1)]);
    rho2 = duplicateCorrelation(logCpm, x, block, weights: weights).consensus;
    fits = [for (var g = 0; g < cnt.length; g++) _gls(x, logCpm[g], weights[g], block, rho2)];
  }
  final dfRes = (ns - p).toDouble();
  final prior = fitFDist([for (final f in fits) f.sigma * f.sigma], List.filled(fits.length, dfRes));
  final dfPooled = dfRes * fits.length;
  final s2post = [
    for (final f in fits) prior.df.isInfinite ? prior.s2 : (dfRes * f.sigma * f.sigma + prior.df * prior.s2) / (dfRes + prior.df)
  ];
  final dfT = List<double>.filled(fits.length, math.min(dfRes + prior.df, dfPooled));

  // Contrastes : niveaux contre la référence, puis entre niveaux non de référence.
  final gc = model.groupCols;
  final defs = <(int, int)>[for (var i = 1; i < lv.length; i++) (i, 0), for (var i = 1; i < lv.length; i++) for (var j = i + 1; j < lv.length; j++) (j, i)];
  final contrasts = <ExpressionContrast>[];
  for (final (num, den) in defs) {
    final c = List<double>.filled(p, 0);
    c[gc[num - 1]] = 1;
    if (den > 0) c[gc[den - 1]] = -1;
    final lfc = <double>[], se = <double>[], t = <double>[], pv = <double>[];
    for (var g = 0; g < fits.length; g++) {
      final f = fits[g];
      var est = 0.0, varU = 0.0;
      for (var a = 0; a < p; a++) {
        est += c[a] * f.beta[a];
        for (var b = 0; b < p; b++) {
          varU += c[a] * c[b] * f.v.get(a, b);
        }
      }
      final s = math.sqrt(varU * s2post[g]);
      lfc.add(est);
      se.add(s);
      t.add(est / s);
      pv.add(tTwoSidedP(est / s, dfT[g]));
    }
    contrasts.add(ExpressionContrast(lv[num], lv[den], logFC: lfc, se: se, t: t, p: pv, adjP: pAdjust(pv, PAdjust.bh)));
  }
  // F modéré global : β_gᵀ V_g⁻¹ β_g / (r · s̃²), V_g = bloc « groupe » de (XᵀW_gX)⁻¹.
  final r = gc.length;
  final fStat = <double>[], fP = <double>[];
  for (var g = 0; g < fits.length; g++) {
    final f = fits[g];
    final sub = Matrix(r, r);
    for (var a = 0; a < r; a++) {
      for (var b = 0; b < r; b++) {
        sub.set(a, b, f.v.get(gc[a], gc[b]));
      }
    }
    final inv = invertSpd(sub)!;
    var q = 0.0;
    for (var a = 0; a < r; a++) {
      for (var b = 0; b < r; b++) {
        q += f.beta[gc[a]] * inv.get(a, b) * f.beta[gc[b]];
      }
    }
    final fv = q / (r * s2post[g]);
    fStat.add(fv);
    fP.add(fUpper(fv, r.toDouble(), dfT[g]));
  }
  return ExpressionDesignFit(
    genes: [for (final g in keep) genes[g]],
    levels: lv,
    coefficientNames: model.names,
    libSize: lib,
    normFactors: nf,
    aveExpr: amean,
    dfTotal: dfT,
    logCpm: logCpm,
    weights: weights,
    dfResidual: dfRes,
    dfPrior: prior.df,
    s2Prior: prior.s2,
    filteredOut: counts.length - keep.length,
    contrasts: contrasts,
    fStat: fStat,
    fP: fP,
    fAdjP: pAdjust(fP, PAdjust.bh),
    blockCorrelation1: rho1,
    blockCorrelation2: rho2,
  );
}

/// Chaîne à deux groupes. [counts] : gènes × échantillons (comptages bruts) ; [treated] : vrai pour les échantillons
/// du groupe comparé au groupe de référence. Filtre : CPM ≥ [minCpm] dans au moins [minSamples] échantillons
/// (par défaut, l'effectif du plus petit groupe).
ExpressionFit voomLimma(List<String> genes, List<List<double>> counts, List<bool> treated, {double minCpm = 1, int? minSamples, double span = 0.5}) {
  final d = voomLimmaDesign(genes, counts, ExpressionDesign([for (final t in treated) t ? 'T' : 'C'], reference: 'C'),
      minCpm: minCpm, minSamples: minSamples, span: span);
  final c = d.contrasts.single;
  return ExpressionFit(
    genes: d.genes,
    libSize: d.libSize,
    normFactors: d.normFactors,
    logCpm: d.logCpm,
    weights: d.weights,
    logFC: c.logFC,
    aveExpr: d.aveExpr,
    se: c.se,
    t: c.t,
    p: c.p,
    adjP: c.adjP,
    dfPrior: d.dfPrior,
    s2Prior: d.s2Prior,
    dfTotal: d.dfTotal,
    filteredOut: d.filteredOut,
  );
}

/// Analyse à deux groupes présentée (cas particulier de [differentialExpressionDesign]).
AnalysisResult differentialExpression(List<String> genes, List<List<double>> counts, List<bool> treated,
    {String controlName = '', String treatedName = '', double fdr = 0.05, double minLogFC = 1, double minCpm = 1, int? minSamples, double level = 0.95, int maxRows = 50}) {
  final ctl = controlName.isEmpty ? tr('témoin', 'control') : controlName;
  final trt = treatedName.isEmpty ? tr('traité', 'treated') : treatedName;
  return differentialExpressionDesign(genes, counts, ExpressionDesign([for (final t in treated) t ? trt : ctl], reference: ctl),
      fdr: fdr, minLogFC: minLogFC, minCpm: minCpm, minSamples: minSamples, level: level, maxRows: maxRows);
}

/// Analyse d'expression différentielle présentée sur un plan général : tableaux par contraste, F global (≥ 3 groupes),
/// volcano plot du contraste [volcanoContrast], contrôles du plan.
AnalysisResult differentialExpressionDesign(List<String> genes, List<List<double>> counts, ExpressionDesign design,
    {List<String>? samples, double fdr = 0.05, double minLogFC = 1, double minCpm = 1, int? minSamples, double level = 0.95, int maxRows = 30, int volcanoContrast = 0}) {
  final notInteger = counts.any((r) => r.any((c) => c != c.roundToDouble()));
  final fit = voomLimmaDesign(genes, counts, design, minCpm: minCpm, minSamples: minSamples);
  final m = fit.genes.length, ns = design.group.length, lv = fit.levels;
  final multi = lv.length > 2;
  final main = fit.contrasts[volcanoContrast.clamp(0, fit.contrasts.length - 1)];
  List<int> ordered(List<double> p) => [for (var g = 0; g < m; g++) g]..sort((a, b) {
      final k = p[a].compareTo(p[b]);
      return k != 0 ? k : a.compareTo(b);
    });
  final order = ordered(main.p);
  final sig = [for (var g = 0; g < m; g++) main.adjP[g] < fdr];
  final nSig = sig.where((b) => b).length;
  final up = [for (var g = 0; g < m; g++) if (sig[g] && main.logFC[g] > 0) g].length;
  final down = nSig - up;
  final sigFc = [for (var g = 0; g < m; g++) if (sig[g] && main.logFC[g].abs() >= minLogFC) g].length;
  final nSigC = [for (final c in fit.contrasts) c.adjP.where((v) => v < fdr).length];
  final nSigF = fit.fAdjP.where((v) => v < fdr).length;
  double q(double df) => tQuantile(1 - (1 - level) / 2, df);
  final nfRange = '${fmt(fit.normFactors.reduce(math.min), digits: 3)}–${fmt(fit.normFactors.reduce(math.max), digits: 3)}';
  final sizes = {for (final l in lv) l: design.group.where((g) => g == l).length};
  final adjusted = [...design.factors.keys, ...design.covariates.keys];
  final sampleName = samples != null && samples.length == ns ? samples : [for (var j = 0; j < ns; j++) '${j + 1}'];
  List<String> row(ExpressionContrast c, int g) =>
      [fit.genes[g], fmt(c.logFC[g]), fmt(math.pow(2, c.logFC[g]).toDouble()), fmt(fit.aveExpr[g]), fmt(c.t[g]), _pCell(c.p[g]), _pCell(c.adjP[g])];
  final header = [tr('Gène', 'Gene'), 'log2 FC', tr('Rapport', 'Fold change'), tr('Expression moy. (log2 CPM)', 'Mean expression (log2 CPM)'), 't', 'p', tr('p ajusté (BH)', 'adjusted p (BH)')];
  final contrastSummary = [for (var i = 0; i < fit.contrasts.length; i++) '${fit.contrasts[i].name} : ${nSigC[i]}'].join(' ; ');
  final contrastSummaryEn = [for (var i = 0; i < fit.contrasts.length; i++) '${fit.contrasts[i].name}: ${nSigC[i]}'].join('; ');
  return AnalysisResult(
    methodId: 'differential_expression',
    methodName: tr('Expression différentielle RNA-seq (TMM + voom + limma)', 'RNA-seq differential expression (TMM + voom + limma)'),
    inputs: {
      'genes': genes.length,
      'samples': ns,
      'groups': {for (final e in sizes.entries) e.key: e.value},
      'reference': lv.first,
      'adjusted_for': adjusted,
      'fdr': fdr,
      'minCpm': minCpm,
      'minSamples': minSamples,
      'level': level,
    },
    formula: tr(
        'Filtre : CPM ≥ ${fmt(minCpm)} dans ≥ k échantillons ; normalisation TMM (trim 30 % des log-rapports, 5 % des intensités, pondération inverse de la variance) ; '
            'voom : y = log2((comptage + 0,5)/(taille normalisée + 1)·10⁶), tendance √σ ~ log-comptage par lowess (f = 0,5), poids 1/s⁴ ; '
            'modèle pondéré ${design.formula} par gène (référence ${lv.first}) ; t modéré = cᵀβ̂ / √(cᵀ(XᵀW_gX)⁻¹c · s̃²), s̃² = (d·s² + d₀·s₀²)/(d + d₀) (Bayes empirique)'
            '${multi ? ' ; F modéré global du groupe = β̂ᵀV⁻¹β̂ / ((k − 1)·s̃²), exact gène par gène' : ''}'
            '${design.block != null ? ' ; mesures répétées : corrélation intra-sujet ρ (REML gène par gène, moyenne tronquée des atanh ρ, 2 passes avec voom), moindres carrés généralisés V = D·C(ρ)·D' : ''} ; FDR de Benjamini-Hochberg par contraste.',
        'Filter: CPM ≥ ${fmt(minCpm)} in ≥ k samples; TMM normalization (trimming 30% of log-ratios, 5% of intensities, inverse-variance weighting); '
            'voom: y = log2((count + 0.5)/(normalized size + 1)·10⁶), √σ ~ log-count trend by lowess (f = 0.5), weights 1/s⁴; '
            'weighted model ${design.formula} per gene (reference ${lv.first}); moderated t = cᵀβ̂ / √(cᵀ(XᵀW_gX)⁻¹c · s̃²), s̃² = (d·s² + d₀·s₀²)/(d + d₀) (empirical Bayes)'
            '${multi ? '; global moderated F for group = β̂ᵀV⁻¹β̂ / ((k − 1)·s̃²), exact gene by gene' : ''}'
            '${design.block != null ? '; repeated measures: within-subject correlation ρ (gene-wise REML, trimmed mean of atanh ρ, 2 passes with voom), generalized least squares V = D·C(ρ)·D' : ''}; Benjamini-Hochberg FDR per contrast.'),
    estimates: [
      for (final g in order.take(5))
        Estimate(tr('${fit.genes[g]} : log2 FC ${main.name}', '${fit.genes[g]}: log2 FC ${main.name}'), main.logFC[g],
            lower: main.logFC[g] - q(fit.dfTotal[g]) * main.se[g], upper: main.logFC[g] + q(fit.dfTotal[g]) * main.se[g], level: level, pValue: main.p[g], se: main.se[g]),
    ],
    statistics: {
      'genes_tested': m.toDouble(),
      'genes_filtered': fit.filteredOut.toDouble(),
      'n_sig': nSig.toDouble(),
      'n_up': up.toDouble(),
      'n_down': down.toDouble(),
      'n_sig_fc': sigFc.toDouble(),
      for (var i = 0; i < fit.contrasts.length; i++) 'n_sig_c$i': nSigC[i].toDouble(),
      if (multi) 'n_sig_f': nSigF.toDouble(),
      'df_residual': fit.dfResidual,
      if (fit.blockCorrelation2 != null) 'block_correlation': fit.blockCorrelation2!,
      'df_prior': fit.dfPrior,
      's2_prior': fit.s2Prior,
      for (var j = 0; j < ns; j++) 'norm_factor_$j': fit.normFactors[j],
    },
    checks: [
      Check('replicates', tr('Réplicats biologiques (≥ 3 par groupe conseillé)', 'Biological replicates (≥ 3 per group advised)'),
          sizes.values.every((s) => s >= 3) ? CheckStatus.ok : CheckStatus.warning,
          tr('Effectifs : ${[for (final e in sizes.entries) '${e.key} ${e.value}'].join(', ')}. Avec 2 réplicats, la variance biologique est très mal estimée, même modérée.',
              'Sizes: ${[for (final e in sizes.entries) '${e.key} ${e.value}'].join(', ')}. With 2 replicates, biological variance is poorly estimated, even when moderated.')),
      Check('raw_counts', tr('Comptages bruts entiers (pas de FPKM/TPM)', 'Raw integer counts (not FPKM/TPM)'), notInteger ? CheckStatus.violated : CheckStatus.ok,
          notInteger
              ? tr('Des valeurs non entières suggèrent des données déjà normalisées : voom requiert les comptages bruts.', 'Non-integer values suggest already-normalized data: voom requires raw counts.')
              : tr('Comptages entiers.', 'Integer counts.')),
      Check('norm_factors', tr('Facteurs TMM modérés (0,5–2)', 'Moderate TMM factors (0.5–2)'),
          fit.normFactors.every((f) => f > 0.5 && f < 2) ? CheckStatus.ok : CheckStatus.warning,
          tr('Facteurs : $nfRange. Des facteurs extrêmes signalent une composition très différente ou un échantillon défaillant.',
              'Factors: $nfRange. Extreme factors signal a very different composition or a failed sample.')),
      if (design.factors.isEmpty)
        Check('batch', tr('Absence d\'effet lot confondu avec le groupe', 'No batch effect confounded with group'), CheckStatus.notAssessed,
            tr('Aucun facteur de lot déclaré. Si les groupes ont été séquencés à des dates ou sur des lignes différentes, l\'effet lot est indissociable de l\'effet étudié.',
                'No batch factor declared. If groups were sequenced on different dates or lanes, the batch effect cannot be separated from the effect studied.'))
      else
        Check('batch', tr('Effet lot ajusté, non confondu avec le groupe', 'Batch effect adjusted, not confounded with group'), CheckStatus.ok,
            tr('Ajusté sur : ${design.factors.keys.join(', ')} ; plan de rang plein (l\'effet du groupe reste estimable).',
                'Adjusted for: ${design.factors.keys.join(', ')}; full-rank design (the group effect remains estimable).')),
      if (fit.blockCorrelation2 != null)
        Check('pairing', tr('Mesures répétées par sujet prises en compte', 'Repeated measures per subject accounted for'), CheckStatus.ok,
            tr('Corrélation intra-sujet consensuelle ρ = ${fmt(fit.blockCorrelation2, digits: 3)} (duplicateCorrelation, 2 passes) ; moindres carrés généralisés par sujet. Ignorer cette corrélation donnerait des p trop petits pour les effets entre sujets.',
                'Consensus within-subject correlation ρ = ${fmt(fit.blockCorrelation2, digits: 3)} (duplicateCorrelation, 2 passes); generalized least squares by subject. Ignoring this correlation would give p-values too small for between-subject effects.')),
      Check('residual_df', tr('Degrés de liberté résiduels (≥ 3 conseillé)', 'Residual degrees of freedom (≥ 3 advised)'), fit.dfResidual >= 3 ? CheckStatus.ok : CheckStatus.warning,
          tr('n − p = $ns − ${fit.coefficientNames.length} = ${fit.dfResidual.toInt()} ; chaque terme d\'ajustement consomme un degré de liberté.',
              'n − p = $ns − ${fit.coefficientNames.length} = ${fit.dfResidual.toInt()}; each adjustment term uses one degree of freedom.')),
    ],
    alerts: [
      if (notInteger)
        Alert('not_counts', Severity.serious,
            tr('Données non entières : la modélisation moyenne–variance de voom n\'est valide que sur des comptages bruts.', 'Non-integer data: the voom mean–variance modelling is valid only on raw counts.')),
      if (fit.dfPrior.isInfinite)
        Alert('df_prior_inf', Severity.info,
            tr('d₀ infini : les variances des gènes sont compatibles avec une variance commune ; les t modérés utilisent s₀².',
                'Infinite d₀: gene variances are compatible with a common variance; moderated t uses s₀².')),
      if (multi)
        Alert('multiple_contrasts', Severity.info,
            tr('${fit.contrasts.length} comparaisons deux à deux : le FDR est contrôlé dans chaque comparaison, pas sur l\'ensemble. Le F global teste d\'abord si le gène varie entre les ${lv.length} groupes.',
                '${fit.contrasts.length} pairwise comparisons: the FDR is controlled within each comparison, not overall. The global F first tests whether the gene varies across the ${lv.length} groups.')),
    ],
    tables: [
      if (multi)
        ResultTable(
            tr('Effet global du groupe (F modéré, ${lv.length - 1} ddl) — ${math.min(maxRows, m)} gènes sur $m', 'Global group effect (moderated F, ${lv.length - 1} df) — ${math.min(maxRows, m)} genes of $m'),
            [tr('Gène', 'Gene'), 'F', 'p', tr('p ajusté (BH)', 'adjusted p (BH)'), for (final c in fit.contrasts.take(lv.length - 1)) 'log2 FC ${c.name}'],
            [
              for (final g in ordered(fit.fP).take(maxRows))
                [fit.genes[g], fmt(fit.fStat[g]), _pCell(fit.fP[g]), _pCell(fit.fAdjP[g]), for (final c in fit.contrasts.take(lv.length - 1)) fmt(c.logFC[g])]
            ]),
      for (final c in fit.contrasts)
        ResultTable(
            multi
                ? tr('${c.name} : gènes les plus significatifs (${math.min(maxRows, m)} sur $m)', '${c.name}: most significant genes (${math.min(maxRows, m)} of $m)')
                : tr('Gènes les plus significatifs (${math.min(maxRows, m)} sur $m)', 'Most significant genes (${math.min(maxRows, m)} of $m)'),
            header,
            [for (final g in ordered(c.p).take(maxRows)) row(c, g)]),
      ResultTable(tr('Normalisation', 'Normalization'), [
        tr('Échantillon', 'Sample'), tr('Groupe', 'Group'), for (final f in design.factors.keys) f, for (final c in design.covariates.keys) c,
        tr('Taille de librairie', 'Library size'), tr('Facteur TMM', 'TMM factor')
      ], [
        for (var j = 0; j < ns; j++)
          [
            sampleName[j], design.group[j], for (final f in design.factors.values) f[j], for (final c in design.covariates.values) fmt(c[j]),
            fit.libSize[j].toStringAsFixed(0), fmt(fit.normFactors[j], digits: 4)
          ]
      ]),
    ],
    figures: {
      'volcano': {
        'logFC': main.logFC,
        'negLog10P': [for (final v in main.p) -math.log(v) / math.ln10],
        'significant': sig,
        'genes': fit.genes,
        'minLogFC': minLogFC,
        'contrast': main.name,
      },
      'ma': {'A': fit.aveExpr, 'M': main.logFC},
    },
    log: [
      tr('${fit.filteredOut} gène(s) écarté(s) par le filtre d\'expression ; $m testé(s).', '${fit.filteredOut} gene(s) removed by the expression filter; $m tested.'),
      tr('Plan : ${design.formula} ; référence ${lv.first} ; coefficients : ${fit.coefficientNames.join(', ')} ; ddl résiduels ${fit.dfResidual.toInt()}.',
          'Design: ${design.formula}; reference ${lv.first}; coefficients: ${fit.coefficientNames.join(', ')}; residual df ${fit.dfResidual.toInt()}.'),
      tr('Loi a priori : d₀ = ${fmt(fit.dfPrior)}, s₀² = ${fmt(fit.s2Prior, digits: 4)}.', 'Prior: d₀ = ${fmt(fit.dfPrior)}, s₀² = ${fmt(fit.s2Prior, digits: 4)}.'),
      if (fit.blockCorrelation2 != null)
        tr('Corrélation intra-sujet : passe 1 ρ = ${fmt(fit.blockCorrelation1, digits: 4)}, passe 2 ρ = ${fmt(fit.blockCorrelation2, digits: 4)}.',
            'Within-subject correlation: pass 1 ρ = ${fmt(fit.blockCorrelation1, digits: 4)}, pass 2 ρ = ${fmt(fit.blockCorrelation2, digits: 4)}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Des milliers de gènes testés sur peu d\'échantillons : voom modélise la relation moyenne–variance des comptages, et limma emprunte de l\'information entre gènes pour stabiliser les variances ; le FDR contrôle la proportion de faux positifs parmi les gènes déclarés.'
              '${adjusted.isEmpty ? '' : ' Le modèle ajuste sur ${adjusted.join(', ')} : les comparaisons de groupes sont faites à ces facteurs constants.'}',
          'Thousands of genes tested on few samples: voom models the mean–variance relationship of counts, and limma borrows information across genes to stabilize variances; the FDR controls the proportion of false positives among declared genes.'
              '${adjusted.isEmpty ? '' : ' The model adjusts for ${adjusted.join(', ')}: group comparisons are made with these factors held constant.'}'),
      whatItMeans: multi
          ? tr(
              '$nSigF gène(s) varient entre les ${lv.length} groupes (F global, FDR ${fmtPct(fdr)}). Par comparaison : $contrastSummary. ${main.name} : $up sur-exprimé(s), $down sous-exprimé(s) ; $sigFc avec |log2 FC| ≥ ${fmt(minLogFC)}.',
              '$nSigF gene(s) vary across the ${lv.length} groups (global F, FDR ${fmtPct(fdr)}). By comparison: $contrastSummaryEn. ${main.name}: $up up-regulated, $down down-regulated; $sigFc with |log2 FC| ≥ ${fmt(minLogFC)}.')
          : tr(
              '$nSig gène(s) différentiellement exprimé(s) au FDR ${fmtPct(fdr)} ($up sur-exprimé(s), $down sous-exprimé(s) chez ${main.numerator}) ; $sigFc avec |log2 FC| ≥ ${fmt(minLogFC)}. Environ ${fmtPct(fdr)} de ces gènes peuvent être de faux positifs.',
              '$nSig differentially expressed gene(s) at FDR ${fmtPct(fdr)} ($up up-regulated, $down down-regulated in ${main.numerator}); $sigFc with |log2 FC| ≥ ${fmt(minLogFC)}. About ${fmtPct(fdr)} of these genes may be false positives.'),
      notJustified: tr(
          'Interpréter un gène isolé sans validation (qPCR, cohorte indépendante) ; filtrer sur le log2 FC puis recalculer le FDR ; conclure à une absence d\'effet pour les gènes non significatifs ; conclure sur la protéine ou la fonction'
              '${multi ? ' ; additionner les gènes des différentes comparaisons comme s\'ils étaient indépendants' : ''}.',
          'Interpreting a single gene without validation (qPCR, independent cohort); filtering on log2 FC and then recomputing the FDR; concluding no effect for non-significant genes; concluding about the protein or the function'
              '${multi ? '; adding up genes from the different comparisons as if they were independent' : ''}.'),
    ),
  );
}
