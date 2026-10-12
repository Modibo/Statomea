/// Lois exactes des statistiques de rang (Mann-Whitney, Wilcoxon signé),
/// par dénombrement, en l'absence d'ex aequo. Équivalent de `pwilcox` et
/// `psignrank` de R.
library;

import 'dart:math' as math;

import '../math/special.dart';

/// P(W ≤ q) pour la statistique W de Mann-Whitney (n1, n2), W ∈ [0, n1·n2].
double pWilcox(int q, int n1, int n2) {
  if (q < 0) return 0;
  final maxW = n1 * n2;
  if (q >= maxW) return 1;
  // f[k][w] = nb de façons d'obtenir w avec k éléments du premier échantillon
  // parmi les i premiers rangs ; récurrence sur le nombre d'éléments.
  // On utilise la fonction génératrice : ∏_{j=1..n1} (1 − x^{n2+j}) / (1 − x^j).
  var poly = List<double>.filled(maxW + 1, 0)..[0] = 1;
  for (var j = 1; j <= n1; j++) {
    // multiplier par (1 − x^{n2+j})
    final m = n2 + j;
    for (var w = maxW; w >= m; w--) {
      poly[w] -= poly[w - m];
    }
    // diviser par (1 − x^j) : somme cumulée de pas j
    for (var w = j; w <= maxW; w++) {
      poly[w] += poly[w - j];
    }
  }
  final total = math.exp(lnChoose(n1 + n2, n1));
  var s = 0.0;
  for (var w = 0; w <= q; w++) {
    s += poly[w];
  }
  return math.min(1.0, s / total);
}

/// P(V ≤ q) pour la statistique V du test signé de Wilcoxon (n paires non nulles).
double pSignRank(int q, int n) {
  if (q < 0) return 0;
  final maxV = n * (n + 1) ~/ 2;
  if (q >= maxV) return 1;
  final c = List<double>.filled(maxV + 1, 0)..[0] = 1;
  for (var k = 1; k <= n; k++) {
    for (var v = maxV; v >= k; v--) {
      c[v] += c[v - k];
    }
  }
  var s = 0.0;
  for (var v = 0; v <= q; v++) {
    s += c[v];
  }
  return math.min(1.0, s / math.pow(2, n));
}
