import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  final ds = parseCsv(File('test/reference/cardiometabolique_simule.csv').readAsStringSync()).dataset;
  const spec = PredictionSpec(
    targetPopulation: 'Adultes de 30 à 70 ans (simulé)',
    outcome: 'evenement_5ans',
    eventLevel: '1',
    horizon: '5 ans',
    intendedUse: 'Orientation vers un bilan',
    predictors: [
      TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('tour_taille'), TermSpec('pas'),
      TermSpec('glycemie'), TermSpec('hdl'), TermSpec('tabac', categorical: true, reference: 'non'),
      TermSpec('atcd_familial', categorical: true, reference: 'non'),
    ],
  );
  final mi = developPredictionModelMI(ds, spec, m: 5, bootstrap: 30, seed: 3);
  final cc = developPredictionModel(ds, spec, bootstrap: 30, seed: 3);
  test('aucun sujet exclu pour un prédicteur manquant (800 vs 777 en cas complets)', () {
    expect(mi.statistics['n'], 800);
    expect(cc.statistics['n'], 777);
    expect((mi.inputs['imputed'] as List), containsAll(['glycemie', 'hdl']));
  });
  test('peu de données manquantes (≈ 3 %) : coefficients et AUC corrigée proches des cas complets', () {
    for (final k in mi.statistics.keys.where((k) => k.startsWith('beta_'))) {
      final se = cc.statistics['se_${k.substring(5)}'] ?? mi.statistics['se_${k.substring(5)}']!;
      expect((mi.statistics[k]! - cc.statistics[k]!).abs(), lessThan(0.5 * se), reason: k);
    }
    expect((mi.statistics['auc_corrected']! - cc.statistics['auc_corrected']!).abs(), lessThan(0.02));
    expect(mi.statistics['auc_corrected'], lessThan(mi.statistics['auc_apparent']!));
  });
  test('imputation refaite dans chaque réplique (contrôle de fuite) ; reproductible à graine égale', () {
    expect(mi.checks.firstWhere((c) => c.id == 'leakage').status, CheckStatus.ok);
    expect(mi.statistics['bootstrap_ok'], 30);
    final again = developPredictionModelMI(ds, spec, m: 5, bootstrap: 30, seed: 3);
    expect(again.statistics['auc_corrected'], mi.statistics['auc_corrected']);
  });
  test('l\'équation combinée peut être validée en externe', () {
    final ext = parseCsv(File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync()).dataset;
    final r = externalValidation(ext, ModelEquation.fromDevelopment(mi));
    expect(r.statistics['auc'], greaterThan(0.7));
  });
}
