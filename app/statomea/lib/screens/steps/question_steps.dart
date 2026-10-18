import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../review_screen.dart';
import '../roadmap_screen.dart';

/// Étape 1 : question biomédicale (PICO + objectif).
class QuestionStep extends StatefulWidget {
  final Project p;
  const QuestionStep(this.p, {super.key});
  @override
  State<QuestionStep> createState() => _QuestionStepState();
}

class _QuestionStepState extends State<QuestionStep> {
  late final Map<String, TextEditingController> c;
  @override
  void initState() {
    super.initState();
    final q = widget.p.question;
    c = {
      'text': TextEditingController(text: q.text),
      'population': TextEditingController(text: q.population),
      'exposure': TextEditingController(text: q.exposure),
      'comparator': TextEditingController(text: q.comparator),
      'outcome': TextEditingController(text: q.outcome),
      'horizon': TextEditingController(text: q.horizon),
    };
  }

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Déduction à partir du texte de la question : caractéristiques, éléments PICO vides, plan d'analyse proposé.
  void _autoComplete() {
    final p = widget.p;
    final before = Map.of(p.inferred);
    autoCompleteProject(p);
    for (final k in const ['population', 'exposure', 'comparator', 'outcome', 'horizon']) {
      final ctl = c[k]!;
      final v = switch (k) { 'population' => p.question.population, 'exposure' => p.question.exposure, 'comparator' => p.question.comparator, 'outcome' => p.question.outcome, _ => p.question.horizon };
      if (ctl.text != v && (ctl.text.trim().isEmpty || ctl.text == before[k])) ctl.text = v;
    }
    setState(() {});
    context.read<AppState>().saveSoon(p);
  }

  void _update([String? key]) {
    if (key == 'text') {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _autoComplete();
      });
    }
    final q = widget.p.question;
    widget.p.question = q.copyWith(
      text: c['text']!.text,
      population: c['population']!.text,
      exposure: c['exposure']!.text,
      comparator: c['comparator']!.text,
      outcome: c['outcome']!.text,
      horizon: c['horizon']!.text,
    );
    context.read<AppState>().saveSoon(widget.p);
  }

  Widget _f(String key, String label, String hint, {int lines = 1}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c[key],
          minLines: lines,
          maxLines: lines + 2,
          onChanged: (_) => _update(key),
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final expert = context.watch<AppState>().expertMode;
    return PageBody(maxWidth: 820, children: [
      Heading(tr('1. Question biomédicale', '1. Biomedical question')),
      const SizedBox(height: 4),
      Text(tr('Formulez la question avant de regarder les données. Chaque élément conditionne la méthode et l\'interprétation.', 'State the question before looking at the data. Each element determines the method and the interpretation.')),
      const SizedBox(height: 12),
      _f('text', tr('Question de recherche', 'Research question'), tr('p. ex. Le tabagisme est-il associé à l\'HTA chez l\'adulte de 25 à 75 ans ?', 'e.g. Is smoking associated with hypertension in adults aged 25 to 75?'), lines: 2),
      _Deductions(p),
      _f('population', 'Population (P)', tr('Qui ? Où ? Critères d\'inclusion', 'Who? Where? Inclusion criteria')),
      _f('exposure', tr('Exposition ou intervention (I/E)', 'Exposure or intervention (I/E)'), tr('Facteur étudié, intervention, test index', 'Factor studied, intervention, index test')),
      _f('comparator', tr('Comparateur (C)', 'Comparator (C)'), tr('Non exposés, placebo, référence…', 'Unexposed, placebo, reference…')),
      _f('outcome', tr('Critère de jugement (O)', 'Outcome (O)'), tr('Issue principale et sa mesure', 'Main outcome and its measurement')),
      _f('horizon', tr('Horizon temporel', 'Time horizon'), tr('Au diagnostic, à 30 jours, à 5 ans…', 'At diagnosis, at 30 days, at 5 years…')),
      const SizedBox(height: 8),
      Text(tr('Objectif', 'Aim'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in StudyObjective.values.where((o) => o != StudyObjective.unknown))
          ChoiceChip(
            label: Text(objectiveLabel(o)),
            selected: p.question.objective == o,
            onSelected: (_) {
              setState(() => p.question = p.question.copyWith(objective: o));
              context.read<AppState>().save(p);
            },
          ),
      ]),
      const SizedBox(height: 10),
      if (p.question.objective == StudyObjective.explanatory)
        Banner2(Severity.info,
            tr('Objectif explicatif : on cherche l\'effet d\'un facteur. Les covariables se choisiront d\'après un schéma causal, et une association observationnelle ne suffira pas à conclure à la causalité.', 'Explanatory aim: the effect of a factor is sought. Covariates will be chosen from a causal diagram, and an observational association will not be enough to conclude causality.')),
      if (p.question.objective == StudyObjective.predictive)
        Banner2(Severity.info,
            tr('Objectif prédictif : on cherche à estimer un risque individuel. Population cible, horizon et usage prévu doivent être définis ; les coefficients ne s\'interprètent pas comme des effets.', 'Predictive aim: an individual risk is to be estimated. Target population, horizon and intended use must be defined; the coefficients are not interpreted as effects.')),
      if (p.question.objective == StudyObjective.diagnostic)
        Banner2(Severity.info, tr('Objectif diagnostique : comparer un test à une référence appliquée à tous les sujets.', 'Diagnostic aim: compare a test with a reference applied to all subjects.')),
      if (expert) ...[
        const SizedBox(height: 12),
        Text(tr('Complétude PICO : ${[p.question.population, p.question.exposure, p.question.comparator, p.question.outcome, p.question.horizon].where((s) => s.trim().isNotEmpty).length}/5', 'PICO completeness: ${[p.question.population, p.question.exposure, p.question.comparator, p.question.outcome, p.question.horizon].where((s) => s.trim().isNotEmpty).length}/5'),
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}

/// Étape 2 : plan d'étude et structure des données.
class StudyPlanStep extends StatefulWidget {
  final Project p;
  const StudyPlanStep(this.p, {super.key});
  @override
  State<StudyPlanStep> createState() => _StudyPlanStepState();
}

class _StudyPlanStepState extends State<StudyPlanStep> {
  void set(ResearchQuestion q) {
    setState(() => widget.p.question = q);
    context.read<AppState>().save(widget.p);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.p.question;
    final groupsC = TextEditingController(text: q.groups?.toString() ?? '');
    final eventsC = TextEditingController(text: q.expectedEvents?.toString() ?? '');
    Widget chips<T>(String title, List<(T, String)> items, T value, ResearchQuestion Function(T) apply) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, l) in items) ChoiceChip(label: Text(l), selected: value == v, onSelected: (_) => set(apply(v))),
            ]),
          ]),
        );
    bool? triState(bool? v) => v;
    return PageBody(maxWidth: 820, children: [
      Heading(tr('2. Plan d\'étude', '2. Study design')),
      Text(tr('Ces informations peuvent être déduites du texte de la question (signalées à l\'étape 1) : vérifiez-les et corrigez-les ici. Statoméa ne déduit jamais une méthode du nom des variables.', 'This information can be inferred from the question text (shown in step 1): check and correct it here. Statoméa never infers a method from variable names.')),
      chips(tr('Plan', 'Design'), [for (final d in StudyDesign.values.where((d) => d != StudyDesign.unknown)) (d, designLabel(d))], q.design, (v) => q.copyWith(design: v)),
      chips(tr('Niveau des données', 'Data level'), [(DataLevel.individual, tr('observations individuelles', 'individual observations')), (DataLevel.aggregatedStudies, tr('résultats d\'études (métaanalyse)', 'study results (meta-analysis)'))],
          q.dataLevel, (v) => q.copyWith(dataLevel: v)),
      chips(tr('Type du critère de jugement', 'Outcome type'), [for (final t in OutcomeType.values.where((t) => t != OutcomeType.unknown)) (t, outcomeTypeLabel(t))], q.outcomeType,
          (v) => q.copyWith(outcomeType: v)),
      chips(tr('Type de l\'exposition / du facteur', 'Type of exposure / factor'), [
        (ExposureType.binary, tr('binaire (2 groupes)', 'binary (2 groups)')),
        (ExposureType.categorical, tr('qualitative (> 2 groupes)', 'categorical (> 2 groups)')),
        (ExposureType.continuous, 'quantitative'),
        (ExposureType.none, tr('aucune (description)', 'none (description)')),
      ], q.exposureType, (v) => q.copyWith(exposureType: v)),
      chips('Observations', [(Pairing.independent, tr('indépendantes', 'independent')), (Pairing.paired, tr('appariées (2 mesures / paire)', 'paired (2 measurements / pair)')), (Pairing.repeated, tr('mesures répétées (> 2)', 'repeated measures (> 2)'))],
          q.pairing, (v) => q.copyWith(pairing: v)),
      chips(tr('Facteurs de confusion à prendre en compte ?', 'Confounders to account for?'), [(true, 'oui'), (false, tr('non / essai randomisé', 'no / randomized trial'))], triState(q.needsAdjustment),
          (v) => q.copyWith(needsAdjustment: v)),
      chips(tr('Distribution de l\'issue ~ symétrique ou n ≥ 30 par groupe ?', 'Outcome distribution ~ symmetric or n ≥ 30 per group?'), [(true, 'oui'), (false, 'non')], triState(q.approxNormal), (v) => q.copyWith(approxNormal: v)),
      if (q.outcomeType == OutcomeType.timeToEvent) ...[
        chips(tr('Un autre événement (p. ex. le décès) peut-il empêcher l\'événement étudié ?', 'Can another event (e.g. death) prevent the studied event?'), [(true, tr('oui', 'yes')), (false, tr('non', 'no'))],
            triState(q.competingRisk), (v) => q.copyWith(competingRisk: v)),
        chips(tr('L\'exposition peut-elle survenir ou changer pendant le suivi ?', 'Can the exposure occur or change during follow-up?'), [(true, tr('oui', 'yes')), (false, tr('non', 'no'))],
            triState(q.timeVaryingExposure), (v) => q.copyWith(timeVaryingExposure: v)),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(
            width: 200,
            child: TextField(
                controller: groupsC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Nombre de groupes', 'Number of groups')),
                onSubmitted: (v) => set(q.copyWith(groups: int.tryParse(v))))),
        SizedBox(
            width: 260,
            child: TextField(
                controller: eventsC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Événements attendus (issue binaire)', 'Expected events (binary outcome)')),
                onSubmitted: (v) => set(q.copyWith(expectedEvents: int.tryParse(v))))),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Comparer deux méthodes mesurant la même grandeur (accord)', 'Compare two methods measuring the same quantity (agreement)')),
        value: q.agreementQuestion,
        onChanged: (v) => set(q.copyWith(agreementQuestion: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Un examen de référence est disponible pour tous les sujets (diagnostic)', 'A reference standard is available for all subjects (diagnostic)')),
        value: q.referenceStandardAvailable,
        onChanged: (v) => set(q.copyWith(referenceStandardAvailable: v)),
      ),
      const SizedBox(height: 8),
      if (q.design == StudyDesign.caseControl)
        Banner2(Severity.caution, tr('Cas-témoins : prévalence, risques, RR et différences de risques ne sont pas estimables ; seul l\'OR l\'est.', 'Case-control: prevalence, risks, RRs and risk differences are not estimable; only the OR is.')),
      if (q.design == StudyDesign.crossSectional)
        Banner2(Severity.info, tr('Transversal : on estime des prévalences et des rapports de prévalences ; la temporalité exposition → issue n\'est pas établie.', 'Cross-sectional: prevalences and prevalence ratios are estimated; the exposure → outcome temporality is not established.')),
      if (q.design == StudyDesign.rct)
        Banner2(Severity.info, tr('Essai randomisé : l\'effet de l\'intervention randomisée peut recevoir une interprétation causale (pas les sous-groupes post hoc).', 'Randomized trial: the effect of the randomized intervention can be given a causal interpretation (not post hoc subgroups).')),
    ]);
  }
}

/// Étape 3 : plan d'analyse (pré-spécifié).
class AnalysisPlanStep extends StatefulWidget {
  final Project p;
  const AnalysisPlanStep(this.p, {super.key});
  @override
  State<AnalysisPlanStep> createState() => _AnalysisPlanStepState();
}

class _AnalysisPlanStepState extends State<AnalysisPlanStep> {
  late final TextEditingController c = TextEditingController(text: widget.p.analysisPlan);

  String _template() {
    final q = widget.p.question;
    final a = advise(q);
    final rec = a.options.where((o) => o.recommended).map((o) => o.name).join(' ; ');
    final alt = a.options.where((o) => !o.recommended).map((o) => o.name).join(' ; ');
    return [
      tr('Critère principal : ${q.outcome.isEmpty ? "[à préciser]" : q.outcome} (${outcomeTypeLabel(q.outcomeType)}), horizon ${q.horizon.isEmpty ? "[à préciser]" : q.horizon}.', 'Primary outcome: ${q.outcome.isEmpty ? "[to be specified]" : q.outcome} (${outcomeTypeLabel(q.outcomeType)}), horizon ${q.horizon.isEmpty ? "[to be specified]" : q.horizon}.'),
      tr('Analyse principale : ${rec.isEmpty ? "[à choisir à l'étape 5]" : rec}.', 'Main analysis: ${rec.isEmpty ? "[to be chosen in step 5]" : rec}.'),
      if (alt.isNotEmpty) tr('Alternatives défendables (à justifier) : $alt.', 'Defensible alternatives (to be justified): $alt.'),
      if (q.needsAdjustment == true) tr('Covariables d\'ajustement choisies a priori (schéma causal) : [liste et justification].', 'Adjustment covariates chosen a priori (causal diagram): [list and justification].'),
      tr('Données manquantes : description par variable ; analyse en cas complets documentée.', 'Missing data: description by variable; documented complete-case analysis.'),
      tr('Analyses de sensibilité prévues : [lesquelles et pourquoi].', 'Planned sensitivity analyses: [which and why].'),
      tr('Seuil de pertinence clinique (pour juger l\'absence d\'effet) : [valeur].', 'Clinical relevance threshold (to judge absence of effect): [value].'),
      tr('Sous-groupes prévus a priori : [aucun / lesquels, avec justification].', 'Subgroups planned a priori: [none / which, with justification].'),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(maxWidth: 820, children: [
      Heading(tr('3. Plan d\'analyse', '3. Analysis plan')),
      Text(tr('Fixez l\'analyse principale, les covariables, les sensibilités et les sous-groupes AVANT de voir les résultats. L\'audit comparera le texte final à ce qui a réellement été calculé.', 'Fix the main analysis, covariates, sensitivity analyses and subgroups BEFORE seeing the results. The audit will compare the final text with what was actually computed.')),
      const SizedBox(height: 12),
      TextField(
        controller: c,
        minLines: 10,
        maxLines: 24,
        onChanged: (v) {
          widget.p.analysisPlan = v;
          context.read<AppState>().saveSoon(widget.p);
        },
        decoration: InputDecoration(labelText: tr('Plan d\'analyse', 'Analysis plan'), alignLabelWithHint: true),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.auto_fix_high),
          label: Text(tr('Proposer un canevas à partir de la question', 'Propose an outline from the question')),
          onPressed: () {
            final t = _template();
            setState(() => c.text = c.text.trim().isEmpty ? t : '${c.text.trim()}\n\n$t');
            widget.p.analysisPlan = c.text;
            context.read<AppState>().save(widget.p);
          },
        ),
      ),
      const SizedBox(height: 6),
      Text(tr('Le canevas est un gabarit déterministe à compléter, pas une décision.', 'The outline is a deterministic template to be completed, not a decision.'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}


/// Ce que Statoméa a déduit du texte de la question (à vérifier), méthode proposée et accès à la feuille de route.
class _Deductions extends StatelessWidget {
  final Project p;
  const _Deductions(this.p);
  @override
  Widget build(BuildContext context) {
    final q = p.question;
    final fields = [for (final k in p.inferred.keys) if (k != 'analysisPlan') k];
    if (q.text.trim().length < 15) return const SizedBox.shrink();
    String label(String f) => switch (f) {
          'design' => tr('Plan : ${designLabel(q.design)}', 'Design: ${designLabel(q.design)}'),
          'objective' => tr('Objectif : ${objectiveLabel(q.objective)}', 'Aim: ${objectiveLabel(q.objective)}'),
          'outcomeType' => tr('Issue : ${outcomeTypeLabel(q.outcomeType)}', 'Outcome: ${outcomeTypeLabel(q.outcomeType)}'),
          'exposureType' => tr('Exposition : ${q.exposureType.name == 'binary' ? 'binaire' : q.exposureType.name == 'continuous' ? 'quantitative' : 'qualitative'}', 'Exposure: ${q.exposureType.name}'),
          'pairing' => tr('Mesures : ${q.pairing == Pairing.paired ? 'appariées' : q.pairing == Pairing.repeated ? 'répétées' : 'indépendantes'}', 'Measurements: ${q.pairing.name}'),
          'needsAdjustment' => tr('Ajustement : ${q.needsAdjustment == true ? 'oui' : 'non'}', 'Adjustment: ${q.needsAdjustment == true ? 'yes' : 'no'}'),
          'competingRisk' => tr('Risque concurrent', 'Competing risk'),
          'agreementQuestion' => tr('Accord entre méthodes', 'Agreement between methods'),
          'referenceStandardAvailable' => tr('Test de référence', 'Reference standard'),
          'timeVaryingExposure' => tr('Exposition pendant le suivi', 'Exposure during follow-up'),
          'dataLevel' => tr('Données individuelles', 'Individual data'),
          'population' => 'Population',
          'exposure' => tr('Exposition (texte)', 'Exposure (text)'),
          'comparator' => tr('Comparateur', 'Comparator'),
          'outcome' => tr('Critère (texte)', 'Outcome (text)'),
          'horizon' => 'Horizon',
          _ => f,
        };
    final a = advise(q);
    final main = a.options.where((o) => o.recommended).firstOrNull ?? a.options.firstOrNull;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(tr('Déduit de votre question (à vérifier)', 'Inferred from your question (to check)'), icon: Icons.auto_awesome),
          if (fields.isEmpty)
            Text(tr('Rien de plus à déduire : les caractéristiques déjà renseignées sont conservées.', 'Nothing more to infer: the characteristics already filled in are kept.'), style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(spacing: 6, runSpacing: 6, children: [for (final f in fields) Chip(avatar: const Icon(Icons.auto_awesome, size: 14), label: Text(label(f)), visualDensity: VisualDensity.compact)]),
          const SizedBox(height: 6),
          if (main != null) Text(tr('Méthode proposée : ${main.name}', 'Proposed method: ${main.name}'), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (a.questions.isNotEmpty)
            Text(tr('Encore à préciser (étape 2) : ${a.questions.length} point(s).', 'Still to specify (step 2): ${a.questions.length} point(s).'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 6, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.route_outlined),
              label: Text(tr('Voir les 10 étapes (feuille de route, PDF)', 'See the 10 steps (roadmap, PDF)')),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoadmapScreen(p))),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(tr('Relire et corriger le projet', 'Review and correct the project')),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(p))),
            ),
          ]),
        ]),
      ),
    );
  }
}
