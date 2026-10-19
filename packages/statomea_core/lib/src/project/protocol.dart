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
import '../data/dataset.dart' show varTypeLabel;
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart' show StatInputError;
import '../version.dart';
import 'planning.dart' show planningParagraphs;
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
    (OutcomeType.timeToEvent, RegExp(r"survie|delai (de|jusqu|avant)|temps jusqu|time to|survival|time until|sans recidive|sans progression|disease[- ]free|progression[- ]free")),
    (OutcomeType.count, RegExp(r"nombre (de|d') ?(episodes|crises|hospitalisations|exacerbations|evenements|visites|admissions)|nombre moyen d|taux d'incidence|number of (episodes|events|admissions|visits)|counts?\b")),
    (OutcomeType.ordinal, RegExp(r"stade|grade (\d|de)|echelle de likert|score (faible|moyen|eleve)|leger, modere|mild, moderate|ordinal")),
    (OutcomeType.binary, RegExp(r"risque (de|d')|risk of|survenue|deces|mortalite|guerison|reussite|echec|infection|recidive|rechute|complication|hospitalisation|reponse au traitement|proportion|prevalence|death|mortality|cure|success|failure|relapse|occurrence|odds|oui ou non|oui/non|yes or no|yes/no|presence (de|d')|facteurs associes a|factors associated with")),
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
    if (e.key == 'analysisPlan' || e.key == 'plannedSampleSize') continue;
    if (_repr(q, e.key) == e.value) {
      q = _reset(q, e.key);
    } else {
      p.inferred.remove(e.key); // modifié par le chercheur : il garde la main
    }
  }
  final (nq, filled) = applyInference(q, inferQuestion(q.text));
  p.question = nq;
  p.inferred.removeWhere((k, _) => k != 'analysisPlan' && k != 'plannedSampleSize');
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
  final Map<String, String> sections; // clé → texte (objective, population, intervention, comparator, outcome, design, analysis, sampleSize, ethics), abrégé à 1 200 caractères

  /// Mêmes rubriques, texte intégral (relecture méthodologique).
  final Map<String, String> fullSections;
  final QuestionInference inference;
  final int? sampleSize;
  const ProtocolDraft({required this.title, required this.question, required this.sections, required this.inference, this.sampleSize, this.fullSections = const {}});

  /// Question telle que lue dans le document (PICO : première phrase de chaque rubrique), avant déductions.
  ResearchQuestion baseQuestion() => ResearchQuestion(
        text: question,
        population: _lead(sections['population']),
        exposure: _lead(sections['intervention']),
        comparator: _lead(sections['comparator']),
        outcome: _lead(sections['outcome']),
      );

  /// Question de recherche complète (PICO + caractéristiques) prête pour le projet.
  ResearchQuestion toQuestion() => applyInference(baseQuestion(), inference).$1;
}

/// Première phrase d'une rubrique (au plus 220 caractères) : le champ PICO reste lisible, le texte complet demeure
/// dans le plan d'analyse et le protocole.
String _lead(String? s) {
  if (s == null || s.isEmpty) return '';
  final m = RegExp(r"^.{20,}?[.;](?=\s|$)").firstMatch(s);
  // Une puce de liste (« … oui ou non b. Critères secondaires ») ne termine pas la phrase.
  final t = (m?.group(0) ?? s).trim().replaceFirst(RegExp(r"\s+[a-h0-9][.)]$"), '');
  return t.length > 220 ? '${t.substring(0, 219).trimRight()}…' : t;
}

const _sectionKeys = <String, String>{
  'objective': r"^(question de recherche|objectifs?( general| principal| primaire)?|but de l'etude|research question|(primary )?objectives?|aims?)\b",
  'population': r"^(population( d'etude| cible| etudiee)?|criteres d'(inclusion|eligibilite|non[- ]?inclusion|exclusion)|criteres de (non[- ]?inclusion|selection|exclusion)|participants|study population|eligibility|inclusion criteria)\b",
  'intervention': r"^(intervention|exposition|traitement (etudie|evalue)|exposure|treatment)\b",
  'comparator': r"^(comparateur|groupe (controle|temoin)|comparator|control( group)?)\b",
  'outcome': r"^(criteres? de jugement( principal| primaire)?|critere principal|variable principale|(primary )?(outcome|endpoint)s?)\b",
  'design': r"^(schema|type (et (design|duree) )?(de l'|d')etude|type d'etude|design|methodologie|plan d'etude|methods?|study design)\b",
  'analysis': r"^(analyses? statistiques?|plan d'analyse|methodes? statistiques?|(gestion|saisie|traitement)( et analyse)? des donnees( et analyse statistique)?|analyse des donnees|statistical (analysis|methods)|analysis plan|data analysis)\b",
  'variables': r"^(variables? (etudiees?|recueillies|cliniques|biologiques|d'interet|mesurees)|parametres (de l'etude|etudies|sociodemographiques|cliniques)|donnees (recueillies|collectees)|recueil des donnees|study variables|variables collected|data collected)\b",
  'period': r"^(periode( d'etude)?|duree( de l'etude)?|calendrier|chronogramme|deroulement|study period|timeline|duration)\b",
  'ethics': r"^(considerations? ethiques?|aspects? (ethiques?|reglementaires?)|ethique|comite d'ethique|ethics|ethical (considerations|aspects))\b",
  'sampleSize': r"^(nombre de sujets?( necessaires?)?|(calcul (de )?(la )?)?taille (de l'|d')echantillon|calcul (de l'|d')effectif|effectif|sample size)\b",
};

/// Intitulés qui ne sont pas des rubriques retenues : ils ferment la rubrique en cours (sinon la page de garde, le
/// chronogramme ou les références s'y ajouteraient).
final _otherHeading = RegExp(r"^(introduction|contexte|justification|resume|abstract|background|rationale|lieu|cadre|materiels? et methodes?|examens|definitions?( operationnelles?)?|budget|resultats attendus|impact attendu|livrables|forces et limites|limites|perspectives|references|bibliographie|annexes?|plan de surveillance|remerciements|expected (results|outcomes)|acknowledg)");

final _refHeading = RegExp(r"^(references?|bibliographie|bibliography)( bibliographiques)?\s*:?$");

/// Normalise un intitulé : numérotation (« 2. », « III. », « b) », « 1.2 »), puces et article initial ôtés.
String _headingKey(String line) {
  var n = _norm(line).trim();
  final num = RegExp(r"^(?:(?:[ivx]+|\d+(?:\.\d+)*|[a-h])[.)]|\d+(?:\.\d+)+|[\-–•*])\s*");
  for (var k = 0; k < 3; k++) {
    final m = num.firstMatch(n);
    if (m == null || m.end == 0) break;
    n = n.substring(m.end);
  }
  return n.replaceFirst(RegExp(r"^(la|le|les|l')\s*"), '');
}

/// Effectif prévu : parmi les entiers de la rubrique, celui que le texte désigne comme nombre de sujets nécessaires
/// (« n = 550 patients », « … ramènera à 110 sujets nécessaires ») ; les décimaux (« 268,889 »), pourcentages, âges et
/// effectifs par centre sont écartés ; à score égal, le dernier cité (après ajustements) l'emporte.
int? _plannedSampleSize(String text) {
  final t = _norm(text);
  int? best;
  var bestScore = -1;
  for (final m in RegExp(r"(?<![\d.,])(\d{1,3}(?:[  ]\d{3})+|\d{2,6})(?![\d]|[.,]\d)").allMatches(t)) {
    final v = int.tryParse(m.group(1)!.replaceAll(RegExp(r"[  ]"), ''));
    if (v == null || v < 10) continue;
    final before = t.substring((m.start - 70).clamp(0, t.length), m.start);
    final after = t.substring(m.end, (m.end + 30).clamp(0, t.length));
    if (RegExp(r"^\s*(%|ans\b|mois|jours|semaines|heures|minutes|pays|centres|par centre|/centre|patients? par centre|patients?/centre|g/l|mmol|mg|ml)").hasMatch(after)) continue;
    // « 10 patients éligibles par mois » : un rythme, pas un effectif.
    if (RegExp(r"^[^.]{0,30}?(par|/)\s*(jour|semaine|mois|an|annee)\b").hasMatch(after)) continue;
    if (RegExp(r"(19|20)\d\d").hasMatch(m.group(1)!) && m.group(1)!.length == 4 && !RegExp(r"^\s*(patients|sujets|participants)").hasMatch(after)) continue;
    var score = 0;
    if (RegExp(r"^\s*(patients|sujets|participants|malades|subjects|enfants|femmes|hommes|individus|cas|blesses)").hasMatch(after)) score += 1;
    if (RegExp(r"(necessaire|final|total|globale|requis|retenu|sera donc|ramener|\bn\s*=\s*$|\bn\s*=\s*\D{0,3}$|soit)").hasMatch(before) || RegExp(r"^\s*\w*\s*necessaires?").hasMatch(after)) score += 3;
    if (score >= bestScore) {
      bestScore = score;
      best = v;
    }
  }
  return best;
}

/// Lit le texte d'un protocole (extrait d'un Word ou d'un PDF) : sections, question, déductions.
ProtocolDraft protocolFromText(String raw) {
  final lines = <String>[];
  for (final l in raw.replaceAll('\r', '').replaceAll(RegExp(r'[\t  ]'), ' ').split('\n')) {
    final t = l.trim().replaceAll(RegExp(r' {2,}'), ' ');
    // Les zones de texte de Word sont parfois écrites deux fois de suite : on ne garde qu'un exemplaire.
    if (t.isNotEmpty && lines.isNotEmpty && lines.last == t) continue;
    lines.add(t);
  }
  // Les références bibliographiques ne servent ni aux rubriques ni à la question.
  final refAt = lines.indexWhere((l) => l.isNotEmpty && l.length <= 40 && _refHeading.hasMatch(_headingKey(l)));
  final body = refAt > 0 ? lines.sublist(0, refAt) : lines;
  final nonEmpty = [for (final l in body) if (l.isNotEmpty) l];
  if (nonEmpty.isEmpty) throw StatInputError('protocol_empty', tr('Le document ne contient pas de texte lisible (document numérisé en image ?).', 'The document contains no readable text (scanned image?).'));
  String? current;
  final buf = <String, List<String>>{};
  String? titleLine;
  var wantTitle = false;
  for (final l in nonEmpty) {
    final n = _headingKey(l);
    if (wantTitle) {
      titleLine = l;
      wantTitle = false;
    }
    final tm = RegExp(r"^(theme|titre( du projet| de l'etude| de la these)?|intitule|title)\s*:?\s*(.*)$").firstMatch(n);
    if (titleLine == null && tm != null && l.length <= 300) {
      final rest = l.contains(':') ? l.substring(l.indexOf(':') + 1).trim() : '';
      if (rest.length >= 10) {
        titleLine = rest;
      } else if (tm.group(3)!.isEmpty) {
        wantTitle = true;
      }
      continue;
    }
    String? key;
    // Un intitulé ne se termine pas par un point (sauf « Objectif : … ») : « Le nombre de sujets nécessaire sera donc
    // n = 550 patients. » est une phrase de la rubrique, pas un titre.
    final headingLike = l.length <= 90 && (l.contains(':') || !RegExp(r"[.;]$").hasMatch(l));
    if (headingLike) {
      for (final e in _sectionKeys.entries) {
        if (RegExp(e.value).hasMatch(n)) {
          key = e.key;
          break;
        }
      }
    }
    if (key != null) {
      current = key;
      // Une rubrique déjà ouverte mais presque vide (cellule d'un chronogramme, sommaire) est remplacée.
      // (Sauf la période : « Période d'étude : avril-décembre 2023 » de la page de garde reste valable.)
      if (!buf.containsKey(key) || (key != 'period' && buf[key]!.join(' ').length < 120)) buf[key] = [];
      // Texte après le titre sur la même ligne (« Objectif : … »).
      final after = l.contains(':') ? l.substring(l.indexOf(':') + 1).trim() : '';
      if (after.isNotEmpty) buf[key]!.add(after);
      continue;
    }
    if (headingLike && _otherHeading.hasMatch(n)) {
      current = null;
      continue;
    }
    if (RegExp(r"^[\d\s./:,%<>≥≤–-]*$").hasMatch(l)) continue;
    if (current != null) buf[current]!.add(l);
  }
  final full = {for (final e in buf.entries) e.key: e.value.join(' ').trim()};
  final sections = <String, String>{
    for (final e in full.entries)
      if (e.value.isNotEmpty) e.key: e.value.length > 1200 ? '${e.value.substring(0, 1200)}…' : e.value,
  };
  // Question : première phrase interrogative ; sinon l'objectif ; sinon le titre.
  // Question : les lignes sont recollées (un PDF coupe les phrases en fin de ligne) ; l'intitulé « Question : » est ôté.
  final all = nonEmpty.join(' ');
  var q = RegExp(r"[^.?!]{15,}\?").firstMatch(all)?.group(0)?.trim();
  if (q != null && q.contains(':')) q = q.substring(q.lastIndexOf(':') + 1).trim();
  final objectiveFirst = sections['objective'] == null ? null : RegExp(r"^[^.]+\.?").firstMatch(sections['objective']!)?.group(0);
  // Titre : « Thème : … » ou « Titre du projet » s'il existe ; sinon la première ligne qui n'est pas une mention de page
  // de garde (auteur, ministère, université, « Protocole de … »).
  final boiler = RegExp(r"^(realise|presente|redige|soutenu|these (dirigee|realisee)|dirige|par\b|republique|ministere|universite|faculte|ecole|institut|departement|promotion|annee|protocole( de| d'|$)|version|code|date|\*+|un peuple)");
  final firstText = nonEmpty.firstWhere((l) => l.length >= 15 && !boiler.hasMatch(_headingKey(l)), orElse: () => nonEmpty.first);
  final t0 = titleLine ?? firstText;
  final title = t0.length > 160 ? '${t0.substring(0, 160)}…' : t0;
  final question = q ?? objectiveFirst ?? title;
  // Le titre dit souvent le plan (« Essai randomisé… », « Étude transversale… »).
  final basis = [question, ...[sections['objective'], sections['design'], sections['outcome'], sections['intervention'], sections['comparator']].whereType<String>(), ?titleLine].join('\n');
  final inf = inferQuestion(basis);
  final ss = full['sampleSize'] == null ? null : _plannedSampleSize(full['sampleSize']!);
  return ProtocolDraft(title: title, question: question, sections: sections, inference: inf, sampleSize: ss, fullSections: {
        for (final e in full.entries)
          if (e.value.isNotEmpty) e.key: e.value,
        // Texte intégral (sans les références), pour les grilles SPIRIT, STROBE, STARD et TRIPOD ; il reste sur l'appareil.
        '_text': () {
          final t = nonEmpty.join('\n');
          return t.length > 200000 ? t.substring(0, 200000) : t;
        }(),
      });
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

  /// Calculateur à ouvrir depuis l'étape (p. ex. calcul d'effectif), identifiant de méthode du registre.
  final String? calculator;
  final Map<String, String> calculatorPresets;
  const RoadmapStep(this.step, this.status, this.lines, {this.calculator, this.calculatorPresets = const {}});
}

/// Calcul d'effectif adapté à la question : calculateur et hypothèses à renseigner.
class SampleSizePlan {
  final String calculator; // identifiant de méthode (calculatorFor dans l'application)
  final String title;
  final List<String> hypotheses;

  /// Préréglages du calculateur (type de calcul, valeurs lues dans le protocole), p. ex. {'type': 'riley'}.
  final Map<String, String> presets;
  const SampleSizePlan(this.calculator, this.title, this.hypotheses, {this.presets = const {}});
}

SampleSizePlan? sampleSizePlan(ResearchQuestion q) {
  if (q.dataLevel == DataLevel.aggregatedStudies || q.design == StudyDesign.systematicReview) return null;
  final a = tr('risque α (souvent 5 %) et puissance (80 à 90 %)', 'α risk (often 5%) and power (80 to 90%)');
  if (q.agreementQuestion) {
    return SampleSizePlan('bland_altman', tr('Accord entre méthodes : au moins 100 échantillons couvrant la plage de mesure (CLSI EP09 : 40 au minimum)', 'Agreement between methods: at least 100 samples covering the measuring range (CLSI EP09: 40 minimum)'),
        [tr('écart acceptable fixé a priori', 'acceptable difference set a priori'), tr('étendue de mesure à couvrir', 'measuring range to cover')]);
  }
  switch (q.objective) {
    case StudyObjective.predictive:
      return SampleSizePlan('sample_size', tr('Modèle de prédiction : effectif minimal de Riley et al. (pmsampsize)', 'Prediction model: Riley et al. minimum sample size (pmsampsize)'),
          [tr('prévalence attendue de l\'issue', 'expected outcome prevalence'), tr('nombre de paramètres candidats', 'number of candidate parameters'), tr('performance attendue (R² de Cox-Snell ou AUC)', 'expected performance (Cox-Snell R² or AUC)')],
          presets: const {'type': 'riley'});
    case StudyObjective.diagnostic:
      return SampleSizePlan('sample_size', tr('Performance diagnostique : précision voulue de la sensibilité et de la spécificité (Buderer)', 'Diagnostic accuracy: desired precision of sensitivity and specificity (Buderer)'),
          [tr('sensibilité et spécificité attendues', 'expected sensitivity and specificity'), tr('prévalence de la maladie', 'disease prevalence'), tr('demi-largeur voulue de l\'IC', 'desired CI half-width')]);
    case StudyObjective.descriptive:
      if (q.outcomeType == OutcomeType.continuous) {
        return SampleSizePlan('sample_size', tr('Estimer une moyenne avec une précision donnée', 'Estimate a mean with a given precision'), [tr('écart-type attendu', 'expected SD'), tr('demi-largeur voulue de l\'IC', 'desired CI half-width')]);
      }
      return SampleSizePlan('sample_size', tr('Estimer une proportion (prévalence) avec une précision donnée', 'Estimate a proportion (prevalence) with a given precision'),
          [tr('proportion attendue', 'expected proportion'), tr('précision voulue (± absolue)', 'desired precision (± absolute)'), tr('effet de plan si sondage en grappes', 'design effect if cluster sampling')],
          presets: const {'type': 'prop'});
    case StudyObjective.explanatory:
    case StudyObjective.unknown:
      switch (q.outcomeType) {
        case OutcomeType.timeToEvent:
          return SampleSizePlan('power_survival', tr('Délai jusqu\'à événement : nombre d\'événements (Schoenfeld) puis de patients (Freedman)', 'Time to event: number of events (Schoenfeld) then patients (Freedman)'),
              [tr('HR cliniquement pertinent', 'clinically relevant HR'), tr('proportion d\'événements attendue dans le groupe témoin', 'expected event proportion in the control group'), a]);
        case OutcomeType.continuous when q.exposureType == ExposureType.continuous:
          return SampleSizePlan('sample_size', tr('Mettre en évidence une corrélation (transformation de Fisher)', 'Detect a correlation (Fisher transformation)'),
              [tr('plus petite corrélation cliniquement pertinente', 'smallest clinically relevant correlation'), a],
              presets: const {'type': 'correlation'});
        case OutcomeType.continuous:
          return SampleSizePlan('power_means', tr('Comparer deux moyennes', 'Compare two means'),
              [tr('différence minimale cliniquement pertinente', 'minimal clinically important difference'), tr('écart-type attendu', 'expected SD'), if (q.pairing == Pairing.paired) tr('corrélation entre mesures appariées', 'correlation between paired measurements'), a]);
        case OutcomeType.binary:
          if (q.design == StudyDesign.caseControl) {
            return SampleSizePlan('power_case_control', tr('Étude cas-témoins', 'Case-control study'),
                [tr('prévalence de l\'exposition chez les témoins', 'exposure prevalence among controls'), tr('OR minimal à détecter', 'minimal OR to detect'), tr('nombre de témoins par cas', 'controls per case'), a]);
          }
          return SampleSizePlan('power_proportions', tr('Comparer deux proportions', 'Compare two proportions'),
              [tr('proportion attendue dans le groupe de référence', 'expected proportion in the reference group'), tr('proportion (ou effet) minimale à détecter', 'minimal proportion (or effect) to detect'), a]);
        default:
          return null;
      }
  }
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
    RoadmapStep(Step.analysisPlan, st(Step.analysisPlan, proposed: main != null), calculator: sampleSizePlan(q)?.calculator, calculatorPresets: sampleSizePlan(q)?.presets ?? const {}, [
      if (main != null) tr('Méthode principale proposée : ${main.name}.', 'Proposed main method: ${main.name}.') else tr('Méthode : répondre d\'abord aux précisions de l\'étape 2.', 'Method: first answer the clarifications of step 2.'),
      if (a.options.length > 1) tr('Alternatives défendables : ${[for (final o in a.options) if (o != main) o.name].join(' ; ')}.', 'Defensible alternatives: ${[for (final o in a.options) if (o != main) o.name].join('; ')}.'),
      if (sampleSizePlan(q) case final ss?) ...[
        tr('Effectif : ${ss.title}.', 'Sample size: ${ss.title}.'),
        tr('Hypothèses à renseigner : ${ss.hypotheses.join(' ; ')}.', 'Hypotheses to provide: ${ss.hypotheses.join('; ')}.'),
      ],
      if (p.inferred['plannedSampleSize'] case final n?) tr('Effectif prévu par le protocole : $n sujets (à confronter au calcul).', 'Sample size planned by the protocol: $n subjects (to compare with the calculation).'),
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

/// Section d'un protocole prérédigé ; les paragraphes commençant par [placeholderPrefix] sont à compléter.
class ProtocolSection {
  final String title;
  final List<String> paragraphs;
  const ProtocolSection(this.title, this.paragraphs);
}

String get placeholderPrefix => tr('[À compléter', '[To complete');
String _todo(String what) => tr('[À compléter : $what]', '[To complete: $what]');

/// Protocole prérédigé à partir du projet (question, plan, effectif, plan d'analyse, variables), avec les rubriques
/// attendues par un comité d'éthique ; ce qui ne peut pas être déduit est marqué « à compléter ».
List<ProtocolSection> protocolOutline(Project p) {
  final q = p.question;
  String or(String v, String what) => v.trim().isEmpty ? _todo(what) : v.trim();
  final ss = sampleSizePlan(q);
  final power = [
    for (final e in p.journal)
      if (e.methodId.startsWith('power_') || e.methodId == 'sample_size' || e.methodId.startsWith('sample_size')) e
  ];
  final ds = p.dataset;
  return [
    ProtocolSection(tr('Identification', 'Identification'), [
      tr('Titre : ${p.title}', 'Title: ${p.title}'),
      tr('Version et date : ${_todo('numéro de version, date')}', 'Version and date: ${_todo('version number, date')}'),
      tr('Investigateur principal et centres : ${_todo('noms, affiliations')}', 'Principal investigator and centres: ${_todo('names, affiliations')}'),
    ]),
    ProtocolSection(tr('Résumé', 'Summary'), [
      tr('Question : ${or(q.text, 'question de recherche')}', 'Question: ${or(q.text, 'research question')}'),
      tr('Schéma : ${designLabel(q.design)} ; objectif : ${objectiveLabel(q.objective)}.', 'Design: ${designLabel(q.design)}; aim: ${objectiveLabel(q.objective)}.'),
      tr('Population : ${or(q.population, 'population étudiée')} ; critère de jugement principal : ${or(q.outcome, 'critère de jugement')}.', 'Population: ${or(q.population, 'study population')}; primary outcome: ${or(q.outcome, 'outcome')}.'),
    ]),
    ProtocolSection(tr('Contexte et justification', 'Background and rationale'), [_todo(tr('état des connaissances, lacune à combler, intérêt pour les patients ; références', 'state of knowledge, gap, interest for patients; references'))]),
    ProtocolSection(tr('Question de recherche et objectifs', 'Research question and objectives'), [
      or(q.text, tr('question de recherche', 'research question')),
      tr('Objectif principal : ${objectiveLabel(q.objective)} — ${or(q.exposure, 'exposition ou intervention')} ${q.comparator.isEmpty ? '' : 'comparé(e) à ${q.comparator} '}sur ${or(q.outcome, 'critère de jugement')}${q.horizon.isEmpty ? '' : ' à ${q.horizon}'}, chez ${or(q.population, 'population')}.',
          'Primary objective: ${objectiveLabel(q.objective)} — ${or(q.exposure, 'exposure or intervention')} ${q.comparator.isEmpty ? '' : 'compared with ${q.comparator} '}on ${or(q.outcome, 'outcome')}${q.horizon.isEmpty ? '' : ' at ${q.horizon}'}, in ${or(q.population, 'population')}.'),
      tr('Objectifs secondaires : ${_todo('objectifs secondaires')}', 'Secondary objectives: ${_todo('secondary objectives')}'),
    ]),
    ProtocolSection(tr('Schéma de l\'étude', 'Study design'), [
      tr('Type d\'étude : ${designLabel(q.design)}.', 'Study type: ${designLabel(q.design)}.'),
      if (q.design == StudyDesign.rct) tr('Randomisation, aveugle et allocation : ${_todo('méthode de randomisation, insu, dissimulation de l\'allocation')}', 'Randomisation, blinding and allocation: ${_todo('randomisation method, blinding, allocation concealment')}'),
      if (q.design == StudyDesign.cohort || q.design == StudyDesign.caseControl) tr('Recueil : ${_todo('prospectif ou rétrospectif, sources des données')}', 'Data collection: ${_todo('prospective or retrospective, data sources')}'),
      tr('Durée de participation et de l\'étude : ${or(q.horizon, 'durée')}', 'Duration of participation and of the study: ${or(q.horizon, 'duration')}'),
    ]),
    ProtocolSection(tr('Population', 'Population'), [
      or(q.population, tr('population étudiée', 'study population')),
      tr('Critères d\'inclusion : ${_todo('critères d\'inclusion')}', 'Inclusion criteria: ${_todo('inclusion criteria')}'),
      tr('Critères de non-inclusion : ${_todo('critères de non-inclusion')}', 'Exclusion criteria: ${_todo('exclusion criteria')}'),
    ]),
    ProtocolSection(tr('Intervention, exposition et comparateur', 'Intervention, exposure and comparator'), [
      tr('Intervention ou exposition : ${or(q.exposure, 'intervention ou exposition')}', 'Intervention or exposure: ${or(q.exposure, 'intervention or exposure')}'),
      tr('Comparateur : ${or(q.comparator, 'comparateur')}', 'Comparator: ${or(q.comparator, 'comparator')}'),
    ]),
    ProtocolSection(tr('Critères de jugement', 'Outcomes'), [
      tr('Critère principal : ${or(q.outcome, 'critère de jugement principal')} (${outcomeTypeLabel(q.outcomeType)})${q.horizon.isEmpty ? '' : ', évalué à ${q.horizon}'} ; mesure : ${_todo('méthode et moment de mesure')}', 'Primary outcome: ${or(q.outcome, 'primary outcome')} (${outcomeTypeLabel(q.outcomeType)})${q.horizon.isEmpty ? '' : ', assessed at ${q.horizon}'}; measurement: ${_todo('method and timing of measurement')}'),
      tr('Critères secondaires : ${_todo('critères secondaires')}', 'Secondary outcomes: ${_todo('secondary outcomes')}'),
    ]),
    ProtocolSection(tr('Nombre de sujets nécessaires', 'Sample size'), [
      if (ss != null) ...[
        ss.title,
        tr('Hypothèses : ${ss.hypotheses.map((h) => '$h = ${_todo('valeur et source')}').join(' ; ')}', 'Hypotheses: ${ss.hypotheses.map((h) => '$h = ${_todo('value and source')}').join('; ')}'),
      ],
      for (final e in power) '${e.methodName} : ${(e.result['interpretation'] as Map?)?['meaning'] ?? ''}',
      if (p.inferred['plannedSampleSize'] case final n?) tr('Effectif prévu : $n sujets.', 'Planned sample size: $n subjects.'),
      if (power.isEmpty && p.inferred['plannedSampleSize'] == null) tr('Effectif retenu : ${_todo('nombre de sujets, majoré des perdus de vue attendus (calcul dans Statoméa)')}', 'Sample size retained: ${_todo('number of subjects, increased for expected losses (calculation in Statoméa)')}'),
    ]),
    ProtocolSection(tr('Plan d\'analyse statistique', 'Statistical analysis plan'), [
      for (final l in p.analysisPlan.split('\n')) if (l.trim().isNotEmpty) l.trim(),
      if (p.analysisPlan.trim().isEmpty) _todo(tr('plan d\'analyse', 'analysis plan')),
      tr('Données manquantes : ${_todo('fréquence attendue, analyse en cas complets ou imputation multiple')}', 'Missing data: ${_todo('expected frequency, complete-case analysis or multiple imputation')}'),
      tr('Logiciel : Statoméa ($engineName $engineVersion), méthodes validées contre R ; journal des calculs et des corrections conservé.', 'Software: Statoméa ($engineName $engineVersion), methods validated against R; log of computations and corrections kept.'),
    ]),
    ProtocolSection(tr('Données recueillies', 'Data collected'), [
      if (ds == null) _todo(tr('liste des variables (type, unité, valeurs possibles)', 'list of variables (type, unit, possible values)'))
      else
        for (final n in ds.names)
          '$n : ${varTypeLabel(ds.dictionary[n]!.type)}${ds.dictionary[n]!.unit.isEmpty ? '' : ' (${ds.dictionary[n]!.unit})'}${ds.dictionary[n]!.label.isEmpty ? '' : ' — ${ds.dictionary[n]!.label}'}',
    ]),
    ProtocolSection(tr('Aspects éthiques et réglementaires', 'Ethical and regulatory aspects'), [
      tr('Avis du comité d\'éthique : ${_todo('comité, numéro d\'avis')}', 'Ethics committee approval: ${_todo('committee, approval number')}'),
      tr('Information et consentement : ${_todo('modalités')}', 'Information and consent: ${_todo('procedures')}'),
      tr('Confidentialité : données pseudonymisées, sans identifiant direct ; ${_todo('conservation, accès, déclaration réglementaire')}', 'Confidentiality: pseudonymised data, no direct identifier; ${_todo('storage, access, regulatory declaration')}'),
    ]),
    ProtocolSection(tr('Calendrier, budget et diffusion', 'Timeline, budget and dissemination'), planningParagraphs(p, _todo)),
  ];
}
