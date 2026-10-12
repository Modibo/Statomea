import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('cox_prediction');
  final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
  const terms = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('ph.ecog')];
  final s = buildSurvivalDesign(lung, 'time', 'deces', 'oui', terms);
  final indices = [for (final r in ref['indices'] as List) [for (final v in r as List) (v as num).toInt()]];
  List<double> lpOf(List<double> beta) => [for (final r in s.design.x) r[0] * beta[0] + r[1] * beta[1] + r[2] * beta[2]];

  test('jeu et coefficients identiques à coxph (Efron et Breslow)', () {
    expect(s.time.length, ref['n']);
    expect(s.events, ref['events']);
    final f = fitCox(s.design.x, s.time, s.status);
    final fb = fitCox(s.design.x, s.time, s.status, efron: false);
    for (var j = 0; j < 3; j++) {
      expect(f.beta[j], closeRel(asD((ref['beta'] as List)[j])!, rel: 1e-7));
      expect(fb.beta[j], closeRel(asD((ref['beta_breslow'] as List)[j])!, rel: 1e-7));
    }
  });

  test('risque cumulé de base H₀(t) contre survfit.coxph (ctype 2 et 1 ; ties Breslow)', () {
    final f = fitCox(s.design.x, s.time, s.status);
    final fb = fitCox(s.design.x, s.time, s.status, efron: false);
    final h = [for (final v in ref['horizons'] as List) asD(v)!];
    for (var k = 0; k < h.length; k++) {
      expect(baselineCumHazard(s.time, s.status, lpOf(f.beta), h[k]), closeRel(asD((ref['H0_efron'] as List)[k])!, rel: 1e-6));
      expect(baselineCumHazard(s.time, s.status, lpOf(f.beta), h[k], efron: false),
          closeRel(asD((ref['H0_efron_breslowtype'] as List)[k])!, rel: 1e-6));
      expect(baselineCumHazard(s.time, s.status, lpOf(fb.beta), h[k], efron: false), closeRel(asD((ref['H0_breslow'] as List)[k])!, rel: 1e-6));
    }
  });

  test('modèle pronostique : risque à 365 j, C, optimisme bootstrap et calibration contre la référence R', () {
    final r = developCoxPredictionModel(s, horizon: 365, indices: indices, targetPopulation: 'cancer du poumon avancé', intendedUse: 'pédagogique');
    final st = r.statistics;
    expect(st['replicates'], indices.length.toDouble());
    expect(st['c_apparent'], closeRel(asD(ref['c_app'])!, rel: 1e-10));
    expect(st['c_apparent'], closeRel(asD(ref['c_coxph'])!, rel: 1e-10));
    expect(st['mean_risk_horizon'], closeRel(asD(ref['mean_risk365'])!, rel: 1e-6));
    expect(st['km_risk_horizon'], closeRel(asD(ref['km365_all'])!, rel: 1e-10));
    // L'optimisme repose sur 60 réajustements : comparaison à la précision de convergence de coxph.
    expect(st['c_optimism'], closeRel(asD(ref['opt_c'])!, rel: 1e-5, abs: 1e-9));
    expect(st['slope_optimism'], closeRel(asD(ref['opt_slope'])!, rel: 1e-5, abs: 1e-9));
    expect(st['c_corrected'], closeRel(asD(ref['c_corrected'])!, rel: 1e-7));
    expect(st['slope_corrected'], closeRel(asD(ref['slope_corrected'])!, rel: 1e-6));
    final cal = (r.figures['calibration'] as List).cast<Map<String, double>>();
    final rc = ref['calibration'] as List;
    expect(cal, hasLength(5));
    for (var g = 0; g < 5; g++) {
      final row = (rc[g] as List).map((v) => asD(v)!).toList();
      expect(cal[g]['predicted'], closeRel(row[0], rel: 1e-6));
      expect(cal[g]['observed'], closeRel(row[1], rel: 1e-9));
      expect(cal[g]['lower'], closeRel(row[2], rel: 1e-9));
      expect(cal[g]['upper'], closeRel(row[3], rel: 1e-9));
      expect(cal[g]['n'], row[4]);
    }
  });

  test('risques individuels à 365 j contre predict/survfit', () {
    final f = fitCox(s.design.x, s.time, s.status);
    final lp = lpOf(f.beta);
    final h0 = baselineCumHazard(s.time, s.status, lp, 365);
    final head = [for (final v in ref['risk365_head'] as List) asD(v)!];
    for (var i = 0; i < head.length; i++) {
      expect(1 - math.exp(-h0 * math.exp(lp[i])), closeRel(head[i], rel: 1e-6));
    }
  });

  test('horizon au-delà du suivi : refusé ; spécification incomplète signalée', () {
    expect(() => developCoxPredictionModel(s, horizon: 100000, bootstrap: 5),
        throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'horizon_beyond_follow_up')));
    final r = developCoxPredictionModel(s, horizon: 365, bootstrap: 5);
    expect(r.alerts.map((a) => a.code), contains('spec_incomplete'));
    expect(r.methodId, startsWith('prediction_'));
    expect(r.figures['stage'], 'internal');
  });
}
