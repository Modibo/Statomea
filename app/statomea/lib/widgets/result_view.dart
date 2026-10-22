import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart';

import '../state/app_state.dart';
import 'common.dart';

/// Affichage d'un résultat du moteur. En mode guidé : résultat principal,
/// alertes importantes, trois questions, conditions. En mode expert : en plus
/// toutes les estimations, statistiques, tableaux, formule, journal, JSON.
class ResultView extends StatelessWidget {
  final AnalysisResult result;
  final VoidCallback? onOpenLesson;
  const ResultView(this.result, {super.key, this.onOpenLesson});

  @override
  Widget build(BuildContext context) {
    final expert = context.watch<AppState>().expertMode;
    final r = result;
    final cs = Theme.of(context).colorScheme;
    final info = methodInfo(r.methodId);
    final main = r.estimates.isEmpty ? null : r.estimates.first;
    final serious = r.alerts.where((a) => a.severity.index >= Severity.caution.index).toList()
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(r.methodName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            StatusChip(r.status),
            if (!r.reliable && r.status == MethodStatus.validated)
              Chip(
                  label: Text(tr('Résultat non fiable', 'Unreliable result')),
                  backgroundColor: cs.errorContainer,
                  labelStyle: TextStyle(color: cs.onErrorContainer),
                  visualDensity: VisualDensity.compact),
          ]),
          if (r.status != MethodStatus.validated)
            Banner2(Severity.critical, tr('Méthode en développement : ce résultat ne doit pas être présenté comme fiable.', 'Method in development: this result must not be presented as reliable.')),
          const SizedBox(height: 8),
          if (main != null && r.reliable) ...[
            SectionLabel(tr('Résultat calculé', 'Computed result'), icon: Icons.calculate_outlined),
            // Hauteur minimale 48 : le texte sélectionnable est une cible tactile pour les lecteurs d'écran.
            ConstrainedBox(
              // 48 × 48 au minimum : un résultat très court (« 492 ») reste une cible tactile suffisante.
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: SelectableText(fmtCi(main), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.primary)),
            ),
            Text(main.label, style: Theme.of(context).textTheme.bodySmall),
            if (main.pValue != null) Text(fmtP(main.pValue), style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (main != null && !r.reliable) ...[
            SectionLabel(tr('Résultat calculé', 'Computed result'), icon: Icons.calculate_outlined),
            Text(tr('Estimation non rapportable', 'Estimate not reportable'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cs.error)),
            Text(tr('${main.label} : voir les alertes ci-dessous. ${expert ? "Valeur brute du moteur (à ne pas rapporter) : ${fmtCi(main)}." : ""}', '${main.label}: see the alerts below. ${expert ? "Raw engine value (not to be reported): ${fmtCi(main)}." : ""}'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          for (final a in expert ? serious : serious.where((a) => a.severity.index >= Severity.caution.index).take(4))
            Banner2(a.severity, a.message, suggestion: a.suggestion),
          const SizedBox(height: 8),
          if (!expert && r.reliable && r.estimates.length > 1)
            ...r.estimates.skip(1).take(4).map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(tr('• ${e.label} : ${fmtCi(e)}', '• ${e.label}: ${fmtCi(e)}'), style: Theme.of(context).textTheme.bodyMedium),
                )),
          if (expert && r.estimates.isNotEmpty)
            DataTableView(ResultTable(tr('Estimations', 'Estimates'), [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('Intervalle', 'Interval'), 'p', tr('ES', 'SE')], [
              for (final e in r.estimates)
                [
                  e.label,
                  fmt(e.value, digits: 4),
                  e.hasInterval ? tr('${e.intervalKind} ${(e.level * 100).round()} % : ${fmt(e.lower, digits: 4)} à ${fmt(e.upper, digits: 4)}', '${(e.level * 100).round()}% ${intervalName(e.intervalKind)}: ${fmt(e.lower, digits: 4)} to ${fmt(e.upper, digits: 4)}') : '—',
                  fmtP(e.pValue),
                  e.se == null ? '—' : fmt(e.se, digits: 3),
                ]
            ])),
          for (final t in expert ? r.tables : (r.reliable ? r.tables.take(1) : const <ResultTable>[])) DataTableView(t),
          FiguresView(r),
          const SizedBox(height: 8),
          SectionLabel(tr('Interprétation proposée', 'Proposed interpretation'), icon: Icons.lightbulb_outline),
          _Question(tr('Pourquoi cette méthode ?', 'Why this method?'), r.interpretation.whyThisMethod, initiallyExpanded: false),
          _Question(tr('Que signifie le résultat ?', 'What does the result mean?'), r.interpretation.whatItMeans, initiallyExpanded: true),
          _Question(tr('Quelles conclusions restent injustifiées ?', 'Which conclusions remain unjustified?'), r.interpretation.notJustified, initiallyExpanded: true),
          if (r.checks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionLabel(tr('Hypothèses et diagnostics', 'Assumptions and diagnostics'), icon: Icons.fact_check_outlined),
            for (final c in r.checks) CheckTile(c, detailed: expert),
          ],
          ExpertHint(tr('toutes les estimations et tableaux, formule, journal de calcul', 'all estimates and tables, formula, computation log')),
          if (expert) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Méthode, formule et journal de calcul', 'Method, formula and computation log')),
              children: [
                Align(alignment: Alignment.centerLeft, child: SelectableText(r.formula, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                if (info != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Validation : ${info.reference}', 'Validation: ${info.reference}'), style: Theme.of(context).textTheme.bodySmall)),
                if (r.statistics.isNotEmpty)
                  DataTableView(ResultTable(tr('Statistiques', 'Statistics'), [tr('Nom', 'Name'), tr('Valeur', 'Value')],
                      [for (final s in r.statistics.entries.where((s) => !s.key.startsWith('se_'))) [s.key, fmt(s.value, digits: 6)]])),
                for (final l in r.log) Align(alignment: Alignment.centerLeft, child: Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(tr('Copier le résultat JSON', 'Copy the result as JSON')),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(r.toJson())));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Résultat copié.', 'Result copied.'))));
                    },
                  ),
                ),
              ],
            ),
          ],
          if (onOpenLesson != null)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onOpenLesson, icon: const Icon(Icons.school_outlined), label: Text(tr('Leçon associée', 'Related lesson')))),
        ]),
      ),
    );
  }
}

class _Question extends StatelessWidget {
  final String q, a;
  final bool initiallyExpanded;
  const _Question(this.q, this.a, {required this.initiallyExpanded});
  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        // Texte sélectionnable = cible tactile : au moins 48 de haut, même pour une réponse courte.
        children: [ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: SelectableText(a))],
      );
}

/// Figures produites par le moteur (SVG identiques à celles des exports).
class FiguresView extends StatelessWidget {
  final AnalysisResult r;
  const FiguresView(this.r, {super.key});
  @override
  Widget build(BuildContext context) {
    final f = r.figures;
    // (titre, SVG, largeur minimale lisible, largeur maximale utile)
    final svgs = <(String, String, double, double)>[
      if (f['forest'] is Map) ('Forest plot', forestPlotSvg((f['forest'] as Map).cast(), font: 'NotoSans'), 640, 820),
      if (f['calibration'] is List) (tr('Courbe de calibration', 'Calibration curve'), calibrationSvg((f['calibration'] as List).cast(), font: 'NotoSans', smooth: (f['calibrationSmooth'] as List?)?.cast()), 340, 460),
      if (f['doseResponse'] is List)
        for (final c in (f['doseResponse'] as List).cast<Map>()) (tr('Courbe dose-effet : ${c['variable']}', 'Dose-response curve: ${c['variable']}'), doseResponseSvg(c, font: 'NotoSans'), 340, 520),
      if (f['bayes'] is Map) (tr('A priori et a posteriori', 'Prior and posterior'), bayesSvg(f['bayes'] as Map, font: 'NotoSans'), 340, 480),
      if (f['its'] is Map) (tr('Série chronologique interrompue', 'Interrupted time series'), itsSvg(f['its'] as Map, font: 'NotoSans'), 340, 520),
      if (f['referenceInterval'] is Map) (tr('Intervalle de référence', 'Reference interval'), referenceIntervalSvg(f['referenceInterval'] as Map, font: 'NotoSans'), 340, 480),
      if (f['methodComparison'] is Map) (tr('Comparaison de méthodes', 'Method comparison'), methodComparisonSvg(f['methodComparison'] as Map, font: 'NotoSans'), 340, 460),
      if (f['lovePlot'] is Map) (tr('Équilibre des covariables (love plot)', 'Covariate balance (love plot)'), lovePlotSvg(f['lovePlot'] as Map, font: 'NotoSans'), 360, 560),
      if (f['psOverlap'] is Map) (tr('Recouvrement des scores de propension', 'Propensity score overlap'), psOverlapSvg(f['psOverlap'] as Map, font: 'NotoSans'), 340, 520),
      if (f['decisionCurve'] is List) (tr('Courbe de décision', 'Decision curve'), decisionCurveSvg((f['decisionCurve'] as List).cast(), font: 'NotoSans'), 340, 500),
      if (f['miChains'] is Map) (tr('Convergence des chaînes d\'imputation', 'Convergence of the imputation chains'), miChainsSvg(f['miChains'] as Map, font: 'NotoSans'), 340, 480),
      if (f['sroc'] is Map) (tr('Espace ROC : études, point combiné, SROC', 'ROC space: studies, pooled point, SROC'), srocSvg((f['sroc'] as Map).cast(), font: 'NotoSans'), 360, 520),
      if (f['bubble'] is Map) (tr('Méta-régression (aire ∝ poids)', 'Meta-regression (area ∝ weight)'), bubblePlotSvg(f['bubble'] as Map, font: 'NotoSans'), 340, 520),
      if (f['trajectories'] is Map) (tr('Trajectoires individuelles', 'Individual trajectories'), trajectoriesSvg(f['trajectories'] as Map, font: 'NotoSans'), 340, 520),
      if (f['powerCurve'] is Map) (tr('Courbe de puissance', 'Power curve'), powerCurveSvg(f['powerCurve'] as Map, font: 'NotoSans'), 340, 480),
      if (f['cumulativeIncidence'] is Map) (tr('Incidence cumulée', 'Cumulative incidence'), cifSvg(f['cumulativeIncidence'] as Map, font: 'NotoSans'), 340, 520),
      if (f['kaplanMeier'] is Map) ('Kaplan-Meier', kmSvg((f['kaplanMeier'] as Map).cast(), font: 'NotoSans'), 340, 520),
      if (f['blandAltman'] is Map) ('Bland-Altman', blandAltmanSvg(f['blandAltman'] as Map, font: 'NotoSans'), 340, 500),
      if (f['volcano'] is Map) ('Volcano plot', volcanoSvg(f['volcano'] as Map, font: 'NotoSans'), 360, 560),
      if (f['standardCurve'] is Map) (tr('Courbe standard', 'Standard curve'), standardCurveSvg(f['standardCurve'] as Map, font: 'NotoSans'), 340, 480),
      if (f['manhattan'] is Map) ('Manhattan plot', manhattanSvg(f['manhattan'] as Map, font: 'NotoSans'), 480, 720),
      if (f['qq'] is Map) ('QQ plot', qqSvg(f['qq'] as Map, font: 'NotoSans'), 320, 460),
      if (f['ldsc'] is Map) ((f['ldsc'] as Map)['cross'] == true ? tr('Régression LD score croisée', 'Cross-trait LD score regression') : tr('Régression LD score', 'LD score regression'), ldscSvg(f['ldsc'] as Map, font: 'NotoSans'), 320, 460),
      if (f['prs'] is Map) (tr('Score polygénique : choix du seuil', 'Polygenic score: threshold choice'), prsSvg(f['prs'] as Map, font: 'NotoSans'), 340, 480),
      if (f['mr'] is Map) (tr('Randomisation mendélienne', 'Mendelian randomization'), mrSvg(f['mr'] as Map, font: 'NotoSans'), 340, 480),
      if (f['king'] is Map) (tr('Apparentement (KING)', 'Relatedness (KING)'), kingSvg(f['king'] as Map, font: 'NotoSans'), 360, 540),
      if (f['pca'] is Map) (tr('ACP des génotypes', 'Genotype PCA'), pcaSvg(f['pca'] as Map, font: 'NotoSans'), 360, 520),
    ];
    final al = f['alignment'] is Map ? (f['alignment'] as Map) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (title, svg, minW, maxW) in svgs) ...[
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth.clamp(minW, maxW);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Semantics(
              image: true,
              label: figureDescription(title, f),
              child: ExcludeSemantics(child: Container(color: Colors.white, width: w, child: SvgPicture.string(svg, width: w, fit: BoxFit.contain))),
            ),
          );
        }),
        if (minW > 400) Text(tr('Faire défiler horizontalement sur petit écran.', 'Scroll horizontally on a small screen.'), style: Theme.of(context).textTheme.bodySmall),
      ],
      if (al != null) ...[
        const SizedBox(height: 8),
        Text(tr('Alignement avec ${al['subject']}', 'Alignment with ${al['subject']}'), style: Theme.of(context).textTheme.labelLarge),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText('${al['text']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.25)),
        ),
      ],
    ]);
  }
}

/// Texte de remplacement d'une figure pour les lecteurs d'écran : ce que la
/// figure montre, et où trouver les valeurs (les tableaux du résultat).
String figureDescription(String title, Map<String, Object?> f) {
  final tables = tr('Les valeurs représentées figurent dans les tableaux du résultat.', 'The plotted values are given in the result tables.');
  if (f['doseResponse'] is List && (title.startsWith('Courbe dose-effet') || title.startsWith('Dose-response'))) {
    final c = (f['doseResponse'] as List).cast<Map>().firstWhere((c) => title.endsWith(': ${c['variable']}'), orElse: () => (f['doseResponse'] as List).first as Map);
    return tr('Courbe dose-effet de ${c['variable']} : ${c['effect']} par rapport à la médiane (${fmt((c['ref'] as num).toDouble())}), avec sa bande de confiance ; la ligne horizontale marque l\'absence d\'effet, les traits rouges les nœuds de la spline. $tables',
        'Dose-response curve of ${c['variable']}: ${c['effect']} relative to the median (${fmt((c['ref'] as num).toDouble())}), with its confidence band; the horizontal line marks no effect, the red ticks the spline knots. $tables');
  }
  if (f['bayes'] is Map && (title == 'A priori et a posteriori' || title == 'Prior and posterior')) {
    return tr('Courbes de densité : a priori en gris, données en tirets rouges, a posteriori en bleu ; la bande bleutée marque l\'intervalle de crédibilité. $tables',
        'Density curves: prior in grey, data as red dashes, posterior in blue; the shaded band marks the credible interval. $tables');
  }
  if (f['its'] is Map && (title == 'Série chronologique interrompue' || title == 'Interrupted time series')) {
    final m = f['its'] as Map;
    return tr('Évolution de ${m['yLabel']} selon ${m['xLabel']} : points observés, droite ajustée avant et après l\'intervention (${fmt((m['interruption'] as num).toDouble())}), et en tirets la tendance antérieure prolongée (ce qui serait arrivé sans intervention). $tables',
        'Trajectory of ${m['yLabel']} by ${m['xLabel']}: observed points, fitted line before and after the intervention (${fmt((m['interruption'] as num).toDouble())}), and dashed the extended prior trend (what would have happened without the intervention). $tables');
  }
  if (f['referenceInterval'] is Map && (title == 'Intervalle de référence' || title == 'Reference interval')) {
    final m = f['referenceInterval'] as Map;
    return tr('Histogramme des valeurs de référence ; bornes de l\'intervalle en rouge (${fmt((m['lower'] as num).toDouble())} et ${fmt((m['upper'] as num).toDouble())}), IC des bornes en bandes. $tables',
        'Histogram of the reference values; interval limits in red (${fmt((m['lower'] as num).toDouble())} and ${fmt((m['upper'] as num).toDouble())}), CIs of the limits as bands. $tables');
  }
  if (f['methodComparison'] is Map && (title == 'Comparaison de méthodes' || title == 'Method comparison')) {
    final m = f['methodComparison'] as Map;
    return tr('${m['yName']} selon ${m['xName']} (${(m['x'] as List).length} échantillons) ; droite ajustée y = ${fmt((m['intercept'] as num).toDouble())} + ${fmt((m['slope'] as num).toDouble())}·x en rouge, identité en tirets. $tables',
        '${m['yName']} against ${m['xName']} (${(m['x'] as List).length} samples); fitted line y = ${fmt((m['intercept'] as num).toDouble())} + ${fmt((m['slope'] as num).toDouble())}·x in red, identity dashed. $tables');
  }
  if (f['lovePlot'] is Map && title.contains('love plot')) {
    final rows = ((f['lovePlot'] as Map)['rows'] as List).cast<Map>();
    final bad = rows.where((r) => ((r['after'] as num).abs()) >= 0.1).length;
    return tr('Différences standardisées de ${rows.length} variables avant (cercles vides) et après ajustement (cercles pleins), seuil 0,1 en tirets ; $bad variable(s) au-dessus du seuil après ajustement. $tables',
        'Standardized differences of ${rows.length} variables before (open circles) and after adjustment (filled circles), 0.1 threshold dashed; $bad variable(s) above the threshold after adjustment. $tables');
  }
  if (f['psOverlap'] is Map && (title.startsWith('Recouvrement') || title.startsWith('Propensity score overlap'))) {
    return tr('Histogrammes en miroir du score de propension : traités en haut, autres en bas ; le recouvrement indique la zone où des sujets comparables existent. $tables',
        'Mirrored histograms of the propensity score: treated above, others below; the overlap shows where comparable subjects exist. $tables');
  }
  if (title == 'Forest plot' && f['forest'] is Map) {
    final fo = (f['forest'] as Map).cast<String, Object?>();
    final k = (fo['studies'] as List).length;
    final pooled = (fo['pooled'] as Map).cast<String, Object?>();
    double v(String key) => (pooled[key] as num).toDouble();
    return tr('Forest plot : $k études, effet combiné ${fmt(v('est'))} (IC ${fmt(v('lower'))} à ${fmt(v('upper'))}) ; la ligne verticale marque l\'absence d\'effet. $tables',
        'Forest plot: $k studies, pooled effect ${fmt(v('est'))} (CI ${fmt(v('lower'))} to ${fmt(v('upper'))}); the vertical line marks no effect. $tables');
  }
  if (title == 'Volcano plot' && f['volcano'] is Map) {
    final sig = ((f['volcano'] as Map)['significant'] as List).where((e) => e == true).length;
    final n = ((f['volcano'] as Map)['significant'] as List).length;
    return tr('Volcano plot : $n gènes, rapport d\'expression (log2) en abscisse, −log10 p en ordonnée ; $sig gènes significatifs en rouge. $tables',
        'Volcano plot: $n genes, log2 fold change on the x axis, −log10 p on the y axis; $sig significant genes in red. $tables');
  }
  if (title == 'QQ plot' && f['qq'] is Map) {
    final l = (f['qq'] as Map)['lambda'];
    return tr('QQ plot des p observés contre les p attendus sous l\'hypothèse nulle, avec bande de confiance à 95 %${l == null ? '' : ' ; λ = ${fmt((l as num).toDouble(), digits: 3)}'}. $tables',
        'QQ plot of observed against expected p-values under the null hypothesis, with a 95% confidence band${l == null ? '' : '; λ = ${fmt((l as num).toDouble(), digits: 3)}'}. $tables');
  }
  if (f['trajectories'] is Map) {
    final m = f['trajectories'] as Map;
    return tr('Trajectoires individuelles de ${m['yLabel']} selon ${m['xLabel']} (une ligne grise par sujet, ${(m['subjects'] as List).length} au plus), et moyenne ajustée par le modèle mixte pour chaque groupe (lignes de couleur). $tables',
        'Individual trajectories of ${m['yLabel']} by ${m['xLabel']} (one grey line per subject, ${(m['subjects'] as List).length} at most), and mean fitted by the mixed model for each group (coloured lines). $tables');
  }
  if (f['powerCurve'] is Map) {
    final m = f['powerCurve'] as Map;
    return tr('Courbe de puissance : puissance selon ${m['xLabel']}, avec la puissance visée (${((m['target'] as num) * 100).round()} %) et l\'effectif retenu (${(m['nStar'] as num).ceil()}). $tables',
        'Power curve: power by ${m['xLabel']}, with the target power (${((m['target'] as num) * 100).round()}%) and the chosen sample size (${(m['nStar'] as num).ceil()}). $tables');
  }
  if (f['cumulativeIncidence'] is Map) {
    final m = f['cumulativeIncidence'] as Map;
    final groups = [for (final c in (m['curves'] as List).cast<Map>()) c['group'].toString()];
    return tr('Incidence cumulée de « ${m['cause']} » au cours du temps (${groups.join(', ')}), en trait plein avec sa bande de confiance ; en tirets, 1 − Kaplan-Meier naïf, plus élevé ; en pointillés, l\'incidence de l\'événement concurrent (${m['competing']}). $tables',
        'Cumulative incidence of "${m['cause']}" over time (${groups.join(', ')}), solid line with its confidence band; dashed, naive 1 − Kaplan-Meier, higher; dotted, the incidence of the competing event (${m['competing']}). $tables');
  }
  if (f['mr'] is Map) {
    final m = f['mr'] as Map;
    return tr('Randomisation mendélienne : pour chaque variant, association avec ${m['outcome']} selon l\'association avec ${m['exposure']}, avec leurs erreurs types ; les pentes des droites IVW, MR-Egger et médiane pondérée estiment l\'effet causal. $tables',
        'Mendelian randomization: for each variant, association with ${m['outcome']} against association with ${m['exposure']}, with their standard errors; the slopes of the IVW, MR-Egger and weighted median lines estimate the causal effect. $tables');
  }
  if (f['prs'] is Map) {
    final m = f['prs'] as Map;
    return tr('Score polygénique : R² de Nagelkerke en validation pour chaque seuil de p, le seuil retenu en rouge ; la ligne pointillée donne le R² sur l\'échantillon de test (${fmt((m['testR2'] as num).toDouble(), digits: 2)}), plus faible. $tables',
        'Polygenic score: Nagelkerke R² in validation for each p threshold, the chosen threshold in red; the dashed line gives the R² on the test sample (${fmt((m['testR2'] as num).toDouble(), digits: 2)}), lower. $tables');
  }
  if (f['ldsc'] is Map && (f['ldsc'] as Map)['cross'] == true) {
    final a = ((f['ldsc'] as Map)['intercept'] as num).toDouble();
    return tr('Régression LD score croisée : produit z₁·z₂ moyen des variants selon leur score LD, avec la droite ajustée ; la pente reflète la covariance génétique, l\'intercept ${fmt(a, digits: 3)} la corrélation non génétique entre les deux balayages. $tables',
        'Cross-trait LD score regression: mean product z₁·z₂ of variants by LD score, with the fitted line; the slope reflects the genetic covariance, the intercept ${fmt(a, digits: 3)} the non-genetic correlation between the two scans. $tables');
  }
  if (f['ldsc'] is Map) {
    final a = ((f['ldsc'] as Map)['intercept'] as num).toDouble();
    return tr('Régression LD score : χ² moyen des variants selon leur score LD, avec la droite ajustée ; intercept ${fmt(a, digits: 3)} (1 = pas de confusion), la pente reflète la polygénie. $tables',
        'LD score regression: mean χ² of variants by LD score, with the fitted line; intercept ${fmt(a, digits: 3)} (1 = no confounding), the slope reflects polygenicity. $tables');
  }
  return '$title. $tables';
}
