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
    'fine_gray' => 'fine_gray',
    'lmm_longitudinal' => 'mixed',
    'gee' => 'gee',
    'glmm_longitudinal' => 'glmm',
    'count_regression' => 'counts',
    'ordinal_logistic' => 'ordinal',
    'multinomial_logistic' => 'multinomial',
    _ => 'linear',
  };
  String? outcome, event;
  String? status; // Cox et Fine-Gray : variable de statut
  String? censor; // Fine-Gray : modalité de censure (les autres modalités sont des événements concurrents)
  // Cox avec covariable dépendant du temps : données en intervalles (colonne de début), ou découpage à une date de
  // changement (colonne du temps de changement + covariable binaire concernée).
  String? startCol, switchCol, switchCov;
  // Mesures répétées : identifiant du sujet, pente aléatoire facultative (temps).
  String? subjectCol, slopeCol;
  GeeFamily geeFamily = GeeFamily.gaussian;
  GeeCorrelation geeCorr = GeeCorrelation.exchangeable;
  bool geeSmall = false;
  GlmmFamily glmmFamily = GlmmFamily.binomial;
  int glmmAgq = 1;
  // Comptages : modèle et temps d'exposition (offset) ; issues ordinales : ordre des modalités.
  CountModel countModel = CountModel.negativeBinomial;
  String? exposureCol;
  final levelOrder = TextEditingController();
  bool get categoricalOutcome => model == 'ordinal' || model == 'multinomial';
  bool efron = true;
  bool mi = false;
  final miM = TextEditingController(text: '20');
  List<TermSpec> terms = [];
  List<(String, String)> interactions = [];

  bool get surv => model == 'cox' || model == 'fine_gray';
  bool get binary => model == 'glmm' ? glmmFamily == GlmmFamily.binomial : model == 'gee' ? geeFamily == GeeFamily.binomial : !const {'linear', 'mixed', 'counts', 'ordinal', 'multinomial'}.contains(model) && !surv;

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
    final eventVar = surv ? status : outcome;
    if ((binary || surv) && eventVar != null && event != null) {
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
      // Liste déroulante (et non boutons segmentés) : lisible sur téléphone quel que soit le nombre de modèles.
      Pick<String>(tr('Modèle', 'Model'), model, [
        ('linear', tr('Linéaire', 'Linear')),
        ('logistic', tr('Logistique', 'Logistic')),
        if (design != StudyDesign.caseControl) ('poisson', tr('Poisson robuste', 'Robust Poisson')),
        ('firth', tr('Logistique de Firth', 'Firth logistic')),
        ('counts', tr('Comptages (Poisson, binomiale négative)', 'Counts (Poisson, negative binomial)')),
        ('ordinal', tr('Issue ordinale (cotes proportionnelles)', 'Ordinal outcome (proportional odds)')),
        ('multinomial', tr('Issue nominale (multinomiale)', 'Nominal outcome (multinomial)')),
        ('cox', tr('Cox (survie)', 'Cox (survival)')),
        ('fine_gray', tr('Fine-Gray (risques concurrents)', 'Fine-Gray (competing risks)')),
        ('mixed', tr('Mesures répétées (modèle mixte)', 'Repeated measures (mixed model)')),
        ('gee', tr('Mesures répétées (GEE)', 'Repeated measures (GEE)')),
        ('glmm', tr('Mesures répétées binaires ou comptages (modèle mixte)', 'Repeated binary or count outcomes (mixed model)')),
      ], (v) => setState(() {
            if (v == null || v == model) return;
            model = v;
            outcome = null;
            event = null;
          }), width: 340),
      const SizedBox(height: 6),
      Text(
          switch (model) {
            'linear' => tr('Issue quantitative ; coefficients = différences de moyennes ajustées.', 'Quantitative outcome; coefficients = adjusted differences in means.'),
            'logistic' => tr('Issue binaire ; OR ajustés. Seule option en cas-témoins.', 'Binary outcome; adjusted ORs. The only option in case-control studies.'),
            'poisson' => tr('Issue binaire fréquente en cohorte, essai ou transversal ; RR (ou RP) ajustés.', 'Common binary outcome in a cohort, trial or cross-sectional study; adjusted RRs (or PRs).'),
            'cox' => tr('Délai jusqu\'à un événement avec censure ; HR ajustés, test de proportionnalité des risques.', 'Time to an event with censoring; adjusted HRs, proportional hazards test.'),
            'counts' => tr('Nombre d\'événements (entier ≥ 0) ; IRR (rapports de taux) ; binomiale négative si la variance dépasse la moyenne ; temps d\'exposition en offset.', 'Number of events (integer ≥ 0); IRRs (rate ratios); negative binomial if the variance exceeds the mean; exposure time as offset.'),
            'ordinal' => tr('Issue à modalités ordonnées (≥ 3) ; un OR par facteur, commun à tous les seuils.', 'Outcome with ordered levels (≥ 3); one OR per factor, common to all thresholds.'),
            'multinomial' => tr('Issue à modalités non ordonnées (≥ 3) ; un RRR par modalité contre la référence.', 'Outcome with unordered levels (≥ 3); one RRR per level against the reference.'),
            'glmm' => tr('Issue binaire ou de comptage mesurée plusieurs fois ; intercept aléatoire par sujet ; OR ou RR propres au sujet.', 'Binary or count outcome measured several times; random intercept per subject; subject-specific ORs or RRs.'),
            'gee' => tr('Plusieurs mesures par sujet ; effet moyen dans la population avec erreurs types robustes ; issue quantitative, binaire ou de comptage.', 'Several measurements per subject; population-average effect with robust standard errors; quantitative, binary or count outcome.'),
            'mixed' => tr('Plusieurs mesures par sujet (format long : une ligne par mesure) ; intercept et pente aléatoires par sujet, effets fixes avec tests t (ddl de nlme).', 'Several measurements per subject (long format: one row per measurement); random intercept and slope per subject, fixed effects with t tests (nlme df).'),
            'fine_gray' => tr('Délai jusqu\'à un événement quand un autre événement (p. ex. le décès) peut l\'empêcher ; sHR sur l\'incidence cumulée, HR spécifiques de cause en regard.', 'Time to an event when another event (e.g. death) can prevent it; sHRs on the cumulative incidence, cause-specific HRs alongside.'),
            _ => tr('Issue binaire avec peu d\'événements ou séparation ; OR pénalisés (IC profilés).', 'Binary outcome with few events or separation; penalized ORs (profile CIs).'),
          },
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(surv ? tr('Durée de suivi', 'Follow-up time') : tr('Issue', 'Outcome'), outcome, [
          for (final n in ds.names)
            if (binary
                ? (ds.dictionary[n]!.type == VarType.binary)
                : categoricalOutcome
                    ? ds.levels(n).length >= 3 && ds.levels(n).length <= 12
                    // Comptage : toute colonne à valeurs numériques, même typée qualitative (peu de valeurs).
                    : ((model == 'gee' && geeFamily == GeeFamily.poisson) || (model == 'glmm' && glmmFamily == GlmmFamily.poisson) || model == 'counts'
                        ? ds.text(n).every((v) => v == null || parseNumber(v) != null)
                        : ds.dictionary[n]!.type == VarType.numeric)) (n, n)
        ], (v) => setState(() {
              outcome = v;
              if (categoricalOutcome && v != null) levelOrder.text = (ds.dictionary[v]?.order ?? ds.levels(v)).join(' ; ');
              if (!surv) event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              terms = [for (final t in terms) if (t.variable != v) t];
            })),
        if (surv)
          Pick<String>(model == 'cox' ? tr('Statut (événement / censure)', 'Status (event / censoring)') : tr('Statut (événement, concurrent, censure)', 'Status (event, competing, censoring)'), status, [
            for (final n in ds.names)
              if (ds.dictionary[n]!.type == VarType.binary || ds.dictionary[n]!.type == VarType.categorical) (n, n)
          ], (v) => setState(() {
                status = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
                censor = v == null ? null : (ds.levels(v).contains('0') ? '0' : null);
                terms = [for (final t in terms) if (t.variable != v) t];
              })),
        if ((binary && outcome != null) || (surv && status != null))
          Pick<String>(model == 'fine_gray' ? tr('Événement d\'intérêt', 'Event of interest') : tr('Modalité « événement »', 'Event level'), event,
              [for (final l in ds.levels(surv ? status! : outcome!)) (l, l)], (v) => setState(() => event = v)),
        if (model == 'fine_gray' && status != null)
          Pick<String>(tr('Modalité « censure »', 'Censoring level'), censor, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => censor = v)),
        if (model == 'counts') ...[
          Pick<CountModel>(tr('Modèle de comptage', 'Count model'), countModel, [
            (CountModel.negativeBinomial, tr('Binomiale négative', 'Negative binomial')),
            (CountModel.poisson, 'Poisson'),
            (CountModel.quasiPoisson, 'Quasi-Poisson'),
          ], (v) => setState(() => countModel = v ?? countModel), width: 240),
          Pick<String>(tr('Temps d\'exposition (offset, facultatif)', 'Exposure time (offset, optional)'), exposureCol ?? '', [
            ('', tr('— aucun —', '— none —')),
            for (final n in ds.names)
              if (n != outcome && ds.dictionary[n]!.type == VarType.numeric) (n, n)
          ], (v) => setState(() => exposureCol = (v == null || v.isEmpty) ? null : v), width: 300),
        ],
        if (model == 'ordinal' && outcome != null)
          SizedBox(
              width: 360,
              child: TextField(
                  controller: levelOrder,
                  decoration: InputDecoration(
                      labelText: tr('Ordre des modalités (croissant, séparées par « ; »)', 'Order of the levels (increasing, separated by ";")'),
                      border: const OutlineInputBorder(),
                      isDense: true))),
        if (model == 'gee') ...[
          Pick<GeeFamily>(tr('Type d\'issue', 'Outcome type'), geeFamily, [
            (GeeFamily.gaussian, tr('Quantitative (gaussienne)', 'Quantitative (Gaussian)')),
            (GeeFamily.binomial, tr('Binaire (logit)', 'Binary (logit)')),
            (GeeFamily.poisson, tr('Comptage (Poisson)', 'Count (Poisson)')),
          ], (v) => setState(() {
                geeFamily = v ?? geeFamily;
                outcome = null;
                event = null;
              }), width: 260),
          Pick<GeeCorrelation>(tr('Corrélation de travail', 'Working correlation'), geeCorr, [
            (GeeCorrelation.exchangeable, tr('Échangeable', 'Exchangeable')),
            (GeeCorrelation.independence, tr('Indépendance', 'Independence')),
          ], (v) => setState(() => geeCorr = v ?? geeCorr), width: 240),
          if (expert)
            Pick<bool>(tr('Convention', 'Convention'), geeSmall, [(false, 'geepack (φ = Σr²/N)'), (true, tr('gee, petits échantillons', 'gee, small samples'))], (v) => setState(() => geeSmall = v ?? false), width: 260),
        ],
        if (model == 'glmm') ...[
          Pick<GlmmFamily>(tr('Type d\'issue', 'Outcome type'), glmmFamily, [
            (GlmmFamily.binomial, tr('Binaire (logistique)', 'Binary (logistic)')),
            (GlmmFamily.poisson, tr('Comptage (Poisson)', 'Count (Poisson)')),
          ], (v) => setState(() {
                glmmFamily = v ?? glmmFamily;
                outcome = null;
                event = null;
              }), width: 260),
          if (expert)
            Pick<int>(tr('Approximation', 'Approximation'), glmmAgq, [(1, 'Laplace'), (10, tr('Gauss-Hermite, 10 points', 'Gauss-Hermite, 10 points')), (25, tr('Gauss-Hermite, 25 points', 'Gauss-Hermite, 25 points'))],
                (v) => setState(() => glmmAgq = v ?? 1), width: 260),
        ],
        if (model == 'mixed' || model == 'gee' || model == 'glmm') ...[
          Pick<String>(tr('Sujet (identifiant)', 'Subject (identifier)'), subjectCol, [for (final n in ds.names) if (n != outcome) (n, n)],
              (v) => setState(() => subjectCol = v), width: 260),
          if (model == 'mixed')
            Pick<String>(tr('Pente aléatoire (temps, facultatif)', 'Random slope (time, optional)'), slopeCol ?? '', [
            ('', tr('— aucune —', '— none —')),
            // Temps : toute colonne à valeurs numériques (un temps à quelques visites peut être typé qualitatif).
            for (final n in ds.names)
              if (n != outcome && n != subjectCol && ds.text(n).every((v) => v == null || parseNumber(v) != null)) (n, n)
          ], (v) => setState(() => slopeCol = (v == null || v.isEmpty) ? null : v), width: 300),
        ],
        if (model == 'cox')
          Pick<String>(tr('Début d\'intervalle (données (début, fin])', 'Interval start ((start, stop] data)'), startCol ?? '', [
            ('', tr('— aucun : suivi depuis 0 —', '— none: follow-up from 0 —')),
            for (final n in ds.names)
              if (ds.dictionary[n]!.type == VarType.numeric && n != outcome) (n, n)
          ], (v) => setState(() {
                startCol = (v == null || v.isEmpty) ? null : v;
                if (startCol != null) switchCol = switchCov = null;
              }), width: 300),
        if (model == 'cox' && startCol == null) ...[
          Pick<String>(tr('Changement en cours de suivi : temps', 'Change during follow-up: time'), switchCol ?? '', [
            ('', tr('— aucun —', '— none —')),
            for (final n in ds.names)
              if (ds.dictionary[n]!.type == VarType.numeric && n != outcome) (n, n)
          ], (v) => setState(() => switchCol = (v == null || v.isEmpty) ? null : v), width: 300),
          if (switchCol != null)
            Pick<String>(tr('Covariable qui change (non → oui)', 'Covariate that changes (no → yes)'), switchCov, [
              for (final n in ds.names)
                if (ds.dictionary[n]!.type == VarType.binary && n != status) (n, n)
            ], (v) => setState(() => switchCov = v), width: 300),
        ],
        if (model == 'cox' && expert)
          Pick<bool>(tr('Ex aequo', 'Ties'), efron, [(true, tr('Efron (défaut de coxph)', 'Efron (coxph default)')), (false, 'Breslow')], (v) => setState(() => efron = v ?? true), width: 220),
      ]),
      const SizedBox(height: 10),
      PredictorEditor(ds, terms, (l) => setState(() {
            terms = l;
            interactions = [for (final i in interactions) if (l.any((t) => t.variable == i.$1) && l.any((t) => t.variable == i.$2)) i];
          }), exclude: {?outcome, if (surv) ?status, if (model == 'mixed' || model == 'gee' || model == 'glmm') ?subjectCol, if (model == 'counts') ?exposureCol}),
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
      if (mi && !surv && model != 'firth') NumField(tr('Nombre d\'imputations m', 'Number of imputations m'), miM, width: 200),
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
            if ((binary || surv) && event == null) throw StatInputError('missing', tr('Préciser la modalité « événement ».', 'Specify the event level.'));
            if (model == 'fine_gray') {
              if (status == null || censor == null) throw StatInputError('missing', tr('Choisir la variable de statut et la modalité de censure.', 'Choose the status variable and the censoring level.'));
              return fineGrayRegression(buildCompetingDesign(ds, outcome!, status!, event!, {censor!}, terms));
            }
            if (model == 'cox') {
              if (status == null) throw StatInputError('missing', tr('Choisir la variable de statut.', 'Choose the status variable.'));
              if (startCol != null) return coxRegression(buildCountingDesign(ds, startCol!, outcome!, status!, event!, terms), efron: efron);
              if (switchCol != null) {
                if (switchCov == null) throw StatInputError('missing', tr('Choisir la covariable qui change au temps « $switchCol ».', 'Choose the covariate that changes at time "$switchCol".'));
                final yes = tr('oui', 'yes'), no = tr('non', 'no');
                final long = splitAtSwitch(ds, time: outcome!, status: status!, eventLevel: event!, switchTime: switchCol!, covariate: switchCov!, yes: yes, no: no);
                final tdTerms = [for (final t in terms) if (t.variable != switchCov && t.variable != switchCol) t, TermSpec(switchCov!, categorical: true, reference: no)];
                return coxRegression(buildCountingDesign(long, 'debut', 'fin', status!, event!, tdTerms), efron: efron);
              }
              return coxRegression(buildSurvivalDesign(ds, outcome!, status!, event!, terms), efron: efron);
            }
            final f = ModelFormula(outcome!, terms, interactions: interactions, eventLevel: event);
            if (model == 'counts') return countRegression(ds, f, model: countModel, exposure: exposureCol);
            if (categoricalOutcome) {
              final order = [for (final s in levelOrder.text.split(';')) if (s.trim().isNotEmpty) s.trim()];
              final known = ds.levels(outcome!);
              final lv = order.toSet().length == known.length && order.every(known.contains) ? order : known;
              return model == 'ordinal' ? ordinalRegression(ds, f, levels: lv) : multinomialRegression(ds, f, levels: lv);
            }
            if (model == 'glmm') {
              if (subjectCol == null) throw StatInputError('missing', tr('Choisir la colonne qui identifie le sujet.', 'Choose the column that identifies the subject.'));
              return glmmLongitudinal(ds, f, subject: subjectCol!, family: glmmFamily, nAgq: glmmAgq);
            }
            if (model == 'gee') {
              if (subjectCol == null) throw StatInputError('missing', tr('Choisir la colonne qui identifie le sujet.', 'Choose the column that identifies the subject.'));
              return geeRegression(ds, f, subject: subjectCol!, family: geeFamily, corr: geeCorr, smallSample: geeSmall);
            }
            if (model == 'mixed') {
              if (subjectCol == null) throw StatInputError('missing', tr('Choisir la colonne qui identifie le sujet.', 'Choose the column that identifies the subject.'));
              return longitudinalMixedModel(ds, f, subject: subjectCol!, slope: slopeCol);
            }
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
