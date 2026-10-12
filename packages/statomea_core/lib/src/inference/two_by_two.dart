/// Tableau 2 × 2 : mesures d'association, test du χ² et test exact de Fisher.
///
/// Convention : lignes = exposition (exposés, non exposés), colonnes = issue
/// (événement, pas d'événement).
///
///               Événement   Pas d'événement
///   Exposés         a              b
///   Non exposés     c              d
library;

import 'dart:math' as math;

import '../math/distributions.dart';
import '../math/special.dart';
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'common.dart';
import 'proportion.dart';

/// Résultat du test exact de Fisher (algorithme de R `fisher.test`).
class FisherResult {
  final double pValue;
  final double conditionalOr;
  final double lower, upper;
  FisherResult(this.pValue, this.conditionalOr, this.lower, this.upper);
}

FisherResult fisherExact(int a, int b, int c, int d, {double level = 0.95}) {
  final m = a + c; // total de la colonne « événement »
  final n = b + d;
  final k = a + b; // total de la ligne « exposés »
  final lo = math.max(0, k - n);
  final hi = math.min(k, m);
  final support = [for (var i = lo; i <= hi; i++) i];
  final logdc = [for (final s in support) lnChoose(m, s) + lnChoose(n, k - s) - lnChoose(m + n, k)];

  List<double> dnhyper(double ncp) {
    final dd = [for (var i = 0; i < support.length; i++) logdc[i] + math.log(ncp) * support[i]];
    final mx = dd.reduce(math.max);
    final e = [for (final v in dd) math.exp(v - mx)];
    final s = e.fold(0.0, (x, y) => x + y);
    return [for (final v in e) v / s];
  }

  double mnhyper(double ncp) {
    if (ncp == 0) return lo.toDouble();
    if (ncp.isInfinite) return hi.toDouble();
    final dn = dnhyper(ncp);
    var s = 0.0;
    for (var i = 0; i < support.length; i++) {
      s += support[i] * dn[i];
    }
    return s;
  }

  double pnhyper(int q, double ncp, {bool upperTail = false}) {
    if (ncp == 0) return (upperTail ? q <= lo : q >= lo) ? 1 : 0;
    if (ncp.isInfinite) return (upperTail ? q <= hi : q >= hi) ? 1 : 0;
    final dn = dnhyper(ncp);
    var s = 0.0;
    for (var i = 0; i < support.length; i++) {
      if (upperTail ? support[i] >= q : support[i] <= q) s += dn[i];
    }
    return s;
  }

  // Valeur de p bilatérale : somme des probabilités ≤ probabilité observée.
  final d0 = dnhyper(1);
  final obs = d0[a - lo];
  var p = 0.0;
  for (final v in d0) {
    if (v <= obs * (1 + 1e-7)) p += v;
  }
  p = math.min(1.0, p);

  // Estimateur du maximum de vraisemblance conditionnelle.
  double mle;
  if (a == lo) {
    mle = 0;
  } else if (a == hi) {
    mle = double.infinity;
  } else {
    final mu = mnhyper(1);
    if (mu > a) {
      mle = brentRoot((t) => mnhyper(t) - a, 0, 1, tol: 1e-12);
    } else if (mu < a) {
      mle = 1 / brentRoot((t) => mnhyper(1 / t) - a, 2.2e-16, 1, tol: 1e-12);
    } else {
      mle = 1;
    }
  }

  final alpha = (1 - level) / 2;
  double ncpU() {
    if (a == hi) return double.infinity;
    final pp = pnhyper(a, 1);
    if (pp < alpha) return brentRoot((t) => pnhyper(a, t) - alpha, 0, 1, tol: 1e-12);
    if (pp > alpha) {
      return 1 / brentRoot((t) => pnhyper(a, 1 / t) - alpha, 2.2e-16, 1, tol: 1e-12);
    }
    return 1;
  }

  double ncpL() {
    if (a == lo) return 0;
    final pp = pnhyper(a, 1, upperTail: true);
    if (pp > alpha) {
      return brentRoot((t) => pnhyper(a, t, upperTail: true) - alpha, 0, 1, tol: 1e-12);
    }
    if (pp < alpha) {
      return 1 /
          brentRoot((t) => pnhyper(a, 1 / t, upperTail: true) - alpha, 2.2e-16, 1, tol: 1e-12);
    }
    return 1;
  }

  return FisherResult(p, mle, ncpL(), ncpU());
}

/// χ² de Pearson d'un tableau r × c (avec correction de Yates si 2 × 2 et
/// [yates] vrai, comme R `chisq.test`).
({double statistic, double df, double p, List<List<double>> expected}) chiSquareTable(
    List<List<int>> t,
    {bool yates = false}) {
  final r = t.length, c = t.first.length;
  final rowS = [for (final row in t) row.fold<int>(0, (a, b) => a + b)];
  final colS = [for (var j = 0; j < c; j++) t.fold<int>(0, (a, row) => a + row[j])];
  final total = rowS.fold<int>(0, (a, b) => a + b);
  final exp = [
    for (var i = 0; i < r; i++) [for (var j = 0; j < c; j++) rowS[i] * colS[j] / total]
  ];
  var x2 = 0.0;
  for (var i = 0; i < r; i++) {
    for (var j = 0; j < c; j++) {
      var dev = (t[i][j] - exp[i][j]).abs();
      if (yates && r == 2 && c == 2) {
        // R : YATES <- min(0.5, abs(x - E)).
        var minDev = double.infinity;
        for (var ii = 0; ii < 2; ii++) {
          for (var jj = 0; jj < 2; jj++) {
            minDev = math.min(minDev, (t[ii][jj] - exp[ii][jj]).abs());
          }
        }
        dev -= math.min(0.5, minDev);
      }
      x2 += dev * dev / exp[i][j];
    }
  }
  final df = ((r - 1) * (c - 1)).toDouble();
  return (statistic: x2, df: df, p: chiSquareUpper(x2, df), expected: exp);
}

/// Analyse d'un tableau 2 × 2 en fonction du plan d'étude.
AnalysisResult twoByTwo(int a, int b, int c, int d,
    {StudyDesign design = StudyDesign.unknown, double level = 0.95, String? exposure, String? outcome}) {
  exposure ??= tr('Exposition', 'Exposure');
  outcome ??= tr('Événement', 'Event');
  if ([a, b, c, d].any((v) => v < 0)) {
    throw StatInputError('negative_count', tr('Les effectifs doivent être des entiers positifs.', 'Counts must be non-negative integers.'));
  }
  final n1 = a + b, n0 = c + d, total = n1 + n0;
  if (n1 == 0 || n0 == 0) {
    throw StatInputError('empty_row', tr('Une ligne du tableau est vide : aucune comparaison possible entre exposés et non exposés.',
        'A row of the table is empty: no comparison between exposed and unexposed is possible.'));
  }
  if (a + c == 0 || b + d == 0) {
    throw StatInputError(
        'empty_column',
        tr("Aucun ${a + c == 0 ? "événement" : "non-événement"} observé : aucune mesure d'association n'est estimable.",
            'No ${a + c == 0 ? "event" : "non-event"} observed: no measure of association can be estimated.'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final alerts = <Alert>[];
  final checks = <Check>[];
  final log = <String>[];
  final zeroCell = [a, b, c, d].contains(0);
  // Correction de Haldane-Anscombe si une cellule est nulle.
  final cc = zeroCell ? 0.5 : 0.0;
  if (zeroCell) {
    alerts.add(Alert('zero_cell', Severity.caution,
        tr("Cellule nulle : 0,5 ajouté à chaque cellule (correction de Haldane-Anscombe) pour les estimations OR et RR par la méthode du logarithme. L'OR conditionnel et son IC exacts (Fisher) sont préférables.",
            'Zero cell: 0.5 added to each cell (Haldane-Anscombe correction) for the log-method OR and RR estimates. The exact conditional OR and its CI (Fisher) are preferable.'),
        suggestion: tr("Rapporter l'IC exact de Fisher ; mentionner la correction.", "Report Fisher's exact CI; mention the correction.")));
    log.add(tr('Correction de continuité 0,5 appliquée (cellule nulle).', 'Continuity correction of 0.5 applied (zero cell).'));
  }
  final aa = a + cc, bb = b + cc, ccc = c + cc, dd = d + cc;
  final or = (aa * dd) / (bb * ccc);
  final seLogOr = math.sqrt(1 / aa + 1 / bb + 1 / ccc + 1 / dd);
  final orE = Estimate('Odds ratio (Woolf)', or,
      lower: math.exp(math.log(or) - z * seLogOr), upper: math.exp(math.log(or) + z * seLogOr), level: level, se: seLogOr);
  final fisher = fisherExact(a, b, c, d, level: level);
  final orCond = Estimate(tr('Odds ratio conditionnel (Fisher, exact)', 'Conditional odds ratio (Fisher, exact)'), fisher.conditionalOr,
      lower: fisher.lower, upper: fisher.upper, level: level, pValue: fisher.pValue);

  final chi = chiSquareTable([
    [a, b],
    [c, d]
  ]);
  final chiY = chiSquareTable([
    [a, b],
    [c, d]
  ], yates: true);
  final minExp = chi.expected.expand((r) => r).reduce(math.min);
  final smallExpected = minExp < 5;
  checks.add(Check(
      'expected_counts',
      tr('Effectifs attendus ≥ 5 (validité du χ²)', 'Expected counts ≥ 5 (validity of the χ² test)'),
      smallExpected ? CheckStatus.violated : CheckStatus.ok,
      tr('Plus petit effectif attendu = ${fmt(minExp)}.${smallExpected ? " Le test exact de Fisher est retenu." : ""}',
          'Smallest expected count = ${fmt(minExp)}.${smallExpected ? " Fisher's exact test is used." : ""}')));
  checks.add(Check('independence', tr('Observations indépendantes', 'Independent observations'), CheckStatus.notAssessed,
      tr("Chaque individu ne doit figurer qu'une fois ; pour des données appariées, utiliser McNemar.", 'Each individual must appear only once; for paired data, use McNemar.')));

  final estimates = <Estimate>[];
  final r1 = a / n1, r0 = c / n0;
  final riskAllowed = designAllowsRisk(design);
  Estimate? rrE, rdE;
  if (riskAllowed || design == StudyDesign.unknown) {
    final rr = (aa / (aa + bb)) / (ccc / (ccc + dd));
    final seLogRr = math.sqrt(1 / aa - 1 / (aa + bb) + 1 / ccc - 1 / (ccc + dd));
    final name = design == StudyDesign.crossSectional ? tr('Rapport de prévalences', 'Prevalence ratio') : tr('Risque relatif', 'Risk ratio');
    rrE = Estimate(name, rr,
        lower: math.exp(math.log(rr) - z * seLogRr), upper: math.exp(math.log(rr) + z * seLogRr), level: level, se: seLogRr);
    final ci = newcombeDiffCi(a, n1, c, n0, level: level);
    rdE = Estimate(
        design == StudyDesign.crossSectional ? tr('Différence de prévalences', 'Prevalence difference') : tr('Différence de risques', 'Risk difference'),
        r1 - r0,
        lower: ci.lower,
        upper: ci.upper,
        level: level);
    estimates.addAll([rrE, rdE]);
  }
  estimates.addAll([orE, orCond]);
  if (design == StudyDesign.caseControl) {
    alerts.add(Alert('cc_no_risk', Severity.info,
        tr("Plan cas-témoins : l'échantillonnage se fait sur l'issue, les risques, le RR et la différence de risques ne sont pas estimables ; seul l'OR est interprétable.",
            'Case-control design: sampling is on the outcome, so risks, the RR and the risk difference cannot be estimated; only the OR is interpretable.')));
  } else if (design == StudyDesign.unknown) {
    alerts.add(Alert('design_unknown', Severity.caution,
        tr("Plan d'étude non précisé : RR et différence de risques sont affichés mais ne sont valides que si les proportions par ligne estiment des risques (cohorte, essai, transversal). En cas-témoins, seul l'OR est interprétable.",
            'Study design not specified: RR and risk difference are shown but are valid only if row proportions estimate risks (cohort, trial, cross-sectional). In a case-control study, only the OR is interpretable.'),
        suggestion: tr("Préciser le plan d'étude dans le projet.", 'Specify the study design in the project.')));
  }
  final overall = (a + c) / total;
  if (riskAllowed && overall > 0.1) {
    alerts.add(Alert('or_rr_divergence', Severity.caution,
        tr("Issue fréquente (${fmtPct(overall)}) : l'OR (${fmt(or)}) s'éloigne du RR (${fmt(rrE!.value)}). Ne pas présenter l'OR comme un risque relatif.",
            'Common outcome (${fmtPct(overall)}): the OR (${fmt(or)}) diverges from the RR (${fmt(rrE.value)}). Do not present the OR as a risk ratio.')));
  }
  final events = math.min(a + c, b + d);
  if (events < 10) {
    alerts.add(Alert('rare_events', Severity.caution,
        tr('Seulement $events événement(s) dans la catégorie la plus rare : estimations imprécises.', 'Only $events event(s) in the rarest category: imprecise estimates.')));
  }

  final primaryP = smallExpected ? fisher.pValue : chi.p;
  final primary = riskAllowed ? rrE! : orE;
  final nullText = readInterval(primary, nullValue: 1, ratio: true);
  return AnalysisResult(
    methodId: 'two_by_two',
    methodName: tr("Tableau 2 × 2 : mesures d'association", '2 × 2 table: measures of association'),
    inputs: {'a': a, 'b': b, 'c': c, 'd': d, 'design': design.name, 'level': level, 'exposure': exposure, 'outcome': outcome},
    formula: tr(
        'RR = [a/(a+b)] / [c/(c+d)], ES(ln RR) = √(1/a − 1/(a+b) + 1/c − 1/(c+d)) ; OR = ad/bc, ES(ln OR) = √(1/a + 1/b + 1/c + 1/d) (Woolf) ; '
            'DR = a/(a+b) − c/(c+d), IC de Newcombe ; χ² de Pearson ; test exact de Fisher (loi hypergéométrique, OR conditionnel par maximum de vraisemblance).',
        'RR = [a/(a+b)] / [c/(c+d)], SE(ln RR) = √(1/a − 1/(a+b) + 1/c − 1/(c+d)); OR = ad/bc, SE(ln OR) = √(1/a + 1/b + 1/c + 1/d) (Woolf); '
            'RD = a/(a+b) − c/(c+d), Newcombe CI; Pearson χ²; Fisher exact test (hypergeometric distribution, conditional maximum likelihood OR).'),
    estimates: estimates,
    statistics: {
      'chi2': chi.statistic,
      'chi2_df': 1,
      'chi2_p': chi.p,
      'chi2_yates': chiY.statistic,
      'chi2_yates_p': chiY.p,
      'fisher_p': fisher.pValue,
      'min_expected': minExp,
      'risk_exposed': r1,
      'risk_unexposed': r0,
      'p_primary': primaryP,
    },
    checks: checks,
    alerts: alerts,
    tables: [
      ResultTable(tr('Tableau de contingence', 'Contingency table'), [
        exposure,
        outcome,
        tr("Pas d'événement", 'No event'),
        'Total',
        if (riskAllowed) tr('Risque', 'Risk')
      ], [
        [tr('Exposés', 'Exposed'), '$a', '$b', '$n1', if (riskAllowed) fmtPct(r1)],
        [tr('Non exposés', 'Unexposed'), '$c', '$d', '$n0', if (riskAllowed) fmtPct(r0)],
        ['Total', '${a + c}', '${b + d}', '$total', if (riskAllowed) fmtPct(overall)],
      ]),
      ResultTable(tr('Mesures', 'Measures'), [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('IC ${(level * 100).round()} %', '${(level * 100).round()}% CI')],
          [for (final e in estimates) [e.label, fmt(e.value), '${fmt(e.lower)} – ${fmt(e.upper)}']]),
    ],
    log: [
      ...log,
      tr('Test principal : ${smallExpected ? "exact de Fisher (effectif attendu < 5)" : "χ² de Pearson sans correction"}, ${fmtP(primaryP)}.',
          'Main test: ${smallExpected ? "Fisher exact (expected count < 5)" : "Pearson χ² without correction"}, ${fmtP(primaryP)}.')
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Deux variables binaires indépendantes (exposition, issue). La mesure d'effet dépend du plan : RR/DR en cohorte ou essai, rapport de prévalences en transversal, OR seulement en cas-témoins.",
          'Two independent binary variables (exposure, outcome). The effect measure depends on the design: RR/RD in a cohort or trial, prevalence ratio in a cross-sectional study, OR only in a case-control study.'),
      whatItMeans: '${primary.label} = ${fmtCi(primary)}, ${fmtP(primaryP)}. $nullText',
      notJustified: tr("Une association brute n'est pas un effet causal : confusion, biais de sélection et de mesure ne sont pas pris en compte. ",
              'A crude association is not a causal effect: confounding, selection and measurement bias are not accounted for. ') +
          (riskAllowed ? '' : tr("En cas-témoins, l'OR n'est pas un risque relatif. ", 'In a case-control study, the OR is not a risk ratio. ')) +
          pValueCaveat,
    ),
  );
}
