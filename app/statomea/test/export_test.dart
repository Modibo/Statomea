import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rapport PDF de la démonstration 2 (forest plot, audit, polices embarquées)', () async {
    final p = buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync());
    final audit = runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);
    final bytes = await buildProjectPdf(p, audit: audit, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
    final out = Platform.environment['STATOMEA_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('rapport PDF et HTML de la démonstration 4 (alignement en chasse fixe, courbe probit, audit)', () async {
    final p = buildDemoTb(File('assets/demos/tb_rifampicine_simule.csv').readAsStringSync(), File('assets/demos/tb_references_simule.fasta').readAsStringSync(),
        File('assets/demos/tb_isolat_simule.fasta').readAsStringSync());
    final audit = runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);
    final bytes = await buildProjectPdf(p, audit: audit, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final html = projectReportHtml(p, audit: audit, generatedAt: 'test');
    expect(html, contains('<pre>'));
    expect(html, contains('MTBC_sim'));
    final out = Platform.environment['STATOMEA_PDF_OUT_TB'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  test('rapport PDF et HTML de la démonstration 5 (Manhattan, QQ, KING, ACP)', () async {
    final p = buildDemoGwas(File('assets/demos/gwas_simule.bed').readAsBytesSync(), File('assets/demos/gwas_simule.bim').readAsStringSync(),
        File('assets/demos/gwas_simule.fam').readAsStringSync(), File('assets/demos/gwas_covariables_simule.csv').readAsStringSync());
    final audit = runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);
    final bytes = await buildProjectPdf(p, audit: audit, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final html = projectReportHtml(p, audit: audit, generatedAt: 'test');
    for (final cap in ['Manhattan plot', 'QQ plot', 'Apparentement', 'ACP des génotypes']) {
      expect(html, contains(cap));
    }
    final out = Platform.environment['STATOMEA_PDF_OUT_GWAS'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rapport PDF et HTML d\'une régression LD score et d\'une corrélation génétique (figures selon ℓ, polices Noto)', () async {
    final ld = parsePlinkBed(File('assets/demos/genotypes_dl_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_dl_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_dl_simule.fam').readAsStringSync());
    final ds = genotypeDataset(ld);
    final chi2 = <double>[];
    snpScan(ds, ds.names.sublist(ds.names.length - ld.variantCount), 'statut', 'cas', chi2Out: chi2);
    final r = ldscFromScan(ld, chi2, n: ld.sampleCount).result;
    final trCsv = parseCsv(File('assets/demos/genotypes_dl_traits.csv').readAsStringSync()).dataset;
    final rgDs = genotypeDataset(ld, covariates: {for (final c in ['diabete', 'coronaropathie']) c: {for (var i = 0; i < trCsv.rowCount; i++) trCsv.cell(i, 'id')!: trCsv.cell(i, c)!}});
    final rgNames = rgDs.names.sublist(rgDs.names.length - ld.variantCount);
    final za = <double>[], zb = <double>[];
    snpScan(rgDs, rgNames, 'diabete', 'oui', zOut: za);
    snpScan(rgDs, rgNames, 'coronaropathie', 'oui', zOut: zb);
    final rg = geneticCorrelationFromScans(ld, za, zb, n: ld.sampleCount, trait1: 'diabete', trait2: 'coronaropathie').result;
    final pg = parsePlinkBed(File('assets/demos/genotypes_prs_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_prs_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_prs_simule.fam').readAsStringSync());
    final prs = polygenicRiskScore(pg, [for (final p in pg.phenotype) p == null ? null : (p == 2 ? 1.0 : 0.0)]).result;
    final p = Project(id: 'ldsc', title: 'LDSC', createdAt: '2026-10-12')
      ..journal.add(JournalEntry.fromResult(r, id: 'l1', timestamp: 'test'))
      ..journal.add(JournalEntry.fromResult(rg, id: 'l2', timestamp: 'test'))
      ..journal.add(JournalEntry.fromResult(prs, id: 'l3', timestamp: 'test'));
    final bytes = await buildProjectPdf(p, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final html = projectReportHtml(p, generatedAt: 'test');
    expect(html, contains('Régression LD score : χ² moyen par classe de score LD'));
    expect(html, contains('Régression LD score croisée : z₁·z₂ moyen'));
    expect(html, contains('Score polygénique : R² de Nagelkerke en validation'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rapport PDF et HTML de la démonstration 6 (régressions LD score, corrélation génétique, audit)', () async {
    final p = buildDemoPolygenic(File('assets/demos/genotypes_dl_simule.bed').readAsBytesSync(), File('assets/demos/genotypes_dl_simule.bim').readAsStringSync(),
        File('assets/demos/genotypes_dl_simule.fam').readAsStringSync(), File('assets/demos/genotypes_dl_traits.csv').readAsStringSync());
    final audit = runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);
    final bytes = await buildProjectPdf(p, audit: audit, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final html = projectReportHtml(p, audit: audit, generatedAt: 'test');
    for (final cap in ['Régression LD score : χ² moyen', 'Régression LD score croisée', 'Inflation génomique : polygénie ou confusion']) {
      expect(html, contains(cap));
    }
    final out = Platform.environment['STATOMEA_PDF_OUT_POLY'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('rapport PDF et HTML de la démonstration 7 (randomisation mendélienne, audit)', () async {
    final p = buildDemoMr(File('assets/demos/mr_ldl_chd.csv').readAsStringSync());
    final audit = runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);
    final bytes = await buildProjectPdf(p, audit: audit, generatedAt: 'test');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final html = projectReportHtml(p, audit: audit, generatedAt: 'test');
    expect(html, contains('Randomisation mendélienne : βY selon βX'));
    expect(html, contains('Pléiotropie directionnelle détectée'));
  });

  test('suppression complète d\'un projet', () async {
    final storage = MemoryStorage();
    final s = AppState(storage);
    await s.load();
    final p = s.createProject('À supprimer');
    p.dataset = Dataset(['x'], [['1'], ['2']]);
    await s.save(p);
    expect(storage.docs.containsKey(p.id), isTrue);
    await s.delete(p);
    expect(storage.docs.containsKey(p.id), isFalse);
    expect(s.projects, isEmpty);
  });

  test('chaque calcul dans un projet est journalisé avec l\'empreinte des données', () async {
    final s = AppState(MemoryStorage());
    await s.load();
    final p = s.createProject('Journal');
    p.dataset = Dataset(['g', 'y'], [for (var i = 0; i < 20; i++) [i.isEven ? 'A' : 'B', '${5 + i % 4}']]);
    final r = proportionCi(3, 20);
    final e = s.record(p, r);
    expect(p.journal.single.id, e.id);
    expect(e.datasetFingerprint, hasLength(8));
    expect(e.result['engineVersion'], engineVersion);
  });
}
