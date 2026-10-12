import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('lmm');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/lmm.bed').readAsBytesSync(), File('$dir/lmm.bim').readAsStringSync(), File('$dir/lmm.fam').readAsStringSync());
  final ph = parseCsv(File('$dir/lmm_phenotypes.csv').readAsStringSync()).dataset;
  final trait = {for (var i = 0; i < ph.rowCount; i++) ph.cell(i, 'id')!: double.parse(ph.cell(i, 'trait')!)};
  final age = {for (var i = 0; i < ph.rowCount; i++) ph.cell(i, 'id')!: ph.cell(i, 'age')};
  final y = [for (final s in g.samples) trait[s]];
  final sexe = LmmCovariate('sexe', [for (final s in g.sex) s == 1 ? 'H' : 'F'], categorical: true, reference: 'H');

  test('sexe en effet fixe : composantes de variance et p = rrBLUP 4.6 (GWAS P3D) et recalcul serré', () {
    final r = lmmScan(g, y, covariates: [sexe]);
    final t = ref['sexe'] as Map;
    // Optimum REML plat : deux optimiseurs (Brent dans R, section dorée ici) s'arrêtent à ~1e-8 près de λ.
    expect(r.lambda, closeRel(asD(t['lambda'])!, rel: 1e-6));
    expect(r.vu, closeRel(asD(t['Vu'])!, rel: 1e-6));
    expect(r.ve, closeRel(asD(t['Ve'])!, rel: 1e-6));
    expect(r.vu, closeRel(asD(ref['rrblup_Vu'])!, rel: 1e-5)); // rrBLUP : optimize à tolérance par défaut
    final pT = v(t['p']), pR = v(ref['p_rrblup']);
    for (var j = 0; j < 1500; j++) {
      expect(r.p[j], closeRel(pT[j], rel: 1e-7), reason: 'serré ${r.variants[j]}');
      expect(r.p[j], closeRel(pR[j], rel: 1e-4), reason: 'rrBLUP ${r.variants[j]}');
    }
  });

  test('sexe + âge (covariable numérique) : recalcul serré ; λ_GC et variant causal', () {
    final r = lmmScan(g, y, covariates: [sexe, LmmCovariate('age', [for (final s in g.samples) age[s]])], positions: {for (final x in g.variants) x.id: (x.chrom, x.pos)});
    final t = ref['full'] as Map;
    expect(r.lambda, closeRel(asD(t['lambda'])!, rel: 1e-6));
    final pT = v(t['p']);
    for (var j = 0; j < 1500; j++) {
      expect(r.p[j], closeRel(pT[j], rel: 1e-7), reason: r.variants[j]);
    }
    expect(r.result.statistics['lambda_gc'], closeRel(asD(t['gc'])!, rel: 1e-6));
    expect(r.result.estimates[1].label, contains(ref['causal']));
    expect(r.result.figures['manhattan'], isNotNull);
    expect(r.h2, inInclusiveRange(0.3, 0.8));
  });

  test('sujets incomplets écartés ; trop peu de sujets refusés', () {
    final y2 = [...y];
    y2[0] = null;
    expect(lmmScan(g, y2, covariates: [sexe]).result.inputs['samples'], 599);
    expect(() => lmmScan(g.subset(sampleIdx: [for (var i = 0; i < 10; i++) i]), y.sublist(0, 10)), throwsA(isA<StatInputError>()));
  });

  test('LOCO : K sans le chromosome testé, REML par chromosome = recalcul R (31_loco.R)', () {
    final loco = loadRef('lmm_loco');
    final r = lmmScan(g, y, covariates: [sexe, LmmCovariate('age', [for (final s in g.samples) age[s]])], loco: true);
    final lc = v(loco['lambda_by_chrom']);
    for (var c = 0; c < 3; c++) {
      expect(r.result.statistics['lambda_reml_chr${c + 1}'], closeRel(lc[c], rel: 1e-6), reason: 'chromosome ${c + 1}');
    }
    final pT = v(loco['p']);
    for (var j = 0; j < 1500; j++) {
      expect(r.p[j], closeRel(pT[j], rel: 1e-6), reason: r.variants[j]);
    }
    expect(r.result.statistics['lambda_gc'], closeRel(asD(loco['gc'])!, rel: 1e-6));
    expect(r.result.checks.firstWhere((c) => c.id == 'proximal').status, CheckStatus.ok);
    expect(() => lmmScan(g.subset(variantIdx: [for (var j = 0; j < 400; j++) j]), y, loco: true), throwsA(isA<StatInputError>()));
  });
}
