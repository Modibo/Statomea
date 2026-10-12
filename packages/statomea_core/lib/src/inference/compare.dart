/// Comparaisons de groupes indépendants : t de Student / Welch, Mann-Whitney,
/// ANOVA à un facteur (classique et de Welch), Kruskal-Wallis, χ² r × c.
library;

import 'dart:math' as math;

import '../descriptive/descriptive.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import 'common.dart';
import 'posthoc.dart';
import 'rank_distributions.dart';

Check _normalityCheck(String name, List<double> x) {
  if (x.length < 3) {
    return Check('normality_$name', tr('Distribution approximativement normale ($name)', 'Approximately normal distribution ($name)'),
        CheckStatus.notAssessed, tr('Moins de 3 valeurs.', 'Fewer than 3 values.'));
  }
  final s = summarize(x);
  final skew = s.skewness;
  final big = x.length >= 30;
  final status = skew.isNaN
      ? CheckStatus.notAssessed
      : (skew.abs() > 2 || (!big && skew.abs() > 1))
          ? CheckStatus.warning
          : CheckStatus.ok;
  return Check(
      'normality_$name',
      tr('Distribution approximativement normale ou n suffisant ($name)', 'Approximately normal distribution or sufficient n ($name)'),
      status,
      tr('n = ${x.length}, asymétrie = ${fmt(skew)}. ${big ? "Avec n ≥ 30, le théorème central limite rend le test t robuste à une asymétrie modérée." : "Petit effectif : la normalité compte ; examiner le graphique quantile-quantile."}',
          'n = ${x.length}, skewness = ${fmt(skew)}. ${big ? "With n ≥ 30, the central limit theorem makes the t-test robust to moderate skewness." : "Small sample: normality matters; inspect the quantile-quantile plot."}'));
}

/// Test t pour deux groupes indépendants. [welch] = vrai par défaut
/// (variances non supposées égales), comme recommandé.
AnalysisResult tTestIndependent(List<double?> x1raw, List<double?> x2raw,
    {bool welch = true,
    double level = 0.95,
    String? group1,
    String? group2,
    String unit = '',
    double? margin}) {
  group1 ??= tr('Groupe 1', 'Group 1');
  group2 ??= tr('Groupe 2', 'Group 2');
  final x1 = finiteValues(x1raw), x2 = finiteValues(x2raw);
  if (x1.length < 2 || x2.length < 2) {
    throw StatInputError('n_too_small', tr('Chaque groupe doit compter au moins 2 valeurs.', 'Each group must have at least 2 values.'));
  }
  final n1 = x1.length.toDouble(), n2 = x2.length.toDouble();
  final m1 = mean(x1), m2 = mean(x2), v1 = variance(x1), v2 = variance(x2);
  final diff = m1 - m2;
  double se, df;
  if (welch) {
    se = math.sqrt(v1 / n1 + v2 / n2);
    df = math.pow(v1 / n1 + v2 / n2, 2) /
        (math.pow(v1 / n1, 2) / (n1 - 1) + math.pow(v2 / n2, 2) / (n2 - 1));
  } else {
    df = n1 + n2 - 2;
    final vp = ((n1 - 1) * v1 + (n2 - 1) * v2) / df;
    se = math.sqrt(vp * (1 / n1 + 1 / n2));
  }
  final t = diff / se;
  final p = tTwoSidedP(t, df);
  final q = tQuantile(1 - (1 - level) / 2, df);
  final e = Estimate(tr('Différence de moyennes ($group1 − $group2)', 'Difference in means ($group1 − $group2)'), diff,
      lower: diff - q * se, upper: diff + q * se, level: level, pValue: p, se: se);
  // Taille d'effet : g de Hedges (écart-type poolé, correction de petit échantillon).
  final sp = math.sqrt(((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2));
  final dCohen = diff / sp;
  final j = 1 - 3 / (4 * (n1 + n2) - 9);
  final g = dCohen * j;
  final seG = math.sqrt((n1 + n2) / (n1 * n2) + g * g / (2 * (n1 + n2)));
  final zq = normalQuantile(1 - (1 - level) / 2);
  final gE = Estimate(tr('g de Hedges', "Hedges' g"), g, lower: g - zq * seG, upper: g + zq * seG, level: level);
  final ratio = math.max(v1, v2) / math.min(v1, v2);
  final u = unit.isEmpty ? '' : ' $unit';
  return AnalysisResult(
    methodId: welch ? 't_test_welch' : 't_test_student',
    methodName: welch ? tr('Test t de Welch (groupes indépendants)', "Welch's t-test (independent groups)") : tr('Test t de Student (variances égales)', "Student's t-test (equal variances)"),
    inputs: {'n1': x1.length, 'n2': x2.length, 'welch': welch, 'level': level,
      'missing1': x1raw.length - x1.length, 'missing2': x2raw.length - x2.length},
    formula: welch
        ? tr('t = (x̄1 − x̄2) / √(s1²/n1 + s2²/n2) ; ddl de Welch-Satterthwaite.', 't = (x̄1 − x̄2) / √(s1²/n1 + s2²/n2); Welch-Satterthwaite df.')
        : tr('t = (x̄1 − x̄2) / [sp √(1/n1 + 1/n2)], sp² = [(n1−1)s1² + (n2−1)s2²]/(n1+n2−2) ; ddl = n1+n2−2.',
            't = (x̄1 − x̄2) / [sp √(1/n1 + 1/n2)], sp² = [(n1−1)s1² + (n2−1)s2²]/(n1+n2−2); df = n1+n2−2.'),
    estimates: [
      e,
      gE,
      Estimate(tr('Moyenne $group1', 'Mean $group1'), m1),
      Estimate(tr('Moyenne $group2', 'Mean $group2'), m2),
    ],
    statistics: {'t': t, 'df': df, 'p': p, 'sd1': math.sqrt(v1), 'sd2': math.sqrt(v2), 'variance_ratio': ratio},
    checks: [
      _normalityCheck(group1, x1),
      _normalityCheck(group2, x2),
      Check(
          'equal_variance',
          tr('Variances comparables', 'Comparable variances'),
          welch
              ? CheckStatus.ok
              : (ratio > 4 ? CheckStatus.violated : (ratio > 2 ? CheckStatus.warning : CheckStatus.ok)),
          tr('Rapport des variances = ${fmt(ratio)}. ${welch ? "Le test de Welch ne suppose pas l'égalité des variances." : "Si le rapport dépasse 2 à 4, préférer Welch."}',
              'Variance ratio = ${fmt(ratio)}. ${welch ? "Welch's test does not assume equal variances." : "If the ratio exceeds 2 to 4, prefer Welch."}')),
      Check('independence', tr('Groupes indépendants', 'Independent groups'), CheckStatus.notAssessed,
          tr("Un sujet ne doit appartenir qu'à un groupe ; mesures répétées = test apparié.", 'A subject must belong to only one group; repeated measures = paired test.')),
    ],
    alerts: [
      if (!welch && ratio > 2)
        Alert('unequal_variance', Severity.caution,
            tr('Variances inégales (rapport ${fmt(ratio)}) avec le test de Student.', "Unequal variances (ratio ${fmt(ratio)}) with Student's test."),
            suggestion: tr('Utiliser le test de Welch.', "Use Welch's test.")),
    ],
    tables: [
      ResultTable(tr('Groupes', 'Groups'), [tr('Groupe', 'Group'), 'n', tr('Moyenne', 'Mean'), tr('ÉT', 'SD')], [
        [group1, '${x1.length}', fmt(m1), fmt(math.sqrt(v1))],
        [group2, '${x2.length}', fmt(m2), fmt(math.sqrt(v2))],
      ])
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Variable quantitative, deux groupes indépendants, objectif : comparer les moyennes. ${welch ? "Welch est robuste à l'inégalité des variances et perd très peu quand elles sont égales." : ""}',
          'Quantitative variable, two independent groups, aim: compare means. ${welch ? "Welch is robust to unequal variances and loses very little when they are equal." : ""}'),
      whatItMeans: tr('Différence de moyennes = ${fmtCi(e)}$u, ${fmtP(p)}. ', 'Difference in means = ${fmtCi(e)}$u, ${fmtP(p)}. ') +
          readInterval(e, nullValue: 0, margin: margin, unit: u),
      notJustified: tr(
          "Interpréter p comme la probabilité que les groupes soient identiques ; conclure à l'absence de différence parce que p > 0,05 ; attribuer la différence au facteur de groupe dans une étude observationnelle.",
          'Interpreting p as the probability that the groups are identical; concluding there is no difference because p > 0.05; attributing the difference to the grouping factor in an observational study.'),
    ),
  );
}

/// Test de Mann-Whitney (Wilcoxon de la somme des rangs), algorithme de R
/// `wilcox.test` : loi exacte si n1, n2 < 50 et pas d'ex aequo, sinon
/// approximation normale avec correction de continuité et d'ex aequo.
AnalysisResult mannWhitney(List<double?> x1raw, List<double?> x2raw,
    {String? group1, String? group2, bool? exact}) {
  group1 ??= tr('Groupe 1', 'Group 1');
  group2 ??= tr('Groupe 2', 'Group 2');
  final x1 = finiteValues(x1raw), x2 = finiteValues(x2raw);
  if (x1.isEmpty || x2.isEmpty) {
    throw StatInputError('n_too_small', tr('Chaque groupe doit compter au moins une valeur.', 'Each group must have at least one value.'));
  }
  final n1 = x1.length, n2 = x2.length;
  final rk = rankWithTies([...x1, ...x2]);
  var r1 = 0.0;
  for (var i = 0; i < n1; i++) {
    r1 += rk.ranks[i];
  }
  final w = r1 - n1 * (n1 + 1) / 2;
  final hasTies = rk.tieSizes.isNotEmpty;
  final useExact = (exact ?? (n1 < 50 && n2 < 50)) && !hasTies;
  double p;
  double? z;
  if (useExact) {
    final wi = w.round();
    final pp = w > n1 * n2 / 2 ? 1 - pWilcox(wi - 1, n1, n2) : pWilcox(wi, n1, n2);
    p = math.min(1.0, 2 * pp);
  } else {
    final nn = (n1 + n2).toDouble();
    final tieSum = rk.tieSizes.fold<double>(0, (a, t) => a + (t * t * t - t).toDouble());
    final sigma = math.sqrt((n1 * n2 / 12) * ((nn + 1) - tieSum / (nn * (nn - 1))));
    final zRaw = w - n1 * n2 / 2;
    final corr = zRaw == 0 ? 0 : (zRaw > 0 ? 0.5 : -0.5);
    z = (zRaw - corr) / sigma;
    p = normalTwoSidedP(z);
  }
  final ps = w / (n1 * n2);
  final s1 = [...x1]..sort();
  final s2 = [...x2]..sort();
  return AnalysisResult(
    methodId: 'mann_whitney',
    methodName: tr('Test de Mann-Whitney (somme des rangs de Wilcoxon)', 'Mann-Whitney test (Wilcoxon rank-sum)'),
    inputs: {'n1': n1, 'n2': n2, 'exact': useExact},
    formula: tr('W = R1 − n1(n1+1)/2 (R1 = somme des rangs du groupe 1). ${useExact ? "Loi exacte de W (dénombrement)." : "z = (W − n1n2/2 ± 0,5)/σ, σ corrigé des ex aequo."}',
        'W = R1 − n1(n1+1)/2 (R1 = sum of ranks of group 1). ${useExact ? "Exact distribution of W (enumeration)." : "z = (W − n1n2/2 ± 0.5)/σ, σ corrected for ties."}'),
    estimates: [
      Estimate(tr('Probabilité de supériorité P($group1 > $group2)', 'Probability of superiority P($group1 > $group2)'), ps, pValue: p),
      Estimate(tr('Médiane $group1', 'Median $group1'), quantile(s1, 0.5)),
      Estimate(tr('Médiane $group2', 'Median $group2'), quantile(s2, 0.5)),
    ],
    statistics: {'W': w, 'p': p, 'z': ?z},
    checks: [
      Check('independence', tr('Groupes indépendants', 'Independent groups'), CheckStatus.notAssessed,
          tr("Un sujet ne doit appartenir qu'à un groupe.", 'A subject must belong to only one group.')),
      Check('ties', tr("Peu d'ex aequo", 'Few ties'), hasTies ? CheckStatus.warning : CheckStatus.ok,
          hasTies ? tr('Ex aequo présents : p par approximation normale corrigée.', 'Ties present: p from the corrected normal approximation.') : tr('Aucun ex aequo.', 'No ties.')),
    ],
    alerts: [
      if (exact == true && hasTies)
        Alert('exact_ties', Severity.info,
            tr('Loi exacte demandée mais ex aequo présents : approximation normale utilisée.', 'Exact distribution requested but ties present: normal approximation used.')),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Variable ordinale ou quantitative non normale (petits effectifs, asymétrie), deux groupes indépendants.',
          'Ordinal or non-normal quantitative variable (small samples, skewness), two independent groups.'),
      whatItMeans: tr("La probabilité qu'une valeur tirée au hasard dans $group1 dépasse une valeur tirée dans $group2 est estimée à ${fmt(ps)} (0,5 = aucune tendance), ${fmtP(p)}.",
          'The probability that a random value from $group1 exceeds a random value from $group2 is estimated at ${fmt(ps)} (0.5 = no tendency), ${fmtP(p)}.'),
      notJustified: tr('Présenter ce test comme une « comparaison des médianes » : il compare des distributions et ne teste les médianes que si les formes sont identiques.',
          'Presenting this test as a "comparison of medians": it compares distributions and tests medians only if the shapes are identical.'),
    ),
  );
}

/// ANOVA à un facteur (classique) et ANOVA de Welch (`oneway.test`).
AnalysisResult anovaOneWay(Map<String, List<double?>> groupsRaw, {bool welch = false}) {
  final groups = {for (final e in groupsRaw.entries) e.key: finiteValues(e.value)};
  if (groups.length < 2 || groups.values.any((g) => g.length < 2)) {
    throw StatInputError('n_too_small', tr('Au moins 2 groupes de 2 valeurs ou plus sont requis.', 'At least 2 groups of 2 or more values are required.'));
  }
  final k = groups.length.toDouble();
  final all = groups.values.expand((g) => g).toList();
  final grand = mean(all);
  final n = all.length.toDouble();
  var ssb = 0.0, ssw = 0.0;
  for (final g in groups.values) {
    final m = mean(g);
    ssb += g.length * (m - grand) * (m - grand);
    for (final v in g) {
      ssw += (v - m) * (v - m);
    }
  }
  final eta2 = ssb / (ssb + ssw);
  double f, df1, df2;
  if (!welch) {
    df1 = k - 1;
    df2 = n - k;
    f = (ssb / df1) / (ssw / df2);
  } else {
    final w = [for (final g in groups.values) g.length / variance(g)];
    final m = [for (final g in groups.values) mean(g)];
    final sw = w.fold(0.0, (a, b) => a + b);
    var mw = 0.0;
    for (var i = 0; i < w.length; i++) {
      mw += w[i] * m[i];
    }
    mw /= sw;
    var num = 0.0, tmp = 0.0;
    final ns = [for (final g in groups.values) g.length];
    for (var i = 0; i < w.length; i++) {
      num += w[i] * (m[i] - mw) * (m[i] - mw);
      tmp += math.pow(1 - w[i] / sw, 2) / (ns[i] - 1);
    }
    tmp /= (k * k - 1);
    df1 = k - 1;
    df2 = 1 / (3 * tmp);
    f = num / (df1 * (1 + 2 * (k - 2) * tmp));
  }
  final p = fUpper(f, df1, df2);
  // Comparaisons deux à deux dès 3 groupes : Tukey (variances égales) ou Games-Howell (Welch).
  final post = k >= 3 ? (welch ? gamesHowell(groups) : tukeyHsd(groups)) : const <Pairwise>[];
  final postName = welch ? 'Games-Howell' : 'Tukey HSD';
  final sds = [for (final g in groups.values) sd(g)];
  final ratio = math.pow(sds.reduce(math.max) / sds.reduce(math.min), 2).toDouble();
  return AnalysisResult(
    methodId: welch ? 'anova_welch' : 'anova_oneway',
    methodName: welch ? tr('ANOVA de Welch à un facteur', "Welch's one-way ANOVA") : tr('ANOVA à un facteur', 'One-way ANOVA'),
    inputs: {'groups': {for (final e in groups.entries) e.key: e.value.length}, 'welch': welch},
    formula: welch
        ? tr('F de Welch avec poids w_i = n_i/s_i² (Welch 1951).', 'Welch F with weights w_i = n_i/s_i² (Welch 1951).')
        : tr('F = [SCE inter/(k−1)] / [SCE intra/(N−k)] ; η² = SCE inter / SCE totale.', 'F = [SS between/(k−1)] / [SS within/(N−k)]; η² = SS between / SS total.') +
            (post.isEmpty
                ? ''
                : tr(' Comparaisons : $postName, q = |x̄j − x̄i| / ES, p et IC simultanés par la loi de l\'étendue studentisée.',
                    ' Comparisons: $postName, q = |x̄j − x̄i| / SE, p and simultaneous CIs from the studentized range distribution.')),
    estimates: [
      Estimate(tr('η² (part de variance expliquée par le groupe)', 'η² (share of variance explained by group)'), eta2),
      for (final e in groups.entries) Estimate(tr('Moyenne ${e.key}', 'Mean ${e.key}'), mean(e.value)),
    ],
    statistics: {
      'F': f,
      'df1': df1,
      'df2': df2,
      'p': p,
      'eta2': eta2,
      'variance_ratio_max': ratio,
      for (final x in post) 'posthoc_p_${x.group1}_${x.group2}': x.pFinal,
    },
    alerts: [if (post.isNotEmpty) _posthocAlert()],
    checks: [
      for (final e in groups.entries) _normalityCheck(e.key, e.value),
      Check('equal_variance', tr('Variances comparables', 'Comparable variances'), welch ? CheckStatus.ok : (ratio > 4 ? CheckStatus.violated : CheckStatus.ok),
          tr('Rapport variance max/min = ${fmt(ratio)}.', 'Max/min variance ratio = ${fmt(ratio)}.')),
    ],
    tables: [
      ResultTable(tr('Groupes', 'Groups'), [tr('Groupe', 'Group'), 'n', tr('Moyenne', 'Mean'), tr('ÉT', 'SD')],
          [for (final e in groups.entries) [e.key, '${e.value.length}', fmt(mean(e.value)), fmt(sd(e.value))]]),
      if (post.isNotEmpty) pairwiseTable(tr('Comparaisons deux à deux ($postName)', 'Pairwise comparisons ($postName)'), post, interval: true),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Variable quantitative, plus de deux groupes indépendants.', 'Quantitative variable, more than two independent groups.') +
          (post.isEmpty
              ? ''
              : (welch
                  ? tr(' Games-Howell compare les paires sans supposer l\'égalité des variances.', ' Games-Howell compares pairs without assuming equal variances.')
                  : tr(' Tukey HSD compare toutes les paires en contrôlant le risque global d\'erreur.', ' Tukey HSD compares all pairs while controlling the family-wise error rate.'))),
      whatItMeans: tr('F(${fmt(df1)} ; ${fmt(df2)}) = ${fmt(f)}, ${fmtP(p)}. Le facteur de groupe explique ${fmtPct(eta2)} de la variance observée.',
              'F(${fmt(df1)}; ${fmt(df2)}) = ${fmt(f)}, ${fmtP(p)}. The grouping factor explains ${fmtPct(eta2)} of the observed variance.') +
          (post.isEmpty ? '' : ' ${pairwiseSummary(post)}'),
      notJustified: post.isEmpty
          ? tr("Désigner quels groupes diffèrent : l'ANOVA globale ne le dit pas ; des comparaisons deux à deux exigent une correction pour la multiplicité.",
              'Naming which groups differ: the global ANOVA does not say; pairwise comparisons require a multiplicity correction.')
          : _posthocNotJustified(),
    ),
  );
}

/// Test de Kruskal-Wallis (correction des ex aequo, loi du χ²).
AnalysisResult kruskalWallis(Map<String, List<double?>> groupsRaw) {
  final groups = {for (final e in groupsRaw.entries) e.key: finiteValues(e.value)};
  if (groups.length < 2 || groups.values.any((g) => g.isEmpty)) {
    throw StatInputError('n_too_small', tr('Au moins 2 groupes non vides sont requis.', 'At least 2 non-empty groups are required.'));
  }
  final all = groups.values.expand((g) => g).toList();
  final n = all.length.toDouble();
  final rk = rankWithTies(all);
  var h = 0.0, idx = 0;
  for (final g in groups.values) {
    var r = 0.0;
    for (var i = 0; i < g.length; i++) {
      r += rk.ranks[idx++];
    }
    h += r * r / g.length;
  }
  h = 12 / (n * (n + 1)) * h - 3 * (n + 1);
  final tieSum = rk.tieSizes.fold<double>(0, (a, t) => a + (t * t * t - t).toDouble());
  h /= 1 - tieSum / (n * n * n - n);
  final df = groups.length - 1.0;
  final p = chiSquareUpper(h, df);
  final post = groups.length >= 3 ? dunnHolm(groups) : const <Pairwise>[];
  return AnalysisResult(
    methodId: 'kruskal_wallis',
    methodName: tr('Test de Kruskal-Wallis', 'Kruskal-Wallis test'),
    inputs: {'groups': {for (final e in groups.entries) e.key: e.value.length}},
    formula: tr('H = 12/[N(N+1)] Σ R_i²/n_i − 3(N+1), corrigé des ex aequo ; H ~ χ²(k−1).', 'H = 12/[N(N+1)] Σ R_i²/n_i − 3(N+1), corrected for ties; H ~ χ²(k−1).') +
        (post.isEmpty
            ? ''
            : tr(' Comparaisons : test de Dunn, z = (R̄j − R̄i) / √{[N(N+1)/12 − Σ(t³−t)/(12(N−1))](1/ni + 1/nj)}, p ajustés par Holm.',
                ' Comparisons: Dunn\'s test, z = (R̄j − R̄i) / √{[N(N+1)/12 − Σ(t³−t)/(12(N−1))](1/ni + 1/nj)}, p adjusted by Holm.')),
    estimates: [for (final e in groups.entries) Estimate(tr('Médiane ${e.key}', 'Median ${e.key}'), median(e.value))],
    statistics: {'H': h, 'df': df, 'p': p, for (final x in post) 'posthoc_p_${x.group1}_${x.group2}': x.pFinal},
    alerts: [if (post.isNotEmpty) _posthocAlert()],
    tables: [
      if (post.isNotEmpty) pairwiseTable(tr('Comparaisons deux à deux (Dunn, Holm)', 'Pairwise comparisons (Dunn, Holm)'), post, interval: false, statName: 'z'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Variable ordinale ou quantitative non normale, plus de deux groupes indépendants.', 'Ordinal or non-normal quantitative variable, more than two independent groups.'),
      whatItMeans: tr('H = ${fmt(h)} (ddl ${fmt(df)}), ${fmtP(p)}.', 'H = ${fmt(h)} (df ${fmt(df)}), ${fmtP(p)}.') + (post.isEmpty ? '' : ' ${pairwiseSummary(post)}'),
      notJustified: post.isEmpty
          ? tr('Identifier les groupes qui diffèrent sans comparaisons post hoc corrigées.', 'Identifying which groups differ without corrected post hoc comparisons.')
          : _posthocNotJustified(),
    ),
  );
}

Alert _posthocAlert() => Alert(
    'posthoc_exploratory',
    Severity.info,
    tr("Comparaisons deux à deux ajustées pour la multiplicité. Elles sont exploratoires si elles n'étaient pas prévues dans le plan d'analyse ; les présenter comme telles.",
        'Pairwise comparisons adjusted for multiplicity. They are exploratory if they were not planned in the analysis plan; present them as such.'));

String _posthocNotJustified() => tr(
    "Conclure que deux groupes sont équivalents parce que leur comparaison n'est pas significative ; ajouter d'autres tests deux à deux non ajustés ; présenter comme confirmatoires des comparaisons non prévues.",
    'Concluding that two groups are equivalent because their comparison is not significant; adding other unadjusted pairwise tests; presenting unplanned comparisons as confirmatory.');

/// χ² d'indépendance pour un tableau r × c, avec V de Cramér.
AnalysisResult chiSquareRxC(List<List<int>> table, {List<String>? rowNames, List<String>? colNames}) {
  final r = table.length, c = table.first.length;
  final rowS = [for (final row in table) row.fold<int>(0, (a, b) => a + b)];
  final colS = [for (var j = 0; j < c; j++) table.fold<int>(0, (a, row) => a + row[j])];
  if (rowS.contains(0) || colS.contains(0)) {
    throw StatInputError('empty_margin', tr('Une ligne ou une colonne est vide : la retirer ou regrouper.', 'A row or column is empty: remove it or merge categories.'));
  }
  final total = rowS.fold<int>(0, (a, b) => a + b);
  final exp = [for (var i = 0; i < r; i++) [for (var j = 0; j < c; j++) rowS[i] * colS[j] / total]];
  var x2 = 0.0;
  var small = 0;
  var minE = double.infinity;
  for (var i = 0; i < r; i++) {
    for (var j = 0; j < c; j++) {
      x2 += math.pow(table[i][j] - exp[i][j], 2) / exp[i][j];
      if (exp[i][j] < 5) small++;
      minE = math.min(minE, exp[i][j]);
    }
  }
  final df = ((r - 1) * (c - 1)).toDouble();
  final p = chiSquareUpper(x2, df);
  final v = math.sqrt(x2 / (total * (math.min(r, c) - 1)));
  final fracSmall = small / (r * c);
  final bad = fracSmall > 0.2 || minE < 1;
  return AnalysisResult(
    methodId: 'chi_square_rxc',
    methodName: tr("Test du χ² d'indépendance (r × c)", 'χ² test of independence (r × c)'),
    inputs: {'table': table},
    formula: tr('χ² = Σ (O − E)²/E, E = (total ligne × total colonne)/N ; ddl = (r−1)(c−1) ; V = √[χ²/(N(min(r,c)−1))].',
        'χ² = Σ (O − E)²/E, E = (row total × column total)/N; df = (r−1)(c−1); V = √[χ²/(N(min(r,c)−1))].'),
    estimates: [Estimate(tr('V de Cramér', "Cramér's V"), v)],
    statistics: {'chi2': x2, 'df': df, 'p': p, 'min_expected': minE},
    checks: [
      Check('expected_counts', tr('Au plus 20 % des effectifs attendus < 5 et aucun < 1 (Cochran)', 'At most 20% of expected counts < 5 and none < 1 (Cochran)'),
          bad ? CheckStatus.violated : CheckStatus.ok,
          tr('$small cellule(s) sur ${r * c} avec E < 5 ; minimum ${fmt(minE)}.', '$small cell(s) out of ${r * c} with E < 5; minimum ${fmt(minE)}.')),
    ],
    alerts: [
      if (bad)
        Alert('chi2_invalid', Severity.serious,
            tr("Conditions du χ² non remplies : la valeur de p n'est pas fiable.", 'χ² conditions not met: the p-value is not reliable.'),
            suggestion: tr('Regrouper des catégories justifiées a priori, ou utiliser un test exact.', 'Merge categories justified a priori, or use an exact test.')),
    ],
    tables: [
      ResultTable(tr('Tableau observé', 'Observed table'), ['', ...colNames ?? [for (var j = 0; j < c; j++) 'C${j + 1}']],
          [for (var i = 0; i < r; i++) [rowNames?[i] ?? 'L${i + 1}', ...table[i].map((e) => '$e')]]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Deux variables qualitatives, observations indépendantes.', 'Two categorical variables, independent observations.'),
      whatItMeans: tr('χ²(${df.toInt()}) = ${fmt(x2)}, ${fmtP(p)} ; V de Cramér = ${fmt(v)}.', "χ²(${df.toInt()}) = ${fmt(x2)}, ${fmtP(p)}; Cramér's V = ${fmt(v)}."),
      notJustified: tr("Interpréter le sens ou la force causale de l'association à partir du seul χ².", 'Interpreting the direction or causal strength of the association from the χ² alone.'),
    ),
  );
}
