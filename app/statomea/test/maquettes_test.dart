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
import 'package:statomea/widgets/calculators.dart';
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

/// Densité des captures : 2 pixels par point, pour un texte net sur les écrans haute densité (page d'accueil, docs).
const pixelRatio = 2.0;

void main() {
  late AppState state;
  late Project demoAghbs, demoMeta, demoPred, demoGwas, demoMr, demoSurv, demoLong;

  setUpAll(() async {
    await _loadFonts();
    state = AppState(MemoryStorage());
    await state.load();
    demoAghbs = buildDemoAghbs(File('assets/demos/aghbs_simule.csv').readAsStringSync());
    demoMeta = buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync());
    demoPred = buildDemoPrediction(File('assets/demos/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 60);
    demoGwas = buildDemoGwas(File('assets/demos/gwas_simule.bed').readAsBytesSync(), File('assets/demos/gwas_simule.bim').readAsStringSync(),
        File('assets/demos/gwas_simule.fam').readAsStringSync(), File('assets/demos/gwas_covariables_simule.csv').readAsStringSync());
    demoMr = buildDemoMr(File('assets/demos/mr_ldl_chd.csv').readAsStringSync());
    demoSurv = buildDemoSurvivalAdvanced(File('assets/demos/risques_concurrents_simule.csv').readAsStringSync());
    // Mesures répétées : projet construit à partir de l'essai simulé HbA1c (modèle mixte avec trajectoires).
    final hb = parseCsv(File('test/hba1c_longitudinal_simule.csv').readAsStringSync(), source: 'hba1c_longitudinal_simule.csv').dataset;
    final lmm = longitudinalMixedModel(hb, const ModelFormula('hba1c', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')], interactions: [('mois', 'bras')]),
        subject: 'patient', slope: 'mois');
    demoLong = state.createProject('Suivi de l\'HbA1c (mesures répétées)')
      ..dataset = hb
      ..journal.add(JournalEntry.fromResult(lmm, id: 'maquette-01', timestamp: 'maquette', data: hb));
    state.projects.remove(demoLong);
    state.projects.addAll([demoMeta, demoAghbs]);
  });

  Future<void> shot(WidgetTester t, String name, Size size, Widget home, {Future<void> Function()? before, double scroll = 0, String? target, double after = 0}) async {
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size * pixelRatio;
    t.view.devicePixelRatio = pixelRatio;
    await t.pumpWidget(_app(state, home));
    await t.pumpAndSettle();
    // Images (logo) : décodage réel avant la capture, sinon le cadre reste vide.
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
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
    if (target != null) {
      // Défilement jusqu'à un repère (titre de figure), puis d'un peu plus pour montrer la figure.
      final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      final candidates = vertical.evaluate().toList();
      double area(Element e) => (e.size?.width ?? 0) * (e.size?.height ?? 0);
      candidates.sort((a, b) => area(b).compareTo(area(a)));
      final main = find.byElementPredicate((e) => e == candidates.first);
      // Sans « .first » : dans une liste, le repère hors écran ne compte pas encore comme visible.
      await t.scrollUntilVisible(find.text(target), 250, scrollable: main);
      await t.pumpAndSettle();
      // Titre de la figure aligné près du haut de l'écran, la figure en dessous.
      await t.runAsync(() => Scrollable.ensureVisible(find.text(target).first.evaluate().first, alignment: 0.02));
      await t.pumpAndSettle();
      if (after != 0) {
        await t.dragFrom(t.getCenter(main), Offset(0, -after));
        await t.pumpAndSettle();
      }
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
    testWidgets('$tag — GWAS', (t) => shot(t, '$tag-09-gwas', size, ProjectScreen(project: demoGwas, initialStep: PStep.interpretation), target: 'Manhattan plot'));
    testWidgets('$tag — causalité', (t) => shot(t, '$tag-10-causalite', size, ProjectScreen(project: demoMr, initialStep: PStep.interpretation), target: 'Randomisation mendélienne'));
    testWidgets('$tag — survie avancée', (t) => shot(t, '$tag-11-survie', size, ProjectScreen(project: demoSurv, initialStep: PStep.interpretation), target: 'Incidence cumulée'));
    testWidgets('$tag — puissance', (t) => shot(t, '$tag-12-puissance', size, const Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: 'power_survival'))),
        before: () async {
          await t.ensureVisible(find.text('Calculer'));
          await t.pumpAndSettle();
          await t.tap(find.text('Calculer'));
          await t.pumpAndSettle();
        }, target: 'Courbe de puissance'));
    testWidgets('$tag — mesures répétées', (t) => shot(t, '$tag-13-mesures-repetees', size, ProjectScreen(project: demoLong, initialStep: PStep.interpretation), target: 'Trajectoires individuelles'));
  }
}
