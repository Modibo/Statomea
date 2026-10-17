/// Validation externe d'un modèle de prédiction logistique : l'équation
/// publiée (ou développée dans Statoméa) est appliquée telle quelle à de
/// nouvelles données, sans réestimation. Mesures (Riley et al., BMJ 2024 ;
/// Van Calster et al. 2016, 2019) :
///  - discrimination : AUC (IC de DeLong) ;
///  - calibration : intercept de calibration « dans l'ensemble » (logit
///    prédit en offset), pente de calibration, rapport observé/attendu
///    (O/E, IC de Debray 2017), courbe par groupes de risque ;
///  - score de Brier ; bénéfice net (courbe de décision) ;
///  - recalibration proposée : mise à jour de l'intercept, ou de
///    l'intercept et de la pente (« logistic recalibration »).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/design_matrix.dart';
import 'model_development.dart';
import 'performance.dart';

/// Équation d'un modèle logistique : prédicteurs (codage) et coefficients
/// nommés comme les colonnes de la matrice de plan (« Constante » compris).
class ModelEquation {
  final String name;
  final String outcome;
  final String eventLevel;
  final List<TermSpec> predictors;
  final Map<String, double> coefficients;
  final String source; // origine : projet, publication…
  const ModelEquation(
      {required this.name, required this.outcome, required this.eventLevel, required this.predictors, required this.coefficients, this.source = ''});

  /// Équation extraite d'un résultat de développement (journal Statoméa).
  /// Coefficients dont les noms sont exprimés dans la langue courante.
  Map<String, double> get localCoefficients => {for (final e in coefficients.entries) localizeColumn(e.key): e.value};

  factory ModelEquation.fromDevelopment(AnalysisResult r, {String? name}) {
    name ??= tr('Modèle développé', 'Developed model');
    if (!r.methodId.startsWith('prediction_logistic_internal')) {
      throw StatInputError('not_prediction', tr("Le résultat choisi n'est pas un modèle de prédiction développé dans Statoméa.", 'The selected result is not a prediction model developed in Statoméa.'));
    }
    final spec = PredictionSpec.fromJson((r.inputs['spec'] as Map).cast());
    final cols = [for (final c in ((r.inputs['model'] as Map)['columns'] as List)) c as String];
    // Splines : nœuds du développement figés (sinon recalculés sur les nouvelles données).
    final knots = ((r.inputs['model'] as Map)['splineKnots'] as Map?) ?? const {};
    return ModelEquation(
      name: name,
      outcome: spec.outcome,
      eventLevel: spec.eventLevel,
      predictors: [
        for (final t in spec.predictors)
          knots[t.variable] is List && t.knots == null
              ? TermSpec(t.variable, transform: t.transform, knots: [for (final k in knots[t.variable] as List) (k as num).toDouble()])
              : t
      ],
      coefficients: {for (final c in cols) c: r.statistics['beta_$c']!},
      source: tr('développement : ${spec.targetPopulation} ; horizon ${spec.horizon}', 'development: ${spec.targetPopulation}; horizon ${spec.horizon}'),
    );
  }

  factory ModelEquation.fromJson(Map<String, Object?> j) => ModelEquation(
        name: (j['name'] as String?) ?? tr('Modèle importé', 'Imported model'),
        outcome: j['outcome'] as String,
        eventLevel: (j['eventLevel'] as String?) ?? '1',
        predictors: [for (final t in j['predictors'] as List) TermSpec.fromJson((t as Map).cast())],
        coefficients: {for (final e in (j['coefficients'] as Map).entries) e.key as String: (e.value as num).toDouble()},
        source: (j['source'] as String?) ?? tr('importée', 'imported'),
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'outcome': outcome,
        'eventLevel': eventLevel,
        'predictors': [for (final t in predictors) t.toJson()],
        'coefficients': coefficients,
        'source': source,
      };
}

double _logit(double p) {
  final q = p.clamp(1e-12, 1 - 1e-12);
  return math.log(q / (1 - q));
}

/// Applique l'équation à un jeu de données ; retourne y, logit prédit, lignes.
({List<double> y, List<double> lp, DesignMatrix d}) applyEquation(Dataset ds, ModelEquation eq) {
  final d = buildDesign(ds, ModelFormula(eq.outcome, eq.predictors, eventLevel: eq.eventLevel), binaryOutcome: true);
  final coefs = eq.localCoefficients;
  final missing = [for (final c in coefs.keys) if (!d.columns.contains(c)) c];
  final extra = [for (final c in d.columns) if (!coefs.containsKey(c)) c];
  if (missing.isNotEmpty || extra.isNotEmpty) {
    throw StatInputError(
        'equation_mismatch',
        tr("Le codage des données ne correspond pas à l'équation du modèle. ${missing.isEmpty ? "" : "Termes de l'équation absents des données : ${missing.join(", ")}. "}${extra.isEmpty ? "" : "Modalités des données absentes de l'équation : ${extra.join(", ")}. "}Vérifier les noms des variables, les modalités et les catégories de référence.",
            'The data coding does not match the model equation. ${missing.isEmpty ? "" : "Equation terms missing from the data: ${missing.join(", ")}. "}${extra.isEmpty ? "" : "Data levels missing from the equation: ${extra.join(", ")}. "}Check the variable names, levels and reference categories.'));
  }
  final lp = [
    for (final row in d.x)
      () {
        var s = 0.0;
        for (var j = 0; j < d.p; j++) {
          s += row[j] * coefs[d.columns[j]]!;
        }
        return s;
      }()
  ];
  return (y: d.y, lp: lp, d: d);
}

AnalysisResult externalValidation(Dataset ds, ModelEquation eq, {double level = 0.95, String population = ''}) {
  final a = applyEquation(ds, eq);
  final y = a.y, lp = a.lp, n = y.length;
  final p = [for (final v in lp) 1 / (1 + math.exp(-v))];
  final events = y.where((v) => v == 1).length;
  if (events == 0 || events == n) throw StatInputError('constant_outcome', tr('Toutes les observations ont la même issue : aucune validation possible.', 'All observations have the same outcome: no validation possible.'));
  final z = normalQuantile(1 - (1 - level) / 2);
  final auc = aucDeLong(p, y, level: level);
  final cal = calibrationSlopeIntercept(p, y);
  final o = events.toDouble(), e = p.fold(0.0, (s, v) => s + v);
  final oe = o / e;
  final seLogOe = math.sqrt((1 - o / n) / o);
  final brier = brierScore(p, y);
  final prev = o / n;
  final brierScaled = 1 - brier / (prev * (1 - prev));
  final thresholds = [for (var t = 1; t <= 50; t++) t / 100];
  // Recalibrations : intercept seul (a + lp), intercept et pente (a + b·lp).
  final aUpd = cal.intercept;
  final coefs = eq.localCoefficients;
  final updIntercept = coefs[interceptName]! + aUpd;
  final recal = {
    'interceptOnly': {interceptName: updIntercept, for (final k in coefs.keys) if (k != interceptName) k: coefs[k]!},
  };
  // Pour a + b·lp : β* = b·β, constante* = a' + b·β0, a' issu de glm(y ~ lp).
  final slopeFit = _interceptOfSlopeModel(p, y);
  final logisticRecal = {
    for (final k in coefs.keys)
      k: k == interceptName ? slopeFit.a + cal.slope * coefs[k]! : cal.slope * coefs[k]!,
  };
  final alerts = <Alert>[...a.d.alerts];
  if (events < 100 || n - events < 100) {
    alerts.add(Alert('external_small', Severity.caution,
        tr('${math.min(events, n - events)} observations dans la classe la plus rare : une validation externe vise au moins 100 événements et 100 non-événements (idéalement 200) pour estimer précisément la calibration.',
            '${math.min(events, n - events)} observations in the rarer class: an external validation aims for at least 100 events and 100 non-events (ideally 200) to estimate calibration precisely.')));
  }
  final citlLo = cal.intercept - z * cal.interceptSe, citlHi = cal.intercept + z * cal.interceptSe;
  final slLo = cal.slope - z * cal.slopeSe, slHi = cal.slope + z * cal.slopeSe;
  final miscal = citlLo > 0 || citlHi < 0;
  final slopeOff = slLo > 1 || slHi < 1;
  if (miscal) {
    alerts.add(Alert('calibration_in_the_large', Severity.serious,
        tr('Calibration globale défaillante : le modèle ${cal.intercept < 0 ? "SURESTIME" : "SOUS-ESTIME"} le risque moyen (O/E = ${fmt(oe)}).',
            'Poor calibration-in-the-large: the model ${cal.intercept < 0 ? "OVERESTIMATES" : "UNDERESTIMATES"} the mean risk (O/E = ${fmt(oe)}).'),
        suggestion: tr("Recalibrer l'intercept sur la population locale avant tout usage (mise à jour proposée dans les tableaux).", 'Recalibrate the intercept on the local population before any use (update proposed in the tables).')));
  }
  if (slopeOff) {
    alerts.add(Alert('calibration_slope', Severity.serious,
        tr('Pente de calibration ${fmt(cal.slope)} : prédictions ${cal.slope < 1 ? "trop extrêmes (surajustement ou population plus homogène)" : "pas assez dispersées"}.',
            'Calibration slope ${fmt(cal.slope)}: predictions ${cal.slope < 1 ? "too extreme (overfitting or a more homogeneous population)" : "not spread enough"}.'),
        suggestion: tr('Envisager une recalibration logistique (intercept et pente), puis une nouvelle validation.', 'Consider logistic recalibration (intercept and slope), then a new validation.')));
  }
  final pct = (level * 100).round();
  return AnalysisResult(
    methodId: 'external_validation',
    methodName: tr("Validation externe d'un modèle de prédiction", 'External validation of a prediction model'),
    inputs: {'equation': eq.toJson(), 'model': a.d.describe(), 'population': population, 'level': level},
    formula: tr('p̂ = expit(Xβ) avec β FIXÉS (non réestimés) ; AUC (DeLong) ; intercept de calibration : logit P(Y=1) = a + logit(p̂) (offset) ; pente : logit P(Y=1) = a + b·logit(p̂) ; O/E = Σy/Σp̂, ES(ln O/E) = √[(1 − O/n)/O] ; Brier = moyenne (p̂ − y)².',
        'p̂ = expit(Xβ) with β FIXED (not re-estimated); AUC (DeLong); calibration intercept: logit P(Y=1) = a + logit(p̂) (offset); slope: logit P(Y=1) = a + b·logit(p̂); O/E = Σy/Σp̂, SE(ln O/E) = √[(1 − O/n)/O]; Brier = mean (p̂ − y)².'),
    estimates: [
      Estimate(tr('AUC (C-statistique)', 'AUC (C-statistic)'), auc.auc, lower: auc.lower, upper: auc.upper, level: level),
      Estimate(tr('Intercept de calibration (idéal 0)', 'Calibration intercept (ideal 0)'), cal.intercept, lower: citlLo, upper: citlHi, level: level, se: cal.interceptSe),
      Estimate(tr('Pente de calibration (idéal 1)', 'Calibration slope (ideal 1)'), cal.slope, lower: slLo, upper: slHi, level: level, se: cal.slopeSe),
      Estimate(tr('Rapport observé/attendu O/E (idéal 1)', 'Observed/expected ratio O/E (ideal 1)'), oe,
          lower: oe * math.exp(-z * seLogOe), upper: oe * math.exp(z * seLogOe), level: level),
      Estimate(tr('Score de Brier', 'Brier score'), brier),
      Estimate(tr('Brier standardisé (1 − Brier/Brier max.)', 'Scaled Brier (1 − Brier/max Brier)'), brierScaled),
    ],
    statistics: {
      'n': n.toDouble(),
      'events': o,
      'expected': e,
      'auc': auc.auc,
      'auc_se': auc.se,
      'citl': cal.intercept,
      'citl_se': cal.interceptSe,
      'slope': cal.slope,
      'slope_se': cal.slopeSe,
      'oe': oe,
      'brier': brier,
      'recal_intercept': updIntercept,
      'recal_logistic_a': slopeFit.a,
    },
    checks: [
      Check('calibration_in_the_large', tr('Calibration globale (intercept compatible avec 0)', 'Calibration-in-the-large (intercept compatible with 0)'), miscal ? CheckStatus.violated : CheckStatus.ok,
          tr('Intercept = ${fmt(cal.intercept)} (IC ${fmt(citlLo)} à ${fmt(citlHi)}) ; risque moyen prédit ${fmtPct(e / n)} vs observé ${fmtPct(prev)}.',
              'Intercept = ${fmt(cal.intercept)} (CI ${fmt(citlLo)} to ${fmt(citlHi)}); mean predicted risk ${fmtPct(e / n)} vs observed ${fmtPct(prev)}.')),
      Check('calibration_slope', tr('Pente de calibration compatible avec 1', 'Calibration slope compatible with 1'), slopeOff ? CheckStatus.violated : CheckStatus.ok,
          tr('Pente = ${fmt(cal.slope)} (IC ${fmt(slLo)} à ${fmt(slHi)}).', 'Slope = ${fmt(cal.slope)} (CI ${fmt(slLo)} to ${fmt(slHi)}).')),
      Check('case_mix', tr('Population de validation décrite (case-mix)', 'Validation population described (case-mix)'), CheckStatus.notAssessed,
          tr('Comparer la distribution des prédicteurs et la prévalence avec la population de développement : une AUC plus basse peut refléter un case-mix plus homogène.',
              'Compare the distribution of predictors and the prevalence with the development population: a lower AUC may reflect a more homogeneous case-mix.')),
      Check('transportability', tr("Même définition de l'issue, des prédicteurs et de l'horizon", 'Same definition of outcome, predictors and horizon'), CheckStatus.notAssessed,
          tr('Condition de validité de toute validation externe ; à documenter (TRIPOD+AI).', 'Validity condition of any external validation; to be documented (TRIPOD+AI).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Performance en validation externe', 'External validation performance'), [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), tr('Valeur idéale', 'Ideal value')], [
        ['AUC', fmt(auc.auc), '${fmt(auc.lower)} – ${fmt(auc.upper)}', tr('1 (0,5 = hasard)', '1 (0.5 = chance)')],
        [tr('Intercept de calibration', 'Calibration intercept'), fmt(cal.intercept), '${fmt(citlLo)} – ${fmt(citlHi)}', '0'],
        [tr('Pente de calibration', 'Calibration slope'), fmt(cal.slope), '${fmt(slLo)} – ${fmt(slHi)}', '1'],
        ['O/E', fmt(oe), '${fmt(oe * math.exp(-z * seLogOe))} – ${fmt(oe * math.exp(z * seLogOe))}', '1'],
        ['Brier', fmt(brier, digits: 3), '—', '0'],
      ]),
      ResultTable(tr('Équation appliquée et recalibrations proposées', 'Applied equation and proposed recalibrations'),
          [tr('Terme', 'Term'), tr("Équation d'origine", 'Original equation'), tr('Intercept mis à jour', 'Updated intercept'), tr('Intercept et pente mis à jour', 'Updated intercept and slope')], [
        for (final k in eq.coefficients.keys)
          [k, fmt(coefs[k], digits: 4), fmt(recal['interceptOnly']![k], digits: 4), fmt(logisticRecal[k], digits: 4)]
      ]),
      ResultTable('Observations', [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [tr('n / événements', 'n / events'), '$n / $events'],
        [tr('Risque moyen prédit / observé', 'Mean predicted / observed risk'), '${fmtPct(e / n)} / ${fmtPct(prev)}'],
        [tr('Exclues (manquants)', 'Excluded (missing)'), a.d.excludedBy.isEmpty ? '0' : a.d.excludedBy.entries.map((x) => tr('${x.key} : ${x.value}', '${x.key}: ${x.value}')).join(tr(' ; ', '; '))],
      ]),
    ],
    figures: {
      'calibration': calibrationGroups(p, y),
      'decisionCurve': decisionCurve(p, y, thresholds),
      'stage': 'external',
    },
    log: [tr('Équation : ${eq.name} (${eq.source})', 'Equation: ${eq.name} (${eq.source})'), tr('Population de validation : ${population.isEmpty ? "non décrite" : population}', 'Validation population: ${population.isEmpty ? "not described" : population}')],
    interpretation: Interpretation(
      whyThisMethod: tr("Juger la transportabilité d'un modèle : ses coefficients sont appliqués SANS réestimation à des données indépendantes (autre lieu, autre période), seule façon d'estimer sa performance réelle hors de l'échantillon de développement.",
          'Judging the transportability of a model: its coefficients are applied WITHOUT re-estimation to independent data (another place, another period), the only way to estimate its real performance outside the development sample.'),
      whatItMeans: tr('Discrimination : AUC ${fmt(auc.auc)} (IC ${fmt(auc.lower)} à ${fmt(auc.upper)}). Calibration : risque moyen prédit ${fmtPct(e / n)} contre ${fmtPct(prev)} observé (O/E ${fmt(oe)}), pente ${fmt(cal.slope)}. ${miscal || slopeOff ? "Le modèle est mal calibré dans cette population : une recalibration locale est nécessaire avant tout usage." : "La calibration est compatible avec un bon accord dans cette population."}',
          'Discrimination: AUC ${fmt(auc.auc)} (CI ${fmt(auc.lower)} to ${fmt(auc.upper)}). Calibration: mean predicted risk ${fmtPct(e / n)} versus ${fmtPct(prev)} observed (O/E ${fmt(oe)}), slope ${fmt(cal.slope)}. ${miscal || slopeOff ? "The model is poorly calibrated in this population: local recalibration is needed before any use." : "Calibration is compatible with good agreement in this population."}'),
      notJustified: tr("Conclure à l'utilité clinique à partir d'une validation externe (une étude d'impact reste nécessaire) ; généraliser à d'autres populations que celle étudiée ; réestimer les coefficients sur ces données et appeler cela une validation externe ; utiliser la version recalibrée sans la valider à son tour.",
          'Concluding clinical usefulness from an external validation (an impact study is still needed); generalizing to populations other than the one studied; re-estimating the coefficients on these data and calling it external validation; using the recalibrated version without validating it in turn.'),
    ),
  );
}

/// Intercept a' de glm(y ~ logit(p̂)) (avec la pente libre).
({double a}) _interceptOfSlopeModel(List<double> p, List<double> y) {
  final lp = [for (final v in p) _logit(v)];
  // Newton sur (a, b).
  var a = 0.0, b = 1.0;
  for (var it = 0; it < 100; it++) {
    var ga = 0.0, gb = 0.0, haa = 0.0, hab = 0.0, hbb = 0.0;
    for (var i = 0; i < y.length; i++) {
      final m = 1 / (1 + math.exp(-(a + b * lp[i])));
      final w = m * (1 - m);
      ga += y[i] - m;
      gb += (y[i] - m) * lp[i];
      haa += w;
      hab += w * lp[i];
      hbb += w * lp[i] * lp[i];
    }
    final det = haa * hbb - hab * hab;
    final da = (hbb * ga - hab * gb) / det, db = (-hab * ga + haa * gb) / det;
    a += da;
    b += db;
    if (da.abs() + db.abs() < 1e-13) break;
  }
  return (a: a);
}
