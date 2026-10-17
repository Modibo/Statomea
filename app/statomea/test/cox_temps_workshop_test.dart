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
  testWidgets('Cox avec covariable dépendant du temps (greffe de Stanford) : le biais du temps immortel disparaît', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Stanford');
    p.dataset = parseCsv(File('test/greffe_stanford.csv').readAsStringSync()).dataset;
    final got = <AnalysisResult>[];
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got.add(r), initialMethod: 'cox'),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await pick(t, 'Durée de suivi', 'jours');
    await pick(t, 'Statut (événement / censure)', 'deces');
    await pick(t, 'Modalité « événement »', 'oui');
    await t.tap(find.text('Ajouter une variable'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('greffe (').last);
    await t.pumpAndSettle();
    // Analyse naïve : la greffe codée à l'inclusion.
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(got.last.estimates.first.value, lessThan(0.4));
    // Covariable dépendant du temps : greffe à « attente_greffe ».
    await pick(t, 'Changement en cours de suivi : temps', 'attente_greffe');
    await pick(t, 'Covariable qui change (non → oui)', 'greffe');
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    final r = got.last;
    expect(r.methodName, contains('dépendant du temps'));
    expect(r.statistics['n'], 170);
    expect(r.estimates.first.value, closeTo(1.0, 0.25));
    expect(t.takeException(), isNull);
  });
}
