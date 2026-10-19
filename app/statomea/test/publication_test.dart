import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/screens/flow_screen.dart';
import 'package:statomea/screens/references_screen.dart';
import 'package:statomea/screens/reviewer_screen.dart';
import 'package:statomea/services/reviewer_document.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<(AppState, Project)> _demo() async {
  final state = AppState(MemoryStorage());
  await state.load();
  final p = buildDemoAghbs(File('../../packages/statomea_core/test/reference/aghbs_simule.csv').readAsStringSync());
  state.projects.add(p);
  return (state, p);
}

void main() {
  testWidgets('diagramme de flux : saisie, dessin, contrôle, PDF', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2400));
    final (state, p) = await _demo();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: FlowScreen(p))));
    await t.pumpAndSettle();
    expect(find.text('n = ${p.dataset!.rowCount}'), findsWidgets, reason: 'inclus proposés depuis les données');
    await t.enterText(find.byKey(const ValueKey('flow-assessed')), '700');
    await t.enterText(find.byKey(const ValueKey('flow-excluded_reasons')), 'refus : 40\ndossier incomplet : 20');
    await t.pumpAndSettle();
    expect(find.text('n = 700'), findsOneWidget);
    expect(find.text('• refus : 40'), findsOneWidget);
    expect(find.text('n = 60'), findsOneWidget);
    expect(p.flow['assessed'], '700');
    await t.enterText(find.byKey(const ValueKey('flow-included')), '650');
    await t.pumpAndSettle();
    expect(find.textContaining('différent des inclus (650)'), findsOneWidget);
    final pdf = pdfText(await buildFlowPdf(p)).replaceAll(RegExp(r'\s+'), ' ');
    expect(pdf, contains('Diagramme de flux des participants (STROBE)'));
    expect(pdf, contains('n = 700'));
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('Tableau 2 : rôles préremplis, calcul, journal avec formule', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final (state, p) = await _demo();
    p.roles = const VariableRoles(outcome: 'aghbs', eventLevel: 'positif', exposure: 'residence', covariates: ['age']);
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: p, initialMethod: 'table2'))))));
    await t.pumpAndSettle();
    expect(find.text('Prérempli avec les rôles déclarés (issue, exposition, facteurs d\'ajustement).'), findsOneWidget);
    final before = p.journal.length;
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(p.journal.length, before + 1);
    final e = p.journal.last;
    expect(e.methodId, 'association_table');
    expect((e.result['inputs'] as Map)['formula'], isNotNull);
    expect(find.text('Tableau 2 (Word)'), findsOneWidget);
    expect(find.textContaining('OR ajusté', skipOffstage: false), findsWidgets);
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('bibliographie : ajout manuel, clé, numéro, citation dans l\'article', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2000));
    final (state, p) = await _demo();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: ReferencesScreen(p))));
    await t.pumpAndSettle();
    await t.tap(find.text('Ajouter à la main'));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Coulibaly, Modibo Mouctar\nTraoré, Aminata');
    await t.enterText(fields.at(1), 'Hepatitis B in pregnant women in Mali');
    await t.enterText(fields.at(2), 'BMC Infect Dis');
    await t.enterText(fields.at(3), '2021');
    await t.tap(find.text('Ajouter'));
    await t.pumpAndSettle();
    expect(p.references.single.key, 'coulibaly2021');
    expect(find.textContaining('Coulibaly MM, Traoré A. Hepatitis B in pregnant women in Mali. BMC Infect Dis. 2021.'), findsOneWidget);
    expect(find.text('[@coulibaly2021]'), findsOneWidget);
    p.analysisPlan = '${p.analysisPlan}\nIC de Wilson [@coulibaly2021].';
    final art = articleOutline(p);
    expect(art.firstWhere((s) => s.title == 'Analyse statistique').paragraphs.join(' '), contains('Wilson [1]'));
    expect(art.firstWhere((s) => s.title == 'Références').paragraphs.single, startsWith('1. Coulibaly MM'));
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('réponse aux relecteurs : analyse, réponses proposées et modifiables, lettre Word', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 3000));
    final (state, p) = await _demo();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: ReviewerScreen(p))));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Commentaires des relecteurs'), 'Reviewer 1\n1. Please report confidence intervals.\n2. How were missing data handled?\n');
    await t.tap(find.text('Analyser et proposer les réponses'));
    await t.pumpAndSettle();
    expect(p.reviewerItems.length, 2);
    expect(find.text('intervalles de confiance'), findsOneWidget);
    expect(find.text('données manquantes'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Modification apportée').first, 'Résultats, page 8, lignes 12-20.');
    await t.pumpAndSettle();
    expect(p.reviewerItems.first.change, 'Résultats, page 8, lignes 12-20.');
    final letter = docxText(reviewerLetterDocx(p));
    expect(letter, contains('Réponse aux relecteurs'));
    expect(letter, contains('Reviewer 1'));
    expect(letter, contains('Commentaire 2'));
    expect(letter, contains('Please report confidence intervals.'));
    expect(letter, contains('Modification : Résultats, page 8, lignes 12-20.'));
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });
}
