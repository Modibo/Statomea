/// Méta-régression à effets mixtes : y_i = x_iᵀβ + u_i + e_i,
/// u_i ~ N(0, τ²), e_i ~ N(0, v_i). τ² résiduel par REML (scores de Fisher)
/// ou DerSimonian-Laird généralisé ; effet fixe possible. Option de
/// Hartung-Knapp. Conventions de calcul alignées sur `metafor::rma(mods = )`.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import '../regression/common.dart';
import '../regression/design_matrix.dart';
import 'meta.dart';

/// Modérateur : quantitatif (clé d'une valeur extraite) ou qualitatif
/// (le sous-groupe de l'étude, avec une référence).
class Moderator {
  final String name;
  final bool categorical;
  final String? reference;
  const Moderator(this.name, {this.categorical = false, this.reference});
  Map<String, Object?> toJson() => {'name': name, 'categorical': categorical, 'reference': reference};
}

/// Ajustement pondéré : β, (XᵀWX)⁻¹, résidus.
({List<double> b, Matrix xtwxInv}) _wls(List<List<double>> x, List<double> y, List<double> w) {
  final p = x.first.length;
  final xtwx = crossprodWeighted(x, w);
  final inv = invertSpd(xtwx);
  if (inv == null) {
    throw StatInputError('meta_reg_singular', tr("Modérateurs colinéaires ou modalité sans étude : la méta-régression n'est pas estimable.", 'Collinear moderators or a level without studies: the meta-regression is not estimable.'));
  }
  final xty = List<double>.filled(p, 0);
  for (var i = 0; i < x.length; i++) {
    for (var j = 0; j < p; j++) {
      xty[j] += x[i][j] * w[i] * y[i];
    }
  }
  return (b: inv.multiplyVector(xty), xtwxInv: inv);
}

/// Matrice P = W − WX(XᵀWX)⁻¹XᵀW (k × k).
Matrix _projP(List<List<double>> x, List<double> w, Matrix inv) {
  final k = x.length;
  final pm = Matrix(k, k);
  final wx = [for (var i = 0; i < k; i++) [for (final v in x[i]) v * w[i]]];
  for (var i = 0; i < k; i++) {
    final a = inv.multiplyVector(wx[i]);
    for (var j = 0; j < k; j++) {
      var s = 0.0;
      for (var c = 0; c < a.length; c++) {
        s += a[c] * wx[j][c];
      }
      pm.set(i, j, (i == j ? w[i] : 0) - s);
    }
  }
  return pm;
}

double _trace(Matrix m) {
  var s = 0.0;
  for (var i = 0; i < m.rows; i++) {
    s += m.get(i, i);
  }
  return s;
}

/// τ² résiduel.
double metaRegTau2(List<List<double>> x, List<double> y, List<double> v, TauMethod method) {
  final k = x.length, p = x.first.length;
  final w0 = [for (final vi in v) 1 / vi];
  final fe = _wls(x, y, w0);
  final p0 = _projP(x, w0, fe.xtwxInv);
  var qe = 0.0;
  for (var i = 0; i < k; i++) {
    var f = 0.0;
    for (var j = 0; j < p; j++) {
      f += x[i][j] * fe.b[j];
    }
    qe += w0[i] * (y[i] - f) * (y[i] - f);
  }
  final dl = math.max(0.0, (qe - (k - p)) / _trace(p0));
  if (method == TauMethod.fixed) return 0;
  if (method == TauMethod.dl) return dl;
  var tau2 = dl;
  for (var it = 0; it < 1000; it++) {
    final w = [for (final vi in v) 1 / (vi + tau2)];
    final inv = _wls(x, y, w).xtwxInv;
    final pm = _projP(x, w, inv);
    final py = pm.multiplyVector(y);
    final ypPy = py.fold(0.0, (a, e) => a + e * e);
    final pp = pm * pm;
    final adj = (ypPy - _trace(pm)) / _trace(pp);
    var next = tau2 + adj, step = adj;
    while (next < 0) {
      step /= 2;
      next = tau2 + step;
      if (step.abs() < 1e-15) {
        next = 0;
        break;
      }
    }
    if ((next - tau2).abs() < 1e-12) {
      tau2 = next;
      break;
    }
    tau2 = next;
  }
  return tau2;
}

AnalysisResult metaRegression(List<Study> all, MetaOptions o, List<Moderator> moderators) {
  if (moderators.isEmpty) throw StatInputError('no_moderator', tr('Au moins un modérateur est requis.', 'At least one moderator is required.'));
  final effects = <StudyEffect>[];
  final excluded = <List<String>>[];
  for (final s in all) {
    if (s.excluded) {
      excluded.add([s.label, tr("exclue par l'utilisateur", 'excluded by the user')]);
      continue;
    }
    final e = computeEffect(s, o.measure, add: o.continuityCorrection).effect;
    final missingMod = moderators.where((m) => m.categorical ? s.subgroup.isEmpty : s.v(m.name) == null).map((m) => m.name).toList();
    if (e == null) {
      excluded.add([s.label, tr('effet incalculable', 'effect not computable')]);
    } else if (missingMod.isNotEmpty) {
      excluded.add([s.label, tr('modérateur manquant : ${missingMod.join(", ")}', 'missing moderator: ${missingMod.join(", ")}')]);
    } else {
      effects.add(e);
    }
  }
  // Matrice des modérateurs (constante + colonnes).
  final cols = <String>[interceptName];
  final getters = <double Function(Study)>[(_) => 1.0];
  final terms = <String>['($interceptName)'];
  for (final m in moderators) {
    if (m.categorical) {
      final levels = {for (final e in effects) e.study.subgroup}.toList()..sort();
      if (levels.length < 2) throw StatInputError('constant_moderator', tr("Le modérateur « ${m.name} » n'a qu'une modalité parmi les études incluses.", 'The moderator "${m.name}" has only one level among the included studies.'));
      final ref = m.reference ?? levels.first;
      for (final l in levels.where((l) => l != ref)) {
        cols.add('${m.name} = $l (vs $ref)');
        terms.add(m.name);
        getters.add((s) => s.subgroup == l ? 1.0 : 0.0);
      }
    } else {
      cols.add(m.name);
      terms.add(m.name);
      getters.add((s) => s.v(m.name)!);
    }
  }
  final k = effects.length, p = cols.length;
  if (k <= p) {
    throw StatInputError('meta_reg_too_few', tr('$k étude(s) pour $p paramètre(s) : méta-régression non estimable.', '$k study(ies) for $p parameter(s): meta-regression not estimable.'));
  }
  final x = [for (final e in effects) [for (final g in getters) g(e.study)]];
  final y = [for (final e in effects) e.yi], v = [for (final e in effects) e.vi];
  final tau2 = metaRegTau2(x, y, v, o.method);
  final w = [for (final vi in v) 1 / (vi + tau2)];
  final fit = _wls(x, y, w);
  // Hétérogénéité résiduelle (QE, poids fixes) ; I² et H² résiduels comme metafor.
  final w0 = [for (final vi in v) 1 / vi];
  final fe = _wls(x, y, w0);
  final p0 = _projP(x, w0, fe.xtwxInv);
  var qe = 0.0;
  for (var i = 0; i < k; i++) {
    var f = 0.0;
    for (var j = 0; j < p; j++) {
      f += x[i][j] * fe.b[j];
    }
    qe += w0[i] * (y[i] - f) * (y[i] - f);
  }
  final qeP = chiSquareUpper(qe, (k - p).toDouble());
  final vt = (k - p) / _trace(p0);
  final i2 = o.method == TauMethod.fixed ? math.max(0.0, (qe - (k - p)) / qe) : tau2 / (tau2 + vt);
  // Variance des coefficients (Hartung-Knapp : facteur s²).
  var s2 = 1.0;
  if (o.knha) {
    var rss = 0.0;
    for (var i = 0; i < k; i++) {
      var f = 0.0;
      for (var j = 0; j < p; j++) {
        f += x[i][j] * fit.b[j];
      }
      rss += w[i] * (y[i] - f) * (y[i] - f);
    }
    s2 = rss / (k - p);
  }
  final df = (k - p).toDouble();
  final crit = o.knha ? tQuantile(1 - (1 - o.level) / 2, df) : normalQuantile(1 - (1 - o.level) / 2);
  final coefs = [
    for (var j = 0; j < p; j++)
      () {
        final se = math.sqrt(s2 * fit.xtwxInv.get(j, j));
        final st = fit.b[j] / se;
        final pv = o.knha ? tTwoSidedP(st, df) : normalTwoSidedP(st);
        return Coefficient(cols[j], fit.b[j], se, st, pv, fit.b[j] - crit * se, fit.b[j] + crit * se);
      }()
  ];
  // Test omnibus des modérateurs (QM, ou F de Hartung-Knapp).
  final m = p - 1;
  final sub = Matrix(m, m);
  for (var a = 0; a < m; a++) {
    for (var c = 0; c < m; c++) {
      sub.set(a, c, s2 * fit.xtwxInv.get(a + 1, c + 1));
    }
  }
  final bm = fit.b.sublist(1);
  final sol = solveSpd(sub, bm)!;
  var qm = 0.0;
  for (var a = 0; a < m; a++) {
    qm += sol[a] * bm[a];
  }
  final qmStat = o.knha ? qm / m : qm;
  final qmP = o.knha ? fUpper(qmStat, m.toDouble(), df) : chiSquareUpper(qm, m.toDouble());
  // R² : part de τ² expliquée (modèle sans modérateur, même estimateur).
  // Effet fixe : R² ajusté de la régression pondérée, 1 − (QE/QE₀)(k − 1)/(k − p) (convention de metafor).
  double r2;
  if (o.method != TauMethod.fixed) {
    final tau0 = poolInverseVariance(y, v, method: o.method).tau2;
    r2 = tau0 <= 0 ? 0 : math.max(0.0, (tau0 - tau2) / tau0);
  } else {
    final qe0 = poolInverseVariance(y, v, method: TauMethod.fixed).q;
    r2 = qe0 <= 0 ? 0 : math.max(0.0, 1 - (qe / qe0) * (k - 1) / (k - p));
  }
  final ratio = isRatio(o.measure);
  double back(double v) => ratio ? math.exp(v) : v;
  final alerts = <Alert>[
    if (k < 10 * m)
      Alert('meta_reg_few_studies', k < 5 * m ? Severity.serious : Severity.caution,
          tr('$k étude(s) pour $m coefficient(s) de modérateur : puissance faible et risque de faux positifs (repère : ≥ 10 études par modérateur).',
              '$k study(ies) for $m moderator coefficient(s): low power and risk of false positives (benchmark: ≥ 10 studies per moderator).')),
    Alert('ecological', Severity.info,
        tr("Relation observée ENTRE études (agrégée) : elle ne s'applique pas forcément aux individus (biais écologique) et peut être confondue par d'autres caractéristiques des études.",
            'Relationship observed BETWEEN studies (aggregated): it does not necessarily apply to individuals (ecological bias) and may be confounded by other study characteristics.')),
    Alert('prespecified', Severity.info,
        tr("Une méta-régression n'est crédible que si les modérateurs ont été choisis a priori (protocole), en petit nombre et avec une justification.",
            'A meta-regression is credible only if the moderators were chosen a priori (protocol), few in number and with a justification.')),
    if (excluded.isNotEmpty) Alert('excluded_studies', Severity.caution, tr('${excluded.length} étude(s) non incluse(s) : voir le tableau.', '${excluded.length} study(ies) not included: see the table.')),
  ];
  // Graphique à bulles pour un modérateur quantitatif unique.
  Map<String, Object?>? bubble;
  if (moderators.length == 1 && !moderators.first.categorical) {
    final xs = [for (final r in x) r[1]];
    final wsum = w.fold(0.0, (a, b) => a + b);
    bubble = {
      'x': xs,
      'y': [for (final e in y) back(e)],
      'w': [for (final wi in w) 100 * wi / wsum],
      'labels': [for (final e in effects) e.study.label],
      'b0': fit.b[0],
      'b1': fit.b[1],
      'ratio': ratio,
      'xName': moderators.first.name,
      'yName': measureLabel(o.measure),
    };
  }
  final mainMod = coefs.length > 1 ? coefs[1] : coefs.first;
  final pct = (o.level * 100).round();
  return AnalysisResult(
    methodId: 'meta_regression',
    methodName: tr('Méta-régression — ${measureLabel(o.measure)}, ${o.method == TauMethod.fixed ? "effet fixe" : o.method == TauMethod.dl ? "effets mixtes (DL)" : "effets mixtes (REML)"}${o.knha ? ", Hartung-Knapp" : ""}',
        'Meta-regression — ${measureLabel(o.measure)}, ${o.method == TauMethod.fixed ? "fixed effect" : o.method == TauMethod.dl ? "mixed effects (DL)" : "mixed effects (REML)"}${o.knha ? ", Hartung-Knapp" : ""}'),
    inputs: {'options': o.toJson(), 'moderators': [for (final m in moderators) m.toJson()], 'k': k, 'studies': [for (final s in all) s.toJson()]},
    formula: tr('y_i = x_iᵀβ + u_i + e_i ; β̂ = (XᵀWX)⁻¹XᵀWy, W = diag(1/(v_i + τ̂²)) ; τ² résiduel ${o.method == TauMethod.reml ? "par REML" : o.method == TauMethod.dl ? "DerSimonian-Laird généralisé" : "= 0"} ; QM = β̂ₘᵀ Var(β̂ₘ)⁻¹ β̂ₘ ; QE = Σ(1/v_i)(y_i − x_iᵀβ̂_FE)² ; R² = (τ²₀ − τ²)/τ²₀.',
        'y_i = x_iᵀβ + u_i + e_i; β̂ = (XᵀWX)⁻¹XᵀWy, W = diag(1/(v_i + τ̂²)); residual τ² ${o.method == TauMethod.reml ? "by REML" : o.method == TauMethod.dl ? "generalized DerSimonian-Laird" : "= 0"}; QM = β̂ₘᵀ Var(β̂ₘ)⁻¹ β̂ₘ; QE = Σ(1/v_i)(y_i − x_iᵀβ̂_FE)²; R² = (τ²₀ − τ²)/τ²₀.'),
    estimates: [
      for (final c in coefs.skip(1))
        Estimate('${ratio ? tr("Rapport (exp β)", "Ratio (exp β)") : "β"} — ${c.name}', back(c.estimate), lower: back(c.lower), upper: back(c.upper), level: o.level, pValue: c.p, se: c.se),
      Estimate(tr('τ² résiduel', 'Residual τ²'), tau2),
      Estimate(tr('R² (part de τ² expliquée)', 'R² (share of τ² explained)'), r2),
    ],
    statistics: {
      'k': k.toDouble(),
      'tau2': tau2,
      'QE': qe,
      'QE_p': qeP,
      'QM': qmStat,
      'QM_p': qmP,
      'I2_resid': i2,
      'H2_resid': o.method == TauMethod.fixed ? qe / (k - p) : (tau2 + vt) / vt,
      'R2': r2,
      for (var j = 0; j < p; j++) 'beta_${cols[j]}': fit.b[j],
      for (var j = 0; j < p; j++) 'se_${cols[j]}': coefs[j].se,
    },
    checks: [
      Check('residual_heterogeneity', tr('Hétérogénéité résiduelle', 'Residual heterogeneity'), qeP < 0.1 ? CheckStatus.warning : CheckStatus.ok,
          tr('QE = ${fmt(qe)} (ddl ${k - p}), ${fmtP(qeP)} ; I² résiduel = ${fmtPct(i2)}.', 'QE = ${fmt(qe)} (df ${k - p}), ${fmtP(qeP)}; residual I² = ${fmtPct(i2)}.')),
      Check('studies_per_moderator', tr('Au moins 10 études par modérateur', 'At least 10 studies per moderator'), k >= 10 * m ? CheckStatus.ok : CheckStatus.warning,
          tr('$k étude(s), $m coefficient(s).', '$k study(ies), $m coefficient(s).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Coefficients (échelle ${ratio ? "logarithmique" : "de l'effet"})', 'Coefficients (${ratio ? "log" : "effect"} scale)'), [tr('Terme', 'Term'), 'β', tr('ES', 'SE'), o.knha ? 't' : 'z', tr('IC $pct %', '$pct% CI'), 'p'], [
        for (final c in coefs) [c.name, fmt(c.estimate, digits: 4), fmt(c.se), fmt(c.statistic), '${fmt(c.lower)} – ${fmt(c.upper)}', fmtP(c.p)]
      ]),
      ResultTable(tr('Tests et hétérogénéité', 'Tests and heterogeneity'), [tr('Élément', 'Item'), tr('Valeur', 'Value')], [
        [o.knha ? tr('Test des modérateurs (F)', 'Test of moderators (F)') : tr('Test des modérateurs (QM)', 'Test of moderators (QM)'),
          tr('${fmt(qmStat)} (ddl ${o.knha ? "$m ; ${k - p}" : "$m"}), ${fmtP(qmP)}', '${fmt(qmStat)} (df ${o.knha ? "$m; ${k - p}" : "$m"}), ${fmtP(qmP)}')],
        [tr('Hétérogénéité résiduelle (QE)', 'Residual heterogeneity (QE)'), tr('${fmt(qe)} (ddl ${k - p}), ${fmtP(qeP)}', '${fmt(qe)} (df ${k - p}), ${fmtP(qeP)}')],
        [tr('τ² résiduel', 'Residual τ²'), fmt(tau2)],
        [tr('I² résiduel', 'Residual I²'), fmtPct(i2)],
        [o.method == TauMethod.fixed ? tr('R² ajusté (effet fixe)', 'Adjusted R² (fixed effect)') : tr('R² (τ² expliqué)', 'R² (τ² explained)'), fmtPct(r2)],
      ]),
      if (excluded.isNotEmpty) ResultTable(tr('Études non incluses', 'Studies not included'), [tr('Étude', 'Study'), tr('Raison', 'Reason')], excluded),
    ],
    figures: {'bubble': ?bubble},
    interpretation: Interpretation(
      whyThisMethod: tr("Explorer si l'effet varie avec une caractéristique des études (source d'hétérogénéité), en tenant compte de la variance intra-étude et de l'hétérogénéité résiduelle.",
          'Exploring whether the effect varies with a study characteristic (source of heterogeneity), accounting for within-study variance and residual heterogeneity.'),
      whatItMeans: coefs.length > 1
          ? tr('« ${mainMod.name} » : ${ratio ? "l'effet est multiplié par ${fmt(math.exp(mainMod.estimate))} (IC ${fmt(math.exp(mainMod.lower))} à ${fmt(math.exp(mainMod.upper))})" : "l'effet varie de ${fmt(mainMod.estimate)} (IC ${fmt(mainMod.lower)} à ${fmt(mainMod.upper)})"} par unité du modérateur, ${fmtP(mainMod.p)}. Les modérateurs expliquent ${fmtPct(r2)} de la variance entre études ; hétérogénéité résiduelle I² = ${fmtPct(i2)}.',
              '"${mainMod.name}": ${ratio ? "the effect is multiplied by ${fmt(math.exp(mainMod.estimate))} (CI ${fmt(math.exp(mainMod.lower))} to ${fmt(math.exp(mainMod.upper))})" : "the effect changes by ${fmt(mainMod.estimate)} (CI ${fmt(mainMod.lower)} to ${fmt(mainMod.upper)})"} per unit of the moderator, ${fmtP(mainMod.p)}. The moderators explain ${fmtPct(r2)} of the between-study variance; residual heterogeneity I² = ${fmtPct(i2)}.')
          : '',
      notJustified: tr('Interpréter la relation entre études comme valable pour les individus (biais écologique) ; conclure à un effet causal du modérateur ; présenter comme confirmatoire un modérateur choisi après avoir vu les données ; tester de nombreux modérateurs sans en tenir compte.',
          'Interpreting the between-study relationship as valid for individuals (ecological bias); concluding a causal effect of the moderator; presenting as confirmatory a moderator chosen after seeing the data; testing many moderators without accounting for it.'),
    ),
  );
}
