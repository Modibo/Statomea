import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('mr_steiger');
  final ds = parseCsv(File('test/reference/mr_bidirectionnel_simule.csv').readAsStringSync()).dataset;
  List<double> col(String c, String set) => [for (var i = 0; i < ds.rowCount; i++) if (ds.cell(i, 'instrument') == set) double.parse(ds.cell(i, c)!)];
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final nX = asD(ref['nX'])!.round(), nY = asD(ref['nY'])!.round();
  final s = steigerDirectionality(col('beta_x', 'X'), col('se_x', 'X'), col('beta_y', 'X'), col('se_y', 'X'), nX: nX, nY: nY, exposure: 'X', outcome: 'Y');
  final r = ref['steiger'] as Map;

  test('test agrégé : r²_X, r²_Y et z = formules de TwoSampleMR et psych::r.test', () {
    expect(s.r2x, closeRel(asD(r['r2x'])!, rel: 1e-12));
    expect(s.r2y, closeRel(asD(r['r2y'])!, rel: 1e-12));
    expect(s.z, closeRel(asD(r['z'])!, rel: 1e-12));
    expect(s.z, closeRel(asD(r['z_psych'])!, rel: 1e-10));
    expect(s.p, lessThan(1e-30)); // R affiche 0 (sous-dépassement)
    expect(s.result.checks.firstWhere((c) => c.id == 'direction').status, CheckStatus.ok);
  });

  test('filtrage variant par variant : r², p et variants de sens inverse = R ; IVW avec et sans eux = mr_ivw', () {
    final rx = v(r['r2x_snp']), ry = v(r['r2y_snp']), p = v(r['p_snp']);
    for (var j = 0; j < rx.length; j++) {
      expect(s.r2xSnp[j], closeRel(rx[j], rel: 1e-12));
      expect(s.r2ySnp[j], closeRel(ry[j], rel: 1e-12));
      // psych::r.test calcule 2·(1 − pnorm(|z|)) : perte de chiffres pour les petites p (le moteur prend la queue directement).
      expect(s.pSnp[j], closeRel(p[j], rel: 1e-6, abs: 1e-14));
    }
    expect(s.correctDirection.where((ok) => !ok).length, asD(ref['n_flagged'])!.round());
    final f = ref['forward'] as Map, ff = ref['forward_filtered'] as Map;
    expect(s.ivwAll!.estimate, closeRel(asD(f['estimate'])!, rel: 1e-10));
    expect(s.ivwAll!.se, closeRel(asD(f['se'])!, rel: 1e-10));
    expect(s.ivwFiltered!.estimate, closeRel(asD(ff['estimate'])!, rel: 1e-10));
    expect(s.ivwFiltered!.upper, closeRel(asD(ff['upper'])!, rel: 1e-10));
  });

  test('MR inverse (instruments de Y) : pas d\'effet de Y sur X = mr_ivw', () {
    final rev = mendelianRandomization(col('beta_y', 'Y'), col('se_y', 'Y'), col('beta_x', 'Y'), col('se_x', 'Y'), outcomeLogOdds: false, iterations: 200);
    final rr = ref['reverse'] as Map;
    expect(rev.ivw.estimate, closeRel(asD(rr['estimate'])!, rel: 1e-10));
    expect(rev.ivw.se, closeRel(asD(rr['se'])!, rel: 1e-10));
    expect(rev.ivw.p, greaterThan(0.05));
  });

  test('entrées invalides refusées', () {
    expect(() => steigerDirectionality([0.1], [0.01], [0.1], [0.01], nX: 5, nY: 100), throwsA(isA<StatInputError>()));
  });
}
