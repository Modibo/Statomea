import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('series_interrompues');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final ds = parseCsv(File('test/reference/serie_interrompue_simule.csv').readAsStringSync()).dataset;
  final t0 = asD(ref['T0'])!;

  test('régression segmentée, issue continue : β, ES de Newey-West (retard 3), Durbin-Watson, effet à h = lm + sandwich', () {
    final r = interruptedTimeSeries(ds.numeric('mois'), ds.numeric('taux_100k'), t0, lag: 3);
    final m = ref['lin'] as Map;
    final b = v(m['coef']), se = v(m['se_nw']), ols = v(m['se_ols']), eff = v(m['effect']);
    for (var a = 0; a < 4; a++) {
      expect(r.statistics['beta_$a'], closeRel(b[a], rel: 1e-10), reason: 'β$a');
      expect(r.statistics['se_$a'], closeRel(se[a], rel: 1e-10), reason: 'ES NW $a');
      expect(r.statistics['se_ols_$a'], closeRel(ols[a], rel: 1e-10), reason: 'ES MCO $a');
    }
    expect(r.statistics['dw'], closeRel(asD(m['dw'])!, rel: 1e-10));
    expect(r.statistics['ac1'], closeRel(asD(m['ac1'])!, rel: 1e-10));
    expect(r.statistics['horizon'], asD(ref['h']));
    expect(r.statistics['effect'], closeRel(eff[0], rel: 1e-10));
    expect(r.statistics['effect_se'], closeRel(eff[1], rel: 1e-10));
    expect(r.figures['its'], isA<Map>());
  });

  test('comptages : Poisson avec offset, dispersion quasi-Poisson, effet à h = glm(quasipoisson)', () {
    final r = interruptedTimeSeries(ds.numeric('mois'), ds.numeric('admissions'), t0, family: SeriesFamily.poisson, population: ds.numeric('population'));
    final m = ref['pois'] as Map;
    final b = v(m['coef']), se = v(m['se']), eff = v(m['effect']);
    for (var a = 0; a < 4; a++) {
      expect(r.statistics['beta_$a'], closeRel(b[a], rel: 1e-8), reason: 'β$a');
      expect(r.statistics['se_$a'], closeRel(se[a], rel: 1e-7), reason: 'ES $a');
    }
    expect(r.statistics['dispersion'], closeRel(asD(m['dispersion'])!, rel: 1e-7));
    expect(r.statistics['effect'], closeRel(eff[0], rel: 1e-8));
    expect(r.statistics['effect_se'], closeRel(eff[1], rel: 1e-7));
  });

  test('moins de 3 périodes d\'un côté, ou comptage non entier : refus', () {
    expect(() => interruptedTimeSeries([1, 2, 3, 4, 5], [1, 2, 3, 4, 5], 5), throwsA(isA<StatInputError>()));
    expect(() => interruptedTimeSeries([1, 2, 3, 4, 5, 6, 7, 8], [1, 2, 3.5, 4, 5, 6, 7, 8], 5, family: SeriesFamily.poisson), throwsA(isA<StatInputError>()));
  });
}
