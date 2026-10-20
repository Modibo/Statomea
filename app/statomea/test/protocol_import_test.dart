import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/screens/projects_screen.dart';
import 'package:statomea/screens/steps/question_steps.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;
import 'package:statomea_core/statomea_core.dart' as core show Step;

Uint8List docx(List<String> paragraphs) {
  final xml = '<?xml version="1.0"?><w:document xmlns:w="w"><w:body>${[for (final l in paragraphs) '<w:p><w:r><w:t>${l.replaceAll('&', '&amp;').replaceAll("'", '&apos;')}</w:t></w:r></w:p>'].join()}</w:body></w:document>';
  final data = utf8.encode(xml);
  return Uint8List.fromList(ZipEncoder().encode(Archive()..addFile(ArchiveFile('word/document.xml', data.length, data))));
}

void main() {
  testWidgets('nouvelle question : caractéristiques, PICO et plan d\'analyse déduits pendant la saisie', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Q');
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: QuestionStep(p)))));
    await t.enterText(find.widgetWithText(TextField, 'Question de recherche'), 'Quelle est la prévalence de l\'AgHBs chez les femmes enceintes à Bamako ?');
    await t.pump(const Duration(milliseconds: 800));
    await t.pumpAndSettle();
    expect(p.question.design, StudyDesign.crossSectional);
    expect(p.question.population, 'femmes enceintes');
    expect(find.text('femmes enceintes'), findsOneWidget); // champ PICO rempli
    expect(find.text('Plan : étude transversale'), findsOneWidget);
    expect(find.textContaining('Méthode proposée : Proportion'), findsOneWidget);
    expect(p.analysisPlan, contains('Analyse principale'));
    await t.pump(const Duration(seconds: 3)); // enregistrement différé
    expect(t.takeException(), isNull);
  });

  testWidgets('import d\'un protocole Word : aperçu, création du projet, feuille de route en 10 étapes', (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 5200));
    final state = AppState(MemoryStorage());
    await state.load();
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })))));
    final bytes = docx([
      'Efficacité de la vitamine D chez l\'adulte hypertendu',
      'Question de recherche : La supplémentation en vitamine D réduit-elle la pression artérielle systolique à 12 mois chez les adultes hypertendus ?',
      'Schéma de l\'étude',
      'Essai randomisé contrôlé, deux bras parallèles.',
      'Comparateur : placebo.',
      'Critère de jugement principal',
      'Pression artérielle systolique à 12 mois (mmHg).',
      'Nombre de sujets nécessaires',
      '240 patients.',
    ]);
    final fut = importProtocolDocument(ctx, bytes, 'protocole.docx');
    await t.pumpAndSettle();
    expect(find.textContaining('essai contrôlé randomisé'), findsOneWidget);
    expect(find.textContaining('240'), findsOneWidget);
    await t.tap(find.text('Créer le projet'));
    await t.pumpAndSettle();
    expect(find.text('Feuille de route'), findsOneWidget);
    for (final s in core.Step.values) {
      expect(find.text(stepLabel(s)), findsOneWidget);
    }
    expect(find.text('Proposé — à vérifier'), findsWidgets);
    final p = state.projects.first;
    expect(p.question.design, StudyDesign.rct);
    expect(p.inferred['design'], 'rct');
    await t.pageBack();
    await t.pumpAndSettle();
    expect((await fut)!.id, p.id);
    expect(t.takeException(), isNull);
  });

  test('feuille de route en PDF : 10 étapes dans l\'ordre (relue par l\'extracteur)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final p = Project(id: 'r', title: 'Vitamine D', createdAt: '');
    p.question = applyInference(ResearchQuestion(text: 'Essai randomisé : la vitamine D réduit-elle la pression artérielle chez les adultes ?'), inferQuestion('Essai randomisé : la vitamine D réduit-elle la pression artérielle chez les adultes ?')).$1;
    p.analysisPlan = draftAnalysisPlan(p.question);
    final text = pdfText(await buildRoadmapPdf(p, generatedAt: '18/10/2026')).replaceAll(RegExp(r'\s+'), ' ');
    var last = -1;
    for (final s in core.Step.values) {
      final i = text.indexOf(stepLabel(s));
      expect(i, greaterThan(last), reason: stepLabel(s));
      last = i;
    }
    expect(text, contains('Plan d\'analyse proposé'));
  });
}
