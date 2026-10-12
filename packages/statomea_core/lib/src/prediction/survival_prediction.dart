/// Modèle pronostique de survie (Cox) : risque de base, risque prédit à un
/// horizon, discrimination (C de Harrell), calibration (pente, courbe à
/// l'horizon) et validation interne par bootstrap avec correction de
/// l'optimisme (Harrell). Mêmes principes que le modèle logistique : prédicteurs
/// pré-spécifiés, ajustement refait dans chaque réplique, aucun modèle déclaré
/// « validé ».
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../inference/survival.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/common.dart';
import '../regression/cox.dart';
import 'model_development.dart';

List<double> _lp(List<List<double>> x, List<double> beta) => [
      for (final r in x)
        () {
          var s = 0.0;
          for (var j = 0; j < beta.length; j++) {
            s += r[j] * beta[j];
          }
          return s;
        }()
    ];

/// Risque cumulé de base H₀(t) au point x = 0 (comme `survfit.coxph`) :
/// Efron (`ctype = 2`, défaut de R pour un modèle ajusté avec Efron) ou
/// Breslow (`ctype = 1`).
double baselineCumHazard(List<double> time, List<double> status, List<double> lp, double horizon, {bool efron = true}) {
  final w = [for (final e in lp) math.exp(e)];
  final eventTimes = {for (var i = 0; i < time.length; i++) if (status[i] == 1 && time[i] <= horizon) time[i]}.toList()..sort();
  var h = 0.0;
  for (final tj in eventTimes) {
    var r = 0.0, dSum = 0.0, m = 0;
    for (var i = 0; i < time.length; i++) {
      if (time[i] >= tj) r += w[i];
      if (time[i] == tj && status[i] == 1) {
        dSum += w[i];
        m++;
      }
    }
    if (efron) {
      for (var k = 0; k < m; k++) {
        h += 1 / (r - k / m * dSum);
      }
    } else {
      h += m / r;
    }
  }
  return h;
}

/// Pente de calibration : coefficient du prédicteur linéaire dans un modèle de Cox à une seule covariable.
double coxCalibrationSlope(List<double> time, List<double> status, List<double> lp, {bool efron = true}) =>
    fitCox([for (final v in lp) [v]], time, status, efron: efron).beta.first;

/// Développement et validation interne d'un modèle pronostique de Cox.
/// [horizon] : temps auquel le risque est prédit (même unité que la durée).
AnalysisResult developCoxPredictionModel(SurvivalDesign s,
    {required double horizon,
    int bootstrap = 200,
    int seed = 20261011,
    List<List<int>>? indices,
    bool efron = true,
    String targetPopulation = '',
    String intendedUse = '',
    String timeUnit = '',
    double level = 0.95}) {
  final d = s.design, t = s.time, st = s.status;
  final n = t.length, p = d.p, events = s.events;
  if (events < 2) throw StatInputError('n_too_small', tr('Moins de 2 événements : aucun modèle pronostique estimable.', 'Fewer than 2 events: no prognostic model can be estimated.'));
  final km = kaplanMeier(t, st);
  final kmAt = km.at(horizon);
  if (horizon <= 0 || kmAt == null) {
    throw StatInputError('horizon_beyond_follow_up',
        tr("L'horizon (${fmt(horizon)}) dépasse le suivi disponible : le risque observé n'y est pas estimable.",
            'The horizon (${fmt(horizon)}) exceeds the available follow-up: the observed risk cannot be estimated there.'));
  }
  final fit = fitCox(d.x, t, st, efron: efron);
  if (!fit.converged || fit.beta.any((b) => !b.isFinite || b.abs() > 20)) {
    throw StatInputError('prediction_unstable',
        tr('Le modèle de Cox ne converge pas ou présente une vraisemblance monotone : aucune performance ne peut être rapportée.',
            'The Cox model does not converge or has a monotone likelihood: no performance can be reported.'));
  }
  final lp = _lp(d.x, fit.beta);
  final h0 = baselineCumHazard(t, st, lp, horizon, efron: efron);
  final risk = [for (final e in lp) 1 - math.exp(-h0 * math.exp(e))];
  final cApp = coxConcordance(t, st, lp).c;

  // Optimisme (Harrell) : ajustement sur l'échantillon bootstrap, mesures sur cet échantillon et sur les données d'origine.
  final idx = indices ?? bootstrapIndices(n, bootstrap, seed);
  var sumC = 0.0, sumS = 0.0;
  var ok = 0, failed = 0;
  for (final b in idx) {
    final xb = [for (final i in b) d.x[i]], tb = [for (final i in b) t[i]], db = [for (final i in b) st[i]];
    if (!db.contains(1)) {
      failed++;
      continue;
    }
    final fb = fitCox(xb, tb, db, efron: efron);
    if (!fb.converged || fb.beta.any((v) => !v.isFinite || v.abs() > 20)) {
      failed++;
      continue;
    }
    final lpOrig = _lp(d.x, fb.beta);
    sumC += coxConcordance(tb, db, _lp(xb, fb.beta)).c - coxConcordance(t, st, lpOrig).c;
    sumS += 1 - coxCalibrationSlope(t, st, lpOrig, efron: efron);
    ok++;
  }
  if (ok == 0) throw StatInputError('mi_bootstrap', tr('Aucune réplique bootstrap exploitable.', 'No usable bootstrap replicate.'));
  final optC = sumC / ok, optS = sumS / ok;
  final cCorr = cApp - optC, slopeCorr = 1 - optS;

  // Calibration à l'horizon : quintiles de risque prédit, risque observé par Kaplan-Meier.
  // Tri stable (ex aequo dans l'ordre des lignes, comme order() de R) : des risques identiques ne changent pas de quintile.
  final order = List<int>.generate(n, (i) => i)..sort((a, b) {
      final c = risk[a].compareTo(risk[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final groups = <Map<String, double>>[];
  for (var g = 0; g < 5; g++) {
    final sel = order.sublist((g * n / 5).floor(), ((g + 1) * n / 5).floor());
    if (sel.isEmpty) continue;
    final kg = kaplanMeier([for (final i in sel) t[i]], [for (final i in sel) st[i]], level: level).at(horizon);
    if (kg == null) continue;
    groups.add({
      'predicted': sel.fold(0.0, (a, i) => a + risk[i]) / sel.length,
      'observed': 1 - kg.s,
      'lower': 1 - kg.upper,
      'upper': 1 - kg.lower,
      'n': sel.length.toDouble(),
    });
  }
  final meanRisk = risk.fold(0.0, (a, v) => a + v) / n;
  final obsRisk = 1 - kmAt.s;
  final atRisk = [for (final v in t) if (v >= horizon) v].length;
  final evBefore = [for (var i = 0; i < n; i++) if (st[i] == 1 && t[i] <= horizon) i].length;
  final u = timeUnit.isEmpty ? '' : ' $timeUnit';
  final epv = events / p;
  final zph = p > 0 ? coxZph(s, fit, efron: efron) : null;

  final checks = <Check>[
    Check('sample_size', tr('Événements par paramètre (EPV ≥ 20 recommandé pour un modèle pronostique)', 'Events per parameter (EPV ≥ 20 recommended for a prognostic model)'),
        epv >= 20 ? CheckStatus.ok : (epv >= 10 ? CheckStatus.warning : CheckStatus.violated),
        tr('$events événement(s) pour $p paramètre(s) : EPV = ${fmt(epv)}.', '$events event(s) for $p parameter(s): EPV = ${fmt(epv)}.')),
    Check('shrinkage', tr('Surajustement limité (pente corrigée ≥ 0,9)', 'Limited overfitting (corrected slope ≥ 0.9)'),
        slopeCorr >= 0.9 ? CheckStatus.ok : (slopeCorr >= 0.8 ? CheckStatus.warning : CheckStatus.violated),
        tr('Pente de calibration corrigée = ${fmt(slopeCorr)} (facteur de rétrécissement uniforme).', 'Corrected calibration slope = ${fmt(slopeCorr)} (uniform shrinkage factor).')),
    Check('follow_up', tr("Suivi suffisant à l'horizon", 'Sufficient follow-up at the horizon'),
        atRisk >= math.max(10, n * 0.1) ? CheckStatus.ok : CheckStatus.warning,
        tr("$atRisk sujet(s) encore suivi(s) à ${fmt(horizon)}$u, $evBefore événement(s) avant l'horizon.",
            '$atRisk subject(s) still followed at ${fmt(horizon)}$u, $evBefore event(s) before the horizon.')),
    if (zph != null)
      Check('proportional_hazards', tr('Risques proportionnels (cox.zph)', 'Proportional hazards (cox.zph)'),
          zph.globalP < 0.05 ? CheckStatus.warning : CheckStatus.ok,
          tr('Global : χ² = ${fmt(zph.globalChi2)} (ddl ${zph.globalDf}), ${fmtP(zph.globalP)}.', 'Global: χ² = ${fmt(zph.globalChi2)} (df ${zph.globalDf}), ${fmtP(zph.globalP)}.')),
    Check('censoring', tr('Censure non informative', 'Non-informative censoring'), CheckStatus.notAssessed,
        tr('Hypothèse non vérifiable par le calcul ; à argumenter.', 'Assumption not verifiable by computation; to be argued.')),
    Check('external_validation', tr('Validation externe', 'External validation'), CheckStatus.notAssessed,
        tr('Non réalisée : la performance dans une autre population reste inconnue.', 'Not performed: performance in another population remains unknown.')),
  ];
  final alerts = <Alert>[
    ...d.alerts,
    if (failed > 0) Alert('bootstrap_failures', failed > idx.length * 0.05 ? Severity.serious : Severity.caution,
        tr("$failed réplique(s) bootstrap sur ${idx.length} écartée(s) (aucun événement ou non-convergence) : l'optimisme peut être sous-estimé.",
            '$failed bootstrap replicate(s) out of ${idx.length} discarded (no event or non-convergence): optimism may be underestimated.')),
    if (targetPopulation.trim().isEmpty || intendedUse.trim().isEmpty)
      Alert('spec_incomplete', Severity.serious,
          tr("Population cible ou usage prévu non renseigné : un modèle pronostique n'a de sens que pour une population et un usage définis.",
              'Target population or intended use not filled in: a prognostic model makes sense only for a defined population and use.')),
    Alert('cox_prediction_scope', Severity.info,
        tr("Le risque prédit à l'horizon repose sur le risque de base estimé dans ces données : il ne se transporte pas tel quel à une autre population (recalibration nécessaire).",
            'The predicted risk at the horizon relies on the baseline hazard estimated in these data: it does not transfer as is to another population (recalibration needed).')),
  ];
  final pct = (level * 100).round();
  return AnalysisResult(
    methodId: 'prediction_cox_internal',
    methodName: tr('Modèle pronostique de survie (Cox) : développement et validation interne (bootstrap)',
        'Prognostic survival model (Cox): development and internal validation (bootstrap)'),
    inputs: {
      'model': d.describe(),
      'horizon': horizon,
      'timeUnit': timeUnit,
      'ties': efron ? 'efron' : 'breslow',
      'bootstrap': idx.length,
      'seed': indices == null ? seed : tr('indices fournis', 'indices supplied'),
      'spec': {'targetPopulation': targetPopulation, 'intendedUse': intendedUse, 'horizon': '${fmt(horizon)}$u'},
      'survival': {
        'time': s.timeName,
        'status': s.statusName,
        'eventLevel': s.eventLevel,
        'terms': [for (final t in s.terms) t.toJson()],
        'columns': d.columns,
      },
    },
    formula: tr(
        "Cox (prédicteurs pré-spécifiés). Risque à l'horizon t₀ : 1 − exp[−H₀(t₀)·exp(xᵀβ)], H₀ = risque cumulé de base (${efron ? "Efron" : "Breslow"}) au point x = 0. C de Harrell ; pente de calibration = coefficient de xᵀβ dans un Cox à une covariable. Optimisme (Harrell) : pour chaque réplique bootstrap, réajuster, mesurer sur l'échantillon bootstrap et sur les données d'origine ; performance corrigée = apparente − optimisme moyen. Calibration à t₀ : quintiles de risque prédit, risque observé par Kaplan-Meier.",
        "Cox (pre-specified predictors). Risk at horizon t₀: 1 − exp[−H₀(t₀)·exp(xᵀβ)], H₀ = baseline cumulative hazard (${efron ? "Efron" : "Breslow"}) at x = 0. Harrell's C; calibration slope = coefficient of xᵀβ in a one-covariate Cox model. Optimism (Harrell): for each bootstrap replicate, refit, measure on the bootstrap sample and on the original data; corrected performance = apparent − mean optimism. Calibration at t₀: quintiles of predicted risk, observed risk by Kaplan-Meier."),
    estimates: [
      Estimate(tr('C de Harrell apparent', "Apparent Harrell's C"), cApp),
      Estimate(tr("C de Harrell corrigé de l'optimisme", "Optimism-corrected Harrell's C"), cCorr),
      Estimate(tr('Pente de calibration corrigée', 'Corrected calibration slope'), slopeCorr),
      Estimate(tr('Risque moyen prédit à ${fmt(horizon)}$u', 'Mean predicted risk at ${fmt(horizon)}$u'), meanRisk),
      Estimate(tr('Risque observé à ${fmt(horizon)}$u (Kaplan-Meier)', 'Observed risk at ${fmt(horizon)}$u (Kaplan-Meier)'), obsRisk,
          lower: 1 - kmAt.upper, upper: 1 - kmAt.lower, level: level),
    ],
    statistics: {
      'n': n.toDouble(),
      'events': events.toDouble(),
      'epv': epv,
      'horizon': horizon,
      'H0_horizon': h0,
      'c_apparent': cApp,
      'c_optimism': optC,
      'c_corrected': cCorr,
      'slope_optimism': optS,
      'slope_corrected': slopeCorr,
      'mean_risk_horizon': meanRisk,
      'km_risk_horizon': obsRisk,
      'replicates': ok.toDouble(),
      'failed': failed.toDouble(),
      for (var j = 0; j < p; j++) 'beta_${d.columns[j]}': fit.beta[j],
    },
    checks: checks,
    alerts: alerts,
    tables: [
      ResultTable('Performance', [tr('Mesure', 'Measure'), tr('Apparente', 'Apparent'), tr('Optimisme', 'Optimism'), tr('Corrigée', 'Corrected')], [
        [tr('C de Harrell', "Harrell's C"), fmt(cApp), fmt(optC), fmt(cCorr)],
        [tr('Pente de calibration', 'Calibration slope'), '1', fmt(optS), fmt(slopeCorr)],
      ]),
      ResultTable(tr("Équation du modèle (à rapporter intégralement, TRIPOD+AI)", 'Model equation (to be reported in full, TRIPOD+AI)'), [tr('Terme', 'Term'), 'β', 'HR'], [
        for (var j = 0; j < p; j++) [d.columns[j], fmt(fit.beta[j], digits: 4), fmt(math.exp(fit.beta[j]))],
        [tr('H₀(${fmt(horizon)}) — risque cumulé de base à x = 0', 'H₀(${fmt(horizon)}) — baseline cumulative hazard at x = 0'), fmt(h0, digits: 6), '—'],
      ]),
      ResultTable(tr('Calibration à ${fmt(horizon)}$u (quintiles de risque prédit)', 'Calibration at ${fmt(horizon)}$u (quintiles of predicted risk)'),
          ['n', tr('Risque prédit moyen', 'Mean predicted risk'), tr('Risque observé (KM)', 'Observed risk (KM)'), tr('IC $pct %', '$pct% CI')], [
        for (final g in groups)
          ['${g['n']!.toInt()}', fmtPct(g['predicted']), fmtPct(g['observed']), '${fmtPct(g['lower'])} – ${fmtPct(g['upper'])}']
      ]),
      coefficientTable(
          [
            for (var j = 0; j < p; j++)
              () {
                final se = math.sqrt(fit.cov.get(j, j));
                final z = normalQuantile(1 - (1 - level) / 2);
                return Coefficient(d.columns[j], fit.beta[j], se, fit.beta[j] / se, normalTwoSidedP(fit.beta[j] / se), fit.beta[j] - z * se, fit.beta[j] + z * se);
              }()
          ],
          effectLabel: 'HR',
          exponentiate: true,
          level: level),
    ],
    figures: {'calibration': groups, 'stage': 'internal'},
    log: [
      tr('Modèle : ${d.formula}', 'Model: ${d.formula}'),
      tr('n = $n, événements = $events, paramètres = $p.', 'n = $n, events = $events, parameters = $p.'),
      tr('Bootstrap : $ok réplique(s) valides sur ${idx.length}${indices == null ? " (graine $seed)" : " (indices fournis)"}.',
          'Bootstrap: $ok valid replicate(s) out of ${idx.length}${indices == null ? " (seed $seed)" : " (indices supplied)"}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Objectif pronostique avec un délai censuré : le modèle de Cox estime le risque individuel d'événement à l'horizon ${fmt(horizon)}$u ; le bootstrap estime de combien la performance mesurée sur les données de développement est trop optimiste.",
          'Prognostic aim with a censored time: the Cox model estimates the individual risk of the event at the horizon ${fmt(horizon)}$u; the bootstrap estimates how optimistic the performance measured on the development data is.'),
      whatItMeans: tr(
          'Discrimination : C corrigé ${fmt(cCorr)} (apparent ${fmt(cApp)} ; 0,5 = hasard). Calibration : pente corrigée ${fmt(slopeCorr)}${slopeCorr < 0.9 ? " (prédictions trop extrêmes attendues dans de nouvelles données)" : ""} ; à ${fmt(horizon)}$u, risque moyen prédit ${fmtPct(meanRisk)} contre ${fmtPct(obsRisk)} observé (Kaplan-Meier). Ces valeurs décrivent la performance attendue dans une population SEMBLABLE.',
          'Discrimination: corrected C ${fmt(cCorr)} (apparent ${fmt(cApp)}; 0.5 = chance). Calibration: corrected slope ${fmt(slopeCorr)}${slopeCorr < 0.9 ? " (predictions expected to be too extreme in new data)" : ""}; at ${fmt(horizon)}$u, mean predicted risk ${fmtPct(meanRisk)} versus ${fmtPct(obsRisk)} observed (Kaplan-Meier). These values describe the expected performance in a SIMILAR population.'),
      notJustified: tr(
          'Qualifier le modèle de « validé » ou de « validé cliniquement » : seule une validation interne a été faite ; prédire au-delà du suivi disponible ; appliquer le risque de base à une autre population sans recalibration ; interpréter les HR comme des effets causaux.',
          'Calling the model "validated" or "clinically validated": only internal validation was done; predicting beyond the available follow-up; applying the baseline hazard to another population without recalibration; interpreting the HRs as causal effects.'),
    ),
  );
}
