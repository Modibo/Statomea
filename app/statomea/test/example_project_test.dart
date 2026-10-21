// Projet d'exemple : protocole fictif en Word (erreurs de méthode volontaires) et données simulées, ouverts depuis
// l'écran Projets ou téléchargés depuis la page d'accueil (EXAMPLE_OUT=dossier écrit les fichiers à publier).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/l10n/gen/app_localizations.dart';
import 'package:statomea/screens/projects_screen.dart';
import 'package:statomea/screens/roadmap_screen.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/example_project.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  tearDown(() => setLang(Lang.fr));

  test('Word d\'exemple (FR et EN) : relu comme un protocole importé, six erreurs cachées retrouvées', () {
    for (final lang in Lang.values) {
      setLang(lang);
      final docx = exampleProtocolDocx();
      final text = documentText(docx, exampleProtocolFileName);
      final d = protocolFromText(text);
      expect(d.title, startsWith(lang == Lang.fr ? 'Portage de l\'antigène HBs' : 'Hepatitis B surface antigen'));
      expect(d.sampleSize, 498);
      final p = Project(id: 'e', title: d.title, createdAt: '')
        ..question = d.toQuestion()
        ..protocol = Map.of(d.fullSections)
        ..analysisPlan = d.sections['analysis'] ?? '';
      p.inferred['plannedSampleSize'] = '${d.sampleSize}';
      final ids = reviewProject(p).findings.map((f) => f.id).toSet();
      expect(ids, containsAll(exampleProtocolErrors), reason: lang.name);
      final out = Platform.environment['EXAMPLE_OUT'];
      if (out != null) {
        File('$out/$exampleProtocolFileName').writeAsBytesSync(docx);
        File('assets/demos/aghbs_simule.csv').copySync('$out/$exampleDataFileName');
      }
    }
  });

  testWidgets('écran Projets : « Projet d\'exemple » crée le projet avec ses données et ouvre la feuille de route', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2400));
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('fr'),
            home: Scaffold(body: ProjectsScreen()))));
    await t.pumpAndSettle();
    await t.tap(find.text('Projet d\'exemple'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // lecture de l'asset
    await t.pumpAndSettle();
    expect(find.text('Projet depuis « protocole-exemple-aghbs.docx »'), findsOneWidget);
    expect(find.textContaining('Plan : étude transversale', skipOffstage: false), findsWidgets);
    await t.tap(find.text('Créer le projet'));
    await t.pumpAndSettle();
    expect(find.byType(RoadmapScreen), findsOneWidget);
    final p = state.projects.single;
    expect(p.dataset!.rowCount, 640);
    expect(p.dataset!.source, contains('simulé'));
    expect(p.inferred['plannedSampleSize'], '498');
    expect(reviewProject(p).problems.where((f) => f.level == ReviewLevel.error).length, greaterThanOrEqualTo(3));
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });
}
