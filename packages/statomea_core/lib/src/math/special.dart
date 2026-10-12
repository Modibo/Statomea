/// Fonctions spéciales utilisées par les lois de probabilité.
///
/// Références : Lanczos (1964) pour log Γ ; Press et al., *Numerical Recipes*
/// 3e éd., §6.2 (gamma incomplète) et §6.4 (bêta incomplète, fraction continue
/// de Lentz). Précision visée : ~1e-14 relative, vérifiée contre R (`pgamma`,
/// `pbeta`) dans `test/special_test.dart`.
library;

import 'dart:math' as math;

import '../i18n.dart';

const double _eps = 1e-16;
const double _fpMin = 1e-300;

const List<double> _lanczos = [
  0.99999999999980993,
  676.5203681218851,
  -1259.1392167224028,
  771.32342877765313,
  -176.61502916214059,
  12.507343278686905,
  -0.13857109526572012,
  9.9843695780195716e-6,
  1.5056327351493116e-7,
];

/// log Γ(x) pour x > 0.
double lnGamma(double x) {
  if (x <= 0) throw ArgumentError(tr('lnGamma : x doit être > 0 (reçu $x)', 'lnGamma: x must be > 0 (got $x)'));
  if (x < 0.5) {
    // Réflexion : Γ(x)Γ(1−x) = π / sin(πx)
    return math.log(math.pi / math.sin(math.pi * x)) - lnGamma(1 - x);
  }
  final z = x - 1;
  var a = _lanczos[0];
  final t = z + 7.5;
  for (var i = 1; i < 9; i++) {
    a += _lanczos[i] / (z + i);
  }
  return 0.5 * math.log(2 * math.pi) + (z + 0.5) * math.log(t) - t + math.log(a);
}

/// log du coefficient binomial C(n, k).
double lnChoose(int n, int k) {
  if (k < 0 || k > n) return double.negativeInfinity;
  return lnGamma(n + 1.0) - lnGamma(k + 1.0) - lnGamma(n - k + 1.0);
}

/// Fonction gamma incomplète régularisée inférieure P(a, x).
double gammaP(double a, double x) {
  if (x < 0 || a <= 0) throw ArgumentError(tr('gammaP : a > 0 et x ≥ 0 requis', 'gammaP: a > 0 and x ≥ 0 required'));
  if (x == 0) return 0;
  if (x < a + 1) return _gammaSeries(a, x);
  return 1 - _gammaContinuedFraction(a, x);
}

/// Fonction gamma incomplète régularisée supérieure Q(a, x) = 1 − P(a, x).
double gammaQ(double a, double x) {
  if (x < 0 || a <= 0) throw ArgumentError(tr('gammaQ : a > 0 et x ≥ 0 requis', 'gammaQ: a > 0 and x ≥ 0 required'));
  if (x == 0) return 1;
  if (x < a + 1) return 1 - _gammaSeries(a, x);
  return _gammaContinuedFraction(a, x);
}

double _gammaSeries(double a, double x) {
  var ap = a;
  var sum = 1 / a;
  var del = sum;
  for (var n = 0; n < 100000; n++) {
    ap += 1;
    del *= x / ap;
    sum += del;
    if (del.abs() < sum.abs() * _eps) break;
  }
  return sum * math.exp(-x + a * math.log(x) - lnGamma(a));
}

double _gammaContinuedFraction(double a, double x) {
  var b = x + 1 - a;
  var c = 1 / _fpMin;
  var d = 1 / b;
  var h = d;
  for (var i = 1; i < 100000; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < _fpMin) d = _fpMin;
    c = b + an / c;
    if (c.abs() < _fpMin) c = _fpMin;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < _eps) break;
  }
  return math.exp(-x + a * math.log(x) - lnGamma(a)) * h;
}

/// Fonction bêta incomplète régularisée I_x(a, b).
double betaI(double a, double b, double x) {
  if (a <= 0 || b <= 0) throw ArgumentError(tr('betaI : a, b > 0 requis', 'betaI: a, b > 0 required'));
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final lnFront = lnGamma(a + b) - lnGamma(a) - lnGamma(b) +
      a * math.log(x) + b * math.log(1 - x);
  if (x < (a + 1) / (a + b + 2)) {
    return math.exp(lnFront) * _betaCf(a, b, x) / a;
  }
  return 1 - math.exp(lnFront) * _betaCf(b, a, 1 - x) / b;
}

/// 1 − I_x(a, b), calculé sans perte de précision dans la queue supérieure.
double betaIComplement(double a, double b, double x) => betaI(b, a, 1 - x);

double _betaCf(double a, double b, double x) {
  final qab = a + b;
  final qap = a + 1;
  final qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < _fpMin) d = _fpMin;
  d = 1 / d;
  var h = d;
  for (var m = 1; m < 100000; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < _fpMin) d = _fpMin;
    c = 1 + aa / c;
    if (c.abs() < _fpMin) c = _fpMin;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < _fpMin) d = _fpMin;
    c = 1 + aa / c;
    if (c.abs() < _fpMin) c = _fpMin;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < _eps) break;
  }
  return h;
}

/// Fonction d'erreur complémentaire, via Q(1/2, x²).
double erfc(double x) {
  if (x >= 0) return gammaQ(0.5, x * x);
  return 2 - gammaQ(0.5, x * x);
}

/// Racine d'une fonction monotone sur [lo, hi] par bissection sécurisée par
/// la méthode de Brent. [f] doit changer de signe sur l'intervalle.
double brentRoot(double Function(double) f, double lo, double hi,
    {double tol = 1e-14, int maxIter = 500}) {
  var a = lo, b = hi;
  var fa = f(a), fb = f(b);
  if (fa == 0) return a;
  if (fb == 0) return b;
  if (fa * fb > 0) {
    throw StateError(tr('brentRoot : pas de changement de signe sur [$lo, $hi]', 'brentRoot: no sign change on [$lo, $hi]'));
  }
  var c = a, fc = fa, d = b - a, e = d;
  for (var i = 0; i < maxIter; i++) {
    if (fb * fc > 0) {
      c = a;
      fc = fa;
      d = b - a;
      e = d;
    }
    if (fc.abs() < fb.abs()) {
      a = b;
      b = c;
      c = a;
      fa = fb;
      fb = fc;
      fc = fa;
    }
    final tol1 = 2 * 2.2e-16 * b.abs() + 0.5 * tol;
    final xm = 0.5 * (c - b);
    if (xm.abs() <= tol1 || fb == 0) return b;
    if (e.abs() >= tol1 && fa.abs() > fb.abs()) {
      final s = fb / fa;
      double p, q;
      if (a == c) {
        p = 2 * xm * s;
        q = 1 - s;
      } else {
        final qq = fa / fc;
        final r = fb / fc;
        p = s * (2 * xm * qq * (qq - r) - (b - a) * (r - 1));
        q = (qq - 1) * (r - 1) * (s - 1);
      }
      if (p > 0) q = -q;
      p = p.abs();
      final min1 = 3 * xm * q - (tol1 * q).abs();
      final min2 = (e * q).abs();
      if (2 * p < (min1 < min2 ? min1 : min2)) {
        e = d;
        d = p / q;
      } else {
        d = xm;
        e = d;
      }
    } else {
      d = xm;
      e = d;
    }
    a = b;
    fa = fb;
    b += d.abs() > tol1 ? d : (xm >= 0 ? tol1 : -tol1);
    fb = f(b);
  }
  return b;
}

/// Fonctions polygamma ψ⁽ᵏ⁾(x), k = 0 (digamma), 1 (trigamma), 2 (tétragamma), x > 0 :
/// récurrence jusqu'à x ≥ 10, puis développement asymptotique (nombres de Bernoulli).
double _polygamma(int k, double x) {
  if (!(x > 0)) throw ArgumentError(tr('polygamma : x doit être > 0', 'polygamma: x must be > 0'));
  var acc = 0.0;
  while (x < 10) {
    // ψ⁽ᵏ⁾(x) = ψ⁽ᵏ⁾(x + 1) − (−1)^k k! / x^(k+1)
    acc -= switch (k) { 0 => 1 / x, 1 => -1 / (x * x), _ => 2 / (x * x * x) };
    x += 1;
  }
  const b = [1 / 6, -1 / 30, 1 / 42, -1 / 30, 5 / 66, -691 / 2730, 7 / 6, -3617 / 510];
  final x2 = x * x;
  switch (k) {
    case 0:
      var s = math.log(x) - 1 / (2 * x);
      var p = x2;
      for (var j = 1; j <= b.length; j++) {
        s -= b[j - 1] / (2 * j * p);
        p *= x2;
      }
      return acc + s;
    case 1:
      var s = 1 / x + 1 / (2 * x2);
      var p = x2 * x;
      for (var j = 1; j <= b.length; j++) {
        s += b[j - 1] / p;
        p *= x2;
      }
      return acc + s;
    default:
      var s = -1 / x2 - 1 / (x2 * x);
      var p = x2 * x2;
      for (var j = 1; j <= b.length; j++) {
        s -= b[j - 1] * (2 * j + 1) / p;
        p *= x2;
      }
      return acc + s;
  }
}

double digamma(double x) => _polygamma(0, x);
double trigamma(double x) => _polygamma(1, x);
double tetragamma(double x) => _polygamma(2, x);

// --- Arithmétique double-double (Dekker 1971, Knuth) pour un log2 correctement arrondi.
(double, double) _twoSum(double a, double b) {
  final s = a + b, bb = s - a;
  return (s, (a - (s - bb)) + (b - bb));
}

(double, double) _twoProd(double a, double b) {
  const split = 134217729.0; // 2^27 + 1
  final p = a * b;
  final ca = split * a, ah = ca - (ca - a), al = a - ah;
  final cb = split * b, bh = cb - (cb - b), bl = b - bh;
  return (p, ((ah * bh - p) + ah * bl + al * bh) + al * bl);
}

/// log2(x) correctement arrondi (sauf cas pathologiques), comme `log2` de la libm qu'appelle R.
/// `log(x)/ln 2` diffère souvent d'une unité au dernier rang : sans effet sur une valeur, mais décisif quand on
/// classe des valeurs presque égales (rangs de la troncature TMM). Réduction x = m·2^e, m ∈ [√½, √2) ;
/// ln m = 2·atanh(s), s = (m − 1)/(m + 1), calculés en double-double ; produit par 1/ln 2 en double-double.
double log2(double x) {
  if (!(x > 0) || x.isInfinite) return math.log(x) / math.ln2;
  var e = (math.log(x) / math.ln2).floor();
  var m = x / math.pow(2.0, e); // division exacte par une puissance de 2 (hors sous-normaux extrêmes)
  while (m >= 2) {
    m /= 2;
    e++;
  }
  while (m < 1) {
    m *= 2;
    e--;
  }
  if (m > math.sqrt2) {
    m /= 2;
    e++;
  }
  final num = m - 1; // exact (Sterbenz)
  final (dh, dl) = _twoSum(m, 1);
  final q1 = num / dh;
  final (ph, pl) = _twoProd(q1, dh);
  final q2 = ((num - ph) - pl - q1 * dl) / dh;
  final t = q1 * q1;
  var poly = 1 / 25;
  for (var k = 23; k >= 3; k -= 2) {
    poly = 1 / k + t * poly;
  }
  final tail = q1 * t * poly;
  final lh = 2 * q1, ll = 2 * (q2 + tail);
  const ih = 1.4426950408889634, il = 2.0355273740931033e-17; // 1/ln 2 en double-double
  final (rh, rl0) = _twoProd(lh, ih);
  final rl = rl0 + lh * il + ll * ih;
  final (sh, sl) = _twoSum(e.toDouble(), rh);
  return sh + (sl + rl);
}
