import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import 'calculators.dart';
import 'common.dart';

/// Éditeur de prédicteurs : variable, codage (référence), transformation.
class PredictorEditor extends StatelessWidget {
  final Dataset ds;
  final List<TermSpec> terms;
  final ValueChanged<List<TermSpec>> onChanged;
  final Set<String> exclude;
  final String? _title;
  String get title => _title ?? tr('Prédicteurs', 'Predictors');
  // ignore: prefer_initializing_formals (paramètre nommé public, champ privé)
  const PredictorEditor(this.ds, this.terms, this.onChanged, {super.key, this.exclude = const {}, String? title}) : _title = title;

  @override
  Widget build(BuildContext context) {
    final expert = context.watch<AppState>().expertMode;
    final available = [for (final n in ds.names) if (!exclude.contains(n) && ds.dictionary[n]!.type != VarType.identifier && !terms.any((t) => t.variable == n)) n];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      for (var i = 0; i < terms.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 150, child: Text(terms[i].variable, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (terms[i].categorical)
              Pick<String>(tr('Référence', 'Reference'), terms[i].reference, [for (final l in ds.levels(terms[i].variable)) (l, l)], (v) {
                final l = [...terms];
                l[i] = TermSpec(terms[i].variable, categorical: true, reference: v);
                onChanged(l);
              }, width: 170)
            else if (expert)
              Pick<TermTransform>('Transformation', terms[i].transform, [
                (TermTransform.none, 'aucune'),
                (TermTransform.log, 'logarithme'),
                (TermTransform.log2, tr('log2 (par doublement)', 'log2 (per doubling)')),
                (TermTransform.center, tr('centrée sur la moyenne', 'centred on the mean')),
                (TermTransform.perUnit, tr('par 10 unités', 'per 10 units')),
              ], (v) {
                final l = [...terms];
                l[i] = TermSpec(terms[i].variable, transform: v ?? TermTransform.none, unitStep: v == TermTransform.perUnit ? 10 : null);
                onChanged(l);
              }, width: 200),
            IconButton(
              tooltip: tr('Retirer', 'Remove'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onChanged([...terms]..removeAt(i)),
            ),
          ]),
        ),
      if (available.isNotEmpty)
        PopupMenuButton<String>(
          onSelected: (n) {
            final v = ds.dictionary[n]!;
            final cat = v.type != VarType.numeric;
            onChanged([...terms, TermSpec(n, categorical: cat, reference: cat ? (v.reference ?? ds.levels(n).first) : null)]);
          },
          itemBuilder: (_) => [for (final n in available) PopupMenuItem(value: n, child: Text('$n (${varTypeLabel(ds.dictionary[n]!.type)})'))],
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_circle_outline), SizedBox(width: 6), Text(tr('Ajouter une variable', 'Add a variable'))]),
          ),
        ),
    ]);
  }
}

/// Atelier de régression : linéaire, logistique, Poisson robuste, Firth.
class RegressionWorkshop extends StatefulWidget {
  final Project? project;
  final OnResult onResult;
  final String? initialMethod;
  const RegressionWorkshop({super.key, required this.project, required this.onResult, this.initialMethod});
  @override
  State<RegressionWorkshop> createState() => _RegressionWorkshopState();
}

class _RegressionWorkshopState extends State<RegressionWorkshop> {
  late String model = switch (widget.initialMethod) {
    'logistic_regression' => 'logistic',
    'poisson_robust' => 'poisson',
    'firth_logistic' => 'firth',
    'cox' => 'cox',
    _ => 'linear',
  };
  String? outcome, event;
  String? status; // Cox : variable de statut
  bool efron = true;
  bool mi = false;
  final miM = TextEditingController(text: '20');
  List<TermSpec> terms = [];
  List<(String, String)> interactions = [];

  bool get binary => model != 'linear' && model != 'cox';

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final ds = p?.dataset;
    final expert = context.watch<AppState>().expertMode;
    if (ds == null) {
      return Text(tr('L\'atelier de régression travaille sur un jeu de données individuelles : importez-le à l\'étape 4 d\'un projet.', 'The regression workshop works on an individual dataset: import it in step 4 of a project.'));
    }
    final design = p!.question.design;
    // Mode « petit nombre d'événements » : diagnostic en direct.
    int? events, nonEvents;
    final eventVar = model == 'cox' ? status : outcome;
    if ((binary || model == 'cox') && eventVar != null && event != null) {
      final y = ds.text(eventVar);
      events = y.where((v) => v == event).length;
      nonEvents = y.where((v) => v != null && v != event).length;
    }
    var params = 0;
    for (final t in terms) {
      params += t.categorical ? math.max(1, ds.levels(t.variable).length - 1) : 1;
    }
    final epv = events == null || params == 0 ? null : math.min(events, nonEvents!) / params;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Atelier de régression', 'Regression workshop'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(segments: [
        ButtonSegment(value: 'linear', label: Text(tr('Linéaire', 'Linear'))),
        ButtonSegment(value: 'logistic', label: Text(tr('Logistique', 'Logistic'))),
        ButtonSegment(value: 'poisson', label: Text(tr('Poisson robuste', 'Robust Poisson')), enabled: design != StudyDesign.caseControl),
        const ButtonSegment(value: 'firth', label: Text('Firth')),
        const ButtonSegment(value: 'cox', label: Text('Cox')),
      ], selected: {model}, onSelectionChanged: (s) => setState(() {
            model = s.first;
            outcome = null;
            event = null;
          })),
      const SizedBox(height: 6),
      Text(
          switch (model) {
            'linear' => tr('Issue quantitative ; coefficients = différences de moyennes ajustées.', 'Quantitative outcome; coefficients = adjusted differences in means.'),
            'logistic' => tr('Issue binaire ; OR ajustés. Seule option en cas-témoins.', 'Binary outcome; adjusted ORs. The only option in case-control studies.'),
            'poisson' => tr('Issue binaire fréquente en cohorte, essai ou transversal ; RR (ou RP) ajustés.', 'Common binary outcome in a cohort, trial or cross-sectional study; adjusted RRs (or PRs).'),
            'cox' => tr('Délai jusqu\'à un événement avec censure ; HR ajustés, test de proportionnalité des risques.', 'Time to an event with censoring; adjusted HRs, proportional hazards test.'),
            _ => tr('Issue binaire avec peu d\'événements ou séparation ; OR pénalisés (IC profilés).', 'Binary outcome with few events or separation; penalized ORs (profile CIs).'),
          },
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(model == 'cox' ? tr('Durée de suivi', 'Follow-up time') : tr('Issue', 'Outcome'), outcome, [
          for (final n in ds.names)
            if (binary ? (ds.dictionary[n]!.type == VarType.binary) : ds.dictionary[n]!.type == VarType.numeric) (n, n)
        ], (v) => setState(() {
              outcome = v;
              if (model != 'cox') event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              terms = [for (final t in terms) if (t.variable != v) t];
            })),
        if (model == 'cox')
          Pick<String>(tr('Statut (événement / censure)', 'Status (event / censoring)'), status, [
            for (final n in ds.names)
              if (ds.dictionary[n]!.type == VarType.binary || ds.dictionary[n]!.type == VarType.categorical) (n, n)
          ], (v) => setState(() {
                status = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
                terms = [for (final t in terms) if (t.variable != v) t];
              })),
        if ((binary && outcome != null) || (model == 'cox' && status != null))
          Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(model == 'cox' ? status! : outcome!)) (l, l)],
              (v) => setState(() => event = v)),
        if (model == 'cox' && expert)
          Pick<bool>(tr('Ex aequo', 'Ties'), efron, [(true, tr('Efron (défaut de coxph)', 'Efron (coxph default)')), (false, 'Breslow')], (v) => setState(() => efron = v ?? true), width: 220),
      ]),
      const SizedBox(height: 10),
      PredictorEditor(ds, terms, (l) => setState(() {
            terms = l;
            interactions = [for (final i in interactions) if (l.any((t) => t.variable == i.$1) && l.any((t) => t.variable == i.$2)) i];
          }), exclude: {?outcome, if (model == 'cox') ?status}),
      if (expert && terms.length >= 2) ...[
        const SizedBox(height: 6),
        Text('Interactions', style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 6, children: [
          for (var i = 0; i < terms.length; i++)
            for (var j = i + 1; j < terms.length; j++)
              FilterChip(
                label: Text('${terms[i].variable} × ${terms[j].variable}'),
                selected: interactions.contains((terms[i].variable, terms[j].variable)),
                onSelected: (s) => setState(() => s
                    ? interactions.add((terms[i].variable, terms[j].variable))
                    : interactions.remove((terms[i].variable, terms[j].variable))),
              ),
        ]),
      ],
      if (model == 'linear' || model == 'logistic' || model == 'poisson')
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Imputation multiple des valeurs manquantes (MICE, règles de Rubin)', 'Multiple imputation of missing values (MICE, Rubin\'s rules)')),
          subtitle: Text(tr('Sous l\'hypothèse MAR ; sinon analyse en cas complets (exclusions documentées).', 'Under the MAR assumption; otherwise complete-case analysis (documented exclusions).')),
          value: mi,
          onChanged: (v) => setState(() => mi = v),
        ),
      if (mi && model != 'cox' && model != 'firth') NumField(tr('Nombre d\'imputations m', 'Number of imputations m'), miM, width: 200),
      if (epv != null) ...[
        const SizedBox(height: 10),
        _SmallEventsPanel(events: events!, nonEvents: nonEvents!, params: params, epv: epv),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton.icon(
          icon: const Icon(Icons.calculate),
          label: Text(tr('Ajuster le modèle', 'Fit the model')),
          onPressed: () => run(context, () {
            if (outcome == null || terms.isEmpty) throw StatInputError('missing', tr('Choisir l\'issue et au moins un prédicteur.', 'Choose the outcome and at least one predictor.'));
            if ((binary || model == 'cox') && event == null) throw StatInputError('missing', tr('Préciser la modalité « événement ».', 'Specify the event level.'));
            if (model == 'cox') {
              if (status == null) throw StatInputError('missing', tr('Choisir la variable de statut.', 'Choose the status variable.'));
              return coxRegression(buildSurvivalDesign(ds, outcome!, status!, event!, terms), efron: efron);
            }
            final f = ModelFormula(outcome!, terms, interactions: interactions, eventLevel: event);
            if (mi && model != 'firth') {
              final used = {outcome!, for (final t in terms) t.variable};
              final imp = multipleImputation(ds,
                  MiceOptions(m: (readInt(miM) ?? 20).clamp(2, 200), exclude: {for (final n in ds.names) if (!used.contains(n)) n}));
              return pooledRegression(imp.completed, f,
                  model == 'linear' ? PooledModel.linear : (model == 'logistic' ? PooledModel.logistic : PooledModel.poissonRobust),
                  design: design, imputation: imp);
            }
            final d = buildDesign(ds, f, binaryOutcome: binary);
            return switch (model) {
              'linear' => linearRegression(d, unit: ds.dictionary[outcome]!.unit),
              'logistic' => logisticRegression(d, design: design),
              'poisson' => poissonRobustRegression(d, design: design),
              _ => firthRegression(d),
            };
          }, widget.onResult, options: {'model': model, 'formula': ModelFormula(outcome ?? '', terms, interactions: interactions, eventLevel: event).toJson()}),
        ),
      ),
      const SizedBox(height: 6),
      Text(tr('Les observations incluses, le codage et les exclusions sont détaillés dans le résultat.', 'The included observations, the coding and the exclusions are detailed in the result.'), style: Theme.of(context).textTheme.bodySmall),
      if (design != StudyDesign.rct)
        Banner2(Severity.info, tr('Étude non randomisée : un coefficient ajusté décrit une association conditionnelle, pas un effet causal.', 'Non-randomized study: an adjusted coefficient describes a conditional association, not a causal effect.')),
    ]);
  }
}

class _SmallEventsPanel extends StatelessWidget {
  final int events, nonEvents, params;
  final double epv;
  const _SmallEventsPanel({required this.events, required this.nonEvents, required this.params, required this.epv});
  @override
  Widget build(BuildContext context) {
    final low = epv < 10;
    return Card(
      color: low ? const Color(0xFFFFF4E5) : null,
      child: ExpansionTile(
        initiallyExpanded: low,
        leading: Icon(low ? Icons.warning_amber : Icons.check_circle_outline, color: low ? const Color(0xFFB7791F) : Colors.green),
        title: Text(tr('Mode « petit nombre d\'événements » — EPV = ${fmt(epv)}', '"Few events" mode — EPV = ${fmt(epv)}')),
        subtitle: Text(tr('$events événement(s), $nonEvents non-événement(s), $params paramètre(s)', '$events event(s), $nonEvents non-event(s), $params parameter(s)')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(smallEventsLesson),
          const SizedBox(height: 8),
          Text(tr('Options méthodologiques :', 'Methodological options:'), style: TextStyle(fontWeight: FontWeight.w600)),
          Text(tr('• réduire le nombre de paramètres, sur des bases cliniques fixées a priori (jamais sur les valeurs de p) ;', '• reduce the number of parameters, on clinical grounds set a priori (never on p-values);')),
          Text(tr('• régression pénalisée de Firth (séparation, biais de petit échantillon) ;', '• Firth\'s penalized regression (separation, small-sample bias);')),
          Text(tr('• regrouper des modalités rares si cela a un sens clinique ;', '• merge rare levels if it makes clinical sense;')),
          Text(tr('• méthodes exactes (Fisher) ou présentation descriptive ;', '• exact methods (Fisher) or descriptive presentation;')),
          Text(tr('• présenter l\'analyse comme exploratoire et le dire.', '• present the analysis as exploratory and say so.')),
        ],
      ),
    );
  }
}
