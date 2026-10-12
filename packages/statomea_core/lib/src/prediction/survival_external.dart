/// Validation externe d'un modèle pronostique de Cox : l'équation (β, risque
/// cumulé de base H₀ à l'horizon) est appliquée SANS réestimation à des données
/// indépendantes. Discrimination (C de Harrell), calibration (pente ; risque
/// observé / prédit à l'horizon ; courbe par quintile), recalibrations
/// proposées (risque de base seul, puis pente et risque de base).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../inference/survival.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/cox.dart';
import '../regression/design_matrix.dart';
import 'survival_prediction.dart';

/// Équation d'un modèle pronostique de Cox, transportable.
class CoxEquation {
  final String name, time, status, eventLevel, timeUnit, source;
  final List<TermSpec> predictors;
  final Map<String, double> coefficients;
  final double horizon;

  /// Risque cumulé de base H₀(horizon) au point x = 0.
  final double baselineCumHazard;
  const CoxEquation(
      {required this.name,
      required this.time,
      required this.status,
      required this.eventLevel,
      required this.predictors,
      required this.coefficients,
      required this.horizon,
      required this.baselineCumHazard,
      this.timeUnit = '',
      this.source = ''});

  /// Coefficients dont les noms sont exprimés dans la langue courante.
  Map<String, double> get localCoefficients => {for (final e in coefficients.entries) localizeColumn(e.key): e.value};

  factory CoxEquation.fromDevelopment(AnalysisResult r, {String? name}) {
    if (r.methodId != 'prediction_cox_internal' || r.inputs['survival'] is! Map) {
      throw StatInputError('not_prediction',
          tr("Le résultat choisi n'est pas un modèle pronostique de Cox développé dans Statoméa.", 'The selected result is not a Cox prognostic model developed in Statoméa.'));
    }
    final sv = (r.inputs['survival'] as Map).cast<String, Object?>();
    final cols = [for (final c in sv['columns'] as List) c as String];
    final spec = ((r.inputs['spec'] as Map?) ?? {}).cast<String, Object?>();
    return CoxEquation(
      name: name ?? tr('Modèle pronostique développé', 'Developed prognostic model'),
      time: sv['time'] as String,
      status: sv['status'] as String,
      eventLevel: sv['eventLevel'] as String,
      predictors: [for (final t in sv['terms'] as List) TermSpec.fromJson((t as Map).cast())],
      coefficients: {for (final c in cols) c: r.statistics['beta_$c']!},
      horizon: r.statistics['horizon']!,
      baselineCumHazard: r.statistics['H0_horizon']!,
      timeUnit: (r.inputs['timeUnit'] as String?) ?? '',
      source: tr('développement : ${spec['targetPopulation'] ?? ''}', 'development: ${spec['targetPopulation'] ?? ''}'),
    );
  }

  Map<String, Object?> toJson() => {
        'kind': 'cox',
        'name': name,
        'time': time,
        'status': status,
        'eventLevel': eventLevel,
        'predictors': [for (final t in predictors) t.toJson()],
        'coefficients': coefficients,
        'horizon': horizon,
        'baselineCumHazard': baselineCumHazard,
        'timeUnit': timeUnit,
        'source': source,
      };

  factory CoxEquation.fromJson(Map<String, Object?> j) => CoxEquation(
        name: (j['name'] as String?) ?? tr('Modèle importé', 'Imported model'),
        time: j['time'] as String,
        status: j['status'] as String,
        eventLevel: (j['eventLevel'] as String?) ?? '1',
        predictors: [for (final t in j['predictors'] as List) TermSpec.fromJson((t as Map).cast())],
        coefficients: {for (final e in (j['coefficients'] as Map).entries) e.key as String: (e.value as num).toDouble()},
        horizon: (j['horizon'] as num).toDouble(),
        baselineCumHazard: (j['baselineCumHazard'] as num).toDouble(),
        timeUnit: (j['timeUnit'] as String?) ?? '',
        source: (j['source'] as String?) ?? tr('importée', 'imported'),
      );
}

/// Validation externe d'une équation de Cox sur [ds].
AnalysisResult externalValidationCox(Dataset ds, CoxEquation eq, {double level = 0.95, String population = ''}) {
  final s = buildSurvivalDesign(ds, eq.time, eq.status, eq.eventLevel, eq.predictors);
  final d = s.design, t = s.time, st = s.status;
  final coefs = eq.localCoefficients;
  final missing = [for (final c in coefs.keys) if (!d.columns.contains(c)) c];
  final extra = [for (final c in d.columns) if (!coefs.containsKey(c)) c];
  if (missing.isNotEmpty || extra.isNotEmpty) {
    throw StatInputError(
        'equation_mismatch',
        tr("Le codage des données ne correspond pas à l'équation du modèle. ${missing.isEmpty ? "" : "Termes de l'équation absents des données : ${missing.join(", ")}. "}${extra.isEmpty ? "" : "Modalités des données absentes de l'équation : ${extra.join(", ")}. "}Vérifier les noms des variables, les modalités et les catégories de référence.",
            'The data coding does not match the model equation. ${missing.isEmpty ? "" : "Equation terms missing from the data: ${missing.join(", ")}. "}${extra.isEmpty ? "" : "Data levels missing from the equation: ${extra.join(", ")}. "}Check the variable names, levels and reference categories.'));
  }
  final n = t.length, events = s.events, h = eq.horizon;
  if (events < 2) throw StatInputError('n_too_small', tr('Moins de 2 événements : aucune validation possible.', 'Fewer than 2 events: no validation possible.'));
  final kmAt = kaplanMeier(t, st, level: level).at(h);
  if (kmAt == null) {
    throw StatInputError('horizon_beyond_follow_up',
        tr("L'horizon du modèle (${fmt(h)}) dépasse le suivi de ces données : la calibration n'y est pas estimable.",
            "The model's horizon (${fmt(h)}) exceeds the follow-up of these data: calibration cannot be estimated there."));
  }
  final beta = [for (final c in d.columns) coefs[c]!];
  final lp = [
    for (final r in d.x)
      () {
        var v = 0.0;
        for (var j = 0; j < beta.length; j++) {
          v += r[j] * beta[j];
        }
        return v;
      }()
  ];
  final risk = [for (final e in lp) 1 - math.exp(-eq.baselineCumHazard * math.exp(e))];
  final c = coxConcordance(t, st, lp).c;
  final slopeFit = fitCox([for (final v in lp) [v]], t, st);
  final slope = slopeFit.beta.first, slopeSe = math.sqrt(slopeFit.cov.get(0, 0));
  final z = normalQuantile(1 - (1 - level) / 2);
  final slLo = slope - z * slopeSe, slHi = slope + z * slopeSe;
  final meanRisk = risk.fold(0.0, (a, v) => a + v) / n;
  final obs = 1 - kmAt.s, obsLo = 1 - kmAt.upper, obsHi = 1 - kmAt.lower;
  final oe = obs / meanRisk, oeLo = obsLo / meanRisk, oeHi = obsHi / meanRisk;
  // Recalibrations : H₀ réestimé avec β fixés (décalage), puis pente et H₀.
  final h0Int = baselineCumHazard(t, st, lp, h);
  final h0Slope = baselineCumHazard(t, st, [for (final v in lp) slope * v], h);

  final order = List<int>.generate(n, (i) => i)..sort((a, b) {
      final k = risk[a].compareTo(risk[b]);
      return k != 0 ? k : a.compareTo(b);
    });
  final groups = <Map<String, double>>[];
  for (var g = 0; g < 5; g++) {
    final sel = order.sublist((g * n / 5).floor(), ((g + 1) * n / 5).floor());
    if (sel.isEmpty) continue;
    final kg = kaplanMeier([for (final i in sel) t[i]], [for (final i in sel) st[i]], level: level).at(h);
    if (kg == null) continue;
    groups.add({
      'predicted': sel.fold(0.0, (a, i) => a + risk[i]) / sel.length,
      'observed': 1 - kg.s,
      'lower': 1 - kg.upper,
      'upper': 1 - kg.lower,
      'n': sel.length.toDouble(),
    });
  }
  final u = eq.timeUnit.isEmpty ? '' : ' ${eq.timeUnit}';
  final pct = (level * 100).round();
  final miscal = oeLo > 1 || oeHi < 1;
  final slopeOff = slLo > 1 || slHi < 1;
  final alerts = <Alert>[
    ...d.alerts,
    if (math.min(events, n - events) < 100)
      Alert('external_small', Severity.caution,
          tr('$events événement(s) : une validation externe vise au moins 100 événements (idéalement 200) pour estimer précisément la calibration.',
              '$events event(s): an external validation aims for at least 100 events (ideally 200) to estimate calibration precisely.')),
    if (miscal)
      Alert('calibration_in_the_large', Severity.serious,
          tr('À ${fmt(h)}$u, le modèle ${oe > 1 ? "SOUS-ESTIME" : "SURESTIME"} le risque (observé/prédit = ${fmt(oe)}).',
              'At ${fmt(h)}$u, the model ${oe > 1 ? "UNDERESTIMATES" : "OVERESTIMATES"} the risk (observed/predicted = ${fmt(oe)}).'),
          suggestion: tr('Réestimer le risque de base sur la population locale (recalibration proposée dans les tableaux), puis valider à nouveau.',
              'Re-estimate the baseline hazard on the local population (recalibration proposed in the tables), then validate again.')),
    if (slopeOff)
      Alert('calibration_slope', Severity.serious,
          tr('Pente de calibration ${fmt(slope)} : prédictions ${slope < 1 ? "trop extrêmes (surajustement ou population plus homogène)" : "pas assez dispersées"}.',
              'Calibration slope ${fmt(slope)}: predictions ${slope < 1 ? "too extreme (overfitting or a more homogeneous population)" : "not spread enough"}.')),
  ];
  return AnalysisResult(
    methodId: 'external_validation_cox',
    methodName: tr("Validation externe d'un modèle pronostique de Cox", 'External validation of a Cox prognostic model'),
    inputs: {'equation': eq.toJson(), 'model': d.describe(), 'population': population, 'level': level},
    formula: tr(
        "Risque à t₀ = 1 − exp[−H₀(t₀)·exp(xᵀβ)] avec β et H₀ FIXÉS (non réestimés). C de Harrell ; pente : coefficient de xᵀβ dans un Cox à une covariable ; observé/prédit à t₀ = (1 − KM(t₀)) / risque moyen prédit. Recalibration : H₀ réestimé avec xᵀβ en décalage, puis avec pente·xᵀβ.",
        'Risk at t₀ = 1 − exp[−H₀(t₀)·exp(xᵀβ)] with β and H₀ FIXED (not re-estimated). Harrell\'s C; slope: coefficient of xᵀβ in a one-covariate Cox model; observed/predicted at t₀ = (1 − KM(t₀)) / mean predicted risk. Recalibration: H₀ re-estimated with xᵀβ as an offset, then with slope·xᵀβ.'),
    estimates: [
      Estimate(tr('C de Harrell', "Harrell's C"), c),
      Estimate(tr('Pente de calibration (idéal 1)', 'Calibration slope (ideal 1)'), slope, lower: slLo, upper: slHi, level: level, se: slopeSe),
      Estimate(tr('Rapport observé/prédit à ${fmt(h)}$u (idéal 1)', 'Observed/predicted ratio at ${fmt(h)}$u (ideal 1)'), oe, lower: oeLo, upper: oeHi, level: level),
      Estimate(tr('Risque moyen prédit à ${fmt(h)}$u', 'Mean predicted risk at ${fmt(h)}$u'), meanRisk),
      Estimate(tr('Risque observé à ${fmt(h)}$u (Kaplan-Meier)', 'Observed risk at ${fmt(h)}$u (Kaplan-Meier)'), obs, lower: obsLo, upper: obsHi, level: level),
    ],
    statistics: {
      'n': n.toDouble(),
      'events': events.toDouble(),
      'horizon': h,
      'c': c,
      'slope': slope,
      'slope_se': slopeSe,
      'mean_risk': meanRisk,
      'km_risk': obs,
      'oe': oe,
      'H0_original': eq.baselineCumHazard,
      'H0_recal_intercept': h0Int,
      'H0_recal_slope': h0Slope,
    },
    checks: [
      Check('calibration_in_the_large', tr("Risque observé compatible avec le risque prédit à l'horizon", 'Observed risk compatible with predicted risk at the horizon'),
          miscal ? CheckStatus.violated : CheckStatus.ok,
          tr('Observé/prédit = ${fmt(oe)} (IC ${fmt(oeLo)} à ${fmt(oeHi)}) ; risque prédit ${fmtPct(meanRisk)} vs observé ${fmtPct(obs)}.',
              'Observed/predicted = ${fmt(oe)} (CI ${fmt(oeLo)} to ${fmt(oeHi)}); predicted risk ${fmtPct(meanRisk)} vs observed ${fmtPct(obs)}.')),
      Check('calibration_slope', tr('Pente de calibration compatible avec 1', 'Calibration slope compatible with 1'), slopeOff ? CheckStatus.violated : CheckStatus.ok,
          tr('Pente = ${fmt(slope)} (IC ${fmt(slLo)} à ${fmt(slHi)}).', 'Slope = ${fmt(slope)} (CI ${fmt(slLo)} to ${fmt(slHi)}).')),
      Check('case_mix', tr('Population de validation décrite (case-mix)', 'Validation population described (case-mix)'), CheckStatus.notAssessed,
          tr('Comparer prédicteurs, suivi et risque de base avec la population de développement.', 'Compare predictors, follow-up and baseline risk with the development population.')),
      Check('transportability', tr("Même définition de l'événement, des prédicteurs et de l'origine du temps", 'Same definition of event, predictors and time origin'), CheckStatus.notAssessed,
          tr('Condition de validité de toute validation externe ; à documenter (TRIPOD+AI).', 'Validity condition of any external validation; to be documented (TRIPOD+AI).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Performance en validation externe', 'External validation performance'),
          [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), tr('Valeur idéale', 'Ideal value')], [
        [tr('C de Harrell', "Harrell's C"), fmt(c), '—', tr('1 (0,5 = hasard)', '1 (0.5 = chance)')],
        [tr('Pente de calibration', 'Calibration slope'), fmt(slope), '${fmt(slLo)} – ${fmt(slHi)}', '1'],
        [tr('Observé / prédit à ${fmt(h)}$u', 'Observed / predicted at ${fmt(h)}$u'), fmt(oe), '${fmt(oeLo)} – ${fmt(oeHi)}', '1'],
      ]),
      ResultTable(tr('Équation appliquée et recalibrations proposées', 'Applied equation and proposed recalibrations'),
          [tr('Élément', 'Item'), tr("Équation d'origine", 'Original equation'), tr('Risque de base mis à jour', 'Updated baseline hazard'), tr('Pente et risque de base mis à jour', 'Updated slope and baseline hazard')], [
        for (var j = 0; j < d.columns.length; j++) [d.columns[j], fmt(beta[j], digits: 4), fmt(beta[j], digits: 4), fmt(slope * beta[j], digits: 4)],
        [tr('H₀(${fmt(h)}) à x = 0', 'H₀(${fmt(h)}) at x = 0'), fmt(eq.baselineCumHazard, digits: 6), fmt(h0Int, digits: 6), fmt(h0Slope, digits: 6)],
      ]),
      ResultTable(tr('Calibration à ${fmt(h)}$u (quintiles de risque prédit)', 'Calibration at ${fmt(h)}$u (quintiles of predicted risk)'),
          ['n', tr('Risque prédit moyen', 'Mean predicted risk'), tr('Risque observé (KM)', 'Observed risk (KM)'), tr('IC $pct %', '$pct% CI')], [
        for (final g in groups) ['${g['n']!.toInt()}', fmtPct(g['predicted']), fmtPct(g['observed']), '${fmtPct(g['lower'])} – ${fmtPct(g['upper'])}']
      ]),
    ],
    figures: {'calibration': groups, 'stage': 'external'},
    log: [
      tr('Équation : ${eq.name} (${eq.source})', 'Equation: ${eq.name} (${eq.source})'),
      tr('Population de validation : ${population.isEmpty ? "non décrite" : population}', 'Validation population: ${population.isEmpty ? "not described" : population}'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Juger la transportabilité d'un modèle pronostique : coefficients et risque de base appliqués SANS réestimation à des données indépendantes.",
          'Judging the transportability of a prognostic model: coefficients and baseline hazard applied WITHOUT re-estimation to independent data.'),
      whatItMeans: tr(
          'Discrimination : C = ${fmt(c)}. Calibration à ${fmt(h)}$u : risque prédit ${fmtPct(meanRisk)} contre ${fmtPct(obs)} observé (observé/prédit ${fmt(oe)}), pente ${fmt(slope)}. ${miscal || slopeOff ? "Le modèle est mal calibré dans cette population : une recalibration locale est nécessaire avant tout usage." : "La calibration est compatible avec un bon accord dans cette population."}',
          'Discrimination: C = ${fmt(c)}. Calibration at ${fmt(h)}$u: predicted risk ${fmtPct(meanRisk)} versus ${fmtPct(obs)} observed (observed/predicted ${fmt(oe)}), slope ${fmt(slope)}. ${miscal || slopeOff ? "The model is poorly calibrated in this population: local recalibration is needed before any use." : "Calibration is compatible with good agreement in this population."}'),
      notJustified: tr(
          "Conclure à l'utilité clinique à partir d'une validation externe (une étude d'impact reste nécessaire) ; utiliser la version recalibrée sans la valider à son tour ; prédire au-delà de l'horizon du modèle.",
          'Concluding clinical usefulness from an external validation (an impact study is still needed); using the recalibrated version without validating it in turn; predicting beyond the model horizon.'),
    ),
  );
}
