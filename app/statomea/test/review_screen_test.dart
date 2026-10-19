import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/screens/planning_screen.dart';
import 'package:statomea/screens/review_screen.dart';
import 'package:statomea/screens/roadmap_screen.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

const protocole = """
Titre du projet
Facteurs associés à l'anémie chez les femmes enceintes
Objectif principal
Rechercher les facteurs associés à l'anémie chez les femmes enceintes.
Type d'étude
Étude transversale.
Taille de l'échantillon
Avec une prévalence attendue de 40 %, une marge d'erreur de 5 % et un niveau de confiance de 95 %, il faut 369 femmes ; en ajoutant 10 % pour les refus, nous inclurons 406 femmes.
Analyse statistique
Les proportions seront comparées par le test du khi-deux au seuil de 5 %.
""";

void main() {
  testWidgets('relecture : constats, correction appliquée d\'un appui, toutes les corrections, rapport PDF, bandeau de la feuille de route', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 4000));
    final state = AppState(MemoryStorage());
    await state.load();
    final d = protocolFromText(protocole);
    final p = state.createProject(d.title)
      ..question = d.toQuestion()
      ..protocol = Map.of(d.fullSections);
    if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
    p.analysisPlan = d.sections['analysis']!;
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: RoadmapScreen(p))));
    await t.pumpAndSettle();
    expect(find.textContaining('Relecture méthodologique : 2 erreur(s)'), findsOneWidget);
    await t.tap(find.text('Relire et corriger'));
    await t.pumpAndSettle();

    expect(find.text('Relecture et corrections'), findsOneWidget);
    expect(find.text('Majoration pour les pertes mal calculée', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('n = 369 / (1 − 0,1) = 410', skipOffstage: false), findsOneWidget);
    expect(find.text('Calcul de précision refait : 369 sujets', skipOffstage: false), findsOneWidget);
    // Une correction seule.
    final card = find.ancestor(of: find.text('Majoration pour les pertes mal calculée'), matching: find.byType(Card));
    await t.tap(find.descendant(of: card, matching: find.text('Appliquer la correction')));
    await t.pumpAndSettle();
    expect(p.inferred['plannedSampleSize'], '410');
    expect(reviewProject(p).problems.map((f) => f.id), isNot(contains('loss_adjustment')));
    expect(find.text('Majoration pour les pertes mal calculée', skipOffstage: false), findsOneWidget, reason: 'reste dans l\'historique des corrections');
    expect(find.textContaining('Effectif prévu : 410 (au lieu de 406)', skipOffstage: false), findsWidgets); // corrections appliquées
    // Toutes les autres.
    await t.tap(find.textContaining(RegExp(r'^Appliquer les \d+ corrections proposées')));
    await t.pumpAndSettle();
    expect(find.textContaining('Le projet sera modifié ainsi'), findsOneWidget);
    await t.tap(find.text('Appliquer'));
    await t.pumpAndSettle();
    expect(p.corrections.map((c) => c.id), containsAll(['loss_adjustment', 'no_adjustment', 'missing_data']));
    expect(reviewProject(p).fixable, isEmpty);
    expect(state.projects.first.corrections.length, p.corrections.length);
    // Rapport PDF relu par l'extracteur.
    final pdf = pdfText(await buildReviewPdf(p, generatedAt: '2026-10-19'));
    expect(pdf, contains('Relecture méthodologique'));
    expect(pdf, contains('Corrections appliquées'));
    // Retour : le bandeau de la feuille de route est à jour.
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.textContaining('Relecture méthodologique : 0 erreur(s)'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('« Calculer l\'effectif » ouvre le calculateur prérempli avec les hypothèses du protocole', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 4000));
    final state = AppState(MemoryStorage());
    await state.load();
    final d = protocolFromText("""
Titre du projet
Prévalence de l'anémie chez les femmes enceintes
Objectif principal
Déterminer la prévalence de l'anémie chez les femmes enceintes.
Type d'étude
Étude transversale.
Taille de l'échantillon
Avec une prévalence attendue de 7 %, une marge d'erreur de 5 % et un niveau de confiance de 95 %, il faut 100 femmes.
Analyse statistique
Proportion avec IC à 95 % (Wilson), seuil de 5 %, données manquantes décrites.
""");
    final p = state.createProject(d.title)
      ..question = d.toQuestion()
      ..protocol = Map.of(d.fullSections)
      ..analysisPlan = d.sections['analysis']!;
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: ReviewScreen(p))));
    await t.pumpAndSettle();
    final card = find.ancestor(of: find.text('Précision trop large pour la proportion attendue'), matching: find.byType(Card));
    await t.tap(find.descendant(of: card, matching: find.text('Calculer l\'effectif')));
    await t.pumpAndSettle();
    expect(find.textContaining('Prérempli avec les hypothèses lues dans le protocole'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0,07'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0,02'), findsOneWidget);
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('626', skipOffstage: false), findsWidgets);
    expect(p.journal.last.methodId, 'sample_size_proportion');
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('budget et chronogramme : Gantt, coût unitaire saisi, total, enregistrement dans le projet', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final d = protocolFromText("""
Titre du projet
Anémie des femmes enceintes : étude transversale
Type et durée de l'étude
Étude transversale ; la durée totale de l'étude sera de douze mois.
Nombre de sujets nécessaires
Il faut 400 femmes.
Variables étudiées
Les informations suivantes seront recueillies : l'âge, le poids, l'hémoglobine et la glycémie.
""");
    final p = state.createProject(d.title)
      ..question = d.toQuestion()
      ..protocol = Map.of(d.fullSections);
    p.inferred['plannedSampleSize'] = '400';
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: PlanningScreen(p))));
    await t.pumpAndSettle();
    expect(find.text('CHRONOGRAMME (12 MOIS)'), findsOneWidget);
    expect(find.text('Inclusions et recueil des données'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('plan-u_lab')), '2500');
    await t.pumpAndSettle();
    expect(p.planning['u_lab'], '2500');
    expect(find.text('2 000 000 FCFA'), findsOneWidget);
    expect(find.textContaining('Total : 2 200 000 FCFA'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('plan-m_recruit')), '8');
    await t.pumpAndSettle();
    expect(find.text('CHRONOGRAMME (15 MOIS)'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(state.projects.first.planning['m_recruit'], '8');
    expect(t.takeException(), isNull);
  });
}
