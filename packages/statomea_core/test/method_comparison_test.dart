import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('comparaison_methodes');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final ds = parseCsv(File('test/reference/creatinine_serum_plasma.csv').readAsStringSync()).dataset;
  final x = ds.numeric('creatinine_serum'), y = ds.numeric('creatinine_plasma');

  test('Passing-Bablok : pente, ordonnée et IC analytiques = algorithme publié ; mcr (angles) à 1e-4 près', () {
    final res = methodComparison(x, y, decisionLevels: const [1, 2, 4]);
    final c = ref['paba_classic'] as Map;
    final s = v(c['slope']), a = v(c['intercept']);
    expect(res.statistics['n'], asD(ref['n']));
    expect(res.statistics['n_slopes'], asD(c['N']));
    expect(res.statistics['k_negative'], asD(c['K']));
    for (final (k, e) in [('slope', s[0]), ('slope_lower', s[1]), ('slope_upper', s[2]), ('intercept', a[0]), ('intercept_lower', a[1]), ('intercept_upper', a[2])]) {
      expect(res.statistics[k], closeRel(e, rel: 1e-12, abs: 1e-12), reason: k);
    }
    final m = ref['paba_mcr'] as Map;
    expect(res.statistics['slope'], closeRel(v(m['slope'])[0], rel: 1e-8));
    expect(res.statistics['intercept'], closeRel(v(m['intercept'])[0], rel: 1e-7));
    expect(res.statistics['slope_upper'], closeRel(v(m['slope'])[2], rel: 1e-4));
    final kt = ref['kendall'] as Map;
    expect(res.statistics['kendall_tau'], closeRel(asD(kt['tau'])!, rel: 1e-12));
    expect(res.statistics['kendall_p'], closeRel(asD(kt['p'])!, rel: 1e-6, abs: 1e-300));
    expect(res.statistics['bias_at_2'], closeRel(a[0] + (s[0] - 1) * 2, rel: 1e-12));
    expect(res.figures['methodComparison'], isA<Map>());
  });

  test('Passing-Bablok, cas limites (ex aequo, paire verticale, n = 20) = algorithme publié et mcr', () {
    final sm = ref['small'] as Map;
    final res = methodComparison(v(sm['x']), v(sm['y']));
    final c = sm['classic'] as Map, m = sm['mcr'] as Map;
    expect(res.statistics['slope'], closeRel(v(c['slope'])[0], rel: 1e-12));
    expect(res.statistics['slope_lower'], closeRel(v(m['slope'])[1], rel: 1e-12));
    expect(res.statistics['slope_upper'], closeRel(v(m['slope'])[2], rel: 1e-12));
    expect(res.statistics['intercept_lower'], closeRel(v(m['intercept'])[1], rel: 1e-9));
    expect(res.statistics['intercept_upper'], closeRel(v(m['intercept'])[2], rel: 1e-9));
  });

  for (final (key, lambda) in [('deming1', 1.0), ('deming2', 2.0)]) {
    test('Deming λ = $lambda : coefficients et IC jackknife = mcr', () {
      final res = methodComparison(x, y, kind: MethodComparisonKind.deming, errorRatio: lambda);
      final r = ref[key] as Map;
      final s = v(r['slope']), a = v(r['intercept']), se = v(r['se']);
      expect(res.statistics['slope'], closeRel(s[0], rel: 1e-11));
      expect(res.statistics['slope_lower'], closeRel(s[1], rel: 1e-10));
      expect(res.statistics['slope_upper'], closeRel(s[2], rel: 1e-10));
      expect(res.statistics['intercept'], closeRel(a[0], rel: 1e-10));
      expect(res.statistics['intercept_lower'], closeRel(a[1], rel: 1e-9));
      expect(res.statistics['intercept_se'], closeRel(se[0], rel: 1e-9));
      expect(res.statistics['slope_se'], closeRel(se[1], rel: 1e-9));
    });
  }

  test('moins de 10 paires refusé ; biais constant et proportionnel détectés', () {
    expect(() => methodComparison([1, 2, 3], [1, 2, 3]), throwsA(isA<StatInputError>()));
    final xs = [for (var i = 1; i <= 50; i++) i.toDouble()];
    final ys = [for (var i = 0; i < 50; i++) 2 + 1.2 * xs[i] + ((i * 7) % 5 - 2) * 0.1];
    final r = methodComparison(xs, ys);
    expect(r.statistics['intercept_lower']!, greaterThan(0));
    expect(r.statistics['slope_lower']!, greaterThan(1));
  });
}
