import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void main() {
  final ref = loadRef('diagnostic_descriptif');
  group('Performance diagnostique contre R (prop.test Wilson ; Simel 1991)', () {
    for (final c in (ref['diagnostic'] as List).cast<Map<String, dynamic>>()) {
      test('${c['tp']}/${c['fp']}/${c['fn']}/${c['tn']}', () {
        final r = diagnosticAccuracy(c['tp'] as int, c['fp'] as int, c['fn'] as int, c['tn'] as int, targetPrevalence: 0.01);
        void ci(Estimate e, String key) {
          expect(e.lower, closeRel(dl(c[key])[0], rel: 1e-9), reason: key);
          expect(e.upper, closeRel(dl(c[key])[1], rel: 1e-9), reason: key);
        }
        expect(r.estimates[0].value, closeRel(asD(c['se'])!));
        ci(r.estimates[0], 'se_ci');
        ci(r.estimates[1], 'sp_ci');
        ci(r.estimates[2], 'ppv_ci');
        ci(r.estimates[3], 'npv_ci');
        expect(r.estimates[4].value, closeRel(asD(c['lrp'])!, rel: 1e-12));
        ci(r.estimates[4], 'lrp_ci');
        expect(r.estimates[5].value, closeRel(asD(c['lrn'])!, rel: 1e-12));
        ci(r.estimates[5], 'lrn_ci');
        expect(r.statistics['ppv_target'], closeRel(asD(c['ppv_01'])!, rel: 1e-12));
      });
    }
  });
  test('Statistiques descriptives contre R (mean, sd, t.test, quantile type 7)', () {
    final d = ref['describe'] as Map<String, dynamic>;
    final x = [for (final v in d['x'] as List) asD(v)];
    final r = describeNumeric(x);
    expect(r.estimates[0].value, closeRel(asD(d['mean'])!, rel: 1e-12));
    expect(r.estimates[0].lower, closeRel(dl(d['ci'])[0], rel: 1e-10));
    expect(r.estimates[0].upper, closeRel(dl(d['ci'])[1], rel: 1e-10));
    expect(r.estimates[1].value, closeRel(asD(d['sd'])!, rel: 1e-12));
    final q = dl(d['q']);
    expect(r.estimates[3].value, closeRel(q[0], rel: 1e-12));
    expect(r.estimates[2].value, closeRel(q[1], rel: 1e-12));
    expect(r.estimates[4].value, closeRel(q[2], rel: 1e-12));
    expect(r.statistics['skewness'], closeRel(asD(d['skew'])!, rel: 1e-10));
    expect(r.statistics['missing'], 1);
  });
}
