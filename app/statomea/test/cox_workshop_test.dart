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
  testWidgets('atelier de régression : modèle de Cox de bout en bout (lung)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2400));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Cox');
    p.dataset = parseCsv(File('test/cox_lung.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got = r, initialMethod: 'cox'),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Durée de suivi', 'time');
    await pick(t, 'Statut (événement / censure)', 'deces');
    await pick(t, 'Modalité « événement »', 'oui');
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('age (').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.methodId, 'cox');
    expect(got!.estimates.first.label, 'HR — age');
    expect(got!.statistics['events'], 165); // lung complet sur l'âge : 228 sujets, 165 décès
  });
}
