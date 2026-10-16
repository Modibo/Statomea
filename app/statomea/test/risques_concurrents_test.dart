import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea/widgets/regression_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<void> pick(WidgetTester t, String label, String item) async {
  await t.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('calculateur de risques concurrents (saisie directe) : incidence cumulée, Fine-Gray et figure', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: 'cumulative_incidence')))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('incidence cumulée de « 1 »'), findsWidgets);
    expect(find.text('Incidence cumulée'), findsWidgets); // titre de la figure
    expect(find.byWidgetPredicate((w) => w is SelectableText && (w.data ?? '').contains('1 − Kaplan-Meier naïf')), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('atelier de régression : modèle de Fine-Gray sur les données simulées (rechute, décès concurrent)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Fine-Gray');
    p.dataset = parseCsv(File('test/risques_concurrents_simule.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got = r, initialMethod: 'fine_gray'),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Durée de suivi', 'mois');
    await pick(t, 'Statut (événement, concurrent, censure)', 'statut');
    await pick(t, 'Événement d\'intérêt', 'rechute');
    await pick(t, 'Modalité « censure »', 'censure');
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('age (').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.methodId, 'fine_gray');
    expect(got!.statistics['events'], 191);
    expect(got!.statistics['competing'], 141);
    // Âge : HR spécifique de cause > 1, sHR < 1.
    expect(got!.statistics['cs_beta_age']!, greaterThan(0));
    expect(got!.statistics['beta_age']!, lessThan(0));
  });
}
