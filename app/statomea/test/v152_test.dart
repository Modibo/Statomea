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

Future<void> panel(WidgetTester t, {String? method, Dataset? ds}) async {
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
}

void main() {
  test('recherche : mots sans accents ni casse, synonymes et méthodes du registre', () {
    expect(searchCalculators('creatinine'), contains('method_comparison'));
    expect(searchCalculators('Survie').first, 'kaplan_meier');
    expect(searchCalculators('comparer deux moyennes'), contains('compare_two'));
    expect(searchCalculators('répétabilité'), ['precision']);
    expect(searchCalculators('fine gray'), containsAll(['cumulative_incidence', 'regression']));
    expect(searchCalculators('xyzzy'), isEmpty);
  });

  testWidgets('familles puis recherche : la puce trouvée ouvre le calculateur', (t) async {
    await panel(t);
    expect(find.text('Familles'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Laboratoire'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Intervalle de référence (EP28)'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'propension');
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Score de propension (appariement, IPTW)'));
    await t.pumpAndSettle();
    expect(find.text('Traitement (exposition)'), findsNothing); // pas de données : message
    expect(find.textContaining('Le score de propension travaille sur un jeu de données'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('intervalle de référence (saisie) puis par sexe sur données', (t) async {
    await panel(t, method: 'reference_interval');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Intervalle de référence (non paramétrique)'), findsWidgets);
    expect(find.text('Intervalle de référence'), findsOneWidget); // figure
    await panel(t, method: 'reference_interval', ds: parseCsv(File('test/creatinine_reference_simule.csv').readAsStringSync()).dataset);
    await pick(t, 'Analyte', 'creatinine');
    await pick(t, 'Sous-groupe (facultatif)', 'sexe');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Harris et Boyd'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('fidélité EP15 avec vérification de la fidélité annoncée', (t) async {
    await panel(t, method: 'precision', ds: parseCsv(File('test/fidelite_ep15_simule.csv').readAsStringSync()).dataset);
    await pick(t, 'Valeur mesurée', 'y');
    await pick(t, 'Jour', 'jour');
    await t.enterText(find.widgetWithText(TextField, 'ÉT de répétabilité annoncé'), '2');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Fidélité de la méthode (EP15'), findsWidgets);
    expect(find.textContaining('Répétabilité annoncée vérifiée'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('équivalence (saisie directe) : TOST puis non-infériorité ; proportions', (t) async {
    await panel(t, method: 'equivalence_tost');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Test d\'équivalence (TOST'), findsWidgets);
    await t.tap(find.text('Non-inf. (↑ meilleur)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Test de non-infériorité'), findsWidgets);
    await t.tap(find.text('Proportions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('équivalence de deux proportions'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('valeur E (RR)', (t) async {
    await panel(t, method: 'e_value');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Valeur E (confusion non mesurée)'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('série interrompue (comptages, population)', (t) async {
    await panel(t, method: 'interrupted_time_series', ds: parseCsv(File('test/serie_interrompue_simule.csv').readAsStringSync()).dataset);
    await t.tap(find.text('Comptages'));
    await t.pumpAndSettle();
    await pick(t, 'Temps (période)', 'mois');
    await pick(t, 'Indicateur', 'admissions');
    await pick(t, 'Population (facultatif)', 'population');
    await t.enterText(find.widgetWithText(TextField, 'Début de l\'intervention (temps)'), '25');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Série chronologique interrompue (régression segmentée, quasi-Poisson)'), findsWidgets);
    expect(find.text('Série chronologique interrompue'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
