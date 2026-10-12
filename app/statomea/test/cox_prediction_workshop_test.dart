import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/prediction_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<void> pick(WidgetTester t, String label, String item) async {
  await t.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('atelier de prédiction : modèle pronostique de Cox de bout en bout (lung)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Pronostic');
    p.dataset = parseCsv(File('test/cox_lung.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    Map<String, Object?>? opts;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PredictionWorkshop(project: p, onResult: (r, {options = const {}}) {
              got = r;
              opts = options;
            }),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Délai avec censure (Cox)'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Population cible'), 'cancer du poumon avancé');
    await t.enterText(find.widgetWithText(TextField, 'Usage prévu (décision éclairée par le modèle)'), 'pédagogique');
    await pick(t, 'Durée de suivi', 'time');
    await pick(t, 'Statut (événement / censure)', 'deces');
    await pick(t, 'Modalité « événement »', 'oui');
    await t.enterText(find.widgetWithText(TextField, 'Horizon (en unités de la durée)'), '365');
    await t.enterText(find.widgetWithText(TextField, 'Répliques bootstrap'), '20');
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('age (').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Développer et valider (bootstrap)'));
    // Le calcul tourne dans un isolat : laisser le temps réel s'écouler.
    for (var i = 0; i < 60 && got == null; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await t.pump();
    }
    expect(got, isNotNull);
    expect(got!.methodId, 'prediction_cox_internal');
    expect(got!.statistics['replicates'], 20);
    expect(got!.statistics['horizon'], 365);
    expect(opts!['horizon'], 365);
    expect(got!.alerts.map((a) => a.code), isNot(contains('spec_incomplete')));
    expect(got!.lang, Lang.fr);
  });

  testWidgets('validation externe d\'un modèle de Cox développé dans un autre projet', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3400));
    final state = AppState(MemoryStorage());
    await state.load();
    final dev = state.createProject('Développement');
    dev.dataset = parseCsv(File('test/cox_lung.csv').readAsStringSync()).dataset;
    const terms = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('ph.ecog')];
    state.record(dev, developCoxPredictionModel(buildSurvivalDesign(dev.dataset!, 'time', 'deces', 'oui', terms), horizon: 365, bootstrap: 10,
        targetPopulation: 'lung', intendedUse: 'test'));
    final val = state.createProject('Validation');
    val.dataset = parseCsv(File('../../packages/statomea_core/test/reference/cox_externe_simule.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PredictionWorkshop(project: val, onResult: (r, {options = const {}}) => got = r))),
      ),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Modèle développé dans Statoméa', 'Développement — a001 (Cox)');
    await t.enterText(find.widgetWithText(TextField, 'Population de validation (lieu, période, critères)'), 'cohorte simulée');
    await t.tap(find.text('Valider le modèle sur les données de ce projet'));
    await t.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.methodId, 'external_validation_cox');
    expect(got!.statistics['events'], 274);
    expect(got!.checks.firstWhere((c) => c.id == 'calibration_slope').status, CheckStatus.violated);
  });
}
