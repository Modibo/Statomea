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
  testWidgets('atelier de régression : modèle mixte pour mesures répétées (HbA1c, pente aléatoire du temps)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('HbA1c');
    p.dataset = parseCsv(File('test/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got = r)))),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Modèle', 'Mesures répétées (modèle mixte)');
    await pick(t, 'Issue', 'hba1c');
    await pick(t, 'Sujet (identifiant)', 'patient');
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Pente aléatoire (temps, facultatif)'));
    await t.pumpAndSettle();
    await t.tap(find.text('mois').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('mois (').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.methodId, 'lmm_longitudinal');
    expect(got!.statistics['subjects'], 120);
    expect(got!.statistics['n'], 539);
    expect(got!.figures['trajectories'], isNotNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('sélecteur de modèle à 390 px : aucun débordement', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('x');
    p.dataset = parseCsv(File('test/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) {}))))),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Modèle', 'Fine-Gray (risques concurrents)');
    expect(t.takeException(), isNull);
  });
}
