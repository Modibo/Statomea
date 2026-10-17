/// Les démonstrations complètes (livrable 7). Chaque démonstration est
/// un projet entièrement calculé par le moteur : question, plan, données,
/// contrôle, analyses journalisées et un BROUILLON de texte contenant des
/// erreurs volontaires à repérer avec l'audit.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../advisor/advisor.dart';
import '../data/csv.dart';
import '../data/dataset.dart';
import 'dart:typed_data';

import '../genetics/alignment.dart';
import '../genetics/examples.dart' show stanfordHeartExample;
import '../genetics/association.dart';
import '../genetics/genotype_io.dart';
import '../genetics/genotype_kinship.dart';
import '../genetics/genotype_ldsc.dart';
import '../genetics/genotype_pca.dart';
import '../genetics/mendelian.dart';
import '../genetics/pathogens.dart';
import '../genetics/qpcr.dart';
import '../inference/compare.dart';
import '../inference/competing_risks.dart';
import '../inference/correlation.dart';
import '../inference/method_comparison.dart';
import '../inference/survival.dart';
import '../inference/proportion.dart';
import '../inference/two_by_two.dart';
import '../meta/meta.dart';
import '../meta/meta_regression.dart';
import '../model/design.dart';
import '../model/result.dart';
import '../prediction/external_validation.dart';
import '../prediction/model_development.dart';
import '../regression/design_matrix.dart';
import '../regression/glm.dart';
import '../regression/cox.dart';
import '../regression/fine_gray.dart';
import 'project.dart';

String get simulatedNotice => tr(
    'DONNÉES SIMULÉES à but pédagogique (script R et graine fournis dans validation/r/). Elles ne décrivent aucune population réelle et ne doivent pas être citées comme résultats épidémiologiques.',
    'SIMULATED DATA for teaching purposes (R script and seed provided in validation/r/). They describe no real population and must not be cited as epidemiological results.');

/// Sous-ensemble de lignes (filtre documenté dans la source).
Dataset subsetRows(Dataset ds, bool Function(int row) keep, String description) {
  final rows = [for (var i = 0; i < ds.rowCount; i++) if (keep(i)) [for (final n in ds.names) ds.cell(i, n)]];
  return Dataset(ds.names, rows, source: tr('${ds.source} — sous-ensemble : $description', '${ds.source} — subset: $description'));
}

JournalEntry _entry(int i, AnalysisResult r, {Dataset? data, String note = ''}) =>
    JournalEntry.fromResult(r, id: 'demo-${i.toString().padLeft(2, '0')}', timestamp: tr('démonstration', 'demonstration'), data: data, note: note);

/// Démonstration 1 : prévalence de l'AgHBs et événements rares.
Project buildDemoAghbs(String csv) {
  final ds = parseCsv(csv, source: tr('aghbs_simule.csv (simulé)', 'aghbs_simule.csv (simulated)')).dataset;
  final hbs = ds.text('aghbs');
  final n = [for (final v in hbs) ?v].length;
  final pos = hbs.where((v) => v == 'positif').length;
  final res = ds.text('residence');
  int count(String r, [String? s]) => [for (var i = 0; i < ds.rowCount; i++) if (res[i] == r && (s == null || hbs[i] == s)) i].length;
  final journal = <JournalEntry>[];
  final r1 = proportionCi(pos, n, label: tr("Prévalence de l'AgHBs", 'HBsAg prevalence'));
  journal.add(_entry(1, r1, data: ds, note: tr('Critère principal : prévalence chez les femmes enceintes dépistées.', 'Primary outcome: prevalence among screened pregnant women.')));
  final r2 = proportionDifference(count('rural', 'positif'), count('rural'), count('urbain', 'positif'), count('urbain'),
      group1: 'rural', group2: 'urbain');
  journal.add(_entry(2, r2, data: ds));
  final d3 = buildDesign(
      ds,
      const ModelFormula('aghbs', [TermSpec('residence', categorical: true, reference: 'urbain'), TermSpec('age', transform: TermTransform.perUnit, unitStep: 10)],
          eventLevel: 'positif'),
      binaryOutcome: true);
  journal.add(_entry(3, poissonRobustRegression(d3, design: StudyDesign.crossSectional), data: ds,
      note: tr("Rapport de prévalences ajusté sur l'âge (transversal : RP, pas RR).", 'Prevalence ratio adjusted for age (cross-sectional: PR, not RR).')));
  // Enfants suivis nés de mères porteuses : événements rares.
  final inf = subsetRows(ds, (i) => ds.cell(i, 'enfant_suivi') == 'oui', tr('enfants suivis nés de mères AgHBs+', 'followed-up children born to HBsAg+ mothers'));
  final y = inf.text('enfant_infecte');
  final nInf = y.where((v) => v != null).length;
  final infected = y.where((v) => v == 'oui').length;
  journal.add(_entry(4, proportionCi(infected, nInf, label: tr('Transmission mère-enfant', 'Mother-to-child transmission')), data: inf,
      note: tr('Proportion rare : IC exact et de Wilson.', 'Rare proportion: exact and Wilson CI.')));
  final e = inf.text('aghbe');
  int c(String m, String o) => [for (var i = 0; i < inf.rowCount; i++) if (e[i] == m && y[i] == o) i].length;
  journal.add(_entry(5, twoByTwo(c('positif', 'oui'), c('positif', 'non'), c('negatif', 'oui'), c('negatif', 'non'),
      design: StudyDesign.cohort, exposure: tr('AgHBe maternel', 'Maternal HBeAg'), outcome: tr('Enfant infecté', 'Infected child')), data: inf));
  final d6 = buildDesign(inf, const ModelFormula('enfant_infecte', [TermSpec('aghbe', categorical: true, reference: 'negatif')], eventLevel: 'oui'),
      binaryOutcome: true);
  journal.add(_entry(6, logisticRegression(d6, design: StudyDesign.cohort), data: inf,
      note: tr("Montré volontairement : la séparation rend l'estimation du maximum de vraisemblance inutilisable.", 'Shown on purpose: separation makes the maximum likelihood estimate unusable.')));
  journal.add(_entry(7, firthRegression(d6), data: inf, note: tr('Alternative pénalisée : OR fini mais très imprécis.', 'Penalized alternative: finite but very imprecise OR.')));
  return Project(
    id: 'demo-aghbs',
    title: tr("Démo 1 — Prévalence de l'AgHBs et événements rares", 'Demo 1 — HBsAg prevalence and rare events'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: simulatedNotice,
    dataset: ds,
    question: ResearchQuestion(
      text: tr("Quelle est la prévalence de l'AgHBs chez les femmes enceintes dépistées, varie-t-elle selon la résidence, et quelle est la fréquence de la transmission à l'enfant malgré la sérovaccination ?",
          'What is the prevalence of HBsAg among screened pregnant women, does it vary by residence, and how frequent is transmission to the child despite serovaccination?'),
      population: tr('Femmes enceintes dépistées en consultation prénatale (population simulée)', 'Pregnant women screened at antenatal visits (simulated population)'),
      exposure: tr('Résidence rurale ; statut AgHBe maternel (pour la transmission)', 'Rural residence; maternal HBeAg status (for transmission)'),
      comparator: tr('Résidence urbaine ; mères AgHBe négatives', 'Urban residence; HBeAg-negative mothers'),
      outcome: tr("Portage de l'AgHBs ; infection de l'enfant", 'HBsAg carriage; infection of the child'),
      horizon: tr("Au dépistage ; 9 mois de vie pour l'enfant", 'At screening; 9 months of age for the child'),
      design: StudyDesign.crossSectional,
      objective: StudyObjective.descriptive,
      outcomeType: OutcomeType.binary,
      exposureType: ExposureType.binary,
      pairing: Pairing.independent,
      dataLevel: DataLevel.individual,
      needsAdjustment: true,
      expectedEvents: 5,
    ),
    analysisPlan: tr(
        "1) Prévalence de l'AgHBs avec IC exact et de Wilson. 2) Différence de prévalence rural − urbain (Newcombe). 3) Rapport de prévalences ajusté sur l'âge (Poisson robuste ; transversal). 4) Proportion d'enfants infectés (IC exact ; peu d'événements). 5) Association avec l'AgHBe maternel : Fisher ; logistique non pénalisée attendue instable ; Firth.",
        '1) HBsAg prevalence with exact and Wilson CI. 2) Difference in prevalence rural − urban (Newcombe). 3) Prevalence ratio adjusted for age (robust Poisson; cross-sectional). 4) Proportion of infected children (exact CI; few events). 5) Association with maternal HBeAg: Fisher; unpenalized logistic regression expected to be unstable; Firth.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit.
    resultsText: tr(
        "La prévalence de l'AgHBs était de ${fmtFixed(pos / n * 100, 4)} %. La résidence rurale entraîne un portage plus fréquent. Aucune différence selon l'âge n'a été observée (p > 0,05), l'âge n'a donc pas d'effet. La transmission mère-enfant était de ${fmtFixed(infected / nInf * 100, 1)} %, ce qui prouve l'efficacité de la sérovaccination. Une analyse de sensibilité a confirmé ces résultats.",
        'HBsAg prevalence was ${fmtFixed(pos / n * 100, 4)}%. Rural residence causes more frequent carriage. No difference by age was observed (p > 0.05), so age has no effect. Mother-to-child transmission was ${fmtFixed(infected / nInf * 100, 1)}%, which proves the effectiveness of serovaccination. A sensitivity analysis confirmed these results.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 2 : métaanalyse du BCG (données publiées, Colditz 1994).
Project buildDemoMeta(String csv) {
  final ds = parseCsv(csv, source: tr('bcg_colditz1994.csv (données publiées)', 'bcg_colditz1994.csv (published data)')).dataset;
  final studies = <Study>[];
  for (var i = 0; i < ds.rowCount; i++) {
    final label = ds.cell(i, 'etude')!;
    final src = tr('Colditz et al., JAMA 1994, tableau 1 (via metafor::dat.bcg)', 'Colditz et al., JAMA 1994, table 1 (via metafor::dat.bcg)');
    final lat = parseNumber(ds.cell(i, 'latitude'))!;
    studies.add(Study(label, label, {
      for (final k in ['e1', 'n1', 'e2', 'n2']) k: SourcedValue(parseNumber(ds.cell(i, k)), source: src),
      'latitude': SourcedValue(lat, source: src),
      'annee': SourcedValue(parseNumber(ds.cell(i, 'annee')), source: src),
    },
        subgroup: ds.cell(i, 'allocation')!,
        compatibility: StudyCompatibility(
          population: Compat.yes,
          comparator: Compat.yes,
          outcome: Compat.yes,
          followUp: Compat.unclear,
          measure: Compat.yes,
          comment: tr('Durées de suivi très variables (non homogénéisées) ; latitude ${lat.toStringAsFixed(0)}°.', 'Highly variable follow-up durations (not harmonized); latitude ${lat.toStringAsFixed(0)}°.'),
        )));
  }
  final journal = <JournalEntry>[
    _entry(1, metaAnalysis(studies, const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.reml)),
        note: tr('Analyse principale : RR, effets aléatoires REML.', 'Main analysis: RR, REML random effects.')),
    _entry(2, metaAnalysis(studies, const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.reml, knha: true)),
        note: tr('Sensibilité : IC de Hartung-Knapp.', 'Sensitivity: Hartung-Knapp CI.')),
    _entry(3, metaAnalysis(studies, const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.fixed, mantelHaenszelFixed: true)),
        note: tr("Sensibilité : effet fixe de Mantel-Haenszel (montré pour comparaison ; inadapté vu l'hétérogénéité).", 'Sensitivity: Mantel-Haenszel fixed effect (shown for comparison; unsuitable given the heterogeneity).')),
    _entry(4, metaRegression(studies, const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.reml), const [Moderator('latitude')]),
        note: tr("Méta-régression prévue a priori : la latitude (exposition aux mycobactéries environnementales) explique-t-elle l'hétérogénéité ?", 'Meta-regression planned a priori: does latitude (exposure to environmental mycobacteria) explain the heterogeneity?')),
  ];
  return Project(
    id: 'demo-meta',
    title: tr('Démo 2 — Métaanalyse du vaccin BCG (forest plot)', 'Demo 2 — Meta-analysis of the BCG vaccine (forest plot)'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: tr(
        "Données PUBLIÉES et publiques (13 essais, Colditz et al. 1994, jeu dat.bcg du paquet R metafor). La grille de compatibilité a été remplie à titre d'exemple ; elle n'est pas une expertise de ces essais.",
        'PUBLISHED, public data (13 trials, Colditz et al. 1994, dat.bcg dataset of the R package metafor). The compatibility grid was filled in as an example; it is not an expert appraisal of these trials.'),
    dataset: ds,
    studies: studies,
    question: ResearchQuestion(
      text: tr("Le vaccin BCG réduit-il le risque de tuberculose par rapport à l'absence de vaccination ?", 'Does the BCG vaccine reduce the risk of tuberculosis compared with no vaccination?'),
      population: tr('Participants des essais de vaccination BCG', 'Participants in BCG vaccination trials'),
      exposure: tr('Vaccination BCG', 'BCG vaccination'),
      comparator: tr('Absence de vaccination', 'No vaccination'),
      outcome: tr('Tuberculose diagnostiquée pendant le suivi', 'Tuberculosis diagnosed during follow-up'),
      horizon: tr('Durée de suivi de chaque essai', 'Follow-up duration of each trial'),
      design: StudyDesign.systematicReview,
      objective: StudyObjective.explanatory,
      outcomeType: OutcomeType.binary,
      dataLevel: DataLevel.aggregatedStudies,
    ),
    analysisPlan: tr(
        "RR par étude ; combinaison par effets aléatoires (REML), intervalle de prédiction ; sensibilité : Hartung-Knapp, retrait d'une étude à la fois, effet fixe de Mantel-Haenszel ; sous-groupes prévus a priori : mode d'allocation ; méta-régression prévue a priori sur la latitude.",
        'RR per study; pooling by random effects (REML), prediction interval; sensitivity: Hartung-Knapp, leaving one study out at a time, Mantel-Haenszel fixed effect; subgroups planned a priori: allocation method; meta-regression planned a priori on latitude.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit.
    resultsText: tr(
        "Le BCG réduit le risque de tuberculose d'environ moitié. L'hétérogénéité était importante. Le résultat est hautement significatif et démontre que le vaccin est efficace partout. Le biais de publication a été exclu par le test d'Egger.",
        "BCG reduces the risk of tuberculosis by about half. Heterogeneity was considerable. The result is highly significant and demonstrates that the vaccine is effective everywhere. Publication bias was ruled out by Egger's test."),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 3 : modèle de risque cardiométabolique, validation interne.
Project buildDemoPrediction(String csv, {int bootstrap = 200, String? externalCsv}) {
  final ds = parseCsv(csv, source: tr('cardiometabolique_simule.csv (simulé)', 'cardiometabolique_simule.csv (simulated)')).dataset;
  final spec = PredictionSpec(
    targetPopulation: tr('Adultes de 30 à 70 ans vus en soins primaires, sans maladie cardiométabolique connue (population simulée)',
        'Adults aged 30 to 70 seen in primary care, without known cardiometabolic disease (simulated population)'),
    outcome: 'evenement_5ans',
    eventLevel: '1',
    horizon: tr('5 ans', '5 years'),
    intendedUse: tr('Repérer les personnes à orienter vers un bilan cardiométabolique approfondi', 'Identify people to refer for an in-depth cardiometabolic work-up'),
    setting: tr('Soins primaires', 'Primary care'),
    predictors: const [
      TermSpec('age', transform: TermTransform.perUnit, unitStep: 10),
      TermSpec('sexe', categorical: true, reference: 'F'),
      TermSpec('tour_taille', transform: TermTransform.perUnit, unitStep: 10),
      TermSpec('pas', transform: TermTransform.perUnit, unitStep: 10),
      TermSpec('glycemie'),
      TermSpec('hdl'),
      TermSpec('tabac', categorical: true, reference: 'non'),
      TermSpec('atcd_familial', categorical: true, reference: 'non'),
    ],
    referencePredictors: const [TermSpec('age', transform: TermTransform.perUnit, unitStep: 10), TermSpec('sexe', categorical: true, reference: 'F')],
    referenceName: tr('Âge + sexe', 'Age + sex'),
  );
  final r = developPredictionModel(ds, spec, bootstrap: bootstrap, seed: 20261010);
  return Project(
    id: 'demo-prediction',
    title: tr('Démo 3 — Modèle de risque cardiométabolique (validation interne)', 'Demo 3 — Cardiometabolic risk model (internal validation)'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: simulatedNotice,
    dataset: ds,
    predictionSpec: spec,
    question: ResearchQuestion(
      text: tr("Peut-on estimer le risque à 5 ans d'événement cardiométabolique chez l'adulte en soins primaires à partir de données simples ?",
          'Can the 5-year risk of a cardiometabolic event in adults in primary care be estimated from simple data?'),
      population: tr('Adultes de 30 à 70 ans en soins primaires', 'Adults aged 30 to 70 in primary care'),
      outcome: tr('Événement cardiométabolique à 5 ans', 'Cardiometabolic event at 5 years'),
      horizon: tr('5 ans', '5 years'),
      design: StudyDesign.cohort,
      objective: StudyObjective.predictive,
      outcomeType: OutcomeType.binary,
      dataLevel: DataLevel.individual,
      pairing: Pairing.independent,
    ),
    analysisPlan: tr(
        'Régression logistique, 8 prédicteurs pré-spécifiés (pas de sélection). Cas complets (documentés). Validation interne par bootstrap (200 répliques, graine 20261010). Discrimination (AUC, DeLong), calibration (pente, intercept, courbe), Brier, courbe de décision 1–50 %. Comparaison au modèle âge + sexe. Validation externe sur une cohorte indépendante (coefficients non réestimés), avec recalibration proposée si nécessaire.',
        'Logistic regression, 8 pre-specified predictors (no selection). Complete cases (documented). Internal validation by bootstrap (200 replicates, seed 20261010). Discrimination (AUC, DeLong), calibration (slope, intercept, curve), Brier, decision curve 1–50%. Comparison with the age + sex model. External validation on an independent cohort (coefficients not re-estimated), with recalibration proposed if needed.'),
    journal: [
      _entry(1, r, data: ds),
      if (externalCsv != null)
        () {
          final ext = parseCsv(externalCsv, source: tr('cardiometabolique_externe_simule.csv (simulé, cohorte indépendante)', 'cardiometabolique_externe_simule.csv (simulated, independent cohort)')).dataset;
          return _entry(2, externalValidation(ext, ModelEquation.fromDevelopment(r, name: tr('Modèle cardiométabolique (démo 3)', 'Cardiometabolic model (demo 3)')),
                  population: tr('Cohorte externe simulée : adultes de 40 à 78 ans, autre centre', 'Simulated external cohort: adults aged 40 to 78, another centre')),
              data: ext, note: tr('Validation externe : coefficients appliqués sans réestimation à une cohorte indépendante.', 'External validation: coefficients applied without re-estimation to an independent cohort.'));
        }(),
    ],
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit.
    resultsText: tr(
        "Le modèle présente une excellente discrimination (AUC ${fmtFixed(r.statistics["auc_apparent"]!, 2)}) et est validé. Il est donc utilisable en pratique clinique pour le dépistage. Le tour de taille augmente le risque d'événement. La calibration était satisfaisante.",
        'The model shows excellent discrimination (AUC ${fmtFixed(r.statistics["auc_apparent"]!, 2)}) and is validated. It is therefore usable in clinical practice for screening. Waist circumference increases the risk of the event. Calibration was satisfactory.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Série de dilutions du test moléculaire (UFC/mL ; détectés sur 20 réplicats), simulée (validation/r/24_demo_tb.R).
const demoTbLodConcentrations = <double>[5, 10, 20, 40, 80, 160];
const demoTbLodDetected = [4, 9, 14, 18, 20, 20];

/// Démonstration 4 : tuberculose résistante à la rifampicine — que vaut le génotypage moléculaire ?
/// [csv] : isolats ; [referencesFasta] : bibliothèque d'identification ; [isolateFasta] : séquence à identifier.
Project buildDemoTb(String csv, String referencesFasta, String isolateFasta) {
  final ds = parseCsv(csv, source: tr('tb_rifampicine_simule.csv (simulé)', 'tb_rifampicine_simule.csv (simulated)')).dataset;
  final journal = <JournalEntry>[];
  const three = ['rpoB_S450L', 'rpoB_H445Y', 'rpoB_D435V'];
  final c3 = mutationPhenotypeConcordance(ds, 'rifampicine', 'R', three);
  journal.add(_entry(1, c3, data: ds,
      note: tr('Référence : antibiogramme phénotypique (MGIT). Panel des trois mutations à haut niveau de confiance ; échecs d\'amplification exclus, non imputés.',
          'Reference: phenotypic susceptibility testing (MGIT). Panel of the three high-confidence mutations; amplification failures excluded, not imputed.')));
  final c4 = mutationPhenotypeConcordance(ds, 'rifampicine', 'R', [...three, 'rpoB_L430P']);
  journal.add(_entry(2, c4, data: ds,
      note: tr('Ajout de rpoB L430P, mutation « limite » souvent classée sensible en MGIT : la spécificité baisse.',
          'Adding rpoB L430P, a "borderline" mutation often classified susceptible by MGIT: specificity drops.')));
  journal.add(_entry(3, typeDiversity(ds, 'lignee'), data: ds,
      note: tr('Pouvoir discriminant du typage par lignée (Hunter-Gaston) : insuffisant pour une enquête de transmission.',
          'Discriminatory power of lineage typing (Hunter-Gaston): insufficient for a transmission investigation.')));
  final rif = ds.text('rifampicine'), lin = ds.text('lignee'), cen = ds.text('centre');
  int n2(bool Function(int) f) => [for (var i = 0; i < ds.rowCount; i++) if (f(i)) i].length;
  journal.add(_entry(4, twoByTwo(n2((i) => lin[i] == 'L2' && rif[i] == 'R'), n2((i) => lin[i] == 'L2' && rif[i] == 'S'),
      n2((i) => lin[i] != 'L2' && rif[i] == 'R'), n2((i) => lin[i] != 'L2' && rif[i] == 'S'),
      design: StudyDesign.crossSectional, exposure: tr('Lignée L2', 'Lineage L2'), outcome: tr('Résistance à la rifampicine', 'Rifampicin resistance')), data: ds,
      note: tr('Association transversale : la lignée est un marqueur, pas une cause démontrée.', 'Cross-sectional association: lineage is a marker, not a demonstrated cause.')));
  final centres = (cen.whereType<String>().toSet().toList())..sort();
  journal.add(_entry(5, chiSquareRxC([
    for (final c in centres) [n2((i) => cen[i] == c && rif[i] == 'R'), n2((i) => cen[i] == c && rif[i] == 'S')]
  ], rowNames: centres, colNames: const ['R', 'S']), data: ds));
  journal.add(_entry(6, qpcrLimitOfDetection(demoTbLodConcentrations, demoTbLodDetected, List.filled(6, 20)),
      note: tr('Limite de détection du test moléculaire : 20 réplicats par niveau (CLSI EP17).', 'Limit of detection of the molecular test: 20 replicates per level (CLSI EP17).')));
  journal.add(_entry(7, localAlignmentSearch(isolateFasta, parseFasta(referencesFasta), queryName: 'TB-X'),
      note: tr('Identification de l\'isolat TB-X contre une bibliothèque locale de séquences fictives.', 'Identification of isolate TB-X against a local library of fictitious sequences.')));
  final se = c3.estimates.first.value;
  return Project(
    id: 'demo-tb',
    title: tr('Démo 4 — Tuberculose résistante à la rifampicine : que vaut le génotypage ?', 'Demo 4 — Rifampicin-resistant tuberculosis: what is genotyping worth?'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: simulatedNotice,
    dataset: ds,
    question: ResearchQuestion(
      text: tr(
          'Chez les isolats de Mycobacterium tuberculosis, la détection des mutations rpoB prédit-elle la résistance phénotypique à la rifampicine (sensibilité, spécificité, concordance) ? Accessoirement : limite de détection du test, typage par lignée, identification d\'un isolat par séquençage.',
          'In Mycobacterium tuberculosis isolates, does detection of rpoB mutations predict phenotypic rifampicin resistance (sensitivity, specificity, agreement)? Secondarily: limit of detection of the test, lineage typing, identification of an isolate by sequencing.'),
      population: tr('Isolats consécutifs de 3 centres (population simulée)', 'Consecutive isolates from 3 centres (simulated population)'),
      exposure: tr('Mutations rpoB détectées par le test moléculaire', 'rpoB mutations detected by the molecular test'),
      comparator: tr('Antibiogramme phénotypique MGIT (référence)', 'Phenotypic MGIT susceptibility testing (reference)'),
      outcome: tr('Résistance phénotypique à la rifampicine', 'Phenotypic rifampicin resistance'),
      horizon: tr('Au diagnostic', 'At diagnosis'),
      design: StudyDesign.diagnosticAccuracy,
      objective: StudyObjective.diagnostic,
      outcomeType: OutcomeType.binary,
      exposureType: ExposureType.binary,
      pairing: Pairing.independent,
      dataLevel: DataLevel.individual,
      referenceStandardAvailable: true,
      expectedEvents: 70,
    ),
    analysisPlan: tr(
        '1) Concordance du panel de 3 mutations rpoB avec l\'antibiogramme : Se, Sp (Wilson), kappa ; échecs d\'amplification exclus et décomptés. 2) Même analyse en ajoutant rpoB L430P. 3) Pouvoir discriminant des lignées (Hunter-Gaston). 4) Lignée L2 et résistance (tableau 2 × 2, Fisher). 5) Résistance selon le centre (χ²). 6) Limite de détection du test (probit, LOD95). 7) Identification de l\'isolat TB-X par alignement local (bibliothèque locale).',
        '1) Agreement of the 3-mutation rpoB panel with susceptibility testing: Se, Sp (Wilson), kappa; amplification failures excluded and counted. 2) Same analysis adding rpoB L430P. 3) Discriminatory power of lineages (Hunter-Gaston). 4) Lineage L2 and resistance (2 × 2 table, Fisher). 5) Resistance by centre (χ²). 6) Limit of detection of the test (probit, LOD95). 7) Identification of isolate TB-X by local alignment (local library).'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit (et, pour certaines, par l'enseignant).
    resultsText: tr(
        'Le panel moléculaire avait une sensibilité de ${fmtFixed(se * 100, 5)} %. L\'absence de mutation permet donc d\'exclure la résistance à la rifampicine. La lignée L2 entraîne la résistance à la rifampicine. La résistance ne variait pas selon le centre (p > 0,05) : il n\'y a aucune différence entre centres. L\'isolat TB-X est Mycobacterium tuberculosis. Une analyse de sensibilité a confirmé ces résultats.',
        'The molecular panel had a sensitivity of ${fmtFixed(se * 100, 5)}%. The absence of mutation therefore rules out rifampicin resistance. Lineage L2 causes rifampicin resistance. Resistance did not vary by centre (p > 0.05): there is no difference between centres. Isolate TB-X is Mycobacterium tuberculosis. A sensitivity analysis confirmed these results.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 5 : étude d'association cas-témoins pangénomique (simulée), de bout en bout.
/// [bed], [bim], [fam] : génotypes PLINK ; [covariatesCsv] : « id,age ».
Project buildDemoGwas(Uint8List bed, String bim, String fam, String covariatesCsv) {
  final g = parsePlinkBed(bed, bim, fam, source: tr('gwas_simule.bed/.bim/.fam (simulé)', 'gwas_simule.bed/.bim/.fam (simulated)'));
  final journal = <JournalEntry>[];
  final qc = genotypeQc(g);
  journal.add(_entry(1, qc.result, note: tr('Seuils fixés dans le plan d\'analyse avant de voir les résultats.', 'Thresholds fixed in the analysis plan before seeing the results.')));
  final kin = genotypeKinship(qc.cleaned);
  journal.add(_entry(2, kin.result, note: tr('Doublons et apparentés écartés avant l\'ACP et l\'association.', 'Duplicates and relatives removed before PCA and association.')));
  final removed = kin.removed.toSet();
  final u = qc.cleaned.subset(sampleIdx: [for (var i = 0; i < qc.cleaned.sampleCount; i++) if (!removed.contains(i)) i],
      notes: [tr('${removed.length} sujet(s) apparenté(s) écarté(s).', '${removed.length} related subject(s) removed.')]);
  final pca = genotypePca(u);
  journal.add(_entry(3, pca.result, note: tr('ACP sur les sujets non apparentés, après élagage LD.', 'PCA on unrelated subjects, after LD pruning.')));
  final cov = parseCsv(covariatesCsv).dataset;
  final age = {for (var i = 0; i < cov.rowCount; i++) cov.cell(i, 'id')!: cov.cell(i, 'age')!};
  final ds = genotypeDataset(u, covariates: {'age': age, ...pca.covariates(2)});
  final snps = ds.names.sublist(ds.names.length - u.variantCount);
  final positions = {for (var j = 0; j < snps.length; j++) snps[j]: (u.variants[j].chrom, u.variants[j].pos)};
  final status = tr('statut', 'status'), caseL = tr('cas', 'case'), sex = tr('sexe', 'sex');
  final raw = snpScan(ds, snps, status, caseL, positions: positions);
  journal.add(_entry(4, raw, note: tr('Balayage brut, montré pour l\'inflation λ (confusion par l\'ascendance).', 'Raw scan, shown for the inflation λ (confounding by ancestry).')));
  final adj = snpScan(ds, snps, status, caseL, positions: positions,
      covariates: [TermSpec(sex, categorical: true, reference: 'H'), const TermSpec('age'), const TermSpec('PC1'), const TermSpec('PC2')]);
  journal.add(_entry(5, adj, note: tr('Analyse principale : ajustée sur le sexe, l\'âge et les 2 premières composantes principales.', 'Main analysis: adjusted for sex, age and the first 2 principal components.')));
  // Statistiques conservées pour les 500 plus petits p (balayage étendu) : suffisent au classement.
  final pAdj = {for (final sn in snps) if (adj.statistics['p_$sn'] != null) sn: adj.statistics['p_$sn']!};
  final ranked = [...pAdj.keys]..sort((a, b) => pAdj[a]!.compareTo(pAdj[b]!));
  final top = ranked.first;
  journal.add(_entry(6, snpAssociation(ds, top, status, caseL), note: tr('Détail génotypique du variant le plus associé.', 'Genotype detail of the most associated variant.')));
  // Table du projet : covariables et les 20 variants les plus associés (la matrice complète reste dans les fichiers PLINK).
  final keepCols = ['id', status, sex, 'age', 'PC1', 'PC2', ...ranked.take(20)];
  final slim = Dataset.fromColumns({for (final c in keepCols) c: ds.text(c)}, source: tr('gwas_simule (sujets retenus, 20 variants les plus associés)', 'gwas_simule (retained subjects, 20 most associated variants)'));
  final orTop = adj.estimates.firstWhere((e) => e.label.endsWith(top)).value;
  final second = ranked[2];
  return Project(
    id: 'demo-gwas',
    title: tr('Démo 5 — Étude d\'association cas-témoins pangénomique', 'Demo 5 — Genome-wide case-control association study'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: simulatedNotice,
    dataset: slim,
    question: ResearchQuestion(
      text: tr('Des variants génétiques fréquents sont-ils associés à la maladie, indépendamment de l\'ascendance, du sexe et de l\'âge ?',
          'Are common genetic variants associated with the disease, independently of ancestry, sex and age?'),
      population: tr('Cas et témoins génotypés sur puce (population simulée, deux ascendances)', 'Cases and controls genotyped on an array (simulated population, two ancestries)'),
      exposure: tr('Génotype de chaque variant (modèle additif)', 'Genotype of each variant (additive model)'),
      comparator: tr('Témoins', 'Controls'),
      outcome: tr('Statut cas/témoin', 'Case/control status'),
      horizon: tr('Au recrutement', 'At recruitment'),
      design: StudyDesign.caseControl,
      objective: StudyObjective.explanatory,
      outcomeType: OutcomeType.binary,
      exposureType: ExposureType.binary,
      pairing: Pairing.independent,
      dataLevel: DataLevel.individual,
      needsAdjustment: true,
      expectedEvents: 200,
    ),
    analysisPlan: tr(
        '1) Contrôle de qualité : sujets (taux d\'appel ≥ 95 %, hétérozygotie à 3 ET), variants (taux d\'appel ≥ 95 %, MAF ≥ 1 %, HWE p ≥ 10⁻⁶ chez les témoins). 2) Parenté KING-robust : un sujet par paire au-delà du 2e degré. 3) ACP sur les non-apparentés après élagage LD. 4) Balayage logistique additif brut (inflation λ). 5) Analyse principale ajustée sur sexe, âge, CP1–CP2 ; seuil pangénomique 5 × 10⁻⁸, suggestif 10⁻⁵. 6) Détail génotypique du meilleur signal ; réplication indépendante nécessaire.',
        '1) Quality control: subjects (call rate ≥ 95%, heterozygosity within 3 SD), variants (call rate ≥ 95%, MAF ≥ 1%, HWE p ≥ 10⁻⁶ in controls). 2) KING-robust kinship: one subject per pair beyond 2nd degree. 3) PCA on unrelated subjects after LD pruning. 4) Raw additive logistic scan (inflation λ). 5) Main analysis adjusted for sex, age, PC1–PC2; genome-wide threshold 5 × 10⁻⁸, suggestive 10⁻⁵. 6) Genotype detail of the best signal; independent replication needed.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit (et, pour certaines, par l'enseignant).
    resultsText: tr(
        'Le variant $top cause la maladie : le risque est multiplié par ${fmtFixed(orTop, 5)} chez les porteurs de chaque allèle. Le variant $second est non significatif après correction, il n\'a donc aucun effet. Le λ de 1,47 du balayage brut traduit un fort signal polygénique. Une analyse de sensibilité a confirmé ces résultats.',
        'Variant $top causes the disease: the risk is multiplied by ${fmtFixed(orTop, 5)} in carriers of each allele. Variant $second is not significant after correction, so it has no effect. The λ of 1.47 of the raw scan reflects a strong polygenic signal. A sensitivity analysis confirmed these results.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 6 : polygénie ou confusion ? Régression LD score et corrélation génétique (données simulées en blocs de
/// DL, deux sous-populations). L'hypertension (statut du .fam) est confondue par l'ascendance ; diabète et coronaropathie
/// (fichier de traits) partagent une base génétique simulée (rg = 0,7).
Project buildDemoPolygenic(Uint8List bed, String bim, String fam, String traitsCsv) {
  final g = parsePlinkBed(bed, bim, fam, source: tr('genotypes_dl_simule.bed/.bim/.fam (simulé)', 'genotypes_dl_simule.bed/.bim/.fam (simulated)'));
  final journal = <JournalEntry>[];
  final qc = genotypeQc(g);
  journal.add(_entry(1, qc.result, note: tr('Seuils fixés dans le plan d\'analyse.', 'Thresholds fixed in the analysis plan.')));
  final u = qc.cleaned;
  final pca = genotypePca(u);
  journal.add(_entry(2, pca.result, note: tr('Ascendance résumée par les composantes principales.', 'Ancestry summarized by the principal components.')));
  final traits = parseCsv(traitsCsv).dataset;
  final hta = tr('hypertension', 'hypertension'), diab = tr('diabete', 'diabetes'), coro = tr('coronaropathie', 'coronary_disease');
  final yes = tr('oui', 'yes'), no = tr('non', 'no');
  String yn(String? v) => v == 'oui' ? yes : no;
  final cov = <String, Map<String, String>>{
    hta: {for (var i = 0; i < u.sampleCount; i++) if (u.phenotype[i] != null) u.samples[i]: u.phenotype[i] == 2 ? yes : no},
    diab: {for (var i = 0; i < traits.rowCount; i++) traits.cell(i, 'id')!: yn(traits.cell(i, 'diabete'))},
    coro: {for (var i = 0; i < traits.rowCount; i++) traits.cell(i, 'id')!: yn(traits.cell(i, 'coronaropathie'))},
    ...pca.covariates(2),
  };
  final ds = genotypeDataset(u, covariates: cov);
  final snps = ds.names.sublist(ds.names.length - u.variantCount);
  final positions = {for (var j = 0; j < snps.length; j++) snps[j]: (u.variants[j].chrom, u.variants[j].pos)};
  final sex = tr('sexe', 'sex');
  final sexTerm = TermSpec(sex, categorical: true, reference: 'H');
  final adjusted = [sexTerm, const TermSpec('PC1'), const TermSpec('PC2')];
  final ell = ldScores(u);
  final m = ell.where((x) => x != null).length;
  final n = u.sampleCount;
  final parsed = <String, SnpData>{};
  (AnalysisResult, List<double>) scan(String outcome, List<TermSpec> terms) {
    final z = <double>[];
    final r = snpScan(ds, snps, outcome, yes, positions: positions, covariates: terms, zOut: z, parsedSnps: parsed);
    return (r, z);
  }

  final (hRaw, zRaw) = scan(hta, [sexTerm]);
  journal.add(_entry(3, hRaw, note: tr('Hypertension, ajustée sur le sexe seulement : λ à interpréter.', 'Hypertension, adjusted for sex only: λ to be interpreted.')));
  final ldRaw = ldscRegression([for (final z in zRaw) z * z], ell, n: n, m: m, scanName: tr('l\'hypertension (sexe)', 'hypertension (sex)'));
  journal.add(_entry(4, ldRaw.result, note: tr('Polygénie ou confusion ? Intercept de la régression LD score.', 'Polygenicity or confounding? LD score regression intercept.')));
  final (hAdj, zAdj) = scan(hta, adjusted);
  journal.add(_entry(5, hAdj, note: tr('Hypertension, ajustée sur le sexe et CP1–CP2.', 'Hypertension, adjusted for sex and PC1–PC2.')));
  final ldAdj = ldscRegression([for (final z in zAdj) z * z], ell, n: n, m: m, scanName: tr('l\'hypertension (sexe, CP1, CP2)', 'hypertension (sex, PC1, PC2)'));
  journal.add(_entry(6, ldAdj.result, note: tr('Intercept après ajustement sur l\'ascendance.', 'Intercept after adjustment for ancestry.')));
  final (dScan, zD) = scan(diab, adjusted);
  journal.add(_entry(7, dScan, note: tr('Diabète, ajusté sur le sexe et CP1–CP2.', 'Diabetes, adjusted for sex and PC1–PC2.')));
  final (cScan, zC) = scan(coro, adjusted);
  journal.add(_entry(8, cScan, note: tr('Coronaropathie, ajustée sur le sexe et CP1–CP2.', 'Coronary disease, adjusted for sex and PC1–PC2.')));
  final rg = geneticCorrelation(zD, zC, ell, n: n, m: m, trait1: diab, trait2: coro);
  journal.add(_entry(9, rg.result, note: tr('Base génétique commune au diabète et à la coronaropathie.', 'Genetic basis shared by diabetes and coronary disease.')));
  final slim = Dataset.fromColumns({for (final c in ['id', sex, hta, diab, coro, 'PC1', 'PC2']) c: ds.text(c)},
      source: tr('genotypes_dl_simule (sujets retenus ; génotypes dans les fichiers PLINK)', 'genotypes_dl_simule (retained subjects; genotypes in the PLINK files)'));
  final lambdaRaw = hRaw.statistics['lambda_gc']!;
  String f2(double v) => fmtFixed(v, 2);
  return Project(
    id: 'demo-polygenic',
    title: tr('Démo 6 — Polygénie ou confusion ? Régression LD score et corrélation génétique', 'Demo 6 — Polygenicity or confounding? LD score regression and genetic correlation'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: simulatedNotice,
    dataset: slim,
    question: ResearchQuestion(
      text: tr('L\'inflation des statistiques d\'association traduit-elle une polygénie ou une confusion par l\'ascendance ? Le diabète et la coronaropathie partagent-ils une base génétique ?',
          'Does the inflation of the association statistics reflect polygenicity or confounding by ancestry? Do diabetes and coronary disease share a genetic basis?'),
      population: tr('Cohorte génotypée sur puce, deux ascendances (simulée)', 'Cohort genotyped on an array, two ancestries (simulated)'),
      exposure: tr('Génotypes de 3 000 variants (modèle additif)', 'Genotypes of 3,000 variants (additive model)'),
      comparator: tr('Sujets indemnes', 'Unaffected subjects'),
      outcome: tr('Hypertension ; diabète ; coronaropathie', 'Hypertension; diabetes; coronary disease'),
      horizon: tr('Au recrutement', 'At recruitment'),
      design: StudyDesign.crossSectional,
      objective: StudyObjective.explanatory,
      outcomeType: OutcomeType.binary,
      exposureType: ExposureType.binary,
      pairing: Pairing.independent,
      dataLevel: DataLevel.individual,
      needsAdjustment: true,
      expectedEvents: 400,
    ),
    analysisPlan: tr(
        '1) Contrôle de qualité. 2) ACP (ascendance). 3) Balayage logistique de l\'hypertension ajusté sur le sexe ; inflation λ. 4) Régression LD score : intercept (confusion) et pente (polygénie). 5–6) Même analyse ajustée sur CP1–CP2. 7–8) Balayages du diabète et de la coronaropathie ajustés sur le sexe et CP1–CP2. 9) Corrélation génétique par régression LD score croisée. Scores LD calculés dans l\'échantillon ; 3 000 variants : estimations indicatives.',
        '1) Quality control. 2) PCA (ancestry). 3) Logistic scan of hypertension adjusted for sex; inflation λ. 4) LD score regression: intercept (confounding) and slope (polygenicity). 5–6) Same analysis adjusted for PC1–PC2. 7–8) Scans of diabetes and coronary disease adjusted for sex and PC1–PC2. 9) Genetic correlation by cross-trait LD score regression. In-sample LD scores; 3,000 variants: indicative estimates.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit (et, pour certaines, par l'enseignant).
    resultsText: tr(
        'Le λ de ${f2(lambdaRaw)} du balayage de l\'hypertension traduit un fort signal polygénique. Après ajustement, l\'héritabilité h²_SNP de l\'hypertension vaut ${fmtFixed(ldAdj.h2, 5)}. La corrélation génétique entre diabète et coronaropathie (rg = ${f2(rg.rg)}) prouve que le diabète cause la coronaropathie, et les deux héritabilités sont estimées avec précision. Une analyse de sensibilité a confirmé ces résultats.',
        'The λ of ${f2(lambdaRaw)} of the hypertension scan reflects a strong polygenic signal. After adjustment, the h²_SNP heritability of hypertension is ${fmtFixed(ldAdj.h2, 5)}. The genetic correlation between diabetes and coronary disease (rg = ${f2(rg.rg)}) proves that diabetes causes coronary disease, and both heritabilities are precisely estimated. A sensitivity analysis confirmed these results.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 7 : randomisation mendélienne à partir de statistiques publiées (28 variants ; LDL, HDL, triglycérides
/// et maladie coronarienne ; jeu d'exemple du paquet R MendelianRandomization, Waterworth et al. 2010).
Project buildDemoMr(String csv) {
  final ds = parseCsv(csv, source: tr('mr_ldl_chd.csv (statistiques publiées)', 'mr_ldl_chd.csv (published statistics)')).dataset;
  List<double> col(String c) => [for (var i = 0; i < ds.rowCount; i++) double.parse(ds.cell(i, c)!)];
  final names = [for (var i = 0; i < ds.rowCount; i++) ds.cell(i, 'variant')!];
  final by = col('beta_chd'), byse = col('se_chd');
  final chd = tr('maladie coronarienne', 'coronary heart disease');
  final ldlName = tr('LDL-cholestérol (mmol/L)', 'LDL cholesterol (mmol/L)'), hdlName = tr('HDL-cholestérol (mmol/L)', 'HDL cholesterol (mmol/L)'),
      tgName = tr('triglycérides (mmol/L)', 'triglycerides (mmol/L)');
  final journal = <JournalEntry>[];
  final ldl = mendelianRandomization(col('beta_ldl'), col('se_ldl'), by, byse, names: names, exposure: ldlName, outcome: chd);
  journal.add(_entry(1, ldl.result, data: ds, note: tr('Analyse principale : LDL-cholestérol, quatre méthodes et leave-one-out.', 'Main analysis: LDL cholesterol, four methods and leave-one-out.')));
  final hdl = mendelianRandomization(col('beta_hdl'), col('se_hdl'), by, byse, names: names, exposure: hdlName, outcome: chd);
  journal.add(_entry(2, hdl.result, data: ds, note: tr('HDL-cholestérol seul : les mêmes variants agissent aussi sur le LDL et les triglycérides.', 'HDL cholesterol alone: the same variants also act on LDL and triglycerides.')));
  final tg = mendelianRandomization(col('beta_tg'), col('se_tg'), by, byse, names: names, exposure: tgName, outcome: chd);
  journal.add(_entry(3, tg.result, data: ds, note: tr('Triglycérides seuls.', 'Triglycerides alone.')));
  final mv = multivariableMendelianRandomization([col('beta_ldl'), col('beta_hdl'), col('beta_tg')], [col('se_ldl'), col('se_hdl'), col('se_tg')], by, byse,
      exposures: [ldlName, hdlName, tgName], outcome: chd, names: names);
  journal.add(_entry(4, mv.result, data: ds, note: tr('Effets directs de chaque lipide, à niveau égal des deux autres.', 'Direct effect of each lipid, holding the other two fixed.')));
  final orLdl = math.exp(ldl.ivw.estimate);
  return Project(
    id: 'demo-mr',
    title: tr('Démo 7 — Causalité : LDL, HDL et maladie coronarienne (randomisation mendélienne)', 'Demo 7 — Causality: LDL, HDL and coronary disease (Mendelian randomization)'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: tr('Statistiques résumées PUBLIÉES (28 variants, Waterworth et al. 2010, jeu d\'exemple du paquet R MendelianRandomization) : aucune donnée individuelle.',
        'PUBLISHED summary statistics (28 variants, Waterworth et al. 2010, example data of the R package MendelianRandomization): no individual data.'),
    dataset: ds,
    question: ResearchQuestion(
      text: tr('Le LDL-cholestérol est-il une cause de la maladie coronarienne ? Le HDL-cholestérol en protège-t-il ?',
          'Is LDL cholesterol a cause of coronary heart disease? Does HDL cholesterol protect against it?'),
      population: tr('Consortiums de génétique des lipides et de la maladie coronarienne (ascendance européenne)', 'Lipid and coronary disease genetics consortia (European ancestry)'),
      exposure: tr('Taux de lipides prédits par 28 variants (instruments)', 'Lipid levels predicted by 28 variants (instruments)'),
      comparator: tr('Porteurs de moins d\'allèles augmentant le lipide', 'Carriers of fewer lipid-raising alleles'),
      outcome: tr('Maladie coronarienne (log-odds)', 'Coronary heart disease (log-odds)'),
      horizon: tr('Exposition génétique sur la vie entière', 'Lifelong genetic exposure'),
      design: StudyDesign.caseControl,
      objective: StudyObjective.explanatory,
      outcomeType: OutcomeType.binary,
      exposureType: ExposureType.continuous,
      pairing: Pairing.independent,
      dataLevel: DataLevel.unknown, // statistiques résumées de GWAS : ni données individuelles ni métaanalyse d'études
      needsAdjustment: false,
      expectedEvents: 0,
    ),
    analysisPlan: tr(
        '1) LDL-cholestérol : IVW (effets aléatoires), MR-Egger, médiane et mode pondérés, leave-one-out ; force des instruments (F), hétérogénéité, pléiotropie (intercept). 2–3) HDL et triglycérides séparément. 4) MR multivariée des trois lipides (effets directs). Conclusion causale seulement si les méthodes concordent et que les hypothèses (instruments valides, pas de pléiotropie horizontale) sont discutées.',
        '1) LDL cholesterol: IVW (random effects), MR-Egger, weighted median and mode, leave-one-out; instrument strength (F), heterogeneity, pleiotropy (intercept). 2–3) HDL and triglycerides separately. 4) Multivariable MR of the three lipids (direct effects). Causal conclusion only if methods agree and the assumptions (valid instruments, no horizontal pleiotropy) are discussed.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit (et, pour certaines, par l'enseignant).
    resultsText: tr(
        'Le LDL-cholestérol cause la maladie coronarienne : chaque mmol/L multiplie le risque par ${fmtFixed(orLdl, 4)} (IVW). Le HDL-cholestérol protège contre la maladie coronarienne (MR univariée, ${fmtP(hdl.ivw.p)}) : augmenter le HDL par un médicament réduira donc les infarctus. Les analyses de sensibilité ont confirmé ces résultats.',
        'LDL cholesterol causes coronary heart disease: each mmol/L multiplies the risk by ${fmtFixed(orLdl, 4)} (IVW). HDL cholesterol protects against coronary heart disease (univariable MR, ${fmtP(hdl.ivw.p)}): raising HDL with a drug will therefore reduce heart attacks. The sensitivity analyses confirmed these results.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}

/// Démonstration 8 : survie avancée — rechute avec décès concurrent (données simulées) et biais du temps immortel
/// (greffe cardiaque de Stanford, données réelles embarquées).
Project buildDemoSurvivalAdvanced(String csv) {
  final ds = parseCsv(csv, source: tr('risques_concurrents_simule.csv (simulé)', 'risques_concurrents_simule.csv (simulated)')).dataset;
  final journal = <JournalEntry>[];
  // 1) Erreur fréquente : Kaplan-Meier de la rechute, décès traités comme des censures.
  final naive = survivalAnalysis(ds.numeric('mois'), [for (final v in ds.text('statut')) v == null ? null : (v == 'rechute' ? '1' : '0')], '1',
      groupRaw: ds.text('bras'), horizon: 24, timeUnit: 'mois', groupName: 'bras');
  journal.add(_entry(1, naive, data: ds, note: tr('Approche naïve : décès comptés comme censures — à comparer à l\'incidence cumulée.', 'Naive approach: deaths counted as censoring — to be compared with the cumulative incidence.')));
  // 2) Incidence cumulée d'Aalen-Johansen, test de Gray, sHR du bras.
  final cif = competingRisksAnalysis(ds.numeric('mois'), ds.text('statut'), 'rechute', {'censure'}, groupRaw: ds.text('bras'), horizon: 24, timeUnit: 'mois', groupName: 'bras');
  journal.add(_entry(2, cif, data: ds, note: tr('Incidence cumulée de la rechute, le décès étant un événement concurrent.', 'Cumulative incidence of relapse, death being a competing event.')));
  // 3) Fine-Gray ajusté, Cox spécifique de cause en regard.
  final fg = fineGrayRegression(buildCompetingDesign(ds, 'mois', 'statut', 'rechute', {'censure'}, [
    TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'),
  ]));
  journal.add(_entry(3, fg, data: ds, note: tr('Modèle de Fine-Gray ajusté : l\'âge en sens opposés selon le modèle.', 'Adjusted Fine-Gray model: age in opposite directions depending on the model.')));
  // 4–5) Stanford : greffe codée à l'inclusion, puis en covariable dépendant du temps.
  final h = stanfordHeartExample;
  final yes = tr('oui', 'yes'), no = tr('non', 'no');
  final st = Dataset.fromColumns({
    'jours': h.days,
    'deces': [for (final d in h.died) d == 1 ? yes : no],
    'attente_greffe': h.wait,
    'greffe': [for (final w in h.wait) w == null ? no : yes],
    'age': h.age,
    'chirurgie': [for (final c in h.surgery) c == 1 ? yes : no],
  }, source: tr('greffe cardiaque de Stanford (jasa, paquet R survival)', 'Stanford heart transplant (jasa, R package survival)'));
  final terms = [TermSpec('greffe', categorical: true, reference: no), TermSpec('age'), TermSpec('chirurgie', categorical: true, reference: no)];
  final coxNaive = coxRegression(buildSurvivalDesign(st, 'jours', 'deces', yes, terms));
  journal.add(_entry(4, coxNaive, data: st, note: tr('Greffe codée à l\'inclusion : biais du temps immortel.', 'Transplant coded at inclusion: immortal time bias.')));
  final long = splitAtSwitch(st, time: 'jours', status: 'deces', eventLevel: yes, switchTime: 'attente_greffe', covariate: 'greffe', yes: yes, no: no);
  final coxTd = coxRegression(buildCountingDesign(long, 'debut', 'fin', 'deces', yes, terms));
  journal.add(_entry(5, coxTd, data: long, note: tr('Greffe en covariable dépendant du temps : comparaison correcte à chaque décès.', 'Transplant as a time-dependent covariate: correct comparison at each death.')));
  final naiveA = naive.estimates.firstWhere((e) => e.label.startsWith(tr('Survie à', 'Survival at')) && e.label.endsWith('— A'));
  return Project(
    id: 'demo-survie',
    title: tr('Démo 8 — Survie avancée : risques concurrents et temps immortel', 'Demo 8 — Advanced survival: competing risks and immortal time'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: tr('Rechute et décès : données SIMULÉES (400 patients). Greffe : données RÉELLES publiées du programme de Stanford (103 patients, Crowley et Hu 1977).',
        'Relapse and death: SIMULATED data (400 patients). Transplant: REAL published data from the Stanford programme (103 patients, Crowley and Hu 1977).'),
    dataset: ds,
    question: ResearchQuestion(
      text: tr('Le bras B réduit-il la rechute après traitement d\'un cancer, sachant que des patients meurent avant de rechuter ?',
          'Does arm B reduce relapse after cancer treatment, given that some patients die before relapsing?'),
      population: tr('Patients traités pour un cancer, suivis jusqu\'à 72 mois', 'Patients treated for cancer, followed up to 72 months'),
      exposure: tr('Bras B', 'Arm B'),
      comparator: tr('Bras A', 'Arm A'),
      outcome: tr('Rechute (décès sans rechute : événement concurrent)', 'Relapse (death without relapse: competing event)'),
      horizon: tr('24 mois', '24 months'),
      design: StudyDesign.cohort,
      objective: StudyObjective.explanatory,
      outcomeType: OutcomeType.timeToEvent,
      exposureType: ExposureType.binary,
      pairing: Pairing.independent,
      dataLevel: DataLevel.individual,
      needsAdjustment: true,
      expectedEvents: 191,
      competingRisk: true,
      timeVaryingExposure: false,
    ),
    analysisPlan: tr(
        '1) Kaplan-Meier « naïf » de la rechute (pour montrer l\'erreur). 2) Incidence cumulée d\'Aalen-Johansen par bras, test de Gray, sHR du bras. 3) Fine-Gray ajusté (bras, âge, sexe) avec Cox spécifique de cause en regard. 4–5) Exemple de la greffe de Stanford : greffe codée à l\'inclusion (biais du temps immortel), puis en covariable dépendant du temps.',
        '1) "Naive" Kaplan-Meier of relapse (to show the error). 2) Aalen-Johansen cumulative incidence by arm, Gray test, sHR of the arm. 3) Adjusted Fine-Gray (arm, age, sex) with cause-specific Cox alongside. 4–5) Stanford transplant example: transplant coded at inclusion (immortal time bias), then as a time-dependent covariate.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit et la leçon « risques concurrents et temps immortel ».
    resultsText: tr(
        'D\'après Kaplan-Meier, ${fmtPct(1 - naiveA.value)} des patients du bras A ont rechuté à 24 mois. L\'âge protège contre la rechute (sHR < 1). Dans la cohorte de Stanford, la greffe réduit la mortalité de ${fmtPct(1 - coxNaive.estimates.first.value, decimals: 0)} (HR = ${fmt(coxNaive.estimates.first.value)}), ce qui prouve son efficacité.',
        'According to Kaplan-Meier, ${fmtPct(1 - naiveA.value)} of patients in arm A had relapsed at 24 months. Age protects against relapse (sHR < 1). In the Stanford cohort, transplantation reduces mortality by ${fmtPct(1 - coxNaive.estimates.first.value, decimals: 0)} (HR = ${fmt(coxNaive.estimates.first.value)}), which proves its efficacy.'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}



/// Démonstration 9 : laboratoire — la créatinine dosée sur plasma remplace-t-elle le dosage sur sérum ?
/// Données réelles publiées (mcr::creatinine).
Project buildDemoMethodComparison(String csv) {
  final ds = parseCsv(csv, source: tr('creatinine_serum_plasma.csv (paquet R mcr)', 'creatinine_serum_plasma.csv (R package mcr)')).dataset;
  final x = ds.numeric('creatinine_serum'), y = ds.numeric('creatinine_plasma');
  final journal = <JournalEntry>[];
  final r = correlation(x, y, xName: 'creatinine_serum', yName: 'creatinine_plasma');
  journal.add(_entry(1, r, data: ds, note: tr('Corrélation : mesure l\'association, pas l\'accord (à ne pas utiliser pour conclure).', 'Correlation: measures association, not agreement (not to be used to conclude).')));
  final ba = blandAltman(x, y, name1: 'creatinine_serum', name2: 'creatinine_plasma', unit: 'mg/dL', acceptableLimit: 0.3);
  journal.add(_entry(2, ba, data: ds, note: tr('Limite acceptable fixée a priori : ±0,3 mg/dL.', 'Acceptable limit set a priori: ±0.3 mg/dL.')));
  final pb = methodComparison(x, y, xName: 'creatinine_serum', yName: 'creatinine_plasma', unit: 'mg/dL', decisionLevels: const [1.2, 2.0]);
  journal.add(_entry(3, pb, data: ds, note: tr('Niveaux de décision : 1,2 mg/dL (limite supérieure usuelle) et 2,0 mg/dL.', 'Decision levels: 1.2 mg/dL (usual upper limit) and 2.0 mg/dL.')));
  final dm = methodComparison(x, y, kind: MethodComparisonKind.deming, xName: 'creatinine_serum', yName: 'creatinine_plasma', unit: 'mg/dL', decisionLevels: const [1.2, 2.0]);
  journal.add(_entry(4, dm, data: ds, note: tr('Deming, répétabilités supposées égales (λ = 1).', 'Deming, repeatabilities assumed equal (λ = 1).')));
  double est(AnalysisResult a, String fr) => a.estimates.firstWhere((e) => e.label.startsWith(fr)).value;
  final lo = est(ba, tr('Limite d\'accord inf', 'Lower limit')), hi = est(ba, tr('Limite d\'accord sup', 'Upper limit'));
  return Project(
    id: 'demo-methodes',
    title: tr('Démo 9 — Laboratoire : créatinine sur plasma ou sur sérum ?', 'Demo 9 — Laboratory: creatinine on plasma or on serum?'),
    createdAt: tr('démonstration', 'demonstration'),
    demoNotice: tr('Données RÉELLES publiées : créatinine dosée sur sérum et sur plasma chez 108 patients (jeu d\'exemple du paquet R mcr, mg/dL).',
        'REAL published data: creatinine measured on serum and on plasma in 108 patients (example data of the R package mcr, mg/dL).'),
    dataset: ds,
    question: ResearchQuestion(
      text: tr('Le dosage de la créatinine sur plasma peut-il remplacer le dosage sur sérum sans changer l\'interprétation clinique ?',
          'Can creatinine measured on plasma replace measurement on serum without changing the clinical interpretation?'),
      population: tr('Patients dont la créatinine est dosée en routine', 'Patients with routine creatinine measurement'),
      exposure: tr('Dosage sur plasma (méthode évaluée)', 'Measurement on plasma (test method)'),
      comparator: tr('Dosage sur sérum (méthode de référence)', 'Measurement on serum (reference method)'),
      outcome: tr('Créatinine (mg/dL)', 'Creatinine (mg/dL)'),
      horizon: tr('Même prélèvement', 'Same sample'),
      design: StudyDesign.crossSectional,
      objective: StudyObjective.descriptive,
      outcomeType: OutcomeType.continuous,
      exposureType: ExposureType.binary,
      pairing: Pairing.paired,
      dataLevel: DataLevel.individual,
      agreementQuestion: true,
    ),
    analysisPlan: tr(
        '1) Bland-Altman (biais, limites d\'accord et leurs IC), écart acceptable fixé a priori à ±0,3 mg/dL. 2) Passing-Bablok : biais constant (ordonnée) et proportionnel (pente), biais aux niveaux de décision 1,2 et 2,0 mg/dL. 3) Deming (λ = 1) en sensibilité. La corrélation est rapportée pour montrer qu\'elle ne mesure pas l\'accord.',
        '1) Bland-Altman (bias, limits of agreement and their CIs), acceptable difference set a priori at ±0.3 mg/dL. 2) Passing-Bablok: constant (intercept) and proportional (slope) bias, bias at the decision levels 1.2 and 2.0 mg/dL. 3) Deming (λ = 1) as sensitivity analysis. The correlation is reported to show that it does not measure agreement.'),
    journal: journal,
    // Brouillon contenant des erreurs volontaires, à repérer avec l'audit et la leçon « accord entre méthodes ».
    resultsText: tr(
        'Les deux dosages sont très fortement corrélés (r = ${fmt(r.estimates.first.value)}), ce qui prouve qu\'ils sont interchangeables. La différence entre sérum et plasma est comprise dans l\'IC à 95 % de ${fmt(lo)} à ${fmt(hi)} mg/dL. La pente de Passing-Bablok vaut ${fmtFixed(pb.statistics['slope']!, 5)} : pas de différence entre les méthodes (p > 0,05 pour la tendance de Bland-Altman).',
        'The two assays are very strongly correlated (r = ${fmt(r.estimates.first.value)}), which proves that they are interchangeable. The difference between serum and plasma lies within the 95% CI from ${fmt(lo)} to ${fmt(hi)} mg/dL. The Passing-Bablok slope is ${fmtFixed(pb.statistics['slope']!, 5)}: no difference between the methods (p > 0.05 for the Bland-Altman trend).'),
    completed: {Step.question, Step.studyPlan, Step.analysisPlan, Step.dataControl, Step.methodChoice, Step.computation, Step.diagnostics, Step.interpretation},
  );
}
