/// Développement et validation interne d'un modèle de prédiction binaire
/// (régression logistique, prédicteurs pré-spécifiés).
///
/// Validation interne : bootstrap avec correction de l'optimisme (Harrell,
/// Lee & Mark 1996 ; Steyerberg 2019). Toutes les étapes dépendant des
/// données (ici : l'estimation des coefficients) sont refaites dans chaque
/// échantillon bootstrap ; il n'y a pas de sélection automatique de
/// variables en V1, ce qui évite la principale source de fuite
/// d'information entre préparation, ajustement et validation.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../data/imputation.dart';
import '../regression/pooling.dart';
import '../math/random.dart';
import '../model/result.dart';
import '../regression/design_matrix.dart';
import '../regression/glm.dart';
import 'performance.dart';

/// Spécification d'un modèle de prédiction (TRIPOD+AI : items 3, 5, 6).
class PredictionSpec {
  final String targetPopulation;
  final String outcome;
  final String eventLevel;
  final String horizon;
  final String intendedUse; // p. ex. « dépistage en soins primaires »
  final String setting;
  final List<TermSpec> predictors;
  final List<TermSpec> referencePredictors; // modèle de référence (peut être vide)
  final String referenceName;

  const PredictionSpec({
    required this.targetPopulation,
    required this.outcome,
    required this.eventLevel,
    required this.horizon,
    required this.intendedUse,
    this.setting = '',
    required this.predictors,
    this.referencePredictors = const [],
    this.referenceName = 'Modèle de référence',
  });

  List<String> get missingFields => [
        if (targetPopulation.trim().isEmpty) tr('population cible', 'target population'),
        if (horizon.trim().isEmpty) tr('horizon de prédiction', 'prediction horizon'),
        if (intendedUse.trim().isEmpty) tr('usage prévu', 'intended use'),
      ];

  Map<String, Object?> toJson() => {
        'targetPopulation': targetPopulation,
        'outcome': outcome,
        'eventLevel': eventLevel,
        'horizon': horizon,
        'intendedUse': intendedUse,
        'setting': setting,
        'predictors': [for (final t in predictors) t.toJson()],
        'referencePredictors': [for (final t in referencePredictors) t.toJson()],
        'referenceName': referenceName,
      };

  factory PredictionSpec.fromJson(Map<String, Object?> j) => PredictionSpec(
      targetPopulation: (j['targetPopulation'] as String?) ?? '',
      outcome: j['outcome'] as String,
      eventLevel: j['eventLevel'] as String,
      horizon: (j['horizon'] as String?) ?? '',
      intendedUse: (j['intendedUse'] as String?) ?? '',
      setting: (j['setting'] as String?) ?? '',
      predictors: [for (final t in j['predictors'] as List) TermSpec.fromJson((t as Map).cast())],
      referencePredictors: [for (final t in (j['referencePredictors'] as List? ?? [])) TermSpec.fromJson((t as Map).cast())],
      referenceName: (j['referenceName'] as String?) ?? 'Modèle de référence');
}

class _Perf {
  final double auc, slope, intercept, brier;
  _Perf(this.auc, this.slope, this.intercept, this.brier);
}

List<double> _predict(List<List<double>> x, List<double> beta) => [
      for (final row in x)
        () {
          var e = 0.0;
          for (var j = 0; j < beta.length; j++) {
            e += row[j] * beta[j];
          }
          return 1 / (1 + math.exp(-e));
        }()
    ];

_Perf _perf(List<double> p, List<double> y) {
  final c = calibrationSlopeIntercept(p, y);
  return _Perf(aucFast(p, y), c.slope, c.intercept, brierScore(p, y));
}

/// Génère B jeux d'indices bootstrap reproductibles à partir d'une graine.
List<List<int>> bootstrapIndices(int n, int b, int seed) {
  final rng = SeededRandom(seed);
  return [for (var k = 0; k < b; k++) [for (var i = 0; i < n; i++) rng.nextInt(n)]];
}

/// Résultat de l'optimisme par bootstrap pour un modèle.
class BootstrapValidation {
  final double appAuc, appSlope, appIntercept, appBrier;
  final double optAuc, optSlope, optIntercept, optBrier;
  final int replicates, failed;
  BootstrapValidation(this.appAuc, this.appSlope, this.appIntercept, this.appBrier, this.optAuc, this.optSlope,
      this.optIntercept, this.optBrier, this.replicates, this.failed);
  double get corrAuc => appAuc - optAuc;
  double get corrSlope => appSlope - optSlope;
  double get corrIntercept => appIntercept - optIntercept;
  double get corrBrier => appBrier - optBrier;
}

BootstrapValidation bootstrapOptimism(List<List<double>> x, List<double> y, List<List<int>> indices) {
  final full = fitLogistic(x, y);
  final pApp = _predict(x, full.beta);
  final app = _perf(pApp, y);
  var sAuc = 0.0, sSlope = 0.0, sInt = 0.0, sBrier = 0.0;
  var ok = 0, failed = 0;
  for (final idx in indices) {
    final xb = [for (final i in idx) x[i]];
    final yb = [for (final i in idx) y[i]];
    final ev = yb.where((v) => v == 1).length;
    if (ev == 0 || ev == yb.length) {
      failed++;
      continue;
    }
    final fb = fitLogistic(xb, yb);
    if (!fb.converged || fb.beta.any((b) => !b.isFinite)) {
      failed++;
      continue;
    }
    final pb = _predict(xb, fb.beta);
    final pt = _predict(x, fb.beta);
    final a = _perf(pb, yb), t = _perf(pt, y);
    sAuc += a.auc - t.auc;
    sSlope += a.slope - t.slope;
    sInt += a.intercept - t.intercept;
    sBrier += a.brier - t.brier;
    ok++;
  }
  return BootstrapValidation(app.auc, app.slope, app.intercept, app.brier, sAuc / ok, sSlope / ok, sInt / ok, sBrier / ok,
      ok, failed);
}

/// Développement + validation interne d'un modèle logistique de prédiction.
AnalysisResult developPredictionModel(Dataset ds, PredictionSpec spec,
    {int bootstrap = 200, int seed = 20261010, List<List<int>>? indices, double level = 0.95}) {
  final alerts = <Alert>[];
  final checks = <Check>[];
  final missing = spec.missingFields;
  if (missing.isNotEmpty) {
    alerts.add(Alert('spec_incomplete', Severity.serious,
        tr("Spécification incomplète : ${missing.join(", ")}. Un modèle de prédiction n'a de sens que pour une population, un horizon et un usage définis.",
            'Incomplete specification: ${missing.join(", ")}. A prediction model makes sense only for a defined population, horizon and use.'),
        suggestion: tr("Compléter la fiche du modèle avant d'interpréter les performances.", 'Complete the model sheet before interpreting performance.')));
  }
  final f = ModelFormula(spec.outcome, spec.predictors, eventLevel: spec.eventLevel);
  final d = buildDesign(ds, f, binaryOutcome: true);
  alerts.addAll(d.alerts);
  final fit = fitLogistic(d.x, d.y);
  final sep = separationDiagnostic(d, fit);
  if (!fit.converged || sep.suspected) {
    throw StatInputError('prediction_unstable',
        tr('Le modèle ne converge pas ou présente une séparation (${sep.detail}) : aucune performance ne peut être rapportée. Réduire le nombre de prédicteurs ou regrouper des modalités, sur des bases cliniques.',
            'The model does not converge or shows separation (${sep.detail}): no performance can be reported. Reduce the number of predictors or merge levels, on clinical grounds.'));
  }
  final n = d.n;
  final events = d.y.where((v) => v == 1).length;
  final prev = events / n;
  final params = d.p - 1;
  final p = _predict(d.x, fit.beta);
  final aucCi = aucDeLong(p, d.y, level: level);
  final idx = indices ?? bootstrapIndices(n, bootstrap, seed);
  final bv = bootstrapOptimism(d.x, d.y, idx);
  if (bv.failed > 0) {
    alerts.add(Alert('bootstrap_failures', bv.failed > idx.length * 0.05 ? Severity.serious : Severity.caution,
        tr("${bv.failed} réplique(s) bootstrap sur ${idx.length} écartée(s) (non-convergence ou issue constante) : l'optimisme peut être sous-estimé.",
            '${bv.failed} bootstrap replicate(s) out of ${idx.length} discarded (non-convergence or constant outcome): optimism may be underestimated.')));
  }
  // R² et taille d'échantillon selon Riley (indicatif, a posteriori).
  final llNull = n * (prev * math.log(prev) + (1 - prev) * math.log(1 - prev));
  final r2 = pseudoR2(fit.logLik, llNull, n);
  final r2Adj = r2.coxSnell * bv.corrSlope.clamp(0.0, 1.0);
  final riley = rileySampleSize(parameters: params, prevalence: prev, r2CoxSnell: r2Adj > 0 ? r2Adj : r2.coxSnell);
  final epv = math.min(events, n - events) / math.max(1, params);
  checks.add(Check('sample_size', tr("Taille d'échantillon suffisante (critères de Riley)", 'Sufficient sample size (Riley criteria)'),
      n >= riley.n ? CheckStatus.ok : CheckStatus.violated,
      tr('n = $n ; minimum indicatif ${riley.n.ceil()} (critère i : ${riley.n1.ceil()}, ii : ${riley.n2.ceil()}, iii : ${riley.n3.ceil()}), calculé avec R²(Cox-Snell) corrigé = ${fmt(r2Adj)}, $params paramètre(s), prévalence ${fmtPct(prev)}. EPV = ${fmt(epv)}.',
          'n = $n; indicative minimum ${riley.n.ceil()} (criterion i: ${riley.n1.ceil()}, ii: ${riley.n2.ceil()}, iii: ${riley.n3.ceil()}), computed with adjusted R²(Cox-Snell) = ${fmt(r2Adj)}, $params parameter(s), prevalence ${fmtPct(prev)}. EPV = ${fmt(epv)}.')));
  if (n < riley.n) {
    alerts.add(Alert('riley_insufficient', Severity.serious,
        tr("L'échantillon est inférieur au minimum indicatif de Riley (${riley.n.ceil()}) : surajustement probable.", 'The sample is below the indicative Riley minimum (${riley.n.ceil()}): overfitting likely.'),
        suggestion: tr('Réduire le nombre de paramètres (prédicteurs choisis sur des bases cliniques), ou appliquer une pénalisation, ou collecter davantage de données.',
            'Reduce the number of parameters (predictors chosen on clinical grounds), apply penalization, or collect more data.')));
  }
  checks.add(Check('shrinkage', tr('Surajustement limité (pente corrigée ≥ 0,9)', 'Limited overfitting (corrected slope ≥ 0.9)'),
      bv.corrSlope >= 0.9 ? CheckStatus.ok : (bv.corrSlope >= 0.8 ? CheckStatus.warning : CheckStatus.violated),
      tr("Pente de calibration corrigée de l'optimisme = ${fmt(bv.corrSlope)} (facteur de rétrécissement uniforme). Une pente < 1 indique des prédictions trop extrêmes dans de nouvelles données.",
          'Optimism-corrected calibration slope = ${fmt(bv.corrSlope)} (uniform shrinkage factor). A slope < 1 indicates predictions too extreme in new data.')));
  checks.add(Check('leakage', tr("Pas de fuite d'information entre préparation, ajustement et validation", 'No information leakage between preparation, fitting and validation'),
      CheckStatus.ok,
      tr("Prédicteurs pré-spécifiés, aucune sélection automatique ni imputation dépendant de l'issue ; l'ajustement est refait dans chacun des ${bv.replicates} échantillons bootstrap. Toute recodification décidée après examen des résultats invaliderait cette garantie.",
          'Pre-specified predictors, no automatic selection or outcome-dependent imputation; the fit is redone in each of the ${bv.replicates} bootstrap samples. Any recoding decided after seeing the results would invalidate this guarantee.')));
  checks.add(Check('external_validation', tr('Validation externe', 'External validation'), CheckStatus.notAssessed,
      tr('Non réalisée : la performance dans une autre population, un autre lieu ou une autre période reste inconnue.', 'Not performed: performance in another population, place or period remains unknown.')));
  if (d.excludedBy.isNotEmpty) {
    checks.add(Check('missing_data', tr('Données manquantes documentées', 'Missing data documented'), CheckStatus.warning,
        tr('Analyse en cas complets : ${d.excludedBy.entries.map((e) => "${e.key} : ${e.value}").join(" ; ")}. Le modèle ne pourra pas être appliqué à un patient dont un prédicteur manque.',
            'Complete-case analysis: ${d.excludedBy.entries.map((e) => "${e.key}: ${e.value}").join("; ")}. The model cannot be applied to a patient with a missing predictor.')));
  }

  // Modèle de référence
  Map<String, Object?>? refFig;
  final estimates = <Estimate>[
    Estimate(tr('AUC apparente', 'Apparent AUC'), aucCi.auc, lower: aucCi.lower, upper: aucCi.upper, level: level),
    Estimate(tr("AUC corrigée de l'optimisme", 'Optimism-corrected AUC'), bv.corrAuc),
    Estimate(tr('Pente de calibration corrigée', 'Corrected calibration slope'), bv.corrSlope),
    Estimate(tr('Intercept de calibration corrigé', 'Corrected calibration intercept'), bv.corrIntercept),
    Estimate(tr('Score de Brier corrigé', 'Corrected Brier score'), bv.corrBrier),
  ];
  final tables = <ResultTable>[];
  final stats = <String, double>{
    'n': n.toDouble(),
    'events': events.toDouble(),
    'prevalence': prev,
    'parameters': params.toDouble(),
    'epv': epv,
    'auc_apparent': aucCi.auc,
    'auc_se': aucCi.se,
    'auc_optimism': bv.optAuc,
    'auc_corrected': bv.corrAuc,
    'slope_apparent': bv.appSlope,
    'slope_optimism': bv.optSlope,
    'slope_corrected': bv.corrSlope,
    'intercept_apparent': bv.appIntercept,
    'intercept_corrected': bv.corrIntercept,
    'brier_apparent': bv.appBrier,
    'brier_corrected': bv.corrBrier,
    'r2_coxsnell': r2.coxSnell,
    'r2_nagelkerke': r2.nagelkerke,
    'riley_n': riley.n,
    'bootstrap_ok': bv.replicates.toDouble(),
    for (var j = 0; j < d.p; j++) 'beta_${d.columns[j]}': fit.beta[j],
  };
  if (spec.referencePredictors.isNotEmpty) {
    final dr = buildDesign(ds, ModelFormula(spec.outcome, spec.referencePredictors, eventLevel: spec.eventLevel), binaryOutcome: true);
    final common = {...d.rows}.intersection({...dr.rows});
    final keepNew = [for (var i = 0; i < d.rows.length; i++) if (common.contains(d.rows[i])) i];
    final keepRef = [for (var i = 0; i < dr.rows.length; i++) if (common.contains(dr.rows[i])) i];
    if (common.length != d.rows.length || common.length != dr.rows.length) {
      alerts.add(Alert('reference_rows', Severity.info,
          tr("Données manquantes différentes entre les deux modèles : la comparaison (et l'ajustement du modèle de référence) porte sur les ${common.length} observations complètes pour les deux.",
              'Missing data differ between the two models: the comparison (and the fit of the reference model) uses the ${common.length} observations complete for both.')));
    }
    final xr = [for (final i in keepRef) dr.x[i]];
    final yr = [for (final i in keepRef) dr.y[i]];
    final fr = fitLogistic(xr, yr);
    final pr = _predict(xr, fr.beta);
    final pn = [for (final i in keepNew) p[i]];
    final cmp = compareAucDeLong(pn, pr, yr, level: level);
    final refAuc = aucDeLong(pr, yr, level: level);
    final bvRef = bootstrapOptimism(xr, yr, indices != null && keepRef.length == n ? idx : bootstrapIndices(xr.length, bootstrap, seed));
    estimates.addAll([
      Estimate(tr('AUC apparente — ${spec.referenceName}', 'Apparent AUC — ${spec.referenceName}'), refAuc.auc, lower: refAuc.lower, upper: refAuc.upper, level: level),
      Estimate(tr('AUC corrigée — ${spec.referenceName}', 'Corrected AUC — ${spec.referenceName}'), bvRef.corrAuc),
      Estimate(tr("Différence d'AUC (nouveau − référence, apparente)", 'AUC difference (new − reference, apparent)'), cmp.diff, lower: cmp.lower, upper: cmp.upper, level: level, pValue: cmp.p),
    ]);
    stats.addAll({
      'ref_auc': refAuc.auc,
      'ref_auc_corrected': bvRef.corrAuc,
      'delta_auc': cmp.diff,
      'delta_auc_se': cmp.se,
      'delta_auc_p': cmp.p,
      'delta_auc_corrected': bv.corrAuc - bvRef.corrAuc,
    });
    tables.add(ResultTable(tr('Comparaison au modèle de référence', 'Comparison with the reference model'), [tr('Mesure', 'Measure'), tr('Nouveau modèle', 'New model'), spec.referenceName, tr('Différence', 'Difference')], [
      [tr('AUC apparente', 'Apparent AUC'), fmt(aucCi.auc), fmt(refAuc.auc), tr('${fmt(cmp.diff)} (IC ${fmt(cmp.lower)} à ${fmt(cmp.upper)})', '${fmt(cmp.diff)} (CI ${fmt(cmp.lower)} to ${fmt(cmp.upper)})')],
      [tr('AUC corrigée', 'Corrected AUC'), fmt(bv.corrAuc), fmt(bvRef.corrAuc), fmt(bv.corrAuc - bvRef.corrAuc)],
      [tr('Pente corrigée', 'Corrected slope'), fmt(bv.corrSlope), fmt(bvRef.corrSlope), '—'],
      [tr('Brier corrigé', 'Corrected Brier'), fmt(bv.corrBrier, digits: 3), fmt(bvRef.corrBrier, digits: 3), '—'],
    ]));
    refFig = {'auc': refAuc.auc, 'name': spec.referenceName};
    if (cmp.lower <= 0 && cmp.upper >= 0) {
      alerts.add(Alert('no_auc_gain', Severity.info,
          tr("L'IC de la différence d'AUC inclut 0 : le gain de discrimination par rapport au modèle de référence n'est pas démontré.",
              'The CI of the AUC difference includes 0: the gain in discrimination over the reference model is not demonstrated.')));
    }
  }

  tables.insertAll(0, [
    ResultTable('Performance', [tr('Mesure', 'Measure'), tr('Apparente', 'Apparent'), tr('Optimisme', 'Optimism'), tr('Corrigée', 'Corrected')], [
      [tr('AUC (C-statistique)', 'AUC (C-statistic)'), fmt(bv.appAuc), fmt(bv.optAuc), fmt(bv.corrAuc)],
      [tr('Pente de calibration', 'Calibration slope'), fmt(bv.appSlope), fmt(bv.optSlope), fmt(bv.corrSlope)],
      [tr('Intercept de calibration', 'Calibration intercept'), fmt(bv.appIntercept), fmt(bv.optIntercept), fmt(bv.corrIntercept)],
      [tr('Score de Brier', 'Brier score'), fmt(bv.appBrier, digits: 3), fmt(bv.optBrier, digits: 2), fmt(bv.corrBrier, digits: 3)],
    ]),
    ResultTable(tr('Équation du modèle (à rapporter intégralement, TRIPOD+AI item 10)', 'Model equation (to be reported in full, TRIPOD+AI item 10)'), [tr('Terme', 'Term'), 'β', 'OR'], [
      for (var j = 0; j < d.p; j++) [d.columns[j], fmt(fit.beta[j], digits: 4), j == 0 ? '—' : fmt(math.exp(fit.beta[j]))]
    ]),
  ]);
  final thresholds = [for (var t = 1; t <= 50; t++) t / 100];
  return AnalysisResult(
    methodId: 'prediction_logistic_internal',
    methodName: tr('Modèle de prédiction binaire : développement et validation interne (bootstrap)', 'Binary prediction model: development and internal validation (bootstrap)'),
    inputs: {'spec': spec.toJson(), 'model': d.describe(), 'bootstrap': idx.length, 'seed': indices == null ? seed : tr('indices fournis', 'indices supplied')},
    formula: tr(
        "Régression logistique, prédicteurs pré-spécifiés. Optimisme (Harrell) : pour b = 1…B, ajuster le modèle sur l'échantillon bootstrap, mesurer la performance sur cet échantillon et sur les données d'origine ; optimisme = moyenne des écarts ; performance corrigée = apparente − optimisme. AUC : IC de DeLong ; calibration : logit(P(Y=1)) = a + b·logit(p̂) ; Brier = moyenne (p̂ − y)².",
        'Logistic regression, pre-specified predictors. Optimism (Harrell): for b = 1…B, fit the model on the bootstrap sample, measure performance on that sample and on the original data; optimism = mean of the differences; corrected performance = apparent − optimism. AUC: DeLong CI; calibration: logit(P(Y=1)) = a + b·logit(p̂); Brier = mean (p̂ − y)².'),
    estimates: estimates,
    statistics: stats,
    checks: checks,
    alerts: alerts,
    tables: tables,
    figures: {
      'calibration': calibrationGroups(p, d.y),
      'decisionCurve': decisionCurve(p, d.y, thresholds),
      'reference': ?refFig,
      'stage': 'internal',
    },
    log: [
      tr('Modèle : ${d.formula}', 'Model: ${d.formula}'),
      tr('n = $n, événements = $events, paramètres = $params.', 'n = $n, events = $events, parameters = $params.'),
      tr('Bootstrap : ${bv.replicates} réplique(s) valides sur ${idx.length}${indices == null ? " (graine $seed)" : " (indices fournis)"}.',
          'Bootstrap: ${bv.replicates} valid replicate(s) out of ${idx.length}${indices == null ? " (seed $seed)" : " (indices supplied)"}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr("Objectif prédictif : estimer un risque individuel d'issue binaire à l'horizon « ${spec.horizon} ». Le bootstrap estime de combien la performance mesurée sur les données de développement est trop optimiste.",
          'Predictive aim: estimate an individual risk of a binary outcome at the horizon "${spec.horizon}". The bootstrap estimates how optimistic the performance measured on the development data is.'),
      whatItMeans: tr('Discrimination : AUC corrigée ${fmt(bv.corrAuc)} (apparente ${fmt(aucCi.auc)}). Calibration : pente corrigée ${fmt(bv.corrSlope)} ${bv.corrSlope < 0.9 ? "(prédictions trop extrêmes attendues dans de nouvelles données)" : ""}. Ces valeurs décrivent la performance attendue dans une population SEMBLABLE à celle de développement.',
          'Discrimination: corrected AUC ${fmt(bv.corrAuc)} (apparent ${fmt(aucCi.auc)}). Calibration: corrected slope ${fmt(bv.corrSlope)} ${bv.corrSlope < 0.9 ? "(predictions expected to be too extreme in new data)" : ""}. These values describe the expected performance in a population SIMILAR to the development one.'),
      notJustified: tr("Qualifier le modèle de « validé » ou de « validé cliniquement » : seule une validation interne a été faite ; aucune validation externe, aucune étude d'impact. Interpréter les coefficients comme des effets causaux (modèle prédictif, non explicatif). Utiliser le modèle hors de la population cible.",
          'Calling the model "validated" or "clinically validated": only internal validation was done; no external validation, no impact study. Interpreting the coefficients as causal effects (predictive, not explanatory model). Using the model outside the target population.'),
    ),
  );
}


/// Lignes d'un jeu de données (doublons permis : rééchantillonnage bootstrap).
Dataset _rowsOf(Dataset ds, List<int> idx, String source) =>
    Dataset(ds.names, [for (final i in idx) [for (final n in ds.names) ds.cell(i, n)]], source: source,
        dictionary: {for (final e in ds.dictionary.entries) e.key: Variable.fromJson(e.value.toJson())});

/// Développement et validation interne avec imputation multiple.
///
/// 1. Les sujets dont l'issue manque sont exclus (l'issue n'est pas imputée).
/// 2. MICE (m jeux) sur l'issue et les prédicteurs ; modèle final = coefficients
///    combinés par les règles de Rubin ; performance apparente = moyenne sur
///    les m jeux.
/// 3. Optimisme : dans CHAQUE réplique bootstrap, l'échantillon incomplet est
///    réimputé, le modèle réajusté, puis évalué sur lui-même et sur les m jeux
///    imputés d'origine (« imputation dans le bootstrap », Wahl et al. 2016) :
///    aucune information ne passe de la validation vers l'imputation.
AnalysisResult developPredictionModelMI(Dataset ds, PredictionSpec spec,
    {int m = 10, int maxit = 10, int bootstrap = 100, int seed = 20261012, double level = 0.95}) {
  final vars = {spec.outcome, for (final t in spec.predictors) t.variable};
  final yText = ds.text(spec.outcome);
  final keep = [for (var i = 0; i < ds.rowCount; i++) if (!ds.excludedRows.contains(i) && yText[i] != null) i];
  final base = _rowsOf(ds, keep, tr('${ds.source} — issue observée', '${ds.source} — observed outcome'));
  final exclude = {for (final n in base.names) if (!vars.contains(n)) n};
  final imp = multipleImputation(base, MiceOptions(m: m, maxit: maxit, seed: seed, exclude: exclude));
  final f = ModelFormula(spec.outcome, spec.predictors, eventLevel: spec.eventLevel);
  final designs = [for (final c in imp.completed) buildDesign(c, f, binaryOutcome: true)];
  final cols = designs.first.columns;
  final p = cols.length;
  final fits = [for (final d in designs) fitLogistic(d.x, d.y)];
  final pooled = [
    for (var j = 0; j < p; j++)
      rubin(cols[j], [for (final fi in fits) fi.beta[j]], [for (final fi in fits) fi.cov.get(j, j)], (designs.first.n - p).toDouble(), level: level)
  ];
  final beta = [for (final x in pooled) x.estimate];
  // Performance apparente du modèle combiné, moyennée sur les m jeux.
  double avg(List<double> v) => v.fold(0.0, (a, b) => a + b) / v.length;
  final appPerf = [for (final d in designs) _perf(_predict(d.x, beta), d.y)];
  final app = _Perf(avg([for (final q in appPerf) q.auc]), avg([for (final q in appPerf) q.slope]), avg([for (final q in appPerf) q.intercept]),
      avg([for (final q in appPerf) q.brier]));
  // Optimisme avec imputation dans chaque réplique.
  final rng = SeededRandom(seed + 1);
  var sAuc = 0.0, sSlope = 0.0, sInt = 0.0, sBrier = 0.0, ok = 0, failed = 0;
  final n = base.rowCount;
  for (var b = 0; b < bootstrap; b++) {
    final idx = [for (var i = 0; i < n; i++) rng.nextInt(n)];
    final bs = _rowsOf(base, idx, 'bootstrap $b');
    try {
      final bi = multipleImputation(bs, MiceOptions(m: 1, maxit: maxit, seed: seed + 1000 + b, exclude: exclude));
      final db = buildDesign(bi.completed.first, f, binaryOutcome: true);
      if (db.columns.length != p) {
        failed++;
        continue;
      }
      final fb = fitLogistic(db.x, db.y);
      if (!fb.converged || fb.beta.any((v) => !v.isFinite)) {
        failed++;
        continue;
      }
      final a = _perf(_predict(db.x, fb.beta), db.y);
      final tests = [for (final d in designs) _perf(_predict(d.x, fb.beta), d.y)];
      sAuc += a.auc - avg([for (final t in tests) t.auc]);
      sSlope += a.slope - avg([for (final t in tests) t.slope]);
      sInt += a.intercept - avg([for (final t in tests) t.intercept]);
      sBrier += a.brier - avg([for (final t in tests) t.brier]);
      ok++;
    } on StatInputError {
      failed++;
    }
  }
  if (ok == 0) throw StatInputError('mi_bootstrap', tr('Aucune réplique bootstrap exploitable.', 'No usable bootstrap replicate.'));
  final opt = _Perf(sAuc / ok, sSlope / ok, sInt / ok, sBrier / ok);
  final corr = _Perf(app.auc - opt.auc, app.slope - opt.slope, app.intercept - opt.intercept, app.brier - opt.brier);
  final events = designs.first.y.where((v) => v == 1).length;
  final maxFmi = pooled.skip(1).map((x) => x.fmi).fold(0.0, math.max);
  final pct = (level * 100).round();
  final pAvg = [for (var i = 0; i < n; i++) avg([for (final d in designs) _predict([d.x[i]], beta).first])];
  final yObs = designs.first.y;
  return AnalysisResult(
    methodId: 'prediction_logistic_internal_mi',
    methodName: tr('Modèle de prédiction binaire avec imputation multiple : développement et validation interne', 'Binary prediction model with multiple imputation: development and internal validation'),
    inputs: {
      'spec': spec.toJson(),
      'model': {...designs.first.describe(), 'excludedMissing': {tr('${spec.outcome} (issue non imputée)', '${spec.outcome} (outcome not imputed)'): ds.rowCount - ds.excludedRows.length - n}},
      'imputation': imp.options.toJson(),
      'imputed': [for (final dg in imp.diagnostics) dg.variable],
      'bootstrap': bootstrap,
      'seed': seed,
    },
    formula: tr(
        "MICE (PMM / régression logistique bayésienne), m = $m ; modèle final : coefficients combinés (Rubin) ; performance apparente : moyenne sur les m jeux ; optimisme : bootstrap de l'échantillon INCOMPLET, réimputation dans chaque réplique, test sur les m jeux d'origine ; performance corrigée = apparente − optimisme.",
        'MICE (PMM / Bayesian logistic regression), m = $m; final model: pooled coefficients (Rubin); apparent performance: mean over the m datasets; optimism: bootstrap of the INCOMPLETE sample, re-imputation in each replicate, test on the m original datasets; corrected performance = apparent − optimism.'),
    estimates: [
      Estimate(tr('AUC apparente (moyenne des m jeux)', 'Apparent AUC (mean of the m datasets)'), app.auc),
      Estimate(tr("AUC corrigée de l'optimisme", 'Optimism-corrected AUC'), corr.auc),
      Estimate(tr('Pente de calibration corrigée', 'Corrected calibration slope'), corr.slope),
      Estimate(tr('Intercept de calibration corrigé', 'Corrected calibration intercept'), corr.intercept),
      Estimate(tr('Score de Brier corrigé', 'Corrected Brier score'), corr.brier),
    ],
    statistics: {
      'n': n.toDouble(),
      'events': events.toDouble(),
      'm': m.toDouble(),
      'auc_apparent': app.auc,
      'auc_optimism': opt.auc,
      'auc_corrected': corr.auc,
      'slope_apparent': app.slope,
      'slope_corrected': corr.slope,
      'intercept_corrected': corr.intercept,
      'brier_apparent': app.brier,
      'brier_corrected': corr.brier,
      'bootstrap_ok': ok.toDouble(),
      for (var j = 0; j < p; j++) 'beta_${cols[j]}': beta[j],
      for (var j = 0; j < p; j++) 'se_${cols[j]}': pooled[j].se,
      for (var j = 0; j < p; j++) 'fmi_${cols[j]}': pooled[j].fmi,
    },
    checks: [
      Check('leakage', tr("Pas de fuite d'information entre imputation, ajustement et validation", 'No information leakage between imputation, fitting and validation'), CheckStatus.ok,
          tr("Imputation refaite dans chacune des $ok répliques bootstrap ; l'issue est incluse dans le modèle d'imputation mais n'est jamais imputée.",
              'Imputation redone in each of the $ok bootstrap replicates; the outcome is included in the imputation model but never imputed.')),
      Check('mi_m', tr("Nombre d'imputations suffisant (m ≥ 100 × fmi)", 'Sufficient number of imputations (m ≥ 100 × fmi)'), m >= (maxFmi * 100).ceil() ? CheckStatus.ok : CheckStatus.warning,
          tr('m = $m ; fmi maximale = ${fmtPct(maxFmi)}.', 'm = $m; maximum fmi = ${fmtPct(maxFmi)}.')),
      Check('shrinkage', tr('Surajustement limité (pente corrigée ≥ 0,9)', 'Limited overfitting (corrected slope ≥ 0.9)'),
          corr.slope >= 0.9 ? CheckStatus.ok : (corr.slope >= 0.8 ? CheckStatus.warning : CheckStatus.violated), tr('Pente corrigée = ${fmt(corr.slope)}.', 'Corrected slope = ${fmt(corr.slope)}.')),
      Check('external_validation', tr('Validation externe', 'External validation'), CheckStatus.notAssessed, tr('À réaliser sur des données indépendantes.', 'To be performed on independent data.')),
      for (final dg in imp.diagnostics)
        Check('mi_${dg.variable}', tr('Imputation de « ${dg.variable} » (${dg.method})', 'Imputation of "${dg.variable}" (${dg.method})'), CheckStatus.notAssessed,
            tr('${dg.missing} valeur(s) imputée(s) ; moyenne observée ${fmt(dg.observedMean)} ; moyenne imputée ${fmt(avg(dg.imputedMeans))}. Hypothèse MAR à discuter.',
                '${dg.missing} imputed value(s); observed mean ${fmt(dg.observedMean)}; imputed mean ${fmt(avg(dg.imputedMeans))}. MAR assumption to be discussed.')),
    ],
    alerts: [
      if (failed > 0) Alert('bootstrap_failures', failed > bootstrap * 0.05 ? Severity.serious : Severity.caution, tr('$failed réplique(s) écartée(s).', '$failed replicate(s) discarded.')),
      Alert('mi_mar', Severity.info,
          tr("L'imputation multiple suppose des données manquantes au hasard (MAR) conditionnellement aux variables du modèle ; pour appliquer le modèle à un patient incomplet, une stratégie d'imputation au moment de l'usage doit aussi être prévue.",
              'Multiple imputation assumes data missing at random (MAR) conditional on the model variables; to apply the model to an incomplete patient, an imputation strategy at the time of use must also be planned.')),
    ],
    tables: [
      ResultTable('Performance', [tr('Mesure', 'Measure'), tr('Apparente', 'Apparent'), tr('Optimisme', 'Optimism'), tr('Corrigée', 'Corrected')], [
        ['AUC', fmt(app.auc), fmt(opt.auc), fmt(corr.auc)],
        [tr('Pente de calibration', 'Calibration slope'), fmt(app.slope), fmt(opt.slope), fmt(corr.slope)],
        [tr('Intercept de calibration', 'Calibration intercept'), fmt(app.intercept), fmt(opt.intercept), fmt(corr.intercept)],
        [tr('Score de Brier', 'Brier score'), fmt(app.brier, digits: 3), fmt(opt.brier, digits: 2), fmt(corr.brier, digits: 3)],
      ]),
      ResultTable(tr('Équation du modèle (coefficients combinés, Rubin)', 'Model equation (pooled coefficients, Rubin)'), [tr('Terme', 'Term'), 'β', tr('ES', 'SE'), tr('IC $pct %', '$pct% CI'), 'fmi'], [
        for (final x in pooled) [x.name, fmt(x.estimate, digits: 4), fmt(x.se), '${fmt(x.lower)} – ${fmt(x.upper)}', fmtPct(x.fmi)]
      ]),
      ResultTable(tr('Variables imputées', 'Imputed variables'), ['Variable', tr('Méthode', 'Method'), tr('Manquants', 'Missing')], [
        for (final dg in imp.diagnostics) [dg.variable, dg.method, '${dg.missing}']
      ]),
    ],
    figures: {
      'calibration': calibrationGroups(pAvg, yObs),
      'decisionCurve': decisionCurve(pAvg, yObs, [for (var t = 1; t <= 50; t++) t / 100]),
      'miChains': {for (final dg in imp.diagnostics) dg.variable: dg.chainMeans},
      'stage': 'internal',
    },
    log: [tr('$m imputations, $maxit itérations ; bootstrap : $ok répliques valides sur $bootstrap (graine $seed).', '$m imputations, $maxit iterations; bootstrap: $ok valid replicates out of $bootstrap (seed $seed).')],
    interpretation: Interpretation(
      whyThisMethod: tr("Des prédicteurs ont des valeurs manquantes : l'analyse en cas complets perdrait des sujets et pourrait biaiser le modèle. L'imputation multiple, refaite dans chaque réplique bootstrap, donne une performance corrigée honnête.",
          'Predictors have missing values: a complete-case analysis would lose subjects and could bias the model. Multiple imputation, redone in each bootstrap replicate, gives an honest corrected performance.'),
      whatItMeans: tr('AUC corrigée ${fmt(corr.auc)} (apparente ${fmt(app.auc)}), pente corrigée ${fmt(corr.slope)}, sur $n sujets ($events événements) sans exclure les sujets incomplets.',
          'Corrected AUC ${fmt(corr.auc)} (apparent ${fmt(app.auc)}), corrected slope ${fmt(corr.slope)}, on $n subjects ($events events) without excluding incomplete subjects.'),
      notJustified: tr("Qualifier le modèle de « validé » ; oublier que son usage chez un patient incomplet exige une règle d'imputation ; supposer que l'imputation corrige des données manquantes non au hasard.",
          'Calling the model "validated"; forgetting that using it in an incomplete patient requires an imputation rule; assuming imputation corrects data missing not at random.'),
    ),
  );
}
