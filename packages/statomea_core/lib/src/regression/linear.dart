/// Régression linéaire (moindres carrés ordinaires, factorisation QR).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

class LinearFit {
  final List<double> beta;
  final Matrix covUnscaled; // (XᵀX)⁻¹
  final double sigma2;
  final int df;
  final List<double> fitted, residuals, leverage;
  LinearFit(this.beta, this.covUnscaled, this.sigma2, this.df, this.fitted, this.residuals, this.leverage);
}

/// Ajustement brut (utilisé aussi par les diagnostics).
LinearFit fitOls(List<List<double>> x, List<double> y) {
  final qr = householderQr(x, y);
  if (qr.aliased.isNotEmpty) {
    throw StatInputError('aliased',
        tr('Colonnes parfaitement colinéaires (index ${qr.aliased.join(", ")}) : un terme est une combinaison exacte des autres (p. ex. catégorie vide, variable dupliquée).',
            'Perfectly collinear columns (index ${qr.aliased.join(", ")}): a term is an exact combination of the others (e.g. empty category, duplicated variable).'));
  }
  final p = qr.rank;
  final beta = backSolve(qr.r, qr.qtY.sublist(0, p));
  final cov = invertRtR(qr.r);
  final n = x.length;
  final fitted = [for (final row in x) _dot(row, beta)];
  final res = [for (var i = 0; i < n; i++) y[i] - fitted[i]];
  final rss = res.fold(0.0, (a, e) => a + e * e);
  final lev = [
    for (final row in x) _dot(row, cov.multiplyVector(row)),
  ];
  return LinearFit(beta, cov, rss / (n - p), n - p, fitted, res, lev);
}

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

AnalysisResult linearRegression(DesignMatrix d, {double level = 0.95, String unit = ''}) {
  final fit = fitOls(d.x, d.y);
  final n = d.n, p = d.p;
  final tq = tQuantile(1 - (1 - level) / 2, fit.df.toDouble());
  final coefs = <Coefficient>[];
  for (var j = 0; j < p; j++) {
    final se = math.sqrt(fit.sigma2 * fit.covUnscaled.get(j, j));
    final t = fit.beta[j] / se;
    coefs.add(Coefficient(d.columns[j], fit.beta[j], se, t, tTwoSidedP(t, fit.df.toDouble()),
        fit.beta[j] - tq * se, fit.beta[j] + tq * se));
  }
  final ybar = d.y.fold(0.0, (a, b) => a + b) / n;
  final tss = d.y.fold(0.0, (a, v) => a + (v - ybar) * (v - ybar));
  final rss = fit.sigma2 * fit.df;
  final r2 = 1 - rss / tss;
  final adjR2 = 1 - (1 - r2) * (n - 1) / fit.df;
  final fStat = ((tss - rss) / (p - 1)) / fit.sigma2;
  final fP = p > 1 ? fUpper(fStat, p - 1.0, fit.df.toDouble()) : double.nan;

  // Diagnostics
  final checks = <Check>[];
  final alerts = <Alert>[...d.alerts];
  final stdRes = [
    for (var i = 0; i < n; i++) fit.residuals[i] / math.sqrt(fit.sigma2 * (1 - fit.leverage[i]))
  ];
  final cook = [for (var i = 0; i < n; i++) stdRes[i] * stdRes[i] * fit.leverage[i] / (p * (1 - fit.leverage[i]))];
  final cookCut = 4 / n;
  final influential = [for (var i = 0; i < n; i++) if (cook[i] > cookCut) i];
  final maxCook = cook.reduce(math.max);
  final highLev = [for (var i = 0; i < n; i++) if (fit.leverage[i] > 2 * p / n) i];
  checks.add(Check(
      'influence',
      tr("Pas d'observation exagérément influente (distance de Cook)", "No unduly influential observation (Cook's distance)"),
      maxCook > 1 ? CheckStatus.violated : (influential.isNotEmpty ? CheckStatus.warning : CheckStatus.ok),
      tr('Cook max = ${fmt(maxCook)} ; ${influential.length} observation(s) > 4/n ; ${highLev.length} à levier > 2p/n. Lignes : ${influential.take(10).map((i) => d.rows[i] + 1).join(", ")}${influential.length > 10 ? "…" : ""}.',
          'Max Cook = ${fmt(maxCook)}; ${influential.length} observation(s) > 4/n; ${highLev.length} with leverage > 2p/n. Rows: ${influential.take(10).map((i) => d.rows[i] + 1).join(", ")}${influential.length > 10 ? "…" : ""}.')));

  // Homoscédasticité : test de Breusch-Pagan studentisé (Koenker).
  final e2 = [for (final r in fit.residuals) r * r];
  double bpStat = double.nan, bpP = double.nan;
  if (p > 1) {
    final aux = fitOls(d.x, e2);
    final m = e2.fold(0.0, (a, b) => a + b) / n;
    final tssA = e2.fold(0.0, (a, v) => a + (v - m) * (v - m));
    final rssA = aux.sigma2 * aux.df;
    bpStat = n * (1 - rssA / tssA);
    bpP = chiSquareUpper(bpStat, p - 1.0);
  }
  checks.add(Check('homoscedasticity', tr('Variance des résidus constante (Breusch-Pagan)', 'Constant residual variance (Breusch-Pagan)'),
      bpP.isNaN ? CheckStatus.notAssessed : (bpP < 0.05 ? CheckStatus.warning : CheckStatus.ok),
      bpP.isNaN
          ? tr('Non évaluable.', 'Not assessable.')
          : tr('BP = ${fmt(bpStat)}, ${fmtP(bpP)}. ${bpP < 0.05 ? "Hétéroscédasticité possible : les ES peuvent être faux ; envisager une transformation ou des ES robustes." : ""}',
              'BP = ${fmt(bpStat)}, ${fmtP(bpP)}. ${bpP < 0.05 ? "Possible heteroscedasticity: SEs may be wrong; consider a transformation or robust SEs." : ""}')));

  // Normalité des résidus (utile surtout pour petits n).
  final sr = [...stdRes]..sort();
  final m3 = stdRes.fold(0.0, (a, v) => a + v * v * v) / n;
  checks.add(Check('residual_normality', tr('Résidus approximativement normaux', 'Approximately normal residuals'),
      (m3.abs() > 1 && n < 50) ? CheckStatus.warning : CheckStatus.ok,
      tr('Asymétrie des résidus standardisés ≈ ${fmt(m3)} ; résidus extrêmes : ${fmt(sr.first)} et ${fmt(sr.last)}. Avec n = $n, ${n >= 50 ? "l'inférence est robuste à un écart modéré." : "vérifier le graphique quantile-quantile."}',
          'Skewness of standardized residuals ≈ ${fmt(m3)}; extreme residuals: ${fmt(sr.first)} and ${fmt(sr.last)}. With n = $n, ${n >= 50 ? "inference is robust to a moderate departure." : "check the quantile-quantile plot."}')));

  // Linéarité : ajout d'un terme quadratique pour chaque prédicteur continu.
  final linNotes = <String>[];
  var nonLinear = false;
  for (var j = 1; j < p; j++) {
    final col = [for (final r in d.x) r[j]];
    if (col.toSet().length <= 2) continue; // indicatrice
    final mu = col.fold(0.0, (a, b) => a + b) / n;
    final xq = [for (var i = 0; i < n; i++) [...d.x[i], math.pow(col[i] - mu, 2).toDouble()]];
    try {
      final fq = fitOls(xq, d.y);
      final b = fq.beta.last;
      final se = math.sqrt(fq.sigma2 * fq.covUnscaled.get(p, p));
      final pq = tTwoSidedP(b / se, fq.df.toDouble());
      if (pq < 0.05) nonLinear = true;
      linNotes.add(tr('${d.columns[j]} : terme quadratique ${fmtP(pq)}', '${d.columns[j]}: quadratic term ${fmtP(pq)}'));
    } on StatInputError {
      // colonne quadratique colinéaire : ignorée
    }
  }
  checks.add(Check('linearity', tr('Relation linéaire avec les prédicteurs continus', 'Linear relationship with continuous predictors'),
      linNotes.isEmpty ? CheckStatus.notAssessed : (nonLinear ? CheckStatus.warning : CheckStatus.ok),
      linNotes.isEmpty
          ? tr('Aucun prédicteur continu.', 'No continuous predictor.')
          : tr('${linNotes.join(" ; ")}. Un terme quadratique significatif suggère une courbure ; examiner le graphique des résidus.',
              '${linNotes.join("; ")}. A significant quadratic term suggests curvature; examine the residual plot.')));

  final g = gvif(d);
  final col = collinearityCheck(g);
  checks.add(col);
  if (col.status == CheckStatus.violated) {
    alerts.add(Alert('collinearity', Severity.serious,
        tr('Colinéarité forte : les coefficients concernés sont instables et leurs ES gonflés.', 'Strong collinearity: the coefficients involved are unstable and their SEs inflated.'),
        suggestion: tr('Retirer ou combiner des prédicteurs redondants, choisis sur des bases cliniques.', 'Remove or combine redundant predictors, chosen on clinical grounds.')));
  }
  final ppar = p - 1;
  if (ppar > 0 && n / ppar < 10) {
    alerts.add(Alert('overfit_linear', Severity.caution,
        tr('$n observations pour $ppar prédicteur(s) (${fmt(n / ppar)} par paramètre) : risque de surajustement.', '$n observations for $ppar predictor(s) (${fmt(n / ppar)} per parameter): risk of overfitting.'),
        suggestion: tr('Viser au moins 10 à 20 observations par paramètre estimé.', 'Aim for at least 10 to 20 observations per estimated parameter.')));
  }
  final u = unit.isEmpty ? '' : ' $unit';
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  return AnalysisResult(
    methodId: 'linear_regression',
    methodName: tr('Régression linéaire (moindres carrés ordinaires)', 'Linear regression (ordinary least squares)'),
    inputs: {'model': d.describe(), 'level': level},
    formula: tr('y = Xβ + ε, ε ~ N(0, σ²) ; β̂ = (XᵀX)⁻¹Xᵀy par factorisation QR ; ES(β̂) = √[σ̂²(XᵀX)⁻¹] ; IC = β̂ ± t(1−α/2 ; n−p)·ES.',
        'y = Xβ + ε, ε ~ N(0, σ²); β̂ = (XᵀX)⁻¹Xᵀy by QR factorization; SE(β̂) = √[σ̂²(XᵀX)⁻¹]; CI = β̂ ± t(1−α/2; n−p)·SE.'),
    estimates: [
      for (final c in coefs)
        Estimate(c.name, c.estimate, lower: c.lower, upper: c.upper, level: level, pValue: c.p, se: c.se)
    ],
    statistics: {
      'n': n.toDouble(),
      'p': p.toDouble(),
      'df_residual': fit.df.toDouble(),
      'sigma': math.sqrt(fit.sigma2),
      'r2': r2,
      'adj_r2': adjR2,
      'F': fStat,
      'F_p': fP,
      'bp': bpStat,
      'bp_p': bpP,
      'max_cook': maxCook,
      for (final e in g.entries) 'gvif_${e.key}': e.value.$1,
    },
    checks: checks,
    alerts: alerts,
    tables: [
      coefficientTable(coefs, effectLabel: 'β', level: level),
      ResultTable(tr('Codage et observations', 'Coding and observations'), [tr('Élément', 'Item'), tr('Détail', 'Detail')], [
        [tr('Modèle', 'Model'), d.formula],
        [tr('Observations utilisées', 'Observations used'), '$n'],
        [tr('Exclues (manquants)', 'Excluded (missing)'), d.excludedBy.isEmpty ? '0' : d.excludedBy.entries.map((e) => tr('${e.key} : ${e.value}', '${e.key}: ${e.value}')).join(tr(' ; ', '; '))],
        [tr('Exclues (corrections)', 'Excluded (corrections)'), '${d.excludedByCorrection}'],
        for (final c in d.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    figures: {
      'residuals': {'fitted': fit.fitted, 'residuals': fit.residuals, 'standardized': stdRes, 'leverage': fit.leverage, 'cook': cook},
    },
    log: [
      tr('Matrice de plan : $n × $p ; rang plein.', 'Design matrix: $n × $p; full rank.'),
      tr('σ̂ = ${fmt(math.sqrt(fit.sigma2))}, R² = ${fmt(r2)}, R² ajusté = ${fmt(adjR2)}.', 'σ̂ = ${fmt(math.sqrt(fit.sigma2))}, R² = ${fmt(r2)}, adjusted R² = ${fmt(adjR2)}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Issue quantitative continue ; on modélise sa moyenne comme combinaison linéaire des prédicteurs.',
          'Continuous quantitative outcome; its mean is modelled as a linear combination of the predictors.'),
      whatItMeans: coefs.length > 1
          ? tr('À autres variables du modèle fixées, une unité de plus de « ${main.name} » est associée à une variation moyenne de ${fmt(main.estimate)}$u (IC ${fmt(main.lower)} à ${fmt(main.upper)}). Le modèle explique ${fmtPct(r2)} de la variance (R² ajusté ${fmtPct(adjR2)}).',
              'Holding the other model variables fixed, one more unit of "${main.name}" is associated with a mean change of ${fmt(main.estimate)}$u (CI ${fmt(main.lower)} to ${fmt(main.upper)}). The model explains ${fmtPct(r2)} of the variance (adjusted R² ${fmtPct(adjR2)}).')
          : tr('Modèle sans prédicteur.', 'Model without predictors.'),
      notJustified: tr("Interpréter un coefficient ajusté comme l'effet causal d'une intervention sur la variable (confusion résiduelle, choix des covariables, sens causal) ; extrapoler hors de la plage observée ; utiliser R² comme preuve de validité du modèle.",
          'Interpreting an adjusted coefficient as the causal effect of intervening on the variable (residual confounding, covariate choice, causal direction); extrapolating beyond the observed range; using R² as proof of model validity.'),
    ),
  );
}
