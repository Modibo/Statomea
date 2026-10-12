import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('acp');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/strat.bed').readAsBytesSync(), File('$dir/strat.bim').readAsStringSync(), File('$dir/strat.fam').readAsStringSync());
  final pca = genotypePca(g);

  test('élagage LD : mêmes variants retenus que la règle réimplémentée dans R (60 paires corrélées écartées)', () {
    expect(pca.keptVariants, [for (final x in ref['keep'] as List) (x as num).toInt() - 1]);
    expect(pca.result.statistics['variants_pruned'], 60);
  });

  test('ACP : valeurs propres, trace et 10 composantes (signe normalisé) = eigen() de R', () {
    final ev = v(ref['eigenvalues']);
    for (var c = 0; c < 10; c++) {
      expect(pca.eigenvalues[c], closeRel(ev[c], rel: 1e-12), reason: 'λ${c + 1}');
    }
    expect(pca.trace, closeRel(asD(ref['trace'])!, rel: 1e-12));
    final pcs = [for (final r in ref['pcs'] as List) v(r)];
    for (var i = 0; i < 400; i++) {
      for (var c = 0; c < 10; c++) {
        expect(pca.pcs[i][c], closeRel(pcs[i][c], rel: 1e-8, abs: 1e-11), reason: 'sujet $i CP${c + 1}');
      }
    }
  });

  test('CP1 sépare les deux sous-populations ; structure signalée', () {
    final pop = [for (final x in ref['pop'] as List) (x as num).toInt()];
    final pc1 = [for (final r in pca.pcs) r[0]];
    final m1 = [for (var i = 0; i < 400; i++) if (pop[i] == 1) pc1[i]], m2 = [for (var i = 0; i < 400; i++) if (pop[i] == 2) pc1[i]];
    expect((m1.reduce((a, b) => a + b) / m1.length) * (m2.reduce((a, b) => a + b) / m2.length), lessThan(0));
    expect(pca.result.checks.firstWhere((c) => c.id == 'structure').status, CheckStatus.warning);
  });

  test('inflation génomique : λ et p du balayage sans puis avec ajustement sur 2 CP = glm de R', () {
    final snps = [for (final x in g.variants) x.id];
    final base = genotypeDataset(g);
    final r0 = snpScan(base, snps, 'statut', 'cas', covariates: const [TermSpec('sexe', categorical: true, reference: 'H')]);
    expect(r0.statistics['lambda_gc'], closeRel(asD(ref['lambda_unadj'])!, rel: 1e-6));
    expect(r0.checks.firstWhere((c) => c.id == 'stratification').status, CheckStatus.warning);
    final withPc = genotypeDataset(g, covariates: pca.covariates(2));
    final r2 = snpScan(withPc, snps, 'statut', 'cas',
        covariates: const [TermSpec('sexe', categorical: true, reference: 'H'), TermSpec('PC1'), TermSpec('PC2')]);
    expect(r2.statistics['lambda_gc'], closeRel(asD(ref['lambda_pc'])!, rel: 1e-6));
    final p0 = v(ref['p_unadj']), p2 = v(ref['p_pc']);
    for (var j = 0; j < 1000; j++) {
      expect(r0.statistics['p_${snps[j]}'], closeRel(p0[j], rel: 1e-6), reason: snps[j]);
      expect(r2.statistics['p_${snps[j]}'], closeRel(p2[j], rel: 1e-6), reason: snps[j]);
    }
  });

  test('peu de variants : λ non calculé, stratification « non évaluable »', () {
    final r = snpScan(genotypeDataset(g), [for (final x in g.variants.take(20)) x.id], 'statut', 'cas');
    expect(r.statistics.containsKey('lambda_gc'), isFalse);
    expect(r.checks.firstWhere((c) => c.id == 'stratification').status, CheckStatus.notAssessed);
  });
}
