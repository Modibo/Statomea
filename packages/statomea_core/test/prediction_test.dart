import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void main() {
  final ref = loadRef('prediction');
  final ds = parseCsv(File('test/reference/cardiometabolique_simule.csv').readAsStringSync()).dataset;
  final indices = [for (final r in ref['indices'] as List) [for (final i in r as List) i as int]];
  const spec = PredictionSpec(
    targetPopulation: 'Adultes de 30 à 70 ans sans diabète connu, soins primaires (population simulée)',
    outcome: 'evenement_5ans',
    eventLevel: '1',
    horizon: '5 ans',
    intendedUse: 'Repérer les personnes à orienter vers un bilan cardiométabolique',
    predictors: [
      TermSpec('age'),
      TermSpec('sexe', categorical: true, reference: 'F'),
      TermSpec('tour_taille'),
      TermSpec('pas'),
      TermSpec('glycemie'),
      TermSpec('hdl'),
      TermSpec('tabac', categorical: true, reference: 'non'),
      TermSpec('atcd_familial', categorical: true, reference: 'non'),
    ],
    referencePredictors: [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F')],
    referenceName: 'Âge + sexe',
  );
  final r = developPredictionModel(ds, spec, indices: indices);

  test('cas complets identiques à R', () {
    expect(r.statistics['n'], ref['n_complete']);
  });
  test('coefficients du modèle', () {
    final b = dl((ref['new'] as Map)['coef']);
    final cols = ((r.inputs['model'] as Map)['columns'] as List).cast<String>();
    for (var j = 0; j < b.length; j++) {
      expect(r.statistics['beta_${cols[j]}'], closeRel(b[j], rel: 1e-8), reason: cols[j]);
    }
  });
  test('performance apparente, optimisme et performance corrigée (mêmes indices bootstrap que R)', () {
    for (final (k, s) in [('auc', 'auc'), ('slope', 'slope'), ('brier', 'brier')]) {
      final app = asD(((ref['new'] as Map)['apparent'] as Map)[k])!;
      final cor = asD(((ref['new'] as Map)['corrected'] as Map)[k])!;
      expect(r.statistics['${s}_apparent'], closeRel(app, rel: 1e-8), reason: 'app $k');
      expect(r.statistics['${s}_corrected'], closeRel(cor, rel: 1e-6), reason: 'corr $k');
    }
    final ci = r.estimates.first;
    expect(ci.lower, closeRel(dl(ref['auc_ci'])[0], rel: 1e-8));
    expect(ci.upper, closeRel(dl(ref['auc_ci'])[1], rel: 1e-8));
    expect(r.statistics['auc_se']! * r.statistics['auc_se']!, closeRel(asD(ref['var_auc'])!, rel: 1e-8));
    expect(r.statistics['intercept_corrected'], closeRel(asD(((ref['new'] as Map)['corrected'] as Map)['intercept'])!, rel: 1e-5, abs: 1e-8));
  });
  test('modèle de référence et test de DeLong apparié (pROC roc.test)', () {
    final d = ref['delta'] as Map<String, dynamic>;
    expect(r.statistics['delta_auc'], closeRel(asD(d['diff'])!, rel: 1e-8));
    expect(r.statistics['delta_auc']! / r.statistics['delta_auc_se']!, closeRel(asD(d['z'])!, rel: 1e-7));
    expect(r.statistics['ref_auc_corrected'], closeRel(asD(((ref['ref'] as Map)['corrected'] as Map)['auc'])!, rel: 1e-6));
  });
  test('courbe de décision (bénéfice net)', () {
    final dca = ref['dca'] as Map<String, dynamic>;
    final t = dl(dca['t']), nb = dl(dca['nb']);
    final x = (r.figures['decisionCurve'] as List).cast<Map<String, double>>();
    for (var i = 0; i < t.length; i++) {
      final row = x.firstWhere((m) => (m['threshold']! - t[i]).abs() < 1e-12);
      expect(row['model'], closeRel(nb[i], rel: 1e-10, abs: 1e-14));
    }
  });
  test('R² de Cox-Snell', () {
    expect(r.statistics['r2_coxsnell'], closeRel(asD(ref['r2cs'])!, rel: 1e-8));
  });
  test('taille d\'échantillon de Riley contre pmsampsize', () {
    for (final c in (ref['riley'] as List).cast<Map<String, dynamic>>()) {
      final n = dl(c['n']);
      final x = rileySampleSize(parameters: c['p'] as int, prevalence: asD(c['prev'])!, r2CoxSnell: asD(c['r2'])!);
      expect(x.n1.ceil(), n[0].toInt());
      expect(x.n2.ceil(), n[1].toInt());
      expect(x.n3.ceil(), n[2].toInt());
    }
  });
  test('garde-fous : jamais « validé », validation externe non évaluée', () {
    final text = '${r.interpretation.whatItMeans} ${r.methodName}'.toLowerCase();
    expect(text.contains('validé cliniquement'), isFalse);
    expect(r.checks.firstWhere((c) => c.id == 'external_validation').status, CheckStatus.notAssessed);
    expect(r.interpretation.notJustified, contains('validé'));
  });
  test('spécification incomplète signalée', () {
    const bad = PredictionSpec(targetPopulation: '', outcome: 'evenement_5ans', eventLevel: '1', horizon: '', intendedUse: '',
        predictors: [TermSpec('age')]);
    final x = developPredictionModel(ds, bad, bootstrap: 20);
    expect(x.alerts.map((a) => a.code), contains('spec_incomplete'));
  });
}
