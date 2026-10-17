/// Issues qualitatives à plus de deux modalités :
///  - ordinale : modèle logistique à cotes proportionnelles, logit P(Y ≤ k) = ζₖ − xᵀβ (comme MASS::polr) ;
///  - nominale : logistique multinomiale, log(P(Y = k)/P(Y = 1)) = xᵀβₖ (comme nnet::multinom).
/// Maximum de vraisemblance par Newton-Raphson (hessienne analytique), ES par l'inverse de l'information.
/// Validé contre validation/r/46_ordinal.R (MASS 7.3, nnet 7.3).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

double _f(double a) => a == double.infinity || a == double.negativeInfinity ? 0 : math.exp(-a.abs()) / ((1 + math.exp(-a.abs())) * (1 + math.exp(-a.abs())));
double _cdf(double a) => a == double.infinity ? 1 : (a == double.negativeInfinity ? 0 : (a >= 0 ? 1 / (1 + math.exp(-a)) : math.exp(a) / (1 + math.exp(a))));
double _fp(double a) => _f(a) * (1 - 2 * _cdf(a)); // dérivée de la densité logistique

class OrdinalFit {
  final List<double> zeta, beta;
  final Matrix cov; // (ζ…, β…)
  final double logLik;
  final bool converged;
  const OrdinalFit(this.zeta, this.beta, this.cov, this.logLik, this.converged);
}

/// Cotes proportionnelles : [x] sans constante, [y] = rang 0 … K − 1.
OrdinalFit fitProportionalOdds(List<List<double>> x, List<int> y, int k) {
  final n = y.length, p = x.isEmpty ? 0 : x.first.length, q = k - 1 + p;
  // Départ : seuils logit des fréquences cumulées, β = 0.
  final counts = List<int>.filled(k, 0);
  for (final v in y) {
    counts[v]++;
  }
  var cum = 0;
  final theta = <double>[
    for (var j = 0; j < k - 1; j++)
      () {
        cum += counts[j];
        final pr = cum / n;
        return math.log(pr / (1 - pr));
      }(),
    for (var j = 0; j < p; j++) 0.0,
  ];
  ({double ll, List<double> g, Matrix h})? eval(List<double> t) {
    var ll = 0.0;
    final g = List<double>.filled(q, 0);
    final h = Matrix(q, q);
    for (var i = 0; i < n; i++) {
      var eta = 0.0;
      for (var j = 0; j < p; j++) {
        eta += x[i][j] * t[k - 1 + j];
      }
      final c = y[i];
      final a = c < k - 1 ? t[c] - eta : double.infinity;
      final b = c > 0 ? t[c - 1] - eta : double.negativeInfinity;
      final pr = _cdf(a) - _cdf(b);
      if (!(pr > 0)) return null;
      ll += math.log(pr);
      final ga = _f(a) / pr, gb = -_f(b) / pr;
      final laa = _fp(a) / pr - ga * ga, lbb = -_fp(b) / pr - gb * gb, lab = -ga * gb;
      // Gradients de a et de b par rapport aux paramètres (vecteurs creux : un seuil, puis −x).
      List<double> grad(int? zi) => [for (var j = 0; j < q; j++) j == zi ? 1.0 : (j >= k - 1 ? -x[i][j - (k - 1)] : 0.0)];
      final da = grad(c < k - 1 ? c : null), db = grad(c > 0 ? c - 1 : null);
      final hasA = c < k - 1, hasB = c > 0;
      for (var r = 0; r < q; r++) {
        g[r] += (hasA ? ga * da[r] : 0) + (hasB ? gb * db[r] : 0);
        for (var s = 0; s < q; s++) {
          var v = 0.0;
          if (hasA) v += laa * da[r] * da[s];
          if (hasB) v += lbb * db[r] * db[s];
          if (hasA && hasB) v += lab * (da[r] * db[s] + db[r] * da[s]);
          h.data[r * q + s] += v;
        }
      }
    }
    return (ll: ll, g: g, h: h);
  }

  var cur = eval(theta)!;
  var converged = false;
  var t = theta;
  for (var it = 0; it < 100; it++) {
    final neg = Matrix(q, q);
    for (var i = 0; i < q * q; i++) {
      neg.data[i] = -cur.h.data[i];
    }
    final step = solveSpd(neg, cur.g);
    if (step == null) break;
    var scale = 1.0;
    ({double ll, List<double> g, Matrix h})? next;
    List<double> tn = t;
    for (var h = 0; h < 40; h++) {
      tn = [for (var j = 0; j < q; j++) t[j] + scale * step[j]];
      next = eval(tn);
      if (next != null && next.ll >= cur.ll - 1e-12 * (1 + cur.ll.abs())) break;
      scale /= 2;
    }
    if (next == null) break;
    final change = (next.ll - cur.ll).abs();
    t = tn;
    cur = next;
    if (change < 1e-14 * (1 + cur.ll.abs()) && step.every((v) => v.abs() < 1e-9)) {
      converged = true;
      break;
    }
  }
  final neg = Matrix(q, q);
  for (var i = 0; i < q * q; i++) {
    neg.data[i] = -cur.h.data[i];
  }
  return OrdinalFit(t.sublist(0, k - 1), t.sublist(k - 1), invertSpd(neg) ?? Matrix(q, q), cur.ll, converged);
}

class MultinomFit {
  final List<List<double>> beta; // (K − 1) × p, catégorie de référence = 0
  final Matrix cov; // ordre : catégorie 2 (tous les coefficients), catégorie 3…
  final double logLik;
  final bool converged;
  const MultinomFit(this.beta, this.cov, this.logLik, this.converged);
}

/// Logistique multinomiale : [x] avec constante, [y] = 0 … K − 1 (0 = référence).
MultinomFit fitMultinomial(List<List<double>> x, List<int> y, int k) {
  final n = y.length, p = x.first.length, m = k - 1, q = m * p;
  var b = List<double>.filled(q, 0);
  ({double ll, List<double> g, Matrix h}) eval(List<double> bb) {
    var ll = 0.0;
    final g = List<double>.filled(q, 0);
    final h = Matrix(q, q);
    for (var i = 0; i < n; i++) {
      final eta = [for (var c = 0; c < m; c++) [for (var j = 0; j < p; j++) x[i][j] * bb[c * p + j]].fold(0.0, (s, v) => s + v)];
      final mx = eta.fold(0.0, math.max);
      final den = math.exp(-mx) + eta.fold(0.0, (s, e) => s + math.exp(e - mx));
      final pr = [for (final e in eta) math.exp(e - mx) / den];
      ll += (y[i] == 0 ? -mx : eta[y[i] - 1] - mx) - math.log(den);
      for (var c = 0; c < m; c++) {
        final r = (y[i] == c + 1 ? 1.0 : 0.0) - pr[c];
        for (var j = 0; j < p; j++) {
          g[c * p + j] += r * x[i][j];
        }
        for (var d = 0; d < m; d++) {
          final w = pr[c] * ((c == d ? 1 : 0) - pr[d]);
          for (var j = 0; j < p; j++) {
            for (var l = 0; l < p; l++) {
              h.data[(c * p + j) * q + d * p + l] += w * x[i][j] * x[i][l]; // information (−hessienne)
            }
          }
        }
      }
    }
    return (ll: ll, g: g, h: h);
  }

  var cur = eval(b);
  var converged = false;
  for (var it = 0; it < 100; it++) {
    final step = solveSpd(cur.h, cur.g);
    if (step == null) break;
    var scale = 1.0;
    var bn = b;
    var next = cur;
    for (var hh = 0; hh < 40; hh++) {
      bn = [for (var j = 0; j < q; j++) b[j] + scale * step[j]];
      next = eval(bn);
      if (next.ll >= cur.ll - 1e-12 * (1 + cur.ll.abs())) break;
      scale /= 2;
    }
    final change = (next.ll - cur.ll).abs();
    b = bn;
    cur = next;
    if (change < 1e-14 * (1 + cur.ll.abs()) && step.every((v) => v.abs() < 1e-9)) {
      converged = true;
      break;
    }
  }
  return MultinomFit([for (var c = 0; c < m; c++) b.sublist(c * p, (c + 1) * p)], invertSpd(cur.h) ?? Matrix(q, q), cur.ll, converged);
}

/// Prépare X (avec constante) et le rang de l'issue selon [levels] (ordre croissant ; défaut : modalités triées).
({DesignMatrix d, List<int> y, List<String> levels}) _design(Dataset ds, ModelFormula f, List<String>? levels) {
  final lv = levels ?? ds.levels(f.outcome);
  if (lv.length < 3) throw StatInputError('few_levels', tr('L\'issue doit avoir au moins 3 modalités (sinon : régression logistique).', 'The outcome must have at least 3 levels (otherwise: logistic regression).'));
  const code = '__rang_issue';
  final txt = ds.text(f.outcome);
  final ds2 = Dataset([...ds.names, code], [
    for (var i = 0; i < ds.rowCount; i++) [for (final n in ds.names) ds.cell(i, n), txt[i] == null || !lv.contains(txt[i]) ? null : '${lv.indexOf(txt[i]!)}']
  ], source: ds.source);
  final d = buildDesign(ds2, ModelFormula(code, f.terms, interactions: f.interactions));
  final present = {for (final v in d.y) v.round()};
  if (present.length < lv.length) {
    throw StatInputError('empty_level', tr('Une modalité de l\'issue n\'a aucune observation complète.', 'A level of the outcome has no complete observation.'));
  }
  return (d: d, y: [for (final v in d.y) v.round()], levels: lv);
}

/// Régression logistique ordinale (cotes proportionnelles). [levels] : modalités de l'issue dans l'ordre croissant.
AnalysisResult ordinalRegression(Dataset ds, ModelFormula f, {List<String>? levels, double level = 0.95}) {
  final prep = _design(ds, f, levels);
  final d = prep.d, lv = prep.levels, k = lv.length;
  final x = [for (final r in d.x) r.sublist(1)]; // sans constante (absorbée par les seuils)
  final cols = d.columns.sublist(1);
  final fit = fitProportionalOdds(x, prep.y, k);
  final p = cols.length;
  final z = normalQuantile(1 - (1 - level) / 2);
  final coefs = [
    for (var j = 0; j < p; j++)
      () {
        final b = fit.beta[j], se = math.sqrt(fit.cov.get(k - 1 + j, k - 1 + j));
        return Coefficient(cols[j], b, se, b / se, normalTwoSidedP(b / se), b - z * se, b + z * se);
      }()
  ];
  // Modèle nul (seuils seuls) pour le test global.
  final nullFit = fitProportionalOdds([for (var i = 0; i < x.length; i++) <double>[]], prep.y, k);
  final lr = 2 * (fit.logLik - nullFit.logLik);
  // Comparaison au modèle multinomial (approximation du test des cotes proportionnelles).
  final mn = fitMultinomial(d.x, prep.y, k);
  final poLr = math.max(0.0, 2 * (mn.logLik - fit.logLik));
  final poDf = (k - 1) * d.p - (k - 1 + p);
  final poP = chiSquareUpper(poLr, poDf.toDouble());
  final pct = (level * 100).round();
  final main = coefs.first;
  String or(Coefficient c) => '${fmt(math.exp(c.estimate))} (${fmt(math.exp(c.lower))} – ${fmt(math.exp(c.upper))})';
  return AnalysisResult(
    methodId: 'ordinal_logistic',
    methodName: tr('Régression logistique ordinale (cotes proportionnelles)', 'Ordinal logistic regression (proportional odds)'),
    inputs: {'model': d.describe(), 'levels': lv, 'level': level},
    formula: tr(
        'logit P(Y ≤ k) = ζₖ − xᵀβ, k = 1 … ${k - 1} (modalités : ${lv.join(' < ')}) ; OR = exp(β) : facteur multiplicatif des cotes d\'être dans une modalité plus élevée, le même pour chaque seuil ; maximum de vraisemblance (Newton-Raphson), ES par l\'inverse de l\'information, IC de Wald. Cotes proportionnelles : rapport de vraisemblance contre le modèle multinomial (approximation).',
        'logit P(Y ≤ k) = ζₖ − xᵀβ, k = 1 … ${k - 1} (levels: ${lv.join(' < ')}); OR = exp(β): multiplicative factor of the odds of being in a higher level, the same at each threshold; maximum likelihood (Newton-Raphson), SEs from the inverse information, Wald CIs. Proportional odds: likelihood ratio against the multinomial model (approximation).'),
    estimates: [for (final c in coefs) Estimate('OR — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), pValue: c.p, se: c.se, level: level)],
    statistics: {
      'n': d.n.toDouble(), 'loglik': fit.logLik, 'lr': lr, 'lr_p': chiSquareUpper(lr, p.toDouble()), 'po_lr': poLr, 'po_p': poP,
      for (var j = 0; j < p; j++) 'beta_${cols[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${cols[j]}': coefs[j].se,
      for (var j = 0; j < k - 1; j++) 'zeta_$j': fit.zeta[j],
      for (var j = 0; j < k - 1; j++) 'se_zeta_$j': math.sqrt(fit.cov.get(j, j)),
    },
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), fit.converged ? CheckStatus.ok : CheckStatus.violated, ''),
      Check('proportional_odds', tr('Cotes proportionnelles (même OR à chaque seuil)', 'Proportional odds (same OR at each threshold)'), poP < 0.05 ? CheckStatus.warning : CheckStatus.ok,
          tr('Rapport de vraisemblance contre le modèle multinomial : ${fmt(poLr)} ($poDf ddl), ${fmtP(poP)}${poP < 0.05 ? ' : les effets semblent différer selon le seuil ; examiner le modèle multinomial.' : '.'}',
              'Likelihood ratio against the multinomial model: ${fmt(poLr)} ($poDf df), ${fmtP(poP)}${poP < 0.05 ? ': effects seem to differ by threshold; examine the multinomial model.' : '.'}')),
    ],
    alerts: [...d.alerts],
    tables: [
      ResultTable(tr('Coefficients', 'Coefficients'), [tr('Terme', 'Term'), 'β', 'ES', 'z', 'p', 'OR (IC $pct %)'], [
        for (final c in coefs) [c.name, fmt(c.estimate), fmt(c.se), fmt(c.statistic), fmtP(c.p), or(c)]
      ]),
      ResultTable(tr('Seuils', 'Thresholds'), [tr('Seuil', 'Threshold'), 'ζ', 'ES'], [
        for (var j = 0; j < k - 1; j++) ['${lv[j]} | ${lv[j + 1]}', fmt(fit.zeta[j]), fmt(math.sqrt(fit.cov.get(j, j)))]
      ]),
      ResultTable(tr('Ajustement', 'Fit'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('Observations', 'Observations'), '${d.n}'],
        [tr('Log-vraisemblance', 'Log-likelihood'), fmt(fit.logLik, digits: 6)],
        [tr('Test global (RV)', 'Global test (LR)'), '${fmt(lr)} ($p ${tr('ddl', 'df')}), ${fmtP(chiSquareUpper(lr, p.toDouble()))}'],
        for (final c in d.codingNotes) if (!c.contains('__rang_issue')) [tr('Codage', 'Coding'), c],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Issue ordinale (${lv.join(' < ')}) : le modèle à cotes proportionnelles utilise l\'ordre des modalités sans les traiter comme des nombres équidistants, et résume l\'effet de chaque facteur par un seul OR.',
          'Ordinal outcome (${lv.join(' < ')}): the proportional odds model uses the order of the levels without treating them as equally spaced numbers, and summarizes the effect of each factor by a single OR.'),
      whatItMeans: tr('« ${main.name} » : OR = ${or(main)}, ${fmtP(main.p)} — les cotes d\'une modalité plus élevée sont multipliées par ${fmt(math.exp(main.estimate))}, à autres variables fixées.',
          '"${main.name}": OR = ${or(main)}, ${fmtP(main.p)} — the odds of a higher level are multiplied by ${fmt(math.exp(main.estimate))}, holding other variables fixed.'),
      notJustified: tr('Analyser une échelle ordinale comme une variable continue (moyennes) ; dichotomiser l\'issue et perdre de l\'information ; ignorer un écart net aux cotes proportionnelles.',
          'Analysing an ordinal scale as a continuous variable (means); dichotomizing the outcome and losing information; ignoring a clear departure from proportional odds.'),
    ),
  );
}

/// Régression logistique multinomiale (issue nominale), catégorie de référence = première de [levels].
AnalysisResult multinomialRegression(Dataset ds, ModelFormula f, {List<String>? levels, double level = 0.95}) {
  final prep = _design(ds, f, levels);
  final d = prep.d, lv = prep.levels, k = lv.length, p = d.p;
  final fit = fitMultinomial(d.x, prep.y, k);
  final z = normalQuantile(1 - (1 - level) / 2);
  final rows = <List<String>>[];
  final est = <Estimate>[];
  final stats = <String, double>{};
  for (var c = 0; c < k - 1; c++) {
    for (var j = 0; j < p; j++) {
      final b = fit.beta[c][j], se = math.sqrt(fit.cov.get(c * p + j, c * p + j));
      final pv = normalTwoSidedP(b / se);
      stats['beta_${lv[c + 1]}_${d.columns[j]}'] = b;
      stats['se_${lv[c + 1]}_${d.columns[j]}'] = se;
      rows.add([lv[c + 1], d.columns[j], fmt(b), fmt(se), fmtP(pv), j == 0 ? '' : '${fmt(math.exp(b))} (${fmt(math.exp(b - z * se))} – ${fmt(math.exp(b + z * se))})']);
      if (j > 0) est.add(Estimate(tr('RRR ${lv[c + 1]} vs ${lv[0]} — ${d.columns[j]}', 'RRR ${lv[c + 1]} vs ${lv[0]} — ${d.columns[j]}'), math.exp(b), lower: math.exp(b - z * se), upper: math.exp(b + z * se), pValue: pv, se: se, level: level));
    }
  }
  final nullFit = fitMultinomial([for (var i = 0; i < d.n; i++) [1.0]], prep.y, k);
  final lr = 2 * (fit.logLik - nullFit.logLik), df = (k - 1) * (p - 1);
  final pct = (level * 100).round();
  return AnalysisResult(
    methodId: 'multinomial_logistic',
    methodName: tr('Régression logistique multinomiale (référence : « ${lv[0]} »)', 'Multinomial logistic regression (reference: "${lv[0]}")'),
    inputs: {'model': d.describe(), 'levels': lv, 'level': level},
    formula: tr('log[P(Y = k)/P(Y = ${lv[0]})] = xᵀβₖ pour chaque modalité k ≠ ${lv[0]} ; RRR = exp(β) (rapport de risques relatifs) ; maximum de vraisemblance (Newton-Raphson), ES par l\'inverse de l\'information, IC de Wald.',
        'log[P(Y = k)/P(Y = ${lv[0]})] = xᵀβₖ for each level k ≠ ${lv[0]}; RRR = exp(β) (relative risk ratio); maximum likelihood (Newton-Raphson), SEs from the inverse information, Wald CIs.'),
    estimates: est,
    statistics: {'n': d.n.toDouble(), 'loglik': fit.logLik, 'lr': lr, 'lr_p': chiSquareUpper(lr, df.toDouble()), ...stats},
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), fit.converged ? CheckStatus.ok : CheckStatus.violated, ''),
      Check('iia', tr('Indépendance des alternatives non pertinentes', 'Independence of irrelevant alternatives'), CheckStatus.notAssessed,
          tr('Le rapport entre deux modalités ne doit pas dépendre de la présence des autres ; hypothèse à discuter.', 'The ratio between two levels must not depend on the presence of the others; assumption to be discussed.')),
    ],
    alerts: [...d.alerts],
    tables: [
      ResultTable(tr('Coefficients (contre « ${lv[0]} »)', 'Coefficients (against "${lv[0]}")'), [tr('Modalité', 'Level'), tr('Terme', 'Term'), 'β', 'ES', 'p', 'RRR (IC $pct %)'], rows),
      ResultTable(tr('Ajustement', 'Fit'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('Observations', 'Observations'), '${d.n}'],
        [tr('Log-vraisemblance', 'Log-likelihood'), fmt(fit.logLik, digits: 6)],
        [tr('Test global (RV)', 'Global test (LR)'), '${fmt(lr)} ($df ${tr('ddl', 'df')}), ${fmtP(chiSquareUpper(lr, df.toDouble()))}'],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Issue nominale à $k modalités sans ordre : un modèle logistique par modalité contre la référence, ajustés ensemble.', 'Nominal outcome with $k unordered levels: one logistic model per level against the reference, fitted jointly.'),
      whatItMeans: tr('Chaque RRR compare la probabilité d\'une modalité à celle de « ${lv[0]} » ; ${est.isEmpty ? '' : '${est.first.label} = ${fmt(est.first.value)}.'}',
          'Each RRR compares the probability of a level to that of "${lv[0]}"; ${est.isEmpty ? '' : '${est.first.label} = ${fmt(est.first.value)}.'}'),
      notJustified: tr('Utiliser le modèle multinomial pour une issue ordonnée quand les cotes proportionnelles sont acceptables (perte de puissance) ; lire un RRR comme un rapport de risques absolus.',
          'Using the multinomial model for an ordered outcome when proportional odds are acceptable (loss of power); reading an RRR as a ratio of absolute risks.'),
    ),
  );
}
