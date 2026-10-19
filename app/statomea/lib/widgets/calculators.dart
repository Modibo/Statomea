import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../screens/lesson_screen.dart';
import '../services/file_saver.dart';
import '../services/table_export.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'genomics_workshop.dart';
import 'meta_workshop.dart';
import 'prediction_workshop.dart';
import 'regression_workshop.dart';
import 'result_view.dart';
import 'variable_roles.dart';

/// Calculateurs disponibles (groupés par famille).
List<(String, String, IconData, String)> get calculatorKinds => [
  ('proportion_ci', tr('Proportion / prévalence', 'Proportion / prevalence'), Icons.percent, tr('Descriptif', 'Descriptive')),
  ('describe', tr('Statistiques descriptives', 'Descriptive statistics'), Icons.bar_chart, tr('Descriptif', 'Descriptive')),
  ('table1', tr('Tableau 1 : caractéristiques des participants', 'Table 1: participant characteristics'), Icons.table_chart_outlined, tr('Descriptif', 'Descriptive')),
  ('two_by_two', tr('Tableau 2 × 2 (RR, OR, DR)', '2 × 2 table (RR, OR, RD)'), Icons.grid_on, 'Association'),
  ('chi_square_rxc', 'χ² r × c', Icons.grid_4x4, 'Association'),
  ('diagnostic_accuracy', tr('Performance diagnostique', 'Diagnostic accuracy'), Icons.biotech_outlined, 'Diagnostic'),
  ('compare_two', tr('Comparer 2 groupes', 'Compare 2 groups'), Icons.compare_arrows, tr('Comparaison', 'Comparison')),
  ('compare_k', tr('Comparer k groupes', 'Compare k groups'), Icons.view_week_outlined, tr('Comparaison', 'Comparison')),
  ('equivalence', tr('Équivalence et non-infériorité (TOST)', 'Equivalence and non-inferiority (TOST)'), Icons.compare, tr('Comparaison', 'Comparison')),
  ('paired', tr('Mesures appariées', 'Paired measurements'), Icons.sync_alt, tr('Apparié', 'Paired')),
  ('mcnemar', tr('McNemar (binaire apparié)', 'McNemar (paired binary)'), Icons.swap_horiz, tr('Apparié', 'Paired')),
  ('correlation', tr('Corrélation', 'Correlation'), Icons.scatter_plot_outlined, tr('Corrélation', 'Correlation')),
  ('bland_altman', tr('Accord (Bland-Altman)', 'Agreement (Bland-Altman)'), Icons.align_horizontal_center, tr('Accord', 'Agreement')),
  ('method_comparison', tr('Comparaison de méthodes (Passing-Bablok, Deming)', 'Method comparison (Passing-Bablok, Deming)'), Icons.stacked_line_chart, tr('Accord', 'Agreement')),
  ('reference_interval', tr('Intervalle de référence (EP28)', 'Reference interval (EP28)'), Icons.straighten, tr('Laboratoire', 'Laboratory')),
  ('precision', tr('Fidélité : répétabilité, intralaboratoire (EP05, EP15)', 'Precision: repeatability, within-lab (EP05, EP15)'), Icons.center_focus_strong_outlined, tr('Laboratoire', 'Laboratory')),
  ('kaplan_meier', tr('Survie (Kaplan-Meier, log-rank)', 'Survival (Kaplan-Meier, log-rank)'), Icons.timeline, tr('Survie', 'Survival')),
  ('cumulative_incidence', tr('Risques concurrents (incidence cumulée)', 'Competing risks (cumulative incidence)'), Icons.call_split, tr('Survie', 'Survival')),
  ('rmst', tr('Temps moyen de survie restreint (RMST)', 'Restricted mean survival time (RMST)'), Icons.area_chart, tr('Survie', 'Survival')),
  ('landmark', tr('Analyse landmark (exposition en cours de suivi)', 'Landmark analysis (exposure during follow-up)'), Icons.flag_outlined, tr('Survie', 'Survival')),
  ('propensity', tr('Score de propension (appariement, IPTW)', 'Propensity score (matching, IPTW)'), Icons.balance, tr('Causalité', 'Causality')),
  ('e_value', tr('Valeur E (confusion non mesurée)', 'E-value (unmeasured confounding)'), Icons.shield_outlined, tr('Causalité', 'Causality')),
  ('interrupted_series', tr('Série chronologique interrompue', 'Interrupted time series'), Icons.show_chart, tr('Causalité', 'Causality')),
  ('calibration', tr('Calibration d\'un modèle de risque', 'Calibration of a risk model'), Icons.tune, tr('Prédiction', 'Prediction')),
  ('bayes', tr('Bayésien : proportion, effet publié', 'Bayesian: proportion, published effect'), Icons.auto_graph, tr('Bayésien', 'Bayesian')),
  ('sample_size', tr('Taille d\'échantillon', 'Sample size'), Icons.groups_outlined, tr('Planification', 'Planning')),
  ('power', tr('Puissance et effectif (survie, cas-témoins, GWAS…)', 'Power and sample size (survival, case-control, GWAS…)'), Icons.speed, tr('Planification', 'Planning')),
  ('regression', tr('Atelier de régression', 'Regression workshop'), Icons.functions, tr('Ateliers', 'Workshops')),
  ('meta', tr('Atelier de métaanalyse', 'Meta-analysis workshop'), Icons.stacked_bar_chart, tr('Ateliers', 'Workshops')),
  ('prediction', tr('Atelier de prédiction', 'Prediction workshop'), Icons.monitor_heart_outlined, tr('Ateliers', 'Workshops')),
  ('genomics', tr('Atelier génomique', 'Genomics workshop'), Icons.biotech, tr('Ateliers', 'Workshops')),
];

String calculatorFor(String methodId) => switch (methodId) {
      't_test_welch' || 't_test_student' || 'mann_whitney' => 'compare_two',
      'anova_oneway' || 'anova_welch' || 'kruskal_wallis' => 'compare_k',
      'paired_t_test' || 'wilcoxon_signed_rank' => 'paired',
      'pearson' || 'spearman' => 'correlation',
      'linear_regression' || 'logistic_regression' || 'poisson_robust' || 'firth_logistic' || 'cox' || 'fine_gray' || 'restricted_cubic_spline' => 'regression',
      'passing_bablok' || 'deming' => 'method_comparison',
      'equivalence_tost' || 'non_inferiority' || 'equivalence_proportions' => 'equivalence',
      'interrupted_time_series' => 'interrupted_series',
      'bayes_proportion' || 'bayes_effect' => 'bayes',
      'propensity_matching' || 'propensity_weighting' => 'propensity',
      'meta_binary' || 'meta_continuous' => 'meta',
      'prediction_logistic_internal' => 'prediction',
      'hardy_weinberg' || 'genetic_association' || 'snp_scan' || 'lmm_scan' || 'ldsc' || 'genetic_correlation' || 'polygenic_score' || 'glmm_scan' || 'mendelian_randomization' || 'mendelian_randomization_mv' || 'mr_steiger' || 'genotype_qc' || 'mutation_phenotype' || 'type_diversity' || 'qpcr_standard_curve' || 'qpcr_relative' || 'qpcr_lod' ||
      'differential_expression' || 'local_alignment' => 'genomics',
      'power_means' || 'power_proportions' || 'power_case_control' || 'power_survival' || 'power_gwas' => 'power',
      'describe_numeric' => 'describe',
      'describe_table1' => 'table1',
      _ => calculatorKinds.any((k) => k.$1 == methodId) ? methodId : 'proportion_ci',
    };

/// Mots-clés de recherche propres à chaque calculateur (en plus de son libellé, de sa famille et des méthodes du
/// registre qu'il calcule) : termes du laboratoire et de la clinique, synonymes, noms de tests.
Map<String, String> get _calculatorKeywords => {
      'proportion_ci': tr('prévalence fréquence pourcentage intervalle de confiance wilson exact taux', 'prevalence frequency percentage confidence interval wilson exact rate'),
      'describe': tr('moyenne médiane écart-type quartiles distribution résumé', 'mean median standard deviation quartiles distribution summary'),
      'table1': tr('tableau 1 caractéristiques participants population baseline groupes article', 'table 1 characteristics participants baseline groups article'),
      'two_by_two': tr('risque relatif odds ratio rapport de cotes chi deux fisher exposition cohorte cas-témoins', 'relative risk odds ratio chi square fisher exposure cohort case-control'),
      'chi_square_rxc': tr('chi deux contingence qualitatives association cramer', 'chi square contingency categorical association cramer'),
      'diagnostic_accuracy': tr('sensibilité spécificité valeur prédictive vpp vpn rapport de vraisemblance test diagnostique', 'sensitivity specificity predictive value ppv npv likelihood ratio diagnostic test'),
      'compare_two': tr('test t student welch mann whitney moyennes deux groupes comparer', 'student t test welch mann whitney means two groups compare'),
      'compare_k': tr('anova kruskal wallis plusieurs groupes tukey', 'anova kruskal wallis several groups tukey'),
      'paired': tr('apparié avant après wilcoxon test t apparié', 'paired before after wilcoxon paired t test'),
      'mcnemar': tr('apparié binaire avant après', 'paired binary before after'),
      'correlation': tr('pearson spearman relation lien coefficient', 'pearson spearman relationship coefficient'),
      'bland_altman': tr('accord concordance limites d\'accord biais deux méthodes dosage laboratoire', 'agreement concordance limits of agreement bias two methods assay laboratory'),
      'reference_interval': tr('valeurs de référence normes normales bornes population saine clsi ep28 percentiles', 'reference values normal range limits healthy population clsi ep28 percentiles'),
      'precision': tr('répétabilité reproductibilité fidélité intermédiaire cv coefficient de variation contrôle qualité clsi ep05 ep15 vérification', 'repeatability reproducibility intermediate precision cv coefficient of variation quality control clsi ep05 ep15 verification'),
      'method_comparison': tr('passing bablok deming dosage analyseur automate laboratoire biais pente créatinine glycémie', 'passing bablok deming assay analyser laboratory bias slope creatinine glucose'),
      'kaplan_meier': tr('survie délai décès log-rank courbe médiane de survie', 'survival time death log-rank curve median survival'),
      'cumulative_incidence': tr('risques concurrents gray fine-gray rechute décès', 'competing risks gray fine-gray relapse death'),
      'rmst': tr('survie moyenne restreinte risques non proportionnels', 'restricted mean survival non-proportional hazards'),
      'landmark': tr('temps immortel greffe exposition pendant le suivi', 'immortal time transplant exposure during follow-up'),
      'equivalence': tr('équivalence non-infériorité tost marge bioéquivalence générique', 'equivalence non-inferiority tost margin bioequivalence generic'),
      'bayes': tr('bayésien bayes a priori a posteriori crédibilité probabilité sceptique enthousiaste bêta', 'bayesian bayes prior posterior credible probability sceptical enthusiastic beta'),
      'e_value': tr('valeur e confusion non mesurée sensibilité vanderweele biais', 'e-value unmeasured confounding sensitivity vanderweele bias'),
      'interrupted_series': tr('série chronologique temporelle interrompue régression segmentée politique intervention avant après tendance', 'interrupted time series segmented regression policy intervention before after trend'),
      'propensity': tr('confusion causalité appariement pondération iptw observationnel traitement effet', 'confounding causality matching weighting iptw observational treatment effect'),
      'calibration': tr('hosmer lemeshow calibration risque prédit score validation brier', 'hosmer lemeshow calibration predicted risk score validation brier'),
      'sample_size': tr('nombre de sujets effectif nécessaire précision', 'number of subjects required sample precision'),
      'power': tr('puissance effectif survie cas-témoins gwas', 'power sample size survival case-control gwas'),
      'regression': tr('régression linéaire logistique poisson cox ajustement multivariée spline mixte gee ordinale', 'linear logistic poisson cox regression adjustment multivariable spline mixed gee ordinal'),
      'meta': tr('métaanalyse forest plot hétérogénéité revue systématique', 'meta-analysis forest plot heterogeneity systematic review'),
      'prediction': tr('modèle de prédiction score de risque auc validation bootstrap', 'prediction model risk score auc validation bootstrap'),
      'genomics': tr('génétique génotype snp gwas expression rna-seq qpcr alignement blast', 'genetics genotype snp gwas expression rna-seq qpcr alignment blast'),
    };

/// Calculateur qui réalise une méthode du registre (null si aucun).
String? _calculatorOfMethod(MethodInfo m) {
  final c = calculatorFor(m.id);
  if (c != 'proportion_ci' || m.id == 'proportion_ci') return c;
  return switch (m.category) {
    'Régression' || 'Regression' => 'regression',
    'Génétique' || 'Genetics' => 'genomics',
    'Métaanalyse' || 'Meta-analysis' => 'meta',
    'Prédiction' || 'Prediction' => 'prediction',
    _ => null,
  };
}

/// Calculateurs correspondant à [query] : tous les mots (sans accents ni casse) doivent figurer dans le libellé, la
/// famille, les mots-clés ou les méthodes du registre que le calculateur réalise. Rangés par pertinence (libellé d'abord).
List<String> searchCalculators(String query) {
  String norm(String t) => foldAccents(t.toLowerCase());
  final words = norm(query).split(RegExp(r'[^a-z0-9²]+')).where((w) => w.length > 1).toList();
  if (words.isEmpty) return const [];
  final methods = <String, List<MethodInfo>>{};
  for (final m in methodRegistry) {
    final c = _calculatorOfMethod(m);
    if (c != null) methods.putIfAbsent(c, () => []).add(m);
  }
  final scored = <(String, int)>[];
  for (final (id, label, _, family) in calculatorKinds) {
    final head = norm('$label $family');
    final hay = norm([head, _calculatorKeywords[id] ?? '', for (final m in methods[id] ?? const <MethodInfo>[]) '${m.name} ${m.question} ${m.category}'].join(' '));
    if (!words.every(hay.contains)) continue;
    scored.add((id, words.where(head.contains).length));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
}

/// Panneau de calcul : sélection du calculateur, saisie, résultat. Dans un
/// projet, chaque résultat est ajouté au journal.
class CalculatorPanel extends StatefulWidget {
  final Project? project;
  final String? initialMethod;

  /// Préréglages du calculateur d'effectif (voir [SampleSizeCalc.presets]).
  final Map<String, String> presets;
  const CalculatorPanel({super.key, this.project, this.initialMethod, this.presets = const {}});
  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel> {
  late String kind = calculatorFor(widget.initialMethod ?? 'proportion_ci');
  late String family = calculatorKinds.firstWhere((k) => k.$1 == kind).$4;
  final search = TextEditingController();
  AnalysisResult? result;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void choose(String id) => setState(() {
        kind = id;
        family = calculatorKinds.firstWhere((k) => k.$1 == id).$4;
        result = null;
      });

  void onResult(AnalysisResult r, {Map<String, Object?> options = const {}}) {
    setState(() => result = r);
    final p = widget.project;
    if (p != null) context.read<AppState>().record(p, r, options: options);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final lessons = context.read<AppState>().lessons;
    final ds = p?.dataset;
    final form = switch (kind) {
      'proportion_ci' => ProportionCalc(ds, onResult),
      'describe' => DescribeCalc(ds, onResult),
      'table1' => Table1Calc(ds, onResult),
      'two_by_two' => TwoByTwoCalc(ds, p?.question.design ?? StudyDesign.unknown, onResult),
      'chi_square_rxc' => ChiRxCCalc(ds, onResult),
      'diagnostic_accuracy' => DiagnosticCalc(p?.question.design ?? StudyDesign.diagnosticAccuracy, onResult),
      'compare_two' => CompareTwoCalc(ds, onResult, initial: widget.initialMethod),
      'compare_k' => CompareKCalc(ds, onResult, initial: widget.initialMethod),
      'paired' => PairedCalc(ds, onResult, initial: widget.initialMethod),
      'mcnemar' => McNemarCalc(onResult),
      'correlation' => CorrelationCalc(ds, onResult),
      'bland_altman' => BlandAltmanCalc(ds, onResult),
      'method_comparison' => MethodComparisonCalc(ds, onResult, initial: widget.initialMethod),
      'calibration' => CalibrationCalc(ds, onResult),
      'reference_interval' => ReferenceIntervalCalc(ds, onResult),
      'precision' => PrecisionCalc(ds, onResult),
      'propensity' => PropensityCalc(ds, onResult, initial: widget.initialMethod),
      'equivalence' => EquivalenceCalc(ds, onResult, initial: widget.initialMethod),
      'e_value' => EValueCalc(onResult),
      'bayes' => BayesCalc(onResult, initial: widget.initialMethod),
      'interrupted_series' => InterruptedSeriesCalc(ds, onResult),
      'sample_size' => SampleSizeCalc(onResult, presets: widget.presets),
      'power' => PowerCalc(onResult, initial: widget.initialMethod),
      'kaplan_meier' => SurvivalCalc(ds, onResult),
      'cumulative_incidence' => CompetingRisksCalc(ds, onResult),
      'rmst' => RmstCalc(ds, onResult),
      'landmark' => LandmarkCalc(ds, onResult),
      'regression' => RegressionWorkshop(project: p, onResult: onResult, initialMethod: widget.initialMethod),
      'meta' => MetaWorkshop(project: p, onResult: onResult),
      'genomics' => GenomicsWorkshop(project: p, onResult: onResult, initialMethod: widget.initialMethod),
      _ => PredictionWorkshop(project: p, onResult: onResult),
    };
    final info = result == null ? null : methodInfo(result!.methodId);
    final lesson = info == null ? null : lessonById(lessons, info.lessonId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          labelText: tr('Rechercher une méthode', 'Search for a method'),
          hintText: tr('p. ex. survie, créatinine, comparer deux moyennes', 'e.g. survival, creatinine, compare two means'),
          suffixIcon: search.text.isEmpty
              ? null
              : IconButton(tooltip: tr('Effacer', 'Clear'), icon: const Icon(Icons.clear), onPressed: () => setState(search.clear)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      if (search.text.trim().isNotEmpty) ...[
        Builder(builder: (context) {
          final hits = searchCalculators(search.text);
          if (hits.isEmpty) {
            return Text(tr('Aucune méthode ne correspond. Essayer un autre mot, ou parcourir les familles (effacer la recherche).', 'No method matches. Try another word, or browse the families (clear the search).'),
                style: Theme.of(context).textTheme.bodySmall);
          }
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in hits)
              () {
                final k = calculatorKinds.firstWhere((k) => k.$1 == id);
                return ChoiceChip(avatar: Icon(k.$3, size: 16), label: Text(k.$2), tooltip: k.$4, selected: kind == id, onSelected: (_) => choose(id));
              }(),
          ]);
        }),
      ] else ...[
        Text(tr('Familles', 'Families'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in {for (final k in calculatorKinds) k.$4})
            ChoiceChip(label: Text(f), selected: family == f, onSelected: (_) => setState(() => family = f)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (id, label, icon, f) in calculatorKinds)
            if (f == family) ChoiceChip(avatar: Icon(icon, size: 16), label: Text(label), selected: kind == id, onSelected: (_) => choose(id)),
        ]),
      ],
      const SizedBox(height: 12),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: VariableRolesScope(roles: p?.roles.validFor(ds) ?? const VariableRoles(), dataset: ds, child: KeyedSubtree(key: ValueKey(kind), child: form)))),
      if (result != null)
        ResultView(result!,
            onOpenLesson: lesson == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(lesson)))),
      if (result != null && p != null)
        Text(tr('Résultat ajouté au journal du projet (${p.journal.length} analyse(s)).', 'Result added to the project log (${p.journal.length} analysis(es)).'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

typedef OnResult = void Function(AnalysisResult r, {Map<String, Object?> options});

/// Exécute un calcul en affichant les erreurs d'entrée de façon lisible.
void run(BuildContext context, AnalysisResult Function() f, OnResult onResult, {Map<String, Object?> options = const {}}) {
  try {
    onResult(f(), options: options);
  } on StatInputError catch (e) {
    showError(context, e);
  } catch (e) {
    showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
  }
}

/// Lit une série de nombres (séparateurs : espace, « ; », retour à la ligne ;
/// virgule décimale acceptée).
List<double?> parseSeries(String s) =>
    [for (final t in s.split(RegExp(r'[\s;]+')).where((t) => t.trim().isNotEmpty)) parseNumber(t)];

Widget _computeButton(BuildContext context, VoidCallback onPressed) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.calculate), label: Text(tr('Calculer', 'Compute')))),
    );

Widget _levelField(BuildContext context, TextEditingController c) {
  final expert = context.watch<AppState>().expertMode;
  return expert ? NumField(tr('Niveau de confiance', 'Confidence level'), c, helper: tr('p. ex. 0,95', 'e.g. 0.95')) : const SizedBox.shrink();
}

double _level(TextEditingController c) => (readNum(c) ?? 0.95).clamp(0.5, 0.999);

List<(String, String)> _vars(Dataset ds, {Set<VarType>? types}) =>
    [for (final n in ds.names) if (types == null || types.contains(ds.dictionary[n]!.type)) (n, '$n (${varTypeLabel(ds.dictionary[n]!.type)})')];

/// Bascule « depuis les données » / « saisie ».
class SourceToggle extends StatelessWidget {
  final bool fromData;
  final ValueChanged<bool> onChanged;
  final String? _manualLabel;
  String get manualLabel => _manualLabel ?? tr('Saisie directe', 'Direct entry');
  // ignore: prefer_initializing_formals (paramètre nommé public, champ privé)
  const SourceToggle(this.fromData, this.onChanged, {super.key, String? manualLabel}) : _manualLabel = manualLabel;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(tr('Depuis les données', 'From the data')), icon: Icon(Icons.table_chart_outlined)),
            ButtonSegment(value: false, label: Text(manualLabel), icon: const Icon(Icons.edit_outlined)),
          ],
          selected: {fromData},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}

// ---------------------------------------------------------------- Proportion

class ProportionCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const ProportionCalc(this.ds, this.onResult, {super.key});
  @override
  State<ProportionCalc> createState() => _ProportionCalcState();
}

class _ProportionCalcState extends State<ProportionCalc> {
  late bool fromData = widget.ds != null;
  final x = TextEditingController(text: '12'), n = TextEditingController(text: '400'), level = TextEditingController(text: '0,95');
  String? variable, event;
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Proportion et IC (Wilson, exact)', 'Proportion and CI (Wilson, exact)'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (ds != null) SourceToggle(fromData, (v) => setState(() => fromData = v)),
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (fromData && ds != null) ...[
          Pick<String>('Variable', variable, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                variable = v;
                event = null;
              })),
          if (variable != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(variable!)) (l, l)], (v) => setState(() => event = v)),
        ] else ...[
          NumField(tr('Événements x', 'Events x'), x),
          NumField(tr('Effectif n', 'Sample size n'), n),
        ],
        _levelField(context, level),
      ]),
      _computeButton(context, () {
        run(context, () {
          if (fromData && ds != null) {
            if (variable == null || event == null) throw StatInputError('missing', tr('Choisir la variable et la modalité « événement ».', 'Choose the variable and the event level.'));
            final t = ds.text(variable!);
            final excl = ds.excludedRows;
            final vals = [for (var i = 0; i < t.length; i++) if (!excl.contains(i) && t[i] != null) t[i]];
            return proportionCi(vals.where((v) => v == event).length, vals.length, level: _level(level), label: '$variable = $event');
          }
          final xi = readInt(x), ni = readInt(n);
          if (xi == null || ni == null) throw StatInputError('int', tr('x et n doivent être des entiers.', 'x and n must be integers.'));
          return proportionCi(xi, ni, level: _level(level));
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Descriptif

class DescribeCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const DescribeCalc(this.ds, this.onResult, {super.key});
  @override
  State<DescribeCalc> createState() => _DescribeCalcState();
}

class _DescribeCalcState extends State<DescribeCalc> {
  String? variable;
  final series = TextEditingController(text: '5,2 6,1 5,8 7,4 6,6 5,9 8,3 6,0');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Statistiques descriptives', 'Descriptive statistics'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (ds != null)
        Pick<String>('Variable', variable, _vars(ds), (v) => setState(() => variable = v))
      else
        TextField(controller: series, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('Valeurs (séparées par des espaces ou « ; »)', 'Values (separated by spaces or ";")'))),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (variable == null) throw StatInputError('missing', tr('Choisir une variable.', 'Choose a variable.'));
            final v = ds.dictionary[variable]!;
            final excl = ds.excludedRows;
            if (v.type == VarType.numeric) {
              final col = ds.numeric(variable!);
              return describeNumeric([for (var i = 0; i < col.length; i++) excl.contains(i) ? null : col[i]], variable: variable!, unit: v.unit);
            }
            final col = ds.text(variable!);
            return describeCategorical([for (var i = 0; i < col.length; i++) if (!excl.contains(i)) col[i]], variable: variable!);
          }
          return describeNumeric(parseSeries(series.text));
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Tableau 1

class Table1Calc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const Table1Calc(this.ds, this.onResult, {super.key});
  @override
  State<Table1Calc> createState() => _Table1CalcState();
}

class _Table1CalcState extends State<Table1Calc> {
  String? group;
  Table1? table;

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    if (ds == null) {
      return Text(tr('Tableau 1 : importer d\'abord les données du projet (étape 4).', 'Table 1: first import the project data (step 4).'));
    }
    final groups = [
      for (final n in ds.names)
        if (ds.dictionary[n]!.type != VarType.numeric && ds.dictionary[n]!.type != VarType.identifier && ds.levels(n).length >= 2 && ds.levels(n).length <= 6) (n, n)
    ];
    Future<void> save(String name, Uint8List bytes, String mime) async {
      final where = await saveFile(name, bytes, mime);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Enregistré : $where', 'Saved: $where'))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Tableau 1 : caractéristiques des participants', 'Table 1: participant characteristics'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Pick<String?>(tr('Comparer selon (facultatif)', 'Compare by (optional)'), group, [(null, tr('— aucun groupe —', '— no group —')), for (final g in groups) (g.$1, g.$2)],
          (v) => setState(() => group = v)),
      _computeButton(context, () {
        run(context, () {
          table = table1(ds, group: group);
          setState(() {});
          return table1Result(ds, group: group);
        }, widget.onResult);
      }),
      if (table != null)
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(tr('Tableau 1 (Word)', 'Table 1 (Word)')),
            onPressed: () => save('tableau1.docx', tableDocx(tr('Tableau 1. Caractéristiques des participants', 'Table 1. Participant characteristics'), table!.header, table!.cells, notes: table!.notes),
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.grid_on_outlined),
            label: Text(tr('Tableau 1 (Excel)', 'Table 1 (Excel)')),
            onPressed: () => save('tableau1.xlsx', tableXlsx(tr('Tableau 1', 'Table 1'), table!.header, table!.cells, notes: table!.notes), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
          ),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------- 2 × 2

class TwoByTwoCalc extends StatefulWidget {
  final Dataset? ds;
  final StudyDesign design;
  final OnResult onResult;
  const TwoByTwoCalc(this.ds, this.design, this.onResult, {super.key});
  @override
  State<TwoByTwoCalc> createState() => _TwoByTwoCalcState();
}

class _TwoByTwoCalcState extends State<TwoByTwoCalc> {
  late bool fromData = widget.ds != null;
  late StudyDesign design = widget.design;
  final a = TextEditingController(text: '120'), b = TextEditingController(text: '380'), c = TextEditingController(text: '80'), d = TextEditingController(text: '420');
  final level = TextEditingController(text: '0,95');
  String? expo, expoLevel, out, outLevel;
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    final bin = ds == null ? <(String, String)>[] : _vars(ds, types: {VarType.binary, VarType.categorical});
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Tableau 2 × 2', '2 × 2 table'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Pick<StudyDesign>(tr('Plan d\'étude', 'Study design'), design, [for (final x in StudyDesign.values.where((x) => x != StudyDesign.systematicReview)) (x, designLabel(x))],
          (v) => setState(() => design = v ?? StudyDesign.unknown)),
      const SizedBox(height: 10),
      if (ds != null) SourceToggle(fromData, (v) => setState(() => fromData = v), manualLabel: tr('Saisie des effectifs', 'Count entry')),
      if (fromData && ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Exposition', 'Exposure'), expo, bin, (v) => setState(() {
                expo = v;
                expoLevel = null;
              })),
          if (expo != null) Pick<String>(tr('Modalité « exposé »', 'Exposed level'), expoLevel, [for (final l in ds.levels(expo!)) (l, l)], (v) => setState(() => expoLevel = v)),
          Pick<String>(tr('Issue', 'Outcome'), out, bin, (v) => setState(() {
                out = v;
                outLevel = null;
              })),
          if (out != null) Pick<String>(tr('Modalité « événement »', 'Event level'), outLevel, [for (final l in ds.levels(out!)) (l, l)], (v) => setState(() => outLevel = v)),
        ])
      else
        Table(defaultColumnWidth: const IntrinsicColumnWidth(), children: [
          TableRow(children: [SizedBox(), Padding(padding: EdgeInsets.all(4), child: Text(tr('Événement', 'Event'))), Padding(padding: EdgeInsets.all(4), child: Text(tr('Pas d\'événement', 'No event')))]),
          TableRow(children: [Padding(padding: EdgeInsets.all(8), child: Text(tr('Exposés', 'Exposed'))), Padding(padding: const EdgeInsets.all(4), child: NumField('a', a, width: 110)), Padding(padding: const EdgeInsets.all(4), child: NumField('b', b, width: 110))]),
          TableRow(children: [Padding(padding: EdgeInsets.all(8), child: Text(tr('Non exposés', 'Unexposed'))), Padding(padding: const EdgeInsets.all(4), child: NumField('c', c, width: 110)), Padding(padding: const EdgeInsets.all(4), child: NumField('d', d, width: 110))]),
        ]),
      _levelField(context, level),
      _computeButton(context, () {
        run(context, () {
          if (fromData && ds != null) {
            if ([expo, expoLevel, out, outLevel].contains(null)) throw StatInputError('missing', tr('Choisir exposition, issue et modalités.', 'Choose exposure, outcome and levels.'));
            final e = ds.text(expo!), o = ds.text(out!);
            final excl = ds.excludedRows;
            var aa = 0, bb = 0, cc = 0, dd = 0, miss = 0;
            for (var i = 0; i < ds.rowCount; i++) {
              if (excl.contains(i)) continue;
              if (e[i] == null || o[i] == null) {
                miss++;
                continue;
              }
              final ex = e[i] == expoLevel, ev = o[i] == outLevel;
              if (ex && ev) aa++;
              if (ex && !ev) bb++;
              if (!ex && ev) cc++;
              if (!ex && !ev) dd++;
            }
            final r = twoByTwo(aa, bb, cc, dd, design: design, level: _level(level), exposure: '$expo = $expoLevel', outcome: '$out = $outLevel');
            return miss == 0
                ? r
                : AnalysisResult(
                    methodId: r.methodId,
                    methodName: r.methodName,
                    inputs: {...r.inputs, 'missing_excluded': miss},
                    formula: r.formula,
                    estimates: r.estimates,
                    statistics: r.statistics,
                    checks: r.checks,
                    alerts: [Alert('missing_values', Severity.caution, tr('$miss ligne(s) exclue(s) pour valeur manquante.', '$miss row(s) excluded for missing values.')), ...r.alerts],
                    tables: r.tables,
                    log: r.log,
                    interpretation: r.interpretation);
          }
          final v = [readInt(a), readInt(b), readInt(c), readInt(d)];
          if (v.contains(null)) throw StatInputError('int', tr('Les effectifs doivent être des entiers.', 'Counts must be integers.'));
          return twoByTwo(v[0]!, v[1]!, v[2]!, v[3]!, design: design, level: _level(level));
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- χ² r × c

class ChiRxCCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const ChiRxCCalc(this.ds, this.onResult, {super.key});
  @override
  State<ChiRxCCalc> createState() => _ChiRxCCalcState();
}

class _ChiRxCCalcState extends State<ChiRxCCalc> {
  String? r, c;
  final manual = TextEditingController(text: '20 12 8\n15 25 22\n30 18 10');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('χ² d\'indépendance r × c', 'χ² test of independence r × c'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Variable en lignes', 'Row variable'), r, _vars(ds, types: {VarType.binary, VarType.categorical, VarType.ordinal}), (v) => setState(() => r = v)),
          Pick<String>(tr('Variable en colonnes', 'Column variable'), c, _vars(ds, types: {VarType.binary, VarType.categorical, VarType.ordinal}), (v) => setState(() => c = v)),
        ])
      else
        TextField(controller: manual, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: tr('Tableau (une ligne par ligne, effectifs séparés par des espaces)', 'Table (one row per line, counts separated by spaces)'))),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (r == null || c == null) throw StatInputError('missing', tr('Choisir deux variables.', 'Choose two variables.'));
            final lr = ds.levels(r!), lc = ds.levels(c!);
            final tx = ds.text(r!), tc = ds.text(c!);
            final t = [for (final _ in lr) List<int>.filled(lc.length, 0)];
            for (var i = 0; i < ds.rowCount; i++) {
              if (tx[i] == null || tc[i] == null || ds.excludedRows.contains(i)) continue;
              t[lr.indexOf(tx[i]!)][lc.indexOf(tc[i]!)]++;
            }
            return chiSquareRxC(t, rowNames: lr, colNames: lc);
          }
          final rows = [
            for (final line in manual.text.trim().split('\n'))
              [for (final v in parseSeries(line)) v?.toInt() ?? (throw StatInputError('int', tr('Effectifs entiers attendus.', 'Integer counts expected.')))]
          ];
          if (rows.any((x) => x.length != rows.first.length)) throw StatInputError('shape', tr('Toutes les lignes doivent avoir le même nombre de colonnes.', 'All rows must have the same number of columns.'));
          return chiSquareRxC(rows);
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Diagnostic

class DiagnosticCalc extends StatefulWidget {
  final StudyDesign design;
  final OnResult onResult;
  const DiagnosticCalc(this.design, this.onResult, {super.key});
  @override
  State<DiagnosticCalc> createState() => _DiagnosticCalcState();
}

class _DiagnosticCalcState extends State<DiagnosticCalc> {
  final tp = TextEditingController(text: '90'), fp = TextEditingController(text: '30'), fn = TextEditingController(text: '10'), tn = TextEditingController(text: '870');
  final prev = TextEditingController(), level = TextEditingController(text: '0,95');
  late bool caseControl = widget.design == StudyDesign.caseControl;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Performance diagnostique', 'Diagnostic accuracy'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          NumField(tr('Vrais positifs', 'True positives'), tp),
          NumField(tr('Faux positifs', 'False positives'), fp),
          NumField(tr('Faux négatifs', 'False negatives'), fn),
          NumField(tr('Vrais négatifs', 'True negatives'), tn),
          NumField(tr('Prévalence cible (facultatif)', 'Target prevalence (optional)'), prev, helper: tr('p. ex. 0,01', 'e.g. 0.01'), width: 200),
          _levelField(context, level),
        ]),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: caseControl,
          onChanged: (v) => setState(() => caseControl = v ?? false),
          title: Text(tr('Malades et non-malades recrutés séparément (cas-témoins)', 'Diseased and non-diseased recruited separately (case-control)')),
        ),
        _computeButton(context, () {
          run(context, () {
            final v = [readInt(tp), readInt(fp), readInt(fn), readInt(tn)];
            if (v.contains(null)) throw StatInputError('int', tr('Effectifs entiers attendus.', 'Integer counts expected.'));
            final pr = readNum(prev);
            return diagnosticAccuracy(v[0]!, v[1]!, v[2]!, v[3]!,
                level: _level(level), targetPrevalence: pr, design: caseControl ? StudyDesign.caseControl : StudyDesign.diagnosticAccuracy);
          }, widget.onResult);
        }),
      ]);
}

// ---------------------------------------------------------------- Comparaisons

({List<double?> a, List<double?> b, String ga, String gb}) _twoGroups(Dataset ds, String y, String g, String la, String lb) {
  final yy = ds.numeric(y), gg = ds.text(g);
  final excl = ds.excludedRows;
  return (
    a: [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i) && gg[i] == la) yy[i]],
    b: [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i) && gg[i] == lb) yy[i]],
    ga: la,
    gb: lb,
  );
}

class CompareTwoCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const CompareTwoCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<CompareTwoCalc> createState() => _CompareTwoCalcState();
}

class _CompareTwoCalcState extends State<CompareTwoCalc> {
  late String method = widget.initial == 'mann_whitney' ? 'mw' : (widget.initial == 't_test_student' ? 'student' : 'welch');
  String? y, g, la, lb;
  final s1 = TextEditingController(text: '5,1 5,8 6,2 4,9 5,5 6,0 5,3 5,7'), s2 = TextEditingController(text: '5,9 6,4 6,8 6,1 7,0 6,3 6,6 5,8');
  final margin = TextEditingController(), level = TextEditingController(text: '0,95');
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    y ??= r.pick(r.roles.outcome, {VarType.numeric, VarType.ordinal});
    g ??= r.pick(r.roles.exposure, {VarType.binary, VarType.categorical});
    if (g != null && widget.ds != null) {
      final l = widget.ds!.levels(g!);
      la ??= l.isNotEmpty ? l.first : null;
      lb ??= l.length > 1 ? l[1] : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    final expert = context.watch<AppState>().expertMode;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Comparer deux groupes indépendants', 'Compare two independent groups'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(segments: [
        ButtonSegment(value: 'welch', label: Text(tr('t de Welch', "Welch's t"))),
        if (expert) ButtonSegment(value: 'student', label: Text(tr('t de Student', "Student's t"))),
        const ButtonSegment(value: 'mw', label: Text('Mann-Whitney')),
      ], selected: {method}, onSelectionChanged: (s) => setState(() => method = s.first)),
      const SizedBox(height: 10),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Variable quantitative', 'Quantitative variable'), y, _vars(ds, types: {VarType.numeric, VarType.ordinal}), (v) => setState(() => y = v)),
          Pick<String>(tr('Variable de groupe', 'Grouping variable'), g, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                g = v;
                final l = v == null ? <String>[] : ds.levels(v);
                la = l.isNotEmpty ? l.first : null;
                lb = l.length > 1 ? l[1] : null;
              })),
          if (g != null) Pick<String>(tr('Groupe 1', 'Group 1'), la, [for (final l in ds.levels(g!)) (l, l)], (v) => setState(() => la = v), width: 180),
          if (g != null) Pick<String>(tr('Groupe 2', 'Group 2'), lb, [for (final l in ds.levels(g!)) (l, l)], (v) => setState(() => lb = v), width: 180),
        ])
      else ...[
        TextField(controller: s1, decoration: InputDecoration(labelText: tr('Groupe 1 : valeurs', 'Group 1: values'))),
        const SizedBox(height: 8),
        TextField(controller: s2, decoration: InputDecoration(labelText: tr('Groupe 2 : valeurs', 'Group 2: values'))),
      ],
      if (expert && method != 'mw')
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 12, children: [
              NumField(tr('Marge cliniquement pertinente', 'Clinically relevant margin'), margin, width: 220, helper: tr('pour juger l\'absence d\'effet', 'to judge absence of effect')),
              _levelField(context, level),
            ])),
      _computeButton(context, () {
        run(context, () {
          List<double?> a, b;
          String ga = tr('Groupe 1', 'Group 1'), gb = tr('Groupe 2', 'Group 2');
          if (ds != null) {
            if (y == null || g == null || la == null || lb == null || la == lb) throw StatInputError('missing', tr('Choisir la variable, le groupe et deux modalités différentes.', 'Choose the variable, the group and two different levels.'));
            final r = _twoGroups(ds, y!, g!, la!, lb!);
            a = r.a;
            b = r.b;
            ga = r.ga;
            gb = r.gb;
          } else {
            a = parseSeries(s1.text);
            b = parseSeries(s2.text);
          }
          if (method == 'mw') return mannWhitney(a, b, group1: ga, group2: gb);
          return tTestIndependent(a, b, welch: method == 'welch', group1: ga, group2: gb, level: _level(level), margin: readNum(margin),
              unit: ds != null && y != null ? ds.dictionary[y]!.unit : '');
        }, widget.onResult);
      }),
    ]);
  }
}

class CompareKCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const CompareKCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<CompareKCalc> createState() => _CompareKCalcState();
}

class _CompareKCalcState extends State<CompareKCalc> {
  late String method = widget.initial == 'kruskal_wallis' ? 'kw' : 'anova';
  String? y, g;
  final manual = TextEditingController(text: tr('A: 5,1 5,8 6,2 4,9 5,5\nB: 5,9 6,4 6,8 6,1 7,0\nC: 7,2 6,9 7,8 8,1 7,4', 'A: 5.1 5.8 6.2 4.9 5.5\nB: 5.9 6.4 6.8 6.1 7.0\nC: 7.2 6.9 7.8 8.1 7.4'));
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    y ??= r.pick(r.roles.outcome, {VarType.numeric, VarType.ordinal});
    g ??= r.pick(r.roles.exposure, {VarType.binary, VarType.categorical});
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Comparer k groupes indépendants', 'Compare k independent groups'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(segments: [
        ButtonSegment(value: 'anova', label: Text('ANOVA')),
        ButtonSegment(value: 'welch', label: Text(tr('ANOVA de Welch', "Welch's ANOVA"))),
        ButtonSegment(value: 'kw', label: Text('Kruskal-Wallis')),
      ], selected: {method}, onSelectionChanged: (s) => setState(() => method = s.first)),
      const SizedBox(height: 10),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Variable quantitative', 'Quantitative variable'), y, _vars(ds, types: {VarType.numeric, VarType.ordinal}), (v) => setState(() => y = v)),
          Pick<String>(tr('Variable de groupe', 'Grouping variable'), g, _vars(ds, types: {VarType.binary, VarType.categorical, VarType.ordinal}), (v) => setState(() => g = v)),
        ])
      else
        TextField(controller: manual, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: tr('Un groupe par ligne : « nom: valeurs »', 'One group per line: "name: values"'))),
      _computeButton(context, () {
        run(context, () {
          final groups = <String, List<double?>>{};
          if (ds != null) {
            if (y == null || g == null) throw StatInputError('missing', tr('Choisir la variable et le groupe.', 'Choose the variable and the group.'));
            final yy = ds.numeric(y!), gg = ds.text(g!);
            for (var i = 0; i < ds.rowCount; i++) {
              if (gg[i] == null || ds.excludedRows.contains(i)) continue;
              groups.putIfAbsent(gg[i]!, () => []).add(yy[i]);
            }
          } else {
            for (final line in manual.text.trim().split('\n')) {
              final parts = line.split(':');
              if (parts.length != 2) continue;
              groups[parts[0].trim()] = parseSeries(parts[1]);
            }
          }
          return method == 'kw' ? kruskalWallis(groups) : anovaOneWay(groups, welch: method == 'welch');
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Apparié, corrélation, accord

class _TwoColumns extends StatelessWidget {
  final Dataset? ds;
  final String? a, b;
  final ValueChanged<String?> onA, onB;
  final TextEditingController sa, sb;
  final String? _la, _lb;
  String get la => _la ?? tr('Mesure 1', 'Measurement 1');
  String get lb => _lb ?? tr('Mesure 2', 'Measurement 2');
  // ignore: prefer_initializing_formals (paramètre nommé public, champ privé)
  const _TwoColumns(this.ds, this.a, this.b, this.onA, this.onB, this.sa, this.sb, {String? la, String? lb}) : _la = la, _lb = lb;
  @override
  Widget build(BuildContext context) {
    if (ds != null) {
      final v = _vars(ds!, types: {VarType.numeric, VarType.ordinal});
      return Wrap(spacing: 12, runSpacing: 12, children: [Pick<String>(la, a, v, onA), Pick<String>(lb, b, v, onB)]);
    }
    return Column(children: [
      TextField(controller: sa, decoration: InputDecoration(labelText: tr('$la : valeurs (même ordre des sujets)', '$la: values (same subject order)'))),
      const SizedBox(height: 8),
      TextField(controller: sb, decoration: InputDecoration(labelText: tr('$lb : valeurs', '$lb: values'))),
    ]);
  }
}

({List<double?> x, List<double?> y}) _cols(Dataset? ds, String? a, String? b, TextEditingController sa, TextEditingController sb) {
  if (ds != null) {
    if (a == null || b == null) throw StatInputError('missing', tr('Choisir les deux variables.', 'Choose the two variables.'));
    final excl = ds.excludedRows;
    final x = ds.numeric(a), y = ds.numeric(b);
    return (x: [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) x[i]], y: [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) y[i]]);
  }
  return (x: parseSeries(sa.text), y: parseSeries(sb.text));
}

class PairedCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const PairedCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<PairedCalc> createState() => _PairedCalcState();
}

class _PairedCalcState extends State<PairedCalc> {
  late String method = widget.initial == 'wilcoxon_signed_rank' ? 'w' : 't';
  String? a, b;
  final sa = TextEditingController(text: '142 138 150 161 129 145 133 158'), sb = TextEditingController(text: '135 136 141 150 128 139 135 149');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Mesures appariées', 'Paired measurements'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(segments: [
          ButtonSegment(value: 't', label: Text(tr('t apparié', 'Paired t'))),
          ButtonSegment(value: 'w', label: Text(tr('Wilcoxon signé', 'Wilcoxon signed-rank'))),
        ], selected: {method}, onSelectionChanged: (s) => setState(() => method = s.first)),
        const SizedBox(height: 10),
        _TwoColumns(widget.ds, a, b, (v) => setState(() => a = v), (v) => setState(() => b = v), sa, sb, la: tr('Avant / mesure 1', 'Before / measurement 1'), lb: tr('Après / mesure 2', 'After / measurement 2')),
        _computeButton(context, () {
          run(context, () {
            final c = _cols(widget.ds, a, b, sa, sb);
            return method == 't' ? pairedTTest(c.x, c.y, label1: a ?? tr('Mesure 1', 'Measurement 1'), label2: b ?? tr('Mesure 2', 'Measurement 2')) : wilcoxonSignedRank(c.x, c.y);
          }, widget.onResult);
        }),
      ]);
}

class McNemarCalc extends StatefulWidget {
  final OnResult onResult;
  const McNemarCalc(this.onResult, {super.key});
  @override
  State<McNemarCalc> createState() => _McNemarCalcState();
}

class _McNemarCalcState extends State<McNemarCalc> {
  final a = TextEditingController(text: '40'), b = TextEditingController(text: '14'), c = TextEditingController(text: '5'), d = TextEditingController(text: '41');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('McNemar — tableau apparié', 'McNemar — paired table'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(tr('a = oui/oui, b = oui (mesure 1) / non (mesure 2), c = non/oui, d = non/non.', 'a = yes/yes, b = yes (measurement 1) / no (measurement 2), c = no/yes, d = no/no.')),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [NumField('a', a), NumField('b', b), NumField('c', c), NumField('d', d)]),
        _computeButton(context, () {
          run(context, () {
            final v = [readInt(a), readInt(b), readInt(c), readInt(d)];
            if (v.contains(null)) throw StatInputError('int', tr('Effectifs entiers attendus.', 'Integer counts expected.'));
            return mcNemar(v[0]!, v[1]!, v[2]!, v[3]!);
          }, widget.onResult);
        }),
      ]);
}

class CorrelationCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const CorrelationCalc(this.ds, this.onResult, {super.key});
  @override
  State<CorrelationCalc> createState() => _CorrelationCalcState();
}

class _CorrelationCalcState extends State<CorrelationCalc> {
  bool spearman = false;
  String? a, b;
  final sa = TextEditingController(text: '5,1 6,3 4,8 7,7 6,0 5,5 8,1 7,2'), sb = TextEditingController(text: '4,9 6,8 4,5 7,1 6,4 5,0 8,6 7,9');
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    a ??= r.pick(r.roles.exposure, {VarType.numeric, VarType.ordinal});
    b ??= r.pick(r.roles.outcome, {VarType.numeric, VarType.ordinal});
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Corrélation', 'Correlation'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<bool>(segments: const [
          ButtonSegment(value: false, label: Text('Pearson')),
          ButtonSegment(value: true, label: Text('Spearman')),
        ], selected: {spearman}, onSelectionChanged: (s) => setState(() => spearman = s.first)),
        const SizedBox(height: 10),
        _TwoColumns(widget.ds, a, b, (v) => setState(() => a = v), (v) => setState(() => b = v), sa, sb, la: 'Variable X', lb: 'Variable Y'),
        _computeButton(context, () {
          run(context, () {
            final c = _cols(widget.ds, a, b, sa, sb);
            return correlation(c.x, c.y, spearman: spearman, xName: a ?? 'X', yName: b ?? 'Y');
          }, widget.onResult);
        }),
      ]);
}

class BlandAltmanCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const BlandAltmanCalc(this.ds, this.onResult, {super.key});
  @override
  State<BlandAltmanCalc> createState() => _BlandAltmanCalcState();
}

class _BlandAltmanCalcState extends State<BlandAltmanCalc> {
  String? a, b;
  final sa = TextEditingController(text: '5,1 6,3 4,8 7,7 6,0 5,5 8,1 7,2 6,6 5,9 4,4 7,0'),
      sb = TextEditingController(text: '4,9 6,8 4,5 7,1 6,4 5,0 8,6 7,9 6,1 6,2 4,1 6,5');
  final limit = TextEditingController();
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Accord entre deux méthodes (Bland-Altman)', 'Agreement between two methods (Bland-Altman)'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _TwoColumns(widget.ds, a, b, (v) => setState(() => a = v), (v) => setState(() => b = v), sa, sb, la: tr('Méthode A', 'Method A'), lb: tr('Méthode B', 'Method B')),
        const SizedBox(height: 10),
        NumField(tr('Écart acceptable fixé a priori (±)', 'Acceptable difference set a priori (±)'), limit, width: 260, helper: tr('critère clinique, facultatif', 'clinical criterion, optional')),
        _computeButton(context, () {
          run(context, () {
            final c = _cols(widget.ds, a, b, sa, sb);
            return blandAltman(c.x, c.y, name1: a ?? tr('Méthode A', 'Method A'), name2: b ?? tr('Méthode B', 'Method B'), acceptableLimit: readNum(limit));
          }, widget.onResult);
        }),
      ]);
}

// ---------------------------------------------------------------- Taille d'échantillon

class SampleSizeCalc extends StatefulWidget {
  final OnResult onResult;

  /// Préréglages : 'type' (prop, two_props, two_means, correlation, riley) et valeurs des champs (lues dans le
  /// protocole par la relecture).
  final Map<String, String> presets;
  const SampleSizeCalc(this.onResult, {super.key, this.presets = const {}});
  @override
  State<SampleSizeCalc> createState() => _SampleSizeCalcState();
}

class _SampleSizeCalcState extends State<SampleSizeCalc> {
  late String type = widget.presets['type'] ?? 'prop';
  final p = TextEditingController(text: '0,08'), d = TextEditingController(text: '0,02'), pop = TextEditingController(), deff = TextEditingController(text: '1');
  final delta = TextEditingController(text: '5'), sd = TextEditingController(text: '12');
  final p1 = TextEditingController(text: '0,10'), p2 = TextEditingController(text: '0,05');
  final r = TextEditingController(text: '0,3');
  final params = TextEditingController(text: '10'), prev = TextEditingController(text: '0,15'), r2 = TextEditingController(text: '0,15'), shrink = TextEditingController(text: '0,9');
  final alpha = TextEditingController(text: '0,05'), power = TextEditingController(text: '0,8'), drop = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final fields = {'p': p, 'd': d, 'deff': deff, 'delta': delta, 'sd': sd, 'p1': p1, 'p2': p2, 'r': r, 'params': params, 'prev': prev, 'r2': r2, 's': shrink, 'alpha': alpha, 'power': power, 'drop': drop};
    for (final e in widget.presets.entries) {
      fields[e.key]?.text = e.value;
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Taille d\'échantillon', 'Sample size'), style: Theme.of(context).textTheme.titleMedium),
        if (widget.presets.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('Prérempli avec les hypothèses lues dans le protocole : à vérifier.', 'Prefilled with the assumptions read in the protocol: to check.'), style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (v, l) in [
            ('prop', tr('Estimer une proportion', 'Estimate a proportion')),
            ('two_props', tr('2 proportions', '2 proportions')),
            ('two_means', tr('2 moyennes', '2 means')),
            ('correlation', tr('Corrélation', 'Correlation')),
            ('riley', tr('Modèle de prédiction (Riley)', 'Prediction model (Riley)')),
          ])
            ChoiceChip(label: Text(l), selected: type == v, onSelected: (_) => setState(() => type = v)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (type == 'prop') ...[
            NumField(tr('Proportion attendue', 'Expected proportion'), p),
            NumField(tr('Précision ± (absolue)', 'Precision ± (absolute)'), d),
            NumField(tr('Taille de la population (fac.)', 'Population size (opt.)'), pop, width: 200),
            NumField(tr('Effet de plan', 'Design effect'), deff),
          ],
          if (type == 'two_props') ...[NumField(tr('p1 attendue', 'expected p1'), p1), NumField(tr('p2 attendue', 'expected p2'), p2)],
          if (type == 'two_means') ...[NumField(tr('Différence minimale pertinente', 'Minimal relevant difference'), delta, width: 220), NumField(tr('Écart-type', 'Standard deviation'), sd)],
          if (type == 'correlation') NumField(tr('Corrélation minimale pertinente r', 'Minimal relevant correlation r'), r, width: 240),
          if (type == 'riley') ...[
            NumField(tr('Paramètres candidats', 'Candidate parameters'), params, width: 190),
            NumField(tr('Prévalence de l\'issue', 'Outcome prevalence'), prev, width: 190),
            NumField(tr('R² de Cox-Snell attendu', 'Expected Cox-Snell R²'), r2, width: 210),
            NumField(tr('Rétrécissement visé S', 'Target shrinkage S'), shrink, width: 190),
            NumField(tr('Perdus de vue (proportion)', 'Lost to follow-up (proportion)'), drop, width: 200),
          ],
          if (type != 'prop' && type != 'riley') ...[NumField(tr('α (bilatéral)', 'α (two-sided)'), alpha), NumField(tr('Puissance', 'Power'), power), NumField(tr('Perdus de vue (proportion)', 'Lost to follow-up (proportion)'), drop, width: 200)],
        ]),
        _computeButton(context, () {
          run(context, () {
            switch (type) {
              case 'prop':
                return sampleSizeProportion(expected: readNum(p) ?? 0, precision: readNum(d) ?? 0, population: readInt(pop), designEffect: readNum(deff) ?? 1);
              case 'correlation':
                return sampleSizeCorrelation(r: readNum(r) ?? 0, alpha: readNum(alpha) ?? 0.05, power: readNum(power) ?? 0.8, dropout: readNum(drop) ?? 0);
              case 'riley':
                return sampleSizePredictionModel(
                    parameters: readInt(params) ?? 0, prevalence: readNum(prev) ?? 0, r2CoxSnell: readNum(r2) ?? 0, shrinkage: readNum(shrink) ?? 0.9, dropout: readNum(drop) ?? 0);
              case 'two_props':
                return sampleSizeTwoProportions(p1: readNum(p1) ?? 0, p2: readNum(p2) ?? 0, alpha: readNum(alpha) ?? 0.05, power: readNum(power) ?? 0.8, dropout: readNum(drop) ?? 0);
              default:
                return sampleSizeTwoMeans(delta: readNum(delta) ?? 0, sd: readNum(sd) ?? 0, alpha: readNum(alpha) ?? 0.05, power: readNum(power) ?? 0.8, dropout: readNum(drop) ?? 0);
            }
          }, widget.onResult);
        }),
      ]);
}

// ---------------------------------------------------------------- Survie

class SurvivalCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const SurvivalCalc(this.ds, this.onResult, {super.key});
  @override
  State<SurvivalCalc> createState() => _SurvivalCalcState();
}

class _SurvivalCalcState extends State<SurvivalCalc> {
  String? time, status, event, group;
  final horizon = TextEditingController();
  final mt = TextEditingController(text: '3 5 6 8 9 12 14 15 20 24 36 36');
  final ms = TextEditingController(text: '1 1 1 1 0 1 1 0 1 1 0 0');
  final mg = TextEditingController(text: 'A A A A A A B B B B B B');
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    time ??= r.pick(r.roles.time, {VarType.numeric});
    status ??= r.pick(r.roles.status, {VarType.binary, VarType.categorical});
    if (status != null) event ??= r.roles.eventLevel;
    group ??= r.pick(r.roles.exposure, {VarType.binary, VarType.categorical});
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Survie : Kaplan-Meier et log-rank', 'Survival: Kaplan-Meier and log-rank'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Durée de suivi', 'Follow-up time'), time, _vars(ds, types: {VarType.numeric}), (v) => setState(() => time = v)),
          Pick<String>(tr('Statut', 'Status'), status, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                status = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              })),
          if (status != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => event = v)),
          Pick<String>(tr('Groupe (facultatif)', 'Group (optional)'), group, [('', tr('— aucun —', '— none —')), ..._vars(ds, types: {VarType.binary, VarType.categorical})],
              (v) => setState(() => group = (v == null || v.isEmpty) ? null : v)),
        ])
      else ...[
        TextField(controller: mt, decoration: InputDecoration(labelText: tr('Durées', 'Times'))),
        const SizedBox(height: 8),
        TextField(controller: ms, decoration: InputDecoration(labelText: tr('Statuts (1 = événement, 0 = censure), même ordre', 'Statuses (1 = event, 0 = censoring), same order'))),
        const SizedBox(height: 8),
        TextField(controller: mg, decoration: InputDecoration(labelText: tr('Groupes (facultatif), même ordre', 'Groups (optional), same order'))),
      ],
      const SizedBox(height: 10),
      NumField(tr('Horizon (facultatif)', 'Horizon (optional)'), horizon, width: 200, helper: tr('survie estimée à ce temps', 'survival estimated at this time')),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (time == null || status == null || event == null) throw StatInputError('missing', tr('Choisir durée, statut et modalité « événement ».', 'Choose time, status and event level.'));
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final t = ds.numeric(time!), st = ds.text(status!), g = group == null ? null : ds.text(group!);
            return survivalAnalysis([for (final i in keep) t[i]], [for (final i in keep) st[i]], event!,
                groupRaw: g == null ? null : [for (final i in keep) g[i]], horizon: readNum(horizon),
                timeUnit: ds.dictionary[time]!.unit, groupName: group ?? tr('Groupe', 'Group'));
          }
          final t = parseSeries(mt.text), s = [for (final v in parseSeries(ms.text)) v == null ? null : (v == 1 ? '1' : '0')];
          final gText = mg.text.trim().split(RegExp(r'[\s;]+')).where((x) => x.isNotEmpty).toList();
          if (s.length != t.length || (gText.isNotEmpty && gText.length != t.length)) {
            throw StatInputError('lengths', tr('Durées, statuts et groupes doivent avoir le même nombre de valeurs.', 'Times, statuses and groups must have the same number of values.'));
          }
          return survivalAnalysis(t, s, '1', groupRaw: gText.isEmpty ? null : gText, horizon: readNum(horizon));
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Risques concurrents

class CompetingRisksCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const CompetingRisksCalc(this.ds, this.onResult, {super.key});
  @override
  State<CompetingRisksCalc> createState() => _CompetingRisksCalcState();
}

class _CompetingRisksCalcState extends State<CompetingRisksCalc> {
  String? time, status, cause, censor, group;
  final horizon = TextEditingController();
  final mt = TextEditingController(text: '2 3 4 5 6 8 9 12 14 15 18 20 24 30 36 36');
  final ms = TextEditingController(text: '1 2 1 0 1 2 1 1 2 0 1 2 0 1 0 0');
  final mg = TextEditingController(text: 'A A A A A A A A B B B B B B B B');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Risques concurrents : incidence cumulée', 'Competing risks: cumulative incidence'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
          tr('Quand un autre événement (p. ex. le décès) peut empêcher l\'événement étudié, 1 − Kaplan-Meier surestime son incidence : l\'estimateur d\'Aalen-Johansen la mesure correctement.',
              'When another event (e.g. death) can prevent the studied event, 1 − Kaplan-Meier overestimates its incidence: the Aalen-Johansen estimator measures it correctly.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Durée de suivi', 'Follow-up time'), time, _vars(ds, types: {VarType.numeric}), (v) => setState(() => time = v)),
          Pick<String>(tr('Statut (événement, concurrent, censure)', 'Status (event, competing, censoring)'), status, _vars(ds, types: {VarType.binary, VarType.categorical}),
              (v) => setState(() {
                    status = v;
                    cause = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
                    censor = v == null ? null : (ds.levels(v).contains('0') ? '0' : null);
                  })),
          if (status != null) ...[
            Pick<String>(tr('Événement d\'intérêt', 'Event of interest'), cause, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => cause = v)),
            Pick<String>(tr('Modalité « censure »', 'Censoring level'), censor, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => censor = v)),
          ],
          Pick<String>(tr('Groupe (facultatif)', 'Group (optional)'), group, [('', tr('— aucun —', '— none —')), ..._vars(ds, types: {VarType.binary, VarType.categorical})],
              (v) => setState(() => group = (v == null || v.isEmpty) ? null : v)),
        ])
      else ...[
        TextField(controller: mt, decoration: InputDecoration(labelText: tr('Durées', 'Times'))),
        const SizedBox(height: 8),
        TextField(controller: ms, decoration: InputDecoration(labelText: tr('Statuts (1 = événement, 2 = concurrent, 0 = censure), même ordre', 'Statuses (1 = event, 2 = competing, 0 = censoring), same order'))),
        const SizedBox(height: 8),
        TextField(controller: mg, decoration: InputDecoration(labelText: tr('Groupes (facultatif), même ordre', 'Groups (optional), same order'))),
      ],
      const SizedBox(height: 10),
      NumField(tr('Horizon (facultatif)', 'Horizon (optional)'), horizon, width: 200, helper: tr('incidence estimée à ce temps', 'incidence estimated at this time')),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (time == null || status == null || cause == null || censor == null) {
              throw StatInputError('missing', tr('Choisir durée, statut, événement d\'intérêt et modalité de censure.', 'Choose time, status, event of interest and censoring level.'));
            }
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final t = ds.numeric(time!), st = ds.text(status!), g = group == null ? null : ds.text(group!);
            return competingRisksAnalysis([for (final i in keep) t[i]], [for (final i in keep) st[i]], cause!, {censor!},
                groupRaw: g == null ? null : [for (final i in keep) g[i]], horizon: readNum(horizon), timeUnit: ds.dictionary[time]!.unit, groupName: group ?? tr('Groupe', 'Group'));
          }
          final t = parseSeries(mt.text), s = [for (final v in parseSeries(ms.text)) v == null ? null : '${v.round()}'];
          final gText = mg.text.trim().split(RegExp(r'[\s;]+')).where((x) => x.isNotEmpty).toList();
          if (s.length != t.length || (gText.isNotEmpty && gText.length != t.length)) {
            throw StatInputError('lengths', tr('Durées, statuts et groupes doivent avoir le même nombre de valeurs.', 'Times, statuses and groups must have the same number of values.'));
          }
          return competingRisksAnalysis(t, s, '1', {'0'}, groupRaw: gText.isEmpty ? null : gText, horizon: readNum(horizon));
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- Puissance et effectif

/// Atelier de puissance : un plan d'étude, puis « calculer l'effectif » (pour une puissance visée) ou « calculer la
/// puissance » (pour un effectif donné) ; courbe de puissance dans le résultat.
class PowerCalc extends StatefulWidget {
  final OnResult onResult;
  final String? initial;
  const PowerCalc(this.onResult, {super.key, this.initial});
  @override
  State<PowerCalc> createState() => _PowerCalcState();
}

class _PowerCalcState extends State<PowerCalc> {
  late String plan = switch (widget.initial) {
    'power_proportions' => 'props',
    'power_case_control' => 'cc',
    'power_survival' => 'surv',
    'power_gwas' => 'gwas',
    _ => 'means',
  };
  MeansDesign design = MeansDesign.twoGroups;
  bool solveN = true;
  final delta = TextEditingController(text: '5'), sd = TextEditingController(text: '10'), ratio = TextEditingController(text: '1');
  final p1 = TextEditingController(text: '0,30'), p2 = TextEditingController(text: '0,18');
  final or = TextEditingController(text: '2'), p0 = TextEditingController(text: '0,20');
  final hr = TextEditingController(text: '0,7'), pC = TextEditingController(text: '0,45');
  final maf = TextEditingController(text: '0,25'), orG = TextEditingController(text: '1,2');
  final alpha = TextEditingController(text: '0,05'), alphaG = TextEditingController(text: '5e-8'), power = TextEditingController(text: '0,8');
  final n = TextEditingController(text: '100');

  String get nLabel => switch (plan) {
        'means' => design == MeansDesign.twoGroups ? tr('n du groupe 1', 'n of group 1') : (design == MeansDesign.paired ? tr('Nombre de paires', 'Number of pairs') : tr('n', 'n')),
        'props' => tr('n par groupe', 'n per group'),
        'surv' => tr('n du bras contrôle', 'n of the control arm'),
        _ => tr('Nombre de cas', 'Number of cases'),
      };

  @override
  Widget build(BuildContext context) {
    final ratioLabel = switch (plan) {
      'cc' || 'gwas' => tr('Témoins par cas', 'Controls per case'),
      'surv' => tr('Ratio expérimental / contrôle', 'Experimental / control ratio'),
      _ => tr('Ratio n2 / n1', 'Ratio n2 / n1'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Puissance et effectif', 'Power and sample size'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(tr('Plan d\'étude', 'Study design'), plan, [
          ('means', tr('Comparer des moyennes', 'Compare means')),
          ('props', tr('Comparer deux proportions', 'Compare two proportions')),
          ('cc', tr('Étude cas-témoins (OR)', 'Case-control study (OR)')),
          ('surv', tr('Survie : essai à deux bras (HR)', 'Survival: two-arm trial (HR)')),
          ('gwas', tr('Étude pangénomique (GWAS)', 'Genome-wide association study (GWAS)')),
        ], (v) => setState(() => plan = v ?? plan), width: 300),
        Pick<bool>(tr('Objectif', 'Goal'), solveN, [(true, tr('l\'effectif nécessaire', 'the required sample size')), (false, tr('la puissance pour un effectif', 'the power for a sample size'))],
            (v) => setState(() => solveN = v ?? true), width: 280),
        if (plan == 'means')
          Pick<MeansDesign>(tr('Plan', 'Design'), design, [
            (MeansDesign.twoGroups, tr('Deux groupes indépendants', 'Two independent groups')),
            (MeansDesign.paired, tr('Mesures appariées', 'Paired measurements')),
            (MeansDesign.oneSample, tr('Un groupe contre une valeur', 'One group against a value')),
          ], (v) => setState(() => design = v ?? design), width: 280),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (plan == 'means') ...[
          NumField(design == MeansDesign.paired ? tr('Différence moyenne', 'Mean difference') : tr('Différence à détecter', 'Difference to detect'), delta, width: 200),
          NumField(design == MeansDesign.paired ? tr('ÉT des différences', 'SD of the differences') : tr('Écart-type', 'Standard deviation'), sd, width: 200),
        ],
        if (plan == 'props') ...[NumField(tr('p1 attendue', 'expected p1'), p1), NumField(tr('p2 attendue', 'expected p2'), p2)],
        if (plan == 'cc') ...[NumField(tr('OR à détecter', 'OR to detect'), or), NumField(tr('Exposition chez les témoins', 'Exposure in controls'), p0, width: 220)],
        if (plan == 'surv') ...[NumField(tr('HR à détecter', 'HR to detect'), hr), NumField(tr('Événements en contrôle (proportion)', 'Events in control (proportion)'), pC, width: 240)],
        if (plan == 'gwas') ...[NumField(tr('Fréquence allélique (témoins)', 'Allele frequency (controls)'), maf, width: 220), NumField(tr('OR par allèle', 'Per-allele OR'), orG)],
        if ((plan == 'means' && design == MeansDesign.twoGroups) || plan == 'cc' || plan == 'surv' || plan == 'gwas') NumField(ratioLabel, ratio, width: 220),
        NumField(tr('α (bilatéral)', 'α (two-sided)'), plan == 'gwas' ? alphaG : alpha),
        if (solveN) NumField(tr('Puissance visée', 'Target power'), power) else NumField(nLabel, n, width: 200),
      ]),
      _computeButton(context, () {
        run(context, () {
          final a = readNum(plan == 'gwas' ? alphaG : alpha) ?? (plan == 'gwas' ? 5e-8 : 0.05), pw = readNum(power) ?? 0.8, k = readNum(ratio) ?? 1;
          final nn = solveN ? null : readNum(n);
          if (!solveN && (nn == null || nn < 2)) throw StatInputError('missing', tr('Indiquer un effectif ≥ 2.', 'Enter a sample size ≥ 2.'));
          return switch (plan) {
            'props' => powerProportions(p1: readNum(p1) ?? 0, p2: readNum(p2) ?? 0, alpha: a, power: pw, n: nn),
            'cc' => powerCaseControl(or: readNum(or) ?? 0, p0: readNum(p0) ?? 0, ratio: k, alpha: a, power: pw, nCases: nn),
            'surv' => powerSurvival(hr: readNum(hr) ?? 0, pC: readNum(pC) ?? 0, ratio: k, alpha: a, power: pw, nControl: nn),
            'gwas' => powerGwas(maf: readNum(maf) ?? 0, or: readNum(orG) ?? 0, ratio: k, alpha: a, power: pw, nCases: nn),
            _ => powerMeans(delta: readNum(delta) ?? 0, sd: readNum(sd) ?? 0, design: design, ratio: design == MeansDesign.twoGroups ? k : 1, alpha: a, power: pw, n: nn),
          };
        }, widget.onResult);
      }),
    ]);
  }
}

// ---------------------------------------------------------------- RMST et landmark

class RmstCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const RmstCalc(this.ds, this.onResult, {super.key});
  @override
  State<RmstCalc> createState() => _RmstCalcState();
}

class _RmstCalcState extends State<RmstCalc> {
  String? time, status, event, group;
  final tau = TextEditingController();
  final mt = TextEditingController(text: '3 5 6 8 9 12 14 15 20 24 36 36 4 7 10 13 18 22 26 30 36 36 36 36');
  final ms = TextEditingController(text: '1 1 1 1 0 1 1 0 1 1 0 0 1 0 1 1 0 1 1 0 0 0 0 0');
  final mg = TextEditingController(text: 'A A A A A A A A A A A A B B B B B B B B B B B B');
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    time ??= r.pick(r.roles.time, {VarType.numeric});
    status ??= r.pick(r.roles.status, {VarType.binary, VarType.categorical});
    if (status != null) event ??= r.roles.eventLevel;
    group ??= r.pick(r.roles.exposure, {VarType.binary, VarType.categorical});
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Temps moyen de survie restreint (RMST)', 'Restricted mean survival time (RMST)'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Aire sous la courbe de Kaplan-Meier jusqu\'à un horizon τ : le temps moyen vécu sans événement ; utile quand les risques ne sont pas proportionnels.',
              'Area under the Kaplan-Meier curve up to a horizon τ: the mean time lived without the event; useful when hazards are not proportional.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Durée de suivi', 'Follow-up time'), time, _vars(ds, types: {VarType.numeric}), (v) => setState(() => time = v)),
          Pick<String>(tr('Statut', 'Status'), status, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                status = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              })),
          if (status != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => event = v)),
          Pick<String>(tr('Groupe (facultatif)', 'Group (optional)'), group, [('', tr('— aucun —', '— none —')), ..._vars(ds, types: {VarType.binary, VarType.categorical})],
              (v) => setState(() => group = (v == null || v.isEmpty) ? null : v)),
        ])
      else ...[
        TextField(controller: mt, decoration: InputDecoration(labelText: tr('Durées', 'Times'))),
        const SizedBox(height: 8),
        TextField(controller: ms, decoration: InputDecoration(labelText: tr('Statuts (1 = événement, 0 = censure), même ordre', 'Statuses (1 = event, 0 = censoring), same order'))),
        const SizedBox(height: 8),
        TextField(controller: mg, decoration: InputDecoration(labelText: tr('Groupes (facultatif), même ordre', 'Groups (optional), same order'))),
      ],
      const SizedBox(height: 10),
      NumField(tr('Horizon τ (facultatif)', 'Horizon τ (optional)'), tau, width: 220, helper: tr('par défaut : suivi du groupe le plus court', 'default: follow-up of the shortest group')),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (time == null || status == null || event == null) throw StatInputError('missing', tr('Choisir durée, statut et modalité « événement ».', 'Choose time, status and event level.'));
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final t = ds.numeric(time!), st = ds.text(status!), g = group == null ? null : ds.text(group!);
            return rmstAnalysis([for (final i in keep) t[i]], [for (final i in keep) st[i]], event!,
                groupRaw: g == null ? null : [for (final i in keep) g[i]], tau: readNum(tau), timeUnit: ds.dictionary[time]!.unit, groupName: group ?? tr('Groupe', 'Group'));
          }
          final t = parseSeries(mt.text), s = [for (final v in parseSeries(ms.text)) v == null ? null : (v == 1 ? '1' : '0')];
          final gText = mg.text.trim().split(RegExp(r'[\s;]+')).where((x) => x.isNotEmpty).toList();
          if (s.length != t.length || (gText.isNotEmpty && gText.length != t.length)) {
            throw StatInputError('lengths', tr('Durées, statuts et groupes doivent avoir le même nombre de valeurs.', 'Times, statuses and groups must have the same number of values.'));
          }
          return rmstAnalysis(t, s, '1', groupRaw: gText.isEmpty ? null : gText, tau: readNum(tau));
        }, widget.onResult);
      }),
    ]);
  }
}

class LandmarkCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const LandmarkCalc(this.ds, this.onResult, {super.key});
  @override
  State<LandmarkCalc> createState() => _LandmarkCalcState();
}

class _LandmarkCalcState extends State<LandmarkCalc> {
  String? time, status, event, switchCol;
  final landmark = TextEditingController(text: '30');
  final adjust = <String>{};
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Analyse landmark', 'Landmark analysis'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Compare, à partir d\'une date repère L, les sujets déjà exposés (greffe, traitement) aux autres, sans biais du temps immortel.',
              'Compares, from a landmark date L, subjects already exposed (transplant, treatment) with the others, without immortal time bias.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds == null)
        Text(tr('L\'analyse landmark travaille sur un jeu de données individuelles (étape 4 d\'un projet).', 'The landmark analysis works on an individual dataset (step 4 of a project).'))
      else ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Durée de suivi', 'Follow-up time'), time, _vars(ds, types: {VarType.numeric}), (v) => setState(() => time = v)),
          Pick<String>(tr('Statut', 'Status'), status, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                status = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              })),
          if (status != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(status!)) (l, l)], (v) => setState(() => event = v)),
          Pick<String>(tr('Temps de survenue de l\'exposition', 'Time of exposure onset'), switchCol, _vars(ds, types: {VarType.numeric}), (v) => setState(() => switchCol = v), width: 300),
          NumField(tr('Landmark L', 'Landmark L'), landmark, width: 160),
        ]),
        const SizedBox(height: 8),
        Text(tr('Ajustement (facultatif)', 'Adjustment (optional)'), style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 6, children: [
          for (final n in ds.names)
            if (n != time && n != status && n != switchCol && ds.dictionary[n]!.type == VarType.numeric)
              FilterChip(label: Text(n), selected: adjust.contains(n), onSelected: (s) => setState(() => s ? adjust.add(n) : adjust.remove(n))),
        ]),
        _computeButton(context, () {
          run(context, () {
            if (time == null || status == null || event == null || switchCol == null) {
              throw StatInputError('missing', tr('Choisir durée, statut, modalité « événement » et temps de survenue de l\'exposition.', 'Choose time, status, event level and time of exposure onset.'));
            }
            final l = readNum(landmark);
            if (l == null || l <= 0) throw StatInputError('landmark', tr('Indiquer un landmark L > 0.', 'Enter a landmark L > 0.'));
            return landmarkAnalysis(ds, time: time!, status: status!, eventLevel: event!, switchTime: switchCol!, landmark: l, terms: [for (final n in adjust) TermSpec(n)]);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}


// ---------------------------------------------------------------- Comparaison de méthodes

class MethodComparisonCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const MethodComparisonCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<MethodComparisonCalc> createState() => _MethodComparisonCalcState();
}

class _MethodComparisonCalcState extends State<MethodComparisonCalc> {
  late MethodComparisonKind kind = widget.initial == 'deming' ? MethodComparisonKind.deming : MethodComparisonKind.passingBablok;
  String? a, b;
  final sa = TextEditingController(text: '0,62 0,71 0,80 0,85 0,93 1,02 1,10 1,18 1,25 1,37 1,48 1,60 1,75 1,90 2,10 2,35 2,60 2,95 3,30 3,80 4,40 5,10'),
      sb = TextEditingController(text: '0,60 0,74 0,78 0,90 0,95 1,08 1,12 1,25 1,30 1,45 1,55 1,70 1,86 2,00 2,24 2,50 2,79 3,12 3,55 4,05 4,70 5,52');
  final ratio = TextEditingController(text: '1'), levels = TextEditingController(text: '1 2');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Comparaison de deux méthodes de mesure', 'Comparison of two measurement methods'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(tr('Régression de Passing-Bablok (non paramétrique) ou de Deming (erreurs sur les deux méthodes) : biais constant (ordonnée) et proportionnel (pente), en complément de Bland-Altman.',
                'Passing-Bablok (nonparametric) or Deming (errors on both methods) regression: constant (intercept) and proportional (slope) bias, alongside Bland-Altman.'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<MethodComparisonKind>(segments: const [
          ButtonSegment(value: MethodComparisonKind.passingBablok, label: Text('Passing-Bablok')),
          ButtonSegment(value: MethodComparisonKind.deming, label: Text('Deming')),
        ], selected: {kind}, onSelectionChanged: (s) => setState(() => kind = s.first)),
        const SizedBox(height: 10),
        _TwoColumns(widget.ds, a, b, (v) => setState(() => a = v), (v) => setState(() => b = v), sa, sb, la: tr('Méthode de référence (x)', 'Reference method (x)'), lb: tr('Méthode évaluée (y)', 'Test method (y)')),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (kind == MethodComparisonKind.deming)
            NumField(tr('Rapport des variances d\'erreur σ²(x)/σ²(y)', 'Error variance ratio σ²(x)/σ²(y)'), ratio, width: 280, helper: tr('1 si répétabilités égales', '1 if equal repeatabilities')),
          SizedBox(
              width: 280,
              child: TextField(controller: levels, decoration: InputDecoration(labelText: tr('Niveaux de décision (facultatif)', 'Decision levels (optional)'), helperText: tr('séparés par des espaces', 'separated by spaces')))),
        ]),
        _computeButton(context, () {
          run(context, () {
            final c = _cols(widget.ds, a, b, sa, sb);
            final unit = widget.ds != null && a != null ? widget.ds!.dictionary[a]!.unit : '';
            return methodComparison(c.x, c.y,
                kind: kind,
                errorRatio: readNum(ratio) ?? 1,
                decisionLevels: [for (final v in parseSeries(levels.text)) ?v],
                xName: a ?? tr('Méthode de référence', 'Reference method'),
                yName: b ?? tr('Méthode évaluée', 'Test method'),
                unit: unit);
          }, widget.onResult);
        }),
      ]);
}

// ---------------------------------------------------------------- Calibration

class CalibrationCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const CalibrationCalc(this.ds, this.onResult, {super.key});
  @override
  State<CalibrationCalc> createState() => _CalibrationCalcState();
}

class _CalibrationCalcState extends State<CalibrationCalc> {
  String? pred, outcome, event;
  final groups = TextEditingController(text: '10');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Calibration d\'un modèle de risque', 'Calibration of a risk model'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Les risques prédits correspondent-ils aux fréquences observées ? Courbe lissée et par déciles, pente et intercept de calibration, Hosmer-Lemeshow, Spiegelhalter, Brier.',
              'Do predicted risks match observed frequencies? Smoothed and decile curves, calibration slope and intercept, Hosmer-Lemeshow, Spiegelhalter, Brier.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds == null)
        Text(tr('La calibration travaille sur un jeu de données contenant une colonne de risques prédits (entre 0 et 1) et l\'issue observée (étape 4 d\'un projet).',
            'Calibration works on a dataset with a column of predicted risks (between 0 and 1) and the observed outcome (step 4 of a project).'))
      else ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Risque prédit (0 à 1)', 'Predicted risk (0 to 1)'), pred, _vars(ds, types: {VarType.numeric}), (v) => setState(() => pred = v)),
          Pick<String>(tr('Issue observée', 'Observed outcome'), outcome, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                outcome = v;
                event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
              })),
          if (outcome != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(outcome!)) (l, l)], (v) => setState(() => event = v)),
          NumField(tr('Groupes (Hosmer-Lemeshow)', 'Groups (Hosmer-Lemeshow)'), groups, width: 200),
        ]),
        _computeButton(context, () {
          run(context, () {
            if (pred == null || outcome == null || event == null) throw StatInputError('missing', tr('Choisir le risque prédit, l\'issue et la modalité « événement ».', 'Choose the predicted risk, the outcome and the event level.'));
            final excl = ds.excludedRows;
            final p = ds.numeric(pred!), y = ds.text(outcome!);
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            return calibrationAssessment([for (final i in keep) p[i]], [for (final i in keep) y[i] == null ? null : (y[i] == event ? 1.0 : 0.0)],
                groups: (readNum(groups) ?? 10).round().clamp(3, 20), predictedName: pred);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- Score de propension

class PropensityCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const PropensityCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<PropensityCalc> createState() => _PropensityCalcState();
}

class _PropensityCalcState extends State<PropensityCalc> {
  String? treatment, treated, outcome, event;
  late PropensityMethod method = widget.initial == 'propensity_weighting' ? PropensityMethod.iptwAte : PropensityMethod.matching;
  List<TermSpec> covariates = [];
  final caliper = TextEditingController(text: '0,2');
  bool _prefilled = false;

  /// Préremplissage par les rôles des variables du projet (étape 5), une seule fois.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final r = VariableRolesScope.maybeOf(context);
    if (r == null) return;
    treatment ??= r.pick(r.roles.exposure, {VarType.binary, VarType.categorical});
    final ds = widget.ds;
    if (treatment != null && ds != null) treated ??= ds.levels(treatment!).contains('oui') ? 'oui' : (ds.levels(treatment!).contains('1') ? '1' : null);
    outcome ??= r.pick(r.roles.outcome, {VarType.numeric, VarType.binary, VarType.categorical});
    if (outcome != null) event ??= r.roles.eventLevel;
    if (covariates.isEmpty) covariates = r.terms(exclude: {?treatment, ?outcome});
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    final binaryOutcome = ds != null && outcome != null && ds.dictionary[outcome]!.type != VarType.numeric;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Score de propension', 'Propensity score'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Étude observationnelle : comparer traités et non-traités à caractéristiques mesurées comparables, par appariement ou pondération, et vérifier l\'équilibre obtenu.',
              'Observational study: compare treated and untreated at comparable measured characteristics, by matching or weighting, and check the balance achieved.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds == null)
        Text(tr('Le score de propension travaille sur un jeu de données individuelles (étape 4 d\'un projet).', 'The propensity score works on an individual dataset (step 4 of a project).'))
      else ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Traitement (exposition)', 'Treatment (exposure)'), treatment, _vars(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                treatment = v;
                treated = v == null ? null : (ds.levels(v).contains('oui') ? 'oui' : ds.levels(v).contains('1') ? '1' : null);
                covariates = [for (final c in covariates) if (c.variable != v) c];
              })),
          if (treatment != null) Pick<String>(tr('Modalité « traité »', 'Treated level'), treated, [for (final l in ds.levels(treatment!)) (l, l)], (v) => setState(() => treated = v)),
          Pick<String>(tr('Issue (facultatif)', 'Outcome (optional)'), outcome, [('', tr('— aucune —', '— none —')), ..._vars(ds, types: {VarType.numeric, VarType.binary, VarType.categorical})],
              (v) => setState(() {
                    outcome = (v == null || v.isEmpty) ? null : v;
                    event = outcome == null ? null : (ds.levels(outcome!).contains('1') ? '1' : ds.levels(outcome!).contains('oui') ? 'oui' : null);
                    covariates = [for (final c in covariates) if (c.variable != outcome) c];
                  })),
          if (binaryOutcome) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(outcome!)) (l, l)], (v) => setState(() => event = v)),
        ]),
        const SizedBox(height: 8),
        PredictorEditor(ds, covariates, (l) => setState(() => covariates = l), exclude: {?treatment, ?outcome}, title: tr('Covariables de confusion (choisies a priori)', 'Confounding covariates (chosen a priori)')),
        const SizedBox(height: 8),
        SegmentedButton<PropensityMethod>(segments: [
          ButtonSegment(value: PropensityMethod.matching, label: Text(tr('Appariement 1:1', '1:1 matching'))),
          const ButtonSegment(value: PropensityMethod.iptwAte, label: Text('IPTW (ATE)')),
          ButtonSegment(value: PropensityMethod.iptwAtt, label: Text(tr('Pondération (ATT)', 'Weighting (ATT)'))),
        ], selected: {method}, onSelectionChanged: (s) => setState(() => method = s.first)),
        if (method == PropensityMethod.matching) ...[
          const SizedBox(height: 10),
          NumField(tr('Caliper (ÉT du score)', 'Caliper (SD of score)'), caliper, width: 220, helper: tr('vide : sans caliper', 'empty: no caliper')),
        ],
        _computeButton(context, () {
          run(context, () {
            if (treatment == null || treated == null) throw StatInputError('missing', tr('Choisir le traitement et la modalité « traité ».', 'Choose the treatment and the treated level.'));
            if (binaryOutcome && event == null) throw StatInputError('missing', tr('Choisir la modalité « événement » de l\'issue.', 'Choose the event level of the outcome.'));
            return propensityAnalysis(ds,
                treatment: treatment!,
                treatedLevel: treated!,
                covariates: covariates,
                outcome: outcome,
                outcomeEvent: binaryOutcome ? event : null,
                method: method,
                caliper: method == PropensityMethod.matching ? readNum(caliper) : null);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}


// ---------------------------------------------------------------- Laboratoire : intervalle de référence, fidélité

class ReferenceIntervalCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const ReferenceIntervalCalc(this.ds, this.onResult, {super.key});
  @override
  State<ReferenceIntervalCalc> createState() => _ReferenceIntervalCalcState();
}

class _ReferenceIntervalCalcState extends State<ReferenceIntervalCalc> {
  String? variable, group;
  ReferenceMethod method = ReferenceMethod.nonparametric;
  bool remove = false;
  final manual = TextEditingController(
      text: '62 71 68 75 80 66 59 73 77 70 64 82 69 74 61 79 72 67 76 65 70 58 84 71 69 73 66 78 63 75 68 72 81 60 74 70 67 77 69 71');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Intervalle de référence (CLSI EP28)', 'Reference interval (CLSI EP28)'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Bornes à 2,5 % et 97,5 % des sujets de référence, avec l\'incertitude des bornes ; valeurs aberrantes (Horn) et partition par sous-groupe (Harris et Boyd).',
              '2.5% and 97.5% limits of the reference subjects, with the uncertainty of the limits; outliers (Horn) and partition by subgroup (Harris and Boyd).'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      SegmentedButton<ReferenceMethod>(segments: [
        ButtonSegment(value: ReferenceMethod.nonparametric, label: Text(tr('Non paramétrique', 'Nonparametric'))),
        ButtonSegment(value: ReferenceMethod.robust, label: Text(tr('Robuste', 'Robust'))),
        ButtonSegment(value: ReferenceMethod.parametric, label: Text(tr('Paramétrique', 'Parametric'))),
      ], selected: {method}, onSelectionChanged: (s) => setState(() => method = s.first)),
      const SizedBox(height: 10),
      if (ds != null)
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Analyte', 'Analyte'), variable, _vars(ds, types: {VarType.numeric}), (v) => setState(() => variable = v)),
          Pick<String>(tr('Sous-groupe (facultatif)', 'Subgroup (optional)'), group, [('', tr('— aucun —', '— none —')), ..._vars(ds, types: {VarType.binary, VarType.categorical})],
              (v) => setState(() => group = (v == null || v.isEmpty) ? null : v)),
        ])
      else
        TextField(controller: manual, maxLines: 3, decoration: InputDecoration(labelText: tr('Valeurs des sujets de référence', 'Values of the reference subjects'))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: remove, onChanged: (v) => setState(() => remove = v),
          title: Text(tr('Retirer les valeurs aberrantes (Horn)', 'Remove outliers (Horn)'))),
      _computeButton(context, () {
        run(context, () {
          if (ds != null) {
            if (variable == null) throw StatInputError('missing', tr('Choisir l\'analyte.', 'Choose the analyte.'));
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final x = ds.numeric(variable!), g = group == null ? null : ds.text(group!);
            return referenceInterval([for (final i in keep) x[i]],
                method: method, removeOutliers: remove, groups: g == null ? null : [for (final i in keep) g[i]], groupName: group, variable: variable!, unit: ds.dictionary[variable]!.unit);
          }
          return referenceInterval(parseSeries(manual.text), method: method, removeOutliers: remove);
        }, widget.onResult);
      }),
    ]);
  }
}

class PrecisionCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const PrecisionCalc(this.ds, this.onResult, {super.key});
  @override
  State<PrecisionCalc> createState() => _PrecisionCalcState();
}

class _PrecisionCalcState extends State<PrecisionCalc> {
  String? value, day, runCol;
  final claimR = TextEditingController(), claimWl = TextEditingController(), levels = TextEditingController(text: '1');
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Fidélité d\'une méthode (CLSI EP05, EP15)', 'Method precision (CLSI EP05, EP15)'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Répétabilité, variabilité entre séries et entre jours, fidélité intermédiaire, avec IC ; vérification d\'une fidélité annoncée par le fabricant.',
              'Repeatability, between-run and between-day variability, within-laboratory precision, with CIs; verification of a precision claimed by the manufacturer.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds == null)
        Text(tr('La fidélité travaille sur un jeu de données (une ligne par mesure : valeur, jour, série facultative ; étape 4 d\'un projet).', 'Precision works on a dataset (one row per measurement: value, day, optional run; step 4 of a project).'))
      else ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Valeur mesurée', 'Measured value'), value, _vars(ds, types: {VarType.numeric}), (v) => setState(() => value = v)),
          Pick<String>(tr('Jour', 'Day'), day, _vars(ds), (v) => setState(() => day = v)),
          Pick<String>(tr('Série (facultatif)', 'Run (optional)'), runCol, [('', tr('— aucune —', '— none —')), ..._vars(ds)], (v) => setState(() => runCol = (v == null || v.isEmpty) ? null : v)),
          NumField(tr('ÉT de répétabilité annoncé', 'Claimed repeatability SD'), claimR, width: 240, helper: tr('facultatif (EP15)', 'optional (EP15)')),
          NumField(tr('ÉT intralaboratoire annoncé', 'Claimed within-lab SD'), claimWl, width: 240, helper: tr('facultatif (EP15)', 'optional (EP15)')),
          NumField(tr('Niveaux testés', 'Levels tested'), levels, width: 160),
        ]),
        _computeButton(context, () {
          run(context, () {
            if (value == null || day == null) throw StatInputError('missing', tr('Choisir la valeur et le jour.', 'Choose the value and the day.'));
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final y = ds.numeric(value!), d = ds.text(day!), r = runCol == null ? null : ds.text(runCol!);
            return precisionAnalysis([for (final i in keep) y[i]], [for (final i in keep) d[i]],
                runRaw: r == null ? null : [for (final i in keep) r[i]],
                claimRepeatability: readNum(claimR), claimWithinLab: readNum(claimWl), levels: (readNum(levels) ?? 1).round().clamp(1, 10), unit: ds.dictionary[value]!.unit);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}


// ---------------------------------------------------------------- Équivalence, valeur E, série interrompue

class EquivalenceCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const EquivalenceCalc(this.ds, this.onResult, {super.key, this.initial});
  @override
  State<EquivalenceCalc> createState() => _EquivalenceCalcState();
}

class _EquivalenceCalcState extends State<EquivalenceCalc> {
  late bool proportions = widget.initial == 'equivalence_proportions';
  late EquivalenceHypothesis hyp = widget.initial == 'non_inferiority' ? EquivalenceHypothesis.nonInferiorityHigherBetter : EquivalenceHypothesis.equivalence;
  bool paired = false;
  String? a, b;
  final sa = TextEditingController(text: '131 128 140 135 122 138 129 133 127 136 142 125 130 134 139 126'),
      sb = TextEditingController(text: '133 127 138 136 124 135 131 130 129 137 140 128 132 131 136 127');
  final low = TextEditingController(text: '-5'), high = TextEditingController(text: '5'), margin = TextEditingController(text: '4');
  final x1 = TextEditingController(text: '93'), n1 = TextEditingController(text: '150'), x2 = TextEditingController(text: '81'), n2 = TextEditingController(text: '140');
  final pLow = TextEditingController(text: '-0,10'), pHigh = TextEditingController(text: '0,10');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Équivalence et non-infériorité', 'Equivalence and non-inferiority'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(tr('Montrer qu\'une différence est cliniquement négligeable (marges fixées a priori) : un test classique non significatif ne le prouve pas.',
                'Show that a difference is clinically negligible (margins set a priori): a non-significant classical test does not prove it.'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(segments: [
          ButtonSegment(value: false, label: Text(tr('Moyennes', 'Means'))),
          ButtonSegment(value: true, label: Text(tr('Proportions', 'Proportions'))),
        ], selected: {proportions}, onSelectionChanged: (s) => setState(() => proportions = s.first)),
        const SizedBox(height: 10),
        if (proportions) ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            NumField(tr('Événements A', 'Events A'), x1), NumField(tr('Effectif A', 'Size A'), n1),
            NumField(tr('Événements B', 'Events B'), x2), NumField(tr('Effectif B', 'Size B'), n2),
            NumField(tr('Marge inférieure', 'Lower margin'), pLow), NumField(tr('Marge supérieure', 'Upper margin'), pHigh),
          ]),
        ] else ...[
          SegmentedButton<EquivalenceHypothesis>(segments: [
            ButtonSegment(value: EquivalenceHypothesis.equivalence, label: Text(tr('Équivalence', 'Equivalence'))),
            ButtonSegment(value: EquivalenceHypothesis.nonInferiorityHigherBetter, label: Text(tr('Non-inf. (↑ meilleur)', 'Non-inf. (↑ better)'))),
            ButtonSegment(value: EquivalenceHypothesis.nonInferiorityLowerBetter, label: Text(tr('Non-inf. (↓ meilleur)', 'Non-inf. (↓ better)'))),
          ], selected: {hyp}, onSelectionChanged: (s) => setState(() => hyp = s.first)),
          const SizedBox(height: 10),
          _TwoColumns(widget.ds, a, b, (v) => setState(() => a = v), (v) => setState(() => b = v), sa, sb, la: tr('Groupe A (nouveau)', 'Group A (new)'), lb: tr('Groupe B (référence)', 'Group B (reference)')),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: paired, onChanged: (v) => setState(() => paired = v), title: Text(tr('Mesures appariées', 'Paired measurements'))),
          Wrap(spacing: 12, runSpacing: 12, children: [
            if (hyp == EquivalenceHypothesis.equivalence) ...[
              NumField(tr('Marge inférieure', 'Lower margin'), low), NumField(tr('Marge supérieure', 'Upper margin'), high),
            ] else
              NumField(tr('Marge de non-infériorité', 'Non-inferiority margin'), margin, width: 240),
          ]),
        ],
        _computeButton(context, () {
          run(context, () {
            if (proportions) {
              final xa = readNum(x1), na = readNum(n1), xb = readNum(x2), nb = readNum(n2), lo = readNum(pLow), hi = readNum(pHigh);
              if ([xa, na, xb, nb, lo, hi].contains(null)) throw StatInputError('missing', tr('Renseigner les effectifs et les marges.', 'Fill in the counts and margins.'));
              return equivalenceProportions(xa!.round(), na!.round(), xb!.round(), nb!.round(), low: lo!, high: hi!);
            }
            final c = _cols(widget.ds, a, b, sa, sb);
            return equivalenceMeans(c.x, c.y,
                paired: paired, hypothesis: hyp, low: readNum(low), high: readNum(high), margin: readNum(margin), xName: a ?? 'A', yName: b ?? 'B', unit: widget.ds != null && a != null ? widget.ds!.dictionary[a]!.unit : '');
          }, widget.onResult);
        }),
      ]);
}

class EValueCalc extends StatefulWidget {
  final OnResult onResult;
  const EValueCalc(this.onResult, {super.key});
  @override
  State<EValueCalc> createState() => _EValueCalcState();
}

class _EValueCalcState extends State<EValueCalc> {
  EValueScale scale = EValueScale.riskRatio;
  final est = TextEditingController(text: '1,8'), lo = TextEditingController(text: '1,3'), hi = TextEditingController(text: '2,5'), se = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final smd = scale == EValueScale.standardizedMeanDifference;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Valeur E (confusion non mesurée)', 'E-value (unmeasured confounding)'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Force minimale qu\'un facteur de confusion non mesuré devrait avoir (avec le traitement et l\'issue) pour annuler l\'association observée.',
              'Minimum strength an unmeasured confounder would need (with both treatment and outcome) to explain away the observed association.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Pick<EValueScale>(tr('Mesure d\'association', 'Association measure'), scale, [
        (EValueScale.riskRatio, tr('Risque relatif (RR)', 'Risk ratio (RR)')),
        (EValueScale.oddsRatioRare, tr('Odds ratio, issue rare (< 15 %)', 'Odds ratio, rare outcome (< 15%)')),
        (EValueScale.oddsRatioCommon, tr('Odds ratio, issue fréquente', 'Odds ratio, common outcome')),
        (EValueScale.hazardRatioRare, tr('Hazard ratio, issue rare', 'Hazard ratio, rare outcome')),
        (EValueScale.hazardRatioCommon, tr('Hazard ratio, issue fréquente', 'Hazard ratio, common outcome')),
        (EValueScale.standardizedMeanDifference, tr('Différence standardisée (d)', 'Standardized difference (d)')),
      ], (v) => setState(() => scale = v ?? EValueScale.riskRatio), width: 320),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        NumField(tr('Estimation', 'Estimate'), est),
        if (smd) NumField(tr('Erreur type', 'Standard error'), se) else ...[
          NumField(tr('IC : borne inférieure', 'CI: lower bound'), lo),
          NumField(tr('IC : borne supérieure', 'CI: upper bound'), hi),
        ],
      ]),
      _computeButton(context, () {
        run(context, () {
          final e = readNum(est);
          if (e == null) throw StatInputError('missing', tr('Indiquer l\'estimation.', 'Enter the estimate.'));
          return smd ? eValue(e, se: readNum(se), scale: scale) : eValue(e, lower: readNum(lo), upper: readNum(hi), scale: scale);
        }, widget.onResult);
      }),
    ]);
  }
}

class InterruptedSeriesCalc extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const InterruptedSeriesCalc(this.ds, this.onResult, {super.key});
  @override
  State<InterruptedSeriesCalc> createState() => _InterruptedSeriesCalcState();
}

class _InterruptedSeriesCalcState extends State<InterruptedSeriesCalc> {
  String? time, outcome, pop;
  SeriesFamily family = SeriesFamily.gaussian;
  final t0 = TextEditingController(), lag = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Série chronologique interrompue', 'Interrupted time series'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Une intervention a-t-elle changé le niveau ou la tendance d\'un indicateur suivi dans le temps ? Comparaison à la tendance antérieure prolongée.',
              'Did an intervention change the level or trend of an indicator followed over time? Comparison with the extended prior trend.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (ds == null)
        Text(tr('La série interrompue travaille sur un jeu de données (une ligne par période : temps, indicateur ; étape 4 d\'un projet).', 'The interrupted series works on a dataset (one row per period: time, indicator; step 4 of a project).'))
      else ...[
        SegmentedButton<SeriesFamily>(segments: [
          ButtonSegment(value: SeriesFamily.gaussian, label: Text(tr('Indicateur continu', 'Continuous indicator'))),
          ButtonSegment(value: SeriesFamily.poisson, label: Text(tr('Comptages', 'Counts'))),
        ], selected: {family}, onSelectionChanged: (s) => setState(() => family = s.first)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Temps (période)', 'Time (period)'), time, _vars(ds, types: {VarType.numeric}), (v) => setState(() => time = v)),
          Pick<String>(tr('Indicateur', 'Indicator'), outcome, _vars(ds, types: {VarType.numeric}), (v) => setState(() => outcome = v)),
          if (family == SeriesFamily.poisson)
            Pick<String>(tr('Population (facultatif)', 'Population (optional)'), pop, [('', tr('— aucune —', '— none —')), ..._vars(ds, types: {VarType.numeric})], (v) => setState(() => pop = (v == null || v.isEmpty) ? null : v)),
          NumField(tr('Début de l\'intervention (temps)', 'Intervention start (time)'), t0, width: 240),
          if (family == SeriesFamily.gaussian) NumField(tr('Retard de Newey-West', 'Newey-West lag'), lag, width: 200, helper: tr('vide : automatique', 'empty: automatic')),
        ]),
        _computeButton(context, () {
          run(context, () {
            final start = readNum(t0);
            if (time == null || outcome == null || start == null) throw StatInputError('missing', tr('Choisir le temps, l\'indicateur et le début de l\'intervention.', 'Choose the time, the indicator and the intervention start.'));
            final excl = ds.excludedRows;
            final keep = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i)) i];
            final tt = ds.numeric(time!), yy = ds.numeric(outcome!), pp = pop == null ? null : ds.numeric(pop!);
            return interruptedTimeSeries([for (final i in keep) tt[i]], [for (final i in keep) yy[i]], start,
                family: family, population: pp == null ? null : [for (final i in keep) pp[i]], lag: readNum(lag)?.round(), outcome: outcome!, timeName: time!, unit: ds.dictionary[outcome]!.unit);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}


// ---------------------------------------------------------------- Bayésien

class BayesCalc extends StatefulWidget {
  final OnResult onResult;
  final String? initial;
  const BayesCalc(this.onResult, {super.key, this.initial});
  @override
  State<BayesCalc> createState() => _BayesCalcState();
}

class _BayesCalcState extends State<BayesCalc> {
  late bool effect = widget.initial == 'bayes_effect';
  BetaPrior betaPrior = BetaPrior.uniform;
  NormalPrior normalPrior = NormalPrior.sceptical;
  bool ratio = true;
  final x = TextEditingController(text: '7'), n = TextEditingController(text: '40'), thr = TextEditingController(text: '0,10');
  final pm = TextEditingController(text: '0,10'), pw = TextEditingController(text: '20');
  final est = TextEditingController(text: '0,75'), lo = TextEditingController(text: '0,58'), hi = TextEditingController(text: '0,97'), target = TextEditingController(text: '0,80');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Analyse bayésienne', 'Bayesian analysis'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(tr('Combine une connaissance préalable (a priori) et les données ; donne des probabilités directement interprétables (« probabilité d\'un bénéfice »).',
                'Combines prior knowledge and the data; gives directly interpretable probabilities ("probability of a benefit").'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(segments: [
          ButtonSegment(value: false, label: Text(tr('Proportion', 'Proportion'))),
          ButtonSegment(value: true, label: Text(tr('Effet publié', 'Published effect'))),
        ], selected: {effect}, onSelectionChanged: (s) => setState(() => effect = s.first)),
        const SizedBox(height: 10),
        if (!effect) ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            NumField(tr('Événements', 'Events'), x), NumField(tr('Effectif', 'Sample size'), n), NumField(tr('Seuil (facultatif)', 'Threshold (optional)'), thr),
            Pick<BetaPrior>(tr('A priori', 'Prior'), betaPrior, [
              (BetaPrior.uniform, tr('uniforme', 'uniform')), (BetaPrior.jeffreys, 'Jeffreys'), (BetaPrior.informative, tr('informatif', 'informative')),
            ], (v) => setState(() => betaPrior = v ?? BetaPrior.uniform), width: 200),
            if (betaPrior == BetaPrior.informative) ...[NumField(tr('Proportion a priori', 'Prior proportion'), pm), NumField(tr('Poids (sujets)', 'Weight (subjects)'), pw)],
          ]),
        ] else ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            Pick<bool>(tr('Mesure', 'Measure'), ratio, [(true, tr('rapport (RR, OR, HR)', 'ratio (RR, OR, HR)')), (false, tr('différence', 'difference'))], (v) => setState(() => ratio = v ?? true), width: 220),
            NumField(tr('Estimation', 'Estimate'), est), NumField(tr('IC 95 % : inférieure', '95% CI: lower'), lo), NumField(tr('IC 95 % : supérieure', '95% CI: upper'), hi),
            NumField(tr('Effet cible (important)', 'Target effect (important)'), target, width: 220),
            Pick<NormalPrior>(tr('A priori', 'Prior'), normalPrior, [
              (NormalPrior.sceptical, tr('sceptique', 'sceptical')), (NormalPrior.enthusiastic, tr('enthousiaste', 'enthusiastic')), (NormalPrior.vague, tr('vague', 'vague')),
            ], (v) => setState(() => normalPrior = v ?? NormalPrior.sceptical), width: 200),
          ]),
        ],
        _computeButton(context, () {
          run(context, () {
            if (!effect) {
              final xx = readNum(x), nn = readNum(n);
              if (xx == null || nn == null) throw StatInputError('missing', tr('Indiquer les événements et l\'effectif.', 'Enter the events and the sample size.'));
              return bayesProportion(xx.round(), nn.round(), prior: betaPrior, priorMean: readNum(pm) ?? 0.5, priorWeight: readNum(pw) ?? 2, threshold: readNum(thr));
            }
            final e = readNum(est), l = readNum(lo), h = readNum(hi), t = readNum(target);
            if ([e, l, h, t].contains(null)) throw StatInputError('missing', tr('Indiquer l\'estimation, son IC et l\'effet cible.', 'Enter the estimate, its CI and the target effect.'));
            return bayesEffect(e!, l!, h!, ratio: ratio, target: t!, prior: normalPrior);
          }, widget.onResult);
        }),
      ]);
}
