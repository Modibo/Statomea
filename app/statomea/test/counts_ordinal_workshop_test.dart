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

Future<AnalysisResult?> run(WidgetTester t, String csv, String model, String outcome, String predictor) async {
  await t.binding.setSurfaceSize(const Size(1200, 2600));
  final state = AppState(MemoryStorage());
  await state.load();
  final p = state.createProject('x');
  p.dataset = parseCsv(File(csv).readAsStringSync()).dataset;
  AnalysisResult? got;
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RegressionWorkshop(project: p, onResult: (r, {options = const {}}) => got = r)))),
  ));
  await t.pumpAndSettle();
  await pick(t, 'Modèle', model);
  await pick(t, 'Issue', outcome);
  await t.tap(find.text('Ajouter une variable'));
  await t.pumpAndSettle();
  await t.tap(find.textContaining('$predictor (').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Ajuster le modèle'));
  await t.pumpAndSettle();
  return got;
}

void main() {
  testWidgets('comptages : binomiale négative sur les absences scolaires (quine)', (t) async {
    final r = await run(t, 'test/absences_quine.csv', 'Comptages (Poisson, binomiale négative)', 'jours_absence', 'origine');
    expect(r!.methodId, 'count_regression');
    expect(r.statistics['theta'], isNotNull);
    expect(r.estimates.first.label, startsWith('IRR'));
    expect(t.takeException(), isNull);
  });

  testWidgets('issue ordinale : satisfaction du logement (cotes proportionnelles), ordre des modalités prérempli', (t) async {
    final r = await run(t, 'test/satisfaction_logement.csv', 'Issue ordinale (cotes proportionnelles)', 'satisfaction', 'influence');
    expect(r!.methodId, 'ordinal_logistic');
    expect(r.inputs['levels'], ['1_faible', '2_moyenne', '3_elevee']);
    expect(t.takeException(), isNull);
  });

  testWidgets('issue nominale : multinomiale', (t) async {
    final r = await run(t, 'test/satisfaction_logement.csv', 'Issue nominale (multinomiale)', 'satisfaction', 'contact');
    expect(r!.methodId, 'multinomial_logistic');
    expect(t.takeException(), isNull);
  });
}
