import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void check(AnalysisResult r, Map<String, dynamic> ref, {String tag = ''}) {
  final b = dl(ref['b']), se = dl(ref['se']), lo = dl(ref['lower']), hi = dl(ref['upper']), p = dl(ref['p']);
  final betas = r.statistics.entries.where((e) => e.key.startsWith('beta_')).map((e) => e.value).toList();
  final ses = r.statistics.entries.where((e) => e.key.startsWith('se_')).map((e) => e.value).toList();
  for (var j = 0; j < b.length; j++) {
    expect(betas[j], closeRel(b[j], rel: 1e-7, abs: 1e-10), reason: '$tag β$j');
    expect(ses[j], closeRel(se[j], rel: 1e-7), reason: '$tag ES$j');
  }
  final coefRows = r.tables.first.rows;
  expect(coefRows.length, b.length);
  for (var j = 1; j < b.length; j++) {
    final e = r.estimates[j - 1];
    expect(math.log(e.lower!), closeRel(lo[j], rel: 1e-7, abs: 1e-10), reason: '$tag IC inf $j');
    expect(math.log(e.upper!), closeRel(hi[j], rel: 1e-7, abs: 1e-10), reason: '$tag IC sup $j');
    expect(e.pValue, closeRel(p[j], rel: 1e-6, abs: 1e-14), reason: '$tag p $j');
  }
  expect(r.statistics['tau2'], closeRel(asD(ref['tau2'])!, rel: 1e-7, abs: 1e-12), reason: '$tag τ²');
  expect(r.statistics['QE'], closeRel(asD(ref['QE'])!, rel: 1e-9), reason: '$tag QE');
  expect(r.statistics['QM'], closeRel(asD(ref['QM'])!, rel: 1e-7), reason: '$tag QM');
  expect(r.statistics['QM_p'], closeRel(asD(ref['QMp'])!, rel: 1e-6, abs: 1e-14), reason: '$tag QMp');
  expect(r.statistics['I2_resid'], closeRel(asD(ref['I2'])!, rel: 1e-7, abs: 1e-12), reason: '$tag I²');
  expect(r.statistics['H2_resid'], closeRel(asD(ref['H2'])!, rel: 1e-7), reason: '$tag H²');
  final r2 = asD(ref['R2']);
  if (r2 != null && !r2.isNaN) expect(r.statistics['R2'], closeRel(r2, rel: 1e-7, abs: 1e-12), reason: '$tag R²');
}

void main() {
  final ref = loadRef('meta_regression');
  final p = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
  const lat = [Moderator('latitude')];
  for (final c in [
    ('ablat_reml', TauMethod.reml, false),
    ('ablat_dl', TauMethod.dl, false),
    ('ablat_fe', TauMethod.fixed, false),
    ('ablat_knha', TauMethod.reml, true),
  ]) {
    test('BCG ~ latitude — ${c.$1} contre metafor', () {
      final r = metaRegression(p.studies, MetaOptions(measure: EffectMeasure.rr, method: c.$2, knha: c.$3), lat);
      check(r, ref[c.$1] as Map<String, dynamic>, tag: c.$1);
    });
  }
  test('BCG ~ latitude + allocation (modérateur qualitatif)', () {
    final r = metaRegression(p.studies, const MetaOptions(measure: EffectMeasure.rr), const [Moderator('latitude'), Moderator('allocation', categorical: true, reference: 'aléatoire')]);
    check(r, ref['ablat_alloc'] as Map<String, dynamic>, tag: 'alloc');
  });
  test('BCG ~ année ; graphique à bulles', () {
    final r = metaRegression(p.studies, const MetaOptions(measure: EffectMeasure.rr), const [Moderator('annee')]);
    check(r, ref['year_reml'] as Map<String, dynamic>, tag: 'année');
    expect(bubblePlotSvg(r.figures['bubble'] as Map), startsWith('<svg'));
  });
  test('trop peu d\'études ou modérateur constant : erreur explicite', () {
    expect(() => metaRegression(p.studies.take(2).toList(), const MetaOptions(measure: EffectMeasure.rr), lat), throwsA(isA<StatInputError>()));
    final same = [for (final s in p.studies) Study(s.id, s.label, s.values, subgroup: 'x')];
    expect(() => metaRegression(same, const MetaOptions(measure: EffectMeasure.rr), const [Moderator('g', categorical: true)]), throwsA(isA<StatInputError>()));
  });
}
