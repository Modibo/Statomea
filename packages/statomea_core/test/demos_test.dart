import 'dart:convert';
import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('demo_aghbs');
  group('Démo 1 — AgHBs', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final results = [for (final e in p.journal) analysisResultFromJson(e.result)];
    test('prévalence et IC exact contre R binom.test', () {
      final r = results.first;
      expect(r.statistics['events'], ref['positives']);
      final cp = r.estimates[1];
      expect(cp.lower, closeRel(asD((ref['prev_exact'] as List)[0])!, rel: 1e-8));
      expect(cp.upper, closeRel(asD((ref['prev_exact'] as List)[1])!, rel: 1e-8));
    });
    test('séparation détectée par la logistique, Firth fini et conforme à logistf', () {
      expect(results[5].reliable, isFalse);
      final firth = results[6];
      final b = [for (final v in ref['firth_coef'] as List) asD(v)!];
      expect(firth.statistics.values.contains(double.infinity), isFalse);
      final betas = firth.statistics.entries.where((e) => e.key.startsWith('beta_')).map((e) => e.value).toList();
      for (var j = 0; j < b.length; j++) {
        expect(betas[j], closeRel(b[j], rel: 1e-7));
      }
      expect(results[4].statistics['fisher_p'], closeRel(asD(ref['fisher_p'])!, rel: 1e-9));
    });
    test('l\'audit trouve les erreurs volontaires du brouillon', () {
      final a = runAudit(question: p.question, results: results, text: p.resultsText);
      final fam = a.alerts.map((f) => f.family).toSet();
      expect(fam, containsAll([AuditFamily.causalLanguage, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
    });
    test('projet sérialisable et relu à l\'identique', () {
      final s = p.encode();
      final back = Project.decode(s);
      expect(back.journal.length, p.journal.length);
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
    });
  });

  group('Démo 2 — métaanalyse BCG', () {
    final p = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
    final meta = loadRef('meta');
    test('RR combiné REML identique à metafor', () {
      final r = analysisResultFromJson(p.journal.first.result);
      final reml = (meta['bcg_RR'] as Map)['reml'] as Map;
      expect(r.statistics['mu'], closeRel(asD(reml['mu'])!, rel: 1e-8));
      expect(r.statistics['tau2'], closeRel(asD(reml['tau2'])!, rel: 1e-8));
      expect(r.figures['forest'], isNotNull);
    });
    test('effet fixe en sensibilité à côté d\'effets aléatoires : prudence, pas « grave »', () {
      final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
      final a = runAudit(question: p.question, results: rs, text: '');
      final fe = a.of(AuditFamily.methodDesign).where((f) => f.message.contains('effet fixe')).single;
      expect(fe.severity, Severity.caution);
    });
    test('forest plot SVG et rapport HTML', () {
      final r = analysisResultFromJson(p.journal.first.result);
      final svg = forestPlotSvg((r.figures['forest'] as Map).cast());
      expect(svg, startsWith('<svg'));
      expect(svg, contains('Aronson 1948'));
      final a = runAudit(question: p.question, results: [r], text: p.resultsText);
      final html = projectReportHtml(p, audit: a, generatedAt: 'test');
      for (final s in ['Données saisies', 'Résultat calculé', 'Interprétation proposée', 'À vérifier par le chercheur', 'Audit contradictoire']) {
        expect(html, contains(s));
      }
      expect(a.alerts.map((f) => f.family), contains(AuditFamily.overPrecision));
      final msgs = a.alerts.map((f) => f.message).join(' | ');
      expect(msgs, contains('Généralisation'));
      expect(msgs, contains('n\'exclut pas un biais de publication'));
    });
    test('CSV d\'un résultat et journal JSON', () {
      final r = analysisResultFromJson(p.journal.first.result);
      final csv = resultToCsv(r);
      expect(csv.split('\n')[1], contains('Libellé'));
      expect(jsonDecode(journalJson(p))['entries'], hasLength(4));
    });
  });

  group('Démo 3 — prédiction cardiométabolique', () {
    final p = buildDemoPrediction(File('test/reference/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 50,
        externalCsv: File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync());
    final r = analysisResultFromJson(p.journal.first.result);
    test('performances calculées, modèle de référence comparé, figures présentes', () {
      expect(r.statistics['auc_corrected'], lessThan(r.statistics['auc_apparent']!));
      expect(r.statistics['delta_auc'], greaterThan(0));
      expect(r.figures['calibration'], isA<List>());
      expect(calibrationSvg((r.figures['calibration'] as List).cast()), startsWith('<svg'));
      expect(decisionCurveSvg((r.figures['decisionCurve'] as List).cast()), startsWith('<svg'));
    });
    test('validation externe journalisée (pente de calibration < 1 détectée)', () {
      final ext = analysisResultFromJson(p.journal[1].result);
      expect(ext.methodId, 'external_validation');
      expect(ext.checks.firstWhere((c) => c.id == 'calibration_slope').status, CheckStatus.violated);
    });
    test('l\'audit refuse « validé » et « utilisable en pratique clinique »', () {
      final a = runAudit(question: p.question, results: [r], text: p.resultsText);
      expect(a.alerts.where((f) => f.family == AuditFamily.predictionOverclaim), isNotEmpty);
    });
  });

  group('Démo 4 — tuberculose résistante à la rifampicine', () {
    final tb = loadRef('demo_tb');
    final p = buildDemoTb(File('test/reference/tb_rifampicine_simule.csv').readAsStringSync(),
        File('test/reference/tb_references_simule.fasta').readAsStringSync(), File('test/reference/tb_isolat_simule.fasta').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
    List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

    test('concordance du panel (3 puis 4 mutations) contre R : effectifs, Se, Sp (Wilson), kappa', () {
      for (final (r, key) in [(rs[0], 'any3'), (rs[1], 'any4')]) {
        final ref = tb[key] as Map;
        expect([r.estimates[0].value, r.estimates[0].lower, r.estimates[0].upper], [for (final x in v(ref['se'])) closeRel(x, rel: 1e-9)], reason: key);
        expect([r.estimates[1].value, r.estimates[1].lower, r.estimates[1].upper], [for (final x in v(ref['sp'])) closeRel(x, rel: 1e-9)], reason: key);
        expect(r.estimates[2].value, closeRel(asD(ref['kappa'])!, rel: 1e-12), reason: key);
      }
      // La mutation « limite » L430P fait baisser la spécificité.
      expect(rs[1].estimates[1].value, lessThan(rs[0].estimates[1].value));
    });

    test('diversité, lignée L2 (Fisher), centres (χ²), LOD95 contre R', () {
      expect(rs[2].statistics['hunter_gaston'], closeRel(asD(tb['hg'])!, rel: 1e-12));
      expect(rs[3].statistics['fisher_p'], closeRel(asD(tb['L2_fisher_p'])!, rel: 1e-9));
      expect(rs[4].statistics['chi2'], closeRel(asD(tb['centre_chi2'])!, rel: 1e-12));
      expect(rs[4].statistics['p'], closeRel(asD(tb['centre_p'])!, rel: 1e-10));
      expect(rs[5].statistics['lod'], closeRel(asD((tb['lod'] as Map)['lod95'])!, rel: 1e-8));
      expect(demoTbLodConcentrations, v((tb['lod'] as Map)['conc']));
      expect(demoTbLodDetected, (tb['lod'] as Map)['det']);
    });

    test('identification : scores Smith-Waterman = Biostrings ; voisin trop proche signalé', () {
      final al = rs[6];
      final sw = tb['sw'] as Map;
      for (final e in sw.entries) {
        expect(al.statistics['score_${e.key}'], asD(e.value), reason: e.key);
      }
      expect(al.tables.first.rows.first.first, 'MTBC_sim');
      expect(al.checks.firstWhere((c) => c.id == 'separation').status, CheckStatus.warning);
    });

    test('l\'audit trouve les erreurs volontaires du brouillon', () {
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      expect(a.alerts.map((f) => f.family).toSet(),
          containsAll([AuditFamily.causalLanguage, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
      expect(a.alerts.where((f) => f.family == AuditFamily.methodDesign), isEmpty);
    });

    test('projet sérialisable et relu à l\'identique', () {
      final back = Project.decode(p.encode());
      expect(back.journal.length, 7);
      expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
    });
  });

  group('Démo 5 — étude d\'association pangénomique', () {
    final ref = loadRef('demo_gwas');
    const d = 'test/reference';
    final p = buildDemoGwas(File('$d/gwas_simule.bed').readAsBytesSync(), File('$d/gwas_simule.bim').readAsStringSync(), File('$d/gwas_simule.fam').readAsStringSync(),
        File('$d/gwas_covariables_simule.csv').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
    List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

    test('chaîne QC → parenté → ACP identique à R : sujets et variants écartés, apparentés, élagage, valeurs propres', () {
      expect(rs[0].statistics['removed_sample_call']! + rs[0].statistics['removed_sample_het']!, (ref['qc_removed_samples'] as List).length);
      expect(rs[0].statistics['samples']! - rs[0].statistics['kept_samples']!, (ref['qc_removed_samples'] as List).length);
      expect(rs[0].statistics['variants']! - rs[0].statistics['kept_variants']!, (ref['qc_removed_variants'] as List).length);
      final kinTable = rs[1].tables[1].rows.map((r) => r.first).toSet();
      expect(kinTable, (ref['related_removed'] as List).map((x) => '$x').toSet());
      expect(rs[2].statistics['variants_pruned'], ref['pruned']);
      final ev = v(ref['eigen']);
      for (var c = 0; c < 4; c++) {
        expect(rs[2].statistics['eigenvalue_${c + 1}'], closeRel(ev[c], rel: 1e-10));
      }
    });

    test('balayages : λ brut et ajusté, meilleurs variants et leurs p = glm de R', () {
      expect(rs[3].statistics['lambda_gc'], closeRel(asD(ref['lambda_raw'])!, rel: 1e-6));
      expect(rs[4].statistics['lambda_gc'], closeRel(asD(ref['lambda_adj'])!, rel: 1e-6));
      final top = [for (final x in ref['top_snps'] as List) '$x'];
      final tp = v(ref['top_p_adj']);
      for (var k = 0; k < 3; k++) {
        expect(rs[4].statistics['p_${top[k]}'], closeRel(tp[k], rel: 1e-5), reason: top[k]);
      }
      expect(rs[4].statistics['n_genome_wide'], ref['n_gw_adj']);
      expect(rs[5].methodName, contains(top.first));
      expect(rs[3].checks.firstWhere((c) => c.id == 'stratification').status, CheckStatus.warning);
      expect(rs[4].checks.firstWhere((c) => c.id == 'stratification').status, CheckStatus.ok);
      expect(rs[4].figures['manhattan'], isNotNull);
    });

    test('l\'audit trouve les erreurs volontaires du brouillon', () {
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      expect(a.alerts.map((f) => f.family).toSet(),
          containsAll([AuditFamily.causalLanguage, AuditFamily.orAsRr, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
      // « traduit un fort signal polygénique » sans régression LD score : attribution non étayée (prudence).
      final gi = a.of(AuditFamily.genomicInflation).single;
      expect(gi.status, AuditStatus.alert);
      expect(gi.severity, Severity.caution);
    });

    test('projet léger (stockage compact < 1 Mo) et relu à l\'identique', () {
      final c = p.encodeCompact();
      expect(c.length, lessThan(1000000));
      expect(Project.decode(c).encode(), p.encode());
    });
  });

  group('Démo 6 — polygénie ou confusion', () {
    const d = 'test/reference/genotypes';
    final p = buildDemoPolygenic(File('$d/ldsc_app.bed').readAsBytesSync(), File('$d/ldsc_app.bim').readAsStringSync(), File('$d/ldsc_app.fam').readAsStringSync(),
        File('$d/ldsc_app_traits.csv').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];

    test('chaîne : contrôle de qualité, ACP, 4 balayages, 2 régressions LD score, corrélation génétique', () {
      expect([for (final r in rs) r.methodId],
          ['genotype_qc', 'genotype_pca', 'snp_scan', 'ldsc', 'snp_scan', 'ldsc', 'snp_scan', 'snp_scan', 'genetic_correlation']);
      expect(rs[2].methodName, contains('sexe'));
      expect(rs[4].methodName, allOf(contains('PC1'), contains('PC2')));
    });

    test('la régression LD score sépare confusion et polygénie : intercept > 1 avant ajustement, ≈ 1 après', () {
      expect(rs[2].statistics['lambda_gc']!, greaterThan(rs[4].statistics['lambda_gc']!));
      expect(rs[3].checks.firstWhere((c) => c.id == 'intercept').status, CheckStatus.warning);
      expect(rs[5].checks.firstWhere((c) => c.id == 'intercept').status, CheckStatus.ok);
      expect(rs[3].statistics['ratio']!, greaterThan(0.5));
      expect((rs[5].statistics['intercept']! - 1).abs(), lessThan(0.1));
    });

    test('corrélation génétique diabète–coronaropathie : identique au calcul direct, IC au-dessus de 0, h² fragiles signalés', () {
      final g = parsePlinkBed(File('$d/ldsc_app.bed').readAsBytesSync(), File('$d/ldsc_app.bim').readAsStringSync(), File('$d/ldsc_app.fam').readAsStringSync());
      final u = genotypeQc(g).cleaned;
      final traits = parseCsv(File('$d/ldsc_app_traits.csv').readAsStringSync()).dataset;
      final cov = {for (final c in ['diabete', 'coronaropathie']) c: {for (var i = 0; i < traits.rowCount; i++) traits.cell(i, 'id')!: traits.cell(i, c)!}};
      final pcs = genotypePca(u).covariates(2);
      final ds = genotypeDataset(u, covariates: {...cov, ...pcs});
      final names = ds.names.sublist(ds.names.length - u.variantCount);
      final terms = [const TermSpec('sexe', categorical: true, reference: 'H'), const TermSpec('PC1'), const TermSpec('PC2')];
      final z1 = <double>[], z2 = <double>[];
      snpScan(ds, names, 'diabete', 'oui', covariates: terms, zOut: z1);
      snpScan(ds, names, 'coronaropathie', 'oui', covariates: terms, zOut: z2);
      final direct = geneticCorrelationFromScans(u, z1, z2, n: u.sampleCount);
      final r = rs[8];
      expect(r.statistics['rg'], closeRel(direct.rg, rel: 1e-12));
      expect(r.estimates.first.lower!, greaterThan(0));
      expect(r.checks.firstWhere((c) => c.id == 'h2_signal').status, CheckStatus.warning);
    });

    test('l\'audit trouve les erreurs volontaires du brouillon, dont l\'inflation attribuée à tort à la polygénie', () {
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      expect(a.alerts.map((f) => f.family).toSet(),
          containsAll([AuditFamily.genomicInflation, AuditFamily.causalLanguage, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
      expect(a.of(AuditFamily.genomicInflation).first.severity, Severity.serious);
      // Le balayage ajusté compte comme analyse ajustée ; la condition HWE répétée donne un seul constat.
      expect(a.alerts.where((f) => f.message.contains('analyse ajustée')), isEmpty);
      expect(a.alerts.where((f) => f.message.contains('Hardy-Weinberg')), hasLength(1));
    });

    test('projet sérialisable et assez léger (stockage compact < 1,5 Mo)', () {
      final c = p.encodeCompact();
      expect(c.length, lessThan(1500000));
      expect(Project.decode(c).encode(), p.encode());
    });
  });

  group('Démo 7 — randomisation mendélienne (LDL, HDL, maladie coronarienne)', () {
    final p = buildDemoMr(File('test/reference/mr_ldl_chd.csv').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
    final ref = loadRef('mr'), refS = loadRef('mr_sensibilite');

    test('chaîne : LDL (= MendelianRandomization), HDL, TG, multivariée (= mr_mvivw)', () {
      expect([for (final r in rs) r.methodId], ['mendelian_randomization', 'mendelian_randomization', 'mendelian_randomization', 'mendelian_randomization_mv']);
      expect(rs[0].statistics['ivw'], closeRel(asD((ref['ivw'] as Map)['estimate'])!, rel: 1e-10));
      expect(rs[0].statistics['egger'], closeRel(asD((ref['egger'] as Map)['estimate'])!, rel: 1e-10));
      expect(rs[0].statistics['weighted_mode'], closeRel(asD((refS['mbe'] as Map)['estimate'])!, rel: 1e-12));
      final mv = [for (final x in (refS['mv'] as Map)['estimate'] as List) asD(x)!];
      expect(rs[3].estimates.where((e) => e.label.startsWith('Effet direct')).map((e) => e.value).toList(), [for (final x in mv) closeRel(x, rel: 1e-10)]);
    });

    test('le HDL : protecteur en IVW univarié, mais pléiotropie (intercept MR-Egger) et effet direct nul en multivariée', () {
      expect(rs[1].statistics['ivw']!, lessThan(0));
      expect(rs[1].statistics['ivw_p']!, lessThan(0.001));
      expect(rs[1].checks.firstWhere((c) => c.id == 'pleiotropy').status, CheckStatus.warning);
      final hdlDirect = rs[3].estimates.firstWhere((e) => e.label.contains('HDL'));
      expect(hdlDirect.lower!, lessThan(0));
      expect(hdlDirect.upper!, greaterThan(0));
      expect(rs[0].checks.firstWhere((c) => c.id == 'pleiotropy').status, CheckStatus.ok);
    });

    test('l\'audit trouve les erreurs volontaires, dont la pléiotropie du HDL passée sous silence', () {
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      expect(a.alerts.map((f) => f.family).toSet(), containsAll([AuditFamily.causalLanguage, AuditFamily.orAsRr, AuditFamily.overPrecision]));
      expect(a.alerts.where((f) => f.message.contains('Pléiotropie directionnelle détectée')), hasLength(1));
      // Les analyses de sensibilité (leave-one-out, MR-Egger, médiane, mode) existent : pas d'alerte « annoncée non faite ».
      expect(a.alerts.where((f) => f.message.contains('analyse de sensibilité')), isEmpty);
      // Avec une discussion des hypothèses, la conclusion causale sur le LDL est acceptée.
      final ok = runAudit(question: p.question, results: rs.sublist(0, 1),
          text: 'La randomisation mendélienne suggère que le LDL-cholestérol cause la maladie coronarienne ; les instruments sont forts et l\'intercept MR-Egger ne montre pas de pléiotropie.');
      expect(ok.of(AuditFamily.causalLanguage).single.status, AuditStatus.ok);
    });

    test('projet sérialisable et relu à l\'identique', () {
      expect(Project.decode(p.encodeCompact()).encode(), p.encode());
    });
  });

  group('Démo 8 — survie avancée (risques concurrents, temps immortel)', () {
    final p = buildDemoSurvivalAdvanced(File('test/reference/risques_concurrents_simule.csv').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
    final rc = loadRef('risques_concurrents'), ct = loadRef('cox_temps');

    test('chaîne : KM naïf, incidence cumulée (= cuminc, test de Gray), Fine-Gray (= crr), Cox naïf et dépendant du temps (= coxph)', () {
      expect([for (final r in rs) r.methodId], ['kaplan_meier', 'cumulative_incidence', 'fine_gray', 'cox', 'cox']);
      expect(rs[1].statistics['cif_A'], closeRel(asD((rc['at24'] as Map)['A'])!, rel: 1e-12));
      expect(rs[1].statistics['gray_chi2'], closeRel(asD(((rc['gray'] as Map)['stat'] as List).first)!, rel: 1e-10));
      expect(rs[1].statistics['naive_A']!, greaterThan(rs[1].statistics['cif_A']!));
      expect(rs[2].statistics['cs_beta_age']!, greaterThan(0));
      expect(rs[2].statistics['beta_age']!, lessThan(0));
      expect(rs[3].estimates.first.value, lessThan(0.25)); // biais du temps immortel
      expect(rs[4].statistics['beta_greffe = oui (vs non)'], closeRel(asD(((ct['efron'] as Map)['coef'] as List).first)!, rel: 1e-8));
    });

    test('le brouillon contient les erreurs volontaires, et l\'audit en relève', () {
      expect(p.resultsText, contains('Kaplan-Meier'));
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      final surv = a.alerts.where((f) => f.family == AuditFamily.survivalPitfalls).toList();
      expect(surv, hasLength(2)); // Kaplan-Meier malgré les décès concurrents ; HR de la greffe biaisé par le temps immortel
      expect(surv.any((f) => f.message.contains('temps immortel')), isTrue);
      expect(a.alerts.map((f) => f.family).toSet(), containsAll([AuditFamily.causalLanguage, AuditFamily.overPrecision]));
    });

    test('projet sérialisable', () {
      expect(Project.decode(p.encodeCompact()).encode(), p.encode());
    });
  });

  group('Démo 9 — laboratoire : créatinine sur plasma ou sur sérum', () {
    final p = buildDemoMethodComparison(File('test/reference/creatinine_serum_plasma.csv').readAsStringSync());
    final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
    final ref = loadRef('comparaison_methodes');

    test('chaîne : corrélation, Bland-Altman, Passing-Bablok (= algorithme publié), Deming (= mcr)', () {
      expect([for (final r in rs) r.methodId], ['pearson', 'bland_altman', 'passing_bablok', 'deming']);
      expect(rs[2].statistics['slope'], closeRel(asD(((ref['paba_classic'] as Map)['slope'] as List).first)!, rel: 1e-12));
      expect(rs[3].statistics['slope'], closeRel(asD(((ref['deming1'] as Map)['slope'] as List).first)!, rel: 1e-11));
      expect(rs[2].statistics.keys, containsAll(['bias_at_1.2', 'bias_at_2']));
    });

    test('le brouillon contient les erreurs volontaires, et l\'audit en relève', () {
      final a = runAudit(question: p.question, results: rs, text: p.resultsText);
      expect(a.alerts.map((f) => f.family).toSet(), containsAll([AuditFamily.agreementVsCi, AuditFamily.pValueMisread, AuditFamily.overPrecision]));
    });

    test('projet sérialisable', () {
      expect(Project.decode(p.encodeCompact()).encode(), p.encode());
    });
  });
}
