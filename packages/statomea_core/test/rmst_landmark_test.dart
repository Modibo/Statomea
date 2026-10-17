import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('rmst_landmark');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final vet = parseCsv(File('test/reference/cox_veteran.csv').readAsStringSync()).dataset;
  final st = parseCsv(File('test/reference/greffe_stanford.csv').readAsStringSync()).dataset;

  for (final key in ['rmst300', 'rmst200']) {
    test('RMST ($key) : par bras, différence, rapports des RMST et des RMTL = survRM2::rmst2', () {
      final r = ref[key] as Map;
      final res = rmstAnalysis(vet.numeric('time'), vet.text('deces'), 'oui', groupRaw: vet.text('trt'), tau: asD(r['tau']));
      final a1 = v(r['arm1']), a0 = v(r['arm0']);
      expect(res.statistics['rmst_test'], closeRel(a1[0], rel: 1e-12));
      expect(res.statistics['se_test'], closeRel(a1[1], rel: 1e-10));
      expect(res.statistics['rmst_standard'], closeRel(a0[0], rel: 1e-12));
      expect(res.statistics['se_standard'], closeRel(a0[1], rel: 1e-10));
      final d = v(r['diff']), q = v(r['ratio']), l = v(r['rmtl_ratio']);
      expect(res.statistics['diff'], closeRel(d[0], rel: 1e-11));
      expect(res.statistics['diff_lower'], closeRel(d[1], rel: 1e-10));
      expect(res.statistics['diff_p'], closeRel(d[3], rel: 1e-9));
      expect(res.statistics['ratio'], closeRel(q[0], rel: 1e-11));
      expect(res.statistics['ratio_lower'], closeRel(q[1], rel: 1e-10));
      expect(res.statistics['rmtl_ratio'], closeRel(l[0], rel: 1e-11));
      expect(res.statistics['rmtl_ratio_upper'], closeRel(l[2], rel: 1e-10));
    });
  }

  test('τ au-delà du suivi du groupe le plus court : refusé ; τ par défaut = plus petit dernier temps', () {
    expect(() => rmstAnalysis(vet.numeric('time'), vet.text('deces'), 'oui', groupRaw: vet.text('trt'), tau: 5000), throwsA(isA<StatInputError>()));
    final r = rmstAnalysis(vet.numeric('time'), vet.text('deces'), 'oui', groupRaw: vet.text('trt'));
    expect(r.statistics['tau']!, greaterThan(500));
  });

  for (final key in ['lm30', 'lm60']) {
    test('landmark ($key, greffe de Stanford) : effectifs, log-rank, Cox = survival', () {
      final r = ref[key] as Map;
      final res = landmarkAnalysis(st, time: 'jours', status: 'deces', eventLevel: 'oui', switchTime: 'attente_greffe', landmark: asD(r['L'])!, terms: [const TermSpec('age')]);
      expect(res.statistics['n'], asD(r['n']));
      expect(res.statistics['exposed'], asD(r['n_greffe']));
      expect(res.statistics['events'], asD(r['events']));
      expect(res.statistics['logrank_chi2'], closeRel(asD(r['logrank'])!, rel: 1e-10));
      final c = v(r['coef']), s = v(r['se']);
      expect(res.statistics['beta_expose_au_landmark = oui (vs non)'], closeRel(c[0], rel: 1e-8));
      expect(res.statistics['se_expose_au_landmark = oui (vs non)'], closeRel(s[0], rel: 1e-8));
      expect(res.statistics['beta_age'], closeRel(c[1], rel: 1e-8));
    });
  }
}
