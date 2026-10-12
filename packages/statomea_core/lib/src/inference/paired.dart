/// Analyses appariées : t apparié, Wilcoxon signé, McNemar.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../descriptive/descriptive.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import 'common.dart';
import 'proportion.dart';
import 'rank_distributions.dart';

/// Extrait les paires complètes et rapporte les paires incomplètes.
({List<double> d, int incomplete}) _pairs(List<double?> before, List<double?> after) {
  if (before.length != after.length) {
    throw StatInputError('unpaired_lengths',
        tr("Les deux séries n'ont pas la même longueur (${before.length} vs ${after.length}) : les observations ne sont pas appariées ligne à ligne.",
            'The two series do not have the same length (${before.length} vs ${after.length}): the observations are not paired row by row.'));
  }
  final d = <double>[];
  var inc = 0;
  for (var i = 0; i < before.length; i++) {
    final a = before[i], b = after[i];
    if (a == null || b == null || !a.isFinite || !b.isFinite) {
      inc++;
    } else {
      d.add(a - b);
    }
  }
  return (d: d, incomplete: inc);
}

/// Test t apparié sur les différences x − y.
AnalysisResult pairedTTest(List<double?> x, List<double?> y,
    {double level = 0.95, String? label1, String? label2, String unit = '', double? margin}) {
  label1 ??= tr('Mesure 1', 'Measurement 1');
  label2 ??= tr('Mesure 2', 'Measurement 2');
  final pr = _pairs(x, y);
  final d = pr.d;
  if (d.length < 2) throw StatInputError('n_too_small', tr('Au moins 2 paires complètes sont requises.', 'At least 2 complete pairs are required.'));
  final n = d.length.toDouble();
  final md = mean(d), s = sd(d);
  final se = s / math.sqrt(n);
  final t = md / se;
  final df = n - 1;
  final p = tTwoSidedP(t, df);
  final q = tQuantile(1 - (1 - level) / 2, df);
  final e = Estimate(tr('Différence moyenne appariée ($label1 − $label2)', 'Mean paired difference ($label1 − $label2)'), md,
      lower: md - q * se, upper: md + q * se, level: level, pValue: p, se: se);
  final skew = summarize(d).skewness;
  final u = unit.isEmpty ? '' : ' $unit';
  return AnalysisResult(
    methodId: 'paired_t_test',
    methodName: tr('Test t apparié', 'Paired t-test'),
    inputs: {'pairs': d.length, 'incomplete_pairs': pr.incomplete, 'level': level},
    formula: tr('d_i = x_i − y_i ; t = d̄ / (s_d/√n) ; ddl = n − 1.', 'd_i = x_i − y_i; t = d̄ / (s_d/√n); df = n − 1.'),
    estimates: [e, Estimate(tr('ÉT des différences', 'SD of differences'), s)],
    statistics: {'t': t, 'df': df, 'p': p},
    checks: [
      Check('normality_diff', tr('Différences approximativement normales', 'Approximately normal differences'),
          (skew.isFinite && skew.abs() > 1 && n < 30) ? CheckStatus.warning : CheckStatus.ok,
          tr('Asymétrie des différences = ${fmt(skew)}, n = ${d.length}.', 'Skewness of differences = ${fmt(skew)}, n = ${d.length}.')),
    ],
    alerts: [
      if (pr.incomplete > 0)
        Alert('incomplete_pairs', Severity.caution,
            tr('${pr.incomplete} paire(s) incomplète(s) exclue(s).', '${pr.incomplete} incomplete pair(s) excluded.'),
            suggestion: tr("Vérifier que l'exclusion n'est pas liée à l'évolution mesurée.", 'Check that the exclusion is not related to the change being measured.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr("Deux mesures quantitatives sur les mêmes sujets : l'appariement retire la variabilité entre sujets ; un test pour groupes indépendants serait incorrect.",
          'Two quantitative measurements on the same subjects: pairing removes between-subject variability; a test for independent groups would be incorrect.'),
      whatItMeans: tr('Différence moyenne = ${fmtCi(e)}$u, ${fmtP(p)}. ', 'Mean difference = ${fmtCi(e)}$u, ${fmtP(p)}. ') + readInterval(e, nullValue: 0, margin: margin, unit: u),
      notJustified: tr("Attribuer le changement à une intervention en l'absence de groupe témoin (régression vers la moyenne, évolution naturelle).",
          'Attributing the change to an intervention without a control group (regression to the mean, natural course).'),
    ),
  );
}

/// Test signé des rangs de Wilcoxon (algorithme de R `wilcox.test(paired = TRUE)`).
AnalysisResult wilcoxonSignedRank(List<double?> x, List<double?> y, {bool? exact}) {
  final pr = _pairs(x, y);
  final nonZero = [for (final v in pr.d) if (v != 0) v];
  final zeros = pr.d.length - nonZero.length;
  final n = nonZero.length;
  if (n == 0) throw StatInputError('all_zero', tr('Toutes les différences sont nulles.', 'All differences are zero.'));
  final rk = rankWithTies([for (final v in nonZero) v.abs()]);
  var v = 0.0;
  for (var i = 0; i < n; i++) {
    if (nonZero[i] > 0) v += rk.ranks[i];
  }
  final hasTies = rk.tieSizes.isNotEmpty;
  final useExact = (exact ?? n < 50) && !hasTies && zeros == 0;
  double p;
  if (useExact) {
    final vi = v.round();
    final pp = v > n * (n + 1) / 4 ? 1 - pSignRank(vi - 1, n) : pSignRank(vi, n);
    p = math.min(1.0, 2 * pp);
  } else {
    final tieSum = rk.tieSizes.fold<double>(0, (a, t) => a + (t * t * t - t).toDouble());
    final sigma = math.sqrt(n * (n + 1) * (2 * n + 1) / 24 - tieSum / 48);
    final zRaw = v - n * (n + 1) / 4;
    final corr = zRaw == 0 ? 0 : (zRaw > 0 ? 0.5 : -0.5);
    p = normalTwoSidedP((zRaw - corr) / sigma);
  }
  return AnalysisResult(
    methodId: 'wilcoxon_signed_rank',
    methodName: tr('Test signé des rangs de Wilcoxon', 'Wilcoxon signed-rank test'),
    inputs: {'pairs': pr.d.length, 'zero_differences': zeros, 'incomplete_pairs': pr.incomplete, 'exact': useExact},
    formula: tr('V = somme des rangs des |d_i| pour d_i > 0 (différences nulles exclues). ${useExact ? "Loi exacte." : "Approximation normale avec corrections de continuité et d'ex aequo."}',
        'V = sum of ranks of |d_i| for d_i > 0 (zero differences excluded). ${useExact ? "Exact distribution." : "Normal approximation with continuity and tie corrections."}'),
    estimates: [Estimate(tr('Médiane des différences', 'Median of differences'), median(pr.d), pValue: p)],
    statistics: {'V': v, 'p': p},
    alerts: [
      if (zeros > 0)
        Alert('zero_diffs', Severity.info, tr('$zeros différence(s) nulle(s) exclue(s) du calcul de V.', '$zeros zero difference(s) excluded from the computation of V.')),
      if (pr.incomplete > 0)
        Alert('incomplete_pairs', Severity.caution, tr('${pr.incomplete} paire(s) incomplète(s) exclue(s).', '${pr.incomplete} incomplete pair(s) excluded.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Mesures appariées dont les différences ne sont pas normales (petit effectif, asymétrie) ou données ordinales.',
          'Paired measurements whose differences are not normal (small sample, skewness) or ordinal data.'),
      whatItMeans: tr('V = ${fmt(v)}, ${fmtP(p)} ; médiane des différences ${fmt(median(pr.d))}.', 'V = ${fmt(v)}, ${fmtP(p)}; median of differences ${fmt(median(pr.d))}.'),
      notJustified: tr("Quantifier l'ampleur du changement à partir de la seule valeur de p.", 'Quantifying the size of the change from the p-value alone.'),
    ),
  );
}

/// Test de McNemar sur les paires discordantes [b] (oui → non) et [c]
/// (non → oui), avec version exacte binomiale et OR apparié.
AnalysisResult mcNemar(int a, int b, int c, int d, {double level = 0.95, bool exactOnly = false}) {
  if ([a, b, c, d].any((v) => v < 0)) throw StatInputError('negative_count', tr('Effectifs négatifs.', 'Negative counts.'));
  final disc = b + c;
  if (disc == 0) {
    throw StatInputError('no_discordant',
        tr("Aucune paire discordante : le test de McNemar n'est pas calculable (aucune information sur la différence).",
            "No discordant pair: McNemar's test cannot be computed (no information on the difference)."));
  }
  final x2 = math.pow((b - c).abs() - 1, 2) / disc;
  final pAsym = chiSquareUpper(x2.toDouble(), 1);
  final pExact = binomialTestTwoSided(b, disc, 0.5);
  final cp = clopperPearsonCi(b, disc, level: level);
  final orP = c == 0 ? double.infinity : b / c;
  final orE = Estimate(tr('OR apparié (b/c)', 'Paired OR (b/c)'), orP,
      lower: cp.lower / (1 - cp.lower), upper: cp.upper >= 1 ? double.infinity : cp.upper / (1 - cp.upper), level: level);
  final n = a + b + c + d;
  final usedExact = exactOnly || disc < 25;
  final p = usedExact ? pExact : pAsym;
  return AnalysisResult(
    methodId: 'mcnemar',
    methodName: tr('Test de McNemar (données binaires appariées)', "McNemar's test (paired binary data)"),
    inputs: {'a': a, 'b': b, 'c': c, 'd': d, 'level': level},
    formula: tr('χ² = (|b − c| − 1)² / (b + c) ; version exacte : test binomial de b parmi b + c sous p = 0,5 ; OR apparié = b/c, IC exact via Clopper-Pearson sur b/(b+c).',
        'χ² = (|b − c| − 1)² / (b + c); exact version: binomial test of b among b + c under p = 0.5; paired OR = b/c, exact CI via Clopper-Pearson on b/(b+c).'),
    estimates: [
      orE,
      Estimate(tr('Différence de proportions appariées', 'Difference in paired proportions'), (b - c) / n),
    ],
    statistics: {'chi2': x2.toDouble(), 'p_asymptotic': pAsym, 'p_exact': pExact, 'p': p, 'discordant': disc.toDouble()},
    checks: [
      Check('discordant', tr("Paires discordantes ≥ 25 pour l'approximation du χ²", 'Discordant pairs ≥ 25 for the χ² approximation'),
          disc < 25 ? CheckStatus.warning : CheckStatus.ok,
          tr('$disc paires discordantes ; ${usedExact ? "version exacte retenue" : "χ² avec correction de continuité retenu"}.',
              '$disc discordant pairs; ${usedExact ? "exact version used" : "χ² with continuity correction used"}.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Variable binaire mesurée deux fois sur les mêmes sujets (avant/après, deux tests sur le même prélèvement) : seules les paires discordantes sont informatives.',
          'Binary variable measured twice on the same subjects (before/after, two tests on the same sample): only discordant pairs are informative.'),
      whatItMeans: tr('$b paires passent de « oui » à « non » contre $c en sens inverse ; OR apparié = ${fmtCi(orE)}, ${fmtP(p)}.',
          '$b pairs go from "yes" to "no" versus $c the other way; paired OR = ${fmtCi(orE)}, ${fmtP(p)}.'),
      notJustified: tr('Utiliser un χ² ou un Fisher pour groupes indépendants sur des données appariées.', "Using a χ² or Fisher's test for independent groups on paired data."),
    ),
  );
}
