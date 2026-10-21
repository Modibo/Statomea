// Temps des exports (poster, présentation, PDF, Word) sur le projet de démonstration : garde-fou contre les
// régressions de performance (un téléphone modeste est 5 à 10 fois plus lent que la machine de test).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/l10n/gen/app_localizations.dart';
import 'package:statomea/main.dart';
import 'package:statomea/screens/project_screen.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/services/article_document.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/presentation_document.dart';
import 'package:statomea/services/protocol_document.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = buildDemoAghbs(File('../../packages/statomea_core/test/reference/aghbs_simule.csv').readAsStringSync());
  final times = <String, int>{};
  Future<void> time(String label, Future<Object?> Function() f) async {
    await f(); // premier passage : chargement des polices, compilation
    final sw = Stopwatch()..start();
    await f();
    times[label] = sw.elapsedMilliseconds;
  }

  test('exports en moins d\'une seconde chacun (machine de test)', () async {
    await time('poster PowerPoint', () async => posterPptx(p));
    await time('poster PDF', () => buildPosterPdf(p));
    await time('présentation PowerPoint', () async => presentationPptx(p));
    await time('article Word', () async => articleDocx(p));
    await time('protocole Word', () async => protocolDocx(p));
    await time('rapport PDF du projet', () => buildProjectPdf(p, generatedAt: '21/10/2026'));
    await time('relecture PDF', () => buildReviewPdf(p, generatedAt: '21/10/2026'));
    await time('feuille de route PDF', () => buildRoadmapPdf(p, generatedAt: '21/10/2026'));
    times.forEach((k, v) => print('${k.padRight(28)} $v ms'));
    for (final e in times.entries) {
      expect(e.value, lessThan(1000), reason: e.key);
    }
  });

  testWidgets('chaque étape s\'ouvre en moins de 2 s (mode débogage) avec 50 000 lignes', (t) async {
    final csv = File('../../packages/statomea_core/test/reference/aghbs_simule.csv').readAsStringSync();
    final lines = csv.trim().split('\n');
    final big = StringBuffer('${lines.first}\n');
    for (var i = 0; i < 50000; i++) {
      final r = lines[1 + i % (lines.length - 1)];
      big.writeln('"X$i"${r.substring(r.indexOf(','))}');
    }
    final q = buildDemoAghbs(csv);
    final ds = (await t.runAsync(() async => parseCsv(big.toString()).dataset))!;
    q.dataset = ds;
    expect(ds.rowCount, greaterThan(49000));
    final state = AppState(MemoryStorage())..projects.add(q);
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final opened = <String, int>{};
    for (final s in [PStep.export, ...PStep.values]) {
      final sw = Stopwatch()..start();
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            locale: const Locale('fr'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            home: KeyedSubtree(key: UniqueKey(), child: ProjectScreen(project: q, initialStep: s)),
          )));
      await t.pump();
      opened[s.name] = sw.elapsedMilliseconds; // la première ouverture (échauffement) est remplacée à la fin
    }
    opened.forEach((k, v) => print('${k.padRight(16)} $v ms'));
    for (final e in opened.entries) {
      expect(e.value, lessThan(2000), reason: e.key);
    }
  });
}
