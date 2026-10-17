import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('cox_temps');
  final ds = parseCsv(File('test/reference/greffe_stanford.csv').readAsStringSync()).dataset;
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final long = splitAtSwitch(ds, time: 'jours', status: 'deces', eventLevel: 'oui', switchTime: 'attente_greffe', covariate: 'greffe');
  final terms = [TermSpec('greffe', categorical: true, reference: 'non'), TermSpec('age'), TermSpec('chirurgie', categorical: true, reference: 'non')];

  test('découpage au changement de covariable = survival::tmerge(tdc()) : mêmes 170 intervalles', () {
    final r = ref['rows'] as Map;
    final start = v(r['start']), stop = v(r['stop']), ev = v(r['event']), gr = v(r['greffe']);
    expect(long.rowCount, start.length);
    for (var i = 0; i < start.length; i++) {
      expect(double.parse(long.cell(i, 'debut')!), start[i]);
      expect(double.parse(long.cell(i, 'fin')!), stop[i]);
      expect(long.cell(i, 'deces') == 'oui' ? 1.0 : 0.0, ev[i], reason: 'ligne $i');
      expect(long.cell(i, 'greffe') == 'oui' ? 1.0 : 0.0, gr[i], reason: 'ligne $i');
    }
  });

  test('Cox en processus de comptage (Efron et Breslow) : coefficients, ES, log-vraisemblance, score, Wald = coxph', () {
    for (final (efron, key) in [(true, 'efron'), (false, 'breslow')]) {
      final r = coxRegression(buildCountingDesign(long, 'debut', 'fin', 'deces', 'oui', terms), efron: efron);
      final e = ref[key] as Map;
      final coef = v(e['coef']), se = v(e['se']), ll = v(e['loglik']);
      final cols = ['greffe = oui (vs non)', 'age', 'chirurgie = oui (vs non)'];
      for (var j = 0; j < 3; j++) {
        expect(r.statistics['beta_${cols[j]}'], closeRel(coef[j], rel: 1e-8), reason: '$key ${cols[j]}');
        expect(r.statistics['se_${cols[j]}'], closeRel(se[j], rel: 1e-8));
      }
      expect(r.statistics['loglik_null'], closeRel(ll[0], rel: 1e-12));
      expect(r.statistics['loglik'], closeRel(ll[1], rel: 1e-11));
      expect(r.statistics['score'], closeRel(asD(e['score'])!, rel: 1e-9));
      expect(r.statistics['wald'], closeRel(asD(e['wald'])!, rel: 1e-7));
      expect(r.statistics.containsKey('concordance'), isFalse);
      expect(r.methodName, contains('dépendant du temps'));
    }
  });

  test('biais du temps immortel : la greffe codée à l\'inclusion paraît protectrice (HR 0,18), pas en covariable dépendant du temps (HR 1,01)', () {
    final naive = coxRegression(buildSurvivalDesign(ds, 'jours', 'deces', 'oui', terms));
    final e = ref['naive'] as Map;
    expect(naive.statistics['beta_greffe = oui (vs non)'], closeRel(v(e['coef']).first, rel: 1e-8));
    final td = coxRegression(buildCountingDesign(long, 'debut', 'fin', 'deces', 'oui', terms));
    expect(naive.estimates.first.value, lessThan(0.25));
    expect(td.estimates.first.value, closeTo(1.0, 0.05));
  });

  test('intervalles invalides refusés ; sans changement, données identiques au Cox ordinaire', () {
    final bad = Dataset(['a', 'b', 's', 'x'], [['5', '3', '1', '1'], ['0', '4', '0', '0']]);
    expect(() => buildCountingDesign(bad, 'a', 'b', 's', '1', [TermSpec('x')]), throwsA(isA<StatInputError>()));
    final plain = Dataset.fromColumns({'t': [3, 5, 7, 9, 11, 14], 's': [1, 0, 1, 1, 0, 1], 'x': [0, 1, 0, 1, 1, 0], 'z': [1.2, 0.4, 2.2, 1.1, 0.3, 1.9], 'zero': [0, 0, 0, 0, 0, 0]});
    final a = coxRegression(buildSurvivalDesign(plain, 't', 's', '1', [TermSpec('x'), TermSpec('z')]));
    final b = coxRegression(buildCountingDesign(plain, 'zero', 't', 's', '1', [TermSpec('x'), TermSpec('z')]));
    expect(b.statistics['beta_x'], closeRel(a.statistics['beta_x']!, rel: 1e-10));
    expect(b.statistics['loglik'], closeRel(a.statistics['loglik']!, rel: 1e-12));
  });
}
