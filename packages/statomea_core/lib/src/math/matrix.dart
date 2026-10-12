/// Algèbre linéaire dense minimale (matrices de petite dimension : modèles à
/// quelques dizaines de paramètres au plus).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';

class Matrix {
  final int rows;
  final int cols;
  final List<double> data; // stockage par lignes

  Matrix(this.rows, this.cols) : data = Float64List(rows * cols); // doubles non boxés
  Matrix._(this.rows, this.cols, this.data);

  factory Matrix.fromRows(List<List<double>> r) {
    final m = Matrix(r.length, r.isEmpty ? 0 : r.first.length);
    for (var i = 0; i < m.rows; i++) {
      if (r[i].length != m.cols) throw ArgumentError(tr('lignes de longueurs inégales', 'rows of unequal lengths'));
      for (var j = 0; j < m.cols; j++) {
        m.data[i * m.cols + j] = r[i][j];
      }
    }
    return m;
  }

  factory Matrix.identity(int n) {
    final m = Matrix(n, n);
    for (var i = 0; i < n; i++) {
      m.data[i * n + i] = 1;
    }
    return m;
  }

  double get(int i, int j) => data[i * cols + j];
  void set(int i, int j, double v) => data[i * cols + j] = v;

  Matrix copy() => Matrix._(rows, cols, List<double>.of(data));

  Matrix transpose() {
    final t = Matrix(cols, rows);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        t.data[j * rows + i] = data[i * cols + j];
      }
    }
    return t;
  }

  Matrix operator *(Matrix o) {
    if (cols != o.rows) throw ArgumentError(tr('dimensions incompatibles', 'incompatible dimensions'));
    final r = Matrix(rows, o.cols);
    for (var i = 0; i < rows; i++) {
      for (var k = 0; k < cols; k++) {
        final a = data[i * cols + k];
        if (a == 0) continue;
        for (var j = 0; j < o.cols; j++) {
          r.data[i * o.cols + j] += a * o.data[k * o.cols + j];
        }
      }
    }
    return r;
  }

  List<double> multiplyVector(List<double> v) {
    final r = List<double>.filled(rows, 0);
    for (var i = 0; i < rows; i++) {
      var s = 0.0;
      for (var j = 0; j < cols; j++) {
        s += data[i * cols + j] * v[j];
      }
      r[i] = s;
    }
    return r;
  }

  List<double> diagonal() => [for (var i = 0; i < math.min(rows, cols); i++) get(i, i)];

  List<List<double>> toRows() =>
      [for (var i = 0; i < rows; i++) [for (var j = 0; j < cols; j++) get(i, j)]];
}

/// Calcule XᵀWX pour un vecteur de poids W (diagonal).
Matrix crossprodWeighted(List<List<double>> x, List<double> w) {
  final p = x.first.length;
  final m = Matrix(p, p);
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final wi = w[i];
    if (wi == 0) continue;
    for (var a = 0; a < p; a++) {
      final xa = xi[a] * wi;
      if (xa == 0) continue;
      for (var b = a; b < p; b++) {
        m.data[a * p + b] += xa * xi[b];
      }
    }
  }
  for (var a = 0; a < p; a++) {
    for (var b = 0; b < a; b++) {
      m.data[a * p + b] = m.data[b * p + a];
    }
  }
  return m;
}

/// Décomposition de Cholesky A = L Lᵀ. Retourne null si A n'est pas définie
/// positive (à la précision numérique près).
Matrix? cholesky(Matrix a) {
  final n = a.rows;
  final l = Matrix(n, n);
  for (var j = 0; j < n; j++) {
    var s = a.get(j, j);
    for (var k = 0; k < j; k++) {
      s -= l.get(j, k) * l.get(j, k);
    }
    if (s <= 1e-13 * (a.get(j, j).abs() + 1e-300)) return null;
    final d = math.sqrt(s);
    l.set(j, j, d);
    for (var i = j + 1; i < n; i++) {
      var t = a.get(i, j);
      for (var k = 0; k < j; k++) {
        t -= l.get(i, k) * l.get(j, k);
      }
      l.set(i, j, t / d);
    }
  }
  return l;
}

/// Inverse d'une matrice symétrique définie positive. Null si singulière.
Matrix? invertSpd(Matrix a) {
  final l = cholesky(a);
  if (l == null) return null;
  final n = a.rows;
  // Inverse de L (triangulaire inférieure)
  final li = Matrix(n, n);
  for (var i = 0; i < n; i++) {
    li.set(i, i, 1 / l.get(i, i));
    for (var j = 0; j < i; j++) {
      var s = 0.0;
      for (var k = j; k < i; k++) {
        s -= l.get(i, k) * li.get(k, j);
      }
      li.set(i, j, s / l.get(i, i));
    }
  }
  return li.transpose() * li;
}

/// Résout A x = b pour A symétrique définie positive.
List<double>? solveSpd(Matrix a, List<double> b) {
  final l = cholesky(a);
  if (l == null) return null;
  final n = a.rows;
  final y = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var s = b[i];
    for (var k = 0; k < i; k++) {
      s -= l.get(i, k) * y[k];
    }
    y[i] = s / l.get(i, i);
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = y[i];
    for (var k = i + 1; k < n; k++) {
      s -= l.get(k, i) * x[k];
    }
    x[i] = s / l.get(i, i);
  }
  return x;
}

/// log du déterminant d'une matrice symétrique définie positive.
double? logDetSpd(Matrix a) {
  final l = cholesky(a);
  if (l == null) return null;
  var s = 0.0;
  for (var i = 0; i < a.rows; i++) {
    s += math.log(l.get(i, i));
  }
  return 2 * s;
}

/// Résultat d'une factorisation QR de Householder avec détection du rang.
class QrResult {
  final Matrix r; // p × p triangulaire supérieure
  final List<double> qtY; // Qᵀy (n)
  final int rank;
  final List<int> aliased; // colonnes linéairement dépendantes des précédentes
  QrResult(this.r, this.qtY, this.rank, this.aliased);
}

/// Factorisation QR de Householder de X (n × p), appliquée simultanément à y.
/// Une colonne dont la norme résiduelle est < tol × norme initiale est
/// déclarée colinéaire (convention proche de `lm` dans R, tol = 1e-7).
QrResult householderQr(List<List<double>> x, List<double> y, {double tol = 1e-7}) {
  final n = x.length;
  final p = x.first.length;
  final a = [for (final row in x) List<double>.of(row)];
  final b = List<double>.of(y);
  final colNorm0 = List<double>.generate(p, (j) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i][j] * a[i][j];
    }
    return math.sqrt(s);
  });
  final aliased = <int>[];
  final kept = <int>[];
  var k = 0; // ligne de pivot courante
  for (var j = 0; j < p; j++) {
    var norm = 0.0;
    for (var i = k; i < n; i++) {
      norm += a[i][j] * a[i][j];
    }
    norm = math.sqrt(norm);
    if (k >= n || norm <= tol * (colNorm0[j] == 0 ? 1 : colNorm0[j]) || colNorm0[j] == 0) {
      aliased.add(j);
      continue;
    }
    final alpha = a[k][j] > 0 ? -norm : norm;
    final v = List<double>.filled(n, 0);
    v[k] = a[k][j] - alpha;
    for (var i = k + 1; i < n; i++) {
      v[i] = a[i][j];
    }
    var vnorm2 = 0.0;
    for (var i = k; i < n; i++) {
      vnorm2 += v[i] * v[i];
    }
    if (vnorm2 > 0) {
      for (var c = j; c < p; c++) {
        var s = 0.0;
        for (var i = k; i < n; i++) {
          s += v[i] * a[i][c];
        }
        final f = 2 * s / vnorm2;
        for (var i = k; i < n; i++) {
          a[i][c] -= f * v[i];
        }
      }
      var s = 0.0;
      for (var i = k; i < n; i++) {
        s += v[i] * b[i];
      }
      final f = 2 * s / vnorm2;
      for (var i = k; i < n; i++) {
        b[i] -= f * v[i];
      }
    }
    kept.add(j);
    k++;
  }
  final rank = kept.length;
  final r = Matrix(rank, rank);
  for (var row = 0; row < rank; row++) {
    for (var c = 0; c < rank; c++) {
      r.set(row, c, a[row][kept[c]]);
    }
  }
  return QrResult(r, b, rank, aliased);
}

/// Résout R β = c pour R triangulaire supérieure.
List<double> backSolve(Matrix r, List<double> c) {
  final n = r.rows;
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = c[i];
    for (var k = i + 1; k < n; k++) {
      s -= r.get(i, k) * x[k];
    }
    x[i] = s / r.get(i, i);
  }
  return x;
}

/// (RᵀR)⁻¹ pour R triangulaire supérieure inversible.
Matrix invertRtR(Matrix r) {
  final n = r.rows;
  final ri = Matrix(n, n);
  for (var i = n - 1; i >= 0; i--) {
    ri.set(i, i, 1 / r.get(i, i));
    for (var j = i + 1; j < n; j++) {
      var s = 0.0;
      for (var k = i + 1; k <= j; k++) {
        s -= r.get(i, k) * ri.get(k, j);
      }
      ri.set(i, j, s / r.get(i, i));
    }
  }
  return ri * ri.transpose();
}

// Boucles internes de tred2 en petites fonctions : appelées O(n²) fois, elles sont vite optimisées par le compilateur
// JIT (tests, `dart run`), alors qu'un unique appel long ne l'est que partiellement. Arithmétique inchangée.
double _tredDot(Float64List tj, Float64List d, Float64List e, int j, int i, double f, double g0) {
  var g = g0;
  for (var k = j + 1; k <= i - 1; k++) {
    g += tj[k] * d[k];
    e[k] += tj[k] * f;
  }
  return g;
}

void _tredRank2(Float64List tj, Float64List d, Float64List e, int j, int i, double f, double g) {
  for (var k = j; k <= i - 1; k++) {
    tj[k] -= f * e[k] + g * d[k];
  }
}

void _tredAccumulate(Float64List ti1, Float64List tj, Float64List d, int i) {
  var g = 0.0;
  for (var k = 0; k <= i; k++) {
    g += ti1[k] * tj[k];
  }
  for (var k = 0; k <= i; k++) {
    tj[k] -= g * d[k];
  }
}

/// Décomposition propre complète d'une matrice symétrique : tridiagonalisation de Householder puis QL implicite
/// (algorithmes tred2/tql2 d'EISPACK, tels que dans JAMA). Valeurs propres décroissantes ; [vectors] en colonnes
/// (vectors[i][k] = composante i du k-ième vecteur propre). Coût O(n³) : à réserver à n ≤ quelques milliers.
({List<double> values, List<List<double>> vectors}) symmetricEigen(List<List<double>> a) {
  final n = a.length;
  // tred2 d'EISPACK/JAMA parcourt V par colonnes : on travaille sur t = Vᵀ (t[c][r] = V[r][c]), lignes Float64List
  // contiguës ; arithmétique et ordre des opérations inchangés. Les lignes de t sont ensuite les colonnes attendues par tql2.
  final t = [for (var c = 0; c < n; c++) Float64List.fromList([for (var r = 0; r < n; r++) a[r][c]])];
  final d = Float64List(n), e = Float64List(n);
  double hypot(double x, double y) => math.sqrt(x * x + y * y);
  // tred2
  for (var j = 0; j < n; j++) {
    d[j] = t[j][n - 1];
  }
  for (var i = n - 1; i > 0; i--) {
    var scale = 0.0, h = 0.0;
    for (var k = 0; k < i; k++) {
      scale += d[k].abs();
    }
    if (scale == 0.0) {
      e[i] = d[i - 1];
      for (var j = 0; j < i; j++) {
        d[j] = t[j][i - 1];
        t[j][i] = 0;
        t[i][j] = 0;
      }
    } else {
      for (var k = 0; k < i; k++) {
        d[k] /= scale;
        h += d[k] * d[k];
      }
      var f = d[i - 1];
      var g = math.sqrt(h);
      if (f > 0) g = -g;
      e[i] = scale * g;
      h -= f * g;
      d[i - 1] = f - g;
      for (var j = 0; j < i; j++) {
        e[j] = 0;
      }
      for (var j = 0; j < i; j++) {
        f = d[j];
        t[i][j] = f;
        e[j] = _tredDot(t[j], d, e, j, i, f, e[j] + t[j][j] * f);
      }
      f = 0;
      for (var j = 0; j < i; j++) {
        e[j] /= h;
        f += e[j] * d[j];
      }
      final hh = f / (h + h);
      for (var j = 0; j < i; j++) {
        e[j] -= hh * d[j];
      }
      for (var j = 0; j < i; j++) {
        _tredRank2(t[j], d, e, j, i, d[j], e[j]);
        d[j] = t[j][i - 1];
        t[j][i] = 0;
      }
    }
    d[i] = h;
  }
  for (var i = 0; i < n - 1; i++) {
    t[i][n - 1] = t[i][i];
    t[i][i] = 1;
    final h = d[i + 1];
    if (h != 0.0) {
      for (var k = 0; k <= i; k++) {
        d[k] = t[i + 1][k] / h;
      }
      for (var j = 0; j <= i; j++) {
        _tredAccumulate(t[i + 1], t[j], d, i);
      }
    }
    for (var k = 0; k <= i; k++) {
      t[i + 1][k] = 0;
    }
  }
  for (var j = 0; j < n; j++) {
    d[j] = t[j][n - 1];
    t[j][n - 1] = 0;
  }
  t[n - 1][n - 1] = 1;
  e[0] = 0;
  // tql2. Les rotations agissent sur les colonnes i et i + 1 de V, c'est-à-dire sur les lignes de t = Vᵀ.
  final w = t;
  for (var i = 1; i < n; i++) {
    e[i - 1] = e[i];
  }
  e[n - 1] = 0;
  var f = 0.0, tst1 = 0.0;
  const eps = 2.220446049250313e-16;
  for (var l = 0; l < n; l++) {
    tst1 = math.max(tst1, d[l].abs() + e[l].abs());
    var m = l;
    while (m < n) {
      if (e[m].abs() <= eps * tst1) break;
      m++;
    }
    if (m > l) {
      do {
        var g = d[l];
        var p = (d[l + 1] - g) / (2 * e[l]);
        var r = hypot(p, 1);
        if (p < 0) r = -r;
        d[l] = e[l] / (p + r);
        d[l + 1] = e[l] * (p + r);
        final dl1 = d[l + 1];
        var h = g - d[l];
        for (var i = l + 2; i < n; i++) {
          d[i] -= h;
        }
        f += h;
        p = d[m];
        var c = 1.0, c2 = c, c3 = c;
        final el1 = e[l + 1];
        var s = 0.0, s2 = 0.0;
        for (var i = m - 1; i >= l; i--) {
          c3 = c2;
          c2 = c;
          s2 = s;
          g = c * e[i];
          h = c * p;
          r = hypot(p, e[i]);
          e[i + 1] = s * r;
          s = e[i] / r;
          c = p / r;
          p = c * d[i] - s * g;
          d[i + 1] = h + s * (c * g + s * d[i]);
          final wi = w[i], wi1 = w[i + 1];
          for (var k = 0; k < n; k++) {
            h = wi1[k];
            wi1[k] = s * wi[k] + c * h;
            wi[k] = c * wi[k] - s * h;
          }
        }
        p = -s * s2 * c3 * el1 * e[l] / dl1;
        e[l] = s * p;
        d[l] = c * p;
      } while (e[l].abs() > eps * tst1);
    }
    d[l] += f;
    e[l] = 0;
  }
  final order = [for (var i = 0; i < n; i++) i]..sort((x, y) => d[y].compareTo(d[x]));
  return (values: [for (final i in order) d[i]], vectors: [for (var r = 0; r < n; r++) [for (final i in order) w[i][r]]]);
}
