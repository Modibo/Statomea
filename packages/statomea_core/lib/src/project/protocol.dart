/// Du texte au projet : déduction des caractéristiques d'une question de recherche ou d'un protocole (règles
/// explicites, sans modèle de langage), puis feuille de route des 10 étapes.
///  - [inferQuestion] : plan, objectif, type d'issue et d'exposition, appariement, ajustement, risques concurrents,
///    éléments PICO et horizon, chacun avec le passage qui le justifie ;
///  - [protocolFromText] : sections d'un protocole (titre, objectif, population, intervention, comparateur, critère de
///    jugement, schéma, analyse statistique, effectif) ;
///  - [applyInference] : complète la question SANS écraser ce que le chercheur a déclaré ;
///  - [draftAnalysisPlan] et [projectRoadmap] : plan d'analyse rédigé et 10 étapes dans l'ordre, avec ce que
///    l'application propose à chacune.
/// Ces déductions sont des propositions à vérifier : l'application les signale comme telles.
library;

import '../advisor/advisor.dart';
import '../advisor/registry.dart';
import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart' show StatInputError;
import 'project.dart';

/// Une déduction : champ, valeur lisible, passage du texte qui la justifie.
class Inference {
  final String field, value, evidence;
  const Inference(this.field, this.value, this.evidence);
}

class QuestionInference {
  final StudyDesign? design;
  final StudyObjective? objective;
  final OutcomeType? outcomeType;
  final ExposureType? exposureType;
  final Pairing? pairing;
  final DataLevel? dataLevel;
  final bool? needsAdjustment, competingRisk, agreement, timeVaryingExposure;
  final String? population, exposure, comparator, outcome, horizon;
  final bool? referenceStandard;
  final List<Inference> reasons;
  const QuestionInference(
      {this.referenceStandard,
      this.design,
      this.objective,
      this.outcomeType,
      this.exposureType,
      this.pairing,
      this.dataLevel,
      this.needsAdjustment,
      this.competingRisk,
      this.agreement,
      this.timeVaryingExposure,
      this.population,
      this.exposure,
      this.comparator,
      this.outcome,
      this.horizon,
      this.reasons = const []});
  bool get isEmpty => reasons.isEmpty;
}

String _norm(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'");

/// Premier passage du texte (≤ 60 caractères autour) qui correspond à [re] dans [n] (texte normalisé), ou null.
String? _hit(String original, String n, RegExp re) {
  final m = re.firstMatch(n);
  if (m == null) return null;
  final s = (m.start - 20).clamp(0, original.length), e = (m.end + 20).clamp(0, original.length);
  return original.length == n.length ? original.substring(s, e).trim() : m.group(0)!;
}

String _clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[,;:\- ]+|[,;:\-?. ]+$'), '');

/// Déduit les caractéristiques d'une question (ou d'un protocole) à partir de son texte.
QuestionInference inferQuestion(String text) {
  final o = text.replaceAll('’', "'");
  final n = _norm(o);
  final reasons = <Inference>[];
  String? ev(RegExp re) => _hit(o, n, re);

  // Plan d'étude (le plus spécifique d'abord).
  StudyDesign? design;
  DataLevel? level;
  final designRules = <(StudyDesign, RegExp)>[
    (StudyDesign.systematicReview, RegExp(r"meta-?analys|revue systematique|systematic review")),
    (StudyDesign.diagnosticAccuracy, RegExp(r"sensibilite|specificite|valeurs? predictives?|performances? diagnostiques?|precision diagnostique|test diagnostique|diagnostic accuracy|sensitivity|specificity")),
    (StudyDesign.rct, RegExp(r"randomis|randomiz|essai (clinique )?controle|essai clinique|controlled trial|\brct\b|tirage au sort")),
    (StudyDesign.caseControl, RegExp(r"cas[- ]temoins?|case[- ]control")),
    (StudyDesign.cohort, RegExp(r"cohorte|cohort|suivi (prospectif|retrospectif)|prospective|retrospective|suivis? pendant|followed (up )?for")),
    (StudyDesign.crossSectional, RegExp(r"transversal|cross[- ]sectional|enquete|survey|prevalence")),
  ];
  for (final (d, re) in designRules) {
    final e = ev(re);
    if (e != null) {
      design = d;
      reasons.add(Inference('design', designLabel(d), e));
      break;
    }
  }
  if (design == StudyDesign.systematicReview) {
    level = DataLevel.aggregatedStudies;
  } else if (design != null) {
    level = DataLevel.individual;
  }

  // Accord entre deux méthodes de mesure.
  final agreeEv = ev(RegExp(r"accord entre|concordance entre|comparaison de (deux )?methodes|deux methodes de (mesure|dosage)|interchangeab|agreement between|method comparison"));
  final agreement = agreeEv != null ? true : null;
  if (agreeEv != null) reasons.add(Inference('agreementQuestion', tr('accord entre deux méthodes', 'agreement between two methods'), agreeEv));

  // Objectif.
  StudyObjective? objective;
  final objRules = <(StudyObjective, RegExp)>[
    (StudyObjective.predictive, RegExp(r"predire|prediction|predict|score de risque|risk score|modele pronostique|prognostic model|identifier les patients a risque")),
    (StudyObjective.diagnostic, RegExp(r"sensibilite|specificite|valeurs? predictives?|performances? diagnostiques?|diagnostic accuracy|sensitivity|specificity")),
    (StudyObjective.explanatory, RegExp(r"effet|efficacite|impact|associe|association|facteurs? de risque|reduit|diminue|augmente|ameliore|compar|versus|\bvs\b|influence|cause|effect|efficacy|associated|reduce|increase|improve")),
    (StudyObjective.descriptive, RegExp(r"prevalence|incidence|frequence|decrire|estimer la proportion|quelle (est la )?proportion|combien de|describe|how many|proportion of")),
  ];
  for (final (ob, re) in objRules) {
    final e = ev(re);
    if (e != null) {
      objective = ob;
      reasons.add(Inference('objective', objectiveLabel(ob), e));
      break;
    }
  }
  if (objective == null && design == StudyDesign.diagnosticAccuracy) objective = StudyObjective.diagnostic;
  if (objective == null && agreement == true) objective = StudyObjective.descriptive;

  // Type d'issue.
  OutcomeType? outcome;
  final outRules = <(OutcomeType, RegExp)>[
    (OutcomeType.timeToEvent, RegExp(r"survie|delai (de|jusqu|avant)|temps jusqu|au cours du suivi|time to|survival|time until|sans recidive|sans progression|disease[- ]free|progression[- ]free")),
    (OutcomeType.count, RegExp(r"nombre (de|d') ?(episodes|crises|hospitalisations|exacerbations|evenements|visites|admissions)|nombre moyen d|taux d'incidence|number of (episodes|events|admissions|visits)|counts?\b")),
    (OutcomeType.ordinal, RegExp(r"stade|grade (\d|de)|echelle de likert|score (faible|moyen|eleve)|leger, modere|mild, moderate|ordinal")),
    (OutcomeType.binary, RegExp(r"risque (de|d')|risk of|survenue|deces|mortalite|guerison|reussite|echec|infection|recidive|rechute|complication|hospitalisation|reponse au traitement|proportion|prevalence|death|mortality|cure|success|failure|relapse|occurrence|odds")),
    (OutcomeType.continuous, RegExp(r"moyenne|concentration|pression arterielle|glycemie|hba1c|cholesterol|poids|imc|taille|tension|creatinine|hemoglobine|score|niveau de|duree de sejour|mean|level of|blood pressure|weight|length of stay")),
  ];
  for (final (t, re) in outRules) {
    final e = ev(re);
    if (e != null) {
      outcome = t;
      reasons.add(Inference('outcomeType', outcomeTypeLabel(t), e));
      break;
    }
  }
  if (outcome == null && agreement == true) outcome = OutcomeType.continuous;
  if (outcome == null && design == StudyDesign.diagnosticAccuracy) {
    outcome = OutcomeType.binary;
    reasons.add(Inference('outcomeType', tr('binaire (malade / non malade)', 'binary (diseased / not diseased)'), designLabel(design!)));
  }

  // Exposition.
  ExposureType? exposure;
  final ex3 = ev(RegExp(r"(trois|3|quatre|4|plusieurs) (groupes|bras|traitements|doses)|(three|3|four|4|several) (groups|arms|treatments|doses)|selon le stade|by stage"));
  final exC = ev(RegExp(r"dose|par (augmentation|unite)|selon (l'|le |la )?(age|niveau|taux|dose|imc)|per (unit|increase)|continuous exposure|relation dose"));
  final ex2 = ev(RegExp(r"versus|\bvs\.?\b|contre |par rapport (a|au|aux)|compare[es]? (a|au|aux|avec)|compared (with|to)|exposes?|non[- ]exposes?|traites?|placebo|groupe (controle|temoin)|control group"));
  if (ex3 != null) {
    exposure = ExposureType.categorical;
    reasons.add(Inference('exposureType', tr('qualitative > 2', 'categorical > 2'), ex3));
  } else if (exC != null) {
    exposure = ExposureType.continuous;
    reasons.add(Inference('exposureType', 'quantitative', exC));
  } else if (ex2 != null || design == StudyDesign.rct || design == StudyDesign.caseControl) {
    exposure = ExposureType.binary;
    reasons.add(Inference('exposureType', tr('binaire', 'binary'), ex2 ?? designLabel(design!)));
  }

  // Norme de référence (diagnostic).
  final refEv = design == StudyDesign.diagnosticAccuracy ? ev(RegExp(r"par rapport (a|au|aux)|reference|etalon|gold standard|reference standard|compared (with|to)")) : null;

  // Appariement.
  Pairing? pairing;
  final rep = ev(RegExp(r"mesures repetees|suivi longitudinal|a chaque visite|mesure(e|es)? (a|aux) (plusieurs|chaque)|repeated measures|longitudinal"));
  final pair = ev(RegExp(r"avant et apres|avant/apres|avant-apres|apparie|meme(s)? (sujets?|patients?)|cross-?over|before and after|paired|matched"));
  if (rep != null) {
    pairing = Pairing.repeated;
    reasons.add(Inference('pairing', tr('répétées', 'repeated'), rep));
  } else if (pair != null) {
    pairing = Pairing.paired;
    reasons.add(Inference('pairing', tr('appariées', 'paired'), pair));
  } else if (design != StudyDesign.systematicReview) {
    pairing = Pairing.independent;
  }
  level ??= DataLevel.individual;

  // Ajustement : nécessaire pour un objectif explicatif hors essai randomisé.
  bool? adjust;
  final adjEv = ev(RegExp(r"ajust|facteurs? de confusion|confond|adjusted|confounder"));
  if (adjEv != null) {
    adjust = true;
    reasons.add(Inference('needsAdjustment', tr('oui', 'yes'), adjEv));
  } else if (objective == StudyObjective.explanatory && design != null) {
    adjust = design != StudyDesign.rct;
    if (adjust) reasons.add(Inference('needsAdjustment', tr('oui (étude observationnelle)', 'yes (observational study)'), designLabel(design)));
  }

  bool? competing, timeVarying;
  final compEv = ev(RegExp(r"risques? concurrents?|evenement concurrent|deces (comme|en tant qu'?) (evenement )?concurrent|competing (risk|event)"));
  if (compEv != null) {
    competing = true;
    reasons.add(Inference('competingRisk', tr('oui', 'yes'), compEv));
  }
  final tvEv = ev(RegExp(r"pendant le suivi|en cours de suivi|greffe|time[- ]varying|during follow[- ]up"));
  if (tvEv != null && outcome == OutcomeType.timeToEvent) {
    timeVarying = true;
    reasons.add(Inference('timeVaryingExposure', tr('oui', 'yes'), tvEv));
  }

  // PICO et horizon (première phrase interrogative, sinon tout le texte). Les motifs portent sur le texte normalisé
  // (sans accents), le passage est repris dans le texte d'origine aux mêmes positions.
  final sentence = RegExp(r"[^.?!\n]*\?").firstMatch(o)?.group(0) ?? o;
  final ns = _norm(sentence);
  final sameLength = ns.length == sentence.length;
  String? grab(RegExp re, int group) {
    final m = re.firstMatch(ns);
    if (m == null || m.group(group) == null) return null;
    final g = m.group(group)!;
    final start = m.start + m.group(0)!.indexOf(g);
    final txt = sameLength ? sentence.substring(start, start + g.length) : g;
    final c = _clean(txt
        .replaceFirst(RegExp(r"^(?:(?:d'une?|de la|du|des|un|une|la|le|les|the|an?)\s+|(?:de l'|d'|l'))", caseSensitive: false), '')
        .replaceFirst(RegExp(r"^(le |la )?(risque|risk) (de |d'|of )", caseSensitive: false), ''));
    return c.isEmpty ? null : c;
  }

  const stop = r"(?=\s+(?:est|sont|a|ont|reduit|diminue|augmente|ameliore|previent|modifie|influence|chez|parmi|dans|sur|pour|a|au|selon|is|are|has|have|does|do|reduce|reduces|increase|increases|improve|improves|prevent|affect|in|among|on|for|at|after|compared|versus|vs)\b|-t-|-(?:il|elle|ils|elles)\b|[,?;()]|$)";
  // Population : « de 40 à 70 ans » fait partie de la population (pas d'arrêt sur « à » suivi d'un nombre).
  final stopPop = stop.replaceAll('|a|', r'|a(?!\s+\d)|');
  final population = grab(RegExp(r"\b(?:chez|parmi|in|among)\s+(?:les|des|l'|la|le)?\s*([^,?;()]+?)" + stopPop), 1);
  const art = r"(?:les|la|le|l'|un|une|des|du|de la|the|a|an)?\s*";
  // Comparaison explicite « A versus B ».
  final cmp = RegExp(art + r"([^,?;():]{3,60}?)\s+(?:versus|vs\.?|contre|par rapport (?:a|au|aux)|comparee?s? (?:a|au|aux|avec)|compared (?:with|to))\s+" + art + r"([^,?;()]{2,60}?)" + stop).firstMatch(ns);
  String? exposureTxt, comparator;
  if (cmp != null) {
    exposureTxt = grab(RegExp(RegExp.escape(cmp.group(1)!)), 0);
    comparator = grab(RegExp(RegExp.escape(cmp.group(2)!)), 0);
    // Diagnostic : le test évalué suit « sensibilité … du » (« la sensibilité du test rapide du paludisme »).
    final cut = RegExp(r"^.*?(?:sensibilite|specificite|performances?|precision|valeurs? predictives?|sensitivity|specificity|accuracy)[^,?;]*?\b(?:du|de la|de l'|des|of the|of)\s+", caseSensitive: false).firstMatch(_norm(exposureTxt ?? ''));
    if (cut != null && exposureTxt != null && design == StudyDesign.diagnosticAccuracy) exposureTxt = exposureTxt.substring(cut.end);
    // Groupe trop long (phrase entière) : chercher le sujet par les autres motifs.
    if (exposureTxt != null && exposureTxt.split(' ').length > 6) exposureTxt = null;
  }
  exposureTxt ??= grab(RegExp(r"(?:effet|efficacite|impact|influence|apport|effect|efficacy|impact|influence) (?:d[eu]s?|de l'|de la|of)?\s*([^,?;()]{3,60}?)\s+(?:sur|on)\b"), 1) ??
      grab(RegExp(art + r"([^,?;()]{3,60}?)\s+(?:est|sont)(?:-(?:il|elle|ils|elles))?\s+(?:elle |il )?associee?s?"), 1) ??
      grab(RegExp(r"\b(?:does|do|did|is|are)\s+" + art + r"([^,?;()]{3,50}?)\s+(?:increase|reduce|decrease|improve|affect|prevent|cause|lower|raise|associated)"), 1) ??
      grab(RegExp(art + r"([^,?;()]{3,50}?)\s+(?:reduit|diminue|augmente|ameliore|previent|modifie)(?:-t)?-(?:il|elle|ils|elles)"), 1);
  final outcomeTxt = grab(RegExp(r"(?:reduit|diminue|augmente|ameliore|previent|modifie|influence|reduce|reduces|increase|increases|improve|improves|prevent|prevents|affect|affects|lower|lowers)(?:-t)?(?:-(?:il|elle|ils|elles))?\s+" + art + r"([^,?;()]{3,70}?)" + stop), 1) ??
      grab(RegExp(r"associee?s? (?:a|au|aux|with)\s+(?:une |un |a |an )?(?:baisse|hausse|augmentation|diminution|reduction|amelioration|decrease|increase|reduction|improvement)?\s*(?:de la |de l'|du |des |de |d'|in |of )?([^,?;()]{3,70}?)" + stop), 1) ??
      grab(RegExp(r"\b(?:risque|risk) (?:de|d'|of)\s*([^,?;()]{3,60}?)" + stop), 1) ??
      grab(RegExp(r"\b(?:prevalence|incidence|frequence|frequency|proportion) (?:de la |de l'|du |des |de |d'|of )?([^,?;()]{2,60}?)" + stop), 1) ??
      grab(RegExp(r"\b(?:sur|on)\s+" + art + r"([^,?;()]{3,70}?)" + stop), 1);
  final horizon = RegExp(r"(?:a|à|au bout de|apres|après|pendant|sur|at|after|within|over)\s+(\d+\s*(?:jours?|semaines?|mois|ans?|annees?|days?|weeks?|months?|years?))", caseSensitive: false).firstMatch(o)?.group(1);
  for (final (f, v) in [('population', population), ('exposure', exposureTxt), ('comparator', comparator), ('outcome', outcomeTxt), ('horizon', horizon)]) {
    if (v != null && v.isNotEmpty) reasons.add(Inference(f, v, v));
  }
  if (exposure == null && objective == StudyObjective.explanatory && exposureTxt != null) {
    exposure = ExposureType.binary;
    reasons.add(Inference('exposureType', tr('binaire (exposé / non exposé)', 'binary (exposed / unexposed)'), exposureTxt));
  }
  if (refEv != null) reasons.add(Inference('referenceStandardAvailable', tr('oui', 'yes'), refEv));
  return QuestionInference(
    referenceStandard: refEv != null ? true : null,
    design: design,
    objective: objective,
    outcomeType: outcome,
    exposureType: exposure,
    pairing: pairing,
    dataLevel: level,
    needsAdjustment: adjust,
    competingRisk: competing,
    agreement: agreement,
    timeVaryingExposure: timeVarying,
    population: population,
    exposure: exposureTxt,
    comparator: comparator,
    outcome: outcomeTxt,
    horizon: horizon,
    reasons: reasons,
  );
}

/// Complète [q] avec les déductions, sans écraser une valeur déclarée (seuls les champs « inconnus » ou vides
/// sont remplis). Renvoie la question et la liste des champs remplis.
(ResearchQuestion, List<String>) applyInference(ResearchQuestion q, QuestionInference i) {
  final filled = <String>[];
  T? pick<T>(String name, T current, T unknown, T? v) {
    if (v == null || current != unknown) return null;
    filled.add(name);
    return v;
  }

  String? txt(String name, String current, String? v) {
    if (v == null || v.isEmpty || current.trim().isNotEmpty) return null;
    filled.add(name);
    return v;
  }

  final nq = q.copyWith(
    design: pick('design', q.design, StudyDesign.unknown, i.design),
    objective: pick('objective', q.objective, StudyObjective.unknown, i.objective),
    outcomeType: pick('outcomeType', q.outcomeType, OutcomeType.unknown, i.outcomeType),
    exposureType: pick('exposureType', q.exposureType, ExposureType.unknown, i.exposureType),
    pairing: pick('pairing', q.pairing, Pairing.unknown, i.pairing),
    dataLevel: pick('dataLevel', q.dataLevel, DataLevel.unknown, i.dataLevel),
    needsAdjustment: pick<bool?>('needsAdjustment', q.needsAdjustment, null, i.needsAdjustment),
    competingRisk: pick<bool?>('competingRisk', q.competingRisk, null, i.competingRisk),
    timeVaryingExposure: pick<bool?>('timeVaryingExposure', q.timeVaryingExposure, null, i.timeVaryingExposure),
    agreementQuestion: pick<bool>('agreementQuestion', q.agreementQuestion, false, i.agreement),
    referenceStandardAvailable: pick<bool>('referenceStandardAvailable', q.referenceStandardAvailable, false, i.referenceStandard),
    population: txt('population', q.population, i.population),
    exposure: txt('exposure', q.exposure, i.exposure),
    comparator: txt('comparator', q.comparator, i.comparator),
    outcome: txt('outcome', q.outcome, i.outcome),
    horizon: txt('horizon', q.horizon, i.horizon),
  );
  return (nq, filled);
}

String _repr(ResearchQuestion q, String f) => switch (f) {
      'design' => q.design.name,
      'objective' => q.objective.name,
      'outcomeType' => q.outcomeType.name,
      'exposureType' => q.exposureType.name,
      'pairing' => q.pairing.name,
      'dataLevel' => q.dataLevel.name,
      'needsAdjustment' => '${q.needsAdjustment}',
      'competingRisk' => '${q.competingRisk}',
      'timeVaryingExposure' => '${q.timeVaryingExposure}',
      'agreementQuestion' => '${q.agreementQuestion}',
      'referenceStandardAvailable' => '${q.referenceStandardAvailable}',
      'population' => q.population,
      'exposure' => q.exposure,
      'comparator' => q.comparator,
      'outcome' => q.outcome,
      'horizon' => q.horizon,
      _ => '',
    };

ResearchQuestion _reset(ResearchQuestion q, String f) {
  final j = q.toJson();
  const unknown = {
    'design': 'unknown', 'objective': 'unknown', 'outcomeType': 'unknown', 'exposureType': 'unknown', 'pairing': 'unknown', 'dataLevel': 'unknown',
    'needsAdjustment': null, 'competingRisk': null, 'timeVaryingExposure': null, 'agreementQuestion': false, 'referenceStandardAvailable': false,
    'population': '', 'exposure': '', 'comparator': '', 'outcome': '', 'horizon': '',
  };
  if (!unknown.containsKey(f)) return q;
  j[f] = unknown[f];
  return ResearchQuestion.fromJson(j);
}

/// Marque [fields] comme déduits (valeurs actuelles de la question), pour les signaler et les recalculer.
void markInferred(Project p, Iterable<String> fields) {
  for (final f in fields) {
    p.inferred[f] = _repr(p.question, f);
  }
}

/// Complète le projet d'après le texte de sa question : les valeurs déduites auparavant et non modifiées depuis sont
/// recalculées, celles que le chercheur a choisies sont conservées ; le plan d'analyse est proposé s'il est vide ou
/// encore celui proposé automatiquement. Renvoie les champs déduits.
List<String> autoCompleteProject(Project p) {
  var q = p.question;
  for (final e in p.inferred.entries.toList()) {
    if (e.key == 'analysisPlan') continue;
    if (_repr(q, e.key) == e.value) {
      q = _reset(q, e.key);
    } else {
      p.inferred.remove(e.key); // modifié par le chercheur : il garde la main
    }
  }
  final (nq, filled) = applyInference(q, inferQuestion(q.text));
  p.question = nq;
  p.inferred.removeWhere((k, _) => k != 'analysisPlan');
  for (final f in filled) {
    p.inferred[f] = _repr(nq, f);
  }
  final autoPlan = p.inferred['analysisPlan'];
  if (p.analysisPlan.trim().isEmpty || p.analysisPlan == autoPlan) {
    final plan = draftAnalysisPlan(nq);
    p.analysisPlan = plan;
    p.inferred['analysisPlan'] = plan;
  }
  return filled;
}

/// Sections reconnues d'un protocole et question déduite.
class ProtocolDraft {
  final String title;
  final String question;
  final Map<String, String> sections; // clé → texte (objective, population, intervention, comparator, outcome, design, analysis, sampleSize)
  final QuestionInference inference;
  final int? sampleSize;
  const ProtocolDraft({required this.title, required this.question, required this.sections, required this.inference, this.sampleSize});

  /// Question de recherche complète (PICO + caractéristiques) prête pour le projet.
  ResearchQuestion toQuestion() {
    final base = ResearchQuestion(
      text: question,
      population: sections['population'] ?? '',
      exposure: sections['intervention'] ?? '',
      comparator: sections['comparator'] ?? '',
      outcome: sections['outcome'] ?? '',
    );
    return applyInference(base, inference).$1;
  }
}

const _sectionKeys = <String, String>{
  'objective': r"^(question de recherche|objectifs?( principal| primaire)?|but de l'etude|research question|(primary )?objectives?|aims?)\b",
  'population': r"^(population( d'etude| cible)?|criteres d'(inclusion|eligibilite)|participants|study population|eligibility|inclusion criteria)\b",
  'intervention': r"^(intervention|exposition|traitement (etudie|evalue)|exposure|treatment)\b",
  'comparator': r"^(comparateur|groupe (controle|temoin)|comparator|control( group)?)\b",
  'outcome': r"^(criteres? de jugement( principal| primaire)?|critere principal|variable principale|(primary )?(outcome|endpoint)s?)\b",
  'design': r"^(schema|type d'etude|design|methodologie|plan d'etude|methods?|study design)\b",
  'analysis': r"^(analyse statistique|analyses statistiques|plan d'analyse|methodes? statistiques?|statistical (analysis|methods)|analysis plan)\b",
  'sampleSize': r"^(nombre de sujets( necessaires)?|taille (de l'|d')echantillon|calcul (de l'|d')effectif|effectif|sample size)\b",
};

/// Lit le texte d'un protocole (extrait d'un Word ou d'un PDF) : sections, question, déductions.
ProtocolDraft protocolFromText(String raw) {
  final lines = [for (final l in raw.replaceAll('\r', '').split('\n')) l.trim()];
  final nonEmpty = [for (final l in lines) if (l.isNotEmpty) l];
  if (nonEmpty.isEmpty) throw StatInputError('protocol_empty', tr('Le document ne contient pas de texte lisible (document numérisé en image ?).', 'The document contains no readable text (scanned image?).'));
  final sections = <String, String>{};
  String? current;
  final buf = <String, List<String>>{};
  for (final l in lines) {
    if (l.isEmpty) continue;
    final n = _norm(l).replaceAll(RegExp(r'^[\d.ivx)\-–• ]+'), '');
    String? key;
    if (l.length <= 90) {
      for (final e in _sectionKeys.entries) {
        if (RegExp(e.value).hasMatch(n)) {
          key = e.key;
          break;
        }
      }
    }
    if (key != null) {
      current = key;
      buf.putIfAbsent(key, () => []);
      // Texte après le titre sur la même ligne (« Objectif : … »).
      final after = l.contains(':') ? l.substring(l.indexOf(':') + 1).trim() : '';
      if (after.isNotEmpty) buf[key]!.add(after);
      continue;
    }
    if (current != null) buf[current]!.add(l);
  }
  for (final e in buf.entries) {
    final t = e.value.join(' ').trim();
    if (t.isNotEmpty) sections[e.key] = t.length > 1200 ? '${t.substring(0, 1200)}…' : t;
  }
  // Question : première phrase interrogative ; sinon l'objectif ; sinon le titre.
  // Question : les lignes sont recollées (un PDF coupe les phrases en fin de ligne) ; l'intitulé « Question : » est ôté.
  final all = nonEmpty.join(' ');
  var q = RegExp(r"[^.?!]{15,}\?").firstMatch(all)?.group(0)?.trim();
  if (q != null && q.contains(':')) q = q.substring(q.lastIndexOf(':') + 1).trim();
  final objectiveFirst = sections['objective'] == null ? null : RegExp(r"^[^.]+\.?").firstMatch(sections['objective']!)?.group(0);
  final title = nonEmpty.first.length > 160 ? '${nonEmpty.first.substring(0, 160)}…' : nonEmpty.first;
  final question = q ?? objectiveFirst ?? title;
  final basis = [question, ...[sections['objective'], sections['design'], sections['outcome'], sections['intervention'], sections['comparator']].whereType<String>()].join('\n');
  final inf = inferQuestion(basis);
  final ss = RegExp(r"(?:\bn\s*=\s*|\b)(\d{2,6})\s*(?:patients|sujets|participants|malades|subjects|enfants|femmes|hommes)?", caseSensitive: false)
      .allMatches(sections['sampleSize'] ?? '')
      .map((m) => int.tryParse(m.group(1)!))
      .whereType<int>()
      .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
  return ProtocolDraft(title: title, question: question, sections: sections, inference: inf, sampleSize: ss);
}

/// Plan d'analyse rédigé à partir de la méthode recommandée par l'assistant (à relire et compléter).
String draftAnalysisPlan(ResearchQuestion q) {
  final a = advise(q);
  if (a.options.isEmpty) {
    return tr('Plan d\'analyse à rédiger : préciser d\'abord ${a.questions.map((c) => c.field).join(', ')} (étape 1 ou 2).', 'Analysis plan to be written: first specify ${a.questions.map((c) => c.field).join(', ')} (step 1 or 2).');
  }
  final main = a.options.firstWhere((o) => o.recommended, orElse: () => a.options.first);
  final info = methodInfo(main.methodId);
  final alts = [for (final o in a.options) if (o.methodId != main.methodId) o.name];
  final b = StringBuffer()
    ..writeln(tr('Analyse principale : ${main.name} — ${main.whenPreferred}', 'Main analysis: ${main.name} — ${main.whenPreferred}'));
  if (info != null) {
    b
      ..writeln(tr('Données nécessaires : ${info.requiredData}.', 'Data required: ${info.requiredData}.'))
      ..writeln(tr('Conditions à vérifier : ${info.conditions.join(' ; ')}.', 'Conditions to check: ${info.conditions.join('; ')}.'))
      ..writeln(tr('Diagnostics prévus : ${info.diagnostics.join(' ; ')}.', 'Planned diagnostics: ${info.diagnostics.join('; ')}.'))
      ..writeln(tr('Résultat rapporté : ${info.output}.', 'Result reported: ${info.output}.'));
  }
  if (alts.isNotEmpty) b.writeln(tr('Analyses de sensibilité ou alternatives : ${alts.join(' ; ')}.', 'Sensitivity or alternative analyses: ${alts.join('; ')}.'));
  for (final c in main.cautions) {
    b.writeln(tr('Précaution : $c', 'Caution: $c'));
  }
  b.write(tr('Ce plan est fixé AVANT de voir les données ; tout changement ultérieur sera signalé comme tel.', 'This plan is fixed BEFORE seeing the data; any later change will be reported as such.'));
  return b.toString();
}

enum RoadmapStatus { done, proposed, todo }

class RoadmapStep {
  final Step step;
  final RoadmapStatus status;
  final List<String> lines;
  const RoadmapStep(this.step, this.status, this.lines);
}

/// Les 10 étapes dans l'ordre, avec ce que l'application propose à chacune.
List<RoadmapStep> projectRoadmap(Project p) {
  final q = p.question;
  final a = advise(q);
  final main = a.options.isEmpty ? null : a.options.firstWhere((o) => o.recommended, orElse: () => a.options.first);
  final info = main == null ? null : methodInfo(main.methodId);
  RoadmapStatus st(Step s, {bool proposed = false}) => p.completed.contains(s) ? RoadmapStatus.done : (proposed ? RoadmapStatus.proposed : RoadmapStatus.todo);
  String or(String v, String fallback) => v.trim().isEmpty ? fallback : v.trim();
  final missing = tr('à préciser', 'to be specified');
  return [
    RoadmapStep(Step.question, st(Step.question, proposed: q.text.isNotEmpty), [
      tr('Question : ${or(q.text, missing)}', 'Question: ${or(q.text, missing)}'),
      tr('Population : ${or(q.population, missing)} ; exposition : ${or(q.exposure, missing)} ; comparateur : ${or(q.comparator, missing)}.', 'Population: ${or(q.population, missing)}; exposure: ${or(q.exposure, missing)}; comparator: ${or(q.comparator, missing)}.'),
      tr('Critère de jugement : ${or(q.outcome, missing)} (${outcomeTypeLabel(q.outcomeType)})${q.horizon.isEmpty ? '' : ', horizon ${q.horizon}'}.', 'Outcome: ${or(q.outcome, missing)} (${outcomeTypeLabel(q.outcomeType)})${q.horizon.isEmpty ? '' : ', horizon ${q.horizon}'}.'),
    ]),
    RoadmapStep(Step.studyPlan, st(Step.studyPlan, proposed: q.design != StudyDesign.unknown), [
      tr('Plan : ${designLabel(q.design)} ; objectif : ${objectiveLabel(q.objective)}.', 'Design: ${designLabel(q.design)}; objective: ${objectiveLabel(q.objective)}.'),
      if (q.needsAdjustment == true) tr('Facteurs de confusion à prendre en compte : les lister a priori (graphe causal).', 'Confounders to account for: list them a priori (causal graph).'),
      for (final c in a.questions) tr('À préciser : ${c.prompt}', 'To specify: ${c.prompt}'),
    ]),
    RoadmapStep(Step.analysisPlan, st(Step.analysisPlan, proposed: main != null), [
      if (main != null) tr('Méthode principale proposée : ${main.name}.', 'Proposed main method: ${main.name}.') else tr('Méthode : répondre d\'abord aux précisions de l\'étape 2.', 'Method: first answer the clarifications of step 2.'),
      if (a.options.length > 1) tr('Alternatives défendables : ${[for (final o in a.options) if (o != main) o.name].join(' ; ')}.', 'Defensible alternatives: ${[for (final o in a.options) if (o != main) o.name].join('; ')}.'),
      tr('Fixer le plan d\'analyse avant de voir les données.', 'Fix the analysis plan before seeing the data.'),
    ]),
    RoadmapStep(Step.dataControl, st(Step.dataControl, proposed: p.dataset != null), [
      if (info != null) tr('Données nécessaires : ${info.requiredData}.', 'Data required: ${info.requiredData}.'),
      tr('Importer les données (CSV, Excel), déclarer le dictionnaire (types, unités, bornes), puis lancer le contrôle de qualité ; corriger par des corrections justifiées.', 'Import the data (CSV, Excel), declare the dictionary (types, units, bounds), then run the quality control; fix with justified corrections.'),
    ]),
    RoadmapStep(Step.methodChoice, st(Step.methodChoice, proposed: main != null), [
      tr('Déclarer les rôles des variables (issue, exposition, ajustement) : ils préremplissent les calculs.', 'Declare the variable roles (outcome, exposure, adjustment): they prefill the calculations.'),
      if (info != null) tr('Conditions de la méthode : ${info.conditions.join(' ; ')}.', 'Method conditions: ${info.conditions.join('; ')}.'),
    ]),
    RoadmapStep(Step.computation, st(Step.computation), [
      if (main != null) tr('Calculer « ${main.name} » (calculateur prérempli) ; chaque résultat entre dans le journal.', 'Compute "${main.name}" (prefilled calculator); each result enters the log.'),
      if (q.needsAdjustment == true) tr('Analyse ajustée sur les facteurs de confusion choisis a priori.', 'Analysis adjusted for confounders chosen a priori.'),
    ]),
    RoadmapStep(Step.diagnostics, st(Step.diagnostics), [
      if (info != null) tr('Diagnostics : ${info.diagnostics.join(' ; ')}.', 'Diagnostics: ${info.diagnostics.join('; ')}.'),
      tr('Si une condition n\'est pas remplie, revenir à l\'étape 5 (méthode alternative) et le signaler.', 'If a condition is not met, return to step 5 (alternative method) and report it.'),
    ]),
    RoadmapStep(Step.interpretation, st(Step.interpretation), [
      if (info != null) tr('Résultat attendu : ${info.output}.', 'Expected result: ${info.output}.'),
      if (main != null) for (final c in main.cautions) c,
      tr('Rédiger ce que le résultat permet de conclure, et ce qu\'il ne permet pas.', 'Write what the result allows concluding, and what it does not.'),
    ]),
    RoadmapStep(Step.audit, st(Step.audit), [
      tr('Relire le texte avec l\'audit contradictoire (11 familles d\'erreurs : causalité, valeur de p, précision, avant/après…).', 'Review the text with the adversarial audit (11 error families: causality, p-value, precision, before/after…).'),
    ]),
    RoadmapStep(Step.export, st(Step.export), [
      tr('Exporter le rapport (PDF, HTML), le journal et le projet ; joindre la grille de rédaction adaptée (TRIPOD+AI, PROBAST+AI, PRISMA).', 'Export the report (PDF, HTML), the log and the project; attach the relevant reporting checklist (TRIPOD+AI, PROBAST+AI, PRISMA).'),
    ]),
  ];
}
