import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<void> pick(WidgetTester t, String label, String item) async {
  await t.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await t.pumpAndSettle();
  // Élément du menu ouvert (les noms de colonnes figurent aussi dans les puces d'ajustement).
  await t.tap(find.descendant(
          of: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          matching: find.byWidgetPredicate((w) => w is Text && (w.data == item || (w.data ?? '').startsWith('$item ('))))
      .last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('RMST (saisie directe) : RMST par groupe, différence, figure avec τ', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: 'rmst')))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Temps moyen de survie restreint (RMST) à τ'), findsWidgets);
    expect(find.text('Kaplan-Meier'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('landmark sur la greffe de Stanford (L = 30 jours)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Stanford');
    p.dataset = parseCsv(File('test/greffe_stanford.csv').readAsStringSync()).dataset;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: p, initialMethod: 'landmark')))),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Durée de suivi', 'jours');
    await pick(t, 'Statut', 'deces');
    await pick(t, 'Modalité « événement »', 'oui');
    await pick(t, 'Temps de survenue de l\'exposition', 'attente_greffe');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Analyse landmark à 30'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
