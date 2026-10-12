/// Grilles d'aide à la rédaction et à l'examen critique. Ce sont des
/// PARAPHRASES pédagogiques, condensées, des listes publiées ; elles guident
/// sans remplacer le texte officiel, à consulter pour toute soumission :
///  - TRIPOD+AI : Collins GS et al., BMJ 2024;385:e078378 ;
///  - PROBAST+AI : Moons KGM et al., BMJ 2025;388:e082505 ;
///  - PRISMA 2020 : Page MJ et al., BMJ 2021;372:n71.
/// Rappel : la conformité à une liste de RAPPORT (TRIPOD, PRISMA) ne mesure
/// pas la qualité méthodologique ; PROBAST+AI évalue le risque de biais.
library;

import '../i18n.dart';

enum ItemAnswer { yes, partial, no, notApplicable, unanswered }

class ChecklistItem {
  final String id;
  final String section;
  final String text;

  /// Élément vérifiable automatiquement dans Statoméa (sinon : déclaratif).
  final String? autoCheck;
  const ChecklistItem(this.id, this.section, this.text, {this.autoCheck});
}

class Checklist {
  final String id;
  final String title;
  final String reference;
  final String purpose;
  final List<ChecklistItem> items;
  const Checklist(this.id, this.title, this.reference, this.purpose, this.items);
}

const _tripodAiFr = Checklist('tripod_ai', 'TRIPOD+AI (paraphrase)', 'Collins GS et al. BMJ 2024;385:e078378',
    'Guide de RAPPORT d\'une étude de développement ou d\'évaluation d\'un modèle de prédiction.', [
  ChecklistItem('T1', 'Titre et résumé', 'Le titre indique qu\'il s\'agit de développer et/ou d\'évaluer un modèle de prédiction, la population cible et l\'issue.'),
  ChecklistItem('T2', 'Titre et résumé', 'Le résumé structuré couvre objectif, sources de données, participants, issue, modèle, performance (discrimination ET calibration) et conclusion.'),
  ChecklistItem('T3', 'Introduction', 'Le contexte clinique, l\'usage prévu du modèle et les utilisateurs visés sont décrits.', autoCheck: 'spec.intendedUse'),
  ChecklistItem('T4', 'Introduction', 'Les objectifs précisent développement, validation interne et/ou externe.'),
  ChecklistItem('T5', 'Méthodes — données', 'Sources de données, dates, lieux et plan (cohorte, registre, essai) sont décrits.'),
  ChecklistItem('T6', 'Méthodes — participants', 'Critères d\'éligibilité, population cible et traitements reçus sont précisés.', autoCheck: 'spec.targetPopulation'),
  ChecklistItem('T7', 'Méthodes — préparation', 'Le prétraitement des données (nettoyage, transformations, recodages) est décrit et a été fait sans fuite d\'information vers la validation.', autoCheck: 'journal.corrections'),
  ChecklistItem('T8', 'Méthodes — issue', 'L\'issue, son horizon et sa méthode de mesure sont définis ; l\'aveugle vis-à-vis des prédicteurs est précisé.', autoCheck: 'spec.horizon'),
  ChecklistItem('T9', 'Méthodes — prédicteurs', 'Les prédicteurs, leur moment de mesure et leur codage sont définis ; ils sont disponibles au moment de la prédiction.', autoCheck: 'model.coding'),
  ChecklistItem('T10', 'Méthodes — taille d\'échantillon', 'La taille d\'échantillon est justifiée (p. ex. critères de Riley).', autoCheck: 'check.sample_size'),
  ChecklistItem('T11', 'Méthodes — données manquantes', 'Le nombre de données manquantes et leur traitement sont rapportés.', autoCheck: 'check.missing_data'),
  ChecklistItem('T12', 'Méthodes — analyse', 'Le type de modèle, la construction, la sélection éventuelle des prédicteurs et la méthode de validation interne sont décrits.', autoCheck: 'result.bootstrap'),
  ChecklistItem('T13', 'Méthodes — performance', 'Les mesures de performance sont définies : discrimination, calibration (courbe, pente, intercept) et, si pertinent, utilité clinique.', autoCheck: 'result.calibration'),
  ChecklistItem('T14', 'Méthodes — équité', 'La performance dans des sous-groupes pertinents (sexe, âge, origine, lieu) est examinée.'),
  ChecklistItem('T15', 'Méthodes — modèle de référence', 'La comparaison à un modèle de référence ou à la pratique courante est décrite.', autoCheck: 'result.reference'),
  ChecklistItem('T16', 'Ouverture', 'Disponibilité des données, du code et du modèle ; enregistrement du protocole.'),
  ChecklistItem('T17', 'Implication des patients', 'L\'implication éventuelle de patients et du public est décrite.'),
  ChecklistItem('T18', 'Résultats — participants', 'Le flux des participants (diagramme), leurs caractéristiques et le nombre d\'événements sont rapportés.'),
  ChecklistItem('T19', 'Résultats — modèle', 'Le modèle complet (toutes les constantes et coefficients) est présenté pour permettre son utilisation.', autoCheck: 'result.equation'),
  ChecklistItem('T20', 'Résultats — performance', 'La performance est rapportée avec IC, apparente et corrigée de l\'optimisme.', autoCheck: 'result.corrected'),
  ChecklistItem('T21', 'Discussion', 'Limites (biais, surajustement, généralisabilité) et nécessité de validation externe et d\'étude d\'impact sont discutées.'),
  ChecklistItem('T22', 'Discussion', 'L\'usage prévu est réexaminé à la lumière des résultats ; aucune revendication de « validation clinique » non étayée.'),
]);

const _probastAiFr = Checklist('probast_ai', 'PROBAST+AI (paraphrase, risque de biais et applicabilité)', 'Moons KGM et al. BMJ 2025;388:e082505',
    'Outil d\'EXAMEN du risque de biais et de l\'applicabilité d\'une étude de modèle de prédiction (développement ou évaluation).', [
  ChecklistItem('P1.1', 'Domaine 1 — Participants et sources de données', 'Les sources de données sont-elles appropriées (cohorte prospective, registre de qualité) plutôt que cas-témoins non corrigé ?'),
  ChecklistItem('P1.2', 'Domaine 1 — Participants et sources de données', 'Toutes les inclusions et exclusions sont-elles appropriées et cohérentes avec la population cible ?'),
  ChecklistItem('P1.A', 'Domaine 1 — Applicabilité', 'Les participants et le contexte correspondent-ils à la question de l\'utilisateur ?'),
  ChecklistItem('P2.1', 'Domaine 2 — Prédicteurs', 'Les prédicteurs sont-ils définis et mesurés de la même façon pour tous les participants ?'),
  ChecklistItem('P2.2', 'Domaine 2 — Prédicteurs', 'Les prédicteurs ont-ils été évalués sans connaissance de l\'issue ?'),
  ChecklistItem('P2.3', 'Domaine 2 — Prédicteurs', 'Tous les prédicteurs sont-ils disponibles au moment où le modèle doit être utilisé ?'),
  ChecklistItem('P2.A', 'Domaine 2 — Applicabilité', 'La définition et le moment de mesure des prédicteurs correspondent-ils à l\'usage prévu ?'),
  ChecklistItem('P3.1', 'Domaine 3 — Issue', 'L\'issue est-elle déterminée de façon appropriée et standardisée ?'),
  ChecklistItem('P3.2', 'Domaine 3 — Issue', 'L\'issue est-elle déterminée sans connaissance des prédicteurs, et les prédicteurs ne font-ils pas partie de sa définition ?'),
  ChecklistItem('P3.3', 'Domaine 3 — Issue', 'L\'intervalle entre mesure des prédicteurs et issue est-il approprié (horizon défini) ?'),
  ChecklistItem('P3.A', 'Domaine 3 — Applicabilité', 'La définition et l\'horizon de l\'issue correspondent-ils à la question ?'),
  ChecklistItem('P4.1', 'Domaine 4 — Analyse', 'La taille d\'échantillon est-elle suffisante (critères de Riley ou équivalent) ?', autoCheck: 'check.sample_size'),
  ChecklistItem('P4.2', 'Domaine 4 — Analyse', 'Les prédicteurs continus sont-ils traités sans dichotomisation injustifiée ?'),
  ChecklistItem('P4.3', 'Domaine 4 — Analyse', 'Les données manquantes sont-elles traitées de façon appropriée ?', autoCheck: 'check.missing_data'),
  ChecklistItem('P4.4', 'Domaine 4 — Analyse', 'La sélection des prédicteurs évite-t-elle la sélection univariée et les fuites d\'information ?', autoCheck: 'check.leakage'),
  ChecklistItem('P4.5', 'Domaine 4 — Analyse', 'Le surajustement et l\'optimisme sont-ils pris en compte (validation interne appropriée, rétrécissement) ?', autoCheck: 'check.shrinkage'),
  ChecklistItem('P4.6', 'Domaine 4 — Analyse', 'Discrimination ET calibration sont-elles évaluées de façon appropriée ?', autoCheck: 'result.calibration'),
  ChecklistItem('P4.7', 'Domaine 4 — Analyse', 'L\'équité (performance par sous-groupes) est-elle examinée lorsque c\'est pertinent ?'),
]);

const _prisma2020Fr = Checklist('prisma_2020', 'PRISMA 2020 (paraphrase)', 'Page MJ et al. BMJ 2021;372:n71',
    'Guide de RAPPORT d\'une revue systématique. La conformité PRISMA ne mesure pas la qualité méthodologique des études ni de la revue (voir RoB 2, ROBINS-I, AMSTAR 2, GRADE).', [
  ChecklistItem('R1', 'Titre', 'Identifier le rapport comme une revue systématique.'),
  ChecklistItem('R2', 'Résumé', 'Résumé structuré (voir PRISMA 2020 pour les résumés).'),
  ChecklistItem('R3', 'Introduction', 'Justification au regard des connaissances existantes.'),
  ChecklistItem('R4', 'Introduction', 'Objectifs ou questions explicites (PICO).', autoCheck: 'question.pico'),
  ChecklistItem('R5', 'Méthodes', 'Critères d\'éligibilité et regroupements pour la synthèse.'),
  ChecklistItem('R6', 'Méthodes', 'Sources d\'information et date de dernière recherche.'),
  ChecklistItem('R7', 'Méthodes', 'Stratégies de recherche complètes pour toutes les bases.'),
  ChecklistItem('R8', 'Méthodes', 'Processus de sélection (nombre de relecteurs, indépendance).'),
  ChecklistItem('R9', 'Méthodes', 'Processus d\'extraction des données.', autoCheck: 'meta.provenance'),
  ChecklistItem('R10', 'Méthodes', 'Liste et définition des données recherchées (issues, autres variables).'),
  ChecklistItem('R11', 'Méthodes', 'Méthode d\'évaluation du risque de biais des études.'),
  ChecklistItem('R12', 'Méthodes', 'Mesures d\'effet utilisées.', autoCheck: 'meta.measure'),
  ChecklistItem('R13', 'Méthodes', 'Méthodes de synthèse : éligibilité à chaque synthèse, préparation des données, modèle, hétérogénéité, sensibilité.', autoCheck: 'meta.model'),
  ChecklistItem('R14', 'Méthodes', 'Évaluation du biais de publication (biais de rapport).'),
  ChecklistItem('R15', 'Méthodes', 'Évaluation de la certitude des preuves (p. ex. GRADE).'),
  ChecklistItem('R16', 'Résultats', 'Sélection des études : diagramme de flux, études exclues avec raisons.'),
  ChecklistItem('R17', 'Résultats', 'Caractéristiques des études incluses.'),
  ChecklistItem('R18', 'Résultats', 'Risque de biais de chaque étude.'),
  ChecklistItem('R19', 'Résultats', 'Résultats de chaque étude (effets et précision), idéalement en forest plot.', autoCheck: 'meta.forest'),
  ChecklistItem('R20', 'Résultats', 'Résultats des synthèses : effet combiné, IC, hétérogénéité, analyses de sensibilité et de sous-groupes.', autoCheck: 'meta.sensitivity'),
  ChecklistItem('R21', 'Résultats', 'Biais de rapport évalué.'),
  ChecklistItem('R22', 'Résultats', 'Certitude des preuves pour chaque issue.'),
  ChecklistItem('R23', 'Discussion', 'Interprétation, limites des preuves et de la revue, implications.'),
  ChecklistItem('R24', 'Autres', 'Enregistrement et protocole (PROSPERO), modifications.'),
  ChecklistItem('R25', 'Autres', 'Financement.'),
  ChecklistItem('R26', 'Autres', 'Conflits d\'intérêts.'),
  ChecklistItem('R27', 'Autres', 'Disponibilité des données, du code et des autres documents.'),
]);

Checklist get tripodAi => currentLang == Lang.en ? _tripodAiEn : _tripodAiFr;
Checklist get probastAi => currentLang == Lang.en ? _probastAiEn : _probastAiFr;
Checklist get prisma2020 => currentLang == Lang.en ? _prisma2020En : _prisma2020Fr;
List<Checklist> get allChecklists => [tripodAi, probastAi, prisma2020];

// English paraphrases (same item identifiers and automatic checks).

const _tripodAiEn = Checklist('tripod_ai', 'TRIPOD+AI (paraphrase)', 'Collins GS et al. BMJ 2024;385:e078378',
    'REPORTING guideline for a study developing or evaluating a prediction model.', [
  ChecklistItem('T1', 'Title and abstract', 'The title states that a prediction model is developed and/or evaluated, the target population and the outcome.'),
  ChecklistItem('T2', 'Title and abstract', 'The structured abstract covers objective, data sources, participants, outcome, model, performance (discrimination AND calibration) and conclusion.'),
  ChecklistItem('T3', 'Introduction', 'The clinical context, the intended use of the model and the intended users are described.', autoCheck: 'spec.intendedUse'),
  ChecklistItem('T4', 'Introduction', 'The objectives specify development, internal and/or external validation.'),
  ChecklistItem('T5', 'Methods — data', 'Data sources, dates, places and design (cohort, registry, trial) are described.'),
  ChecklistItem('T6', 'Methods — participants', 'Eligibility criteria, target population and treatments received are specified.', autoCheck: 'spec.targetPopulation'),
  ChecklistItem('T7', 'Methods — data preparation', 'Data preprocessing (cleaning, transformations, recoding) is described and was done without information leakage into validation.', autoCheck: 'journal.corrections'),
  ChecklistItem('T8', 'Methods — outcome', 'The outcome, its horizon and its measurement method are defined; blinding to the predictors is specified.', autoCheck: 'spec.horizon'),
  ChecklistItem('T9', 'Methods — predictors', 'The predictors, their time of measurement and their coding are defined; they are available at the time of prediction.', autoCheck: 'model.coding'),
  ChecklistItem('T10', 'Methods — sample size', 'The sample size is justified (e.g. Riley criteria).', autoCheck: 'check.sample_size'),
  ChecklistItem('T11', 'Methods — missing data', 'The amount of missing data and its handling are reported.', autoCheck: 'check.missing_data'),
  ChecklistItem('T12', 'Methods — analysis', 'The model type, its construction, any predictor selection and the internal validation method are described.', autoCheck: 'result.bootstrap'),
  ChecklistItem('T13', 'Methods — performance', 'The performance measures are defined: discrimination, calibration (curve, slope, intercept) and, if relevant, clinical usefulness.', autoCheck: 'result.calibration'),
  ChecklistItem('T14', 'Methods — fairness', 'Performance in relevant subgroups (sex, age, ethnicity, setting) is examined.'),
  ChecklistItem('T15', 'Methods — reference model', 'The comparison with a reference model or with current practice is described.', autoCheck: 'result.reference'),
  ChecklistItem('T16', 'Open science', 'Availability of data, code and model; protocol registration.'),
  ChecklistItem('T17', 'Patient involvement', 'Any involvement of patients and the public is described.'),
  ChecklistItem('T18', 'Results — participants', 'The flow of participants (diagram), their characteristics and the number of events are reported.'),
  ChecklistItem('T19', 'Results — model', 'The full model (all intercepts and coefficients) is presented to allow its use.', autoCheck: 'result.equation'),
  ChecklistItem('T20', 'Results — performance', 'Performance is reported with CIs, apparent and optimism-corrected.', autoCheck: 'result.corrected'),
  ChecklistItem('T21', 'Discussion', 'Limitations (bias, overfitting, generalizability) and the need for external validation and an impact study are discussed.'),
  ChecklistItem('T22', 'Discussion', 'The intended use is re-examined in the light of the results; no unsupported claim of "clinical validation".'),
]);

const _probastAiEn = Checklist('probast_ai', 'PROBAST+AI (paraphrase, risk of bias and applicability)', 'Moons KGM et al. BMJ 2025;388:e082505',
    'APPRAISAL tool for the risk of bias and applicability of a prediction model study (development or evaluation).', [
  ChecklistItem('P1.1', 'Domain 1 — Participants and data sources', 'Are the data sources appropriate (prospective cohort, good-quality registry) rather than an uncorrected case-control design?'),
  ChecklistItem('P1.2', 'Domain 1 — Participants and data sources', 'Are all inclusions and exclusions appropriate and consistent with the target population?'),
  ChecklistItem('P1.A', 'Domain 1 — Applicability', "Do the participants and setting match the user's question?"),
  ChecklistItem('P2.1', 'Domain 2 — Predictors', 'Are the predictors defined and measured in the same way for all participants?'),
  ChecklistItem('P2.2', 'Domain 2 — Predictors', 'Were the predictors assessed without knowledge of the outcome?'),
  ChecklistItem('P2.3', 'Domain 2 — Predictors', 'Are all predictors available at the time the model is to be used?'),
  ChecklistItem('P2.A', 'Domain 2 — Applicability', 'Do the definition and timing of the predictors match the intended use?'),
  ChecklistItem('P3.1', 'Domain 3 — Outcome', 'Is the outcome determined in an appropriate, standardized way?'),
  ChecklistItem('P3.2', 'Domain 3 — Outcome', 'Is the outcome determined without knowledge of the predictors, and are the predictors excluded from its definition?'),
  ChecklistItem('P3.3', 'Domain 3 — Outcome', 'Is the interval between predictor measurement and outcome appropriate (defined horizon)?'),
  ChecklistItem('P3.A', 'Domain 3 — Applicability', 'Do the definition and horizon of the outcome match the question?'),
  ChecklistItem('P4.1', 'Domain 4 — Analysis', 'Is the sample size sufficient (Riley criteria or equivalent)?', autoCheck: 'check.sample_size'),
  ChecklistItem('P4.2', 'Domain 4 — Analysis', 'Are continuous predictors handled without unjustified dichotomization?'),
  ChecklistItem('P4.3', 'Domain 4 — Analysis', 'Are missing data handled appropriately?', autoCheck: 'check.missing_data'),
  ChecklistItem('P4.4', 'Domain 4 — Analysis', 'Does predictor selection avoid univariable selection and information leakage?', autoCheck: 'check.leakage'),
  ChecklistItem('P4.5', 'Domain 4 — Analysis', 'Are overfitting and optimism accounted for (appropriate internal validation, shrinkage)?', autoCheck: 'check.shrinkage'),
  ChecklistItem('P4.6', 'Domain 4 — Analysis', 'Are discrimination AND calibration evaluated appropriately?', autoCheck: 'result.calibration'),
  ChecklistItem('P4.7', 'Domain 4 — Analysis', 'Is fairness (performance by subgroup) examined where relevant?'),
]);

const _prisma2020En = Checklist('prisma_2020', 'PRISMA 2020 (paraphrase)', 'Page MJ et al. BMJ 2021;372:n71',
    'REPORTING guideline for a systematic review. PRISMA compliance does not measure the methodological quality of the studies or of the review (see RoB 2, ROBINS-I, AMSTAR 2, GRADE).', [
  ChecklistItem('R1', 'Title', 'Identify the report as a systematic review.'),
  ChecklistItem('R2', 'Abstract', 'Structured abstract (see PRISMA 2020 for abstracts).'),
  ChecklistItem('R3', 'Introduction', 'Rationale in the context of existing knowledge.'),
  ChecklistItem('R4', 'Introduction', 'Explicit objectives or questions (PICO).', autoCheck: 'question.pico'),
  ChecklistItem('R5', 'Methods', 'Eligibility criteria and groupings for the synthesis.'),
  ChecklistItem('R6', 'Methods', 'Information sources and date of last search.'),
  ChecklistItem('R7', 'Methods', 'Full search strategies for all databases.'),
  ChecklistItem('R8', 'Methods', 'Selection process (number of reviewers, independence).'),
  ChecklistItem('R9', 'Methods', 'Data collection process.', autoCheck: 'meta.provenance'),
  ChecklistItem('R10', 'Methods', 'List and definition of the data sought (outcomes, other variables).'),
  ChecklistItem('R11', 'Methods', 'Method for assessing the risk of bias of the studies.'),
  ChecklistItem('R12', 'Methods', 'Effect measures used.', autoCheck: 'meta.measure'),
  ChecklistItem('R13', 'Methods', 'Synthesis methods: eligibility for each synthesis, data preparation, model, heterogeneity, sensitivity.', autoCheck: 'meta.model'),
  ChecklistItem('R14', 'Methods', 'Assessment of publication bias (reporting bias).'),
  ChecklistItem('R15', 'Methods', 'Assessment of the certainty of evidence (e.g. GRADE).'),
  ChecklistItem('R16', 'Results', 'Study selection: flow diagram, excluded studies with reasons.'),
  ChecklistItem('R17', 'Results', 'Characteristics of the included studies.'),
  ChecklistItem('R18', 'Results', 'Risk of bias of each study.'),
  ChecklistItem('R19', 'Results', 'Results of each study (effects and precision), ideally in a forest plot.', autoCheck: 'meta.forest'),
  ChecklistItem('R20', 'Results', 'Results of the syntheses: pooled effect, CI, heterogeneity, sensitivity and subgroup analyses.', autoCheck: 'meta.sensitivity'),
  ChecklistItem('R21', 'Results', 'Reporting bias assessed.'),
  ChecklistItem('R22', 'Results', 'Certainty of evidence for each outcome.'),
  ChecklistItem('R23', 'Discussion', 'Interpretation, limitations of the evidence and of the review, implications.'),
  ChecklistItem('R24', 'Other', 'Registration and protocol (PROSPERO), amendments.'),
  ChecklistItem('R25', 'Other', 'Funding.'),
  ChecklistItem('R26', 'Other', 'Competing interests.'),
  ChecklistItem('R27', 'Other', 'Availability of data, code and other materials.'),
]);
