import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea/widgets/genomics_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

const _ref = '../../packages/statomea_core/test/reference';

Future<void> pick(WidgetTester t, String label, String item) async {
  await t.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await t.pumpAndSettle();
  await t.tap(find.text(item).last);
  await t.pumpAndSettle();
}

Future<(AppState, List<AnalysisResult>)> mount(WidgetTester t, {Project? project, String? initial, bool panel = false}) async {
  await t.binding.setSurfaceSize(const Size(1200, 4000));
  final state = AppState(MemoryStorage());
  await state.load();
  final got = <AnalysisResult>[];
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: panel
              ? CalculatorPanel(project: project, initialMethod: initial)
              : GenomicsWorkshop(project: project, initialMethod: initial, onResult: (r, {options = const {}}) => got.add(r)),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return (state, got);
}

/// Les calculs lourds tournent dans un isolat : laisser le temps réel s'écouler.
Future<void> waitFor(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 80 && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump();
  }
}

void main() {
  testWidgets('association à partir des effectifs, puis Hardy-Weinberg', (t) async {
    final (_, got) = await mount(t);
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.single.methodId, 'genetic_association');
    expect(got.single.estimates.first.value, closeTo(1.60, 0.01));
    await t.tap(find.text('Hardy-Weinberg'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'hardy_weinberg');
  });

  testWidgets('association et balayage depuis un jeu de données', (t) async {
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Génétique');
    p.dataset = parseCsv(File('$_ref/genetique_simule.csv').readAsStringSync()).dataset;
    final (_, got) = await mount(t, project: p);
    await pick(t, 'Variant (génotypes)', 'rs1 (qualitative)');
    await pick(t, 'Statut cas/témoin', 'statut (binaire)');
    await pick(t, 'Modalité « cas »', 'cas');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'genetic_association');
    expect(got.last.statistics['trend_p'], lessThan(0.05));
    await t.tap(find.text('Plusieurs variants'));
    await t.pumpAndSettle();
    await pick(t, 'Statut cas/témoin', 'statut (binaire)');
    await pick(t, 'Modalité « cas »', 'cas');
    for (final s in ['rs1', 'rs2', 'rs3']) {
      await t.tap(find.widgetWithText(FilterChip, s).first);
      await t.pumpAndSettle();
    }
    await t.tap(find.widgetWithText(FilterChip, 'age').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'snp_scan');
    expect(got.last.statistics.keys, containsAll(['p_rs1', 'padj_rs3']));
  });

  testWidgets('pathogènes : concordance mutations–phénotype et diversité', (t) async {
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('TB');
    p.dataset = parseCsv(File('$_ref/pathogenes_simule.csv').readAsStringSync()).dataset;
    final (_, got) = await mount(t, project: p, initial: 'mutation_phenotype');
    await pick(t, 'Phénotype', 'rifampicine (binaire)');
    await t.tap(find.widgetWithText(FilterChip, 'rpoB_S450L'));
    await t.tap(find.widgetWithText(FilterChip, 'rpoB_H445Y'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'mutation_phenotype');
    await t.tap(find.text('Pouvoir discriminant du typage'));
    await t.pumpAndSettle();
    await pick(t, 'Type (MLST, spa, lignée…)', 'lignee (qualitative)');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'type_diversity');
  });

  testWidgets('qPCR : courbe standard, ΔΔCt, limite de détection', (t) async {
    final (_, got) = await mount(t, initial: 'qpcr_standard_curve');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'qpcr_standard_curve');
    expect(got.last.statistics['efficiency'], closeTo(1.0, 0.1));
    await t.tap(find.text('ΔΔCt / Pfaffl'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'qpcr_relative');
    expect(got.last.statistics['ddct'], closeTo(-2.13, 0.01));
    await t.tap(find.text('Limite de détection'));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'qpcr_lod');
  });

  testWidgets('expression différentielle sur l\'exemple simulé', (t) async {
    final (_, got) = await mount(t, initial: 'differential_expression');
    await t.tap(find.text('Exemple simulé (400 gènes, 3 contre 3)'));
    await t.pumpAndSettle();
    expect(find.text('exemple simulé : 400 gènes'), findsOneWidget);
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.isNotEmpty);
    expect(got.single.methodId, 'differential_expression');
    expect(got.single.statistics['n_sig'], greaterThan(20));
  });

  testWidgets('expression : plan à 3 groupes ajusté sur le lot, comparaison choisie pour le volcano', (t) async {
    final (_, got) = await mount(t, initial: 'differential_expression');
    await t.tap(find.text('Exemple à 3 groupes et 2 lots'));
    await t.pumpAndSettle();
    expect(find.textContaining('y ~ groupe + lot — référence A'), findsOneWidget);
    await t.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Comparaison du volcano plot'));
    await t.pumpAndSettle();
    await t.tap(find.text('C − B').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.isNotEmpty);
    final r = got.single;
    expect(r.methodId, 'differential_expression');
    expect((r.figures['volcano'] as Map)['contrast'], 'C − B');
    expect(r.statistics['n_sig_f'], greaterThan(30));
    expect(r.checks.firstWhere((c) => c.id == 'batch').status, CheckStatus.ok);
    // Sans le lot, moins de gènes détectés : l'effet lot gonfle la variance résiduelle.
    await t.enterText(find.widgetWithText(TextField, 'Lot de chaque échantillon (facultatif)'), '');
    await t.pumpAndSettle();
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.length > 1);
    expect(got.last.statistics['n_sig_f'], lessThan(r.statistics['n_sig_f']!));
  });

  testWidgets('expression appariée : effet fixe choisi automatiquement, corrélation intra-sujet au choix, perte sans appariement', (t) async {
    final (_, got) = await mount(t, initial: 'differential_expression');
    await t.tap(find.text('Exemple apparié avant/après (5 patients)'));
    await t.pumpAndSettle();
    expect(find.textContaining('Sujet en effet fixe'), findsOneWidget);
    expect(find.textContaining('y ~ groupe + sujet — référence avant'), findsOneWidget);
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.isNotEmpty);
    final paired = got.last.statistics['n_sig']!;
    expect(paired, greaterThan(25));
    await t.tap(find.text('Corrélation intra-sujet'));
    await t.pumpAndSettle();
    expect(find.textContaining('le sujet est emboîté'), findsOneWidget);
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.length > 1);
    expect(got.last.statistics['block_correlation'], greaterThan(0.5));
    expect(got.last.checks.firstWhere((c) => c.id == 'pairing').status, CheckStatus.ok);
    await t.enterText(find.widgetWithText(TextField, 'Sujet de chaque échantillon (facultatif : mesures répétées, appariement)'), '');
    await t.pumpAndSettle();
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => got.length > 2);
    expect(got.last.statistics['n_sig'], lessThan(paired / 2));
  });

  testWidgets('expression : plan incomplet signalé, calcul refusé avec un message clair', (t) async {
    final (_, got) = await mount(t, initial: 'differential_expression');
    await t.tap(find.text('Exemple simulé (400 gènes, 3 contre 3)'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Groupe de chaque échantillon'), 'A A B B');
    await t.pumpAndSettle();
    expect(find.textContaining('Le plan est incomplet'), findsOneWidget);
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await t.pumpAndSettle();
    expect(find.textContaining('Groupes : 4 valeur(s) pour 6 échantillon(s)'), findsOneWidget);
    expect(got, isEmpty);
  });

  testWidgets('alignement : exemple simulé, la référence 2 est la meilleure correspondance', (t) async {
    final (_, got) = await mount(t, initial: 'local_alignment');
    await t.tap(find.text('Exemple simulé'));
    await t.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^6 séquence\(s\), \d+ lettres$')), findsOneWidget);
    await t.tap(find.text('Rechercher'));
    await waitFor(t, () => got.isNotEmpty);
    expect(got.single.methodId, 'local_alignment');
    expect(got.single.tables.first.rows.first.first, 'ref2');
  });

  testWidgets('randomisation mendélienne : exemple publié LDL-C → maladie coronarienne, IVW = MendelianRandomization', (t) async {
    final (_, got) = await mount(t, initial: 'mendelian_randomization');
    await t.runAsync(() async {
      await t.tap(find.text('Exemple publié : LDL-C et maladie coronarienne (28 variants)'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    await t.tap(find.text('Estimer l\'effet causal'));
    await t.pumpAndSettle();
    final r = got.single;
    expect(r.methodId, 'mendelian_randomization');
    expect(r.statistics['ivw'], closeTo(2.834214, 1e-6));
    expect(r.figures['mr'], isNotNull);
    expect(r.estimates[1].label, contains('OR'));
    expect(r.statistics['weighted_mode'], isNotNull);
    // Multivariée : LDL, HDL, triglycérides (colonnes préremplies par l'exemple).
    await t.tap(find.text('MR multivariée : ajouter d\'autres expositions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Estimer l\'effet causal'));
    await t.pumpAndSettle();
    final mv = got.last;
    expect(mv.methodId, 'mendelian_randomization_mv');
    expect(mv.statistics['theta_beta_hdl'], closeTo(-0.5897134, 1e-6));
  });

  testWidgets('sens causal : exemple simulé X → Y, test de Steiger puis MR inverse sur les instruments de Y', (t) async {
    final (_, got) = await mount(t, initial: 'mr_steiger');
    await t.runAsync(() async {
      await t.tap(find.text('Exemple simulé : sens causal (X → Y)'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    await t.tap(find.text('Tester le sens (Steiger)'));
    await t.pumpAndSettle();
    final st = got.last;
    expect(st.methodId, 'mr_steiger');
    expect(st.statistics['variants_flagged'], 2);
    expect(st.checks.firstWhere((c) => c.id == 'direction').status, CheckStatus.ok);
    // MR inverse : instruments de Y, Y comme exposition.
    await t.tap(find.text('Sens inverse : l\'issue comme exposition (MR bidirectionnelle)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Modalité retenue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Y').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Estimer l\'effet causal'));
    await t.pumpAndSettle();
    final rev = got.last;
    expect(rev.methodId, 'mendelian_randomization');
    expect(rev.methodName, contains('effet de Y sur X'));
    expect(rev.statistics['ivw_p']!, greaterThan(0.05));
  });

  testWidgets('deux GWAS complets : instruments, harmonisation des allèles puis IVW = R (39_gwas_mr.R)', (t) async {
    final (_, got) = await mount(t, initial: 'mendelian_randomization');
    await t.runAsync(() async {
      await t.tap(find.text('Exemple simulé : deux GWAS à harmoniser'));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await t.pumpAndSettle();
    expect(find.textContaining('29 instruments après clumping'), findsOneWidget);
    expect(find.textContaining('palindromique écarté : 2'), findsOneWidget);
    expect(find.textContaining('Issue fournie en OR'), findsOneWidget);
    await t.tap(find.text('Estimer l\'effet causal'));
    await t.pumpAndSettle();
    final r = got.last;
    final ref = (jsonDecode(File('$_ref/gwas_mr.json').readAsStringSync()) as Map)['ivw'] as Map;
    expect(r.methodId, 'mendelian_randomization');
    expect(r.inputs['variants'], 24);
    expect((r.statistics['ivw']! - (ref['estimate'] as num).toDouble()).abs(), lessThan(1e-10));
    // Seuil plus strict : moins d'instruments, harmonisation refaite.
    await t.enterText(find.widgetWithText(TextField, 'Seuil p'), '1e-12');
    await t.tap(find.text('Harmoniser'));
    await t.pumpAndSettle();
    expect(find.textContaining('29 instruments après clumping'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('randomisation mendélienne sans données : message, pas d\'écran d\'erreur', (t) async {
    await mount(t, initial: 'mendelian_randomization');
    expect(find.textContaining('Il faut au moins quatre colonnes numériques'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('panneau de calcul : l\'atelier génomique affiche volcano plot et leçon associée', (t) async {
    await mount(t, initial: 'differential_expression', panel: true);
    expect(find.text('Atelier génomique'), findsWidgets);
    await t.tap(find.text('Exemple simulé (400 gènes, 3 contre 3)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Analyser (TMM + voom + limma)'));
    await waitFor(t, () => find.text('Volcano plot').evaluate().isNotEmpty);
    await t.pumpAndSettle();
    expect(find.text('Volcano plot'), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.text('Leçon associée'), findsOneWidget);
  });

  testWidgets('plan apparié à 390 px et texte à 200 % : aucun débordement', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 6000));
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GenomicsWorkshop(initialMethod: 'differential_expression', onResult: (r, {options = const {}}) {}),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Exemple apparié avant/après (5 patients)'));
    await t.pumpAndSettle();
    expect(find.text('Corrélation intra-sujet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('expression ouverte dans un projet sans colonne de comptages (démo 4) : pas d\'écran gris, message clair', (t) async {
    final p = buildDemoTb(File('assets/demos/tb_rifampicine_simule.csv').readAsStringSync(), File('assets/demos/tb_references_simule.fasta').readAsStringSync(),
        File('assets/demos/tb_isolat_simule.fasta').readAsStringSync());
    await mount(t, project: p, initial: 'differential_expression');
    expect(t.takeException(), isNull);
    expect(find.textContaining('aucune colonne numérique de comptages'), findsOneWidget);
    // Le passage à « Fichier ou exemple » reste possible.
    await t.tap(find.text('Fichier ou exemple'));
    await t.pumpAndSettle();
    await t.tap(find.text('Exemple apparié avant/après (5 patients)'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('Sujet en effet fixe'), findsOneWidget);
  });

  testWidgets('chaque outil × chaque jeu de données des démonstrations : aucun écran d\'erreur', (t) async {
    final projects = [
      buildDemoAghbs(File('assets/demos/aghbs_simule.csv').readAsStringSync()),
      buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync()),
      buildDemoTb(File('assets/demos/tb_rifampicine_simule.csv').readAsStringSync(), File('assets/demos/tb_references_simule.fasta').readAsStringSync(),
          File('assets/demos/tb_isolat_simule.fasta').readAsStringSync()),
      buildDemoPolygenic(File('assets/demos/genotypes_dl_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_dl_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_dl_simule.fam').readAsStringSync(), File('assets/demos/genotypes_dl_traits.csv').readAsStringSync()),
      null,
    ];
    for (final p in projects) {
      for (final m in ['genetic_association', 'hardy_weinberg', 'snp_scan', 'mutation_phenotype', 'type_diversity', 'qpcr_standard_curve', 'qpcr_relative', 'qpcr_lod',
        'differential_expression', 'local_alignment']) {
        await mount(t, project: p, initial: m);
        expect(t.takeException(), isNull, reason: '${p?.id ?? "sans projet"} / $m');
      }
    }
  });
}
