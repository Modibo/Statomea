/// Analyse de données imputées : un modèle par jeu complété, puis combinaison
/// par les règles de Rubin (1987) avec les degrés de liberté de Barnard &
/// Rubin (1999), comme `mice::pool`.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../data/imputation.dart';
import '../math/distributions.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'design_matrix.dart';
import 'glm.dart';
import 'linear.dart';

class PooledParameter {
  final String name;
  final double estimate, ubar, b, t, se, riv, lambda, fmi, df, lower, upper, p;
  PooledParameter(this.name, this.estimate, this.ubar, this.b, this.t, this.se, this.riv, this.lambda, this.fmi, this.df, this.lower,
      this.upper, this.p);
}

/// Règles de Rubin pour un paramètre : [q] estimations, [u] variances (m valeurs).
PooledParameter rubin(String name, List<double> q, List<double> u, double dfCom, {double level = 0.95}) {
  final m = q.length;
  final qbar = q.fold(0.0, (a, b) => a + b) / m;
  final ubar = u.fold(0.0, (a, b) => a + b) / m;
  var b = 0.0;
  for (final x in q) {
    b += (x - qbar) * (x - qbar);
  }
  b /= (m - 1);
  final t = ubar + (1 + 1 / m) * b;
  final riv = (1 + 1 / m) * b / ubar;
  final lambda = (1 + 1 / m) * b / t;
  // Barnard-Rubin (mice:::barnard.rubin).
  final lam = math.max(lambda, 1e-4);
  final dfOld = (m - 1) / (lam * lam);
  final dfObs = (dfCom + 1) / (dfCom + 3) * dfCom * (1 - lam);
  final df = dfOld * dfObs / (dfOld + dfObs);
  final fmi = (riv + 2 / (df + 3)) / (1 + riv);
  final se = math.sqrt(t);
  final tq = tQuantile(1 - (1 - level) / 2, df);
  return PooledParameter(name, qbar, ubar, b, t, se, riv, lambda, fmi, df, qbar - tq * se, qbar + tq * se, tTwoSidedP(qbar / se, df));
}

/// Modèles disponibles pour l'analyse poolée.
enum PooledModel { linear, logistic, poissonRobust }

/// Ajuste le modèle sur chaque jeu complété et combine les résultats.
AnalysisResult pooledRegression(List<Dataset> completed, ModelFormula f, PooledModel model,
    {double level = 0.95, StudyDesign design = StudyDesign.unknown, ImputationResult? imputation}) {
  final m = completed.length;
  if (m < 2) throw StatInputError('mi_m', tr('Au moins 2 jeux imputés sont nécessaires.', 'At least 2 imputed datasets are required.'));
  List<String>? cols;
  final qs = <List<double>>[], us = <List<double>>[];
  var n = 0;
  for (final ds in completed) {
    final d = buildDesign(ds, f, binaryOutcome: model != PooledModel.linear);
    cols ??= d.columns;
    n = d.n;
    switch (model) {
      case PooledModel.linear:
        final fit = fitOls(d.x, d.y);
        qs.add(fit.beta);
        us.add([for (var j = 0; j < d.p; j++) fit.sigma2 * fit.covUnscaled.get(j, j)]);
      case PooledModel.logistic:
        final fit = fitLogistic(d.x, d.y);
        qs.add(fit.beta);
        us.add([for (var j = 0; j < d.p; j++) fit.cov.get(j, j)]);
      case PooledModel.poissonRobust:
        final fit = fitPoissonRobust(d.x, d.y);
        qs.add(fit.beta);
        us.add([for (var j = 0; j < d.p; j++) fit.cov.get(j, j)]);
    }
  }
  final p = cols!.length;
  final dfCom = (n - p).toDouble();
  final pooled = [for (var j = 0; j < p; j++) rubin(cols[j], [for (final q in qs) q[j]], [for (final u in us) u[j]], dfCom, level: level)];
  final ratio = model != PooledModel.linear;
  final effect = switch (model) { PooledModel.linear => 'β', PooledModel.logistic => 'OR', PooledModel.poissonRobust => design == StudyDesign.crossSectional ? tr('RP', 'PR') : 'RR' };
  double back(double v) => ratio ? math.exp(v) : v;
  final maxFmi = pooled.skip(1).map((x) => x.fmi).fold(0.0, math.max);
  final pct = (level * 100).round();
  final alerts = <Alert>[
    if (m < (maxFmi * 100).ceil())
      Alert('mi_m_low', Severity.caution,
          tr("Fraction d'information manquante maximale ${fmtPct(maxFmi)} : la règle de White et al. (2011) suggère m ≥ ${(maxFmi * 100).ceil()} imputations (ici $m).",
              'Maximum fraction of missing information ${fmtPct(maxFmi)}: the rule of White et al. (2011) suggests m ≥ ${(maxFmi * 100).ceil()} imputations (here $m).')),
    Alert('mi_mar', Severity.info,
        tr("L'imputation multiple suppose des données manquantes au hasard (MAR) conditionnellement aux variables du modèle d'imputation ; si le mécanisme dépend de la valeur manquante elle-même (MNAR), une analyse de sensibilité est nécessaire.",
            'Multiple imputation assumes data missing at random (MAR) conditional on the variables of the imputation model; if the mechanism depends on the missing value itself (MNAR), a sensitivity analysis is needed.')),
  ];
  final main = pooled.length > 1 ? pooled[1] : pooled.first;
  return AnalysisResult(
    methodId: 'mi_${model.name}',
    methodName: tr('Imputation multiple (MICE) et ${switch (model) { PooledModel.linear => "régression linéaire", PooledModel.logistic => "régression logistique", PooledModel.poissonRobust => "Poisson robuste" }} — règles de Rubin',
        "Multiple imputation (MICE) and ${switch (model) { PooledModel.linear => "linear regression", PooledModel.logistic => "logistic regression", PooledModel.poissonRobust => "robust Poisson" }} — Rubin's rules"),
    inputs: {'formula': f.toJson(), 'm': m, 'n': n, 'imputation': imputation?.options.toJson(), 'imputed': [for (final d in imputation?.diagnostics ?? <ImputationDiagnostic>[]) d.variable]},
    formula: tr('Q̄ = Σq̂_i/m ; Ū = Σû_i/m ; B = Σ(q̂_i − Q̄)²/(m − 1) ; T = Ū + (1 + 1/m)B ; ddl de Barnard-Rubin ; IC = Q̄ ± t(ddl)·√T ; fmi = (r + 2/(ddl + 3))/(1 + r), r = (1 + 1/m)B/Ū.',
        'Q̄ = Σq̂_i/m; Ū = Σû_i/m; B = Σ(q̂_i − Q̄)²/(m − 1); T = Ū + (1 + 1/m)B; Barnard-Rubin df; CI = Q̄ ± t(df)·√T; fmi = (r + 2/(df + 3))/(1 + r), r = (1 + 1/m)B/Ū.'),
    estimates: [
      for (final x in pooled.skip(1))
        Estimate('$effect — ${x.name}', back(x.estimate), lower: back(x.lower), upper: back(x.upper), level: level, pValue: x.p, se: x.se),
    ],
    statistics: {
      'm': m.toDouble(),
      'n': n.toDouble(),
      'df_com': dfCom,
      for (final x in pooled) 'beta_${x.name}': x.estimate,
      for (final x in pooled) 'se_${x.name}': x.se,
      for (final x in pooled) 'df_${x.name}': x.df,
      for (final x in pooled) 'fmi_${x.name}': x.fmi,
      for (final x in pooled) 'riv_${x.name}': x.riv,
      for (final x in pooled) 'b_${x.name}': x.b,
    },
    checks: [
      Check('mi_m', tr("Nombre d'imputations suffisant (m ≥ 100 × fmi)", 'Sufficient number of imputations (m ≥ 100 × fmi)'), m >= (maxFmi * 100).ceil() ? CheckStatus.ok : CheckStatus.warning,
          tr('m = $m ; fmi maximale = ${fmtPct(maxFmi)}.', 'm = $m; maximum fmi = ${fmtPct(maxFmi)}.')),
      if (imputation != null)
        for (final dg in imputation.diagnostics)
          Check('mi_${dg.variable}', tr('Imputation de « ${dg.variable} » (${dg.method})', 'Imputation of "${dg.variable}" (${dg.method})'), CheckStatus.notAssessed,
              tr('${dg.missing} valeur(s) imputée(s) ; moyenne observée ${fmt(dg.observedMean)}, moyenne des valeurs imputées ${fmt(dg.imputedMeans.fold(0.0, (a, b) => a + b) / dg.imputedMeans.length)} (une différence est attendue si les données ne sont pas MCAR). Vérifier la convergence des chaînes (figure).',
                  '${dg.missing} imputed value(s); observed mean ${fmt(dg.observedMean)}, mean of imputed values ${fmt(dg.imputedMeans.fold(0.0, (a, b) => a + b) / dg.imputedMeans.length)} (a difference is expected if data are not MCAR). Check chain convergence (figure).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Coefficients combinés (règles de Rubin)', "Pooled coefficients (Rubin's rules)"), [tr('Terme', 'Term'), 'Q̄', tr('ES', 'SE'), tr('ddl', 'df'), 'fmi', if (ratio) effect, tr('IC $pct %', '$pct% CI'), 'p'], [
        for (final x in pooled)
          [
            x.name,
            fmt(x.estimate, digits: 4),
            fmt(x.se),
            fmt(x.df),
            fmtPct(x.fmi),
            if (ratio) isIntercept(x.name) ? '—' : fmt(back(x.estimate)),
            ratio && !isIntercept(x.name) ? '${fmt(back(x.lower))} – ${fmt(back(x.upper))}' : '${fmt(x.lower)} – ${fmt(x.upper)}',
            fmtP(x.p),
          ]
      ]),
      if (imputation != null)
        ResultTable(tr('Variables imputées', 'Imputed variables'), ['Variable', tr('Méthode', 'Method'), tr('Manquants', 'Missing'), tr('Moyenne observée', 'Observed mean'), tr('Moyenne imputée', 'Imputed mean')], [
          for (final dg in imputation.diagnostics)
            [dg.variable, dg.method, '${dg.missing}', fmt(dg.observedMean), fmt(dg.imputedMeans.fold(0.0, (a, b) => a + b) / dg.imputedMeans.length)]
        ]),
    ],
    figures: {
      if (imputation != null)
        'miChains': {
          for (final dg in imputation.diagnostics) dg.variable: dg.chainMeans,
        },
    },
    log: [tr('$m jeux imputés analysés ; n = $n par jeu ; ddl complets = ${fmt(dfCom)}.', '$m imputed datasets analysed; n = $n per dataset; complete-data df = ${fmt(dfCom)}.')],
    interpretation: Interpretation(
      whyThisMethod: tr("Des valeurs manquent pour des variables du modèle : l'imputation multiple utilise toute l'information disponible et propage l'incertitude due aux valeurs manquantes (variance entre imputations), au lieu d'exclure les sujets incomplets.",
          'Values are missing for model variables: multiple imputation uses all available information and propagates the uncertainty due to missing values (between-imputation variance), instead of excluding incomplete subjects.'),
      whatItMeans: pooled.length > 1
          ? tr("« ${main.name} » : $effect = ${fmt(back(main.estimate))} (IC ${fmt(back(main.lower))} à ${fmt(back(main.upper))}), ${fmtP(main.p)} ; ${fmtPct(main.fmi)} de l'information sur ce coefficient est « manquante » (fmi).",
              '"${main.name}": $effect = ${fmt(back(main.estimate))} (CI ${fmt(back(main.lower))} to ${fmt(back(main.upper))}), ${fmtP(main.p)}; ${fmtPct(main.fmi)} of the information on this coefficient is "missing" (fmi).')
          : '',
      notJustified: tr("Considérer les valeurs imputées comme observées ; analyser un seul jeu imputé ; imputer sans inclure l'issue dans le modèle d'imputation ; supposer que l'imputation corrige des données manquantes non au hasard (MNAR).",
          'Treating imputed values as observed; analysing a single imputed dataset; imputing without including the outcome in the imputation model; assuming imputation corrects data missing not at random (MNAR).'),
    ),
  );
}
