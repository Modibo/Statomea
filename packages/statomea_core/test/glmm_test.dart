import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('glmm');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/lmm.bed').readAsBytesSync(), File('$dir/lmm.bim').readAsStringSync(), File('$dir/lmm.fam').readAsStringSync());
  final ph = parseCsv(File('$dir/lmm_phenotypes.csv').readAsStringSync()).dataset;
  final dis = parseCsv(File('$dir/glmm_phenotypes.csv').readAsStringSync()).dataset;
  final age = {for (var i = 0; i < ph.rowCount; i++) ph.cell(i, 'id')!: ph.cell(i, 'age')};
  final ill = {for (var i = 0; i < dis.rowCount; i++) dis.cell(i, 'id')!: dis.cell(i, 'maladie') == 'oui' ? 1.0 : 0.0};
  final y = [for (final s in g.samples) ill[s]];
  final cov = [
    LmmCovariate('sexe', [for (final s in g.sex) s == 1 ? 'H' : 'F'], categorical: true, reference: 'H'),
    LmmCovariate('age', [for (final s in g.samples) age[s]]),
  ];
  final r = glmmScan(g, y, covariates: cov, positions: {for (final x in g.variants) x.id: (x.chrom, x.pos)});

  test('modèle nul PQL : τ et α = recalcul R serré (1e-6) et GMMAT 1.4.2 (tolérance 1e-5 de glmmkin)', () {
    expect(r.tau, closeRel(asD(ref['tau'])!, rel: 1e-6));
    final a = v(ref['alpha']);
    for (var j = 0; j < 3; j++) {
      expect(r.alpha[j], closeRel(a[j], rel: 1e-6));
    }
    expect(r.tau, closeRel(asD(ref['gmmat_tau'])!, rel: 1e-4));
    expect(r.result.checks.firstWhere((c) => c.id == 'convergence').status, CheckStatus.ok);
  });

  test('tests du score des 1 500 variants : U, V, p = recalcul serré ; p = GMMAT', () {
    final u = v(ref['U']), vv = v(ref['V']), p = v(ref['p']), pg = v(ref['p_gmmat']);
    expect(r.p.length, 1500);
    for (var j = 0; j < 1500; j++) {
      expect(r.score[j], closeRel(u[j], rel: 1e-6, abs: 1e-6), reason: r.variants[j]);
      expect(r.variance[j], closeRel(vv[j], rel: 1e-6), reason: r.variants[j]);
      expect(r.p[j], closeRel(p[j], rel: 1e-5), reason: r.variants[j]);
      expect(r.p[j], closeRel(pg[j], rel: 1e-3), reason: 'GMMAT ${r.variants[j]}');
    }
  });

  test('apparentés : λ ≈ 1 avec le modèle mixte (la logistique ordinaire donnait ≈ 1,55)', () {
    expect(r.result.statistics['lambda_gc'], closeRel(asD(ref['gc_glmm'])!, rel: 1e-5));
    expect(asD(ref['gc_naive'])!, greaterThan(1.4));
    expect(r.result.checks.firstWhere((c) => c.id == 'inflation').status, CheckStatus.ok);
    expect(r.result.figures['qq'], isNotNull);
  });

  test('issue non binaire refusée', () {
    expect(() => glmmScan(g, [for (var i = 0; i < g.sampleCount; i++) i.toDouble()]), throwsA(isA<StatInputError>()));
  });
}
