import 'dart:math' as math;
// Version anglaise : aucun texte produit par le moteur ne doit rester en
// français quand la langue est l'anglais. Les valeurs issues des DONNÉES
// (noms de variables, modalités, libellés d'études) sont exclues du contrôle.
import 'dart:convert';
import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

final _accents = RegExp(r'[àâäçéèêëîïôöùûüœÀÂÇÉÈÊÎÔÙÛŒ]');
final _frenchSpacing = RegExp(r'[\p{L}\d)\]%»] [:;!?](?=\s|$)', unicode: true);
final _words = RegExp(
    r"\b(le|la|les|des|du|une|est|sont|et|pour|avec|sans|dans|sur|pas|aux|au|ce|cette|qui|que|par|plus|moins|selon|entre|données|leur|chaque|ou|où|peut|doit|être|été|si|sous|vers|chez|mais|donc|aucun|aucune|valeur|valeurs|étude|études|modèle)\b",
    caseSensitive: false);

/// Fragments français trouvés dans [text] (hors [allowed]).
List<String> leaks(String text, Set<String> allowed) {
  // Noms propres et notations mathématiques communs aux deux langues.
  var t = text.replaceAll(RegExp(r'\bet al\b\.?'), ' ').replaceAll('Cramér', 'Cramer').replaceAll('Statoméa', 'Statomea').replaceAll('Sominé', 'Somine').replaceAll('û', 'u');
  // Les clés JSON (identifiants techniques comme « est ») ne sont pas du texte.
  t = t.replaceAll(RegExp(r'"[A-Za-z_0-9]+":'), ' ');
  final sorted = allowed.where((a) => a.trim().isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  // Jetons présents seulement (un jeton absent ne remplacerait rien), regroupés en alternatives du plus long au plus
  // court (paquets de 500) : mot entier seulement (une valeur courte comme « id » ne doit pas amputer « identique »).
  final words = t.split(RegExp(r'[^\p{L}\d]+', unicode: true)).toSet();
  final simple = RegExp(r'^[\p{L}\d]+$', unicode: true);
  final present = [for (final a in sorted) if (simple.hasMatch(a) ? words.contains(a) : t.contains(a)) a];
  for (var k = 0; k < present.length; k += 500) {
    final alt = present.sublist(k, math.min(k + 500, present.length)).map(RegExp.escape).join('|');
    t = t.replaceAll(RegExp('(?<![\\p{L}\\d])(?:$alt)(?![\\p{L}\\d])', unicode: true), ' ');
  }
  final out = <String>[];
  for (final m in _accents.allMatches(t)) {
    final s = (m.start - 30).clamp(0, t.length), e = (m.end + 30).clamp(0, t.length);
    out.add(t.substring(s, e));
  }
  // Typographie française : espace avant « : », « ; », « ! », « ? » (le JSON indenté n'en contient pas ailleurs).
  for (final m in _frenchSpacing.allMatches(t)) {
    final s = (m.start - 30).clamp(0, t.length), e = (m.end + 30).clamp(0, t.length);
    out.add(t.substring(s, e));
  }
  for (final m in _words.allMatches(t)) {
    final s = (m.start - 30).clamp(0, t.length), e = (m.end + 30).clamp(0, t.length);
    out.add(t.substring(s, e));
  }
  return out;
}

Set<String> dataTokens(Iterable<Dataset> sets) => {
      for (final ds in sets) ...[
        ...ds.names,
        ds.source,
        for (var i = 0; i < ds.rowCount; i++)
          for (final n in ds.names) ds.cell(i, n) ?? '',
        for (final n in ds.names) ...ds.levels(n),
      ]
    };

String dump(Object? o) => const JsonEncoder.withIndent(' ').convert(sanitizeJson(o));

void expectEnglish(String what, String text, [Set<String> allowed = const {}]) {
  final l = leaks(text, allowed);
  expect(l, isEmpty, reason: '$what : ${l.length} fragment(s) français, p. ex. « ${l.take(6).join(" » ; « ")} »');
}

void expectResult(String what, AnalysisResult r, [Set<String> allowed = const {}]) => expectEnglish(what, dump(r.toJson()..remove('inputs')), allowed);

/// Démonstration 6 construite une fois (en anglais) pour les tests qui l'utilisent.
Project? _demo6;
Project demo6() => _demo6 ??= withLang<Project>(Lang.en, () => buildDemoPolygenic(File('test/reference/genotypes/ldsc_app.bed').readAsBytesSync(), File('test/reference/genotypes/ldsc_app.bim').readAsStringSync(),
    File('test/reference/genotypes/ldsc_app.fam').readAsStringSync(), File('test/reference/genotypes/ldsc_app_traits.csv').readAsStringSync()));

void main() {
  setUp(() => setLang(Lang.en));
  tearDown(() => setLang(Lang.fr));

  test('formatage des nombres en anglais', () {
    expect(fmt(1234.5678, digits: 5), '1234.6');
    expect(fmtP(0.0004), 'p < 0.001');
    expect(fmtPct(0.123), '12.3%');
    expect(fmtCi(const Estimate('x', 1.5, lower: 1.2, upper: 1.9)), '1.50 (95% CI: 1.20 to 1.90)');
  });

  test('analyses fondamentales', () {
    final g1 = [5.1, 5.8, 6.2, 4.9, 5.5, 6.0, 5.3, 5.7], g2 = [5.9, 6.4, 6.8, 6.1, 7.0, 6.3, 6.6, 5.8];
    final rs = <String, AnalysisResult>{
      'describeNumeric': describeNumeric([...g1, null], variable: 'x', unit: 'mmol/L'),
      'describeCategorical': describeCategorical(['a', 'b', 'a', null, 'c'], variable: 'x'),
      'proportion0': proportionCi(0, 150),
      'proportion': proportionCi(3, 400, p0: 0.01),
      'propDiff': proportionDifference(12, 100, 20, 100, margin: 0.05),
      '2x2cohort': twoByTwo(120, 380, 80, 420, design: StudyDesign.cohort),
      '2x2cc': twoByTwo(30, 70, 15, 85, design: StudyDesign.caseControl),
      '2x2unknown': twoByTwo(0, 25, 6, 19),
      '2x2cross': twoByTwo(30, 70, 15, 85, design: StudyDesign.crossSectional),
      'diag': diagnosticAccuracy(90, 30, 10, 870, targetPrevalence: 0.01, design: StudyDesign.caseControl),
      'welch': tTestIndependent(g1, g2, margin: 0.5),
      'student': tTestIndependent(g1, [1, 9, 2, 8, 3, 7, 4, 6], welch: false),
      'mw': mannWhitney(g1, [1, 2, 2, 3]),
      'anova': anovaOneWay({'A': g1, 'B': g2, 'C': [7, 8, 7.5, 9]}),
      'welchAnova': anovaOneWay({'A': g1, 'B': g2, 'C': [7, 8, 7.5, 9]}, welch: true),
      'kw': kruskalWallis({'A': g1, 'B': g2}),
      'kw3': kruskalWallis({'A': g1, 'B': g2, 'C': [7, 8, 7.5, 9]}),
      'chi2': chiSquareRxC([[1, 2, 3], [2, 1, 30]]),
      'pairedT': pairedTTest([...g1, null], [...g2, 4]),
      'wilcoxon': wilcoxonSignedRank(g1, g2),
      'mcnemar': mcNemar(40, 14, 5, 41),
      'pearson': correlation(g1, g2),
      'spearman': correlation(g1, g2, spearman: true),
      'ba': blandAltman(g1, g2, acceptableLimit: 0.5),
      'ssMeans': sampleSizeTwoMeans(delta: 5, sd: 12, dropout: 0.1),
      'ssProps': sampleSizeTwoProportions(p1: 0.1, p2: 0.05),
      'ssProp': sampleSizeProportion(expected: 0.02, precision: 0.03, population: 1000, designEffect: 2),
      'survival': survivalAnalysis([3, 5, 6, 8, 9, 12, 14, 15], ['1', '1', '1', '0', '1', '0', '1', '0'], '1',
          groupRaw: ['A', 'A', 'A', 'A', 'B', 'B', 'B', 'B'], horizon: 10, timeUnit: 'months'),
    };
    for (final e in rs.entries) {
      expectResult(e.key, e.value, {'mmol/L', 'months'});
    }
  });

  test('régressions, Cox, imputation et combinaison', () {
    final ds = parseCsv(File('test/reference/regression_data.csv').readAsStringSync()).dataset;
    final al = dataTokens([ds]);
    const terms = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('imc', transform: TermTransform.log), TermSpec('tabac', categorical: true)];
    final d = buildDesign(ds, const ModelFormula('pas', terms, interactions: [('age', 'sexe')]));
    expectResult('linear', linearRegression(d, unit: 'mmHg'), {...al, 'mmHg'});
    final db = buildDesign(ds, const ModelFormula('hta', terms), binaryOutcome: true);
    expectResult('logistic', logisticRegression(db, design: StudyDesign.cohort), al);
    expectResult('poisson', poissonRobustRegression(db), al);
    final fd = parseCsv(File('test/reference/firth_data.csv').readAsStringSync()).dataset;
    final dfirth = buildDesign(fd, const ModelFormula('y', [TermSpec('x1'), TermSpec('grp', categorical: true, reference: 'A')], eventLevel: '1'), binaryOutcome: true);
    expectResult('logistic separation', logisticRegression(dfirth), dataTokens([fd]));
    expectResult('firth', firthRegression(dfirth), dataTokens([fd]));
    final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
    final s = buildSurvivalDesign(lung, 'time', 'deces', 'oui', const [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'H')]);
    expectResult('cox', coxRegression(s), dataTokens([lung]));
    final sim = parseCsv(File('test/reference/mi_simulation.csv').readAsStringSync()).dataset;
    final imp = multipleImputation(sim, const MiceOptions(m: 3, maxit: 3));
    expectResult('pooled', pooledRegression(imp.completed, const ModelFormula('y', [TermSpec('x1'), TermSpec('x2', categorical: true, reference: 'non')]), PooledModel.linear, imputation: imp),
        {...dataTokens([sim]), ...{for (final c in imp.completed) c.source}});
  });

  test('métaanalyses', () {
    final p = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
    final al = {...dataTokens([p.dataset!]), for (final s in p.studies) ...[s.label, s.subgroup, for (final v in s.values.values) v.source, s.compatibility.comment]};
    expectResult('meta RR', metaAnalysis(p.studies, const MetaOptions(measure: EffectMeasure.rr, knha: true)), al);
    expectResult('meta MH', metaAnalysis(p.studies, const MetaOptions(measure: EffectMeasure.or, method: TauMethod.fixed, mantelHaenszelFixed: true)), al);
    expectResult('meta-reg', metaRegression(p.studies, const MetaOptions(measure: EffectMeasure.rr), const [Moderator('latitude'), Moderator('alloc', categorical: true)]), al);
    final ad = parseCsv(File('test/reference/diagmeta_auditc.csv').readAsStringSync()).dataset;
    final st = [for (var i = 0; i < ad.rowCount; i++) Study('s$i', 'S$i', {for (final k in ['TP', 'FP', 'FN', 'TN']) k.toLowerCase(): SourcedValue(parseNumber(ad.cell(i, k)))})];
    expectResult('diag meta', diagnosticMetaAnalysis(st), {for (final x in st) x.label});
  });

  test('prédiction, imputation dans le bootstrap, validation externe', () {
    final ds = parseCsv(File('test/reference/cardiometabolique_simule.csv').readAsStringSync()).dataset;
    final ext = parseCsv(File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync()).dataset;
    final al = dataTokens([ds, ext]);
    const spec = PredictionSpec(targetPopulation: 'Adults', outcome: 'evenement_5ans', eventLevel: '1', horizon: '5 years', intendedUse: 'Screening',
        predictors: [TermSpec('age'), TermSpec('hdl'), TermSpec('tabac', categorical: true, reference: 'non')],
        referencePredictors: [TermSpec('age')], referenceName: 'Age only');
    final dev = developPredictionModel(ds, spec, bootstrap: 10);
    expectResult('prediction', dev, al);
    expectResult('prediction MI', developPredictionModelMI(ds, spec, m: 2, bootstrap: 5), al);
    expectResult('external', externalValidation(ext, ModelEquation.fromDevelopment(dev), population: 'External cohort'), al);
    final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
    final sd = buildSurvivalDesign(lung, 'time', 'deces', 'oui', const [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F')]);
    expectResult('cox prediction', developCoxPredictionModel(sd, horizon: 365, bootstrap: 5, targetPopulation: 'lung cancer', intendedUse: 'teaching', timeUnit: 'days'),
        {...al, ...dataTokens([lung])});
    final gen = parseCsv(File('test/reference/genetique_simule.csv').readAsStringSync()).dataset;
    final genTok = {...al, ...dataTokens([gen])};
    expectResult('hwe', hardyWeinberg(159, 119, 72, major: 'T', minor: 'C', variant: 'rs4'), genTok);
    expectResult('association', snpAssociation(gen, 'rs1', 'statut', 'cas'), genTok);
    expectResult('scan', snpScan(gen, ['rs1', 'rs2', 'rs4'], 'statut', 'cas', covariates: const [TermSpec('age')]), genTok);
    final pat = parseCsv(File('test/reference/pathogenes_simule.csv').readAsStringSync()).dataset;
    final patTok = {...genTok, ...dataTokens([pat])};
    expectResult('mutation phenotype', mutationPhenotypeConcordance(pat, 'rifampicine', 'R', ['rpoB_S450L', 'rpoB_H445Y']), patTok);
    expectResult('type diversity', typeDiversity(pat, 'lignee'), patTok);
    expectResult('qpcr curve', qpcrStandardCurve([1, 2, 3, 4, 5], [33.1, 29.8, 26.4, 23.1, 19.7], unknownCt: [25]));
    expectResult('qpcr relative', qpcrRelativeQuantification([25, 25.4, 24.8], [18, 18.2, 17.9], [23, 23.3, 22.6], [18.1, 18, 17.8]));
    expectResult('qpcr lod', qpcrLimitOfDetection([1, 3, 10, 30, 100], [2, 7, 15, 19, 20], [20, 20, 20, 20, 20]));
    final rna = File('test/reference/rnaseq_simule.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
    expectResult('expression', differentialExpression([for (final l in rna) l.split(',').first.replaceAll('"', '')],
        [for (final l in rna) [for (final c in l.split(',').skip(1)) double.parse(c)]], [false, false, false, false, true, true, true, true]));
    final plan = File('test/reference/rnaseq_plan_simule.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
    final planGroups = [for (final g in ['A', 'B', 'C']) for (var i = 0; i < 4; i++) g];
    expectResult('expression design', differentialExpressionDesign([for (final l in plan) l.split(',').first.replaceAll('"', '')],
        [for (final l in plan) [for (final c in l.split(',').skip(1)) double.parse(c)]], ExpressionDesign(planGroups, factors: {'batch': [for (var j = 0; j < 12; j++) j.isEven ? 'L1' : 'L2']},
            covariates: {'rin': [for (var j = 0; j < 12; j++) 6.0 + j / 4]}), samples: [for (var j = 0; j < 12; j++) 'S$j']), {'A', 'B', 'C', 'L1', 'L2', 'batch', 'rin'});
    final bloc = File('test/reference/rnaseq_bloc_simule.csv').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
    expectResult('expression block', differentialExpressionDesign([for (final l in bloc) l.split(',').first.replaceAll('"', '')],
        [for (final l in bloc) [for (final c in l.split(',').skip(1)) double.parse(c)]],
        ExpressionDesign([for (var j = 0; j < 16; j++) j < 8 ? 'control' : 'patient'], factors: {'site': [for (var j = 0; j < 16; j++) j.isEven ? 'skin' : 'blood']},
            block: [for (var j = 0; j < 16; j++) 'S${j ~/ 2}']), minSamples: 8), {'control', 'patient', 'site', 'skin', 'blood'});
    final geno = parsePlinkBed(File('test/reference/genotypes/simule.bed').readAsBytesSync(), File('test/reference/genotypes/simule.bim').readAsStringSync(),
        File('test/reference/genotypes/simule.fam').readAsStringSync());
    final gqc = genotypeQc(geno);
    final gTok = {...geno.samples, for (final v in geno.variants) v.label, 'test/reference/genotypes/simule.bed'};
    expectResult('genotype qc', gqc.result, gTok);
    final vcfQc = genotypeQc(parseVcf(File('test/reference/genotypes/simule.vcf').readAsStringSync()));
    expectResult('genotype qc vcf', vcfQc.result, gTok);
    final gds = genotypeDataset(gqc.cleaned);
    expectResult('genotype scan', snpScan(gds, [for (final v in gqc.cleaned.variants.take(20)) v.id], 'status', 'case'), {...gTok, ...dataTokens([gds])});
    final strat = parsePlinkBed(File('test/reference/genotypes/strat.bed').readAsBytesSync(), File('test/reference/genotypes/strat.bim').readAsStringSync(),
        File('test/reference/genotypes/strat.fam').readAsStringSync());
    final pcaEn = genotypePca(strat);
    expectResult('genotype pca', pcaEn.result, {...strat.samples});
    expectEnglish('pca svg', pcaSvg(pcaEn.result.figures['pca'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    expectResult('scan lambda', snpScan(genotypeDataset(strat), [for (final v in strat.variants.take(60)) v.id], 'status', 'case'),
        {...strat.samples, for (final v in strat.variants) v.id});
    final par = parsePlinkBed(File('test/reference/genotypes/parente.bed').readAsBytesSync(), File('test/reference/genotypes/parente.bim').readAsStringSync(),
        File('test/reference/genotypes/parente.fam').readAsStringSync());
    final kinEn = genotypeKinship(par);
    expectResult('kinship', kinEn.result, {...par.samples});
    expectEnglish('king svg', kingSvg(kinEn.result.figures['king'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    final mq = snpScan(genotypeDataset(strat), [for (final v in strat.variants.take(80)) v.id], 'status', 'case', positions: {for (final v in strat.variants) v.id: (v.chrom, v.pos)});
    expectEnglish('manhattan svg', manhattanSvg(mq.figures['manhattan'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), {for (final v in strat.variants) v.id});
    expectEnglish('qq svg', qqSvg(mq.figures['qq'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    final lg = parsePlinkBed(File('test/reference/genotypes/lmm.bed').readAsBytesSync(), File('test/reference/genotypes/lmm.bim').readAsStringSync(),
        File('test/reference/genotypes/lmm.fam').readAsStringSync());
    final lmmEn = lmmScan(lg.subset(variantIdx: [for (var j = 0; j < 300; j++) j]), [for (var i = 0; i < lg.sampleCount; i++) (i % 7) / 7],
        covariates: [LmmCovariate('sex', [for (final s in lg.sex) s == 1 ? 'M' : 'F'], categorical: true)]);
    expectResult('lmm', lmmEn.result, {...lg.samples, for (final v in lg.variants) v.id, 'M', 'F', 'sex'});
    final locoEn = lmmScan(lg.subset(variantIdx: [for (var j = 0; j < 1500; j += 4) j]), [for (var i = 0; i < lg.sampleCount; i++) (i % 7) / 7], loco: true);
    expectResult('lmm loco', locoEn.result, {...lg.samples, for (final v in lg.variants) v.id});
    final ld = parsePlinkBed(File('test/reference/genotypes/ldsc.bed').readAsBytesSync(), File('test/reference/genotypes/ldsc.bim').readAsStringSync(),
        File('test/reference/genotypes/ldsc.fam').readAsStringSync());
    final ldRef = jsonDecode(File('test/reference/ldsc.json').readAsStringSync()) as Map;
    for (final sc in ['A', 'B']) {
      final ldEn = ldscFromScan(ld, [for (final x in ldRef['chi2_$sc'] as List) (x as num).toDouble()], n: ld.sampleCount, scanName: 'the scan');
      expectResult('ldsc $sc', ldEn.result, {for (final v in ld.variants) v.id});
      expectEnglish('ldsc svg', ldscSvg(ldEn.result.figures['ldsc'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    }
    final rgRef = jsonDecode(File('test/reference/rg.json').readAsStringSync()) as Map;
    List<double> dl(Object? l) => [for (final x in l as List) (x as num).toDouble()];
    final rgEn = geneticCorrelationFromScans(ld, dl(rgRef['z1']), dl(rgRef['z2']), n: ld.sampleCount, trait1: 'diabetes', trait2: 'coronary disease');
    expectResult('genetic correlation', rgEn.result, {for (final v in ld.variants) v.id, 'diabetes', 'coronary disease'});
    expectEnglish('rg svg', ldscSvg(rgEn.result.figures['ldsc'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    expectResult('genetic correlation undefined', geneticCorrelation([for (var j = 0; j < 400; j++) j.isEven ? 0.3 : -0.3], [for (var j = 0; j < 400; j++) j.isEven ? 0.3 : -0.3],
        [for (var j = 0; j < 400; j++) 1.0 + (j % 7) / 3], n: 1000, m: 400).result, const {});
    final glmmEn = glmmScan(lg.subset(variantIdx: [for (var j = 0; j < 300; j++) j]), [for (var i = 0; i < lg.sampleCount; i++) (i % 5 == 0 ? 1.0 : 0.0)],
        covariates: [LmmCovariate('sex', [for (final s in lg.sex) s == 1 ? 'M' : 'F'], categorical: true)]);
    expectResult('glmm', glmmEn.result, {...lg.samples, for (final v in lg.variants) v.id, 'M', 'F', 'sex'});
    final mrDs = parseCsv(File('test/reference/mr_ldl_chd.csv').readAsStringSync()).dataset;
    List<double> mrCol(String c) => [for (var i = 0; i < mrDs.rowCount; i++) double.parse(mrDs.cell(i, c)!)];
    final mrEn = mendelianRandomization(mrCol('beta_ldl'), mrCol('se_ldl'), mrCol('beta_chd'), mrCol('se_chd'),
        names: [for (var i = 0; i < mrDs.rowCount; i++) mrDs.cell(i, 'variant')!], exposure: 'LDL cholesterol', outcome: 'coronary disease', iterations: 500);
    expectResult('mendelian randomization', mrEn.result, {for (var i = 0; i < mrDs.rowCount; i++) mrDs.cell(i, 'variant')!});
    expectEnglish('mr svg', mrSvg(mrEn.result.figures['mr'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    final mvEn = multivariableMendelianRandomization([mrCol('beta_ldl'), mrCol('beta_hdl'), mrCol('beta_tg')], [mrCol('se_ldl'), mrCol('se_hdl'), mrCol('se_tg')],
        mrCol('beta_chd'), mrCol('se_chd'), exposures: ['LDL', 'HDL', 'TG'], outcome: 'coronary disease');
    expectResult('multivariable mr', mvEn.result, const {'LDL', 'HDL', 'TG'});
    final bd = parseCsv(File('test/reference/mr_bidirectionnel_simule.csv').readAsStringSync()).dataset;
    List<double> bcol(String c) => [for (var i = 0; i < bd.rowCount; i++) if (bd.cell(i, 'instrument') == 'X') double.parse(bd.cell(i, c)!)];
    final stEn = steigerDirectionality(bcol('beta_x'), bcol('se_x'), bcol('beta_y'), bcol('se_y'), nX: 60000, nY: 90000, exposure: 'X', outcome: 'Y');
    expectResult('steiger', stEn.result, const {'X', 'Y'});
    final hbEn = parseCsv(File('test/reference/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;
    final longEn = longitudinalMixedModel(hbEn, const ModelFormula('hba1c', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')], interactions: [('mois', 'bras')]), subject: 'patient', slope: 'mois');
    expectResult('gee', geeRegression(hbEn, const ModelFormula('hypoglycemies', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A')]), subject: 'patient', family: GeeFamily.poisson), const {'hypoglycemies', 'mois', 'bras', 'patient'});
    final qEn = parseCsv(File('test/reference/absences_quine.csv').readAsStringSync()).dataset;
    expectResult('count nb', countRegression(qEn, const ModelFormula('jours_absence', [TermSpec('origine', categorical: true, reference: 'aborigene'), TermSpec('sexe', categorical: true, reference: 'F')])),
        const {'jours_absence', 'origine', 'aborigene', 'non_aborigene', 'sexe'});
    final hsEn = parseCsv(File('test/reference/satisfaction_logement.csv').readAsStringSync()).dataset;
    const hsF = ModelFormula('satisfaction', [TermSpec('influence', categorical: true, reference: 'faible'), TermSpec('contact', categorical: true, reference: 'faible')]);
    const hsAllow = {'satisfaction', 'influence', 'faible', 'moyenne', 'forte', 'contact', 'fort', '1_faible', '2_moyenne', '3_elevee'};
    expectResult('ordinal', ordinalRegression(hsEn, hsF), hsAllow);
    expectResult('multinomial', multinomialRegression(hsEn, hsF), hsAllow);
    final tkEn = parseCsv(File('test/reference/tiques_lagopede.csv').readAsStringSync()).dataset;
    expectResult('glmm', glmmLongitudinal(tkEn, const ModelFormula('tiques', [TermSpec('annee', categorical: true, reference: 'a95'), TermSpec('altitude')]), subject: 'couvee', family: GlmmFamily.poisson),
        const {'tiques', 'annee', 'a95', 'a96', 'a97', 'altitude', 'couvee'});
    final vetEn = parseCsv(File('test/reference/cox_veteran.csv').readAsStringSync()).dataset;
    final rmEn = rmstAnalysis(vetEn.numeric('time'), vetEn.text('deces'), 'oui', groupRaw: vetEn.text('trt'), tau: 300, timeUnit: 'days', groupName: 'arm');
    expectResult('rmst', rmEn, const {'standard', 'test', 'oui', 'arm', 'days'});
    expectEnglish('rmst svg', kmSvg((rmEn.figures['kaplanMeier'] as Map).cast()).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'standard', 'test'});
    final stfEn = parseCsv(File('test/reference/greffe_stanford.csv').readAsStringSync()).dataset;
    expectResult('landmark', landmarkAnalysis(stfEn, time: 'jours', status: 'deces', eventLevel: 'oui', switchTime: 'attente_greffe', landmark: 30, terms: [const TermSpec('age')]),
        const {'jours', 'deces', 'oui', 'non', 'attente_greffe', 'expose_au_landmark', 'temps_depuis_landmark', 'age', 'greffe', 'chirurgie', 'patient'});
    final mcDs = parseCsv(File('test/reference/creatinine_serum_plasma.csv').readAsStringSync()).dataset;
    final pbEn = methodComparison(mcDs.numeric('creatinine_serum'), mcDs.numeric('creatinine_plasma'), xName: 'creatinine_serum', yName: 'creatinine_plasma', unit: 'mg/dL', decisionLevels: const [1, 2]);
    expectResult('passing-bablok', pbEn, const {'creatinine_serum', 'creatinine_plasma', 'mg/dL'});
    expectResult('deming', methodComparison(mcDs.numeric('creatinine_serum'), mcDs.numeric('creatinine_plasma'), kind: MethodComparisonKind.deming, errorRatio: 2), const {});
    expectEnglish('method comparison svg', methodComparisonSvg(pbEn.figures['methodComparison'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'creatinine_serum', 'creatinine_plasma'});
    final calRef = jsonDecode(File('test/reference/calibration.json').readAsStringSync())['ext'] as Map;
    final calEn = calibrationAssessment([for (final v in calRef['p'] as List) (v as num).toDouble()], [for (final v in calRef['y'] as List) (v as num).toDouble()]);
    expectResult('calibration', calEn, const {});
    expectEnglish('calibration svg', calibrationSvg((calEn.figures['calibration'] as List).cast(), smooth: (calEn.figures['calibrationSmooth'] as List).cast()).replaceAll(RegExp(r'<[^>]+>'), ' '), const {});
    final psEn = parseCsv(File('test/reference/statines_observationnel_simule.csv').readAsStringSync()).dataset;
    const psCov = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('diabete', categorical: true, reference: 'non'), TermSpec('ldl')];
    const psAllow = {'statine', 'oui', 'non', 'evenement', 'age', 'sexe', 'diabete', 'ldl', 'F', 'H'};
    final pmEn = propensityAnalysis(psEn, treatment: 'statine', treatedLevel: 'oui', covariates: psCov, outcome: 'evenement', outcomeEvent: '1', caliper: 0.2);
    expectResult('propensity matching', pmEn, psAllow);
    expectResult('propensity iptw', propensityAnalysis(psEn, treatment: 'statine', treatedLevel: 'oui', covariates: psCov, outcome: 'evenement', method: PropensityMethod.iptwAte), psAllow);
    expectEnglish('love plot svg', lovePlotSvg(pmEn.figures['lovePlot'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), psAllow);
    expectEnglish('ps overlap svg', psOverlapSvg(pmEn.figures['psOverlap'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), psAllow);
    final splDs = parseCsv(File('test/reference/regression_data.csv').readAsStringSync()).dataset;
    final spEn = logisticRegression(buildDesign(splDs, const ModelFormula('hta', [TermSpec('age', transform: TermTransform.rcs4), TermSpec('sexe', categorical: true, reference: 'F')], eventLevel: '1'), binaryOutcome: true));
    expectResult('spline logistic', spEn, const {'hta', 'age', 'sexe', 'F', 'H'});
    expectEnglish('dose-response svg', doseResponseSvg((spEn.figures['doseResponse'] as List).first as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'age'});
    final riDs = parseCsv(File('test/reference/creatinine_reference_simule.csv').readAsStringSync()).dataset;
    final riEn = referenceInterval(riDs.numeric('creatinine'), groups: riDs.text('sexe'), groupName: 'sex', variable: 'creatinine', unit: 'µmol/L');
    expectResult('reference interval', riEn, const {'creatinine', 'sex', 'H', 'F', 'µmol/L'});
    expectResult('reference interval robust', referenceInterval(riDs.numeric('creatinine'), method: ReferenceMethod.robust, removeOutliers: true), const {});
    expectEnglish('reference svg', referenceIntervalSvg(riEn.figures['referenceInterval'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'creatinine', 'µmol/L'});
    final epDs = parseCsv(File('test/reference/ep05_vca.csv').readAsStringSync()).dataset;
    expectResult('precision ep05', precisionAnalysis(epDs.numeric('y'), epDs.text('day'), runRaw: epDs.text('run'), claimRepeatability: 1.5, claimWithinLab: 2), const {});
    final eqRef = jsonDecode(File('test/reference/equivalence_evalue.json').readAsStringSync()) as Map;
    List<double> dl2(String k) => [for (final x in eqRef[k] as List) (x as num).toDouble()];
    expectResult('tost', equivalenceMeans(dl2('a'), dl2('b'), low: -5, high: 5, xName: 'generic', yName: 'reference', unit: 'mmHg'), const {'generic', 'reference', 'mmHg'});
    expectResult('non-inferiority', equivalenceMeans(dl2('a'), dl2('b'), hypothesis: EquivalenceHypothesis.nonInferiorityLowerBetter, margin: 4, paired: false), const {});
    expectResult('tost proportions', equivalenceProportions(93, 150, 81, 140, low: -0.1, high: 0.1), const {});
    expectResult('e-value', eValue(0.7, lower: 0.55, upper: 0.9, scale: EValueScale.hazardRatioCommon), const {});
    expectResult('e-value null', eValue(1.3, lower: 0.9, upper: 1.9), const {});
    final itsDs = parseCsv(File('test/reference/serie_interrompue_simule.csv').readAsStringSync()).dataset;
    final itsEn = interruptedTimeSeries(itsDs.numeric('mois'), itsDs.numeric('admissions'), 25, family: SeriesFamily.poisson, population: itsDs.numeric('population'), outcome: 'admissions', timeName: 'month');
    expectResult('its poisson', itsEn, const {'admissions', 'month'});
    expectResult('its gaussian', interruptedTimeSeries(itsDs.numeric('mois'), itsDs.numeric('taux_100k'), 25, outcome: 'rate', timeName: 'month'), const {'rate', 'month'});
    expectEnglish('its svg', itsSvg(itsEn.figures['its'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'admissions', 'month'});
    final bpEn = bayesProportion(7, 40, prior: BetaPrior.informative, priorMean: 0.1, priorWeight: 20, threshold: 0.1);
    expectResult('bayes proportion', bpEn, const {});
    final beEn = bayesEffect(0.75, 0.58, 0.97, target: 0.8, label: 'RR');
    expectResult('bayes effect', beEn, const {'RR'});
    expectEnglish('bayes svg', bayesSvg(beEn.figures['bayes'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'RR'});
    const questionEn = 'In a cohort, does smoking increase the risk of myocardial infarction in adults compared with non-smokers?';
    final pr = Project(id: 'en', title: 'Smoking', createdAt: '', question: const ResearchQuestion(text: questionEn));
    autoCompleteProject(pr);
    const qAllow = {'smoking', 'myocardial', 'infarction', 'adults', 'non-smokers', 'cohort', 'Smoking', 'In', 'does', 'increase', 'the', 'risk', 'of', 'in', 'compared', 'with', 'a'};
    expectEnglish('roadmap', [for (final r in projectRoadmap(pr)) ...r.lines].join('\n').replaceAll(questionEn, ' '), qAllow);
    expectEnglish('draft plan', pr.analysisPlan, qAllow);
    expectEnglish('protocol outline', [for (final x in protocolOutline(pr)) ...[x.title, ...x.paragraphs]].join('\n').replaceAll(questionEn, ' '), {...qAllow, 'Smoking', 'smoking'});
    expectEnglish('inference reasons', [for (final r in inferQuestion(questionEn).reasons) r.value].join('\n'), qAllow);
    expectEnglish('protocol error', () {
      try {
        protocolFromText(' ');
      } on StatInputError catch (e) {
        return e.message;
      }
      return '';
    }(), const {});
    final dsEn = Dataset(['v', 'g'], [['1', '1'], ['999', '2'], ['3', '1']]);
    final dicoEn = applyDataDictionary(dsEn, Dataset(['variable', 'type', 'missing', 'levels'], [['v', 'quantitative', '999', null], ['g', 'categorical', null, '1=control;2=treated'], ['zz', 'bogus', null, null]]));
    expectEnglish('dictionary', dicoEn.summary().join(' '), const {'zz', 'v', 'g', 'bogus', '999'});
    expectResult('lmm longitudinal', longEn, const {'hba1c', 'mois', 'bras', 'age', 'patient'});
    expectEnglish('trajectories svg', trajectoriesSvg(longEn.figures['trajectories'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'hba1c', 'mois'});
    for (final r in [
      powerMeans(delta: 5, sd: 10, ratio: 2), powerMeans(delta: 3, sd: 8, design: MeansDesign.paired, n: 30), powerProportions(p1: 0.3, p2: 0.18, n: 150),
      powerCaseControl(or: 2, p0: 0.2, ratio: 2), powerSurvival(hr: 0.7, pC: 0.45), powerGwas(maf: 0.25, or: 1.15, nCases: 5000),
    ]) {
      expectResult(r.methodId, r);
      expectEnglish('${r.methodId} svg', powerCurveSvg(r.figures['powerCurve'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    }
    final crDs = parseCsv(File('test/reference/risques_concurrents_simule.csv').readAsStringSync()).dataset;
    final crEn = competingRisksAnalysis(crDs.numeric('mois'), crDs.text('statut'), 'rechute', {'censure'}, groupRaw: crDs.text('bras'), horizon: 24, timeUnit: 'months', groupName: 'arm');
    expectResult('cumulative incidence', crEn, const {'rechute', 'deces', 'censure', 'arm', 'months'});
    expectEnglish('cif svg', cifSvg(crEn.figures['cumulativeIncidence'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '), const {'rechute', 'deces'});
    final fgEn = fineGrayRegression(buildCompetingDesign(crDs, 'mois', 'statut', 'rechute', {'censure'}, [TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')]));
    expectResult('fine-gray', fgEn, const {'rechute', 'deces', 'censure', 'mois', 'statut', 'bras', 'age'});
    final st = parseCsv(File('test/reference/greffe_stanford.csv').readAsStringSync()).dataset;
    final stLong = splitAtSwitch(st, time: 'jours', status: 'deces', eventLevel: 'oui', switchTime: 'attente_greffe', covariate: 'greffe', yes: 'yes', no: 'no');
    final tdEn = coxRegression(buildCountingDesign(stLong, 'debut', 'fin', 'deces', 'oui', [TermSpec('greffe', categorical: true, reference: 'no'), TermSpec('age')]));
    expectResult('time-dependent cox', tdEn, const {'greffe', 'debut', 'fin', 'deces', 'oui', 'non', 'age'});
    final gh = harmoniseGwas(parseGwasSumstats(File('test/reference/gwas_exposition_simule.tsv').readAsStringSync(), source: 'exposure.tsv'),
        parseGwasSumstats(File('test/reference/gwas_issue_simule.tsv').readAsStringSync(), source: 'outcome.tsv'));
    expectEnglish('gwas harmonisation', [...gh.summary(), gh.toDataset().source, for (final s in HarmonisationStatus.values) s.label].join('\n'), const {'exposure.tsv', 'outcome.tsv'});
    final pg = parsePlinkBed(File('test/reference/genotypes/prs.bed').readAsBytesSync(), File('test/reference/genotypes/prs.bim').readAsStringSync(),
        File('test/reference/genotypes/prs.fam').readAsStringSync());
    final prsEn = polygenicRiskScore(pg, [for (final p in pg.phenotype) p == null ? null : (p == 2 ? 1.0 : 0.0)], outcomeName: 'disease');
    expectResult('polygenic score', prsEn.result, {for (final v in pg.variants) v.id, 'disease'});
    final pc = parseCsv(File('test/reference/genotypes/prs_covariables.csv').readAsStringSync()).dataset;
    final pcRow = {for (var i = 0; i < pc.rowCount; i++) pc.cell(i, 'id')!: i};
    final prsAdj = polygenicRiskScore(pg, [for (final p in pg.phenotype) p == null ? null : (p == 2 ? 1.0 : 0.0)], outcomeName: 'disease', covariates: [
      LmmCovariate('sex', [for (final s in pg.samples) pc.cell(pcRow[s]!, 'sexe')], categorical: true, reference: 'H'),
      LmmCovariate('age', [for (final s in pg.samples) pc.cell(pcRow[s]!, 'age')]),
    ]);
    expectResult('polygenic score adjusted', prsAdj.result, {for (final v in pg.variants) v.id, 'disease', 'sex', 'age'});
    expectEnglish('prs svg', prsSvg(prsEn.result.figures['prs'] as Map).replaceAll(RegExp(r'<[^>]+>'), ' '));
    final lib = parseFasta(File('test/reference/alignement_adn.fasta').readAsStringSync());
    expectResult('alignment', localAlignmentSearch(lib[2].sequence.substring(50, 400), lib), {for (final r in lib) r.id});
    final libP = parseFasta(File('test/reference/alignement_proteines.fasta').readAsStringSync());
    expectResult('alignment protein', localAlignmentSearch(libP[1].sequence.substring(10, 200), libP), {for (final r in libP) r.id, libP[1].sequence.substring(10, 200)});
    final coxDev = withLang(Lang.fr, () => developCoxPredictionModel(sd, horizon: 365, bootstrap: 5, targetPopulation: 'x', intendedUse: 'y'));
    final coxExt = parseCsv(File('test/reference/cox_externe_simule.csv').readAsStringSync()).dataset;
    final coxEqFr = withLang(Lang.fr, () => CoxEquation.fromDevelopment(coxDev, name: 'Cox model'));
    expectResult('cox external', externalValidationCox(coxExt, coxEqFr, population: 'simulated cohort'), {...al, ...dataTokens([lung, coxExt]), 'x', coxEqFr.source}); // provenance enregistrée avec l'équation (français)
  });

  test('contrôle des données, assistant, registre, audit', () {
    final ds = parseCsv('id;age;sexe;glycemie;statut;hb_avant;hb_apres\n1;45;F;5,4;Oui;12,1;12,5\n2;52;H;6,1;oui ;11,0;11,9\n'
            '3;250;F;98;Non;13,2;13,0\n4;38;F;<0,5;Non;10,5;11,2\n5;61;H;5,9;Non;;12,0\n6;47;F;5,2;Non;12,8;12,9\n6;47;F;5,2;Non;12,8;12,9\n')
        .dataset;
    final rep = checkQuality(ds, outcome: 'statut', predictors: ['sexe']);
    expectEnglish('quality', [for (final i in rep.issues) '${i.message} ${i.suggestion ?? ""}'].join('\n'), {...dataTokens([ds]), '<0,5', '« <0,5 »'});
    for (final q in [
      const ResearchQuestion(),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          outcomeType: OutcomeType.binary, exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true, expectedEvents: 20),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.rct, outcomeType: OutcomeType.continuous,
          exposureType: ExposureType.binary, pairing: Pairing.independent),
      const ResearchQuestion(objective: StudyObjective.predictive, dataLevel: DataLevel.individual, outcomeType: OutcomeType.binary),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort, outcomeType: OutcomeType.timeToEvent,
          exposureType: ExposureType.binary, pairing: Pairing.repeated),
      const ResearchQuestion(dataLevel: DataLevel.aggregatedStudies, outcomeType: OutcomeType.binary, referenceStandardAvailable: true),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort, outcomeType: OutcomeType.timeToEvent,
          exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort, outcomeType: OutcomeType.timeToEvent,
          exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true, competingRisk: true, timeVaryingExposure: true),
      const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort, outcomeType: OutcomeType.count,
          exposureType: ExposureType.binary, pairing: Pairing.repeated, needsAdjustment: true),
    ]) {
      final a = advise(q);
      expectEnglish('advisor', [
        for (final c in a.questions) '${c.prompt} ${c.why}',
        for (final o in a.options) '${o.name} ${o.whenPreferred} ${o.conditions.join(" ")} ${o.cautions.join(" ")}',
        ...a.notes,
        for (final t in OutcomeType.values) outcomeTypeLabel(t),
        for (final d in StudyDesign.values) designLabel(d),
        for (final o in StudyObjective.values) objectiveLabel(o),
      ].join('\n'));
    }
    expectEnglish('matrix', methodMatrixMarkdown());
    final logit = twoByTwo(120, 380, 80, 420, design: StudyDesign.cohort);
    final audit = runAudit(question: const ResearchQuestion(design: StudyDesign.cohort, objective: StudyObjective.explanatory), results: [logit],
        text: 'Smoking causes hypertension. The risk was 1.66 times higher. p = 0.21 so there is no difference. A sensitivity analysis confirmed this.');
    expectEnglish('audit', [for (final f in audit.findings) '${auditFamilyLabel(f.family)} ${f.message} ${f.correction ?? ""}'].join('\n'));
    final audit2 = runAudit(question: const ResearchQuestion(), results: [logit], text: '');
    expectEnglish('audit insufficient', [for (final f in audit2.findings) f.message].join('\n'));
  });

  test('leçons et grilles', () {
    for (final l in buildLessons()) {
      expectEnglish('lesson ${l.id}',
          [l.title, levelLabel(l.level), ...l.body, l.exampleTitle, l.example, ...l.commonErrors, for (final e in l.exercises) '${e.prompt} ${e.choices.join(" ")} ${e.correction}'].join('\n'));
    }
    for (final c in allChecklists) {
      expectEnglish('checklist ${c.id}', [c.title, c.purpose, for (final i in c.items) '${i.section} ${i.text}'].join('\n'));
    }
  });

  test('démonstrations, rapports et figures', () {
    final p1 = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final p2 = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
    final p3 = buildDemoPrediction(File('test/reference/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 10,
        externalCsv: File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync());
    final p4 = buildDemoTb(File('test/reference/tb_rifampicine_simule.csv').readAsStringSync(),
        File('test/reference/tb_references_simule.fasta').readAsStringSync(), File('test/reference/tb_isolat_simule.fasta').readAsStringSync());
    const g5 = 'test/reference';
    final p5 = buildDemoGwas(File('$g5/gwas_simule.bed').readAsBytesSync(), File('$g5/gwas_simule.bim').readAsStringSync(), File('$g5/gwas_simule.fam').readAsStringSync(),
        File('$g5/gwas_covariables_simule.csv').readAsStringSync());
    final p6 = demo6();
    final p7 = buildDemoMr(File('test/reference/mr_ldl_chd.csv').readAsStringSync());
    final p8 = buildDemoSurvivalAdvanced(File('test/reference/risques_concurrents_simule.csv').readAsStringSync());
    final p9 = buildDemoMethodComparison(File('test/reference/creatinine_serum_plasma.csv').readAsStringSync());
    final p10 = buildDemoPublicHealth(File('test/reference/serie_interrompue_simule.csv').readAsStringSync());
    for (final p in [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10]) {
      final al = {
        ...dataTokens([p.dataset!]),
        for (final s in p.studies) ...[s.label, s.subgroup, for (final v in s.values.values) v.source, s.compatibility.comment],
        for (final e in p.journal) e.result['inputs'].toString(),
        'cardiometabolique_externe_simule.csv', 'aghbs_simule.csv', 'bcg_colditz1994.csv', 'cardiometabolique_simule.csv', 'creatinine_serum_plasma.csv', 'mg/dL', 'serie_interrompue_simule.csv',
        // Séquences de la démo 4 (lettres A, C, G, T) et libellés des références : données, pas du texte.
        for (final r in parseFasta(File('test/reference/tb_references_simule.fasta').readAsStringSync())) ...[r.id, r.description],
        for (final l in File('test/reference/gwas_simule.bim').readAsLinesSync()) l.split('\t')[1],
        for (final l in File('test/reference/gwas_simule.fam').readAsLinesSync()) l.split('\t')[1],
        'gwas_simule.bed/.bim/.fam (simulated)',
        for (final l in File('test/reference/genotypes/ldsc_app.bim').readAsLinesSync()) l.split('\t')[1],
        for (final l in File('test/reference/genotypes/ldsc_app.fam').readAsLinesSync()) l.split('\t')[1],
        'genotypes_dl_simule.bed/.bim/.fam (simulated)',
      };
      final rs = [for (final e in p.journal) analysisResultFromJson(e.result)];
      final audit = runAudit(question: p.question, results: rs, text: p.resultsText);
      expectEnglish('demo ${p.id} : texte', '${p.title}\n${p.demoNotice}\n${p.question.toJson()}\n${p.analysisPlan}\n${p.resultsText}\n${[for (final e in p.journal) e.userNote].join("\n")}', al);
      expectEnglish('demo ${p.id} : rapport', projectReportHtml(p, audit: audit, generatedAt: 'now').replaceAll(RegExp(r'<style>[\s\S]*?</style>'), ' ').replaceAll(RegExp(r'<[^>]+>'), ' '), al);
      for (final r in rs) {
        expectEnglish('demo ${p.id} : CSV', resultToCsv(r), al);
      }
    }
    final r = analysisResultFromJson(p2.journal.first.result);
    expectEnglish('forest', forestPlotSvg((r.figures['forest'] as Map).cast()).replaceAll(RegExp(r'<[^>]+>'), ' '),
        {for (final s in p2.studies) s.label});
  });

  test('les brouillons des démonstrations sont audités en anglais (erreurs volontaires repérées)', () {
    final p1 = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final p2 = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
    final p3 = buildDemoPrediction(File('test/reference/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 10);
    Set<AuditFamily> fam(Project p) => {
          for (final f in runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText).alerts) f.family
        };
    expect(fam(p1), containsAll([AuditFamily.causalLanguage, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
    expect(fam(p2), containsAll([AuditFamily.pValueMisread, AuditFamily.overPrecision]));
    expect(fam(p3), containsAll([AuditFamily.predictionOverclaim, AuditFamily.causalLanguage]));
    final p4 = buildDemoTb(File('test/reference/tb_rifampicine_simule.csv').readAsStringSync(),
        File('test/reference/tb_references_simule.fasta').readAsStringSync(), File('test/reference/tb_isolat_simule.fasta').readAsStringSync());
    expect(fam(p4), containsAll([AuditFamily.causalLanguage, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
    final p5 = buildDemoGwas(File('test/reference/gwas_simule.bed').readAsBytesSync(), File('test/reference/gwas_simule.bim').readAsStringSync(),
        File('test/reference/gwas_simule.fam').readAsStringSync(), File('test/reference/gwas_covariables_simule.csv').readAsStringSync());
    expect(fam(p5), containsAll([AuditFamily.causalLanguage, AuditFamily.orAsRr, AuditFamily.pValueMisread, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
    final p6 = demo6();
    expect(fam(p6), containsAll([AuditFamily.genomicInflation, AuditFamily.causalLanguage, AuditFamily.overPrecision, AuditFamily.announcedNotDone]));
    final p7 = buildDemoMr(File('test/reference/mr_ldl_chd.csv').readAsStringSync());
    expect(fam(p7), containsAll([AuditFamily.causalLanguage, AuditFamily.orAsRr, AuditFamily.overPrecision]));
    final p8 = buildDemoSurvivalAdvanced(File('test/reference/risques_concurrents_simule.csv').readAsStringSync());
    expect(fam(p8), containsAll([AuditFamily.survivalPitfalls, AuditFamily.causalLanguage, AuditFamily.overPrecision]));
    final p9 = buildDemoMethodComparison(File('test/reference/creatinine_serum_plasma.csv').readAsStringSync());
    expect(fam(p9), containsAll([AuditFamily.agreementVsCi, AuditFamily.pValueMisread, AuditFamily.overPrecision]));
    final p10 = buildDemoPublicHealth(File('test/reference/serie_interrompue_simule.csv').readAsStringSync());
    expect(fam(p10), containsAll([AuditFamily.beforeAfter, AuditFamily.overPrecision]));
  });

  test('une équation développée en français s\'applique en anglais, et inversement', () {
    final csv = File('test/reference/cardiometabolique_simule.csv').readAsStringSync();
    final ext = parseCsv(File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync()).dataset;
    final dFr = withLang(Lang.fr, () => buildDemoPrediction(csv, bootstrap: 5));
    final eqFr = ModelEquation.fromDevelopment(analysisResultFromJson(dFr.journal.first.result));
    expect(eqFr.coefficients.keys, contains('Constante'));
    final rEn = externalValidation(ext, eqFr);
    final rFr = withLang(Lang.fr, () => externalValidation(ext, eqFr));
    expect(rEn.statistics['auc'], rFr.statistics['auc']);
    expect(rEn.statistics['slope'], rFr.statistics['slope']);
    final dEn = buildDemoPrediction(csv, bootstrap: 5);
    final eqEn = ModelEquation.fromDevelopment(analysisResultFromJson(dEn.journal.first.result));
    expect(eqEn.coefficients.keys, contains('Intercept'));
    expect(eqEn.coefficients.keys, contains('age (per 10.0 units)'), reason: eqEn.coefficients.keys.join(' | '));
    expect(withLang(Lang.fr, () => externalValidation(ext, eqEn)).statistics['auc'], rFr.statistics['auc']);
  });

  test('un résultat garde la langue dans laquelle il a été calculé', () {
    final r = withLang(Lang.fr, () => proportionCi(12, 400));
    final back = analysisResultFromJson(r.toJson());
    expect(r.toJson()['lang'], 'fr');
    expect(back.methodName, r.methodName);
    expect(proportionCi(12, 400).toJson()['lang'], 'en');
  });

  test('messages d\'erreur', () {
    final msgs = <String>[];
    void cap(void Function() f) {
      try {
        f();
      } on StatInputError catch (e) {
        msgs.add(e.message);
      }
    }
    cap(() => proportionCi(5, 3));
    cap(() => twoByTwo(0, 10, 0, 12));
    cap(() => mcNemar(10, 0, 0, 12));
    cap(() => pairedTTest([1, 2, 3], [1, 2]));
    cap(() => metaAnalysis([Study.binary('X', 0, 10, 0, 12)], const MetaOptions(measure: EffectMeasure.or)));
    cap(() => survivalAnalysis([1, 2], ['0', '0'], '1'));
    expect(msgs.length, 6);
    expectEnglish('errors', msgs.join('\n'));
  });

  test('methodological review', () {
    const text = 'What is the effect of smoking on the risk of myocardial infarction in adults followed for 10 years?';
    final p = Project(id: 'e', title: 'Smoking', createdAt: '');
    p.question = applyInference(const ResearchQuestion(text: text), inferQuestion(text)).$1.copyWith(design: StudyDesign.cohort);
    p.analysisPlan = 'Groups compared with the chi-square test; Student or Kruskal-Wallis for continuous variables; normality by Kolmogorov-Smirnov.';
    final r = reviewProject(p);
    final b = StringBuffer();
    for (final f in r.findings) {
      b.writeln('${reviewLevelLabel(f.level)} ${f.title} ${f.problem} ${f.correction} ${f.fix?.detail ?? ''}');
    }
    expect(r.findings.map((f) => f.id), containsAll(['causal_wording', 'no_adjustment', 'test_pairing', 'ks_normality', 'missing_data', 'alpha', 'sample_size_missing']));
    applyAllCorrections(p);
    expect(p.question.text, startsWith('What is the association between smoking and the risk'));
    expectEnglish('review', '$b\n${p.analysisPlan}');
    // Essai randomisé importé : contrôles élargis, grille SPIRIT, variables, calculs d'effectif.
    final t = Project(id: 't', title: 'Vitamin D randomised trial', createdAt: '');
    t.question = const ResearchQuestion(text: 'Does vitamin D lower blood pressure at 6 months compared with placebo?', design: StudyDesign.rct, objective: StudyObjective.explanatory, outcomeType: OutcomeType.continuous);
    t.protocol = {'population': 'Hypertensive patients.', 'variables': 'Data collected will include sex, age, weight and height.', '_text': 'Randomised trial. Study period: 12 months.'};
    t.inferred['plannedSampleSize'] = '200';
    t.analysisPlan = 'Student t-test at the 5% level.';
    final b2 = StringBuffer();
    for (final f in reviewProject(t).findings) {
      b2.writeln('${f.title} ${f.problem} ${f.correction} ${f.fix?.detail ?? ''}');
    }
    final c = protocolChecklist(t)!;
    for (final i in c.items) {
      b2.writeln('${c.name} ${c.reference} ${i.code} ${i.label}');
    }
    b2.writeln(protocolDictionaryCsv(t));
    for (final r in [sampleSizeCorrelation(r: 0.3, dropout: 0.1), sampleSizePredictionModel(parameters: 6, prevalence: 0.15, r2CoxSnell: 0.18)]) {
      b2.writeln('${r.methodName} ${r.formula} ${r.interpretation.whyThisMethod} ${r.interpretation.whatItMeans} ${r.interpretation.notJustified} ${r.estimates.map((e) => e.label).join(' ')}');
    }
    expect(reviewProject(t).findings.map((f) => f.id), containsAll(['rct_randomisation', 'rct_itt', 'inclusion_age', 'exclusion_criteria', 'recruitment_feasibility']));
    expect(protocolVariables(t).map((v) => v.code), ['sex', 'age', 'weight', 'height']);
    expectEnglish('review (trial)', b2.toString());
  });

  test('case report form, results review, budget and timeline', () {
    final p = Project(id: 'cf', title: 'Anaemia in pregnancy', createdAt: '');
    p.question = const ResearchQuestion(text: 'What factors are associated with anaemia in pregnant women?', outcome: 'anaemia', outcomeType: OutcomeType.binary, design: StudyDesign.crossSectional, objective: StudyObjective.explanatory, horizon: '28 days');
    p.protocol = {'variables': 'Data collected will include sex, age, weight, blood pressure, haemoglobin and smoking.', '_text': 'Cross-sectional study. Study period: 12 months.', 'analysis': 'Logistic regression at the 5% level.'};
    p.inferred['plannedSampleSize'] = '400';
    p.planning.addAll({'u_lab': '2500', 'u_participants': '1000'});
    p.journal.add(const JournalEntry(id: 'j', timestamp: '', methodId: 'cox', methodName: 'Cox model', result: {}));
    p.resultsText = '250 patients were included. The primary outcome was haemoglobin level (p = 0.03). Among women, the effect was larger.';
    final fields = crfFields(p);
    expect(fields.map((f) => f.code), containsAll(['sex', 'age', 'weight', 'sbp', 'dbp', 'haemoglobin', 'smoking']));
    final b = StringBuffer();
    for (final f in fields) {
      b.writeln('${f.label} ${crfTypeWord(f.type)} ${f.unit} ${f.levels.join(' ')}');
    }
    b.writeln(crfDictionaryCsv(fields));
    final parts = crfWorkbookParts(fields);
    b.writeln(RegExp(r'(?:error|prompt)="([^"]*)"').allMatches(parts['xl/worksheets/sheet1.xml']!).map((m) => m.group(1)).join('\n'));
    b.writeln(parts['xl/workbook.xml']);
    final r = reviewProject(p);
    expect(r.findings.map((f) => f.id), containsAll(['outcome_switch', 'sample_attained', 'unplanned_analysis', 'subgroups', 'p_without_ci']));
    for (final f in r.findings) {
      b.writeln('${f.title} ${f.problem} ${f.correction} ${f.fix?.detail ?? ''}');
    }
    final pl = studyPlanning(p);
    for (final ph in pl.phases) {
      b.writeln(ph.label);
    }
    for (final l in pl.lines) {
      b.writeln('${l.label} ${l.unitLabel}');
    }
    b.writeln(pl.assumptions.join(' '));
    b.writeln(planningParagraphs(p, (w) => '[To complete: $w]').join('\n'));
    expectEnglish('crf, results, planning', b.toString());
  });
}
