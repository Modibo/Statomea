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
  await t.tap(find.descendant(
          of: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          matching: find.byWidgetPredicate((w) => w is Text && (w.data == item || (w.data ?? '').startsWith('$item ('))))
      .last);
  await t.pumpAndSettle();
}

Future<AppState> panel(WidgetTester t, String method, {Dataset? ds}) async {
  await t.binding.setSurfaceSize(const Size(1200, 3600));
  final state = AppState(MemoryStorage());
  await state.load();
  Project? p;
  if (ds != null) {
    p = state.createProject('Essai');
    p.dataset = ds;
  }
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: p, initialMethod: method)))),
  ));
  await t.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('comparaison de méthodes (saisie directe) : Passing-Bablok puis Deming, figure', (t) async {
    await panel(t, 'passing_bablok');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Régression de Passing-Bablok'), findsWidgets);
    expect(find.text('Comparaison de méthodes'), findsOneWidget);
    expect(find.textContaining('Biais aux niveaux de décision'), findsWidgets);
    await t.tap(find.text('Deming'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Régression de Deming'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('calibration sur des risques prédits en validation externe : Hosmer-Lemeshow, courbe lissée', (t) async {
    await panel(t, 'calibration', ds: parseCsv(File('test/calibration_externe.csv').readAsStringSync()).dataset);
    await pick(t, 'Risque prédit (0 à 1)', 'risque_predit');
    await pick(t, 'Issue observée', 'evenement');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Calibration d\'un modèle de risque (Hosmer-Lemeshow'), findsWidgets);
    expect(find.text('Hosmer-Lemeshow par groupe de risque prédit'), findsOneWidget);
    expect(find.text('Courbe de calibration'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('score de propension : appariement sur l\'étude des statines, équilibre et effet', (t) async {
    await panel(t, 'propensity_matching', ds: parseCsv(File('test/statines_observationnel_simule.csv').readAsStringSync()).dataset);
    await pick(t, 'Traitement (exposition)', 'statine');
    await pick(t, 'Issue (facultatif)', 'evenement');
    for (final v in ['age', 'diabete', 'ldl']) {
      await t.tap(find.text('Ajouter une variable'));
      await t.pumpAndSettle();
      await t.tap(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('$v (')).last);
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Score de propension : appariement'), findsWidgets);
    expect(find.text('Équilibre avant et après ajustement'), findsOneWidget);
    expect(find.text('Équilibre des covariables (love plot)'), findsOneWidget);
    expect(find.textContaining('Différence de risques (ATT)'), findsWidgets);
    await t.tap(find.text('IPTW (ATE)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Différence de risques (ATE)'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
