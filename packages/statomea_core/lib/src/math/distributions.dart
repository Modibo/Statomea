/// Lois de probabilité : fonctions de répartition, quantiles et queues.
///
/// Normale : quantile par l'algorithme AS 241 de Wichura (1988), affiné par
/// une itération de Newton. Student, χ², F, bêta : quantiles par inversion
/// numérique (Brent) de la fonction de répartition.
library;

import 'dart:math' as math;

import 'special.dart';

// ---------------------------------------------------------------- Normale

/// Φ(z), fonction de répartition de la loi normale centrée réduite.
double normalCdf(double z) {
  if (z.isNaN) return double.nan;
  return 0.5 * erfc(-z / math.sqrt2);
}

/// 1 − Φ(z), sans annulation dans la queue droite.
double normalUpper(double z) => 0.5 * erfc(z / math.sqrt2);

double normalPdf(double z) => math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi);

/// Quantile Φ⁻¹(p).
double normalQuantile(double p) {
  if (p <= 0) return p == 0 ? double.negativeInfinity : double.nan;
  if (p >= 1) return p == 1 ? double.infinity : double.nan;
  final q = p - 0.5;
  double x;
  if (q.abs() <= 0.425) {
    final r = 0.180625 - q * q;
    x = q *
        (((((((2509.0809287301226727 * r + 33430.575583588128105) * r +
                                67265.770927008700853) *
                            r +
                        45921.953931549871457) *
                    r +
                13731.693765509461125) *
                r +
            1971.5909503065514427) *
            r +
            133.14166789178437745) *
        r +
        3.387132872796366608) /
        (((((((5226.495278852545561 * r + 28729.085735721942674) * r +
                                39307.89580009271061) *
                            r +
                        21213.794301586595867) *
                    r +
                5394.1960214247511077) *
                r +
            687.1870074920579083) *
            r +
            42.313330701600911252) *
        r +
        1);
  } else {
    var r = q < 0 ? p : 1 - p;
    r = math.sqrt(-math.log(r));
    if (r <= 5) {
      r -= 1.6;
      x = (((((((7.7454501427834140764e-4 * r + 0.0227238449892691845833) * r +
                                  0.24178072517745061177) *
                              r +
                          1.27045825245236838258) *
                      r +
                  3.64784832476320460504) *
                  r +
              5.7694972214606914055) *
              r +
              4.6303378461565452959) *
          r +
          1.42343711074968357734) /
          (((((((1.05075007164441684324e-9 * r + 5.475938084995344946e-4) * r +
                                      0.0151986665636164571966) *
                                  r +
                              0.14810397642748007459) *
                          r +
                      0.68976733498510000455) *
                  r +
                  1.6763848301838038494) *
              r +
              2.05319162663775882187) *
              r +
              1);
    } else {
      r -= 5;
      x = (((((((2.01033439929228813265e-7 * r + 2.71155556874348757815e-5) * r +
                                  0.0012426609473880784386) *
                              r +
                          0.026532189526576123093) *
                      r +
                  0.29656057182850489123) *
                  r +
              1.7848265399172913358) *
              r +
              5.4637849111641143699) *
          r +
          6.6579046435011037772) /
          (((((((2.04426310338993978564e-15 * r + 1.4215117583164458887e-7) * r +
                                      1.8463183175100546818e-5) *
                                  r +
                              7.868691311456132591e-4) *
                          r +
                      0.0148753612908506148525) *
                  r +
                  0.13692988092273580531) *
              r +
              0.59983220655588793769) *
              r +
              1);
    }
    if (q < 0) x = -x;
  }
  // Une itération de Newton sur Φ pour absorber toute erreur résiduelle.
  final err = (p < 0.5 ? normalCdf(x) - p : (p - 1) + normalUpper(x));
  final pdf = normalPdf(x);
  if (pdf > 1e-300) x -= err / pdf;
  return x;
}

/// Valeur de p bilatérale d'une statistique z.
double normalTwoSidedP(double z) => math.min(1.0, 2 * normalUpper(z.abs()));

// ---------------------------------------------------------------- Student

/// P(T ≤ t) pour T ~ t(df).
double tCdf(double t, double df) {
  if (df.isInfinite) return normalCdf(t);
  final x = df / (df + t * t);
  final tail = 0.5 * betaI(df / 2, 0.5, x);
  return t >= 0 ? 1 - tail : tail;
}

/// P(|T| ≥ |t|), valeur de p bilatérale.
double tTwoSidedP(double t, double df) {
  if (df.isInfinite) return normalTwoSidedP(t);
  return math.min(1.0, betaI(df / 2, 0.5, df / (df + t * t)));
}

double tQuantile(double p, double df) {
  if (df.isInfinite) return normalQuantile(p);
  if (p <= 0 || p >= 1) return p == 0 ? double.negativeInfinity : (p == 1 ? double.infinity : double.nan);
  if (p == 0.5) return 0;
  // Symétrie : on résout dans la queue où la précision est la meilleure.
  final upper = p > 0.5;
  final tailP = upper ? 1 - p : p; // probabilité de la queue gauche équivalente
  double f(double t) => 0.5 * betaI(df / 2, 0.5, df / (df + t * t)) - tailP;
  var hi = 1.0;
  while (f(hi) > 0) {
    hi *= 2;
    if (hi > 1e300) break;
  }
  final t = brentRoot(f, 0, hi);
  return upper ? t : -t;
}

// ---------------------------------------------------------------- χ²

double chiSquareCdf(double x, double df) => x <= 0 ? 0 : gammaP(df / 2, x / 2);

/// P(X ≥ x), valeur de p d'un test du χ².
double chiSquareUpper(double x, double df) => x <= 0 ? 1 : gammaQ(df / 2, x / 2);

double chiSquareQuantile(double p, double df) {
  if (p <= 0) return 0;
  if (p >= 1) return double.infinity;
  double f(double x) =>
      p < 0.5 ? chiSquareCdf(x, df) - p : (1 - p) - chiSquareUpper(x, df);
  var hi = math.max(1.0, df);
  while (f(hi) < 0) {
    hi *= 2;
  }
  return brentRoot(f, 0, hi);
}

// ---------------------------------------------------------------- F

double fCdf(double x, double d1, double d2) =>
    x <= 0 ? 0 : betaI(d1 / 2, d2 / 2, d1 * x / (d1 * x + d2));

double fUpper(double x, double d1, double d2) =>
    x <= 0 ? 1 : betaI(d2 / 2, d1 / 2, d2 / (d2 + d1 * x));

double fQuantile(double p, double d1, double d2) {
  if (p <= 0) return 0;
  if (p >= 1) return double.infinity;
  double f(double x) => fCdf(x, d1, d2) - p;
  var hi = 1.0;
  while (f(hi) < 0) {
    hi *= 2;
  }
  return brentRoot(f, 0, hi);
}

// ---------------------------------------------------------------- Bêta

double betaQuantile(double p, double a, double b) {
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  return brentRoot((x) => betaI(a, b, x) - p, 0, 1, tol: 1e-15);
}

// ---------------------------------------------------------------- Binomiale

/// P(X ≤ k) pour X ~ B(n, p).
double binomialCdf(int k, int n, double p) {
  if (k < 0) return 0;
  if (k >= n) return 1;
  return betaIComplement(k + 1.0, (n - k).toDouble(), p);
}

double binomialPmf(int k, int n, double p) {
  if (k < 0 || k > n) return 0;
  if (p == 0) return k == 0 ? 1 : 0;
  if (p == 1) return k == n ? 1 : 0;
  return math.exp(lnChoose(n, k) + k * math.log(p) + (n - k) * math.log(1 - p));
}

/// Test binomial exact bilatéral (méthode de R `binom.test` : somme des
/// probabilités inférieures ou égales à celle de l'observation).
double binomialTestTwoSided(int k, int n, double p0) {
  final d = binomialPmf(k, n, p0);
  const relErr = 1 + 1e-7;
  var total = 0.0;
  for (var i = 0; i <= n; i++) {
    final di = binomialPmf(i, n, p0);
    if (di <= d * relErr) total += di;
  }
  return math.min(1.0, total);
}

// ---------------------------------------------------------------- Hypergéométrique

double hypergeometricPmf(int x, int m, int n, int k) {
  // x succès parmi k tirages, m succès et n échecs dans l'urne (notation de R dhyper).
  if (x < math.max(0, k - n) || x > math.min(k, m)) return 0;
  return math.exp(lnChoose(m, x) + lnChoose(n, k - x) - lnChoose(m + n, k));
}
