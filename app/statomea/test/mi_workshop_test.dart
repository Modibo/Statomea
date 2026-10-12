import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/regression_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<void> pick(WidgetTester t, String label, String item) async {
  await t.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('atelier de régression : logistique avec imputation multiple (HDL manquant)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('MI');
    p.dataset = parseCsv(File('test/cardiometabolique_simule.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got = r, initialMethod: 'logistic_regression')))),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Issue', 'evenement_5ans');
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('hdl (').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Imputation multiple des valeurs manquantes (MICE, règles de Rubin)'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Nombre d\'imputations m'), '5');
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(got?.methodId, 'mi_logistic');
    expect(got!.statistics['n'], 800); // aucun sujet exclu
    expect(got!.figures['miChains'], isNotNull);
  });
}
