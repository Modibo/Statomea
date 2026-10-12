import 'dart:convert';
import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('cox_external');
  final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
  final ext = parseCsv(File('test/reference/cox_externe_simule.csv').readAsStringSync()).dataset;
  const terms = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('ph.ecog')];
  final dev = developCoxPredictionModel(buildSurvivalDesign(lung, 'time', 'deces', 'oui', terms), horizon: 365, bootstrap: 10,
      targetPopulation: 'lung', intendedUse: 'test');
  final eq = CoxEquation.fromDevelopment(dev);

  test('équation transportée : coefficients et H₀(365) de la référence', () {
    expect(eq.horizon, 365);
    expect(eq.baselineCumHazard, closeRel(asD(ref['H0_dev'])!, rel: 1e-6));
    final b = [for (final v in ref['beta'] as List) asD(v)!];
    expect(eq.coefficients.values.toList(), [for (final v in b) closeRel(v, rel: 1e-7)]);
    // Aller-retour JSON (équation publiée).
    final back = CoxEquation.fromJson((jsonDecode(jsonEncode(eq.toJson())) as Map).cast());
    expect(back.coefficients, eq.coefficients);
    expect(back.predictors.length, 3);
  });

  test('validation externe contre survival : C, pente, observé/prédit, recalibrations, calibration', () {
    final r = externalValidationCox(ext, eq, population: 'cohorte simulée');
    final s = r.statistics;
    expect(s['n'], ref['n']);
    expect(s['events'], ref['events']);
    expect(s['c'], closeRel(asD(ref['c'])!, rel: 1e-10));
    expect(s['slope'], closeRel(asD(ref['slope'])!, rel: 1e-6));
    expect(s['slope_se'], closeRel(asD(ref['slope_se'])!, rel: 1e-5));
    expect(s['mean_risk'], closeRel(asD(ref['mean_risk'])!, rel: 1e-6));
    expect(s['km_risk'], closeRel(asD(ref['km_risk'])!, rel: 1e-10));
    expect(r.estimates[4].lower, closeRel(asD(ref['km_lower'])!, rel: 1e-9));
    expect(s['oe'], closeRel(asD(ref['oe'])!, rel: 1e-6));
    expect(s['H0_recal_intercept'], closeRel(asD(ref['H0_recal_intercept'])!, rel: 1e-6));
    expect(s['H0_recal_slope'], closeRel(asD(ref['H0_recal_slope'])!, rel: 1e-6));
    final cal = (r.figures['calibration'] as List).cast<Map<String, double>>();
    final rc = ref['calibration'] as List;
    for (var g = 0; g < 5; g++) {
      final row = (rc[g] as List).map((v) => asD(v)!).toList();
      expect(cal[g]['predicted'], closeRel(row[0], rel: 1e-6));
      expect(cal[g]['observed'], closeRel(row[1], rel: 1e-9));
      expect(cal[g]['n'], row[4]);
    }
    // Cohorte plus à risque et plus homogène : le modèle sous-estime le risque et ses prédictions sont trop dispersées.
    expect(r.checks.firstWhere((c) => c.id == 'calibration_slope').status, CheckStatus.violated);
    expect(r.alerts.map((a) => a.code), contains('calibration_slope'));
    expect(r.figures['stage'], 'external');
  });

  test('codage incompatible ou horizon hors suivi : refusés', () {
    final bad = CoxEquation(name: 'x', time: 'time', status: 'deces', eventLevel: 'oui', predictors: const [TermSpec('age')],
        coefficients: const {'age_autre': 0.1}, horizon: 365, baselineCumHazard: 0.2);
    expect(() => externalValidationCox(ext, bad), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'equation_mismatch')));
    final far = CoxEquation.fromJson({...eq.toJson(), 'horizon': 100000});
    expect(() => externalValidationCox(ext, far), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'horizon_beyond_follow_up')));
    expect(() => CoxEquation.fromDevelopment(coxRegression(buildSurvivalDesign(lung, 'time', 'deces', 'oui', terms))),
        throwsA(isA<StatInputError>()));
  });

  test('équation développée en français, appliquée en anglais', () {
    final rEn = withLang(Lang.en, () => externalValidationCox(ext, eq));
    expect(rEn.statistics['c'], closeRel(asD(ref['c'])!, rel: 1e-10));
    expect(rEn.methodName, startsWith('External validation'));
  });
}
