import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('laboratoire');
  List<double> v(Object? l) => [for (final x in l as List) asD(x) ?? double.nan];

  for (final key in ['set50', 'set120', 'set200']) {
    test('intervalle de référence ($key) : paramétrique, robuste, non paramétrique (+ IC), Horn = referenceIntervals, MASS', () {
      final r = ref[key] as Map;
      final x = v(r['x']);
      final p = v(r['param']);
      final par = referenceInterval(x, method: ReferenceMethod.parametric);
      expect(par.statistics['lower'], closeRel(p[0], rel: 1e-12));
      expect(par.statistics['upper'], closeRel(p[1], rel: 1e-12));
      expect(par.statistics['lower_ci_low'], closeRel(p[2], rel: 1e-12));
      expect(par.statistics['upper_ci_high'], closeRel(p[5], rel: 1e-12));
      final rb = referenceInterval(x, method: ReferenceMethod.robust);
      final rr = v(r['robust']);
      expect(rb.statistics['lower'], closeRel(rr[0], rel: 1e-9));
      expect(rb.statistics['upper'], closeRel(rr[1], rel: 1e-9));
      final np = referenceInterval(x);
      final nn = v(r['nonpar']);
      expect(np.statistics['lower'], closeRel(nn[0], rel: 1e-12));
      expect(np.statistics['upper'], closeRel(nn[1], rel: 1e-12));
      if (r['nonpar_ci'] != null) {
        final ci = v(r['nonpar_ci']);
        final rk = v(r['ranks']);
        expect(nonparametricCiRanks(x.length), (rk[0].toInt(), rk[1].toInt()));
        expect([np.statistics['lower_ci_low'], np.statistics['lower_ci_high'], np.statistics['upper_ci_low'], np.statistics['upper_ci_high']], [for (final c in ci) closeRel(c, rel: 1e-12)]);
      } else {
        expect(np.statistics.containsKey('lower_ci_low'), isFalse);
      }
      final h = hornOutliers(x);
      expect(h.lambda, closeRel(asD(r['lambda'])!, rel: 1e-9, abs: 1e-12));
      expect(h.outliers, [for (final o in v(r['outliers'])) closeRel(o, rel: 1e-12)]);
    });
  }

  test('rangs non paramétriques : table de la CLSI reproduite (n = 120, 200, 1000)', () {
    expect(nonparametricCiRanks(120), (1, 7));
    expect(nonparametricCiRanks(200), (2, 10));
    expect(nonparametricCiRanks(500), (7, 19));
    expect(nonparametricCiRanks(1000), (17, 34));
  });

  test('partition de Harris et Boyd (hommes / femmes) et intervalles par sous-groupe', () {
    final ds = parseCsv(File('test/reference/creatinine_reference_simule.csv').readAsStringSync()).dataset;
    final res = referenceInterval(ds.numeric('creatinine'), groups: ds.text('sexe'), groupName: 'sexe');
    final hb = ref['partition'] as Map;
    expect(res.statistics['hb_z'], closeRel(asD(hb['z'])!, rel: 1e-12));
    expect(res.statistics['hb_zstar'], closeRel(asD(hb['zstar'])!, rel: 1e-12));
    expect(res.statistics['hb_sd_ratio'], closeRel(asD(hb['sd_ratio'])!, rel: 1e-12));
    expect(res.alerts.any((a) => a.code == 'ri_partition'), isTrue);
    expect(res.statistics.keys, containsAll(['lower_H', 'upper_F']));
  });

  void same(AnalysisResult res, Map r, List<String> keys) {
    final names = [for (final x in r['names'] as List) x as String];
    final df = v(r['df']), vc = v(r['vc']), sd = v(r['sd']), cv = v(r['cv']), lo = v(r['sd_lcl']), hi = v(r['sd_ucl']);
    for (var i = 0; i < names.length; i++) {
      final k = keys[i];
      expect(res.statistics['df_$k'], closeRel(df[i], rel: 1e-10), reason: 'ddl ${names[i]}');
      expect(res.statistics['vc_$k'], closeRel(vc[i], rel: 1e-10, abs: 1e-12), reason: 'VC ${names[i]}');
      expect(res.statistics['sd_$k'], closeRel(sd[i], rel: 1e-10, abs: 1e-12));
      expect(res.statistics['cv_$k'], closeRel(cv[i], rel: 1e-10, abs: 1e-12));
      if (lo[i].isNaN) {
        expect(res.statistics.containsKey('sd_${k}_lower'), isFalse);
      } else {
        expect(res.statistics['sd_${k}_lower'], closeRel(lo[i], rel: 1e-8, abs: 1e-12), reason: 'IC inf ${names[i]}');
        expect(res.statistics['sd_${k}_upper'], closeRel(hi[i], rel: 1e-8), reason: 'IC sup ${names[i]}');
      }
    }
    expect(res.statistics['mean'], closeRel(asD(r['mean'])!, rel: 1e-12));
  }

  test('fidélité EP05 (20 jours × 2 séries × 2) : composantes, ÉT, CV, IC = VCA', () {
    final ds = parseCsv(File('test/reference/ep05_vca.csv').readAsStringSync()).dataset;
    same(precisionAnalysis(ds.numeric('y'), ds.text('day'), runRaw: ds.text('run')), ref['ep05'] as Map, ['total', 'day', 'run', 'error']);
  });

  test('fidélité EP15 (5 × 5) : composantes = VCA ; vérification de la fidélité annoncée (2 niveaux)', () {
    final ds = parseCsv(File('test/reference/fidelite_ep15_simule.csv').readAsStringSync()).dataset;
    final r = ref['ep15'] as Map;
    final res = precisionAnalysis(ds.numeric('y'), ds.text('jour'), claimRepeatability: 2.0, claimWithinLab: 2.5, levels: 2);
    same(res, r, ['total', 'day', 'error']);
    final vf = r['verif'] as Map;
    expect(res.statistics['uvl_error'], closeRel(asD(vf['repeat_uvl'])!, rel: 1e-10));
    expect(res.statistics['uvl_total'], closeRel(asD(vf['wl_uvl'])!, rel: 1e-10));
  });

  test('variance entre jours estimée négative : bornée à 0, ddl du total comme VCA', () {
    final ds = parseCsv(File('test/reference/ep15_negatif.csv').readAsStringSync()).dataset;
    final res = precisionAnalysis(ds.numeric('y'), ds.text('jour'));
    same(res, ref['ep15neg'] as Map, ['total', 'day', 'error']);
    expect(res.alerts.any((a) => a.code == 'vc_zero'), isTrue);
  });

  test('plan déséquilibré ou moins de 20 valeurs : refus explicite', () {
    expect(() => precisionAnalysis([1, 2, 3, 4, 5, 6, 7], ['a', 'a', 'a', 'b', 'b', 'c', 'c']), throwsA(isA<StatInputError>()));
    expect(() => referenceInterval([for (var i = 1; i < 10; i++) i.toDouble()]), throwsA(isA<StatInputError>()));
  });
}
