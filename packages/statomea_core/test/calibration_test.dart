import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('calibration');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  for (final key in ['dev', 'ext']) {
    test('calibration ($key) : Hosmer-Lemeshow, Spiegelhalter, Brier, recalibration, lowess, Eavg/E90/Emax = R', () {
      final r = ref[key] as Map;
      final p = v(r['p']), y = v(r['y']);
      final res = calibrationAssessment(p, y);
      final hl = v(r['hl']);
      expect(res.statistics['hl_chi2'], closeRel(hl[0], rel: 1e-10));
      expect(res.statistics['hl_df'], hl[1]);
      expect(res.statistics['hl_p'], closeRel(hl[2], rel: 1e-8));
      final h = hosmerLemeshow(p, y);
      final obs = v(r['observed1']), exp = v(r['expected1']);
      final nonEmpty = h.groups.where((g) => g.n > 0).toList();
      for (var k = 0; k < obs.length; k++) {
        expect(nonEmpty[k].obs, obs[k]);
        expect(nonEmpty[k].exp, closeRel(exp[k], rel: 1e-12));
      }
      final sp = v(r['spiegel']);
      expect(res.statistics['spiegelhalter_z'], closeRel(sp[0], rel: 1e-10));
      expect(res.statistics['spiegelhalter_p'], closeRel(sp[1], rel: 1e-8));
      expect(res.statistics['brier'], closeRel(asD(r['brier'])!, rel: 1e-12));
      expect(res.statistics['recal_intercept'], closeRel(asD(r['intercept'])!, rel: 1e-7, abs: 1e-8));
      expect(res.statistics['recal_slope'], closeRel(asD(r['slope'])!, rel: 1e-7));
      expect(res.statistics['citl'], closeRel(asD(r['citl'])!, rel: 1e-8, abs: 1e-8));
      final sx = v(r['smooth_x']), sy = v(r['smooth_y']);
      final fit = lowessFit(sx, [for (final i in (List<int>.generate(p.length, (i) => i)..sort((a, b) { final c = p[a].compareTo(p[b]); return c != 0 ? c : a.compareTo(b); }))) y[i]]);
      for (var k = 0; k < sx.length; k++) {
        expect(fit[k], closeRel(sy[k], rel: 1e-10, abs: 1e-12), reason: 'lowess $k');
      }
      expect(res.statistics['eavg'], closeRel(asD(r['eavg'])!, rel: 1e-9));
      expect(res.statistics['e90'], closeRel(asD(r['e90'])!, rel: 1e-9));
      expect(res.statistics['emax'], closeRel(asD(r['emax'])!, rel: 1e-9));
      expect(res.figures['calibrationSmooth'], isA<List>());
    });
  }

  test('probabilités hors ]0 ; 1[ ou issue non binaire : refus explicite', () {
    expect(() => calibrationAssessment([for (var i = 0; i < 30; i++) i == 3 ? 1.2 : 0.3], [for (var i = 0; i < 30; i++) (i % 2).toDouble()]), throwsA(isA<StatInputError>()));
    expect(() => calibrationAssessment([for (var i = 0; i < 30; i++) 0.3], [for (var i = 0; i < 30; i++) i == 2 ? 2.0 : 0.0]), throwsA(isA<StatInputError>()));
  });
}
