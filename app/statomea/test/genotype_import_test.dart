import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/genotype_import.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

const _ref = '../../packages/statomea_core/test/reference';

Future<(GlobalKey<GenotypeImportToolState>, List<AnalysisResult>)> mount(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(1200, 3000));
  final state = AppState(MemoryStorage());
  await state.load();
  final key = GlobalKey<GenotypeImportToolState>();
  final got = <AnalysisResult>[];
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GenotypeImportTool((r, {options = const {}}) => got.add(r), key: key)))),
  ));
  await t.pumpAndSettle();
  return (key, got);
}

Future<void> waitFor(WidgetTester t, bool Function() done, {int tries = 80}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump();
  }
}

void main() {
  testWidgets('exemple PLINK binaire : contrôle de qualité puis balayage ajusté (sexe, âge) = glm de R', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadExample());
    await t.pumpAndSettle();
    expect(find.textContaining('genotypes_simule.bed'), findsOneWidget);
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    expect(got.single.methodId, 'genotype_qc');
    expect(got.single.statistics['kept_variants'], 237);
    expect(got.single.statistics['kept_samples'], 294);
    await t.pumpAndSettle();
    expect(find.textContaining('Balayage des 237 variants retenus chez 294 sujets'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'age'));
    await t.pumpAndSettle();
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 1);
    final scan = got.last;
    expect(scan.methodId, 'snp_scan');
    final ref = jsonDecode(File('$_ref/genotypes.json').readAsStringSync())['scan'] as Map;
    final k = (ref['snps'] as List).indexOf('rs00020');
    expect(scan.statistics['p_rs00020'], closeTo((ref['p'] as List)[k] as double, 1e-9));
  });

  testWidgets('stratification : λ élevé sans ajustement, ACP, puis λ ramené près de 1 avec CP1–CP2', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadStratifiedExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 1);
    final raw = got.last;
    expect(raw.methodId, 'snp_scan');
    expect(raw.statistics['lambda_gc'], greaterThan(2));
    expect((raw.figures['manhattan'] as Map)['chrom'], isNotEmpty);
    expect((raw.figures['qq'] as Map)['lambda'], raw.statistics['lambda_gc']);
    expect(raw.checks.firstWhere((c) => c.id == 'stratification').status, CheckStatus.warning);
    await t.pumpAndSettle();
    await t.tap(find.text('ACP (stratification de population)'));
    await waitFor(t, () => got.length > 2);
    await t.pumpAndSettle();
    expect(got.last.methodId, 'genotype_pca');
    expect(got.last.figures['pca'], isNotNull);
    expect(find.textContaining('ACP calculée : CP1 à CP10 disponibles'), findsOneWidget);
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 3);
    final adj = got.last;
    expect(adj.statistics['lambda_gc'], lessThan(1.2));
    expect((adj.inputs['covariates'] as List).map((c) => (c as Map)['variable']), containsAll(['PC1', 'PC2']));
  });

  testWidgets('apparentement : doublons et apparentés détectés, exclusion appliquée à l\'ACP et au balayage', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadRelatedExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    final n0 = key.currentState!.analysisData!.sampleCount;
    await t.tap(find.text('Apparentement (KING)'));
    await waitFor(t, () => got.length > 1);
    await t.pumpAndSettle();
    final kin = got.last;
    expect(kin.methodId, 'genotype_kinship');
    expect([kin.statistics['pairs_duplicate'], kin.statistics['pairs_degree1'], kin.statistics['pairs_degree2'], kin.statistics['pairs_degree3']], [4, 25, 1, 1]);
    expect(kin.figures['king'], isNotNull);
    final removed = kin.statistics['removed']!.toInt();
    expect(removed, 15);
    expect(key.currentState!.analysisData!.sampleCount, n0 - removed);
    expect(find.textContaining('Écarter les 15 sujets apparentés'), findsOneWidget);
    await t.tap(find.byType(SwitchListTile));
    await t.pumpAndSettle();
    expect(key.currentState!.analysisData!.sampleCount, n0);
  });

  testWidgets('modèle mixte : exemple familial, trait quantitatif, apparentés gardés, variant causal retrouvé', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadFamilyExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    expect(key.currentState!.mixed, isTrue);
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Issue (cas/témoin)'));
    await t.pumpAndSettle();
    await t.tap(find.text('trait').last);
    await t.pumpAndSettle();
    expect(find.text('Modalité « cas »'), findsNothing);
    for (final c in ['sexe', 'age']) {
      await t.tap(find.widgetWithText(FilterChip, c));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 1);
    final r = got.last;
    expect(r.methodId, 'lmm_scan');
    // Tous les sujets retenus par le contrôle de qualité (apparentés compris) entrent dans le modèle mixte.
    expect(r.inputs['samples'], key.currentState!.cleaned!.sampleCount);
    expect(r.estimates[1].label, contains('m0777'));
    expect(r.statistics['lambda_gc'], lessThan(1.1));
    expect(r.figures['qq'], isNotNull);
    // Même analyse en LOCO.
    await t.tap(find.text('LOCO : parenté calculée sans le chromosome testé'));
    await t.pumpAndSettle();
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 2);
    expect(got.last.methodName, contains('LOCO'));
    expect(got.last.statistics.keys.where((k) => k.startsWith('lambda_reml_chr')), hasLength(3));
  });

  testWidgets('VCF compressé (.vcf.gz) : décompression, sites multialléliques signalés, HWE sur tous les sujets faute de phénotype', (t) async {
    final (key, got) = await mount(t);
    final vcf = File('$_ref/genotypes/simule.vcf').readAsBytesSync();
    key.currentState!.loadFiles({'cohorte.vcf.gz': Uint8List.fromList(const GZipEncoder().encodeBytes(vcf))});
    await t.pumpAndSettle();
    expect(find.textContaining('cohorte.vcf'), findsOneWidget);
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    final r = got.single;
    expect(r.alerts.any((a) => a.message.contains('2 site(s) multiallélique(s)')), isTrue);
    expect(r.checks.firstWhere((c) => c.id == 'hwe_controls').status, CheckStatus.warning);
    await t.pumpAndSettle();
    expect(find.textContaining('Aucune issue utilisable'), findsOneWidget);
  });

  testWidgets('jeu PLINK incomplet : message clair, aucun résultat', (t) async {
    final (key, got) = await mount(t);
    key.currentState!.loadFiles({'a.bed': File('$_ref/genotypes/simule.bed').readAsBytesSync(), 'a.bim': File('$_ref/genotypes/simule.bim').readAsBytesSync()});
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => find.textContaining('les trois fichiers').evaluate().isNotEmpty);
    expect(find.textContaining('les trois fichiers .bed, .bim et .fam'), findsOneWidget);
    expect(got, isEmpty);
  });

  testWidgets('390 px et texte à 200 % après contrôle de qualité : aucun débordement', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 6000));
    final state = AppState(MemoryStorage());
    await state.load();
    state.expertMode = true;
    final key = GlobalKey<GenotypeImportToolState>();
    var n = 0;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: GenotypeImportTool((r, {options = const {}}) => n++, key: key)))),
      ),
    ));
    await t.runAsync(() => key.currentState!.loadExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => n > 0);
    await t.pumpAndSettle();
    expect(find.text('Balayer les variants'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('régression LD score : confusion détectée sur le balayage brut, levée par l\'ajustement sur les CP', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadLdExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    expect(find.text('Disponible après un balayage (scores LD calculés sur ces génotypes).'), findsOneWidget);
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 1, tries: 600);
    await t.pumpAndSettle();
    expect(got.last.methodId, 'snp_scan');
    await t.tap(find.text('Régression LD score : polygénie ou confusion ?'));
    await waitFor(t, () => got.length > 2, tries: 200);
    final raw = got.last;
    expect(raw.methodId, 'ldsc');
    expect(raw.checks.firstWhere((c) => c.id == 'intercept').status, CheckStatus.warning);
    expect(raw.figures['ldsc'], isNotNull);
    expect(raw.interpretation.whatItMeans, contains('ajusté sur sexe'));
    // ACP puis balayage ajusté sur CP1 et CP2 : l'intercept redevient compatible avec 1.
    await t.tap(find.text('ACP (stratification de population)'));
    await waitFor(t, () => got.length > 3, tries: 200);
    await t.pumpAndSettle();
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 4, tries: 900);
    await t.pumpAndSettle();
    await t.tap(find.text('Régression LD score : polygénie ou confusion ?'));
    await waitFor(t, () => got.length > 5, tries: 200);
    final adj = got.last;
    expect(adj.methodId, 'ldsc');
    expect(adj.interpretation.whatItMeans, contains('PC1'));
    expect(adj.statistics['intercept']!, lessThan(raw.statistics['intercept']!));
    expect(adj.checks.firstWhere((c) => c.id == 'intercept').status, CheckStatus.ok, reason: 'intercept ${adj.statistics['intercept']} ± ${adj.statistics['se_intercept']}');
  });

  testWidgets('corrélation génétique : deux maladies balayées successivement sur les mêmes génotypes', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadLdExample());
    await t.pumpAndSettle();
    expect(find.textContaining('genotypes_dl_traits.csv'), findsOneWidget);
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    expect(find.text('Balayer successivement deux issues (par exemple deux maladies) sur ces mêmes génotypes.'), findsOneWidget);
    for (final (k, trait) in [(1, 'diabete'), (2, 'coronaropathie')]) {
      await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Issue (cas/témoin)'));
      await t.pumpAndSettle();
      await t.tap(find.text(trait).last);
      await t.pumpAndSettle();
      expect(key.currentState!.caseLevel, 'oui');
      await t.tap(find.text('Balayer les variants'));
      await waitFor(t, () => got.length > k, tries: 600);
      await t.pumpAndSettle();
    }
    expect(find.text('Corrélation génétique : diabete – coronaropathie'), findsOneWidget);
    await t.tap(find.text('Corrélation génétique : diabete – coronaropathie'));
    await waitFor(t, () => got.length > 3, tries: 200);
    final r = got.last;
    expect(r.methodId, 'genetic_correlation');
    expect(r.statistics['rg']!, greaterThan(0.3));
    expect(r.estimates.first.lower!, greaterThan(0), reason: 'rg simulée 0,7 : IC au-dessus de 0');
    expect(r.figures['ldsc'], isNotNull);
  });

  testWidgets('score de risque polygénique : découverte, validation et test sur l\'exemple de 3 000 sujets', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadPrsExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty, tries: 200);
    await t.pumpAndSettle();
    // L'exemple coche d'office le sexe (lu dans le .fam) : on retire tout ajustement pour le score brut.
    for (final c in [...key.currentState!.covs]) {
      await t.tap(find.widgetWithText(FilterChip, c));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Score de risque polygénique (découverte, validation, test)'));
    await waitFor(t, () => got.length > 1, tries: 600);
    final r = got.last;
    expect(r.methodId, 'polygenic_score');
    expect(r.statistics['test_auc']!, greaterThan(0.6));
    expect(r.estimates.first.lower!, greaterThan(1), reason: 'OR par ET du score > 1 sur le test');
    expect(r.figures['prs'], isNotNull);
    expect(r.statistics['validation_r2']!, greaterThan(r.statistics['test_r2']!));
    // Score ajusté sur l'âge (fichier de covariables de l'exemple) : gain d'AUC au-delà de l'âge.
    await t.tap(find.widgetWithText(FilterChip, 'age'));
    await t.pumpAndSettle();
    await t.tap(find.text('Score de risque polygénique ajusté sur age'));
    await waitFor(t, () => got.length > 2, tries: 600);
    final a = got.last;
    expect(a.methodName, contains('ajusté sur age'));
    expect(a.statistics['test_auc']!, greaterThan(a.statistics['test_auc_base']!));
    expect(a.statistics['delta_auc_p']!, lessThan(0.05));
  });

  testWidgets('modèle mixte logistique : exemple familial, maladie 0/1, apparentés gardés, λ ≈ 1', (t) async {
    final (key, got) = await mount(t);
    await t.runAsync(() => key.currentState!.loadFamilyExample());
    await t.pumpAndSettle();
    await t.tap(find.text('Lire et contrôler la qualité'));
    await waitFor(t, () => got.isNotEmpty);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Issue (cas/témoin)'));
    await t.pumpAndSettle();
    await t.tap(find.text('maladie').last);
    await t.pumpAndSettle();
    expect(find.text('Issue binaire : modèle mixte logistique (GMMAT)'), findsOneWidget);
    for (final c in ['sexe', 'age']) {
      await t.tap(find.widgetWithText(FilterChip, c));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Balayer les variants'));
    await waitFor(t, () => got.length > 1, tries: 600);
    final r = got.last;
    expect(r.methodId, 'glmm_scan');
    expect(r.inputs['samples'], key.currentState!.cleaned!.sampleCount);
    expect(r.statistics['lambda_gc']!, lessThan(1.1));
    expect(r.checks.firstWhere((c) => c.id == 'convergence').status, CheckStatus.ok);
  });
}
