import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../screens/lesson_screen.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'genomics_workshop.dart';
import 'meta_workshop.dart';
import 'prediction_workshop.dart';
import 'regression_workshop.dart';
import 'result_view.dart';

/// Calculateurs disponibles (groupés par famille).
List<(String, String, IconData, String)> get calculatorKinds => [
  ('proportion_ci', tr('Proportion / prévalence', 'Proportion / prevalence'), Icons.percent, tr('Descriptif', 'Descriptive')),
  ('describe', tr('Statistiques descriptives', 'Descriptive statistics'), Icons.bar_chart, tr('Descriptif', 'Descriptive')),
  ('two_by_two', tr('Tableau 2 × 2 (RR, OR, DR)', '2 × 2 table (RR, OR, RD)'), Icons.grid_on, 'Association'),
  ('chi_square_rxc', 'χ² r × c', Icons.grid_4x4, 'Association'),
  ('diagnostic_accuracy', tr('Performance diagnostique', 'Diagnostic accuracy'), Icons.biotech_outlined, 'Diagnostic'),
  ('compare_two', tr('Comparer 2 groupes', 'Compare 2 groups'), Icons.compare_arrows, tr('Comparaison', 'Comparison')),
  ('compare_k', tr('Comparer k groupes', 'Compare k groups'), Icons.view_week_outlined, tr('Comparaison', 'Comparison')),
  ('paired', tr('Mesures appariées', 'Paired measurements'), Icons.sync_alt, tr('Apparié', 'Paired')),
  ('mcnemar', tr('McNemar (binaire apparié)', 'McNemar (paired binary)'), Icons.swap_horiz, tr('Apparié', 'Paired')),
  ('correlation', tr('Corrélation', 'Correlation'), Icons.scatter_plot_outlined, tr('Corrélation', 'Correlation')),
  ('bland_altman', tr('Accord (Bland-Altman)', 'Agreement (Bland-Altman)'), Icons.align_horizontal_center, tr('Accord', 'Agreement')),
  ('kaplan_meier', tr('Survie (Kaplan-Meier, log-rank)', 'Survival (Kaplan-Meier, log-rank)'), Icons.timeline, tr('Survie', 'Survival')),
  ('cumulative_incidence', tr('Risques concurrents (incidence cumulée)', 'Competing risks (cumulative incidence)'), Icons.call_split, tr('Survie', 'Survival')),
  ('rmst', tr('Temps moyen de survie restreint (RMST)', 'Restricted mean survival time (RMST)'), Icons.area_chart, tr('Survie', 'Survival')),
  ('landmark', tr('Analyse landmark (exposition en cours de suivi)', 'Landmark analysis (exposure during follow-up)'), Icons.flag_outlined, tr('Survie', 'Survival')),
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
      'linear_regression' || 'logistic_regression' || 'poisson_robust' || 'firth_logistic' || 'cox' || 'fine_gray' => 'regression',
      'meta_binary' || 'meta_continuous' => 'meta',
      'prediction_logistic_internal' => 'prediction',
      'hardy_weinberg' || 'genetic_association' || 'snp_scan' || 'lmm_scan' || 'ldsc' || 'genetic_correlation' || 'polygenic_score' || 'glmm_scan' || 'mendelian_randomization' || 'mendelian_randomization_mv' || 'mr_steiger' || 'genotype_qc' || 'mutation_phenotype' || 'type_diversity' || 'qpcr_standard_curve' || 'qpcr_relative' || 'qpcr_lod' ||
      'differential_expression' || 'local_alignment' => 'genomics',
      'power_means' || 'power_proportions' || 'power_case_control' || 'power_survival' || 'power_gwas' => 'power',
      'describe_numeric' => 'describe',
      _ => calculatorKinds.any((k) => k.$1 == methodId) ? methodId : 'proportion_ci',
    };

/// Panneau de calcul : sélection du calculateur, saisie, résultat. Dans un
/// projet, chaque résultat est ajouté au journal.
class CalculatorPanel extends StatefulWidget {
  final Project? project;
  final String? initialMethod;
  const CalculatorPanel({super.key, this.project, this.initialMethod});
  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel> {
  late String kind = calculatorFor(widget.initialMethod ?? 'proportion_ci');
  AnalysisResult? result;

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
      'two_by_two' => TwoByTwoCalc(ds, p?.question.design ?? StudyDesign.unknown, onResult),
      'chi_square_rxc' => ChiRxCCalc(ds, onResult),
      'diagnostic_accuracy' => DiagnosticCalc(p?.question.design ?? StudyDesign.diagnosticAccuracy, onResult),
      'compare_two' => CompareTwoCalc(ds, onResult, initial: widget.initialMethod),
      'compare_k' => CompareKCalc(ds, onResult, initial: widget.initialMethod),
      'paired' => PairedCalc(ds, onResult, initial: widget.initialMethod),
      'mcnemar' => McNemarCalc(onResult),
      'correlation' => CorrelationCalc(ds, onResult),
      'bland_altman' => BlandAltmanCalc(ds, onResult),
      'sample_size' => SampleSizeCalc(onResult),
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
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label, icon, _) in calculatorKinds)
          ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: kind == id,
            onSelected: (_) => setState(() {
              kind = id;
              result = null;
            }),
          ),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: KeyedSubtree(key: ValueKey(kind), child: form))),
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
  const SampleSizeCalc(this.onResult, {super.key});
  @override
  State<SampleSizeCalc> createState() => _SampleSizeCalcState();
}

class _SampleSizeCalcState extends State<SampleSizeCalc> {
  String type = 'prop';
  final p = TextEditingController(text: '0,08'), d = TextEditingController(text: '0,02'), pop = TextEditingController(), deff = TextEditingController(text: '1');
  final delta = TextEditingController(text: '5'), sd = TextEditingController(text: '12');
  final p1 = TextEditingController(text: '0,10'), p2 = TextEditingController(text: '0,05');
  final alpha = TextEditingController(text: '0,05'), power = TextEditingController(text: '0,8'), drop = TextEditingController(text: '0');
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Taille d\'échantillon', 'Sample size'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(segments: [
          ButtonSegment(value: 'prop', label: Text(tr('Estimer une proportion', 'Estimate a proportion'))),
          ButtonSegment(value: 'two_props', label: Text('2 proportions')),
          ButtonSegment(value: 'two_means', label: Text('2 moyennes')),
        ], selected: {type}, onSelectionChanged: (s) => setState(() => type = s.first)),
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
          if (type != 'prop') ...[NumField(tr('α (bilatéral)', 'α (two-sided)'), alpha), NumField(tr('Puissance', 'Power'), power), NumField(tr('Perdus de vue (proportion)', 'Lost to follow-up (proportion)'), drop, width: 200)],
        ]),
        _computeButton(context, () {
          run(context, () {
            switch (type) {
              case 'prop':
                return sampleSizeProportion(expected: readNum(p) ?? 0, precision: readNum(d) ?? 0, population: readInt(pop), designEffect: readNum(deff) ?? 1);
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

