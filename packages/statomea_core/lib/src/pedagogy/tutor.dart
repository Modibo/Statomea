/// Mode tuteur : une question de compréhension par étape du projet, adaptée au projet de l'étudiant quand c'est
/// possible (type de son critère, mesure d'effet légitime pour son plan, méthode recommandée pour sa question,
/// conditions à vérifier, portée causale), avec un indice au premier essai manqué et une explication ; la progression
/// est enregistrée dans le projet ([Project.tutor]) et récapitulée pour l'encadrant.
library;

import 'dart:math' as math;

import '../advisor/advisor.dart';
import '../advisor/registry.dart';
import '../i18n.dart';
import '../model/design.dart';
import '../project/project.dart';

class TutorQuestion {
  final Step step;
  final String prompt;
  final List<String> options;
  final int correct;
  final String hint;
  final String explanation;
  final bool personalised; // tirée du projet de l'étudiant
  const TutorQuestion(this.step, this.prompt, this.options, this.correct, this.hint, this.explanation, {this.personalised = false});
}

class TutorStepProgress {
  final Step step;
  final int attempts;
  final bool solved;
  final String date;
  const TutorStepProgress(this.step, this.attempts, this.solved, this.date);
}

/// Place la bonne réponse à une position qui dépend de l'étape (pas toujours la première).
TutorQuestion _q(Step s, String prompt, String right, List<String> wrong, String hint, String explanation, {bool personalised = false}) {
  final opts = [right, ...wrong.where((w) => w != right).take(3)];
  final shift = s.index % opts.length;
  final rotated = [...opts.sublist(opts.length - shift), ...opts.sublist(0, opts.length - shift)];
  return TutorQuestion(s, prompt, rotated, rotated.indexOf(right), hint, explanation, personalised: personalised);
}

/// Les dix questions du projet, dans l'ordre des étapes.
List<TutorQuestion> tutorQuestions(Project p) {
  final q = p.question;
  final out = <TutorQuestion>[];

  // 1. Question : type du critère de jugement.
  final types = {
    OutcomeType.binary: tr('binaire (oui / non)', 'binary (yes / no)'),
    OutcomeType.continuous: tr('quantitatif continu', 'continuous'),
    OutcomeType.timeToEvent: tr('délai jusqu\'à un événement (avec censure)', 'time to an event (with censoring)'),
    OutcomeType.count: tr('nombre d\'événements (comptage)', 'number of events (count)'),
    OutcomeType.ordinal: tr('ordinal (classes ordonnées)', 'ordinal (ordered classes)'),
  };
  if (q.outcome.isNotEmpty && types.containsKey(q.outcomeType)) {
    out.add(_q(Step.question, tr('Quel est le type de votre critère de jugement « ${q.outcome} » ?', 'What type is your outcome "${q.outcome}"?'), types[q.outcomeType]!,
        [for (final e in types.entries) if (e.key != q.outcomeType) e.value],
        tr('Demandez-vous comment le critère est mesuré pour chaque participant : une réponse oui/non, une valeur, une date d\'événement, un nombre ?', 'Ask how the outcome is measured for each participant: a yes/no answer, a value, an event date, a number?'),
        tr('Le type du critère fixe toute la suite : mesure d\'effet, méthode, calcul d\'effectif.', 'The outcome type determines everything that follows: effect measure, method, sample size.'), personalised: true));
  } else {
    out.add(_q(Step.question, tr('Que doit préciser une question de recherche complète ?', 'What must a complete research question specify?'),
        tr('La population, l\'exposition, le comparateur, le critère de jugement et son horizon', 'The population, exposure, comparator, outcome and its time horizon'),
        [tr('Le logiciel et le test statistique', 'The software and statistical test'), tr('Le titre et les mots-clés', 'The title and keywords'), tr('Le nombre de variables recueillies', 'The number of variables collected')],
        tr('Pensez à l\'acronyme PICO.', 'Think of the PICO acronym.'), tr('Une question PICO complète permet de choisir le plan, la méthode et l\'effectif.', 'A complete PICO question allows the design, method and sample size to be chosen.')));
  }

  // 2. Plan d'étude : mesure d'effet légitime.
  final measures = [tr('Risque relatif (RR)', 'Relative risk (RR)'), tr('Odds ratio (OR)', 'Odds ratio (OR)'), tr('Rapport de prévalences', 'Prevalence ratio'), tr('Hazard ratio (HR)', 'Hazard ratio (HR)')];
  final diff = tr('Différence de moyennes', 'Difference in means');
  final right = q.outcomeType == OutcomeType.continuous && q.design != StudyDesign.unknown && q.design != StudyDesign.caseControl
      ? diff
      : switch (q.design) {
          StudyDesign.caseControl => measures[1],
          StudyDesign.crossSectional => measures[2],
          StudyDesign.cohort || StudyDesign.rct => q.outcomeType == OutcomeType.timeToEvent ? measures[3] : measures[0],
          _ => null,
        };
  if (q.objective == StudyObjective.predictive) {
    out.add(_q(Step.studyPlan, tr('Votre objectif est de prédire « ${q.outcome.isEmpty ? 'l\'issue' : q.outcome} ». Quelle mesure décrit la capacité du modèle à distinguer les patients qui auront l\'événement de ceux qui ne l\'auront pas ?', 'Your aim is to predict "${q.outcome.isEmpty ? 'the outcome' : q.outcome}". Which measure describes the model\'s ability to separate patients who will have the event from those who will not?'),
        tr('L\'aire sous la courbe ROC (statistique C)', 'The area under the ROC curve (C statistic)'),
        [tr('Le risque relatif de chaque prédicteur', 'The relative risk of each predictor'), tr('La valeur de p du test global', 'The p-value of the global test'), tr('Le nombre de prédicteurs significatifs', 'The number of significant predictors')],
        tr('On parle de discrimination : classer les patients à haut risque avant ceux à bas risque.', 'This is discrimination: ranking high-risk patients above low-risk ones.'),
        tr('La discrimination se mesure par l\'AUC (statistique C) ; elle se complète par la calibration (risques prédits proches des risques observés).', 'Discrimination is measured by the AUC (C statistic); it is complemented by calibration (predicted risks close to observed risks).'), personalised: true));
  } else if (right != null) {
    out.add(_q(Step.studyPlan, tr('Plan de votre étude : ${designLabel(q.design).toLowerCase()} ; critère ${types[q.outcomeType] ?? 'non précisé'}. Quelle mesure d\'association est la plus adaptée ?', 'Your study design: ${designLabel(q.design).toLowerCase()}; outcome ${types[q.outcomeType] ?? 'not specified'}. Which measure of association is most appropriate?'),
        right, [for (final m in [...measures, diff]) if (m != right) m],
        q.design == StudyDesign.caseControl
            ? tr('En cas-témoins, la proportion de malades est fixée par le recrutement : peut-on calculer un risque ?', 'In a case-control study the proportion of cases is fixed by recruitment: can a risk be computed?')
            : tr('Que mesure le plan : une incidence, une prévalence, un délai ?', 'What does the design measure: incidence, prevalence, time?'),
        tr('La mesure d\'effet découle du plan et du critère : différence de moyennes pour un critère quantitatif, RR en cohorte ou essai, OR en cas-témoins, rapport de prévalences en transversal, HR pour un délai avec censure.', 'The effect measure follows from the design and outcome: difference in means for a quantitative outcome, RR in a cohort or trial, OR in a case-control study, prevalence ratio in a cross-sectional study, HR for time to event with censoring.'), personalised: true));
  } else {
    out.add(_q(Step.studyPlan, tr('Quel plan d\'étude permet de mesurer une incidence ?', 'Which study design measures incidence?'), tr('La cohorte', 'The cohort'),
        [tr('L\'étude transversale', 'The cross-sectional study'), tr('L\'étude cas-témoins', 'The case-control study'), tr('La série de cas', 'The case series')],
        tr('L\'incidence compte les nouveaux cas pendant un suivi.', 'Incidence counts new cases during follow-up.'), tr('Seul un suivi dans le temps (cohorte, essai) mesure l\'incidence ; le transversal mesure une prévalence.', 'Only follow-up over time (cohort, trial) measures incidence; a cross-sectional study measures prevalence.')));
  }

  // 3. Plan d'analyse.
  out.add(_q(Step.analysisPlan, tr('Pourquoi écrire le plan d\'analyse avant de voir les données ?', 'Why write the analysis plan before seeing the data?'),
      tr('Pour ne pas choisir l\'analyse en fonction des résultats', 'So as not to choose the analysis according to the results'),
      [tr('Parce que le comité d\'éthique l\'exige seulement', 'Only because the ethics committee requires it'), tr('Pour gagner du temps lors de la saisie', 'To save time during data entry'), tr('Pour pouvoir changer de critère principal plus tard', 'To be able to change the primary outcome later')],
      tr('Que se passe-t-il si l\'on essaie plusieurs analyses et que l\'on garde la « meilleure » ?', 'What happens if several analyses are tried and the "best" one is kept?'),
      tr('Fixé à l\'avance, le plan protège contre la sélection des résultats (p-hacking) ; tout écart doit être signalé.', 'Set in advance, the plan protects against selective reporting (p-hacking); any deviation must be reported.')));

  // 4. Contrôle des données.
  out.add(_q(Step.dataControl, tr('Vous trouvez un âge de 250 ans dans le fichier. Que faire ?', 'You find an age of 250 years in the file. What should you do?'),
      tr('Vérifier la source, corriger avec une justification tracée, en gardant la valeur d\'origine', 'Check the source, correct with a logged justification, keeping the original value'),
      [tr('Supprimer la ligne sans le dire', 'Delete the row without saying so'), tr('Remplacer par la moyenne de l\'âge', 'Replace with the mean age'), tr('Laisser tel quel : le test est robuste', 'Leave it: the test is robust')],
      tr('Un relecteur doit pouvoir retrouver ce qui a été modifié et pourquoi.', 'A reviewer must be able to see what was changed and why.'),
      tr('Toute correction est tracée (valeur d\'origine, nouvelle valeur, raison, date) : c\'est la base de la reproductibilité.', 'Every correction is logged (original value, new value, reason, date): this is the basis of reproducibility.')));

  // 5. Choix de la méthode : méthode recommandée pour la question.
  final a = advise(q);
  final main = a.options.where((o) => o.recommended).firstOrNull ?? a.options.firstOrNull;
  if (main != null) {
    final others = [
      for (final m in methodRegistry)
        if (m.id != main.methodId && !main.name.contains(m.name) && m.category != methodInfo(main.methodId)?.category && !_specialised(m.id)) m.name
    ];
    others.shuffle(_Rng(main.methodId.hashCode));
    out.add(_q(Step.methodChoice, tr('Quelle méthode principale convient à votre question ?', 'Which main method suits your question?'), main.name, others.take(3).toList(),
        tr('Repartez du type de critère, du plan et de l\'objectif (décrire, expliquer, prédire).', 'Go back to the outcome type, design and aim (describe, explain, predict).'),
        '${main.name}${tr(' : ', ': ')}${main.whenPreferred}', personalised: true));
  } else {
    out.add(_q(Step.methodChoice, tr('Pour comparer une moyenne entre deux groupes indépendants dont la distribution est asymétrique, on utilise :', 'To compare a mean between two independent groups with a skewed distribution, use:'),
        tr('Le test de Mann-Whitney', 'The Mann-Whitney test'), [tr('Le test de Kruskal-Wallis', 'The Kruskal-Wallis test'), tr('Le test du χ²', 'The χ² test'), tr('Le test t apparié', 'The paired t-test')],
        tr('Deux groupes, non paramétrique, indépendants.', 'Two groups, non-parametric, independent.'), tr('Mann-Whitney est l\'équivalent non paramétrique du test t pour deux groupes ; Kruskal-Wallis vaut pour trois groupes ou plus.', 'Mann-Whitney is the non-parametric counterpart of the t-test for two groups; Kruskal-Wallis is for three groups or more.')));
  }

  // 6. Calcul : sens d'un IC.
  out.add(_q(Step.computation, tr('Votre résultat est donné avec un IC à 95 %. Que signifie cet intervalle ?', 'Your result is given with a 95% CI. What does this interval mean?'),
      tr('L\'ensemble des valeurs de l\'effet compatibles avec les données ; la méthode encadre la vraie valeur 95 fois sur 100', 'The set of effect values compatible with the data; the method captures the true value 95 times out of 100'),
      [tr('95 % des patients ont une valeur dans cet intervalle', '95% of patients have a value in this interval'), tr('Il y a 95 % de chances que le résultat soit juste', 'There is a 95% chance the result is correct'), tr('L\'effet est significatif s\'il est large', 'The effect is significant if it is wide')],
      tr('L\'IC porte sur l\'effet (la moyenne, l\'OR…), pas sur les patients.', 'The CI concerns the effect (mean, OR…), not the patients.'),
      tr('Un IC étroit traduit une estimation précise ; un IC qui contient la valeur nulle (0 ou 1) n\'exclut pas l\'absence d\'effet.', 'A narrow CI reflects a precise estimate; a CI that contains the null value (0 or 1) does not rule out no effect.')));

  // 7. Diagnostics : condition de la méthode choisie.
  final info = main == null ? null : methodInfo(main.methodId);
  if (info != null && info.conditions.isNotEmpty) {
    // Distracteurs : conditions d'autres méthodes cliniques, sans mot important commun avec les bonnes conditions.
    final key = {for (final c in info.conditions) ...c.toLowerCase().split(RegExp(r'[^a-zàâçéèêëîïôûùüÿœ]+')).where((w) => w.length >= 6).map((w) => w.substring(0, 6))};
    final wrong = [
      for (final m in methodRegistry)
        if (m.id != info.id && m.category != info.category && !_specialised(m.id))
          for (final c in m.conditions.take(1))
            if (!info.conditions.contains(c) && !c.toLowerCase().split(RegExp(r'[^a-zàâçéèêëîïôûùüÿœ]+')).any((w) => w.length >= 6 && key.contains(w.substring(0, 6)))) c
    ]..shuffle(_Rng(info.id.hashCode));
    // Condition formulée positivement (« Pas en cas-témoins » ferait une mauvaise réponse à cocher).
    final cond = info.conditions.firstWhere((c) => !RegExp(r'^(pas |not |aucun|no )', caseSensitive: false).hasMatch(c), orElse: () => info.conditions.first);
    out.add(_q(Step.diagnostics, tr('Quelle condition faut-il vérifier pour ${info.name} ?', 'Which condition must be checked for ${info.name}?'), cond, wrong.take(3).toList(),
        tr('Revoyez la fiche de la méthode : « Conditions à vérifier ».', 'Review the method\'s sheet: "Conditions to check".'),
        tr('Conditions de ${info.name} : ${info.conditions.join(' ; ')}.', 'Conditions for ${info.name}: ${info.conditions.join('; ')}.'), personalised: true));
  } else {
    out.add(_q(Step.diagnostics, tr('Dans une régression logistique, que vérifie-t-on en priorité ?', 'In a logistic regression, what is checked first?'),
        tr('Le nombre d\'événements par variable et la linéarité des variables continues', 'The number of events per variable and linearity of continuous variables'),
        [tr('La normalité de l\'issue', 'Normality of the outcome'), tr('L\'égalité des variances', 'Equality of variances'), tr('L\'absence de valeurs nulles', 'The absence of zero values')],
        tr('L\'issue est binaire : la normalité n\'a pas de sens.', 'The outcome is binary: normality is meaningless.'), tr('Trop peu d\'événements par variable rend les coefficients instables ; une variable continue non linéaire biaise l\'OR.', 'Too few events per variable makes coefficients unstable; a non-linear continuous variable biases the OR.')));
  }

  // 8. Interprétation : portée causale (ou, pour un modèle de prédiction, validité en dehors de l'échantillon).
  if (q.objective == StudyObjective.predictive) {
    out.add(_q(Step.interpretation, tr('Votre modèle a une bonne AUC après validation interne par bootstrap. Peut-on le recommander pour la pratique ?', 'Your model has a good AUC after internal bootstrap validation. Can it be recommended for practice?'),
        tr('Pas encore : il faut une validation externe et une évaluation de l\'utilité clinique', 'Not yet: external validation and an assessment of clinical utility are needed'),
        [tr('Oui, la validation interne suffit', 'Yes, internal validation is enough'), tr('Oui, si tous les prédicteurs sont significatifs', 'Yes, if all predictors are significant'), tr('Oui, si l\'effectif dépasse 500 patients', 'Yes, if the sample exceeds 500 patients')],
        tr('La validation interne corrige l\'optimisme mais reste sur la même population.', 'Internal validation corrects optimism but stays within the same population.'),
        tr('Un modèle doit être validé dans d\'autres centres ou périodes (validation externe), puis montrer un bénéfice clinique (courbe de décision) avant d\'être utilisé.', 'A model must be validated in other centres or periods (external validation), then show clinical benefit (decision curve) before use.'), personalised: true));
  } else if (q.design != StudyDesign.unknown) {
    final rct = q.design == StudyDesign.rct;
    out.add(_q(Step.interpretation, tr('Plan de votre étude : ${designLabel(q.design).toLowerCase()}. Une association significative permet-elle de conclure à un effet causal ?', 'Your study design: ${designLabel(q.design).toLowerCase()}. Does a significant association allow a causal conclusion?'),
        rct ? tr('Oui pour la comparaison randomisée du critère principal ; non pour les analyses secondaires', 'Yes for the randomised comparison of the primary outcome; not for secondary analyses') : tr('Non : on conclut à une association, la confusion résiduelle restant possible', 'No: we conclude on an association, residual confounding remaining possible'),
        [
          if (rct) tr('Non, jamais : seule la méta-analyse le permet', 'No, never: only meta-analysis allows it') else tr('Oui, si p < 0,05', 'Yes, if p < 0.05'),
          tr('Oui, si l\'effectif est grand', 'Yes, if the sample is large'),
          tr('Oui, après ajustement sur l\'âge et le sexe', 'Yes, after adjustment for age and sex'),
        ],
        tr('Qu\'est-ce que la randomisation garantit que les autres plans ne garantissent pas ?', 'What does randomisation guarantee that other designs do not?'),
        tr('La randomisation équilibre les facteurs de confusion, connus et inconnus ; sans elle, même ajustée, l\'association n\'est pas une preuve de causalité.', 'Randomisation balances confounders, known and unknown; without it, even adjusted, an association is not proof of causation.'), personalised: true));
  } else {
    out.add(_q(Step.interpretation, tr('Une corrélation forte entre deux variables prouve-t-elle que l\'une cause l\'autre ?', 'Does a strong correlation between two variables prove that one causes the other?'), tr('Non', 'No'),
        [tr('Oui si r > 0,8', 'Yes if r > 0.8'), tr('Oui si p < 0,001', 'Yes if p < 0.001'), tr('Oui si l\'effectif dépasse 1 000', 'Yes if the sample exceeds 1,000')],
        tr('Pensez à une troisième variable qui influencerait les deux.', 'Think of a third variable influencing both.'), tr('Corrélation n\'est pas causalité : confusion, causalité inverse et hasard sont possibles.', 'Correlation is not causation: confounding, reverse causation and chance are possible.')));
  }

  // 9. Audit : valeur de p.
  out.add(_q(Step.audit, tr('Un résultat donne p = 0,08. Quelle phrase est correcte ?', 'A result gives p = 0.08. Which sentence is correct?'),
      tr('Les données ne montrent pas de différence avec assez de certitude ; l\'IC indique les effets compatibles', 'The data do not show a difference with enough certainty; the CI shows the compatible effects'),
      [tr('Il n\'y a pas de différence entre les groupes', 'There is no difference between the groups'), tr('Il y a 8 % de chances que l\'hypothèse nulle soit vraie', 'There is an 8% chance the null hypothesis is true'), tr('La différence est presque significative, donc réelle', 'The difference is almost significant, hence real')],
      tr('« Absence de preuve » n\'est pas « preuve d\'absence ».', '"Absence of evidence" is not "evidence of absence".'),
      tr('Une valeur de p > 0,05 ne prouve pas l\'absence d\'effet ; on rapporte l\'estimation et son IC.', 'A p-value > 0.05 does not prove the absence of effect; report the estimate and its CI.')));

  // 10. Export : reproductibilité.
  out.add(_q(Step.export, tr('Pourquoi joindre le journal des calculs au rapport ?', 'Why attach the computation log to the report?'),
      tr('Pour que chaque résultat puisse être refait à l\'identique (données, corrections, options, version)', 'So that every result can be reproduced identically (data, corrections, options, version)'),
      [tr('Pour allonger le rapport', 'To lengthen the report'), tr('Parce que le logiciel l\'impose', 'Because the software requires it'), tr('Pour cacher les analyses non significatives', 'To hide non-significant analyses')],
      tr('Un relecteur doit pouvoir refaire vos calculs.', 'A reviewer must be able to redo your calculations.'),
      tr('Le journal garde l\'empreinte des données, les corrections, les options et la version du moteur : c\'est la reproductibilité.', 'The log keeps the data fingerprint, corrections, options and engine version: this is reproducibility.')));
  return out;
}

/// Générateur pseudo-aléatoire déterministe (mêmes distracteurs à chaque ouverture).
class _Rng implements math.Random {
  int _s;
  _Rng(int seed) : _s = seed & 0x7fffffff | 1;
  @override
  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }

  @override
  double nextDouble() => nextInt(1 << 30) / (1 << 30);
  @override
  bool nextBool() => nextInt(2) == 1;
}

/// Enregistre une réponse ; renvoie vrai si elle est juste.
bool answerTutor(Project p, TutorQuestion q, int choice, {String? date}) {
  final k = q.step.name;
  final attempts = (int.tryParse(p.tutor['attempts_$k'] ?? '') ?? 0) + 1;
  p.tutor['attempts_$k'] = '$attempts';
  final ok = choice == q.correct;
  if (ok && p.tutor['ok_$k'] == null) p.tutor['ok_$k'] = date ?? DateTime.now().toIso8601String().substring(0, 10);
  return ok;
}

List<TutorStepProgress> tutorProgress(Project p) => [
      for (final s in Step.values)
        TutorStepProgress(s, int.tryParse(p.tutor['attempts_${s.name}'] ?? '') ?? 0, p.tutor['ok_${s.name}'] != null, p.tutor['ok_${s.name}'] ?? ''),
    ];

/// Méthodes spécialisées (génétique, biologie moléculaire) écartées des distracteurs d'une question clinique.
bool _specialised(String id) => RegExp(r'^(hardy|genetic|genotype|lmm_scan|ldsc|polygenic|glmm_scan|mendelian|mr_|snp_|mutation|type_diversity|qpcr|differential_expression|local_alignment)').hasMatch(id);
