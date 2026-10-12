/// Correction des tests multiples (équivalent de `p.adjust` dans R).
library;

import 'dart:math' as math;

import '../i18n.dart';
import 'posthoc.dart' show holm;

enum PAdjust { bonferroni, holm, bh, by }

String pAdjustLabel(PAdjust m) => switch (m) {
      PAdjust.bonferroni => 'Bonferroni',
      PAdjust.holm => 'Holm',
      PAdjust.bh => tr('Benjamini-Hochberg (taux de fausses découvertes)', 'Benjamini-Hochberg (false discovery rate)'),
      PAdjust.by => tr('Benjamini-Yekutieli (FDR, dépendance quelconque)', 'Benjamini-Yekutieli (FDR, arbitrary dependence)'),
    };

/// p ajustés, dans l'ordre des p fournis (valeurs manquantes : NaN conservé).
List<double> pAdjust(List<double> p, PAdjust method) {
  final idx = [for (var i = 0; i < p.length; i++) if (!p[i].isNaN) i];
  final m = idx.length;
  final out = List<double>.filled(p.length, double.nan);
  if (m == 0) return out;
  final pv = [for (final i in idx) p[i]];
  List<double> adj;
  switch (method) {
    case PAdjust.bonferroni:
      adj = [for (final v in pv) math.min(1.0, v * m)];
    case PAdjust.holm:
      adj = holm(pv);
    case PAdjust.bh:
    case PAdjust.by:
      // Pas à pas montant : q_(i) = min_{j ≥ i} (c·m/j)·p_(j), plafonné à 1.
      final c = method == PAdjust.by ? [for (var k = 1; k <= m; k++) 1 / k].fold(0.0, (a, b) => a + b) : 1.0;
      final order = [for (var i = 0; i < m; i++) i]..sort((a, b) {
          final k = pv[a].compareTo(pv[b]);
          return k != 0 ? k : a.compareTo(b);
        });
      adj = List<double>.filled(m, 0);
      var running = double.infinity;
      for (var r = m - 1; r >= 0; r--) {
        running = math.min(running, c * m / (r + 1) * pv[order[r]]);
        adj[order[r]] = math.min(1.0, running);
      }
  }
  for (var k = 0; k < m; k++) {
    out[idx[k]] = adj[k];
  }
  return out;
}
