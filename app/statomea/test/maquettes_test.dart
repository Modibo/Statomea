// Maquettes (livrable 3) produites à partir de l'application réelle.
// Régénération : flutter test test/maquettes_test.dart --update-goldens
// puis copie de test/goldens/*.png vers docs/maquettes/.
@Tags(['maquettes'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/l10n/gen/app_localizations.dart';
import 'package:statomea/main.dart';
import 'package:statomea/screens/home_screen.dart';
import 'package:statomea/screens/lesson_screen.dart';
import 'package:statomea/screens/project_screen.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
  await load('NotoSans', ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf']);
  await load('NotoSansMath', ['assets/fonts/NotoSansMath-Regular.ttf']);
  await load('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

Widget _app(AppState s, Widget home) => ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

const sizes = {'mobile': Size(390, 844), 'ordinateur': Size(1366, 860)};

void main() {
  late AppState state;
  late Project demoAghbs, demoMeta, demoPred;

  setUpAll(() async {
    await _loadFonts();
    state = AppState(MemoryStorage());
    await state.load();
    demoAghbs = buildDemoAghbs(File('assets/demos/aghbs_simule.csv').readAsStringSync());
    demoMeta = buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync());
    demoPred = buildDemoPrediction(File('assets/demos/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 60);
    state.projects.addAll([demoMeta, demoAghbs]);
  });

  Future<void> shot(WidgetTester t, String name, Size size, Widget home, {Future<void> Function()? before, double scroll = 0}) async {
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(_app(state, home));
    await t.pumpAndSettle();
    if (before != null) await before();
    if (scroll != 0) {
      final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      // Défileur principal = celui de plus grande surface (le rail d'étapes est étroit, les champs texte petits).
      final candidates = vertical.evaluate().toList();
      double area(Element e) => (e.size?.width ?? 0) * (e.size?.height ?? 0);
      candidates.sort((a, b) => area(b).compareTo(area(a)));
      await t.dragFrom(t.getCenter(find.byElementPredicate((e) => e == candidates.first)), Offset(0, -scroll));
      await t.pumpAndSettle();
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  for (final e in sizes.entries) {
    final tag = e.key, size = e.value;
    testWidgets('$tag — accueil', (t) => shot(t, '$tag-01-accueil', size, const HomeScreen()));
    testWidgets('$tag — question', (t) => shot(t, '$tag-02-question', size, ProjectScreen(project: demoAghbs)));
    testWidgets('$tag — contrôle des données', (t) => shot(t, '$tag-03-donnees', size, ProjectScreen(project: demoAghbs, initialStep: PStep.dataControl), scroll: 900));
    testWidgets('$tag — choix de la méthode', (t) => shot(t, '$tag-04-methode', size, ProjectScreen(project: demoAghbs, initialStep: PStep.methodChoice)));
    testWidgets('$tag — résultat et forest plot', (t) => shot(t, '$tag-05-forest', size, ProjectScreen(project: demoMeta, initialStep: PStep.interpretation), scroll: tag == 'mobile' ? 1450 : 1250));
    testWidgets('$tag — prédiction', (t) => shot(t, '$tag-06-prediction', size, ProjectScreen(project: demoPred, initialStep: PStep.interpretation), scroll: 600));
    testWidgets('$tag — audit', (t) => shot(t, '$tag-07-audit', size, ProjectScreen(project: demoAghbs, initialStep: PStep.audit), before: () async {
          await t.tap(find.text('Lancer l\'audit'));
          await t.pumpAndSettle();
        }, scroll: 350));
    testWidgets('$tag — leçon', (t) => shot(t, '$tag-08-lecon', size, LessonScreen(state.lessons.firstWhere((l) => l.id == 'or_rr'))));
  }
}
