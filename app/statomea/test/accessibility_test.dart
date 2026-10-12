// Accessibilité : règles de Flutter (cibles tactiles ≥ 48 dp Android / 44 pt iOS,
// cibles étiquetées pour les lecteurs d'écran, contraste du texte WCAG AA) sur
// tous les écrans, en thème clair et sombre, puis texte agrandi à 200 % sans
// débordement à 390 px de large.
@Tags(['accessibilite'])
library;

import 'dart:io';
import 'dart:math' as math;

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
import 'package:statomea/widgets/common.dart';
import 'package:statomea/widgets/result_view.dart';
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

Widget _app(AppState s, Widget home, {Brightness b = Brightness.light, double textScale = 1}) => ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
        home: home,
      ),
    );

void main() {
  late AppState state;
  late Project demoAghbs, demoMeta, demoPred, rnaPlan, demoTb, demoGwas, demoPoly, demoMr;
  late AnalysisResult ldsc, rgResult, prsResult, glmmResult, mrResult;

  setUpAll(() async {
    await _loadFonts();
    state = AppState(MemoryStorage());
    await state.load();
    demoAghbs = buildDemoAghbs(File('assets/demos/aghbs_simule.csv').readAsStringSync());
    demoMeta = buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync());
    demoPred = buildDemoPrediction(File('assets/demos/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 20);
    demoTb = buildDemoTb(File('assets/demos/tb_rifampicine_simule.csv').readAsStringSync(), File('assets/demos/tb_references_simule.fasta').readAsStringSync(),
        File('assets/demos/tb_isolat_simule.fasta').readAsStringSync());
    demoGwas = buildDemoGwas(File('assets/demos/gwas_simule.bed').readAsBytesSync(), File('assets/demos/gwas_simule.bim').readAsStringSync(),
        File('assets/demos/gwas_simule.fam').readAsStringSync(), File('assets/demos/gwas_covariables_simule.csv').readAsStringSync());
    demoPoly = buildDemoPolygenic(File('assets/demos/genotypes_dl_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_dl_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_dl_simule.fam').readAsStringSync(), File('assets/demos/genotypes_dl_traits.csv').readAsStringSync());
    demoMr = buildDemoMr(File('assets/demos/mr_ldl_chd.csv').readAsStringSync());
    state.projects.addAll([demoMeta, demoAghbs]);
    final ld = parsePlinkBed(File('assets/demos/genotypes_dl_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_dl_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_dl_simule.fam').readAsStringSync());
    final ldDs = genotypeDataset(ld);
    final chi2 = <double>[];
    snpScan(ldDs, ldDs.names.sublist(ldDs.names.length - ld.variantCount), 'statut', 'cas', chi2Out: chi2);
    ldsc = ldscFromScan(ld, chi2, n: ld.sampleCount).result;
    final trCsv = parseCsv(File('assets/demos/genotypes_dl_traits.csv').readAsStringSync()).dataset;
    final rgDs = genotypeDataset(ld, covariates: {for (final c in ['diabete', 'coronaropathie']) c: {for (var i = 0; i < trCsv.rowCount; i++) trCsv.cell(i, 'id')!: trCsv.cell(i, c)!}});
    final rgNames = rgDs.names.sublist(rgDs.names.length - ld.variantCount);
    final za = <double>[], zb = <double>[];
    snpScan(rgDs, rgNames, 'diabete', 'oui', zOut: za);
    snpScan(rgDs, rgNames, 'coronaropathie', 'oui', zOut: zb);
    final rg = geneticCorrelationFromScans(ld, za, zb, n: ld.sampleCount, trait1: 'diabete', trait2: 'coronaropathie').result;
    rgResult = rg;
    final pg = parsePlinkBed(File('assets/demos/genotypes_prs_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_prs_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_prs_simule.fam').readAsStringSync());
    final fg = parsePlinkBed(File('assets/demos/genotypes_familles_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_familles_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_familles_simule.fam').readAsStringSync());
    final fp = parseCsv(File('assets/demos/genotypes_familles_phenotypes.csv').readAsStringSync()).dataset;
    final ill = {for (var i = 0; i < fp.rowCount; i++) fp.cell(i, 'id')!: fp.cell(i, 'maladie') == 'oui' ? 1.0 : 0.0};
    glmmResult = glmmScan(fg, [for (final s in fg.samples) ill[s]], grmVariants: ldPrune(fg), outcomeName: 'maladie').result;
    final mrDs = parseCsv(File('assets/demos/mr_ldl_chd.csv').readAsStringSync()).dataset;
    List<double> mrCol(String c) => [for (var i = 0; i < mrDs.rowCount; i++) double.parse(mrDs.cell(i, c)!)];
    mrResult = mendelianRandomization(mrCol('beta_ldl'), mrCol('se_ldl'), mrCol('beta_chd'), mrCol('se_chd'), exposure: 'LDL-C', outcome: 'CHD', iterations: 500).result;
    prsResult = polygenicRiskScore(pg, [for (final p in pg.phenotype) p == null ? null : (p == 2 ? 1.0 : 0.0)], outcomeName: 'maladie').result;
    final e = exampleRnaSeqDesign(genes: 200);
    rnaPlan = Project(id: 'rna', title: 'RNA-seq', createdAt: '2026-10-11')
      ..dataset = Dataset.fromColumns({'gene': e.genes, for (var j = 0; j < e.samples.length; j++) e.samples[j]: [for (final r in e.counts) r[j].toInt()]});

  });

  Map<String, Widget> screens() => {
        'accueil': const HomeScreen(),
        for (final s in PStep.values) 'projet AgHBs — ${s.name}': ProjectScreen(project: demoAghbs, initialStep: s),
        'métaanalyse — calcul': ProjectScreen(project: demoMeta, initialStep: PStep.computation),
        'métaanalyse — interprétation': ProjectScreen(project: demoMeta, initialStep: PStep.interpretation),
        'prédiction — calcul': ProjectScreen(project: demoPred, initialStep: PStep.computation),
        'prédiction — interprétation': ProjectScreen(project: demoPred, initialStep: PStep.interpretation),
        'tuberculose — calcul': ProjectScreen(project: demoTb, initialStep: PStep.computation),
        'tuberculose — interprétation': ProjectScreen(project: demoTb, initialStep: PStep.interpretation),
        'tuberculose — audit': ProjectScreen(project: demoTb, initialStep: PStep.audit),
        'pangénomique — calcul': ProjectScreen(project: demoGwas, initialStep: PStep.computation),
        'pangénomique — interprétation': ProjectScreen(project: demoGwas, initialStep: PStep.interpretation),
        'polygénie — calcul': ProjectScreen(project: demoPoly, initialStep: PStep.computation),
        'polygénie — audit': ProjectScreen(project: demoPoly, initialStep: PStep.audit),
        'causalité — calcul': ProjectScreen(project: demoMr, initialStep: PStep.computation),
        'causalité — interprétation': ProjectScreen(project: demoMr, initialStep: PStep.interpretation),
        'leçon': LessonScreen(state.lessons.firstWhere((l) => l.id == 'or_rr')),
        for (final k in calculatorKinds.where((k) => k.$4 != 'Ateliers'))
          'calculateur ${k.$1}': Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: k.$1))),
        'leçon génétique': LessonScreen(state.lessons.firstWhere((l) => l.id == 'genetics')),
        'régression LD score — résultat': Scaffold(body: SingleChildScrollView(child: ResultView(ldsc))),
        'corrélation génétique — résultat': Scaffold(body: SingleChildScrollView(child: ResultView(rgResult))),
        'modèle mixte logistique — résultat': Scaffold(body: SingleChildScrollView(child: ResultView(glmmResult))),
        'randomisation mendélienne — résultat': Scaffold(body: SingleChildScrollView(child: ResultView(mrResult))),
        'score polygénique — résultat': Scaffold(body: SingleChildScrollView(child: ResultView(prsResult))),
        'leçon GWAS': LessonScreen(state.lessons.firstWhere((l) => l.id == 'gwas')),
        'leçon polygénie': LessonScreen(state.lessons.firstWhere((l) => l.id == 'polygenic')),
        'leçon causalité': LessonScreen(state.lessons.firstWhere((l) => l.id == 'causal_mr')),
        for (final m in ['genetic_association', 'genotype_qc', 'mutation_phenotype', 'qpcr_relative', 'differential_expression', 'local_alignment', 'mendelian_randomization', 'mendelian_randomization_mv'])
          'atelier génomique — $m': Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: m))),
        'atelier génomique — plan d\'expression (projet)': Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: rnaPlan, initialMethod: 'differential_expression'))),
      };

  Future<void> pumpScreen(WidgetTester t, Widget w, {Brightness b = Brightness.light, double textScale = 1, double height = 844}) async {
    final size = Size(390, height);
    await t.binding.setSurfaceSize(size);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    // Clé neuve : sinon Flutter garde l'état de l'écran précédent (même étape affichée partout).
    await t.pumpWidget(_app(state, KeyedSubtree(key: UniqueKey(), child: w), b: b, textScale: textScale));
    await t.pumpAndSettle();
  }

  for (final b in Brightness.values) {
    testWidgets('règles d\'accessibilité — thème ${b.name}', (t) async {
      final h = t.ensureSemantics();
      final problems = <String>[];
      final guidelines = {
        'cible Android < 48 dp': androidTapTargetGuideline,
        'cible iOS < 44 pt': iOSTapTargetGuideline,
        'cible sans libellé': labeledTapTargetGuideline,
      };
      // 844 px : écran de téléphone ; 3000 px : tout le contenu sous la ligne de flottaison est aussi évalué.
      for (final height in [844.0, 3000.0]) {
        for (final s in screens().entries) {
          await pumpScreen(t, s.value, b: b, height: height);
          for (final g in guidelines.entries) {
            final r = await g.value.evaluate(t);
            if (!r.passed) problems.add('[${s.key}, ${height.round()} px] ${g.key} : ${(r.reason ?? '').trim().split('\n').take(6).join(' | ')}');
          }
        }
      }
      h.dispose();
      expect(problems, isEmpty, reason: problems.join('\n\n'));
    });
  }

  // Contraste : calcul exact du rapport WCAG sur les couleurs réellement employées. La règle
  // textContrastGuideline de Flutter, qui échantillonne des pixels, donne des faux positifs sur les
  // tableaux à défilement horizontal (cellules à moitié hors champ) et les étiquettes sur deux lignes.
  double luminance(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double ratio(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final b in Brightness.values) {
    test('contraste WCAG des couleurs du thème — ${b.name}', () {
      final cs = buildTheme(b).colorScheme;
      final demo = demoBannerColors(b);
      final text = <String, (Color, Color)>{
        'texte / fond': (cs.onSurface, cs.surface),
        'texte secondaire / fond': (cs.onSurfaceVariant, cs.surface),
        'texte secondaire / carte': (cs.onSurfaceVariant, cs.surfaceContainerLow),
        'lien, étiquette de section / fond': (cs.primary, cs.surface),
        'étiquette de section / carte': (cs.primary, cs.surfaceContainerLow),
        'bouton plein': (cs.onPrimary, cs.primary),
        'puce sélectionnée': (cs.onSecondaryContainer, cs.secondaryContainer),
        'pastille « méthode validée »': (cs.onPrimaryContainer, cs.primaryContainer),
        'valeur corrigée / fond': (cs.error, cs.surface),
        'bandeau de démonstration': (demo.foreground, demo.background),
      };
      // Icônes porteuses de sens (statut, gravité) : 3:1 (WCAG 1.4.11).
      final icons = <String, Color>{
        'info': Colors.blueGrey,
        'à surveiller': const Color(0xFFB7791F),
        'grave': const Color(0xFFC05621),
        'bloquant': cs.error,
        'satisfait': Colors.green.shade700,
      };
      final problems = <String>[
        for (final e in text.entries)
          if (ratio(e.value.$1, e.value.$2) < 4.5) '${e.key} : ${ratio(e.value.$1, e.value.$2).toStringAsFixed(2)} < 4,5',
        for (final e in icons.entries)
          for (final bg in [cs.surface, cs.surfaceContainerLow])
            if (ratio(e.value, bg) < 3) 'icône ${e.key} : ${ratio(e.value, bg).toStringAsFixed(2)} < 3',
      ];
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  testWidgets('lecteur d\'écran : titres annoncés comme titres, graphiques décrits', (t) async {
    final h = t.ensureSemantics();
    await pumpScreen(t, ProjectScreen(project: demoAghbs), height: 3000);
    expect(t.getSemantics(find.bySemanticsLabel('1. Question biomédicale').last).flagsCollection.isHeader, isTrue);
    await pumpScreen(t, ProjectScreen(project: demoMeta, initialStep: PStep.interpretation), height: 6000);
    // Étiquette de section : annoncée comme titre, dans sa casse d'origine (pas « RÉSULTAT CALCULÉ »).
    final section = find.bySemanticsLabel(RegExp('Résultat calculé'));
    expect(section, findsWidgets);
    expect(t.getSemantics(section.first).flagsCollection.isHeader, isTrue);
    expect(find.bySemanticsLabel('RÉSULTAT CALCULÉ'), findsNothing);
    // Forest plot : nombre d'études et effet combiné lus à voix haute.
    final forest = find.bySemanticsLabel(RegExp(r'^Forest plot : 13 études, effet combiné 0,489'));
    expect(forest, findsWidgets);
    expect(t.getSemantics(forest.first).flagsCollection.isImage, isTrue);
    h.dispose();
  });

  testWidgets('texte agrandi à 200 % : aucun débordement à 390 px', (t) async {
    final problems = <String>[];
    final previous = FlutterError.onError;
    String current = '';
    FlutterError.onError = (d) => problems.add('[$current] ${d.exceptionAsString().split('\n').first} — ${d.informationCollector?.call().map((e) => e.toString()).where((l) => l.contains('lib/')).take(1).join() ?? ''}');
    for (final s in screens().entries) {
      current = s.key;
      await pumpScreen(t, s.value, textScale: 2);
    }
    FlutterError.onError = previous;
    expect(problems.toSet().toList(), isEmpty, reason: problems.toSet().join('\n'));
  });
}
