/// Relecture méthodologique d'un projet ou d'un protocole importé : erreurs, incohérences et manques, chacun avec le
/// passage en cause, l'explication et la correction ; les corrections sûres s'appliquent au projet (et sont tracées).
///
/// Règles explicites, sans modèle de langage. Les contrôles portent sur :
///  - la question (éléments PICO, type d'issue, critère principal unique) ;
///  - le plan d'étude (cohérence plan × objectif × issue, langage causal en observationnel) ;
///  - le nombre de sujets (absence de justification, recalcul de la précision d'une proportion et des critères de
///    Riley, majoration pour les pertes, base du calcul cohérente avec l'objectif) ;
///  - le plan d'analyse (ajustement, validation et calibration d'un modèle prédictif, tests appariés au bon nombre de
///    groupes, survie et risques concurrents, données manquantes, multiplicité, effet centre, seuil) ;
///  - l'éthique (protocole importé).
/// Un protocole importé est relu sur SON texte (rubriques conservées dans [Project.protocol]) : la proposition rédigée
/// par Statoméa à l'import n'est pas comptée comme faisant partie du protocole.
library;

import 'dart:math' as math;

import '../advisor/advisor.dart';
import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import '../model/result.dart' show AnalysisResult, StatInputError;
import '../inference/power.dart' show powerTwoMeansD, powerTwoProportionsN;
import '../inference/sample_size.dart' show sampleSizeTwoMeans, sampleSizeTwoProportions;
import '../model/design.dart';
import '../prediction/performance.dart' show rileySampleSize;
import 'project.dart';
import 'protocol.dart';

enum ReviewLevel { error, warning, missing, ok }

String reviewLevelLabel(ReviewLevel l) => switch (l) {
      ReviewLevel.error => tr('Erreur', 'Error'),
      ReviewLevel.warning => tr('À revoir', 'To review'),
      ReviewLevel.missing => tr('Manquant', 'Missing'),
      ReviewLevel.ok => tr('Vérifié', 'Checked'),
    };

/// Correction applicable au projet.
class ReviewFix {
  final String detail; // ce qui sera modifié
  final void Function(Project p) apply;
  const ReviewFix(this.detail, this.apply);
}

class ReviewFinding {
  final String id;
  final ReviewLevel level;
  final Step step;
  final String title;
  final String problem;
  final String correction;
  final String? evidence; // passage du protocole ou du projet
  final ReviewFix? fix;
  final String? calculator; // calculateur à ouvrir (effectif)
  final Map<String, String> calculatorPresets; // valeurs lues dans le protocole, préremplies dans le calculateur
  const ReviewFinding(this.id, this.level, this.step, this.title, this.problem, this.correction,
      {this.evidence, this.fix, this.calculator, this.calculatorPresets = const {}});
}

class ProjectReview {
  final List<ReviewFinding> findings;
  const ProjectReview(this.findings);

  /// Points à traiter (erreurs, puis à revoir, puis manquants ; dans l'ordre des étapes).
  List<ReviewFinding> get problems => [for (final f in findings) if (f.level != ReviewLevel.ok) f]
    ..sort((a, b) => a.level.index != b.level.index ? a.level.index.compareTo(b.level.index) : a.step.index.compareTo(b.step.index));
  List<ReviewFinding> get checked => [for (final f in findings) if (f.level == ReviewLevel.ok) f];
  List<ReviewFinding> get fixable => [for (final f in problems) if (f.fix != null) f];
  int count(ReviewLevel l) => findings.where((f) => f.level == l).length;
}

String _n(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'");

/// Phrase du texte original qui contient la correspondance de [re] dans le texte normalisé (≤ 240 caractères).
String? _quote(String original, RegExp re) {
  final n = _n(original);
  final m = re.firstMatch(n);
  if (m == null) return null;
  if (n.length != original.length) return m.group(0);
  var s = m.start, e = m.end;
  while (s > 0 && !'.!?\n'.contains(original[s - 1]) && m.start - s < 160) {
    s--;
  }
  while (e < original.length && !'.!?\n'.contains(original[e]) && e - m.end < 160) {
    e++;
  }
  if (e < original.length && '.!?'.contains(original[e])) e++;
  final t = original.substring(s, e).trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > 240 ? '${t.substring(0, 239)}…' : t;
}

double? _num(String s) => double.tryParse(s.replaceAll(',', '.'));

String _fmt(double v, [int d = 2]) {
  // Zéros de fin ôtés seulement après la virgule (80 reste 80, et non 8).
  var s = v.toStringAsFixed(d);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return currentLang == Lang.fr ? s.replaceAll('.', ',') : s;
}

final _blockMarker = RegExp(r'(Correction Statoméa|Statoméa correction) — ');

/// Paragraphes ajoutés au plan d'analyse par les corrections (ils comptent dans la relecture d'un protocole importé).
String _correctionBlocks(String plan) {
  final m = _blockMarker.firstMatch(plan);
  return m == null ? '' : plan.substring(m.start);
}

void _appendPlan(Project p, String title, String paragraph) {
  final head = tr('Correction Statoméa', 'Statoméa correction');
  p.analysisPlan = '${p.analysisPlan.trimRight()}${p.analysisPlan.trim().isEmpty ? '' : '\n\n'}$head — $title${tr(' :', ':')}\n$paragraph';
}

const _outcomeWords = r"mortalite|deces|survie|transfusion|hospitalisation|readmission|rechute|recidive|infection|guerison|complications?|amputation|sepsis|choc|remission|reponse au traitement|mortality|death|survival|relapse|recurrence|admission|cure";

/// Relit le projet et renvoie les constats, des plus graves aux vérifications réussies.
ProjectReview reviewProject(Project p) {
  final q = p.question;
  final out = <ReviewFinding>[];
  final imported = p.protocol.isNotEmpty;
  String prot(String k) => p.protocol[k] ?? '';
  bool applied(String id) => p.corrections.any((c) => c.id == id);
  void add(ReviewFinding f) {
    if (f.level == ReviewLevel.ok || f.fix == null || !applied(f.id)) out.add(f);
  }

  final objText = [q.text, prot('objective')].where((s) => s.isNotEmpty).join('\n');
  final planText = imported ? [prot('analysis'), _correctionBlocks(p.analysisPlan)].where((s) => s.isNotEmpty).join('\n') : p.analysisPlan;
  final nPlan = _n(planText);
  bool plan(String re) => RegExp(re).hasMatch(nPlan);
  final allText = [q.text, ...p.protocol.values, p.analysisPlan].join('\n');
  final nAll = _n(allText);
  final inf = inferQuestion([q.text, prot('objective'), prot('design'), prot('outcome')].where((s) => s.isNotEmpty).join('\n'));
  final observational = q.design == StudyDesign.cohort || q.design == StudyDesign.caseControl || q.design == StudyDesign.crossSectional;

  // ---- 1. Question ----
  if (q.text.trim().isEmpty) {
    add(ReviewFinding('question_text', ReviewLevel.missing, Step.question, tr('Question de recherche absente', 'Research question missing'),
        tr('Sans question écrite, ni le plan, ni l\'effectif, ni l\'analyse ne peuvent être justifiés.', 'Without a written question, neither the design, the sample size nor the analysis can be justified.'),
        tr('Écrire la question à l\'étape 1 (population, exposition, comparateur, critère de jugement, horizon).', 'Write the question at step 1 (population, exposure, comparator, outcome, horizon).')));
  }
  if (q.population.trim().isEmpty) {
    final v = inf.population;
    add(ReviewFinding('population', ReviewLevel.missing, Step.question, tr('Population non définie', 'Population not defined'),
        tr('La population (et ses critères d\'inclusion et de non-inclusion) conditionne la portée des résultats.', 'The population (and its inclusion and exclusion criteria) determines how far the results apply.'),
        v == null ? tr('Décrire la population et les critères d\'inclusion à l\'étape 1.', 'Describe the population and inclusion criteria at step 1.') : tr('Population proposée : « $v ».', 'Proposed population: "$v".'),
        fix: v == null ? null : ReviewFix(tr('Population : $v', 'Population: $v'), (p) => p.question = p.question.copyWith(population: v))));
  }
  if (q.outcome.trim().isEmpty) {
    final v = inf.outcome;
    add(ReviewFinding('outcome', ReviewLevel.missing, Step.question, tr('Critère de jugement principal non défini', 'Primary outcome not defined'),
        tr('Le critère principal fixe le type d\'analyse et le calcul d\'effectif.', 'The primary outcome sets the type of analysis and the sample-size calculation.'),
        v == null ? tr('Définir un critère principal unique, mesurable, avec son horizon.', 'Define a single, measurable primary outcome with its time horizon.') : tr('Critère proposé : « $v ».', 'Proposed outcome: "$v".'),
        fix: v == null ? null : ReviewFix(tr('Critère de jugement : $v', 'Outcome: $v'), (p) => p.question = p.question.copyWith(outcome: v))));
  }
  if (q.outcomeType == OutcomeType.unknown) {
    final v = inf.outcomeType;
    add(ReviewFinding('outcome_type', ReviewLevel.missing, Step.question, tr('Type d\'issue non précisé', 'Outcome type not specified'),
        tr('Binaire, continue, délai avec censure, comptage ou ordinale : chaque type appelle une autre méthode.', 'Binary, continuous, time-to-event, count or ordinal: each type calls for a different method.'),
        v == null ? tr('Préciser le type d\'issue à l\'étape 1.', 'Specify the outcome type at step 1.') : tr('Type proposé : ${outcomeTypeLabel(v)}.', 'Proposed type: ${outcomeTypeLabel(v)}.'),
        fix: v == null ? null : ReviewFix(tr('Type d\'issue : ${outcomeTypeLabel(v)}', 'Outcome type: ${outcomeTypeLabel(v)}'), (p) => p.question = p.question.copyWith(outcomeType: v))));
  }
  // Plusieurs critères principaux dans la même phrase d'objectif.
  final primary = RegExp(r"^[^.]+").firstMatch(prot('objective').isNotEmpty ? prot('objective') : q.text)?.group(0) ?? '';
  final nPrimary = _n(primary);
  final words = <String, String>{};
  for (final m in RegExp(_outcomeWords).allMatches(nPrimary)) {
    final w = m.group(0)!, stem = w.substring(0, math.min(5, w.length)); // « cure » n'a que 4 lettres
    if (words.containsKey(stem)) continue;
    final rest = primary.length == nPrimary.length ? primary.substring(m.start) : m.group(0)!;
    words[stem] = RegExp(r"^[^,;.]{3,60}?(?=\s+et\s+|\s+and\s+|[,;.]|$)").firstMatch(rest)?.group(0)?.trim() ?? m.group(0)!;
  }
  if (words.length >= 2 && !plan(r"critere (de jugement )?principal unique|co-?principa|hierarchi")) {
    final list = words.values.toList();
    add(ReviewFinding('primary_outcomes', ReviewLevel.warning, Step.question, tr('Plusieurs critères de jugement principaux', 'Several primary outcomes'),
        tr('L\'objectif principal vise ${list.length} critères (${list.join(' ; ')}). Sans hiérarchie, le risque d\'erreur de première espèce augmente et l\'effectif n\'est calculé que pour l\'un d\'eux.',
            'The primary objective targets ${list.length} outcomes (${list.join('; ')}). Without a hierarchy, the type I error rate increases and the sample size is computed for only one of them.'),
        tr('Retenir « ${list.first} » comme critère principal unique (celui du calcul d\'effectif) ; les autres deviennent secondaires, ou co-principaux avec correction de Holm.',
            'Keep "${list.first}" as the single primary outcome (the one used for the sample size); the others become secondary, or co-primary with Holm correction.'),
        evidence: primary.trim(),
        fix: ReviewFix(tr('Critère principal : ${list.first} ; paragraphe ajouté au plan d\'analyse', 'Primary outcome: ${list.first}; paragraph added to the analysis plan'), (p) {
          p.question = p.question.copyWith(outcome: list.first);
          _appendPlan(
              p,
              tr('critère principal unique', 'single primary outcome'),
              tr('Critère de jugement principal unique : ${list.first}. ${_cap(list.skip(1).join(', '))} : critère(s) secondaire(s), analysé(s) avec la même méthode et présenté(s) comme exploratoire(s) ; s\'ils devaient être co-principaux, les valeurs de p seraient ajustées par la méthode de Holm.',
                  'Single primary outcome: ${list.first}. ${_cap(list.skip(1).join(', '))}: secondary outcome(s), analysed with the same method and reported as exploratory; if they were to be co-primary, p-values would be adjusted by the Holm method.'));
        })));
  }

  // ---- 2. Plan d'étude ----
  if (q.design == StudyDesign.unknown) {
    final v = inf.design;
    add(ReviewFinding('design', ReviewLevel.missing, Step.studyPlan, tr('Plan d\'étude non précisé', 'Study design not specified'),
        tr('Le plan (essai, cohorte, cas-témoins, transversal…) fixe les mesures d\'effet légitimes.', 'The design (trial, cohort, case-control, cross-sectional…) determines which effect measures are legitimate.'),
        v == null ? tr('Préciser le plan d\'étude à l\'étape 2.', 'Specify the study design at step 2.') : tr('Plan proposé : ${designLabel(v)}.', 'Proposed design: ${designLabel(v)}.'),
        fix: v == null ? null : ReviewFix(tr('Plan : ${designLabel(v)}', 'Design: ${designLabel(v)}'), (p) => p.question = p.question.copyWith(design: v))));
  }
  if (q.objective == StudyObjective.unknown) {
    final v = inf.objective;
    add(ReviewFinding('objective', ReviewLevel.missing, Step.studyPlan, tr('Objectif non précisé', 'Aim not specified'),
        tr('Décrire, expliquer, diagnostiquer ou prédire : la méthode et l\'interprétation en dépendent.', 'Describe, explain, diagnose or predict: method and interpretation depend on it.'),
        v == null ? tr('Préciser l\'objectif à l\'étape 2.', 'Specify the aim at step 2.') : tr('Objectif proposé : ${objectiveLabel(v)}.', 'Proposed aim: ${objectiveLabel(v)}.'),
        fix: v == null ? null : ReviewFix(tr('Objectif : ${objectiveLabel(v)}', 'Aim: ${objectiveLabel(v)}'), (p) => p.question = p.question.copyWith(objective: v))));
  }
  final nObj = _n([objText, prot('outcome')].join('\n'));
  if (q.design == StudyDesign.crossSectional) {
    final inc = RegExp(r"\bincidence|delai (de|jusqu|avant)|temps jusqu|survenue (de |d')?[^.]{0,40}au cours du suivi|time to|incidence rate");
    if (q.outcomeType == OutcomeType.timeToEvent || inc.hasMatch(nObj)) {
      add(ReviewFinding('cross_sectional_incidence', ReviewLevel.error, Step.studyPlan, tr('Étude transversale et mesure d\'incidence ou de délai', 'Cross-sectional study with an incidence or time-to-event measure'),
          tr('Une étude transversale observe chaque sujet une seule fois : elle mesure une prévalence, pas une incidence ni un délai jusqu\'à l\'événement.', 'A cross-sectional study observes each subject once: it measures prevalence, not incidence or time to event.'),
          tr('Soit l\'issue devient une prévalence (issue binaire), soit le plan devient une cohorte avec suivi.', 'Either the outcome becomes a prevalence (binary outcome), or the design becomes a cohort with follow-up.'),
          evidence: _quote(objText, inc),
          fix: ReviewFix(tr('Issue binaire (prévalence) ; « incidence » remplacée par « prévalence » dans la question', 'Binary outcome (prevalence); "incidence" replaced by "prevalence" in the question'), (p) {
            p.question = p.question.copyWith(
                outcomeType: OutcomeType.binary, text: p.question.text.replaceAll(RegExp(r"\bincidence\b", caseSensitive: false), tr('prévalence', 'prevalence')));
          })));
    }
  }
  if (q.design == StudyDesign.caseControl) {
    final desc = RegExp(r"\bprevalence|\bincidence|frequence (de|du|des)");
    if (q.objective == StudyObjective.descriptive || desc.hasMatch(_n(objText))) {
      add(ReviewFinding('case_control_frequency', ReviewLevel.error, Step.studyPlan, tr('Cas-témoins et estimation d\'une fréquence', 'Case-control study estimating a frequency'),
          tr('Le recrutement sur la maladie fixe artificiellement la proportion de cas : prévalence et incidence ne sont pas estimables ; seul l\'odds ratio d\'exposition l\'est.', 'Recruitment on disease status fixes the proportion of cases artificially: prevalence and incidence cannot be estimated; only the exposure odds ratio can.'),
          tr('Objectif explicatif : estimer l\'odds ratio de l\'exposition (régression logistique ajustée, conditionnelle si appariement).', 'Explanatory aim: estimate the exposure odds ratio (adjusted logistic regression, conditional if matched).'),
          evidence: _quote(objText, desc),
          fix: ReviewFix(tr('Objectif explicatif (odds ratio)', 'Explanatory aim (odds ratio)'), (p) => p.question = p.question.copyWith(objective: StudyObjective.explanatory))));
    }
    final rr = RegExp(r"risques? relatifs?|\brr\b|relative risk");
    if (rr.hasMatch(nPlan) || rr.hasMatch(_n(objText))) {
      add(ReviewFinding('case_control_rr', ReviewLevel.error, Step.analysisPlan, tr('Risque relatif dans une étude cas-témoins', 'Relative risk in a case-control study'),
          tr('Le risque relatif n\'est pas estimable en cas-témoins (les risques absolus ne le sont pas) ; l\'odds ratio ne l\'approche que si la maladie est rare.', 'The relative risk cannot be estimated in a case-control study (absolute risks cannot); the odds ratio approximates it only when the disease is rare.'),
          tr('Remplacer « risque relatif » par « odds ratio » dans le plan d\'analyse.', 'Replace "relative risk" by "odds ratio" in the analysis plan.'),
          evidence: _quote(planText.isNotEmpty && rr.hasMatch(nPlan) ? planText : objText, rr),
          fix: ReviewFix(tr('« Risque relatif » → « odds ratio »', '"Relative risk" → "odds ratio"'), (p) {
            p.analysisPlan = p.analysisPlan.replaceAll(RegExp(r"risques? relatifs?", caseSensitive: false), 'odds ratio').replaceAll(RegExp(r"\bRR\b"), 'OR');
            _appendPlan(p, tr('mesure d\'association', 'measure of association'),
                tr('Mesure d\'association : odds ratio avec IC à 95 % (le risque relatif n\'est pas estimable dans une étude cas-témoins).', 'Measure of association: odds ratio with 95% CI (the relative risk cannot be estimated in a case-control study).'));
          })));
    }
  }
  if (observational && q.objective == StudyObjective.explanatory) {
    final causal = RegExp(r"\b(effets?|effects?|impacts?|influences?|efficacite|efficacy)\b (de |du |des |d'|of )");
    if (causal.hasMatch(_n(q.text)) && !plan(r"propension|ponderation inverse|appariement|variable instrumentale|propensity|inverse probability")) {
      final rewritten = _associationWording(q.text);
      add(ReviewFinding('causal_wording', ReviewLevel.warning, Step.question, tr('Formulation causale pour une étude observationnelle', 'Causal wording for an observational study'),
          tr('« Effet » ou « impact » annoncent une conclusion causale ; une ${designLabel(q.design).toLowerCase()} établit une association, sauf méthode causale explicite (graphe causal, score de propension).',
              '"Effect" or "impact" announce a causal conclusion; a ${designLabel(q.design).toLowerCase()} establishes an association, unless an explicit causal method is used (causal graph, propensity score).'),
          rewritten == null ? tr('Reformuler en termes d\'association.', 'Rephrase in terms of association.') : tr('Formulation proposée : « $rewritten »', 'Proposed wording: "$rewritten"'),
          evidence: _quote(q.text, causal),
          fix: rewritten == null ? null : ReviewFix(tr('Question reformulée : $rewritten', 'Question rephrased: $rewritten'), (p) => p.question = p.question.copyWith(text: rewritten))));
    }
  }
  if (q.objective == StudyObjective.predictive && q.design == StudyDesign.caseControl) {
    add(ReviewFinding('prediction_case_control', ReviewLevel.warning, Step.studyPlan, tr('Modèle prédictif construit sur un échantillon cas-témoins', 'Prediction model built on a case-control sample'),
        tr('La proportion de cas est fixée par le recrutement : les risques prédits sont faux tant que le modèle n\'est pas recalibré sur la prévalence réelle.', 'The proportion of cases is fixed by recruitment: predicted risks are wrong until the model is recalibrated to the true prevalence.'),
        tr('Préférer une cohorte ; à défaut, corriger l\'intercept par la prévalence de la population cible et le dire.', 'Prefer a cohort; otherwise, correct the intercept with the target population prevalence and say so.')));
  }
  if (q.objective == StudyObjective.diagnostic && !q.referenceStandardAvailable && !RegExp(r"reference|etalon|gold standard|reference standard").hasMatch(nAll)) {
    add(ReviewFinding('reference_standard', ReviewLevel.missing, Step.studyPlan, tr('Test de référence non précisé', 'Reference standard not specified'),
        tr('Sensibilité et spécificité n\'ont de sens que par rapport à un test de référence appliqué à tous les sujets.', 'Sensitivity and specificity only make sense against a reference standard applied to all subjects.'),
        tr('Nommer le test de référence et s\'assurer qu\'il est réalisé chez tous, à l\'insu du test évalué.', 'Name the reference standard and ensure everyone receives it, blinded to the index test.')));
  }

  // ---- 3. Nombre de sujets nécessaires ----
  final ssText = prot('sampleSize');
  final nSs = _n(ssText);
  final ssPlan = sampleSizePlan(q);
  final hasSsCalc = p.journal.any((e) => e.methodId.startsWith('power') || e.methodId.startsWith('sample_size')) || p.inferred['plannedSampleSize'] != null;
  if ((imported && ssText.isEmpty) || (!imported && !hasSsCalc && q.objective != StudyObjective.unknown)) {
    add(ReviewFinding('sample_size_missing', ReviewLevel.missing, Step.analysisPlan, tr('Nombre de sujets non justifié', 'Sample size not justified'),
        tr('Un comité d\'éthique demande comment l\'effectif a été calculé (hypothèses, risque α, puissance ou précision).', 'An ethics committee asks how the sample size was computed (assumptions, α, power or precision).'),
        ssPlan == null ? tr('Justifier l\'effectif à l\'étape 3.', 'Justify the sample size at step 3.') : '${ssPlan.title}. ${tr('Hypothèses à renseigner : ', 'Assumptions to provide: ')}${ssPlan.hypotheses.join(tr(' ; ', '; '))}.',
        calculator: ssPlan?.calculator, calculatorPresets: ssPlan?.presets ?? const {}));
  }
  if (ssText.isNotEmpty) {
    final ints = [
      for (final m in RegExp(r"(?<![\d.,])(\d{2,6})(?![\d]|[.,]\d)").allMatches(nSs)) (int.parse(m.group(1)!), m.start)
    ];
    // a) Majoration pour les pertes : n / (1 − x) et non n × (1 + x).
    final lossM = RegExp(r"(?:perte|perdus|refus|non[- ]repon|attrition|manquant)[^%]{0,80}?(?<![\d.,])(\d{1,2}(?:[.,]\d+)?)\s*%|(?<![\d.,])(\d{1,2}(?:[.,]\d+)?)\s*%[^.%]{0,60}(?:perte|perdus|refus|non[- ]repon|attrition|manquant)").firstMatch(nSs) ??
        RegExp(r"(?:ajout\w*|major\w*|augment\w*)\s+(?:de\s+)?(\d{1,2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
    final x = lossM == null ? null : _num(lossM.group(1) ?? lossM.group(2)!)! / 100;
    if (x != null && x > 0 && x < 0.5) {
      for (var i = 0; i < ints.length; i++) {
        final a = ints[i].$1;
        final wrong = {(a * (1 + x)).round(), (a * (1 + x)).ceil()};
        final right = (a / (1 - x) - 1e-9).ceil();
        final bIdx = ints.indexWhere((t) => t.$2 > ints[i].$2 && wrong.contains(t.$1) && t.$1 != right);
        if (bIdx < 0) continue;
        final b = ints[bIdx].$1;
        final pct = _fmt(x * 100, 1);
        add(ReviewFinding('loss_adjustment', ReviewLevel.error, Step.analysisPlan, tr('Majoration pour les pertes mal calculée', 'Adjustment for losses miscalculated'),
            tr('Ajouter $pct % à $a sujets donne $b ; mais si $pct % des sujets inclus sont perdus, il en reste ${(b * (1 - x)).floor()}, moins que les $a nécessaires. Il faut diviser : n = $a / (1 − ${_fmt(x)}) = $right.',
                'Adding $pct% to $a subjects gives $b; but if $pct% of included subjects are lost, ${(b * (1 - x)).floor()} remain, fewer than the $a required. Divide instead: n = $a / (1 − ${_fmt(x)}) = $right.'),
            tr('Effectif à inclure : $right sujets.', 'Subjects to include: $right.'),
            evidence: _quote(ssText, RegExp('(?<![\\d.,])$b(?![\\d]|[.,]\\d)')),
            fix: ReviewFix(tr('Effectif prévu : $right (au lieu de $b)', 'Planned sample size: $right (instead of $b)'), (p) {
              p.inferred['plannedSampleSize'] = '$right';
              _appendPlan(p, tr('effectif corrigé pour les pertes', 'sample size corrected for losses'),
                  tr('Effectif à inclure : n = $a / (1 − ${_fmt(x)}) = $right sujets (et non $a × (1 + ${_fmt(x)}) = $b), pour disposer de $a sujets analysables avec $pct % de pertes.',
                      'Subjects to include: n = $a / (1 − ${_fmt(x)}) = $right (not $a × (1 + ${_fmt(x)}) = $b), so that $a subjects remain analysable with $pct% losses.'));
            })));
        break;
      }
    }
    // b) Précision d'une proportion : n = z² p (1 − p) / i².
    final marginM = RegExp(r"(?:marge d'erreur|margin of error|precision|erreur (absolue|tolere)\w*|\bi\s*=)[^%]{0,40}?(\d{1,2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
    final propM = RegExp(r"(?:prevalence|proportion|frequence)[^%]{0,160}?(\d{1,2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
    if (marginM != null && propM != null) {
      final i = _num(marginM.group(2)!)! / 100, pr = _num(propM.group(1)!)! / 100;
      const z = 1.959964;
      final n0 = z * z * pr * (1 - pr) / (i * i);
      final stated = ints.where((t) => (t.$1 - n0).abs() <= math.max(1.5, 0.03 * n0)).firstOrNull;
      final formula = 'n = 1,96² × ${_fmt(pr)} × ${_fmt(1 - pr)} / ${_fmt(i)}² = ${_fmt(n0, 1)}';
      if (stated != null) {
        add(ReviewFinding('precision_recomputed', ReviewLevel.ok, Step.analysisPlan, tr('Calcul de précision refait : ${stated.$1} sujets', 'Precision calculation redone: ${stated.$1} subjects'),
            tr('$formula, conforme au protocole.', '$formula, consistent with the protocol.'), ''));
      } else if (ints.isNotEmpty) {
        add(ReviewFinding('precision_mismatch', ReviewLevel.error, Step.analysisPlan, tr('Calcul de précision non reproductible', 'Precision calculation not reproducible'),
            tr('Avec les hypothèses citées ($formula), l\'effectif serait ${n0.ceil()} ; le protocole ne donne pas ce nombre.', 'With the stated assumptions ($formula), the sample size would be ${n0.ceil()}; the protocol does not give this number.'),
            tr('Vérifier les hypothèses ou retenir n = ${n0.ceil()}.', 'Check the assumptions or use n = ${n0.ceil()}.'), evidence: _quote(ssText, RegExp(r"marge d'erreur|margin of error|precision")), calculator: 'sample_size',
            calculatorPresets: {'type': 'prop', 'p': _fmt(pr, 4), 'd': _fmt(i, 4)}));
      }
      final half = math.min(pr, 1 - pr) / 2;
      if (i > half + 1e-9) {
        // Marge ≈ un quart de la proportion, arrondie au demi-point.
        final i2 = math.max(0.005, ((math.min(pr, 1 - pr) / 4) * 200).round() / 200);
        final n2 = (z * z * pr * (1 - pr) / (i2 * i2)).ceil();
        add(ReviewFinding('precision_too_wide', ReviewLevel.warning, Step.analysisPlan, tr('Précision trop large pour la proportion attendue', 'Precision too wide for the expected proportion'),
            tr('Une marge de ± ${_fmt(i * 100, 1)} points autour de ${_fmt(pr * 100, 1)} % donne un intervalle de ${_fmt(math.max(0, pr - i) * 100, 1)} à ${_fmt((pr + i) * 100, 1)} % : l\'estimation resterait très imprécise (la marge dépasse la moitié de la proportion).',
                'A margin of ± ${_fmt(i * 100, 1)} points around ${_fmt(pr * 100, 1)}% gives an interval from ${_fmt(math.max(0, pr - i) * 100, 1)} to ${_fmt((pr + i) * 100, 1)}%: the estimate would remain very imprecise (the margin exceeds half the proportion).'),
            tr('Viser une marge d\'environ un quart de la proportion : ± ${_fmt(i2 * 100, 1)} points → n = $n2 sujets (avant majoration pour les pertes).', 'Aim for a margin of about a quarter of the proportion: ± ${_fmt(i2 * 100, 1)} points → n = $n2 subjects (before adjustment for losses).'),
            evidence: _quote(ssText, RegExp(r"marge d'erreur|margin of error|precision")), calculator: 'sample_size',
            calculatorPresets: {'type': 'prop', 'p': _fmt(pr, 4), 'd': _fmt(i2, 4)}));
      }
      // c) Base du calcul incohérente avec l'objectif principal.
      if (q.objective == StudyObjective.explanatory || q.objective == StudyObjective.predictive) {
        final corr = RegExp(r"correlation|relation (lineaire )?entre|lien entre|relationship between").hasMatch(_n(objText));
        int fisher(double r) => (math.pow((1.959964 + 0.841621) / (0.5 * math.log((1 + r) / (1 - r))), 2) + 3).ceil();
        add(ReviewFinding('sample_size_basis', ReviewLevel.warning, Step.analysisPlan, tr('Effectif calculé sur une prévalence, objectif principal d\'une autre nature', 'Sample size based on a prevalence, primary aim of another kind'),
            tr('Le calcul vise à estimer une proportion (${_fmt(pr * 100, 1)} %) alors que l\'objectif principal est ${objectiveLabel(q.objective).toLowerCase()} : l\'effectif doit permettre de mettre en évidence la relation étudiée.',
                'The calculation aims to estimate a proportion (${_fmt(pr * 100, 1)}%) whereas the primary aim is ${objectiveLabel(q.objective).toLowerCase()}: the sample size must allow the studied relationship to be shown.'),
            corr
                ? tr('Pour une corrélation (α = 5 %, puissance 80 %, transformation de Fisher) : r = 0,3 → ${fisher(0.3)} sujets ; r = 0,2 → ${fisher(0.2)} sujets. Retenir la plus petite corrélation cliniquement pertinente.',
                    'For a correlation (α = 5%, power 80%, Fisher transformation): r = 0.3 → ${fisher(0.3)} subjects; r = 0.2 → ${fisher(0.2)} subjects. Use the smallest clinically relevant correlation.')
                : (ssPlan == null ? tr('Refaire le calcul pour l\'objectif principal.', 'Redo the calculation for the primary aim.') : '${ssPlan.title}. ${tr('Hypothèses : ', 'Assumptions: ')}${ssPlan.hypotheses.join(tr(' ; ', '; '))}.'),
            evidence: _quote(ssText, RegExp(r"prevalence|proportion|frequence")), calculator: corr ? 'sample_size' : ssPlan?.calculator,
            calculatorPresets: corr ? {'type': 'correlation', 'r': _fmt(0.3), if (x != null) 'drop': _fmt(x, 4)} : (ssPlan?.presets ?? const {})));
      }
    }
    // d) Modèle de prédiction : critères de Riley.
    if (RegExp(r"shrinkage|riley|cox.?snell|pmsampsize").hasMatch(nSs)) {
      final sM = RegExp(r"(?:\bs\s*[:=]\s*|shrinkage[^0-9]{0,60})(0[.,]\d+)").firstMatch(nSs);
      final r2M = RegExp(r"(0[.,]\d+)\s*\)?\s*(?:dans la presente|retenu|pour la presente|in this study|assumed)").firstMatch(nSs) ??
          RegExp(r"(?:r²|r2|r\^2)[^0-9]{0,80}?(0[.,]\d+)").firstMatch(nSs);
      final pM = RegExp(r"\bp\s*[:=]\s*(\d{1,3})\b").firstMatch(nSs) ?? RegExp(r"(\d{1,3})\s+(?:parametres|predicteurs|variables candidates|degres de liberte|parameters|predictors)").firstMatch(nSs);
      final phiM = RegExp(r"(?:mortalite|incidence|prevalence|evenements?|taux|mortality|events?)[^%]{0,40}?(\d{1,2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
      final s = sM == null ? 0.9 : _num(sM.group(1)!)!;
      final r2 = r2M == null ? null : _num(r2M.group(1)!);
      final par = pM == null ? null : int.tryParse(pM.group(1)!);
      final phi = phiM == null ? null : _num(phiM.group(1)!)! / 100;
      if (r2 != null && par != null && r2 > 0 && r2 < s && s < 1) {
        final n1 = par / ((s - 1) * math.log(1 - r2 / s));
        final shown = RegExp('(?<!\\d)${n1.floor()}(?!\\d)').hasMatch(ssText);
        final planned = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
        if (shown) {
          add(ReviewFinding('riley_recomputed', ReviewLevel.ok, Step.analysisPlan, tr('Critère (i) de Riley refait : ${n1.ceil()} sujets', 'Riley criterion (i) redone: ${n1.ceil()} subjects'),
              tr('n = $par / ((${_fmt(s)} − 1) × ln(1 − ${_fmt(r2)} / ${_fmt(s)})) = ${_fmt(n1, 1)}, conforme au protocole.', 'n = $par / ((${_fmt(s)} − 1) × ln(1 − ${_fmt(r2)} / ${_fmt(s)})) = ${_fmt(n1, 1)}, consistent with the protocol.'), ''));
        } else {
          add(ReviewFinding('riley_mismatch', ReviewLevel.error, Step.analysisPlan, tr('Critère (i) de Riley non reproductible', 'Riley criterion (i) not reproducible'),
              tr('Avec p = $par, R² = ${_fmt(r2)} et S = ${_fmt(s)}, le critère (i) donne ${n1.ceil()} sujets ; ce nombre n\'apparaît pas dans le protocole.', 'With p = $par, R² = ${_fmt(r2)} and S = ${_fmt(s)}, criterion (i) gives ${n1.ceil()} subjects; this number does not appear in the protocol.'),
              tr('Reprendre le calcul (pmsampsize) avec ces hypothèses.', 'Redo the calculation (pmsampsize) with these assumptions.'), calculator: 'sample_size', calculatorPresets: {'type': 'riley', 'params': '$par', 'r2': _fmt(r2), 's': _fmt(s), if (phi != null) 'prev': _fmt(phi, 4)}));
        }
        if (phi != null && phi > 0 && phi < 1) {
          final rl = rileySampleSize(parameters: par, prevalence: phi, r2CoxSnell: r2, shrinkage: s);
          final need = rl.n.ceil();
          final crit = 'i : ${rl.n1.ceil()} ; ii : ${rl.n2.ceil()} ; iii : ${rl.n3.ceil()}';
          if (planned != null && planned < need) {
            add(ReviewFinding('riley_insufficient', ReviewLevel.error, Step.analysisPlan, tr('Effectif inférieur au minimum de Riley', 'Sample size below the Riley minimum'),
                tr('Les trois critères de Riley ($crit, prévalence ${_fmt(phi * 100, 1)} %) imposent au moins $need sujets ; le protocole en prévoit $planned.', 'The three Riley criteria ($crit, prevalence ${_fmt(phi * 100, 1)}%) require at least $need subjects; the protocol plans $planned.'),
                tr('Porter l\'effectif à $need (avant pertes) ou réduire le nombre de paramètres candidats.', 'Increase the sample size to $need (before losses) or reduce the number of candidate parameters.'), calculator: 'sample_size', calculatorPresets: {'type': 'riley', 'params': '$par', 'r2': _fmt(r2), 's': _fmt(s), 'prev': _fmt(phi, 4)}));
          } else {
            final epp = planned == null ? null : planned * phi / par;
            add(ReviewFinding('riley_all', ReviewLevel.ok, Step.analysisPlan, tr('Critères de Riley respectés', 'Riley criteria met'),
                tr('Minimum $need sujets ($crit) ; ${planned == null ? '' : 'effectif prévu $planned, soit ${_fmt(planned * phi, 1)} événements attendus et ${_fmt(epp!, 1)} événements par paramètre.'}',
                    'Minimum $need subjects ($crit); ${planned == null ? '' : 'planned $planned, i.e. ${_fmt(planned * phi, 1)} expected events and ${_fmt(epp!, 1)} events per parameter.'}'),
                ''));
          }
        }
      }
    }
  }

  // ---- 4. Plan d'analyse ----
  if (planText.trim().isEmpty) {
    add(ReviewFinding('plan_missing', ReviewLevel.missing, Step.analysisPlan, tr('Plan d\'analyse statistique absent', 'Statistical analysis plan missing'),
        tr('Le plan d\'analyse doit être écrit avant de voir les données : sans lui, toute analyse peut être choisie a posteriori.', 'The analysis plan must be written before seeing the data: without it, any analysis can be chosen after the fact.'),
        tr('Plan rédigé par Statoméa à partir de la question (à relire).', 'Plan drafted by Statoméa from the question (to review).'),
        fix: ReviewFix(tr('Plan d\'analyse rédigé à partir de la question', 'Analysis plan drafted from the question'), (p) {
          final d = draftAnalysisPlan(p.question);
          p.analysisPlan = p.analysisPlan.trim().isEmpty ? d : '${p.analysisPlan.trimRight()}\n\n$d';
        })));
  } else {
    if (q.objective == StudyObjective.predictive) {
      if (!plan(r"bootstrap|validation (interne|croisee|externe)|cross-?validation|internal validation|optimism")) {
        add(ReviewFinding('prediction_validation', ReviewLevel.error, Step.analysisPlan, tr('Modèle prédictif sans validation', 'Prediction model without validation'),
            tr('Les performances mesurées sur les données qui ont servi à construire le modèle sont optimistes (TRIPOD) : sans validation, le score paraîtra meilleur qu\'il n\'est.', 'Performance measured on the data used to build the model is optimistic (TRIPOD): without validation, the score will look better than it is.'),
            tr('Validation interne par bootstrap (≥ 200 rééchantillonnages, toute la sélection refaite à chaque fois), avec correction de l\'optimisme de l\'AUC et de la pente de calibration.', 'Internal validation by bootstrap (≥ 200 resamples, the whole selection redone each time), with optimism correction of the AUC and calibration slope.'),
            fix: ReviewFix(tr('Paragraphe « validation interne » ajouté au plan', '"Internal validation" paragraph added to the plan'), (p) => _appendPlan(p, tr('validation interne', 'internal validation'),
                tr('Validation interne par bootstrap (500 rééchantillonnages) : chaque étape de construction, y compris la sélection des variables, est refaite dans chaque échantillon ; l\'optimisme est retranché de l\'AUC, du score de Brier et de la pente de calibration ; un facteur de rétrécissement est appliqué aux coefficients si la pente corrigée est < 0,9.',
                    'Internal validation by bootstrap (500 resamples): every modelling step, including variable selection, is repeated in each sample; optimism is subtracted from the AUC, Brier score and calibration slope; a shrinkage factor is applied to the coefficients if the corrected slope is < 0.9.')))));
      }
      if (!plan(r"calibration")) {
        add(ReviewFinding('prediction_calibration', ReviewLevel.error, Step.analysisPlan, tr('Calibration du modèle non prévue', 'Model calibration not planned'),
            tr('Un bon pouvoir discriminant (AUC) ne garantit pas des risques prédits justes ; la calibration est exigée par TRIPOD.', 'Good discrimination (AUC) does not guarantee correct predicted risks; calibration is required by TRIPOD.'),
            tr('Courbe de calibration lissée, pente et intercept de calibration (avec IC).', 'Smoothed calibration curve, calibration slope and intercept (with CI).'),
            fix: ReviewFix(tr('Paragraphe « calibration » ajouté au plan', '"Calibration" paragraph added to the plan'), (p) => _appendPlan(p, tr('calibration', 'calibration'),
                tr('Calibration : courbe de calibration lissée (loess), pente et intercept de calibration avec IC à 95 %, rapportés avant et après correction de l\'optimisme.', 'Calibration: smoothed calibration curve (loess), calibration slope and intercept with 95% CI, reported before and after optimism correction.')))));
      }
      final step = RegExp(r"pas a pas|stepwise|selection (ascendante|descendante|progressive)|backward|forward selection|p\s*<\s*0[.,][12]\d*\s*en (analyse )?univari");
      if (step.hasMatch(nPlan) && !plan(r"lasso|ridge|penalis|elastic")) {
        add(ReviewFinding('stepwise', ReviewLevel.warning, Step.analysisPlan, tr('Sélection pas à pas ou sur tests univariés', 'Stepwise or univariable-test selection'),
            tr('La sélection par valeurs de p rend les coefficients instables et surestime les performances.', 'Selection by p-values makes coefficients unstable and overestimates performance.'),
            tr('Prédicteurs choisis a priori sur des bases cliniques, estimation pénalisée (LASSO ou ridge).', 'Predictors chosen a priori on clinical grounds, penalised estimation (LASSO or ridge).'),
            evidence: _quote(planText, step),
            fix: ReviewFix(tr('Paragraphe « sélection pénalisée » ajouté', '"Penalised selection" paragraph added'), (p) => _appendPlan(p, tr('choix des prédicteurs', 'choice of predictors'),
                tr('Prédicteurs candidats fixés a priori (littérature, avis clinique) ; pas de sélection sur les valeurs de p ; estimation pénalisée (LASSO, pénalité choisie par validation croisée), refaite dans chaque échantillon bootstrap.', 'Candidate predictors fixed a priori (literature, clinical input); no selection on p-values; penalised estimation (LASSO, penalty chosen by cross-validation), repeated in each bootstrap sample.')))));
      }
      if (plan(r"hosmer")) {
        add(ReviewFinding('hosmer_lemeshow', ReviewLevel.warning, Step.analysisPlan, tr('Test de Hosmer-Lemeshow', 'Hosmer-Lemeshow test'),
            tr('Ce test dépend du découpage en groupes et de l\'effectif, et ne dit pas dans quel sens le modèle se trompe ; il n\'est plus recommandé (TRIPOD).', 'This test depends on the grouping and on sample size, and does not say in which direction the model errs; it is no longer recommended (TRIPOD).'),
            tr('S\'appuyer sur la courbe, la pente et l\'intercept de calibration.', 'Rely on the calibration curve, slope and intercept.'),
            evidence: _quote(planText, RegExp(r"hosmer")),
            fix: ReviewFix(tr('Note ajoutée : la calibration est jugée sur la courbe, la pente et l\'intercept', 'Note added: calibration judged on curve, slope and intercept'), (p) => _appendPlan(p, tr('calibration', 'calibration'),
                tr('Le test de Hosmer-Lemeshow est rapporté à titre indicatif seulement ; la calibration est jugée sur la courbe lissée, la pente et l\'intercept de calibration.', 'The Hosmer-Lemeshow test is reported for information only; calibration is judged on the smoothed curve, calibration slope and intercept.')))));
      }
      final cut = RegExp(r"seuils?[^.]{0,80}(definis|determines|choisis|fixes|etablis)[^.]{0,80}(a partir|selon|en fonction)[^.]{0,60}(performances|donnees|observ|cohorte)");
      if (cut.hasMatch(nPlan) && !plan(r"seuils?[^.]{0,80}(bootstrap|a priori|validation)")) {
        add(ReviewFinding('data_driven_cutoffs', ReviewLevel.warning, Step.analysisPlan, tr('Seuils choisis sur les données de construction', 'Cut-offs chosen on the development data'),
            tr('Des seuils optimisés sur les mêmes données que le modèle donnent des performances optimistes, surtout à effectif modéré.', 'Cut-offs optimised on the same data as the model give optimistic performance, especially with a moderate sample size.'),
            tr('Choisir les seuils dans chaque échantillon bootstrap (performance corrigée de l\'optimisme) ou les fixer a priori.', 'Choose cut-offs within each bootstrap sample (optimism-corrected performance) or fix them a priori.'),
            evidence: _quote(planText, cut),
            fix: ReviewFix(tr('Paragraphe « seuils » ajouté', '"Cut-offs" paragraph added'), (p) => _appendPlan(p, tr('seuils de décision', 'decision cut-offs'),
                tr('Les seuils de décision sont choisis à l\'intérieur de chaque échantillon bootstrap ; sensibilité, spécificité et bénéfice net sont rapportés corrigés de l\'optimisme ; ils devront être confirmés par une validation externe.', 'Decision cut-offs are chosen within each bootstrap sample; sensitivity, specificity and net benefit are reported optimism-corrected; they must be confirmed by external validation.')))));
      }
    }
    if (observational && q.objective == StudyObjective.explanatory && !plan(r"ajust|multivari|confusion|regression (logistique|lineaire|de cox|de poisson|binomiale)|propension|modele mixte|adjust|multivariable|confound|(logistic|linear|poisson|cox) (regression|model)|propensity")) {
      final model = switch (q.outcomeType) {
        OutcomeType.binary => q.design == StudyDesign.cohort
            ? tr('régression de Poisson à variance robuste (risque relatif) ou logistique (odds ratio)', 'Poisson regression with robust variance (relative risk) or logistic regression (odds ratio)')
            : tr('régression logistique (odds ratio ; rapport de prévalences par Poisson robuste en transversal)', 'logistic regression (odds ratio; prevalence ratio by robust Poisson in cross-sectional studies)'),
        OutcomeType.continuous => tr('régression linéaire multiple', 'multiple linear regression'),
        OutcomeType.timeToEvent => tr('modèle de Cox', 'Cox model'),
        OutcomeType.count => tr('régression de Poisson ou binomiale négative', 'Poisson or negative binomial regression'),
        _ => tr('modèle de régression adapté au type d\'issue', 'regression model suited to the outcome type'),
      };
      add(ReviewFinding('no_adjustment', ReviewLevel.error, Step.analysisPlan, tr('Associations étudiées sans ajustement', 'Associations studied without adjustment'),
          tr('L\'objectif est explicatif mais le plan ne prévoit que des tests bivariés : dans une ${designLabel(q.design).toLowerCase()}, une association brute peut être entièrement due à des facteurs de confusion (âge, sexe, ancienneté de la maladie, traitement…).',
              'The aim is explanatory but the plan only includes bivariate tests: in a ${designLabel(q.design).toLowerCase()}, a crude association may be entirely due to confounders (age, sex, disease duration, treatment…).'),
          tr('Analyse multivariable : $model, avec des facteurs d\'ajustement choisis a priori (graphe causal), résultats bruts et ajustés.', 'Multivariable analysis: $model, with adjustment factors chosen a priori (causal graph), crude and adjusted results.'),
          fix: ReviewFix(tr('Paragraphe « analyse ajustée » ajouté', '"Adjusted analysis" paragraph added'), (p) => _appendPlan(p, tr('analyse ajustée', 'adjusted analysis'),
              tr('Les associations seront estimées par $model, ajustée sur les facteurs de confusion identifiés a priori à l\'aide d\'un graphe causal (au minimum âge et sexe) ; les résultats bruts et ajustés seront présentés avec leurs IC à 95 % ; colinéarité et linéarité des variables continues vérifiées.',
                  'Associations will be estimated by $model, adjusted for confounders identified a priori with a causal graph (at least age and sex); crude and adjusted results will be presented with 95% CIs; collinearity and linearity of continuous variables checked.')))));
    }
    final ttest = plan(r"student|\bt[- ]test|test t\b"), kw = plan(r"kruskal"), mw = plan(r"mann|wilcoxon"), anova = plan(r"anova|analyse de (la )?variance");
    if ((ttest && kw && !mw && !anova) || (anova && mw && !kw && !ttest)) {
      final re = RegExp(r"kruskal\w*[ -]*wallis|kruskal|mann[ -]*whitney");
      add(ReviewFinding('test_pairing', ReviewLevel.error, Step.analysisPlan, tr('Tests paramétrique et non paramétrique mal appariés', 'Parametric and non-parametric tests mismatched'),
          tr('Le test de Student compare deux groupes, son équivalent non paramétrique est le test de Mann-Whitney ; Kruskal-Wallis est l\'équivalent de l\'ANOVA (trois groupes ou plus).', 'Student\'s t-test compares two groups and its non-parametric counterpart is the Mann-Whitney test; Kruskal-Wallis is the counterpart of ANOVA (three groups or more).'),
          tr('Deux groupes : Student ou Mann-Whitney ; trois groupes ou plus : ANOVA ou Kruskal-Wallis.', 'Two groups: Student or Mann-Whitney; three groups or more: ANOVA or Kruskal-Wallis.'),
          evidence: _quote(planText, re),
          fix: ReviewFix(tr('Correspondance des tests précisée dans le plan', 'Test correspondence specified in the plan'), (p) => _appendPlan(p, tr('choix des tests', 'choice of tests'),
              tr('Comparaison de deux groupes : test t de Student (ou de Welch) si la distribution le permet, sinon test de Mann-Whitney ; trois groupes ou plus : ANOVA, sinon test de Kruskal-Wallis, suivis de comparaisons deux à deux ajustées (Holm).',
                  'Two groups: Student\'s (or Welch\'s) t-test if the distribution allows, otherwise the Mann-Whitney test; three groups or more: ANOVA, otherwise the Kruskal-Wallis test, followed by adjusted pairwise comparisons (Holm).')))));
    }
    if (plan(r"kolmogorov") && !plan(r"lilliefors|shapiro")) {
      add(ReviewFinding('ks_normality', ReviewLevel.warning, Step.analysisPlan, tr('Normalité jugée par le test de Kolmogorov-Smirnov', 'Normality judged by the Kolmogorov-Smirnov test'),
          tr('Appliqué avec une moyenne et un écart-type estimés sur l\'échantillon, ce test est trop conservateur ; il est peu puissant sur petit effectif et rejette tout sur grand effectif.', 'Applied with a mean and SD estimated from the sample, this test is too conservative; it has little power in small samples and rejects everything in large ones.'),
          tr('Juger la normalité sur un graphique quantile-quantile, complété si besoin par le test de Shapiro-Wilk.', 'Judge normality on a quantile-quantile plot, supplemented if needed by the Shapiro-Wilk test.'),
          evidence: _quote(planText, RegExp(r"kolmogorov")),
          fix: ReviewFix(tr('Paragraphe « normalité » ajouté', '"Normality" paragraph added'), (p) => _appendPlan(p, tr('normalité', 'normality'),
              tr('La normalité est jugée sur l\'histogramme et le graphique quantile-quantile, complétés par le test de Shapiro-Wilk ; en cas de doute, une méthode non paramétrique ou une transformation est utilisée.', 'Normality is judged on the histogram and quantile-quantile plot, supplemented by the Shapiro-Wilk test; if in doubt, a non-parametric method or a transformation is used.')))));
    }
    if (q.outcomeType == OutcomeType.timeToEvent && !plan(r"kaplan|\bcox\b|log-?rank|censur|fine|gray|survie|survival")) {
      add(ReviewFinding('survival_methods', ReviewLevel.error, Step.analysisPlan, tr('Issue de survie sans méthode de survie', 'Time-to-event outcome without survival methods'),
          tr('Avec un délai jusqu\'à l\'événement, les sujets perdus de vue ou encore indemnes à la fin du suivi sont censurés : les ignorer fausse les résultats.', 'With a time-to-event outcome, subjects lost to follow-up or event-free at the end are censored: ignoring them biases the results.'),
          tr('Kaplan-Meier, test du log-rank, modèle de Cox (proportionnalité des risques vérifiée).', 'Kaplan-Meier, log-rank test, Cox model (proportional hazards checked).'),
          fix: ReviewFix(tr('Paragraphe « analyse de survie » ajouté', '"Survival analysis" paragraph added'), (p) => _appendPlan(p, tr('analyse de survie', 'survival analysis'),
              tr('Analyse de survie : courbes de Kaplan-Meier, test du log-rank, modèle de Cox ajusté (hypothèse des risques proportionnels vérifiée par les résidus de Schoenfeld) ; censure à la date des dernières nouvelles.', 'Survival analysis: Kaplan-Meier curves, log-rank test, adjusted Cox model (proportional hazards checked with Schoenfeld residuals); censoring at the date of last contact.')))));
    }
    if (q.outcomeType == OutcomeType.timeToEvent && q.competingRisk == true && !plan(r"fine|gray|concurren|aalen|incidence cumulee|competing")) {
      add(ReviewFinding('competing_risks', ReviewLevel.error, Step.analysisPlan, tr('Risque concurrent non pris en compte', 'Competing risk not accounted for'),
          tr('Quand un autre événement (souvent le décès) empêche l\'événement étudié, 1 − Kaplan-Meier surestime son incidence.', 'When another event (often death) prevents the studied event, 1 − Kaplan-Meier overestimates its incidence.'),
          tr('Incidence cumulée (Aalen-Johansen) et modèle de Fine et Gray, ou modèle à risques spécifiques.', 'Cumulative incidence (Aalen-Johansen) and Fine-Gray model, or cause-specific hazards model.'),
          fix: ReviewFix(tr('Paragraphe « risques concurrents » ajouté', '"Competing risks" paragraph added'), (p) => _appendPlan(p, tr('risques concurrents', 'competing risks'),
              tr('Le décès est traité comme risque concurrent : incidence cumulée par la méthode d\'Aalen-Johansen, comparaison par le test de Gray, modèle de Fine et Gray (et modèle de Cox à risques spécifiques en complément).', 'Death is treated as a competing risk: cumulative incidence by the Aalen-Johansen method, comparison by Gray\'s test, Fine-Gray model (with cause-specific Cox model alongside).')))));
    }
    if (!plan(r"donnees manquantes|valeurs manquantes|manquant|imputation|missing")) {
      add(ReviewFinding('missing_data', ReviewLevel.warning, Step.analysisPlan, tr('Données manquantes non prévues', 'Missing data not planned for'),
          tr('Supprimer les sujets incomplets réduit l\'effectif et biaise les résultats si les manquants ne sont pas dus au hasard.', 'Dropping incomplete subjects reduces the sample size and biases results if data are not missing at random.'),
          tr('Décrire les données manquantes ; imputation multiple si elles dépassent 5 % ; analyse des cas complets en sensibilité.', 'Describe missing data; multiple imputation if they exceed 5%; complete-case analysis as sensitivity.'),
          fix: ReviewFix(tr('Paragraphe « données manquantes » ajouté', '"Missing data" paragraph added'), (p) => _appendPlan(p, tr('données manquantes', 'missing data'),
              tr('Les données manquantes seront décrites par variable ; si elles dépassent 5 %, une imputation multiple par équations chaînées (20 imputations) sera réalisée sous l\'hypothèse de données manquantes au hasard, l\'analyse des cas complets servant d\'analyse de sensibilité.',
                  'Missing data will be described per variable; if they exceed 5%, multiple imputation by chained equations (20 imputations) will be performed under a missing-at-random assumption, with complete-case analysis as sensitivity analysis.')))));
    }
    final objItems = RegExp(r"(?:^|\s)(?:\d|[a-h])[.)]\s+[A-ZÉÈa-zéè]").allMatches(prot('objective')).length;
    if (objItems >= 4 && !plan(r"bonferroni|multiplicit|benjamini|\bfdr\b|objectifs secondaires sont exploratoires|secondary objectives are exploratory|critere (de jugement )?principal unique")) {
      add(ReviewFinding('multiplicity', ReviewLevel.warning, Step.analysisPlan, tr('Nombreux objectifs, aucune règle de multiplicité', 'Many objectives, no multiplicity rule'),
          tr('$objItems objectifs spécifiques, chacun testé au seuil de 5 % : la probabilité d\'au moins un résultat « significatif » par hasard devient élevée.', '$objItems specific objectives, each tested at 5%: the probability of at least one chance "significant" result becomes high.'),
          tr('Désigner l\'analyse principale ; présenter les autres comme exploratoires, ou ajuster (Holm, Benjamini-Hochberg).', 'Designate the primary analysis; present the others as exploratory, or adjust (Holm, Benjamini-Hochberg).'),
          fix: ReviewFix(tr('Paragraphe « multiplicité » ajouté', '"Multiplicity" paragraph added'), (p) => _appendPlan(p, tr('multiplicité', 'multiplicity'),
              tr('L\'objectif principal fait l\'objet de l\'analyse confirmatoire au seuil de 5 % ; les objectifs secondaires sont exploratoires : leurs valeurs de p sont ajustées par la méthode de Benjamini-Hochberg et interprétées avec prudence.',
                  'The primary objective is the confirmatory analysis at the 5% level; secondary objectives are exploratory: their p-values are adjusted by the Benjamini-Hochberg method and interpreted cautiously.')))));
    }
    if (!plan(r"0[.,]05|(?<!9)5 ?% (bilateral|two-sided)|seuil (de signification|de significativite|alpha|de 5)|risque (alpha|α|de premiere espece)|\balpha\b|α|bilater|two-sided|significance level|5 ?% level|level of 5 ?%")) {
      add(ReviewFinding('alpha', ReviewLevel.missing, Step.analysisPlan, tr('Seuil de signification non précisé', 'Significance level not specified'),
          tr('Le risque α et le caractère bilatéral des tests doivent être fixés à l\'avance.', 'The α level and two-sidedness of tests must be set in advance.'),
          tr('Tests bilatéraux, seuil de 5 %.', 'Two-sided tests, 5% level.'),
          fix: ReviewFix(tr('Seuil bilatéral de 5 % ajouté', 'Two-sided 5% level added'), (p) => _appendPlan(p, tr('seuil', 'significance level'),
              tr('Tous les tests sont bilatéraux, au seuil de 5 % ; les estimations sont accompagnées de leur IC à 95 %.', 'All tests are two-sided at the 5% level; estimates are given with their 95% CIs.')))));
    }
    // Analyses intermédiaires : règle d'arrêt (contrôle du risque alpha) et comité indépendant.
    final interim = RegExp(r"analyses? intermediaires?|interim analys|analyses? (a mi-parcours|de mi-etude)|analyses? sequentielles? groupees?|group sequential");
    if (interim.hasMatch(nAll)) {
      final rule = RegExp(r"o'?brien|fleming|pocock|haybittle|peto\b|lan[- ]?demets|depense (du |de l')?(risque )?alpha|alpha[- ]?spending|spending function|regles? d'arret|stopping (rules?|boundar\w*|guidelines?)|(bornes?|limites?|seuils?) d'arret|futilite|futility|puissance conditionnelle|conditional power");
      final ev = _quote(allText, interim);
      if (!rule.hasMatch(nAll)) {
        add(ReviewFinding('interim_without_rule', ReviewLevel.warning, Step.analysisPlan, tr('Analyse intermédiaire sans règle d\'arrêt', 'Interim analysis without a stopping rule'),
            tr('Regarder les données en cours d\'étude et conclure à chaque fois au seuil de 5 % gonfle le risque de faux positif (≈ 8 % pour deux analyses, ≈ 11 % pour trois) ; un arrêt précoce surestime aussi l\'effet.',
                'Looking at the data during the study and concluding each time at the 5% level inflates the false-positive risk (≈ 8% for two analyses, ≈ 11% for three); early stopping also overestimates the effect.'),
            tr('Préciser le nombre et le moment des analyses intermédiaires, la règle d\'arrêt pour efficacité (bornes d\'O\'Brien-Fleming par la fonction de dépense de Lan-DeMets), éventuellement pour futilité, et le seuil de l\'analyse finale.',
                'Specify the number and timing of interim analyses, the stopping rule for efficacy (O\'Brien-Fleming boundaries via the Lan-DeMets spending function), possibly for futility, and the significance level of the final analysis.'),
            evidence: ev,
            fix: ReviewFix(tr('Paragraphe « analyse intermédiaire » ajouté', '"Interim analysis" paragraph added'), (p) => _appendPlan(p, tr('analyse intermédiaire', 'interim analysis'),
                tr('Une analyse intermédiaire est prévue après 50 % des inclusions (ou des événements attendus). Le risque alpha global de 5 % (bilatéral) est réparti par la fonction de dépense de Lan-DeMets de type O\'Brien-Fleming : arrêt pour efficacité si p ≤ 0,003 à l\'analyse intermédiaire, analyse finale au seuil de 0,049. Un arrêt pour futilité, non contraignant, est envisagé si la puissance conditionnelle est inférieure à 10 %. Après un arrêt précoce, l\'effet estimé est interprété avec prudence (surestimation possible).',
                    'An interim analysis is planned after 50% of inclusions (or expected events). The overall two-sided 5% alpha is allocated with an O\'Brien-Fleming-type Lan-DeMets spending function: stopping for efficacy if p ≤ 0.003 at the interim analysis, final analysis at the 0.049 level. Non-binding stopping for futility is considered if conditional power is below 10%. After early stopping, the estimated effect is interpreted with caution (possible overestimation).')))));
      } else {
        add(ReviewFinding('interim_rule_ok', ReviewLevel.ok, Step.analysisPlan, tr('Analyse intermédiaire encadrée par une règle d\'arrêt', 'Interim analysis governed by a stopping rule'),
            '', '', evidence: _quote(allText, rule)));
      }
      final dsmb = RegExp(r"comites? (independants? )?(de (surveillance|suivi|securite|monitorage)|independants?)|\bdsmb\b|\bidmc\b|\bdmc\b|data (and safety )?monitoring");
      if (!dsmb.hasMatch(nAll)) {
        add(ReviewFinding('interim_without_dsmb', ReviewLevel.warning, Step.studyPlan, tr('Analyse intermédiaire sans comité indépendant', 'Interim analysis without an independent committee'),
            tr('Si les investigateurs voient les résultats intermédiaires, la suite de l\'étude peut en être influencée (recrutement, évaluation du critère) ; la décision d\'arrêter revient à un comité indépendant.',
                'If investigators see interim results, the rest of the study may be influenced (recruitment, outcome assessment); the decision to stop belongs to an independent committee.'),
            tr('Prévoir un comité indépendant de surveillance des données, sa composition, sa charte et les résultats qu\'il est seul à voir.', 'Plan an independent data monitoring committee, its membership, charter, and the results only it will see.'),
            evidence: ev,
            fix: ReviewFix(tr('Paragraphe « comité de surveillance » ajouté', '"Monitoring committee" paragraph added'), (p) => _appendPlan(p, tr('comité de surveillance', 'monitoring committee'),
                tr('Un comité indépendant de surveillance des données (un clinicien, un méthodologiste-statisticien et un spécialiste de la sécurité, sans lien avec l\'étude) examine les données de sécurité et l\'analyse intermédiaire, seul à en connaître les résultats par groupe, selon une charte écrite avant la première inclusion ; il recommande la poursuite, la modification ou l\'arrêt de l\'étude.',
                    'An independent data monitoring committee (a clinician, a methodologist-statistician and a safety specialist, unrelated to the study) reviews safety data and the interim analysis, being the only body to see results by group, according to a charter written before the first inclusion; it recommends continuing, modifying or stopping the study.')))));
      }
    }
    if (RegExp(r"multicentri|multi-?center|multicenter|multicentre").hasMatch(nAll) && !plan(r"effet (du )?centre|centre (comme|en tant que|en) (effet|variable|strate)|aleatoire|mixte|stratifi\w*[^.]{0,40}centre|cluster|grappe|random effect|mixed model|interne-externe|internal-external|heterogeneite entre centres")) {
      final pred = q.objective == StudyObjective.predictive;
      add(ReviewFinding('centre_effect', ReviewLevel.warning, Step.analysisPlan, tr('Étude multicentrique sans prise en compte du centre', 'Multicentre study without accounting for centre'),
          tr('Les patients d\'un même centre se ressemblent (corrélation intra-centre, déjà utilisée dans le calcul d\'effectif le cas échéant) : l\'ignorer donne des IC trop étroits${pred ? ' et masque les différences de performance entre centres' : ''}.',
              'Patients from the same centre resemble each other (intra-centre correlation, already used in the sample-size calculation if any): ignoring it gives CIs that are too narrow${pred ? ' and hides differences in performance between centres' : ''}.'),
          pred
              ? tr('Validation interne-externe (chaque centre laissé de côté à tour de rôle) et hétérogénéité des performances entre centres ; intercept aléatoire par centre si nécessaire.', 'Internal-external validation (each centre left out in turn) and heterogeneity of performance across centres; random intercept per centre if needed.')
              : tr('Modèle mixte avec effet aléatoire centre, ou stratification sur le centre.', 'Mixed model with a random centre effect, or stratification by centre.'),
          fix: ReviewFix(tr('Paragraphe « effet centre » ajouté', '"Centre effect" paragraph added'), (p) => _appendPlan(p, tr('effet centre', 'centre effect'),
              pred
                  ? tr('Le centre est pris en compte : validation interne-externe (chaque centre laissé de côté à tour de rôle), hétérogénéité de l\'AUC et de la calibration entre centres (méta-analyse à effets aléatoires), intercept aléatoire par centre en analyse de sensibilité.',
                      'Centre is accounted for: internal-external validation (each centre left out in turn), heterogeneity of AUC and calibration across centres (random-effects meta-analysis), random intercept per centre as sensitivity analysis.')
                  : tr('Le centre est pris en compte par un modèle mixte avec effet aléatoire centre (ou, si les centres sont peu nombreux, par stratification) ; la corrélation intra-centre observée est rapportée.',
                      'Centre is accounted for by a mixed model with a random centre effect (or, with few centres, by stratification); the observed intra-centre correlation is reported.')))));
    }
    final pearson = RegExp(r"correlation de pearson|coefficient de (correlation de )?pearson|\br de pearson|pearson'?s? (correlation|coefficient)");
    if (pearson.hasMatch(nPlan) && !plan(r"spearman")) {
      add(ReviewFinding('pearson_only', ReviewLevel.warning, Step.analysisPlan, tr('Corrélation de Pearson seule', 'Pearson correlation only'),
          tr('Pearson ne mesure qu\'une relation linéaire et est sensible aux valeurs extrêmes, fréquentes en biologie (glycémie, HbA1c…).', 'Pearson measures only a linear relationship and is sensitive to extreme values, common in biology (glucose, HbA1c…).'),
          tr('Nuage de points systématique ; Spearman si la relation est monotone non linéaire ou en présence de valeurs extrêmes ; coefficient avec IC à 95 %.', 'Scatter plot always; Spearman if the relationship is monotonic but non-linear or with extreme values; coefficient with 95% CI.'),
          evidence: _quote(planText, pearson),
          fix: ReviewFix(tr('Paragraphe « corrélation » ajouté', '"Correlation" paragraph added'), (p) => _appendPlan(p, tr('corrélation', 'correlation'),
              tr('Chaque corrélation est examinée sur un nuage de points ; le coefficient de Pearson est complété par celui de Spearman si la relation n\'est pas linéaire ou en présence de valeurs extrêmes, avec IC à 95 %. Une corrélation ne dit pas l\'accord entre deux mesures.',
                  'Each correlation is examined on a scatter plot; Pearson\'s coefficient is complemented by Spearman\'s if the relationship is not linear or with extreme values, with 95% CI. A correlation does not measure agreement between two measurements.')))));
    }
  }

  // Sous-groupes annoncés au plan sans test d'interaction.
  final subRe = RegExp(r"sous-groupes?|subgroups?|analyses? stratifiees? (selon|par)|stratified analys");
  if (subRe.hasMatch(nPlan) && !plan(r"interaction|heterogeneite de l'effet|effect modification|modification de l'effet")) {
    add(ReviewFinding('subgroup_interaction', ReviewLevel.warning, Step.analysisPlan, tr('Sous-groupes sans test d\'interaction', 'Subgroups without an interaction test'),
        tr('Comparer la valeur de p d\'un sous-groupe à l\'autre (« significatif chez les hommes, pas chez les femmes ») n\'établit pas que l\'effet diffère ; multiplier les sous-groupes produit des faux positifs.',
            'Comparing p-values between subgroups ("significant in men, not in women") does not show that the effect differs; multiplying subgroups produces false positives.'),
        tr('Limiter les sous-groupes à quelques-uns, annoncés avec le sens attendu, et les juger par un test d\'interaction ; les présenter comme exploratoires.', 'Limit subgroups to a few, pre-specified with the expected direction, and judge them by an interaction test; present them as exploratory.'),
        evidence: _quote(planText, subRe),
        fix: ReviewFix(tr('Paragraphe « sous-groupes » ajouté', '"Subgroups" paragraph added'), (p) => _appendPlan(p, tr('sous-groupes', 'subgroups'),
            tr('Les analyses en sous-groupes, limitées à celles annoncées ici avec le sens attendu, sont jugées par un test d\'interaction (terme produit dans le modèle) et présentées en forest plot avec leurs IC à 95 % ; elles sont exploratoires.',
                'Subgroup analyses, limited to those pre-specified here with the expected direction, are judged by an interaction test (product term in the model) and shown in a forest plot with their 95% CIs; they are exploratory.')))));
  }

  // ---- 4 bis. Essai randomisé : randomisation, dissimulation, aveugle, intention de traiter ----
  if (q.design == StudyDesign.rct) {
    bool any(String re) => RegExp(re).hasMatch(nAll);
    if (!any(r"(randomis\w*|tirage au sort)[^.]{0,60}(blocs?|stratifi|informatis|ordinateur|logiciel|liste)|sequence (de randomisation|aleatoire)|liste de randomisation|block randomi|computer-generated|randomisation stratifiee")) {
      add(ReviewFinding('rct_randomisation', ReviewLevel.missing, Step.studyPlan, tr('Méthode de randomisation non décrite', 'Randomisation method not described'),
          tr('« Randomisé » ne suffit pas : la génération de la séquence (logiciel, blocs, stratification) conditionne la comparabilité des groupes (CONSORT 8).', '"Randomised" is not enough: how the sequence is generated (software, blocks, stratification) determines group comparability (CONSORT 8).'),
          tr('Liste générée par ordinateur, blocs de taille variable, stratification sur le centre et les facteurs pronostiques majeurs.', 'Computer-generated list, variable block sizes, stratification by centre and major prognostic factors.'),
          fix: ReviewFix(tr('Paragraphe « randomisation » ajouté', '"Randomisation" paragraph added'), (p) => _appendPlan(p, tr('randomisation', 'randomisation'),
              tr('Randomisation 1:1 par liste générée par ordinateur (blocs de taille variable 4 ou 6), stratifiée sur le centre ; la liste est établie par un statisticien indépendant de l\'inclusion.', '1:1 randomisation by computer-generated list (variable block sizes of 4 or 6), stratified by centre; the list is prepared by a statistician independent of recruitment.')))));
    }
    if (!any(r"enveloppes?[^.]{0,30}(opaques?|scellees?|numerotees?)|centralis|dissimul|concealment|serveur|interactive web|iwrs|par telephone")) {
      add(ReviewFinding('rct_concealment', ReviewLevel.missing, Step.studyPlan, tr('Dissimulation de l\'allocation non prévue', 'Allocation concealment not planned'),
          tr('Si l\'investigateur peut connaître le prochain bras avant d\'inclure, il choisit — même sans le vouloir — qui inclure : la randomisation est contournée (CONSORT 9).', 'If the investigator can know the next arm before enrolling, they choose — even unintentionally — whom to enrol: randomisation is bypassed (CONSORT 9).'),
          tr('Allocation centralisée (serveur ou téléphone) ou enveloppes opaques, scellées et numérotées, ouvertes après l\'inclusion.', 'Central allocation (web or phone) or opaque, sealed, numbered envelopes opened after enrolment.'),
          fix: ReviewFix(tr('Paragraphe « dissimulation de l\'allocation » ajouté', '"Allocation concealment" paragraph added'), (p) => _appendPlan(p, tr('dissimulation de l\'allocation', 'allocation concealment'),
              tr('L\'allocation est dissimulée : le bras n\'est révélé qu\'après l\'inclusion définitive, par un système centralisé (ou des enveloppes opaques, scellées et numérotées séquentiellement).', 'Allocation is concealed: the arm is revealed only after definitive enrolment, by a central system (or opaque, sealed, sequentially numbered envelopes).')))));
    }
    if (!any(r"aveugle|insu|masqu|blind|ouvert|open[- ]label")) {
      add(ReviewFinding('rct_blinding', ReviewLevel.missing, Step.studyPlan, tr('Aveugle non précisé', 'Blinding not specified'),
          tr('Qui connaît le traitement attribué (patient, soignant, évaluateur, statisticien) ? Sans aveugle, l\'évaluation d\'un critère subjectif est biaisée.', 'Who knows the allocated treatment (patient, carer, assessor, statistician)? Without blinding, assessment of a subjective outcome is biased.'),
          tr('Préciser l\'aveugle ; si l\'essai est ouvert, faire évaluer le critère principal par une personne en aveugle.', 'Specify blinding; if the trial is open-label, have the primary outcome assessed by a blinded person.'),
          fix: ReviewFix(tr('Paragraphe « aveugle » ajouté', '"Blinding" paragraph added'), (p) => _appendPlan(p, tr('aveugle', 'blinding'),
              tr('Le patient et l\'évaluateur du critère principal ignorent le bras attribué ; si l\'aveugle du patient est impossible, l\'évaluation du critère principal est faite en aveugle et le statisticien analyse les bras codés.', 'The patient and the primary outcome assessor are blind to the allocated arm; if patient blinding is impossible, the primary outcome is assessed blind and the statistician analyses coded arms.')))));
    }
    if (!any(r"intention de traiter|intention-to-treat|\bitt\b")) {
      add(ReviewFinding('rct_itt', ReviewLevel.error, Step.analysisPlan, tr('Analyse en intention de traiter non prévue', 'Intention-to-treat analysis not planned'),
          tr('Exclure les patients qui n\'ont pas suivi le traitement attribué détruit la comparabilité créée par la randomisation.', 'Excluding patients who did not follow the allocated treatment destroys the comparability created by randomisation.'),
          tr('Analyse principale en intention de traiter (tous les randomisés dans leur bras) ; analyse per protocole en sensibilité.', 'Primary analysis by intention to treat (all randomised in their arm); per-protocol analysis as sensitivity.'),
          fix: ReviewFix(tr('Paragraphe « intention de traiter » ajouté', '"Intention to treat" paragraph added'), (p) => _appendPlan(p, tr('population d\'analyse', 'analysis population'),
              tr('L\'analyse principale porte sur tous les patients randomisés, dans le bras attribué (intention de traiter), les données manquantes étant imputées ; une analyse per protocole est présentée en sensibilité.', 'The primary analysis includes all randomised patients in their allocated arm (intention to treat), with missing data imputed; a per-protocol analysis is presented as sensitivity.')))));
    }
    // Effectif d'un essai à deux bras, refait à partir des hypothèses du protocole (calcul exact : power.prop.test,
    // power.t.test).
    if (ssText.isNotEmpty) {
      final powM = RegExp(r"(?:puissance|power)\D{0,15}(\d{2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
      final alphaM = RegExp(r"(?:alpha|α|risque de premiere espece|type i error|seuil)\D{0,15}(\d(?:[.,]\d+)?)\s*%").firstMatch(nSs);
      final pw = powM == null ? 0.8 : _num(powM.group(1)!)! / 100, al = alphaM == null ? 0.05 : _num(alphaM.group(1)!)! / 100;
      final armM = RegExp(r"(?<![\d.,])(\d{2,5})\s+(?:[a-z]+\s+)?(?:par (?:bras|groupe)|per (?:arm|group))").firstMatch(nSs);
      final propM = RegExp(r"(?<![\d.,])(\d{1,2}(?:[.,]\d+)?)\s*% (?:a|vs\.?|versus|contre|to) (\d{1,2}(?:[.,]\d+)?)\s*%").firstMatch(nSs);
      final meanM = propM != null
          ? null
          : RegExp(r"difference[^.;\d]{0,60}?(\d+(?:[.,]\d+)?)[^.;]{0,80}?(?:ecart[- ]type|standard deviation|\bsd\b)[^\d.;]{0,15}(\d+(?:[.,]\d+)?)").firstMatch(nSs);
      AnalysisResult? r;
      try {
        if (propM != null) {
          r = sampleSizeTwoProportions(p1: _num(propM.group(1)!)! / 100, p2: _num(propM.group(2)!)! / 100, alpha: al, power: pw);
        } else if (meanM != null) {
          r = sampleSizeTwoMeans(delta: _num(meanM.group(1)!)!, sd: _num(meanM.group(2)!)!, alpha: al, power: pw);
        }
      } on StatInputError {
        r = null;
      }
      if (r != null && pw > 0.5 && pw < 1 && al > 0 && al < 0.2) {
        final need = r.statistics['n_per_group']!.round();
        final stated = armM == null ? null : int.parse(armM.group(1)!);
        final hyp = propM != null
            ? '${_fmt(_num(propM.group(1)!)!, 1)} % ${tr('contre', 'vs')} ${_fmt(_num(propM.group(2)!)!, 1)} %'
            : '${tr('différence', 'difference')} ${_fmt(_num(meanM!.group(1)!)!)}, ${tr('écart-type', 'SD')} ${_fmt(_num(meanM.group(2)!)!)}';
        final calc = tr('$hyp, α = ${_fmt(al)}, puissance ${_fmt(pw * 100, 0)} % : n = $need par bras (${propM != null ? 'power.prop.test' : 'power.t.test'})',
            '$hyp, α = ${_fmt(al)}, power ${_fmt(pw * 100, 0)}%: n = $need per arm (${propM != null ? 'power.prop.test' : 'power.t.test'})');
        final presets = propM != null
            ? {'type': 'two_props', 'p1': _fmt(_num(propM.group(1)!)! / 100, 4), 'p2': _fmt(_num(propM.group(2)!)! / 100, 4), 'alpha': _fmt(al), 'power': _fmt(pw)}
            : {'type': 'two_means', 'delta': _fmt(_num(meanM!.group(1)!)!), 'sd': _fmt(_num(meanM.group(2)!)!), 'alpha': _fmt(al), 'power': _fmt(pw)};
        if (stated == null || stated >= need) {
          add(ReviewFinding('rct_sample_size_ok', ReviewLevel.ok, Step.analysisPlan, tr('Effectif de l\'essai refait : $need par bras', 'Trial sample size redone: $need per arm'),
              stated == null ? '$calc.' : tr('$calc ; le protocole en prévoit $stated, conforme.', '$calc; the protocol plans $stated, consistent.'), ''));
        } else {
          final real = propM != null
              ? powerTwoProportionsN(stated.toDouble(), _num(propM.group(1)!)! / 100, _num(propM.group(2)!)! / 100, alpha: al)
              : powerTwoMeansD(stated.toDouble(), stated.toDouble(), _num(meanM!.group(1)!)! / _num(meanM.group(2)!)!, alpha: al);
          add(ReviewFinding('rct_sample_size_short', ReviewLevel.error, Step.analysisPlan, tr('Effectif par bras insuffisant', 'Sample size per arm insufficient'),
              tr('Avec les hypothèses du protocole ($calc), $stated sujets par bras ne donnent qu\'une puissance de ${_fmt(real * 100, 0)} % : un vrai effet de cette taille serait manqué une fois sur ${_fmt(1 / (1 - real), 1)}.',
                  'With the protocol assumptions ($calc), $stated subjects per arm give only ${_fmt(real * 100, 0)}% power: a true effect of this size would be missed one time in ${_fmt(1 / (1 - real), 1)}.'),
              tr('Prévoir $need sujets par bras (${2 * need} au total), avant majoration pour les pertes.', 'Plan $need subjects per arm (${2 * need} in total), before adjustment for losses.'),
              evidence: _quote(ssText, RegExp('(?<![\\d.,])$stated(?![\\d]|[.,]\\d)')),
              calculator: 'sample_size',
              calculatorPresets: presets,
              fix: ReviewFix(tr('Effectif recalculé : $need par bras', 'Sample size recomputed: $need per arm'), (p) {
                final planned = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
                if (planned == null || planned < 2 * need) p.inferred['plannedSampleSize'] = '${2 * need}';
                _appendPlan(p, tr('effectif de l\'essai', 'trial sample size'),
                    tr('$calc, soit ${2 * need} sujets au total avant majoration pour les pertes (et non $stated par bras, qui ne donnent qu\'une puissance de ${_fmt(real * 100, 0)} %).',
                        '$calc, i.e. ${2 * need} subjects in total before adjustment for losses (not $stated per arm, which give only ${_fmt(real * 100, 0)}% power).'));
              })));
        }
      }
    }
    // Enregistrement de l'essai avant la première inclusion.
    if (!any(r"clinicaltrials|pactr|isrctn|ictrp|eudract|ctis\b|enregistr\w*[^.]{0,40}(registre|plateforme|essais)|registre (des|d') ?essais|trial regist\w*|registered (in|on|with|at)|registry")) {
      add(ReviewFinding('trial_registration', ReviewLevel.missing, Step.studyPlan, tr('Enregistrement de l\'essai non prévu', 'Trial registration not planned'),
          tr('Un essai doit être enregistré dans un registre public avant la première inclusion (déclaration d\'Helsinki, ICMJE) : sans numéro d\'enregistrement, la plupart des revues refusent l\'article, et le critère principal peut être changé après coup sans trace.',
              'A trial must be registered in a public registry before the first inclusion (Declaration of Helsinki, ICMJE): without a registration number, most journals refuse the article, and the primary outcome can be changed afterwards without trace.'),
          tr('Enregistrer l\'essai (PACTR pour l\'Afrique, ClinicalTrials.gov ou un registre primaire de l\'OMS) avant la première inclusion, en y déclarant le critère principal.', 'Register the trial (PACTR for Africa, ClinicalTrials.gov or a WHO primary registry) before the first inclusion, declaring the primary outcome.'),
          fix: ReviewFix(tr('Paragraphe « enregistrement » ajouté', '"Registration" paragraph added'), (p) => _appendPlan(p, tr('enregistrement', 'registration'),
              tr('L\'essai sera enregistré dans le registre panafricain des essais cliniques (PACTR) ou sur ClinicalTrials.gov avant la première inclusion ; le critère de jugement principal, l\'effectif et le plan d\'analyse y seront déclarés, et le numéro d\'enregistrement sera cité dans toute publication.',
                  'The trial will be registered in the Pan African Clinical Trials Registry (PACTR) or on ClinicalTrials.gov before the first inclusion; the primary outcome, sample size and analysis plan will be declared there, and the registration number will be cited in every publication.')))));
    }
    // Non-infériorité : marge justifiée et analyse per protocole en plus de l'intention de traiter.
    if (any(r"non[- ]?inferiorit|non[- ]?inferior|equivalence")) {
      final eq = !any(r"non[- ]?inferior");
      if (!any(r"marge|margin|\bdelta\b|δ|borne (de non|d'equivalence)")) {
        add(ReviewFinding('noninferiority_margin', ReviewLevel.missing, Step.analysisPlan, tr('Marge de ${eq ? 'd\'équivalence' : 'non-infériorité'} non précisée', '${eq ? 'Equivalence' : 'Non-inferiority'} margin not specified'),
            tr('Sans marge fixée à l\'avance, « non inférieur » ne veut rien dire : c\'est elle qui détermine l\'effectif et la conclusion.', 'Without a margin fixed in advance, "non-inferior" means nothing: it determines the sample size and the conclusion.'),
            tr('Fixer la marge (perte d\'efficacité acceptable), la justifier par les essais antérieurs contre placebo et le jugement clinique, et conclure sur la borne de l\'IC à 95 %.', 'Fix the margin (acceptable loss of efficacy), justify it from previous placebo-controlled trials and clinical judgement, and conclude on the bound of the 95% CI.')));
      }
      if (!any(r"per[- ]?protocole?|per-protocol|perprotocol")) {
        add(ReviewFinding('noninferiority_pp', ReviewLevel.warning, Step.analysisPlan, tr('${eq ? 'Équivalence' : 'Non-infériorité'} sans analyse per protocole', '${eq ? 'Equivalence' : 'Non-inferiority'} without per-protocol analysis'),
            tr('En ${eq ? 'équivalence' : 'non-infériorité'}, l\'intention de traiter seule est anticonservatrice : les écarts au protocole rapprochent les bras et favorisent la conclusion recherchée.', 'In ${eq ? 'equivalence' : 'non-inferiority'}, intention to treat alone is anti-conservative: protocol deviations bring the arms closer and favour the desired conclusion.'),
            tr('Conclure seulement si les analyses en intention de traiter et per protocole concordent.', 'Conclude only if the intention-to-treat and per-protocol analyses agree.'),
            fix: ReviewFix(tr('Paragraphe « intention de traiter et per protocole » ajouté', '"Intention to treat and per protocol" paragraph added'), (p) => _appendPlan(p, tr('populations d\'analyse', 'analysis populations'),
                tr('La ${eq ? 'l\'équivalence' : 'non-infériorité'} est conclue si la borne de l\'IC à 95 % de la différence respecte la marge à la fois en intention de traiter et en per protocole (patients ayant reçu le traitement attribué sans écart majeur) ; une discordance est discutée.',
                    '${eq ? 'Equivalence' : 'Non-inferiority'} is concluded if the bound of the 95% CI of the difference respects the margin in both the intention-to-treat and per-protocol (patients who received the allocated treatment without major deviation) analyses; any discrepancy is discussed.')))));
      }
    }
  }

  // ---- 4 ter. Critères d'inclusion (protocole importé) ----
  final popText = prot('population');
  if (imported && popText.isNotEmpty) {
    final nPop = _n(popText);
    if (!RegExp(r"\d+\s*ans|\bage\b|\bages?\b|years|\d+\s*mois|nouveau-nes?|nourrissons?|adultes?|enfants?|adolescents?|majeurs?|mineurs?|adults?|children").hasMatch(nPop)) {
      add(ReviewFinding('inclusion_age', ReviewLevel.warning, Step.question, tr('Âge des participants non précisé', 'Participants\' age not specified'),
          tr('Sans borne d\'âge, la population est ambiguë (mineurs inclus ? consentement des parents ?) et les résultats ne sont pas transposables.', 'Without an age limit, the population is ambiguous (minors included? parental consent?) and results cannot be transposed.'),
          tr('Préciser l\'âge minimal (et maximal si besoin) dans les critères d\'inclusion.', 'Specify the minimum (and maximum if needed) age in the inclusion criteria.'), evidence: _quote(popText, RegExp(r"^.{0,80}"))));
    }
    if (!RegExp(r"non[- ]?inclusion|exclusion|ne seront pas inclus|seront exclus|exclu|not (be )?included|excluded").hasMatch(nPop)) {
      add(ReviewFinding('exclusion_criteria', ReviewLevel.missing, Step.question, tr('Critères de non-inclusion absents', 'Exclusion criteria missing'),
          tr('Les critères de non-inclusion protègent les participants (contre-indications) et évitent les situations qui fausseraient la mesure du critère principal.', 'Exclusion criteria protect participants (contraindications) and avoid situations that would distort measurement of the primary outcome.'),
          tr('Lister les critères de non-inclusion (refus de consentement, contre-indications, conditions qui faussent la mesure).', 'List the exclusion criteria (refusal of consent, contraindications, conditions that distort measurement).')));
    }
  }

  // ---- 4 quater. Faisabilité du recrutement ----
  final planned = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
  if (imported && planned != null) {
    final months = _studyMonths([prot('design'), prot('period'), prot('sampleSize'), prot('_text')].join('\n'));
    if (months != null && months > 0) {
      final need = planned / months;
      final centres = _centres(nAll);
      final rate = _recruitmentPerMonth(nAll);
      final perCentre = centres == null || centres < 2 ? '' : tr(' (soit ${_fmt(need / centres, 1)} par centre et par mois pour $centres centres)', ' (i.e. ${_fmt(need / centres, 1)} per centre per month for $centres centres)');
      if (rate != null && rate * months < planned) {
        add(ReviewFinding('recruitment_unrealistic', ReviewLevel.error, Step.studyPlan, tr('Recrutement insuffisant pour l\'effectif prévu', 'Recruitment insufficient for the planned sample size'),
            tr('Au rythme indiqué (${_fmt(rate, 1)} sujets par mois), $months mois permettent d\'inclure ${(rate * months).floor()} sujets, moins que les $planned prévus.', 'At the stated rate (${_fmt(rate, 1)} subjects per month), $months months allow ${(rate * months).floor()} subjects, fewer than the $planned planned.'),
            tr('Allonger la période d\'inclusion à ${(planned / rate).ceil()} mois, ajouter des centres ou revoir l\'effectif.', 'Extend recruitment to ${(planned / rate).ceil()} months, add centres or revise the sample size.')));
      } else if (rate == null) {
        add(ReviewFinding('recruitment_feasibility', ReviewLevel.warning, Step.studyPlan, tr('Faisabilité du recrutement non documentée', 'Recruitment feasibility not documented'),
            tr('$planned sujets en $months mois imposent d\'inclure ${_fmt(need, 1)} sujets par mois$perCentre ; le protocole n\'indique pas combien de patients éligibles sont reçus chaque mois.', '$planned subjects in $months months require enrolling ${_fmt(need, 1)} subjects per month$perCentre; the protocol does not say how many eligible patients the department(s) receive.'),
            tr('Indiquer la file active (patients éligibles par mois, d\'après les registres de l\'année précédente) et le taux de participation attendu.', 'State the active caseload (eligible patients per month, from last year\'s registers) and the expected participation rate.')));
      } else {
        add(ReviewFinding('recruitment_ok', ReviewLevel.ok, Step.studyPlan, tr('Recrutement compatible avec l\'effectif', 'Recruitment compatible with the sample size'),
            tr('${_fmt(rate, 1)} sujets par mois pendant $months mois : ${(rate * months).floor()} sujets possibles pour $planned prévus.', '${_fmt(rate, 1)} subjects per month for $months months: ${(rate * months).floor()} possible for $planned planned.'), ''));
      }
    }
  }

  // ---- 4 quinquies. Variables à recueillir ----
  if (imported) {
    final vars = protocolVariables(p);
    if (vars.isEmpty && prot('variables').isEmpty) {
      add(ReviewFinding('variables_missing', ReviewLevel.missing, Step.dataControl, tr('Variables à recueillir non listées', 'Variables to collect not listed'),
          tr('Sans liste des variables (et de leur définition), la fiche de recueil et la base de données ne peuvent pas être préparées, et l\'analyse ajustée n\'est pas vérifiable.', 'Without a list of variables (and their definitions), the case report form and database cannot be prepared, and the adjusted analysis cannot be checked.'),
          tr('Lister les variables : identifiant, critère principal, exposition, facteurs d\'ajustement, avec unité et modalités.', 'List the variables: identifier, primary outcome, exposure, adjustment factors, with unit and levels.')));
    } else if (vars.isNotEmpty && p.dataset != null) {
      final names = [for (final n in p.dataset!.names) _slug(n)];
      final absent = [for (final v in vars) if (!names.any((n) => n == v.code || n.contains(v.code) || v.code.contains(n) && n.length >= 3)) v];
      if (absent.isNotEmpty) {
        add(ReviewFinding('variables_absent', ReviewLevel.warning, Step.dataControl, tr('Variables prévues absentes des données', 'Planned variables absent from the data'),
            tr('${absent.length} variable(s) prévue(s) par le protocole ne se retrouve(nt) pas dans le fichier de données : ${absent.map((v) => v.label).take(12).join(', ')}${absent.length > 12 ? '…' : ''}.',
                '${absent.length} variable(s) planned in the protocol are not found in the data file: ${absent.map((v) => v.label).take(12).join(', ')}${absent.length > 12 ? '…' : ''}.'),
            tr('Vérifier les noms de colonnes (le dictionnaire de données tiré du protocole donne les noms proposés) ou justifier l\'absence.', 'Check the column names (the data dictionary drawn from the protocol gives the proposed names) or justify the absence.')));
      }
    }
  }

  // ---- 4 sexies. Résultats confrontés au protocole (étape 8) ----
  final res = p.resultsText.trim();
  final nRes = _n(res);
  if (res.isNotEmpty || p.journal.isNotEmpty) {
    // Critère principal annoncé, rapporté, ou remplacé.
    final outWords = [for (final w in _n(q.outcome).split(RegExp(r"[^a-z0-9]+"))) if (w.length > 3 && !_stop.contains(w)) w];
    if (res.isNotEmpty && outWords.isNotEmpty) {
      final declared = RegExp(r"(?:critere (?:de jugement )?principal|primary (?:outcome|endpoint))[^.:]{0,25}?(?:est|etait|:|a ete|is|was)\s+(?:la |le |l'|les |the )?([^.,;]{3,60})").firstMatch(nRes);
      if (declared != null && !outWords.any((w) => declared.group(1)!.contains(w))) {
        add(ReviewFinding('outcome_switch', ReviewLevel.error, Step.interpretation, tr('Critère principal changé entre protocole et résultats', 'Primary outcome changed between protocol and results'),
            tr('Le protocole annonce « ${q.outcome} » ; les résultats présentent un autre critère principal. Changer de critère après avoir vu les données est un biais de publication sélective.',
                'The protocol states "${q.outcome}"; the results present another primary outcome. Switching outcome after seeing the data is selective reporting bias.'),
            tr('Rapporter d\'abord le critère principal prévu ; présenter l\'autre comme secondaire, en signalant le changement et sa raison.', 'Report the planned primary outcome first; present the other as secondary, stating the change and its reason.'),
            evidence: _quote(res, RegExp(RegExp.escape(declared.group(0)!.substring(0, math.min(30, declared.group(0)!.length)))))));
      } else if (!outWords.any((w) => nRes.contains(w.substring(0, math.min(w.length, 6))))) {
        add(ReviewFinding('outcome_not_reported', ReviewLevel.warning, Step.interpretation, tr('Critère principal non retrouvé dans les résultats', 'Primary outcome not found in the results'),
            tr('Le texte de résultats ne mentionne pas « ${q.outcome} », le critère principal du protocole.', 'The results text does not mention "${q.outcome}", the protocol\'s primary outcome.'),
            tr('Présenter en premier le résultat du critère principal (effet et IC à 95 %), qu\'il soit significatif ou non.', 'Present the primary outcome result first (effect and 95% CI), whether significant or not.')));
      }
    }
    // Effectif atteint.
    final plannedN = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
    final m = RegExp(r"(\d{2,6})\s*(?:patients?|sujets?|participants?|femmes|enfants|malades|cas)\s*(?:ont ete |ont |were |have been )?(?:inclus|analyses|recrutes|enrolled|included|analysed|analyzed)").firstMatch(nRes);
    final attained = p.dataset?.rowCount ?? (m == null ? null : int.parse(m.group(1)!));
    if (plannedN != null && attained != null) {
      final pct = attained / plannedN;
      if (pct < 0.8) {
        add(ReviewFinding('sample_attained', ReviewLevel.warning, Step.interpretation, tr('Effectif prévu non atteint', 'Planned sample size not reached'),
            tr('$attained sujets analysés pour $plannedN prévus (${_fmt(pct * 100, 0)} %) : la puissance est inférieure à celle visée ; un résultat non significatif ne permet pas de conclure à l\'absence d\'effet.',
                '$attained subjects analysed for $plannedN planned (${_fmt(pct * 100, 0)}%): power is below target; a non-significant result does not show absence of effect.'),
            tr('Le dire dans la discussion et s\'appuyer sur l\'IC à 95 % plutôt que sur la valeur de p.', 'State it in the discussion and rely on the 95% CI rather than the p-value.')));
      } else {
        add(ReviewFinding('sample_attained_ok', ReviewLevel.ok, Step.interpretation, tr('Effectif atteint', 'Sample size reached'),
            tr('$attained sujets pour $plannedN prévus (${_fmt(pct * 100, 0)} %).', '$attained subjects for $plannedN planned (${_fmt(pct * 100, 0)}%).'), ''));
      }
    }
    // Analyses faites mais non prévues.
    final planAll = _n([prot('analysis'), p.analysisPlan].join('\n'));
    final unplanned = <String>[];
    for (final e in p.journal) {
      final re = _planned(e.methodId);
      if (re != null && !RegExp(re).hasMatch(planAll) && !unplanned.contains(e.methodName)) unplanned.add(e.methodName);
    }
    if (unplanned.isNotEmpty) {
      add(ReviewFinding('unplanned_analysis', ReviewLevel.warning, Step.interpretation, tr('Analyses réalisées mais non prévues au plan', 'Analyses performed but not planned'),
          tr('${unplanned.join(' ; ')} : absentes du plan d\'analyse. Présentées comme confirmatoires, elles exposent aux résultats trouvés par hasard.', '${unplanned.join('; ')}: absent from the analysis plan. Presented as confirmatory, they expose to chance findings.'),
          tr('Les présenter comme exploratoires, ou ajouter au plan (daté) la raison du changement.', 'Present them as exploratory, or add to the (dated) plan the reason for the change.'),
          fix: res.isEmpty
              ? null
              : ReviewFix(tr('Mention « exploratoire » ajoutée aux résultats', '"Exploratory" statement added to the results'), (p) {
                  p.resultsText = '${p.resultsText.trimRight()}\n\n${tr('Analyses non prévues au protocole, présentées à titre exploratoire : ${unplanned.join(' ; ')}.', 'Analyses not planned in the protocol, presented as exploratory: ${unplanned.join('; ')}.')}';
                })));
    }
    // Sous-groupes non annoncés.
    final sub = RegExp(r"sous-groupes?|chez les (hommes|femmes)|selon (le sexe|l'age|la tranche)|stratifie|subgroups?|among (men|women)");
    if (sub.hasMatch(nRes) && !RegExp(r"sous-groupes?|interaction|stratifi|subgroup").hasMatch(planAll) && !RegExp(r"sous-groupes?[^.]{0,80}(exploratoire|non prevue|pas prevue)|subgroups?[^.]{0,80}(exploratory|not planned)").hasMatch(nRes)) {
      add(ReviewFinding('subgroups', ReviewLevel.warning, Step.interpretation, tr('Analyses en sous-groupes non annoncées', 'Subgroup analyses not pre-specified'),
          tr('Des résultats par sous-groupe sont présentés sans avoir été prévus ni testés par une interaction : une différence entre sous-groupes est souvent due au hasard.', 'Subgroup results are presented without being planned or tested by an interaction: a difference between subgroups is often due to chance.'),
          tr('Les signaler comme exploratoires ; comparer les sous-groupes par un test d\'interaction, pas par deux valeurs de p.', 'Flag them as exploratory; compare subgroups with an interaction test, not with two p-values.'),
          evidence: _quote(res, sub),
          fix: ReviewFix(tr('Mention « sous-groupes exploratoires » ajoutée aux résultats', '"Exploratory subgroups" statement added to the results'), (p) {
            p.resultsText = '${p.resultsText.trimRight()}\n\n${tr('Les analyses en sous-groupes n\'étaient pas prévues au protocole : elles sont exploratoires et n\'ont pas fait l\'objet d\'un test d\'interaction préalable.', 'Subgroup analyses were not planned in the protocol: they are exploratory and were not pre-specified with an interaction test.')}';
          })));
    }
    // Valeur de p sans intervalle de confiance.
    if (RegExp(r"\bp\s*[<=>≤≥]\s*0?[.,]\d").hasMatch(nRes) && !RegExp(r"\bic\b|intervalle de confiance|\bci\b|confidence interval|\[\s*-?\d").hasMatch(nRes)) {
      add(ReviewFinding('p_without_ci', ReviewLevel.warning, Step.interpretation, tr('Valeurs de p sans intervalle de confiance', 'p-values without confidence intervals'),
          tr('Une valeur de p ne dit ni la taille ni la précision de l\'effet ; les recommandations (CONSORT, STROBE) demandent l\'estimation avec son IC à 95 %.', 'A p-value tells neither the size nor the precision of the effect; guidelines (CONSORT, STROBE) require the estimate with its 95% CI.'),
          tr('Rapporter chaque effet (OR, RR, différence…) avec son IC à 95 %, la valeur de p en complément.', 'Report each effect (OR, RR, difference…) with its 95% CI, the p-value as a complement.'),
          evidence: _quote(res, RegExp(r"\bp\s*[<=>≤≥]\s*0?[.,]\d"))));
    }
  }

  // ---- 5. Éthique (protocole importé) ----
  if (imported && prot('ethics').isEmpty && !RegExp(r"ethique|consentement|comite|helsinki|ethics|consent").hasMatch(nAll)) {
    add(ReviewFinding('ethics', ReviewLevel.missing, Step.studyPlan, tr('Aspects éthiques absents', 'Ethical aspects missing'),
        tr('Avis d\'un comité d\'éthique, consentement éclairé et confidentialité sont exigés pour toute recherche sur des personnes.', 'Ethics committee approval, informed consent and confidentiality are required for any research on human participants.'),
        tr('Ajouter une rubrique : comité d\'éthique sollicité, modalités du consentement, anonymisation et conservation des données.', 'Add a section: ethics committee, consent procedure, anonymisation and data retention.')));
  }
  return ProjectReview(out);
}

/// « l'effet de X sur Y » → « l'association entre X et Y » (null si la tournure n'est pas reconnue).
String? _associationWording(String text) {
  final re = RegExp(r"(l'|le |un |the )?\b(effets?|impacts?|influences?|efficacité|effect|impact)\s+(de la |de l'|du |des |de |d'|of )(.+?)\s+(sur|on)\s+", caseSensitive: false);
  final m = re.firstMatch(text);
  if (m == null) return null;
  final art = switch (m.group(3)!.toLowerCase()) {
    'de la ' => 'la ',
    "de l'" => "l'",
    'du ' => 'le ',
    'des ' => 'les ',
    _ => '',
  };
  final en = m.group(5)!.toLowerCase() == 'on';
  final indefinite = (m.group(1) ?? '').toLowerCase() == 'un ';
  final lead = en ? (indefinite ? 'an association between ' : 'the association between ') : (indefinite ? 'une association entre ' : "l'association entre ");
  final mid = en ? ' and ' : ' et ';
  final start = m.start == 0 ? lead[0].toUpperCase() + lead.substring(1) : lead;
  // « Quel est l'effet » → « Quelle est l'association » (accord au féminin).
  final before = text.substring(0, m.start).replaceFirstMapped(RegExp(r"\b([Qq])uel (est|sera|serait)\s*$"), (g) => '${g[1]}uelle ${g[2]} ');
  return '$before$start$art${m.group(4)}$mid${text.substring(m.end)}';
}

/// Applique la correction d'un constat et la trace dans le projet.
AppliedCorrection applyCorrection(Project p, ReviewFinding f, {String? date}) {
  f.fix!.apply(p);
  final c = AppliedCorrection(
      id: f.id, title: f.title, date: date ?? DateTime.now().toIso8601String().substring(0, 10), detail: f.fix!.detail, level: f.level.name, problem: f.problem, evidence: f.evidence);
  p.corrections.add(c);
  return c;
}

/// Applique toutes les corrections disponibles (la relecture est refaite après chacune).
List<AppliedCorrection> applyAllCorrections(Project p, {String? date}) {
  final done = <AppliedCorrection>[];
  final seen = <String>{};
  for (var k = 0; k < 50; k++) {
    ReviewFinding? next;
    for (final f in reviewProject(p).fixable) {
      if (!seen.contains(f.id)) {
        next = f;
        break;
      }
    }
    if (next == null) break;
    seen.add(next.id);
    done.add(applyCorrection(p, next, date: date));
  }
  return done;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _monthNames = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
const _numberWords = {'six': 6, 'neuf': 9, 'dix': 10, 'douze': 12, 'quinze': 15, 'dix-huit': 18, 'vingt': 20, 'vingt-quatre': 24, 'trente': 30, 'trente-six': 36, 'quarante-huit': 48, 'soixante': 60};

/// Durée de l'étude en mois : « 36 mois », « trente-six mois », « 2 ans », « du 1 avril au 31 décembre 2023 ».
int? _studyMonths(String text) {
  final t = _n(text);
  final mo = _monthNames.join('|');
  final range = RegExp('(?:du\\s+)?(?:\\d{1,2}(?:er)?\\s+)?($mo)\\s*(\\d{4})?\\s*(?:-|–|a|au|to)\\s*(?:(?:le\\s+)?\\d{1,2}\\s+)?($mo)\\s*(\\d{4})?').firstMatch(t);
  if (range != null) {
    final m1 = _monthNames.indexOf(range.group(1)!), m2 = _monthNames.indexOf(range.group(3)!);
    final y2 = int.tryParse(range.group(4) ?? '') ?? 0, y1 = int.tryParse(range.group(2) ?? '') ?? y2;
    var d = (y2 * 12 + m2) - (y1 * 12 + m1) + 1;
    if (d <= 0) d += 12;
    return d;
  }
  final m = RegExp(r"(?:duree|pendant|sur|period|over|durant|etalera|deroulera)[^.]{0,40}?(\d{1,3}|" + _numberWords.keys.join('|') + r")\s*(mois|ans?|annees?|months?|years?)").firstMatch(t);
  if (m == null) return null;
  final v = int.tryParse(m.group(1)!) ?? _numberWords[m.group(1)!];
  if (v == null) return null;
  return m.group(2)!.startsWith('mois') || m.group(2)!.startsWith('month') ? v : v * 12;
}

/// Nombre de centres participants (« 5 centres », « cinq centres », « Le nombre de centre participant = 5 »).
int? _centres(String t) {
  final m = RegExp(r"(\d{1,2}|deux|trois|quatre|cinq|six|sept|huit|dix)\s+(?:centres|sites|hopitaux|structures)|nombre de centres?[^.=]{0,20}=\s*(\d{1,2})").firstMatch(t);
  if (m == null) return null;
  const w = {'deux': 2, 'trois': 3, 'quatre': 4, 'cinq': 5, 'six': 6, 'sept': 7, 'huit': 8, 'dix': 10};
  final g = m.group(1) ?? m.group(2)!;
  return int.tryParse(g) ?? w[g];
}

/// Capacité de recrutement déclarée, ramenée au mois (« 20 patients par mois », « 5 nouveaux cas par semaine »).
double? _recruitmentPerMonth(String t) {
  final m = RegExp(r"(\d{1,4})\s*(?:nouveaux?\s+|nouvelles?\s+)?(?:patients?|cas|malades|consultations|admissions|sujets|femmes|enfants|blesses|participants)\s*(?:eligibles?\s*)?(?:\(\w+\)\s*)?(?:par|/)\s*(jour|semaine|mois|an|annee|day|week|month|year)").firstMatch(t);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return switch (m.group(2)!) {
    'jour' || 'day' => v * 30.4,
    'semaine' || 'week' => v * 4.35,
    'an' || 'annee' || 'year' => v / 12,
    _ => v,
  };
}

String _slug(String s) => _n(s).replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"^_+|_+$"), '');

/// Variable prévue par le protocole.
class PlannedVariable {
  final String label; // libellé tel qu'écrit
  final String code; // nom de colonne proposé
  final String type; // numérique | catégorielle
  const PlannedVariable(this.label, this.code, this.type);
}

const _categoricalWords = r"sexe|genre|profession|niveau|statut|mecanisme|traitements?|ethnie|residence|situation|groupe|type|antecedents?|origine|service|centre|lieu|stade|classe|mode|etat|consentement|tabagisme|alcool|vaccination";

/// Variables énumérées dans la rubrique « variables » du protocole (« … comprendront le sexe, l'âge, le poids et la
/// taille »), avec un nom de colonne et un type proposés ; l'abréviation entre parenthèses sert de nom quand elle existe.
List<PlannedVariable> protocolVariables(Project p) {
  final text = p.protocol['variables'] ?? '';
  if (text.isEmpty) return const [];
  final out = <PlannedVariable>[];
  final seen = <String>{};
  // Phrases (le point d'un décimal ne coupe pas).
  for (final sentence in text.split(RegExp(r"(?<!\d)\.(?!\d)|\n"))) {
    var t = sentence.replaceAll('’', "'");
    final trig = RegExp(r":|comprendront|comprennent|comprendra|incluront|incluent|inclura|il s'agissait de|il s'agit de|à travers|a travers|à savoir|notamment|tels? que|telles? que|suivantes?|suivants?|including|includes?|such as|namely", caseSensitive: false);
    final ms = trig.allMatches(t).toList();
    if (ms.isNotEmpty) t = t.substring(ms.last.end);
    // Parenthèses : abréviation retenue comme nom, le reste retiré.
    final abbrev = <String, String>{};
    t = t.replaceAllMapped(RegExp(r"([^,()]+?)\s*\(([^()]*)\)"), (m) {
      final inner = m.group(2)!.trim();
      final code = inner.split(RegExp(r"[,;]")).last.trim();
      final label = m.group(1)!;
      if (RegExp(r"^[A-Za-z][A-Za-z0-9²⁺⁻₂₃]{1,7}$").hasMatch(code)) abbrev[label.trim()] = code;
      return label;
    });
    final items = [for (final x in t.split(RegExp(r",|;|\s+et\s+|\s+ainsi que\s+|\s+and\s+"))) x.trim()];
    final good = <String>[];
    for (var it in items) {
      it = it.replaceFirst(RegExp(r"^(?:enfin|puis|aussi)\s+", caseSensitive: false), '');
      it = it.replaceFirst(RegExp(r"^(?:de la |de l'|du |des |de |d'|le |la |les |l'|un |une |the )+", caseSensitive: false), '').trim();
      final words = it.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).length;
      if (it.length < 2 || it.length > 60 || words > 6) continue;
      if (RegExp(r"\b(sera|seront|est|sont|etait|été|will|were|was)\b", caseSensitive: false).hasMatch(it)) continue;
      good.add(it);
    }
    if (good.length < 2) continue;
    for (final it in good) {
      String? ab;
      for (final e in abbrev.entries) {
        if (e.key.endsWith(it) || it.endsWith(e.key.replaceFirst(RegExp(r"^(?:de la |de l'|du |des |de |d'|le |la |les |l')+", caseSensitive: false), ''))) ab = e.value;
      }
      final base = ab ?? it;
      var code = _slug(base.replaceAll('²', '2').replaceAll('₂', '2').replaceAll('₃', '3').replaceAll(RegExp(r"[⁺⁻]"), ''));
      if (ab == null) code = code.split('_').where((w) => w.length > 2 || w == 'ph' || RegExp(r"\d").hasMatch(w)).take(3).join('_');
      if (code.isEmpty || !seen.add(code)) continue;
      final type = RegExp(_categoricalWords).hasMatch(_n(it)) ? tr('catégorielle', 'categorical') : tr('numérique', 'numeric');
      out.add(PlannedVariable(it, code, type));
    }
  }
  return out;
}

/// Dictionnaire de données (CSV, séparateur « ; ») tiré du protocole : variable, type, libellé, unité ; à compléter puis
/// à importer avec les données à l'étape 4.
String protocolDictionaryCsv(Project p) {
  final rows = <List<String>>[
    ['variable', 'type', tr('libelle', 'label'), tr('unite', 'unit')],
    ['id', tr('identifiant', 'identifier'), tr('Identifiant anonyme du participant', 'Anonymous participant identifier'), ''],
    for (final v in protocolVariables(p)) [v.code, v.type, v.label, ''],
  ];
  String cell(String c) => c.contains(';') || c.contains('"') ? '"${c.replaceAll('"', '""')}"' : c;
  return '${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
}

const _stop = {'avec', 'sans', 'pour', 'dans', 'chez', 'apres', 'avant', 'jours', 'mois', 'semaines', 'with', 'from', 'days', 'months', 'oui', 'non'};

/// Mots du plan d'analyse qui montrent qu'une méthode était prévue (null : méthode descriptive ou de planification).
String? _planned(String methodId) {
  final id = methodId;
  if (id.startsWith('describe') || id.startsWith('sample_size') || id.startsWith('power') || id == 'multiple_imputation') return null;
  if (id.contains('logistic') || id == 'firth_logistic') return r"logisti";
  if (id == 'linear_regression' || id == 'restricted_cubic_spline') return r"regression lineaire|lineaire|linear regression|spline";
  if (id == 'poisson_robust' || id == 'count_regression') return r"poisson|binomiale negative|comptage|negative binomial";
  if (id == 'cox' || id == 'fine_gray' || id == 'cumulative_incidence') return r"\bcox\b|fine|gray|survie|concurren|survival|competing";
  if (id == 'kaplan_meier' || id == 'rmst' || id == 'landmark') return r"kaplan|survie|log-?rank|survival";
  if (id.startsWith('t_test') || id == 'paired_t_test') return r"student|\bt de\b|test t|t-test|welch";
  if (id == 'mann_whitney' || id == 'wilcoxon_signed_rank') return r"mann|wilcoxon|non parametrique|nonparametric";
  if (id.startsWith('anova')) return r"anova|analyse de (la )?variance";
  if (id == 'kruskal_wallis') return r"kruskal";
  if (id == 'chi_square_rxc' || id == 'two_by_two' || id == 'mcnemar') return r"khi|chi|fisher|mcnemar|proportions?";
  if (id == 'pearson' || id == 'spearman') return r"correl|pearson|spearman";
  if (id == 'proportion_ci') return r"proportion|prevalence|frequence|pourcentage";
  if (id.startsWith('meta')) return r"meta";
  if (id.startsWith('prediction') || id.startsWith('external_validation') || id == 'calibration') return r"predict|score|modele|calibration";
  if (id == 'bland_altman' || id == 'passing_bablok' || id == 'deming') return r"bland|passing|deming|accord|agreement";
  if (id.startsWith('propensity')) return r"propension|propensity";
  if (id == 'lmm_longitudinal' || id == 'gee' || id == 'glmm_longitudinal') return r"mixte|repet|longitudin|gee|mixed";
  if (id == 'diagnostic_accuracy') return r"sensibilite|specificite|sensitivity|specificity";
  return null;
}

/// Durée de l'étude (mois), capacité de recrutement (sujets par mois) et nombre de centres lus dans le protocole.
int? protocolStudyMonths(Project p) => p.protocol.isEmpty
    ? null
    : _studyMonths([p.protocol['design'] ?? '', p.protocol['period'] ?? '', p.protocol['sampleSize'] ?? '', p.protocol['_text'] ?? ''].join('\n'));
double? protocolRecruitmentPerMonth(Project p) => _recruitmentPerMonth(_n([...p.protocol.values].join('\n')));
int? protocolCentres(Project p) => _centres(_n([...p.protocol.values].join('\n')));
