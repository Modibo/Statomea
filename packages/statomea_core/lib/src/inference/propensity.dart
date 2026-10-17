/// Score de propension : appariement et pondération, diagnostics d'équilibre, effet du traitement.
///  - score e = P(traité | covariables) par régression logistique (covariables choisies a priori) ;
///  - appariement 1:1 au plus proche voisin sans remise, traités pris par score décroissant, caliper facultatif en
///    écarts-types du score (MatchIt « nearest ») : effet chez les traités (ATT) ;
///  - pondération IPTW : ATE w = t/e + (1 − t)/(1 − e) ; ATT w = t + (1 − t)·e/(1 − e) (WeightIt) ;
///  - équilibre (cobalt, binary = "std") : différence standardisée des moyennes (pondérées) avec dénominateur non
///    pondéré (ÉT des traités pour l'ATT, ÉT poolé pour l'ATE), rapport des variances pondérées, taille effective ;
///  - effet : différence des moyennes (pondérées) de l'issue (différence de risques pour une issue 0/1) = coefficient de
///    lm(y ~ t, poids) ; ES robuste HC0 (pondération) ou par paire (appariement, vcovCL HC1) ; IC normal. L'incertitude
///    de l'estimation du score n'est pas propagée (prudent pour l'ATE).
/// Validé contre validation/r/53_propension.R (MatchIt 4.5.5, WeightIt 0.14.2, cobalt 4.5.2, sandwich).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/design_matrix.dart';
import '../regression/glm.dart';

enum PropensityMethod { matching, iptwAte, iptwAtt }

/// Appariement 1:1 sans remise : pour chaque traité (score décroissant), témoin libre le plus proche, à moins de
/// [caliper] si fourni ; ex aequo départagés comme MatchIt. Renvoie, pour chaque sujet traité, l'index du témoin apparié (ou null).
Map<int, int?> nearestNeighborMatch(List<double> ps, List<int> t, {double? caliper}) {
  final treated = [for (var i = 0; i < ps.length; i++) if (t[i] == 1) i]..sort((a, b) {
      final c = ps[b].compareTo(ps[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  final used = <int>{};
  final controls = [for (var i = 0; i < ps.length; i++) if (t[i] == 0) i];
  final out = <int, int?>{};
  for (final i in treated) {
    int? best;
    var bd = double.infinity;
    for (final j in controls) {
      if (used.contains(j)) continue;
      final d = (ps[i] - ps[j]).abs();
      // Ex aequo (covariables identiques) : comme MatchIt, qui parcourt les témoins triés par score depuis la position
      // du traité, le plus proche dans cet ordre (dernier index sous le traité, premier au-dessus).
      if (d < bd || (d == bd && best != null && ps[j] < ps[i] && j > best)) {
        bd = d;
        best = j;
      }
    }
    if (best != null && (caliper == null || bd <= caliper)) {
      used.add(best);
      out[i] = best;
    } else {
      out[i] = null;
    }
  }
  return out;
}

double _wmean(List<double> x, List<double> w) {
  var s = 0.0, sw = 0.0;
  for (var i = 0; i < x.length; i++) {
    s += w[i] * x[i];
    sw += w[i];
  }
  return s / sw;
}

/// Variance pondérée « sans biais » (cobalt) : Σw(x − m)²·Σw/((Σw)² − Σw²) ; pour une variable 0/1 : m(1 − m).
double _wvar(List<double> x, List<double> w, {bool binary = false}) {
  final m = _wmean(x, w);
  if (binary) return m * (1 - m);
  var s = 0.0, sw = 0.0, sw2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    s += w[i] * (x[i] - m) * (x[i] - m);
    sw += w[i];
    sw2 += w[i] * w[i];
  }
  return s * sw / (sw * sw - sw2);
}

AnalysisResult propensityAnalysis(Dataset ds,
    {required String treatment,
    required String treatedLevel,
    required List<TermSpec> covariates,
    String? outcome,
    String? outcomeEvent,
    PropensityMethod method = PropensityMethod.matching,
    double? caliper,
    double level = 0.95}) {
  if (covariates.isEmpty) throw StatInputError('no_covariate', tr('Choisir au moins une covariable de confusion.', 'Choose at least one confounding covariate.'));
  if (covariates.any((c) => c.variable == treatment || c.variable == outcome)) {
    throw StatInputError('covariate_role', tr('Le traitement et l\'issue ne peuvent pas être des covariables du score.', 'The treatment and the outcome cannot be covariates of the score.'));
  }
  final d = buildDesign(ds, ModelFormula(treatment, covariates, eventLevel: treatedLevel), binaryOutcome: true);
  // Issue : lignes du score dont l'issue est connue (analyse en cas complets).
  List<double?>? yAll;
  final binaryY = outcomeEvent != null;
  if (outcome != null) {
    yAll = binaryY ? [for (final v in ds.text(outcome)) v == null ? null : (v == outcomeEvent ? 1.0 : 0.0)] : ds.numeric(outcome);
  }
  final keep = [for (var k = 0; k < d.n; k++) if (yAll == null || yAll[d.rows[k]] != null) k];
  final missingY = d.n - keep.length;
  final x = [for (final k in keep) d.x[k]], t = [for (final k in keep) d.y[k].toInt()];
  final y = yAll == null ? null : [for (final k in keep) yAll[d.rows[k]]!];
  final n = x.length;
  final n1 = t.where((v) => v == 1).length, n0 = n - n1;
  if (n1 < 5 || n0 < 5) throw StatInputError('few_treated', tr('Au moins 5 traités et 5 non-traités sont requis.', 'At least 5 treated and 5 untreated subjects are required.'));
  final fit = fitLogistic(x, [for (final v in t) v.toDouble()]);
  final ps = fit.mu;
  final cols = d.columns;
  final z = normalQuantile(1 - (1 - level) / 2);
  final pct = (level * 100).round();
  // Poids selon la méthode.
  final w = List<double>.filled(n, 0);
  Map<int, int?>? pairs;
  double? caliperWidth;
  final pairOf = List<int?>.filled(n, null);
  final estimand = method == PropensityMethod.iptwAte ? 'ATE' : 'ATT';
  if (method == PropensityMethod.matching) {
    if (caliper != null) {
      final m = ps.fold(0.0, (a, b) => a + b) / n;
      caliperWidth = caliper * math.sqrt(ps.fold(0.0, (a, v) => a + (v - m) * (v - m)) / (n - 1));
    }
    pairs = nearestNeighborMatch(ps, t, caliper: caliperWidth);
    var id = 0;
    for (final e in pairs.entries) {
      if (e.value == null) continue;
      w[e.key] = 1;
      w[e.value!] = 1;
      pairOf[e.key] = id;
      pairOf[e.value!] = id;
      id++;
    }
  } else {
    for (var i = 0; i < n; i++) {
      w[i] = method == PropensityMethod.iptwAte ? (t[i] == 1 ? 1 / ps[i] : 1 / (1 - ps[i])) : (t[i] == 1 ? 1.0 : ps[i] / (1 - ps[i]));
    }
  }
  final nMatched = pairs?.values.whereType<int>().length;
  // Équilibre : score puis chaque colonne de la matrice de plan (hors constante).
  final rowsBal = <List<String>>[];
  final love = <Map<String, Object?>>[];
  final stats = <String, double>{};
  final ones = List<double>.filled(n, 1);
  final i1 = [for (var i = 0; i < n; i++) if (t[i] == 1) i], i0 = [for (var i = 0; i < n; i++) if (t[i] == 0) i];
  var maxSmd = 0.0;
  for (var j = 0; j <= cols.length - 1; j++) {
    final isPs = j == 0;
    final name = isPs ? tr('Score de propension', 'Propensity score') : cols[j];
    final v = isPs ? ps : [for (final r in x) r[j]];
    final binary = !isPs && v.every((e) => e == 0 || e == 1);
    List<double> g(List<int> idx, List<double> src) => [for (final i in idx) src[i]];
    final v1 = g(i1, v), v0 = g(i0, v);
    final s1 = _wvar(v1, g(i1, ones), binary: binary), s0 = _wvar(v0, g(i0, ones), binary: binary);
    final denom = math.sqrt(estimand == 'ATE' ? (s1 + s0) / 2 : s1);
    final smdUn = (_wmean(v1, g(i1, ones)) - _wmean(v0, g(i0, ones))) / denom;
    final w1 = g(i1, w), w0 = g(i0, w);
    final sel1 = [for (var k = 0; k < i1.length; k++) if (w1[k] > 0) k], sel0 = [for (var k = 0; k < i0.length; k++) if (w0[k] > 0) k];
    final a1 = [for (final k in sel1) v1[k]], aw1 = [for (final k in sel1) w1[k]], a0 = [for (final k in sel0) v0[k]], aw0 = [for (final k in sel0) w0[k]];
    final smd = (_wmean(a1, aw1) - _wmean(a0, aw0)) / denom;
    final vr = binary ? double.nan : _wvar(a1, aw1) / _wvar(a0, aw0);
    if (!isPs) maxSmd = math.max(maxSmd, smd.abs());
    final key = isPs ? 'ps' : cols[j];
    stats['smd_un_$key'] = smdUn;
    stats['smd_$key'] = smd;
    if (!binary) stats['vr_$key'] = vr;
    rowsBal.add([name, fmt(smdUn, digits: 3), fmt(smd, digits: 3), binary ? '—' : fmt(vr), smd.abs() < 0.1 ? tr('oui', 'yes') : tr('non', 'no')]);
    love.add({'name': name, 'before': smdUn, 'after': smd});
  }
  double ess(List<int> idx) {
    var s = 0.0, s2 = 0.0;
    for (final i in idx) {
      s += w[i];
      s2 += w[i] * w[i];
    }
    return s2 == 0 ? 0 : s * s / s2;
  }

  final ess1 = ess(i1), ess0 = ess(i0);
  stats.addAll({'n': n.toDouble(), 'n_treated': n1.toDouble(), 'n_control': n0.toDouble(), 'ess_treated': ess1, 'ess_control': ess0, 'max_smd': maxSmd});
  if (nMatched != null) stats['n_matched'] = nMatched.toDouble();
  if (caliperWidth != null) stats['caliper_width'] = caliperWidth;
  // Recouvrement des scores.
  final ps1 = [for (final i in i1) ps[i]]..sort(), ps0 = [for (final i in i0) ps[i]]..sort();
  final outside = ps1.where((p) => p > ps0.last).length + ps0.where((p) => p < ps1.first).length;
  // Effet sur l'issue.
  Estimate? effect;
  String effectText = '';
  if (y != null) {
    final sel = [for (var i = 0; i < n; i++) if (w[i] > 0) i];
    final sw1 = sel.where((i) => t[i] == 1).fold(0.0, (a, i) => a + w[i]), sw0 = sel.where((i) => t[i] == 0).fold(0.0, (a, i) => a + w[i]);
    final m1 = sel.where((i) => t[i] == 1).fold(0.0, (a, i) => a + w[i] * y[i]) / sw1, m0 = sel.where((i) => t[i] == 0).fold(0.0, (a, i) => a + w[i] * y[i]) / sw0;
    final est = m1 - m0;
    // lm(y ~ t, poids) : X = [1, t] ; bread = (XᵀWX)⁻¹ ; meat robuste (HC0) ou par paire (HC1 et correction G/(G − 1)).
    var a = 0.0, b = 0.0, c = 0.0; // XᵀWX = [[a, b], [b, c]]
    for (final i in sel) {
      a += w[i];
      b += w[i] * t[i];
      c += w[i] * t[i] * t[i];
    }
    final det = a * c - b * b;
    final inv = [c / det, -b / det, -b / det, a / det];
    final intercept = m0;
    final u = <List<double>>[]; // contributions au score w·e·x, regroupées par paire si appariement
    if (method == PropensityMethod.matching) {
      final byPair = <int, List<double>>{};
      for (final i in sel) {
        final e = y[i] - intercept - est * t[i];
        final s = byPair.putIfAbsent(pairOf[i]!, () => [0, 0]);
        s[0] += w[i] * e;
        s[1] += w[i] * e * t[i];
      }
      u.addAll(byPair.values);
    } else {
      for (final i in sel) {
        final e = y[i] - intercept - est * t[i];
        u.add([w[i] * e, w[i] * e * t[i]]);
      }
    }
    var m00 = 0.0, m01 = 0.0, m11 = 0.0;
    for (final s in u) {
      m00 += s[0] * s[0];
      m01 += s[0] * s[1];
      m11 += s[1] * s[1];
    }
    // Élément (2, 2) de bread·meat·bread.
    final r0 = inv[2], r1 = inv[3];
    var v = r0 * r0 * m00 + 2 * r0 * r1 * m01 + r1 * r1 * m11;
    if (method == PropensityMethod.matching) {
      final gN = u.length, nn = sel.length;
      v *= gN / (gN - 1) * (nn - 1) / (nn - 2);
    }
    final se = math.sqrt(v);
    final label = binaryY ? tr('Différence de risques ($estimand)', 'Risk difference ($estimand)') : tr('Différence de moyennes ($estimand)', 'Mean difference ($estimand)');
    effect = Estimate(label, est, lower: est - z * se, upper: est + z * se, se: se, pValue: normalTwoSidedP(est / se), level: level);
    stats.addAll({'effect': est, 'effect_se': se, 'effect_p': effect.pValue!, 'mean_treated': m1, 'mean_control': m0});
    effectText = binaryY
        ? tr('Risque ${fmtPct(m1)} chez les traités contre ${fmtPct(m0)} chez les non-traités comparables : différence ${fmtPct(est)} (IC ${fmtPct(est - z * se)} à ${fmtPct(est + z * se)}), ${fmtP(effect.pValue!)}.',
            'Risk ${fmtPct(m1)} in the treated vs ${fmtPct(m0)} in comparable untreated: difference ${fmtPct(est)} (CI ${fmtPct(est - z * se)} to ${fmtPct(est + z * se)}), ${fmtP(effect.pValue!)}.')
        : tr('Moyenne ${fmt(m1)} chez les traités contre ${fmt(m0)} chez les non-traités comparables : différence ${fmt(est)} (IC ${fmt(est - z * se)} à ${fmt(est + z * se)}), ${fmtP(effect.pValue!)}.',
            'Mean ${fmt(m1)} in the treated vs ${fmt(m0)} in comparable untreated: difference ${fmt(est)} (CI ${fmt(est - z * se)} to ${fmt(est + z * se)}), ${fmtP(effect.pValue!)}.');
  }
  final methodLabel = switch (method) {
    PropensityMethod.matching => tr('appariement 1:1 au plus proche voisin${caliper == null ? '' : ' (caliper ${fmt(caliper)} ÉT)'}', '1:1 nearest-neighbour matching${caliper == null ? '' : ' (caliper ${fmt(caliper)} SD)'}'),
    PropensityMethod.iptwAte => tr('pondération inverse (IPTW, ATE)', 'inverse probability weighting (IPTW, ATE)'),
    PropensityMethod.iptwAtt => tr('pondération (ATT, poids e/(1 − e) des témoins)', 'weighting (ATT, control weights e/(1 − e))'),
  };
  final wMax = w.reduce(math.max);
  final alerts = <Alert>[...d.alerts];
  if (maxSmd >= 0.1) {
    alerts.add(Alert('imbalance', Severity.serious,
        tr('Équilibre insuffisant après ajustement (|DMS| max = ${fmt(maxSmd, digits: 3)} ≥ 0,1) : l\'effet estimé reste confondu.', 'Insufficient balance after adjustment (max |SMD| = ${fmt(maxSmd, digits: 3)} ≥ 0.1): the estimated effect remains confounded.'),
        suggestion: tr('Revoir la forme des covariables (splines, interactions), changer de méthode ou resserrer le caliper.', 'Revisit the covariate forms (splines, interactions), change method or tighten the caliper.')));
  }
  if (method != PropensityMethod.matching && wMax > 10) {
    alerts.add(Alert('extreme_weights', Severity.caution,
        tr('Poids extrême (max ${fmt(wMax)}) : quelques sujets pèsent beaucoup ; taille effective traités ${fmt(ess1)}, témoins ${fmt(ess0)}.', 'Extreme weight (max ${fmt(wMax)}): a few subjects carry much weight; effective size treated ${fmt(ess1)}, controls ${fmt(ess0)}.'),
        suggestion: tr('Vérifier le recouvrement ; envisager l\'ATT, l\'appariement ou la troncature des poids (analyse de sensibilité).', 'Check overlap; consider the ATT, matching or weight truncation (sensitivity analysis).')));
  }
  if (nMatched != null && nMatched < n1) {
    alerts.add(Alert('unmatched_treated', Severity.caution,
        tr('${n1 - nMatched} traité(s) sans témoin dans le caliper : l\'effet porte sur les $nMatched traités appariés, population différente de l\'ensemble des traités.', '${n1 - nMatched} treated subject(s) without a control within the caliper: the effect concerns the $nMatched matched treated, a population different from all treated.')));
  }
  if (missingY > 0) alerts.add(Alert('missing_outcome', Severity.caution, tr('$missingY ligne(s) sans issue exclue(s).', '$missingY row(s) without outcome excluded.')));
  final psBins = <Map<String, Object?>>[
    for (var k = 0; k < 20; k++)
      {'lo': k / 20, 'hi': (k + 1) / 20, 'treated': ps1.where((p) => p >= k / 20 && (p < (k + 1) / 20 || k == 19)).length, 'control': ps0.where((p) => p >= k / 20 && (p < (k + 1) / 20 || k == 19)).length}
  ];
  return AnalysisResult(
    methodId: method == PropensityMethod.matching ? 'propensity_matching' : 'propensity_weighting',
    methodName: tr('Score de propension : $methodLabel', 'Propensity score: $methodLabel'),
    inputs: {'model': d.describe(), 'treatment': treatment, 'treatedLevel': treatedLevel, 'outcome': ?outcome, 'outcomeEvent': ?outcomeEvent, 'method': method.name, 'caliper': ?caliper, 'level': level},
    formula: tr(
        'e(x) = P(T = 1 | x) par régression logistique. Appariement : traités par e décroissant, témoin libre le plus proche (|Δe| ≤ caliper × ÉT(e)). IPTW : ATE w = T/e + (1 − T)/(1 − e) ; ATT w = T + (1 − T)·e/(1 − e). DMS = (m̄₁ − m̄₀)/s, s = ÉT non pondéré des traités (ATT) ou √((s₁² + s₀²)/2) (ATE). Effet = coefficient de T dans lm(y ~ T, poids) ; ES robuste (HC0, ou par paire pour l\'appariement).',
        'e(x) = P(T = 1 | x) by logistic regression. Matching: treated by decreasing e, nearest free control (|Δe| ≤ caliper × SD(e)). IPTW: ATE w = T/e + (1 − T)/(1 − e); ATT w = T + (1 − T)·e/(1 − e). SMD = (m̄₁ − m̄₀)/s, s = unweighted SD of the treated (ATT) or √((s₁² + s₀²)/2) (ATE). Effect = coefficient of T in lm(y ~ T, weights); robust SE (HC0, or by pair for matching).'),
    estimates: [
      ?effect,
      Estimate(tr('|DMS| maximale après ajustement', 'Maximum |SMD| after adjustment'), maxSmd),
    ],
    statistics: stats,
    checks: [
      Check('balance', tr('Équilibre des covariables (|DMS| < 0,1)', 'Covariate balance (|SMD| < 0.1)'), maxSmd < 0.1 ? CheckStatus.ok : CheckStatus.violated, tr('|DMS| max = ${fmt(maxSmd, digits: 3)}.', 'max |SMD| = ${fmt(maxSmd, digits: 3)}.')),
      Check('overlap', tr('Recouvrement des scores (positivité)', 'Overlap of scores (positivity)'), outside > 0.05 * n ? CheckStatus.warning : CheckStatus.ok,
          tr('Traités : ${fmt(ps1.first, digits: 3)} à ${fmt(ps1.last, digits: 3)} ; non-traités : ${fmt(ps0.first, digits: 3)} à ${fmt(ps0.last, digits: 3)} ; $outside sujet(s) hors de la zone commune.',
              'Treated: ${fmt(ps1.first, digits: 3)} to ${fmt(ps1.last, digits: 3)}; untreated: ${fmt(ps0.first, digits: 3)} to ${fmt(ps0.last, digits: 3)}; $outside subject(s) outside the common region.')),
      Check('no_unmeasured_confounding', tr('Absence de confusion non mesurée', 'No unmeasured confounding'), CheckStatus.notAssessed,
          tr('Hypothèse non vérifiable : le score n\'équilibre que les covariables mesurées et incluses ; justifier leur choix (graphe causal) et discuter la confusion résiduelle (valeur E).',
              'Untestable assumption: the score balances only measured and included covariates; justify their choice (causal graph) and discuss residual confounding (E-value).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Équilibre avant et après ajustement', 'Balance before and after adjustment'),
          [tr('Variable', 'Variable'), tr('DMS avant', 'SMD before'), tr('DMS après', 'SMD after'), tr('Rapport des variances après', 'Variance ratio after'), tr('Équilibrée', 'Balanced')], rowsBal),
      ResultTable(tr('Effectifs', 'Sample sizes'), [tr('Élément', 'Item'), tr('Traités', 'Treated'), tr('Non-traités', 'Untreated')], [
        [tr('Analysés', 'Analysed'), '$n1', '$n0'],
        if (nMatched != null) [tr('Appariés', 'Matched'), '$nMatched', '$nMatched'],
        [tr('Taille effective', 'Effective size'), fmt(ess1), fmt(ess0)],
      ]),
      if (effect != null)
        ResultTable(tr('Effet du traitement « $treatment = $treatedLevel »', 'Effect of treatment "$treatment = $treatedLevel"'), [tr('Estimation', 'Estimate'), tr('Valeur', 'Value'), tr('IC $pct %', '$pct% CI'), 'p'], [
          [effect.label, fmt(effect.value), '${fmt(effect.lower)} – ${fmt(effect.upper)}', fmtP(effect.pValue!)],
        ]),
    ],
    figures: {
      'lovePlot': {'rows': love, 'threshold': 0.1},
      'psOverlap': {'bins': psBins, 'treated': '$treatment = $treatedLevel', 'control': tr('autres', 'others')},
    },
    log: [tr('Score : régression logistique convergée en ${fit.iterations} itération(s).', 'Score: logistic regression converged in ${fit.iterations} iteration(s).'), if (wMax > 0) tr('Poids maximal : ${fmt(wMax)}.', 'Maximum weight: ${fmt(wMax)}.')],
    interpretation: Interpretation(
      whyThisMethod: tr('Étude observationnelle : traités et non-traités diffèrent par leurs caractéristiques ; le score de propension résume ces différences en une probabilité et permet de comparer des sujets comparables (appariement) ou de recréer une population équilibrée (pondération).',
          'Observational study: treated and untreated differ in their characteristics; the propensity score summarizes these differences as a probability and allows comparing comparable subjects (matching) or recreating a balanced population (weighting).'),
      whatItMeans: '${tr('Estimand : ${estimand == 'ATE' ? 'effet moyen dans toute la population (ATE)' : 'effet moyen chez les traités (ATT)'}. Après ajustement, |DMS| max = ${fmt(maxSmd, digits: 3)} ${maxSmd < 0.1 ? '(équilibre atteint)' : '(équilibre insuffisant)'}.', 'Estimand: ${estimand == 'ATE' ? 'average effect in the whole population (ATE)' : 'average effect in the treated (ATT)'}. After adjustment, max |SMD| = ${fmt(maxSmd, digits: 3)} ${maxSmd < 0.1 ? '(balance achieved)' : '(insufficient balance)'}.')} $effectText'.trim(),
      notJustified: tr('Interpréter l\'effet comme causal sans discuter la confusion non mesurée ; choisir les covariables au vu de l\'issue ou des p ; inclure des variables postérieures au traitement ; juger l\'équilibre par des tests de significativité ; ignorer les sujets non appariés ou les poids extrêmes.',
          'Interpreting the effect as causal without discussing unmeasured confounding; choosing covariates based on the outcome or p-values; including post-treatment variables; judging balance by significance tests; ignoring unmatched subjects or extreme weights.'),
    ),
  );
}
