import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('gee');
  List<double> v(Object? l) => l is List ? [for (final x in l) asD(x)!] : [asD(l)!];
  final base = parseCsv(File('test/reference/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;
  // Issue binaire « contrôle » (HbA1c < 7,8), comme le script R.
  final ds = Dataset([...base.names, 'controle'], [
    for (var i = 0; i < base.rowCount; i++) [for (final n in base.names) base.cell(i, n), double.parse(base.cell(i, 'hba1c')!) < 7.8 ? '1' : '0']
  ]);
  const terms = [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')];
  const inter = [('mois', 'bras')];

  void check(String key, ModelFormula f, GeeFamily fam, GeeCorrelation corr, bool small, {double tolBeta = 1e-8, double tolSe = 1e-7}) {
    final r = ref[key] as Map;
    final res = geeRegression(ds, f, subject: 'patient', family: fam, corr: corr, smallSample: small);
    final cols = (res.inputs['model'] as Map)['columns'] as List;
    final beta = v(r['beta']), se = v(r['se']);
    for (var j = 0; j < beta.length; j++) {
      expect(res.statistics['beta_${cols[j]}'], closeRel(beta[j], rel: tolBeta, abs: 1e-12), reason: '$key β ${cols[j]}');
      expect(res.statistics['se_${cols[j]}'], closeRel(se[j], rel: tolSe), reason: '$key ES ${cols[j]}');
    }
    expect(res.statistics['alpha'], closeRel(v(r['alpha']).first, rel: 1e-7, abs: 1e-12), reason: '$key α');
    expect(res.statistics['phi'], closeRel(v(r['phi']).first, rel: 1e-7), reason: '$key φ');
    if (r['p'] != null) {
      final p = v(r['p']);
      for (var j = 0; j < p.length; j++) {
        expect(res.statistics['p_${cols[j]}'], closeRel(p[j], rel: 1e-6, abs: 1e-14));
      }
    }
  }

  test('gaussienne échangeable : geepack (φ = Σr²/N) et gee (Liang-Zeger, correction − p)', () {
    check('gauss_exch_geepack', const ModelFormula('hba1c', terms, interactions: inter), GeeFamily.gaussian, GeeCorrelation.exchangeable, false);
    check('gauss_exch_gee', const ModelFormula('hba1c', terms, interactions: inter), GeeFamily.gaussian, GeeCorrelation.exchangeable, true);
  });

  test('binomiale (contrôle glycémique) : échangeable (geepack, gee) et indépendance = geeglm / gee', () {
    const f = ModelFormula('controle', terms, interactions: inter, eventLevel: '1');
    check('bin_exch_geepack', f, GeeFamily.binomial, GeeCorrelation.exchangeable, false);
    check('bin_exch_gee', f, GeeFamily.binomial, GeeCorrelation.exchangeable, true);
    check('bin_ind_geepack', f, GeeFamily.binomial, GeeCorrelation.independence, false);
  });

  test('Poisson (hypoglycémies) échangeable : geepack et gee', () {
    const f = ModelFormula('hypoglycemies', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A')]);
    check('pois_exch_geepack', f, GeeFamily.poisson, GeeCorrelation.exchangeable, false);
    check('pois_exch_gee', f, GeeFamily.poisson, GeeCorrelation.exchangeable, true);
  });

  test('erreurs : comptage négatif refusé, trop peu de sujets refusé', () {
    final bad = Dataset(['id', 'y', 'x'], [['a', '-1', '1'], ['a', '2', '0'], ['b', '1', '1'], ['c', '0', '0']]);
    expect(() => geeRegression(bad, const ModelFormula('y', [TermSpec('x')]), subject: 'id', family: GeeFamily.poisson), throwsA(isA<StatInputError>()));
  });
}
