import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('expression_plan');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final lines = File('test/reference/rnaseq_plan_simule.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
  final genes = [for (final l in lines) l.split(',').first.replaceAll('"', '')];
  final counts = [for (final l in lines) [for (final c in l.split(',').skip(1)) double.parse(c)]];
  final design = ExpressionDesign([for (final g in ref['group'] as List) '$g'],
      factors: {'lot': [for (final b in ref['batch'] as List) '$b']}, covariates: {'rin': v(ref['rin'])});
  final fit = voomLimmaDesign(genes, counts, design, minSamples: 4);

  test('plan ~ groupe + lot + rin : filtre, TMM, poids voom (lowess sur le plan complet)', () {
    expect(fit.genes, ref['kept']);
    expect(fit.coefficientNames, ['(intercept)', 'B', 'C', 'lot=L2', 'rin']);
    expect(fit.normFactors, [for (final x in v(ref['norm_factors'])) closeRel(x, rel: 1e-12)]);
    final w = [for (final r in ref['w_head'] as List) v(r)];
    for (var g = 0; g < 3; g++) {
      expect(fit.weights[g], [for (final x in w[g]) closeRel(x, rel: 1e-9)]);
    }
    expect(fit.dfResidual, 7);
    expect(fit.dfPrior, closeRel(asD(ref['df_prior'])!, rel: 1e-8));
    expect(fit.s2Prior, closeRel(asD(ref['s2_prior'])!, rel: 1e-8));
    expect(fit.dfTotal.first, closeRel(asD(ref['df_total'])!, rel: 1e-8));
  });

  void checkContrast(ExpressionContrast c, Map r) {
    final lfc = v(r['logFC']), t = v(r['t']), p = v(r['p']), adj = v(r['adj']);
    for (var g = 0; g < fit.genes.length; g++) {
      expect(c.logFC[g], closeRel(lfc[g], rel: 1e-8, abs: 1e-10), reason: '${c.name} ${fit.genes[g]}');
      expect(c.t[g], closeRel(t[g], rel: 1e-7, abs: 1e-9), reason: '${c.name} ${fit.genes[g]}');
      expect(c.p[g], closeRel(p[g], rel: 1e-6, abs: 0), reason: '${c.name} ${fit.genes[g]}');
      expect(c.adjP[g], closeRel(adj[g], rel: 1e-6, abs: 0), reason: '${c.name} ${fit.genes[g]}');
    }
  }

  test('contrastes contre la référence (B − A, C − A) = topTable(coef) de limma', () {
    expect(fit.contrasts.map((c) => c.name), ['B − A', 'C − A', 'C − B']);
    checkContrast(fit.contrasts[0], ref['B'] as Map);
    checkContrast(fit.contrasts[1], ref['C'] as Map);
  });

  test('contraste C − B exact = limma après changement de référence', () => checkContrast(fit.contrasts[2], ref['CB'] as Map));

  test('F modéré global exact du groupe (2 ddl) contre calcul R gène par gène', () {
    final f = v(ref['F']), p = v(ref['F_p']), adj = v(ref['F_adj']);
    for (var g = 0; g < fit.genes.length; g++) {
      expect(fit.fStat[g], closeRel(f[g], rel: 1e-7), reason: fit.genes[g]);
      expect(fit.fP[g], closeRel(p[g], rel: 1e-6, abs: 0), reason: fit.genes[g]);
      expect(fit.fAdjP[g], closeRel(adj[g], rel: 1e-6, abs: 0), reason: fit.genes[g]);
    }
  });

  test('résultat présenté : comptes par contraste, F, contrôles du plan', () {
    final r = differentialExpressionDesign(genes, counts, design, minSamples: 4);
    final n = ref['n_sig'] as Map;
    expect([r.statistics['n_sig_c0'], r.statistics['n_sig_c1'], r.statistics['n_sig_c2'], r.statistics['n_sig_f']], [n['B'], n['C'], n['CB'], n['F']]);
    expect(r.checks.firstWhere((c) => c.id == 'batch').status, CheckStatus.ok);
    expect(r.tables.length, 5); // F, 3 contrastes, normalisation
    expect((r.figures['volcano'] as Map)['contrast'], 'B − A');
    final r2 = differentialExpressionDesign(genes, counts, design, minSamples: 4, volcanoContrast: 2);
    expect((r2.figures['volcano'] as Map)['contrast'], 'C − B');
    expect(r2.statistics['n_sig'], n['CB']);
  });

  test('lot confondu avec le groupe : refus explicite ; trop de termes : refus', () {
    final confounded = ExpressionDesign([for (final g in ref['group'] as List) '$g'], factors: {'lot': [for (final g in ref['group'] as List) 'L$g']});
    expect(() => voomLimmaDesign(genes, counts, confounded), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'confounded')));
    final tooMany = ExpressionDesign([for (final g in ref['group'] as List) '$g'],
        covariates: {for (var i = 0; i < 9; i++) 'x$i': [for (var j = 0; j < 12; j++) ((j + 1) * (i + 2) % 7).toDouble()]});
    expect(() => voomLimmaDesign(genes, counts, tooMany), throwsA(isA<StatInputError>()));
  });
}
