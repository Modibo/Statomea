import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('expression');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final lines = File('test/reference/rnaseq_simule.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
  final genes = [for (final l in lines) l.split(',').first.replaceAll('"', '')];
  final counts = [for (final l in lines) [for (final c in l.split(',').skip(1)) double.parse(c)]];
  final treated = [false, false, false, false, true, true, true, true];
  final fit = voomLimma(genes, counts, treated, minSamples: 4);

  test('filtre CPM et tailles de librairie', () {
    expect(fit.genes, ref['kept']);
    expect(fit.libSize, [for (final x in v(ref['lib_size'])) closeRel(x, rel: 1e-14)]);
  });

  test('facteurs TMM contre edgeR::calcNormFactors', () {
    expect(fit.normFactors, [for (final x in v(ref['norm_factors'])) closeRel(x, rel: 1e-12)]);
  });

  test('voom : log-CPM et poids (lowess) contre limma::voom', () {
    // Matrices 5 × 8 sérialisées ligne par ligne (une liste par gène).
    final e = [for (final r in ref['E_head'] as List) v(r)], w = [for (final r in ref['w_head'] as List) v(r)];
    for (var g = 0; g < 5; g++) {
      for (var j = 0; j < 8; j++) {
        expect(fit.logCpm[g][j], closeRel(e[g][j], rel: 1e-12));
        expect(fit.weights[g][j], closeRel(w[g][j], rel: 1e-9));
      }
    }
  });

  test('eBayes : loi a priori, t modérés, p, FDR contre limma', () {
    expect(fit.dfPrior, closeRel(asD(ref['df_prior'])!, rel: 1e-8));
    expect(fit.s2Prior, closeRel(asD(ref['s2_prior'])!, rel: 1e-8));
    final lfc = v(ref['logFC']), ae = v(ref['AveExpr']), t = v(ref['t']), p = v(ref['p']), adj = v(ref['adj']);
    for (var g = 0; g < fit.genes.length; g++) {
      expect(fit.logFC[g], closeRel(lfc[g], rel: 1e-9, abs: 1e-11), reason: fit.genes[g]);
      expect(fit.aveExpr[g], closeRel(ae[g], rel: 1e-12), reason: fit.genes[g]);
      expect(fit.t[g], closeRel(t[g], rel: 1e-8, abs: 1e-10), reason: fit.genes[g]);
      expect(fit.p[g], closeRel(p[g], rel: 1e-7), reason: fit.genes[g]);
      expect(fit.adjP[g], closeRel(adj[g], rel: 1e-7), reason: fit.genes[g]);
    }
  });

  test('résultat présenté : nombre de gènes significatifs, volcano', () {
    final r = differentialExpression(genes, counts, treated, minSamples: 4);
    expect(r.statistics['n_sig'], asD(ref['n_sig']));
    final truth = (ref['truth_de'] as List).toSet();
    final vol = r.figures['volcano'] as Map;
    final declared = [for (var g = 0; g < fit.genes.length; g++) if ((vol['significant'] as List)[g] == true) fit.genes[g]];
    // Les gènes déclarés sont très majoritairement de vrais gènes DE (FDR nominal 5 %).
    expect(declared.where(truth.contains).length / declared.length, greaterThan(0.85));
  });

  test('lowess contre R (ex æquo, robustesse, f = 2/3 et 0,3)', () {
    final l = ref['lowess'] as Map;
    final a = lowess(v(l['x']), v(l['y']));
    expect(a.x, v(l['xs']));
    expect(a.y, [for (final x in v(l['f23'])) closeRel(x, rel: 1e-12, abs: 1e-13)]);
    final b = lowess(v(l['x']), v(l['y']), f: 0.3, iter: 0);
    expect(b.y, [for (final x in v(l['f03'])) closeRel(x, rel: 1e-12, abs: 1e-13)]);
  });
}
