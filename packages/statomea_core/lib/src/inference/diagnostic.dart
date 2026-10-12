/// Performance d'un test diagnostique dichotomique contre une référence.
///
///                 Malades (réf +)   Non malades (réf −)
///   Test +             VP                 FP
///   Test −             FN                 VN
///
/// IC de Wilson pour Se, Sp, VPP, VPN ; IC des rapports de vraisemblance par
/// la méthode du logarithme (Simel, Samsa & Matchar 1991).
library;

import 'dart:math' as math;

import '../math/distributions.dart';
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'proportion.dart';

AnalysisResult diagnosticAccuracy(int tp, int fp, int fn, int tn,
    {double level = 0.95, StudyDesign design = StudyDesign.diagnosticAccuracy, double? targetPrevalence, String? testName, String? reference}) {
  testName ??= tr('Test index', 'Index test');
  reference ??= tr('Référence', 'Reference');
  if ([tp, fp, fn, tn].any((v) => v < 0)) {
    throw StatInputError('negative_count', tr('Effectifs négatifs.', 'Negative counts.'));
  }
  final diseased = tp + fn, healthy = fp + tn, total = diseased + healthy;
  if (diseased == 0 || healthy == 0) {
    throw StatInputError('no_reference_group', tr('Il faut des sujets malades ET non malades selon la référence pour estimer Se et Sp.',
        'Both diseased AND non-diseased subjects (per the reference) are needed to estimate Se and Sp.'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final alerts = <Alert>[];
  Estimate prop(String label, int x, int n) {
    if (n == 0) return Estimate(label, double.nan);
    final w = wilsonCi(x, n, level: level);
    return Estimate(label, x / n, lower: w.lower, upper: w.upper, level: level);
  }

  final se = prop(tr('Sensibilité', 'Sensitivity'), tp, diseased);
  final sp = prop(tr('Spécificité', 'Specificity'), tn, healthy);
  final ppv = prop(tr("VPP (prévalence de l'échantillon)", 'PPV (sample prevalence)'), tp, tp + fp);
  final npv = prop(tr("VPN (prévalence de l'échantillon)", 'NPV (sample prevalence)'), tn, tn + fn);
  final prev = prop(tr("Prévalence dans l'échantillon", 'Prevalence in the sample'), diseased, total);
  final acc = prop(tr('Exactitude', 'Accuracy'), tp + tn, total);

  Estimate lr(String label, int x1, int n1, int x2, int n2) {
    // Correction 0,5 si un effectif nul rend le logarithme indéfini.
    final zero = x1 == 0 || x2 == 0;
    final c = zero ? 0.5 : 0.0;
    final p1 = (x1 + c) / (n1 + (zero ? 1 : 0));
    final p2 = (x2 + c) / (n2 + (zero ? 1 : 0));
    final v = p1 / p2;
    final s = math.sqrt((1 - p1) / (p1 * (n1 + (zero ? 1 : 0))) + (1 - p2) / (p2 * (n2 + (zero ? 1 : 0))));
    if (zero) {
      alerts.add(Alert('lr_zero_cell', Severity.caution,
          tr('$label : effectif nul, correction de 0,5 appliquée ; estimation instable.', '$label: zero count, 0.5 correction applied; unstable estimate.')));
    }
    return Estimate(label, v, lower: math.exp(math.log(v) - z * s), upper: math.exp(math.log(v) + z * s), level: level);
  }

  final lrPos = lr(tr('Rapport de vraisemblance positif', 'Positive likelihood ratio'), tp, diseased, fp, healthy);
  final lrNeg = lr(tr('Rapport de vraisemblance négatif', 'Negative likelihood ratio'), fn, diseased, tn, healthy);
  final estimates = [se, sp, ppv, npv, lrPos, lrNeg, prev, acc];
  final stats = <String, double>{'youden': se.value + sp.value - 1, 'prevalence_sample': prev.value};

  if (targetPrevalence != null) {
    final p = targetPrevalence;
    final ppvT = se.value * p / (se.value * p + (1 - sp.value) * (1 - p));
    final npvT = sp.value * (1 - p) / (sp.value * (1 - p) + (1 - se.value) * p);
    estimates.add(Estimate(tr('VPP à la prévalence cible ${fmtPct(p)}', 'PPV at target prevalence ${fmtPct(p)}'), ppvT));
    estimates.add(Estimate(tr('VPN à la prévalence cible ${fmtPct(p)}', 'NPV at target prevalence ${fmtPct(p)}'), npvT));
    stats['ppv_target'] = ppvT;
    stats['npv_target'] = npvT;
  }
  if (design == StudyDesign.caseControl) {
    alerts.add(Alert('diag_case_control', Severity.serious,
        tr("Recrutement de type cas-témoins (malades et non-malades sélectionnés séparément) : la prévalence de l'échantillon est artificielle, VPP et VPN ne sont pas transposables, et Se/Sp sont souvent surestimées (biais de spectre).",
            'Case-control recruitment (diseased and non-diseased selected separately): the sample prevalence is artificial, PPV and NPV are not transferable, and Se/Sp are often overestimated (spectrum bias).'),
        suggestion: tr('Recalculer VPP/VPN à une prévalence cible documentée.', 'Recompute PPV/NPV at a documented target prevalence.')));
  }
  if (diseased < 30 || healthy < 30) {
    alerts.add(Alert('diag_small', Severity.caution,
        tr('Effectif faible ($diseased malades, $healthy non malades) : IC larges.', 'Small sample ($diseased diseased, $healthy non-diseased): wide CIs.')));
  }
  return AnalysisResult(
    methodId: 'diagnostic_accuracy',
    methodName: tr('Performance diagnostique (tableau 2 × 2)', 'Diagnostic accuracy (2 × 2 table)'),
    inputs: {'tp': tp, 'fp': fp, 'fn': fn, 'tn': tn, 'level': level, 'design': design.name, 'targetPrevalence': ?targetPrevalence},
    formula: tr(
        'Se = VP/(VP+FN) ; Sp = VN/(VN+FP) ; VPP = VP/(VP+FP) ; VPN = VN/(VN+FN) ; RV+ = Se/(1−Sp) ; RV− = (1−Se)/Sp ; IC de Wilson ; IC des RV par le logarithme ; '
            'VPP(p) = Se·p / [Se·p + (1−Sp)(1−p)] (théorème de Bayes).',
        'Se = TP/(TP+FN); Sp = TN/(TN+FP); PPV = TP/(TP+FP); NPV = TN/(TN+FN); LR+ = Se/(1−Sp); LR− = (1−Se)/Sp; Wilson CIs; log-method CIs for LRs; '
            'PPV(p) = Se·p / [Se·p + (1−Sp)(1−p)] (Bayes theorem).'),
    estimates: estimates,
    statistics: stats,
    checks: [
      Check('reference_standard', tr('Référence appliquée à tous les sujets (pas de biais de vérification)', 'Reference applied to all subjects (no verification bias)'),
          CheckStatus.notAssessed, tr('À documenter selon STARD 2015 / QUADAS-2.', 'To be documented per STARD 2015 / QUADAS-2.')),
      Check('blinding', tr('Lecture du test indépendante de la référence', 'Test read blind to the reference'), CheckStatus.notAssessed,
          tr('Non vérifiable par le calcul.', 'Cannot be checked by calculation.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Tableau diagnostique', 'Diagnostic table'), ['', '$reference +', '$reference −', 'Total'], [
        ['$testName +', '$tp', '$fp', '${tp + fp}'],
        ['$testName −', '$fn', '$tn', '${fn + tn}'],
        ['Total', '$diseased', '$healthy', '$total'],
      ]),
      ResultTable(tr('Indicateurs', 'Indicators'), [tr('Indicateur', 'Indicator'), tr('Estimation', 'Estimate'), tr('IC ${(level * 100).round()} %', '${(level * 100).round()}% CI')],
          [for (final e in estimates) [e.label, fmt(e.value), e.hasInterval ? '${fmt(e.lower)} – ${fmt(e.upper)}' : '—']]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Un test binaire comparé à une référence : Se et Sp décrivent le test, VPP et VPN dépendent en plus de la prévalence.',
          'A binary test compared with a reference: Se and Sp describe the test; PPV and NPV also depend on prevalence.'),
      whatItMeans: tr(
          'Se = ${fmtCi(se)}, Sp = ${fmtCi(sp)}. RV+ = ${fmt(lrPos.value)}, RV− = ${fmt(lrNeg.value)}. Les VPP/VPN calculées ne valent que pour une prévalence de ${fmtPct(prev.value)}.',
          'Se = ${fmtCi(se)}, Sp = ${fmtCi(sp)}. LR+ = ${fmt(lrPos.value)}, LR− = ${fmt(lrNeg.value)}. The computed PPV/NPV apply only at a prevalence of ${fmtPct(prev.value)}.'),
      notJustified: tr(
          "Transposer VPP et VPN à une population de prévalence différente ; conclure à l'utilité clinique du test sans considérer la place dans la stratégie diagnostique ; ignorer l'incertitude des estimations.",
          'Transferring PPV and NPV to a population with a different prevalence; concluding on clinical usefulness without considering the place of the test in the diagnostic pathway; ignoring the uncertainty of the estimates.'),
    ),
  );
}
