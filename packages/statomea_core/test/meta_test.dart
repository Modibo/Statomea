import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double?> dln(Object? v) => [for (final x in v as List) asD(x)];
List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void expectPooled(PooledResult r, Map<String, dynamic> ref, {double rel = 1e-8, String tag = ''}) {
  expect(r.mu, closeRel(asD(ref['mu'])!, rel: rel, abs: 1e-12), reason: '$tag mu');
  expect(r.se, closeRel(asD(ref['se'])!, rel: rel), reason: '$tag se');
  expect(r.lower, closeRel(dl(ref['ci'])[0], rel: rel, abs: 1e-12), reason: '$tag lower');
  expect(r.upper, closeRel(dl(ref['ci'])[1], rel: rel, abs: 1e-12), reason: '$tag upper');
  expect(r.p, closeRel(asD(ref['p'])!, rel: 1e-6, abs: 1e-300), reason: '$tag p');
  expect(r.tau2, closeRel(asD(ref['tau2'])!, rel: rel, abs: 1e-12), reason: '$tag tau2');
  expect(r.q, closeRel(asD(ref['Q'])!, rel: 1e-10), reason: '$tag Q');
  expect(r.i2, closeRel(asD(ref['I2'])!, rel: rel, abs: 1e-12), reason: '$tag I2');
  expect(r.h2, closeRel(asD(ref['H2'])!, rel: rel), reason: '$tag H2');
}

void main() {
  final ref = loadRef('meta');
  final bcg = [
    for (final s in (ref['bcg_data'] as List).cast<Map<String, dynamic>>())
      Study.binary(s['label'] as String, (s['e1'] as num).toInt(), (s['n1'] as num).toInt(), (s['e2'] as num).toInt(),
          (s['n2'] as num).toInt(), subgroup: s['sub'] as String)
  ];
  for (final m in [('RR', EffectMeasure.rr), ('OR', EffectMeasure.or), ('RD', EffectMeasure.rd)]) {
    group('BCG — ${m.$1} contre metafor', () {
      final r = ref['bcg_${m.$1}'] as Map<String, dynamic>;
      final eff = [for (final s in bcg) computeEffect(s, m.$2).effect!];
      final y = [for (final e in eff) e.yi], v = [for (final e in eff) e.vi];
      test('effets individuels (escalc)', () {
        for (var i = 0; i < y.length; i++) {
          expect(y[i], closeRel(dl(r['yi'])[i], rel: 1e-12, abs: 1e-15));
          expect(v[i], closeRel(dl(r['vi'])[i], rel: 1e-12));
        }
      });
      test('REML, DL, FE, Hartung-Knapp', () {
        expectPooled(poolInverseVariance(y, v, method: TauMethod.reml), r['reml'], tag: 'REML');
        expectPooled(poolInverseVariance(y, v, method: TauMethod.dl), r['dl'], tag: 'DL');
        expectPooled(poolInverseVariance(y, v, method: TauMethod.fixed), r['fe'], tag: 'FE');
        expectPooled(poolInverseVariance(y, v, method: TauMethod.reml, knha: true), r['knha'], tag: 'KNHA');
      });
      test('intervalle de prédiction t(k−2), leave-one-out, Egger', () {
        final p = poolInverseVariance(y, v, method: TauMethod.reml);
        expect(p.piLower, closeRel(dl(r['pi_reml'])[0], rel: 1e-8));
        expect(p.piUpper, closeRel(dl(r['pi_reml'])[1], rel: 1e-8));
        final full = metaAnalysis(bcg, MetaOptions(measure: m.$2, method: TauMethod.dl));
        final loo = (full.figures['leaveOneOut'] as List).cast<Map<String, Object?>>();
        final looRef = dl(r['loo_dl']);
        for (var i = 0; i < loo.length; i++) {
          final est = loo[i]['est'] as double;
          expect(m.$1 == 'RD' ? est : math.log(est), closeRel(looRef[i], rel: 1e-8, abs: 1e-12));
        }
        final eg = dl(r['egger']);
        expect(full.statistics['egger_intercept'], closeRel(eg[0], rel: 1e-8));
        expect(full.statistics['egger_p'], closeRel(eg[2], rel: 1e-6));
      });
    });
  }
  test('BCG — Mantel-Haenszel OR et RR contre rma.mh', () {
    final mh = ref['bcg_mh'] as Map<String, dynamic>;
    final o = mantelHaenszel(bcg, EffectMeasure.or), rr = mantelHaenszel(bcg, EffectMeasure.rr);
    expect(o.est, closeRel(dl(mh['or'])[0], rel: 1e-10));
    expect(o.se, closeRel(dl(mh['or'])[1], rel: 1e-10));
    expect(rr.est, closeRel(dl(mh['rr'])[0], rel: 1e-10));
    expect(rr.se, closeRel(dl(mh['rr'])[1], rel: 1e-10));
  });
  test('BCG — test de différence entre sous-groupes (effet fixe) = QM de metafor', () {
    final r = metaAnalysis(bcg, const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.fixed));
    expect(r.statistics['Q_between'], closeRel(asD(ref['bcg_subgroup_QM'])!, rel: 1e-9));
  });

  final normand = [
    for (final s in (ref['normand_data'] as List).cast<Map<String, dynamic>>())
      Study.continuous(s['label'] as String, asD(s['m1'])!, asD(s['sd1'])!, (s['n1'] as num).toInt(), asD(s['m2'])!,
          asD(s['sd2'])!, (s['n2'] as num).toInt())
  ];
  for (final m in [('MD', EffectMeasure.md), ('SMD', EffectMeasure.smd)]) {
    test('Normand 1999 — ${m.$1} contre metafor', () {
      final r = ref['normand_${m.$1}'] as Map<String, dynamic>;
      final eff = [for (final s in normand) computeEffect(s, m.$2).effect!];
      final y = [for (final e in eff) e.yi], v = [for (final e in eff) e.vi];
      for (var i = 0; i < y.length; i++) {
        expect(y[i], closeRel(dl(r['yi'])[i], rel: 1e-12, abs: 1e-14));
        expect(v[i], closeRel(dl(r['vi'])[i], rel: 1e-12));
      }
      expectPooled(poolInverseVariance(y, v, method: TauMethod.reml), r['reml'], tag: 'REML');
      expectPooled(poolInverseVariance(y, v, method: TauMethod.dl), r['dl'], tag: 'DL');
    });
  }

  group('Cellules nulles et événements rares', () {
    final z = ref['zero_data'] as Map<String, dynamic>;
    final e1 = dl(z['e1']), n1 = dl(z['n1']), e2 = dl(z['e2']), n2 = dl(z['n2']);
    final studies = [
      for (var i = 0; i < e1.length; i++) Study.binary('Étude ${i + 1}', e1[i].toInt(), n1[i].toInt(), e2[i].toInt(), n2[i].toInt())
    ];
    final r = ref['zero_OR'] as Map<String, dynamic>;
    test('double zéro exclu, correction 0,5 sinon (escalc drop00)', () {
      final res = metaAnalysis(studies, const MetaOptions(measure: EffectMeasure.or, method: TauMethod.dl));
      expect(res.statistics['k'], 4);
      expect(res.tables.any((t) => t.title.contains('non incluses')), isTrue);
      expect(res.alerts.map((a) => a.code), contains('continuity_correction'));
      final yref = dln(r['yi']).whereType<double>().toList();
      final eff = [for (final s in studies) computeEffect(s, EffectMeasure.or).effect].whereType<StudyEffect>().toList();
      for (var i = 0; i < eff.length; i++) {
        expect(eff[i].yi, closeRel(yref[i], rel: 1e-12));
      }
      final y = [for (final e in eff) e.yi], v = [for (final e in eff) e.vi];
      expectPooled(poolInverseVariance(y, v, method: TauMethod.dl), r['dl'], tag: 'DL');
    });
    test('Mantel-Haenszel sans correction', () {
      final mh = mantelHaenszel(studies, EffectMeasure.or);
      expect(mh.est, closeRel(dl(r['mh'])[0], rel: 1e-10));
      expect(mh.se, closeRel(dl(r['mh'])[1], rel: 1e-10));
    });
  });

  group('Garde-fous', () {
    test('études incompatibles et valeurs hypothétiques signalées', () {
      final s = [
        Study('a', 'A', const {'e1': SourcedValue(3), 'n1': SourcedValue(30), 'e2': SourcedValue(6), 'n2': SourcedValue(30)},
            compatibility: const StudyCompatibility(population: Compat.no)),
        Study('b', 'B', const {
          'e1': SourcedValue(4),
          'n1': SourcedValue(40),
          'e2': SourcedValue(9, provenance: Provenance.assumed, note: 'lu sur une figure'),
          'n2': SourcedValue(41)
        }),
      ];
      final r = metaAnalysis(s, const MetaOptions(measure: EffectMeasure.rr));
      final codes = r.alerts.map((a) => a.code);
      expect(codes, containsAll(['incompatible_studies', 'assumed_values', 'compatibility_unclear', 'few_studies']));
      expect(r.checks.first.status, CheckStatus.violated);
    });
    test('aucune étude exploitable : erreur explicite', () {
      expect(() => metaAnalysis([Study.binary('X', 0, 10, 0, 12)], const MetaOptions(measure: EffectMeasure.or)),
          throwsA(isA<StatInputError>()));
    });
  });
}

