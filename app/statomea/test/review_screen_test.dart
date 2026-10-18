import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
}
