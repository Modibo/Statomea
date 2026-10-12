import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final cases = loadRef('distributions')['cases'] as List;
  group('Lois de probabilité contre R', () {
    for (final c in cases.cast<Map<String, dynamic>>()) {
      final f = c['f'] as String;
      final x = asD(c['x']);
      final expected = asD(c['v'])!;
      test('$f(${c['x']}, ${c['df'] ?? c['a'] ?? c['k'] ?? ''})', () {
        final got = switch (f) {
          'pnorm' => normalCdf(x!),
          'qnorm' => normalQuantile(x!),
          'pt' => tCdf(x!, asD(c['df'])!),
          'qt' => tQuantile(x!, asD(c['df'])!),
          'pchisq_upper' => chiSquareUpper(x!, asD(c['df'])!),
          'qchisq' => chiSquareQuantile(x!, asD(c['df'])!),
          'pf_upper' => fUpper(x!, asD(c['df'])!, asD(c['df2'])!),
          'pbeta' => betaI(asD(c['a'])!, asD(c['b'])!, x!),
          'qbeta' => betaQuantile(x!, asD(c['a'])!, asD(c['b'])!),
          'binom_test' => binomialTestTwoSided(c['k'] as int, c['n'] as int, asD(c['p0'])!),
          'lgamma' => lnGamma(x!),
          _ => throw StateError(f),
        };
        expect(got, closeRel(expected, rel: 1e-9, abs: 1e-14));
      });
    }
  });
}
