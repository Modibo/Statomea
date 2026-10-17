/// Assistant de choix de méthode. Il raisonne uniquement sur les
/// caractéristiques DÉCLARÉES de la question (jamais sur le nom des
/// variables) ; si une information manque, il pose la question au lieu de
/// supposer ; si plusieurs approches sont défendables, il les présente avec
/// leurs conditions.
library;

import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'registry.dart';

enum OutcomeType { binary, continuous, ordinal, categorical, count, timeToEvent, unknown }

enum ExposureType { binary, categorical, continuous, none, unknown }

enum Pairing { independent, paired, repeated, unknown }

enum DataLevel { individual, aggregatedStudies, unknown }

String outcomeTypeLabel(OutcomeType t) => switch (t) {
      OutcomeType.binary => tr('binaire', 'binary'),
      OutcomeType.continuous => tr('quantitative continue', 'continuous quantitative'),
      OutcomeType.ordinal => tr('ordinale', 'ordinal'),
      OutcomeType.categorical => tr('qualitative à plus de 2 modalités', 'categorical with more than 2 levels'),
      OutcomeType.count => tr('de comptage', 'count'),
      OutcomeType.timeToEvent => tr("délai jusqu'à événement (avec censure)", 'time to event (with censoring)'),
      OutcomeType.unknown => tr('non précisé', 'not specified'),
    };

/// Question de recherche structurée (PICO + caractéristiques des données).
class ResearchQuestion {
  final String text;
  final String population;
  final String exposure; // intervention ou exposition
  final String comparator;
  final String outcome;
  final String horizon;
  final StudyDesign design;
  final StudyObjective objective;
  final OutcomeType outcomeType;
  final ExposureType exposureType;
  final int? groups;
  final Pairing pairing;
  final DataLevel dataLevel;
  final bool? needsAdjustment; // facteurs de confusion à prendre en compte
  final bool? approxNormal; // distribution approximativement normale ou n suffisant
  final bool agreementQuestion; // deux méthodes mesurant la même grandeur
  final bool referenceStandardAvailable;
  final int? expectedEvents;

  /// Survie : un autre événement (p. ex. le décès) peut-il empêcher l'événement étudié ?
  final bool? competingRisk;

  /// Survie : l'exposition peut-elle survenir ou changer pendant le suivi (traitement commencé plus tard, greffe) ?
  final bool? timeVaryingExposure;

  const ResearchQuestion({
    this.text = '',
    this.population = '',
    this.exposure = '',
    this.comparator = '',
    this.outcome = '',
    this.horizon = '',
    this.design = StudyDesign.unknown,
    this.objective = StudyObjective.unknown,
    this.outcomeType = OutcomeType.unknown,
    this.exposureType = ExposureType.unknown,
    this.groups,
    this.pairing = Pairing.unknown,
    this.dataLevel = DataLevel.unknown,
    this.needsAdjustment,
    this.approxNormal,
    this.agreementQuestion = false,
    this.referenceStandardAvailable = false,
    this.expectedEvents,
    this.competingRisk,
    this.timeVaryingExposure,
  });

  Map<String, Object?> toJson() => {
        'text': text,
        'population': population,
        'exposure': exposure,
        'comparator': comparator,
        'outcome': outcome,
        'horizon': horizon,
        'design': design.name,
        'objective': objective.name,
        'outcomeType': outcomeType.name,
        'exposureType': exposureType.name,
        'groups': groups,
        'pairing': pairing.name,
        'dataLevel': dataLevel.name,
        'needsAdjustment': needsAdjustment,
        'approxNormal': approxNormal,
        'agreementQuestion': agreementQuestion,
        'referenceStandardAvailable': referenceStandardAvailable,
        'expectedEvents': expectedEvents,
        'competingRisk': competingRisk,
        'timeVaryingExposure': timeVaryingExposure,
      };

  factory ResearchQuestion.fromJson(Map<String, Object?> j) => ResearchQuestion(
        text: (j['text'] as String?) ?? '',
        population: (j['population'] as String?) ?? '',
        exposure: (j['exposure'] as String?) ?? '',
        comparator: (j['comparator'] as String?) ?? '',
        outcome: (j['outcome'] as String?) ?? '',
        horizon: (j['horizon'] as String?) ?? '',
        design: StudyDesign.values.byName((j['design'] as String?) ?? 'unknown'),
        objective: StudyObjective.values.byName((j['objective'] as String?) ?? 'unknown'),
        outcomeType: OutcomeType.values.byName((j['outcomeType'] as String?) ?? 'unknown'),
        exposureType: ExposureType.values.byName((j['exposureType'] as String?) ?? 'unknown'),
        groups: j['groups'] as int?,
        pairing: Pairing.values.byName((j['pairing'] as String?) ?? 'unknown'),
        dataLevel: DataLevel.values.byName((j['dataLevel'] as String?) ?? 'unknown'),
        needsAdjustment: j['needsAdjustment'] as bool?,
        approxNormal: j['approxNormal'] as bool?,
        agreementQuestion: (j['agreementQuestion'] as bool?) ?? false,
        referenceStandardAvailable: (j['referenceStandardAvailable'] as bool?) ?? false,
        expectedEvents: j['expectedEvents'] as int?,
        competingRisk: j['competingRisk'] as bool?,
        timeVaryingExposure: j['timeVaryingExposure'] as bool?,
      );

  ResearchQuestion copyWith({
    String? text,
    String? population,
    String? exposure,
    String? comparator,
    String? outcome,
    String? horizon,
    StudyDesign? design,
    StudyObjective? objective,
    OutcomeType? outcomeType,
    ExposureType? exposureType,
    int? groups,
    Pairing? pairing,
    DataLevel? dataLevel,
    bool? needsAdjustment,
    bool? approxNormal,
    bool? agreementQuestion,
    bool? referenceStandardAvailable,
    int? expectedEvents,
    bool? competingRisk,
    bool? timeVaryingExposure,
  }) =>
      ResearchQuestion(
        text: text ?? this.text,
        population: population ?? this.population,
        exposure: exposure ?? this.exposure,
        comparator: comparator ?? this.comparator,
        outcome: outcome ?? this.outcome,
        horizon: horizon ?? this.horizon,
        design: design ?? this.design,
        objective: objective ?? this.objective,
        outcomeType: outcomeType ?? this.outcomeType,
        exposureType: exposureType ?? this.exposureType,
        groups: groups ?? this.groups,
        pairing: pairing ?? this.pairing,
        dataLevel: dataLevel ?? this.dataLevel,
        needsAdjustment: needsAdjustment ?? this.needsAdjustment,
        approxNormal: approxNormal ?? this.approxNormal,
        agreementQuestion: agreementQuestion ?? this.agreementQuestion,
        referenceStandardAvailable: referenceStandardAvailable ?? this.referenceStandardAvailable,
        expectedEvents: expectedEvents ?? this.expectedEvents,
        competingRisk: competingRisk ?? this.competingRisk,
        timeVaryingExposure: timeVaryingExposure ?? this.timeVaryingExposure,
      );
}

/// Une question à poser à l'utilisateur, identifiée par le champ qu'elle remplit.
class Clarification {
  final String field;
  final String prompt;
  final String why;
  Clarification(this.field, this.prompt, this.why);
}

class MethodOption {
  final String methodId;
  final String name;
  final String whenPreferred;
  final List<String> conditions;
  final List<String> cautions;
  final MethodStatus status;
  final bool recommended;
  const MethodOption(this.methodId, this.name, this.whenPreferred,
      {this.conditions = const [], this.cautions = const [], this.status = MethodStatus.validated, this.recommended = false});
}

class Advice {
  final List<Clarification> questions;
  final List<MethodOption> options;
  final List<String> notes;
  const Advice(this.questions, this.options, this.notes);
  bool get needsMoreInformation => questions.isNotEmpty;
}

MethodOption _opt(String id, String when, {List<String> cautions = const [], bool recommended = false}) {
  final m = methodInfo(id)!;
  return MethodOption(id, m.name, when, conditions: m.conditions, cautions: cautions, status: m.status, recommended: recommended);
}

/// Propose des méthodes ou demande les précisions nécessaires.
Advice advise(ResearchQuestion q) {
  final ask = <Clarification>[];
  final opts = <MethodOption>[];
  final notes = <String>[];

  if (q.objective == StudyObjective.unknown) {
    ask.add(Clarification('objective', tr("Quel est l'objectif : décrire, expliquer (rechercher un effet ou une association), évaluer un test diagnostique, ou prédire un risque individuel ?", 'What is the aim: to describe, to explain (look for an effect or an association), to evaluate a diagnostic test, or to predict an individual risk?'),
        tr("La même base de données appelle des méthodes et des interprétations différentes selon l'objectif (un modèle prédictif ne s'interprète pas comme un modèle explicatif).", 'The same dataset calls for different methods and interpretations depending on the aim (a predictive model is not interpreted like an explanatory model).')));
  }
  if (q.dataLevel == DataLevel.unknown) {
    ask.add(Clarification('dataLevel', tr('Les données sont-elles des observations individuelles, ou des résultats agrégés issus de plusieurs études (métaanalyse) ?', 'Are the data individual observations, or aggregated results from several studies (meta-analysis)?'),
        tr("Une synthèse d'études relève de la métaanalyse.", 'A synthesis of studies is a matter for meta-analysis.')));
  }
  if (q.dataLevel == DataLevel.aggregatedStudies) {
    if (q.outcomeType == OutcomeType.unknown) {
      ask.add(Clarification('outcomeType', tr('Le critère de jugement des études est-il binaire (événement oui/non) ou continu (mesure) ?', 'Is the outcome of the studies binary (event yes/no) or continuous (measurement)?'),
          tr("Détermine la mesure d'effet (OR, RR, DR ou DM, DMS).", 'Determines the effect measure (OR, RR, RD or MD, SMD).')));
    }
    if (q.outcomeType == OutcomeType.binary) {
      opts.add(_opt('meta_binary', tr("Études rapportant les effectifs d'événements par bras.", 'Studies reporting event counts per arm.'),
          cautions: [tr('Vérifier la compatibilité PICO et la durée de suivi de chaque étude avant de combiner.', 'Check PICO compatibility and the follow-up duration of each study before pooling.'),
            tr("RR plus lisible ; OR si études cas-témoins ou issue très fréquente ; DR pour l'impact absolu.", 'RR easier to read; OR for case-control studies or a very common outcome; RD for absolute impact.')]));
    } else if (q.outcomeType == OutcomeType.continuous) {
      opts.add(_opt('meta_continuous', tr('DM si toutes les études utilisent la même échelle, DMS sinon.', 'MD if all studies use the same scale, SMD otherwise.')));
    }
    if (q.outcomeType == OutcomeType.binary || q.outcomeType == OutcomeType.continuous) {
      opts.add(_opt('meta_regression', tr("Si l'hétérogénéité est importante et qu'un modérateur a été prévu dans le protocole.", 'If heterogeneity is considerable and a moderator was planned in the protocol.'),
          cautions: [tr("Analyse exploratoire, entre études : pas d'inférence individuelle.", 'Exploratory, between-study analysis: no individual-level inference.')]));
    }
    if (q.referenceStandardAvailable) {
      opts.add(_opt('meta_diagnostic', tr('Synthèse de performances diagnostiques : modèle bivarié (Se et Sp conjointes).', 'Synthesis of diagnostic performance: bivariate model (joint Se and Sp).'), recommended: true,
          cautions: [tr('Ne pas combiner Se et Sp par deux métaanalyses univariées séparées.', 'Do not pool Se and Sp with two separate univariate meta-analyses.'), tr('Évaluer chaque étude avec QUADAS-2.', 'Assess each study with QUADAS-2.')]));
    }
    return Advice(ask, opts, notes);
  }

  if (q.agreementQuestion) {
    opts.add(_opt('bland_altman', tr('Deux méthodes mesurant la même grandeur quantitative sur les mêmes sujets.', 'Two methods measuring the same quantitative variable on the same subjects.'), recommended: true,
        cautions: [tr("Une corrélation élevée ne prouve pas l'accord.", 'A high correlation does not prove agreement.')]));
    return Advice(ask, opts, notes);
  }

  if (q.outcomeType == OutcomeType.unknown) {
    ask.add(Clarification('outcomeType', tr("Comment le critère de jugement est-il mesuré : binaire, quantitatif continu, ordinal, qualitatif à plusieurs modalités, comptage, ou délai jusqu'à un événement ?", 'How is the outcome measured: binary, continuous quantitative, ordinal, categorical with several levels, count, or time to an event?'),
        tr("Le type de l'issue (déclaré, pas déduit du nom de la variable) détermine la famille de méthodes.", 'The outcome type (declared, not inferred from the variable name) determines the family of methods.')));
  }

  switch (q.objective) {
    case StudyObjective.descriptive:
      if (q.outcomeType == OutcomeType.timeToEvent) {
        if (q.competingRisk == true) {
          opts.add(_opt('cumulative_incidence', tr('Un événement concurrent peut empêcher l\'événement : incidence cumulée d\'Aalen-Johansen plutôt que 1 − Kaplan-Meier.', 'A competing event can prevent the event: Aalen-Johansen cumulative incidence rather than 1 − Kaplan-Meier.'), recommended: true));
        }
        opts.add(_opt('kaplan_meier', tr('Décrire la survie (courbe, médiane, survie à un horizon) malgré la censure.', 'Describe survival (curve, median, survival at a horizon) despite censoring.'), recommended: q.competingRisk != true));
        if (q.competingRisk == null) ask.add(_competingQuestion());
      }
      if (q.outcomeType == OutcomeType.binary) {
        opts.add(_opt('proportion_ci', tr('Estimer une prévalence ou une fréquence avec son IC.', 'Estimate a prevalence or a frequency with its CI.'), recommended: true,
            cautions: [if ((q.expectedEvents ?? 99) < 5) tr("Peu d'événements : IC exact et règle de trois.", 'Few events: exact CI and rule of three.')]));
      } else if (q.outcomeType == OutcomeType.continuous || q.outcomeType == OutcomeType.ordinal) {
        opts.add(_opt('describe_numeric', tr('Décrire position et dispersion.', 'Describe location and spread.'), recommended: true));
      }
      if (q.design == StudyDesign.caseControl) {
        notes.add(tr("Une étude cas-témoins ne permet pas d'estimer une prévalence de l'issue dans la population.", 'A case-control study cannot estimate the prevalence of the outcome in the population.'));
      }
      opts.add(_opt('sample_size', tr('Pour planifier : nombre de sujets nécessaire à la précision voulue.', 'For planning: number of subjects needed for the desired precision.')));
    case StudyObjective.diagnostic:
      if (!q.referenceStandardAvailable) {
        ask.add(Clarification('referenceStandardAvailable', tr("Disposez-vous d'un examen de référence appliqué à tous les sujets ?", 'Do you have a reference standard applied to all subjects?'),
            tr('Sans référence, Se et Sp ne sont pas estimables (biais de vérification).', 'Without a reference, Se and Sp cannot be estimated (verification bias).')));
      }
      opts.add(_opt('diagnostic_accuracy', tr('Test binaire contre une référence.', 'Binary test against a reference.'), recommended: true,
          cautions: [if (q.design == StudyDesign.caseControl) tr('Recrutement cas-témoins : VPP/VPN non transposables, biais de spectre.', 'Case-control recruitment: PPV/NPV not transferable, spectrum bias.')]));
      if (q.exposureType == ExposureType.continuous) {
        opts.add(_opt('prediction_logistic_internal', tr('Marqueur quantitatif : AUC et choix de seuil ; un seuil choisi sur les données est optimiste.', 'Quantitative marker: AUC and threshold choice; a threshold chosen on the data is optimistic.')));
      }
    case StudyObjective.predictive:
      if (q.population.trim().isEmpty || q.horizon.trim().isEmpty) {
        ask.add(Clarification('horizon', tr('Pour quelle population cible et à quel horizon (p. ex. « 5 ans ») le risque doit-il être prédit ?', 'For which target population and at what horizon (e.g. "5 years") should the risk be predicted?'),
            tr("Un modèle de prédiction n'a de sens que pour une population, un horizon et un usage définis (TRIPOD+AI).", 'A prediction model makes sense only for a defined population, horizon and use (TRIPOD+AI).')));
      }
      if (q.outcomeType == OutcomeType.binary) {
        opts.add(_opt('prediction_logistic_internal', tr('Issue binaire à horizon fixe, suivi complet.', 'Binary outcome at a fixed horizon, complete follow-up.'), recommended: true,
            cautions: [tr("Vérifier la taille d'échantillon (Riley) avant d'ajuster.", 'Check the sample size (Riley) before fitting.'), tr('Ne pas sélectionner les prédicteurs sur les valeurs de p.', 'Do not select predictors on p-values.')]));
        opts.add(_opt('external_validation', tr("Un modèle existe déjà (publié ou développé ailleurs) : l'évaluer sur vos données avant d'en développer un nouveau.", 'A model already exists (published or developed elsewhere): evaluate it on your data before developing a new one.')));
      } else if (q.outcomeType == OutcomeType.timeToEvent) {
        opts.add(_opt('prediction_cox_internal', tr('Issue avec censure : modèle pronostique de Cox, risque prédit à un horizon fixé, validation interne par bootstrap.', 'Censored outcome: Cox prognostic model, risk predicted at a fixed horizon, internal validation by bootstrap.'),
            recommended: true,
            cautions: [tr("Choisir l'horizon dans la plage du suivi, avant l'analyse.", 'Choose the horizon within the follow-up range, before the analysis.'),
              tr("Vérifier les événements par paramètre ; la validation externe reste nécessaire avant tout usage.", 'Check events per parameter; external validation is still needed before any use.')]));
        opts.add(_opt('external_validation_cox', tr("Un modèle pronostique existe déjà : l'évaluer sur vos données avant d'en développer un nouveau.", 'A prognostic model already exists: evaluate it on your data before developing a new one.')));
      }
    case StudyObjective.explanatory:
    case StudyObjective.unknown:
      _explanatory(q, ask, opts, notes);
  }
  return Advice(ask, opts, notes);
}

Clarification _competingQuestion() => Clarification('competingRisk',
    tr('Un autre événement (p. ex. le décès) peut-il empêcher l\'événement étudié de survenir ?', 'Can another event (e.g. death) prevent the studied event from occurring?'),
    tr('Si oui, 1 − Kaplan-Meier surestime l\'incidence : il faut l\'incidence cumulée (Aalen-Johansen) et, pour l\'ajustement, le modèle de Fine-Gray.', 'If so, 1 − Kaplan-Meier overestimates the incidence: the cumulative incidence (Aalen-Johansen) is needed and, for adjustment, the Fine-Gray model.'));

void _explanatory(ResearchQuestion q, List<Clarification> ask, List<MethodOption> opts, List<String> notes) {
  if (q.design == StudyDesign.unknown) {
    ask.add(Clarification('design', tr("Quel est le plan d'étude : essai randomisé, cohorte, transversal, cas-témoins ?", 'What is the study design: randomized trial, cohort, cross-sectional, case-control?'),
        tr("Le plan conditionne la mesure d'association légitime (RR impossible en cas-témoins) et le niveau de preuve causale.", 'The design determines the legitimate measure of association (no RR in case-control studies) and the level of causal evidence.')));
  }
  if (q.exposureType == ExposureType.unknown) {
    ask.add(Clarification('exposureType', tr("L'exposition (ou le facteur comparé) est-elle binaire, qualitative à plusieurs modalités ou quantitative ?", 'Is the exposure (or compared factor) binary, categorical with several levels, or quantitative?'),
        tr('Détermine le nombre de groupes et la méthode.', 'Determines the number of groups and the method.')));
  }
  if (q.pairing == Pairing.unknown) {
    ask.add(Clarification('pairing', tr('Les observations comparées sont-elles indépendantes (sujets différents) ou appariées (mêmes sujets mesurés deux fois, paires appariées) ?', 'Are the compared observations independent (different subjects) or paired (same subjects measured twice, matched pairs)?'),
        tr('Ignorer un appariement fausse les erreurs standard.', 'Ignoring pairing distorts the standard errors.')));
  }
  if (q.needsAdjustment == null && q.design != StudyDesign.rct) {
    ask.add(Clarification('needsAdjustment', tr("Des facteurs de confusion doivent-ils être pris en compte (variables liées à la fois à l'exposition et à l'issue) ?", 'Must confounders be accounted for (variables related to both the exposure and the outcome)?'),
        tr('Une comparaison brute dans une étude observationnelle est exposée à la confusion.', 'A crude comparison in an observational study is exposed to confounding.')));
  }
  if (q.pairing == Pairing.repeated) {
    switch (q.outcomeType) {
      case OutcomeType.continuous:
        opts.add(_opt('lmm_longitudinal', tr('Issue quantitative mesurée plusieurs fois : intercept (et pente) aléatoires par sujet ; utilise toutes les mesures, valide sous MAR.', 'Quantitative outcome measured several times: random intercept (and slope) per subject; uses all measurements, valid under MAR.'), recommended: true,
            cautions: [tr('L\'effet du traitement sur l\'évolution est l\'interaction temps × traitement.', 'The treatment effect on the evolution is the time × treatment interaction.')]));
        opts.add(_opt('gee', tr('Effet moyen dans la population avec erreurs types robustes (≥ 40 sujets, données manquantes MCAR).', 'Population-average effect with robust standard errors (≥ 40 subjects, MCAR missing data).')));
      case OutcomeType.binary:
      case OutcomeType.count:
        opts.add(_opt('gee', tr('Issue ${q.outcomeType == OutcomeType.binary ? 'binaire' : 'de comptage'} répétée : GEE (OR ou RR moyens dans la population, variance robuste).', 'Repeated ${q.outcomeType == OutcomeType.binary ? 'binary' : 'count'} outcome: GEE (population-average ORs or RRs, robust variance).'), recommended: true));
        opts.add(_opt('glmm_longitudinal', tr('Effet pour un même sujet (OR ou RR conditionnels, plus éloignés de 1 que ceux des GEE) : modèle mixte à intercept aléatoire.', 'Effect for the same subject (conditional ORs or RRs, further from 1 than GEE ones): random-intercept mixed model.')));
        notes.add(tr('GEE et modèle mixte répondent à deux questions : effet moyen dans la population (GEE) ou effet pour un même sujet (modèle mixte).', 'GEE and the mixed model answer two questions: population-average effect (GEE) or effect for the same subject (mixed model).'));
      default:
        notes.add(tr('Mesures répétées pour ce type d\'issue : résumer chaque sujet (pente, aire sous la courbe, dernier état) puis appliquer un test simple.', 'Repeated measures for this outcome type: summarize each subject (slope, area under the curve, last state), then apply a simple test.'));
    }
    return;
  }
  final paired = q.pairing == Pairing.paired;
  final adjust = q.needsAdjustment == true;
  final multi = q.exposureType == ExposureType.categorical || (q.groups ?? 2) > 2;

  switch (q.outcomeType) {
    case OutcomeType.binary:
      if (paired) {
        opts.add(_opt('mcnemar', tr('Issue binaire mesurée deux fois sur les mêmes sujets.', 'Binary outcome measured twice on the same subjects.'), recommended: true));
        break;
      }
      if (q.exposureType == ExposureType.binary && !adjust) {
        opts.add(_opt('two_by_two', tr('Association brute entre deux variables binaires.', 'Crude association between two binary variables.'), recommended: true));
      }
      if (q.exposureType == ExposureType.categorical && !adjust) {
        opts.add(_opt('chi_square_rxc', tr('Exposition à plus de deux modalités, analyse brute.', 'Exposure with more than two levels, crude analysis.')));
      }
      if (adjust || q.exposureType == ExposureType.continuous) {
        if (q.design == StudyDesign.caseControl) {
          opts.add(_opt('logistic_regression', tr("Cas-témoins : seul l'OR ajusté est estimable.", 'Case-control: only the adjusted OR is estimable.'), recommended: true));
        } else {
          opts.add(_opt('poisson_robust', tr('Cohorte, essai ou transversal avec issue fréquente (> 10 %) : RR ou RP ajusté, plus lisible.', 'Cohort, trial or cross-sectional study with a common outcome (> 10%): adjusted RR or PR, easier to read.'),
              recommended: q.design == StudyDesign.cohort || q.design == StudyDesign.crossSectional || q.design == StudyDesign.rct));
          opts.add(_opt('logistic_regression', tr("OR ajusté ; proche du RR seulement si l'issue est rare (< 10 %).", 'Adjusted OR; close to the RR only if the outcome is rare (< 10%).'),
              cautions: [tr("Ne pas rédiger l'OR comme un « risque multiplié par » quand l'issue est fréquente.", 'Do not write the OR as "risk multiplied by" when the outcome is common.')]));
        }
        if ((q.expectedEvents ?? 1000) < 50) {
          opts.add(_opt('firth_logistic', tr("Peu d'événements ou séparation : estimations pénalisées.", 'Few events or separation: penalized estimates.'),
              cautions: [tr('Limiter les covariables ; lire les IC profilés, pas les IC de Wald.', 'Limit covariates; read the profile CIs, not the Wald CIs.')]));
        }
      }
    case OutcomeType.continuous:
      if (paired) {
        opts.add(_opt('paired_t_test', tr('Différences appariées approximativement normales (ou n ≥ 30 paires).', 'Approximately normal paired differences (or n ≥ 30 pairs).'), recommended: q.approxNormal != false));
        opts.add(_opt('wilcoxon_signed_rank', tr('Différences très asymétriques avec peu de paires, ou données ordinales.', 'Highly skewed differences with few pairs, or ordinal data.'), recommended: q.approxNormal == false));
        break;
      }
      if (q.exposureType == ExposureType.continuous && !adjust) {
        opts.add(_opt('pearson', tr('Relation entre deux variables quantitatives (linéaire : Pearson ; monotone : Spearman).', 'Relationship between two quantitative variables (linear: Pearson; monotonic: Spearman).')));
        opts.add(_opt('linear_regression', tr("Quantifier la variation de l'issue par unité d'exposition.", 'Quantify the change in outcome per unit of exposure.')));
        break;
      }
      if (adjust) {
        opts.add(_opt('linear_regression', tr('Différence de moyennes ajustée sur les facteurs de confusion.', 'Difference in means adjusted for confounders.'), recommended: true));
      } else if (multi) {
        opts.add(_opt('anova_oneway', tr('k > 2 groupes, distribution ~ normale (Welch si variances inégales).', 'k > 2 groups, ~ normal distribution (Welch if variances are unequal).'), recommended: q.approxNormal != false));
        opts.add(_opt('kruskal_wallis', tr('k > 2 groupes, distribution très asymétrique ou ordinale.', 'k > 2 groups, highly skewed or ordinal distribution.'), recommended: q.approxNormal == false));
      } else if (q.exposureType != ExposureType.unknown) {
        opts.add(_opt('t_test_welch', tr("Deux groupes ; Welch par défaut (pas d'hypothèse d'égalité des variances).", 'Two groups; Welch by default (no equal-variance assumption).'), recommended: q.approxNormal != false));
        opts.add(_opt('mann_whitney', tr('Petits effectifs très asymétriques ou issue ordinale.', 'Small, highly skewed samples or ordinal outcome.'), recommended: q.approxNormal == false));
        if (q.approxNormal == null) {
          ask.add(Clarification('approxNormal', tr("La distribution de l'issue est-elle à peu près symétrique, ou chaque groupe compte-t-il au moins 30 sujets ?", 'Is the outcome distribution roughly symmetric, or does each group have at least 30 subjects?'),
              tr('Départage le test t et le test de Mann-Whitney ; à vérifier ensuite sur les données (contrôle).', 'Decides between the t-test and the Mann-Whitney test; to be checked later on the data (data control).')));
        }
      }
    case OutcomeType.ordinal:
      if (paired) {
        opts.add(_opt('wilcoxon_signed_rank', tr('Issue ordinale appariée.', 'Paired ordinal outcome.'), recommended: true));
      } else if (multi) {
        opts.add(_opt('kruskal_wallis', tr('Issue ordinale, k groupes, analyse brute.', 'Ordinal outcome, k groups, crude analysis.'), recommended: !adjust));
      } else {
        opts.add(_opt('mann_whitney', tr('Issue ordinale, deux groupes, analyse brute.', 'Ordinal outcome, two groups, crude analysis.'), recommended: !adjust));
      }
      if (!paired) {
        opts.add(_opt('ordinal_logistic', tr('Issue ordinale ajustée (ou plusieurs facteurs) : un OR par facteur, commun à tous les seuils.', 'Adjusted ordinal outcome (or several factors): one OR per factor, common to all thresholds.'), recommended: adjust,
            cautions: [tr('Vérifier les cotes proportionnelles (comparaison au modèle multinomial fournie).', 'Check proportional odds (comparison with the multinomial model provided).')]));
      }
    case OutcomeType.categorical:
      opts.add(_opt('chi_square_rxc', tr('Issue qualitative à plusieurs modalités, analyse brute.', 'Categorical outcome with several levels, crude analysis.'), recommended: !adjust));
      if (adjust) opts.add(_opt('multinomial_logistic', tr('Issue nominale ajustée : un RRR par modalité contre une référence.', 'Adjusted nominal outcome: one RRR per level against a reference.'), recommended: true));
    case OutcomeType.count:
      opts.add(_opt('count_regression', tr('Nombre d\'événements par sujet : rapports de taux (IRR) ; binomiale négative si surdispersion.', 'Number of events per subject: rate ratios (IRR); negative binomial if overdispersion.'), recommended: true,
          cautions: [tr('Indiquer le temps d\'exposition (offset) si les durées d\'observation diffèrent.', 'Give the exposure time (offset) if observation durations differ.')]));
    case OutcomeType.timeToEvent:
      final competing = q.competingRisk == true;
      if (competing) {
        opts.add(_opt('cumulative_incidence', tr('Événement concurrent : incidence cumulée par groupe et test de Gray (et non 1 − Kaplan-Meier).', 'Competing event: cumulative incidence by group and Gray test (not 1 − Kaplan-Meier).'), recommended: !adjust));
        opts.add(_opt('fine_gray', tr('Événement concurrent, analyse ajustée : sHR sur l\'incidence cumulée, avec le Cox spécifique de cause en regard.', 'Competing event, adjusted analysis: sHR on the cumulative incidence, with the cause-specific Cox model alongside.'), recommended: adjust));
      }
      opts.add(_opt('kaplan_meier', tr('Description de la survie et comparaison brute des groupes (log-rank).', 'Description of survival and crude comparison of groups (log-rank).'), recommended: !adjust && !competing,
          cautions: [if (competing) tr('Avec un événement concurrent, 1 − Kaplan-Meier surestime l\'incidence.', 'With a competing event, 1 − Kaplan-Meier overestimates the incidence.')]));
      opts.add(_opt('cox', tr("Délai jusqu'à un événement avec censure ; HR ajusté.", 'Time to an event with censoring; adjusted HR.'), recommended: adjust && !competing,
          cautions: [tr('Vérifier la proportionnalité des risques (test fourni) ; un test non significatif ne la prouve pas.', 'Check proportional hazards (test provided); a non-significant test does not prove it.'),
            if (q.timeVaryingExposure == true)
              tr('Exposition acquise pendant le suivi : la coder en covariable dépendant du temps (intervalles début–fin), jamais à l\'inclusion (biais du temps immortel).', 'Exposure acquired during follow-up: code it as a time-dependent covariate (start–stop intervals), never at inclusion (immortal time bias).'),
            if (competing) tr('Avec un événement concurrent, le HR de Cox est spécifique de cause (vitesse de survenue), pas un effet sur l\'incidence.', 'With a competing event, the Cox HR is cause-specific (rate of occurrence), not an effect on the incidence.')]));
      if (q.competingRisk == null) ask.add(_competingQuestion());
      if (q.timeVaryingExposure == null) {
        ask.add(Clarification('timeVaryingExposure', tr('L\'exposition peut-elle survenir ou changer pendant le suivi (traitement commencé plus tard, greffe, hospitalisation) ?', 'Can the exposure occur or change during follow-up (treatment started later, transplant, hospitalization)?'),
            tr('Une exposition acquise pendant le suivi, codée à l\'inclusion, crée un biais du temps immortel ; elle doit être une covariable dépendant du temps.', 'An exposure acquired during follow-up, coded at inclusion, creates immortal time bias; it must be a time-dependent covariate.')));
      }
      notes.add(tr('Planification : l\'atelier de puissance calcule les événements et patients nécessaires (Freedman, Schoenfeld).', 'Planning: the power workshop computes the events and patients needed (Freedman, Schoenfeld).'));
      notes.add(tr('Ne pas analyser un délai censuré comme une issue binaire sans horizon commun de suivi complet.', 'Do not analyse a censored time as a binary outcome without a common horizon of complete follow-up.'));
    case OutcomeType.unknown:
      break;
  }
  if (q.design != StudyDesign.rct && q.design != StudyDesign.unknown && q.objective == StudyObjective.explanatory) {
    notes.add(tr('Plan observationnel : une association, même ajustée, ne suffit pas à établir un effet causal (confusion résiduelle, biais de sélection, sens causal).', 'Observational design: an association, even adjusted, is not enough to establish a causal effect (residual confounding, selection bias, causal direction).'));
  }
  if (opts.length > 1) {
    notes.add(tr("Plusieurs approches sont défendables : leurs conditions sont indiquées ; le choix doit être fixé dans le plan d'analyse AVANT de voir les résultats.", 'Several approaches are defensible: their conditions are given; the choice must be fixed in the analysis plan BEFORE seeing the results.'));
  }
}
