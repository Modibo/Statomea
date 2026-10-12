import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('validation_externe');
  final dev = buildDemoPrediction(File('test/reference/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 20);
  final eq = ModelEquation.fromDevelopment(analysisResultFromJson(dev.journal.first.result));
  final ext = parseCsv(File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync()).dataset;

  test('équation appliquée telle quelle : logit prédit identique à predict.glm', () {
    final a = applyEquation(ext, eq);
    final lp = [for (final v in ref['lp_head'] as List) asD(v)!];
    for (var i = 0; i < lp.length; i++) {
      expect(a.lp[i], closeRel(lp[i], rel: 1e-8));
    }
  });
  test('AUC (DeLong), intercept et pente de calibration, O/E, Brier — contre pROC et glm', () {
    final r = externalValidation(ext, eq, population: 'cohorte externe simulée');
    final s = r.statistics;
    expect(s['n'], ref['n']);
    expect(s['events'], ref['events']);
    expect(s['auc'], closeRel(asD(ref['auc'])!, rel: 1e-9));
    expect(r.estimates[0].lower, closeRel(asD((ref['auc_ci'] as List)[0])!, rel: 1e-8));
    expect(s['citl'], closeRel(asD(ref['citl'])!, rel: 1e-8));
    expect(s['citl_se'], closeRel(asD(ref['citl_se'])!, rel: 1e-7));
    expect(s['slope'], closeRel(asD(ref['slope'])!, rel: 1e-8));
    expect(s['slope_se'], closeRel(asD(ref['slope_se'])!, rel: 1e-7));
    expect(s['recal_logistic_a'], closeRel(asD(ref['slope_a'])!, rel: 1e-8));
    expect(s['oe'], closeRel(asD(ref['oe'])!, rel: 1e-10));
    expect(s['brier'], closeRel(asD(ref['brier'])!, rel: 1e-10));
    expect(r.checks.firstWhere((c) => c.id == 'calibration_slope').status, CheckStatus.violated);
  });
  test('codage incompatible : erreur explicite', () {
    final bad = ModelEquation(name: 'x', outcome: 'evenement_5ans', eventLevel: '1', predictors: const [TermSpec('age')],
        coefficients: const {'Constante': -1, 'age_autre': 0.1});
    expect(() => externalValidation(ext, bad), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'equation_mismatch')));
  });
  test('l\'audit accepte « validation externe » quand elle est faite, mais refuse « utilisable en pratique clinique »', () {
    final r = externalValidation(ext, eq);
    final a = runAudit(question: dev.question, results: [analysisResultFromJson(dev.journal.first.result), r],
        text: 'Après validation externe, le modèle est utilisable en pratique clinique.');
    expect(a.of(AuditFamily.announcedNotDone).any((f) => f.status == AuditStatus.alert && (f.trigger ?? '').contains('validation externe')), isFalse);
    expect(a.of(AuditFamily.predictionOverclaim).any((f) => f.status == AuditStatus.alert), isTrue);
  });
}
