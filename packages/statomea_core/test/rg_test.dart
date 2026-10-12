import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('rg');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  void same(GeneticCorrelationFit f, Map t, {double rel = 1e-9}) {
    expect(f.used, asD(t['J'])!.round());
    expect(f.blocks, asD(t['B'])!.round());
    expect(f.h2a, closeRel(asD(t['h2_1'])!, rel: rel));
    expect(f.h2b, closeRel(asD(t['h2_2'])!, rel: rel));
    expect(f.result.statistics['intercept_1'], closeRel(asD(t['int_1'])!, rel: rel));
    expect(f.rho, closeRel(asD(t['rho'])!, rel: rel * 100));
    expect(f.rhoG, closeRel(asD(t['rhog'])!, rel: rel));
    expect(f.rg, closeRel(asD(t['rg'])!, rel: rel));
    expect(f.seRho, closeRel(asD(t['se_rho'])!, rel: rel));
    expect(f.seRhoG, closeRel(asD(t['se_rhog'])!, rel: rel));
    expect(f.seRg, closeRel(asD(t['se_rg'])!, rel: rel));
    expect(f.pRg, closeRel(asD(t['p_rg'])!, rel: rel * 10));
  }

  test('validation : deux traits quantitatifs (rg simulée 0,6, corrélation environnementale −0,2) = R', () {
    final g = parsePlinkBed(File('$dir/ldsc.bed').readAsBytesSync(), File('$dir/ldsc.bim').readAsStringSync(), File('$dir/ldsc.fam').readAsStringSync());
    final ell = ldScores(g);
    final f = geneticCorrelation(v(ref['z1']), v(ref['z2']), ell, n: g.sampleCount, m: g.variantCount);
    same(f, ref['valid'] as Map);
    // Sans z signés (z₂ = |z₂|), la covariance perd son sens : le signe compte.
    final abs2 = [for (final z in v(ref['z2'])) z.abs()];
    expect(geneticCorrelation(v(ref['z1']), abs2, ell, n: g.sampleCount, m: g.variantCount).rhoG, isNot(closeTo(f.rhoG, 1e-3)));
  });

  test('chaîne de l\'exemple : deux balayages logistiques (z de Wald) → corrélation génétique = R', () {
    final g = parsePlinkBed(File('$dir/ldsc_app.bed').readAsBytesSync(), File('$dir/ldsc_app.bim').readAsStringSync(), File('$dir/ldsc_app.fam').readAsStringSync());
    final traits = parseCsv(File('$dir/ldsc_app_traits.csv').readAsStringSync()).dataset;
    final cov = {for (final c in ['diabete', 'coronaropathie']) c: {for (var i = 0; i < traits.rowCount; i++) traits.cell(i, 'id')!: traits.cell(i, c)!}};
    final ds = genotypeDataset(g, covariates: cov);
    final names = ds.names.sublist(ds.names.length - g.variantCount);
    final t = ref['app'] as Map;
    final zs = <List<double>>[];
    for (final (trait, key) in [('diabete', 'z1'), ('coronaropathie', 'z2')]) {
      final z = <double>[];
      snpScan(ds, names, trait, 'oui', zOut: z);
      final r = v(t[key]);
      // Le balayage compte l'allèle mineur, R l'allèle A1 : |z| identiques, signe éventuellement inversé.
      for (var j = 0; j < r.length; j++) {
        expect(z[j].abs(), closeRel(r[j].abs(), rel: 1e-6), reason: '$trait ${names[j]}');
      }
      zs.add(z);
    }
    // Même allèle compté dans les deux balayages : les produits z₁z₂ (seuls utiles à rg) sont identiques à R.
    final r1 = v(t['z1']), r2 = v(t['z2']);
    for (var j = 0; j < r1.length; j++) {
      expect(zs[0][j] * zs[1][j], closeRel(r1[j] * r2[j], rel: 2e-6), reason: names[j]);
    }
    final f = geneticCorrelationFromScans(g, zs[0], zs[1], n: g.sampleCount, trait1: 'diabete', trait2: 'coronaropathie');
    same(f, t, rel: 1e-5);
    expect(f.result.methodName, contains('diabete – coronaropathie'));
  });

  test('rg non défini si une héritabilité est ≤ 0 ; trop peu de variants refusé', () {
    final ell = [for (var j = 0; j < 400; j++) 1.0 + (j % 7) / 3];
    final zero = [for (var j = 0; j < 400; j++) (j % 2 == 0 ? 0.3 : -0.3)];
    final f = geneticCorrelation(zero, zero, ell, n: 1000, m: 400);
    expect(f.rg.isNaN, isTrue);
    expect(f.result.checks.firstWhere((c) => c.id == 'h2_signal').status, CheckStatus.violated);
    expect(() => geneticCorrelation(zero.sublist(0, 100), zero.sublist(0, 100), ell.sublist(0, 100), n: 1000, m: 100), throwsA(isA<StatInputError>()));
  });
}
