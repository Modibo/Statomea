/// Éléments communs aux modèles de régression : tableau des coefficients,
/// facteurs d'inflation de la variance (GVIF), événements par paramètre.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'design_matrix.dart';

class Coefficient {
  final String name;
  final double estimate, se, statistic, p, lower, upper;
  Coefficient(this.name, this.estimate, this.se, this.statistic, this.p, this.lower, this.upper);
  Map<String, Object?> toJson() =>
      {'name': name, 'estimate': estimate, 'se': se, 'statistic': statistic, 'p': p, 'lower': lower, 'upper': upper};
}

/// GVIF par terme (Fox & Monette 1992) ; égal au VIF pour un terme à 1 ddl.
/// Retourne terme → (GVIF, ddl).
Map<String, (double, int)> gvif(DesignMatrix d) {
  final idx = [for (var j = 0; j < d.p; j++) if (!isIntercept(d.termOfColumn[j])) j];
  if (idx.length < 2) return {for (final j in idx) d.termOfColumn[j]: (1.0, 1)};
  final n = d.n;
  // Matrice de corrélation des colonnes (hors constante).
  final means = [for (final j in idx) d.x.fold(0.0, (a, r) => a + r[j]) / n];
  final sds = [
    for (var k = 0; k < idx.length; k++)
      math.sqrt(d.x.fold(0.0, (a, r) => a + math.pow(r[idx[k]] - means[k], 2)) / (n - 1))
  ];
  final m = idx.length;
  final r = Matrix(m, m);
  for (var a = 0; a < m; a++) {
    for (var b = a; b < m; b++) {
      var s = 0.0;
      for (final row in d.x) {
        s += (row[idx[a]] - means[a]) * (row[idx[b]] - means[b]);
      }
      final v = s / ((n - 1) * sds[a] * sds[b]);
      r.set(a, b, v);
      r.set(b, a, v);
    }
  }
  final ldAll = logDetSpd(r);
  final terms = <String>{for (final j in idx) d.termOfColumn[j]};
  final out = <String, (double, int)>{};
  for (final t in terms) {
    final inT = [for (var k = 0; k < m; k++) if (d.termOfColumn[idx[k]] == t) k];
    final outT = [for (var k = 0; k < m; k++) if (d.termOfColumn[idx[k]] != t) k];
    Matrix sub(List<int> s) {
      final q = Matrix(s.length, s.length);
      for (var a = 0; a < s.length; a++) {
        for (var b = 0; b < s.length; b++) {
          q.set(a, b, r.get(s[a], s[b]));
        }
      }
      return q;
    }

    final l1 = logDetSpd(sub(inT)), l2 = outT.isEmpty ? 0.0 : logDetSpd(sub(outT));
    if (ldAll == null || l1 == null || l2 == null) {
      out[t] = (double.infinity, inT.length);
    } else {
      out[t] = (math.exp(l1 + l2 - ldAll), inT.length);
    }
  }
  return out;
}

Check collinearityCheck(Map<String, (double, int)> g) {
  if (g.isEmpty) {
    return Check('collinearity', tr('Colinéarité', 'Collinearity'), CheckStatus.notAssessed, tr('Un seul prédicteur.', 'A single predictor.'));
  }
  // Critère : GVIF^(1/(2·ddl)) > √5 (équivaut à VIF > 5 pour 1 ddl), > √10 grave.
  final adj = {for (final e in g.entries) e.key: math.pow(e.value.$1, 1 / (2 * e.value.$2)).toDouble()};
  final worst = adj.entries.reduce((a, b) => a.value > b.value ? a : b);
  final status = worst.value > math.sqrt(10)
      ? CheckStatus.violated
      : worst.value > math.sqrt(5)
          ? CheckStatus.warning
          : CheckStatus.ok;
  return Check(
      'collinearity',
      tr('Absence de colinéarité forte (GVIF^(1/2ddl) ≤ √5)', 'No strong collinearity (GVIF^(1/2df) ≤ √5)'),
      status,
      g.entries
          .map((e) => tr('${e.key} : GVIF = ${fmt(e.value.$1)}${e.value.$2 > 1 ? " (ddl ${e.value.$2}, ajusté ${fmt(adj[e.key])})" : ""}',
              '${e.key}: GVIF = ${fmt(e.value.$1)}${e.value.$2 > 1 ? " (df ${e.value.$2}, adjusted ${fmt(adj[e.key])})" : ""}'))
          .join(tr(' ; ', '; ')));
}

ResultTable coefficientTable(List<Coefficient> c, {required String effectLabel, bool exponentiate = false, double level = 0.95}) {
  final pct = (level * 100).round();
  return ResultTable('Coefficients', [
    tr('Terme', 'Term'),
    'β',
    tr('ES', 'SE'),
    if (exponentiate) effectLabel,
    tr('IC $pct %', '$pct% CI'),
    'p'
  ], [
    for (final k in c)
      [
        k.name,
        fmt(k.estimate, digits: 4),
        fmt(k.se, digits: 3),
        if (exponentiate) isIntercept(k.name) ? '—' : fmt(math.exp(k.estimate)),
        exponentiate
            ? (isIntercept(k.name) ? '—' : '${fmt(math.exp(k.lower))} – ${fmt(math.exp(k.upper))}')
            : '${fmt(k.lower)} – ${fmt(k.upper)}',
        fmtP(k.p),
      ]
  ]);
}

/// Mode « petit nombre d'événements » : diagnostic EPV et options.
List<Alert> smallEventsAlerts({required int events, required int nonEvents, required int parameters}) {
  final minority = math.min(events, nonEvents);
  final epv = parameters == 0 ? double.infinity : minority / parameters;
  final out = <Alert>[];
  if (epv < 5) {
    out.add(Alert('epv_very_low', Severity.serious,
        tr("Événements par paramètre (EPV) = ${fmt(epv)} ($minority événements de la classe minoritaire pour $parameters paramètre(s)) : estimations biaisées vers l'extrême, IC peu fiables, surajustement probable.",
            'Events per parameter (EPV) = ${fmt(epv)} ($minority events in the minority class for $parameters parameter(s)): estimates biased away from zero, unreliable CIs, overfitting likely.'),
        suggestion: tr("Options : réduire le nombre de paramètres sur des bases cliniques fixées a priori (pas sur les valeurs de p) ; régression pénalisée de Firth ; analyse descriptive ou exacte ; présenter l'analyse comme exploratoire.",
            "Options: reduce the number of parameters on clinical grounds set a priori (not on p-values); Firth's penalized regression; descriptive or exact analysis; present the analysis as exploratory.")));
  } else if (epv < 10) {
    out.add(Alert('epv_low', Severity.caution,
        tr("EPV = ${fmt(epv)} (< 10) : risque de surajustement et d'estimations instables.", 'EPV = ${fmt(epv)} (< 10): risk of overfitting and unstable estimates.'),
        suggestion: tr('Limiter les covariables ; envisager Firth ; vérifier la stabilité (bootstrap).', 'Limit covariates; consider Firth; check stability (bootstrap).')));
  }
  return out;
}

String get smallEventsLesson => tr(
    "Avec peu d'événements, le maximum de vraisemblance surestime les coefficients (biais de petit échantillon), les IC de Wald couvrent mal et une séparation peut rendre une estimation infinie. "
        "Le repère « 10 événements par paramètre » n'est qu'un ordre de grandeur : la taille nécessaire dépend aussi de la prévalence de l'issue et de la force des prédicteurs (Riley et al., BMJ 2020). "
        "Aucune méthode statistique ne crée l'information absente : Firth réduit le biais et gère la séparation, mais l'incertitude reste grande.",
    'With few events, maximum likelihood overestimates coefficients (small-sample bias), Wald CIs have poor coverage and separation can make an estimate infinite. '
        'The "10 events per parameter" rule is only an order of magnitude: the required size also depends on the outcome prevalence and the strength of the predictors (Riley et al., BMJ 2020). '
        'No statistical method creates missing information: Firth reduces bias and handles separation, but uncertainty remains large.');


/// Test de Wald de H₀ : β_idx = 0 ; χ² (ou F = χ²/q si [dfResidual] est donné, modèle linéaire, comme rms::anova).
({double stat, int df, double p}) waldTest(List<double> beta, double Function(int, int) cov, List<int> idx, {int? dfResidual}) {
  final q = idx.length;
  final v = Matrix(q, q);
  for (var a = 0; a < q; a++) {
    for (var b = 0; b < q; b++) {
      v.set(a, b, cov(idx[a], idx[b]));
    }
  }
  final inv = invertSpd(v);
  if (inv == null) return (stat: double.nan, df: q, p: double.nan);
  var w = 0.0;
  for (var a = 0; a < q; a++) {
    for (var b = 0; b < q; b++) {
      w += beta[idx[a]] * inv.get(a, b) * beta[idx[b]];
    }
  }
  if (dfResidual != null) return (stat: w / q, df: q, p: fUpper(w / q, q.toDouble(), dfResidual.toDouble()));
  return (stat: w, df: q, p: chiSquareUpper(w, q.toDouble()));
}

/// Splines cubiques restreintes d'un modèle ajusté : pour chaque variable, test d'association globale (k − 1 ddl),
/// test de non-linéarité (k − 2 ddl) et courbe dose-effet relative à la médiane (contraste f(x) − f(médiane), IC de
/// Wald ; exponentié pour OR, RR ou HR). [effect] : libellé de l'échelle (β, OR, RR, HR). Résultat inchangé sans spline.
AnalysisResult withSplineAnalysis(AnalysisResult r, DesignMatrix d, List<double> beta, double Function(int, int) cov,
    {required String effect, bool exponentiate = false, int? dfResidual, double level = 0.95}) {
  if (d.splineKnots.isEmpty) return r;
  final z = dfResidual == null ? normalQuantile(1 - (1 - level) / 2) : tQuantile(1 - (1 - level) / 2, dfResidual.toDouble());
  final pct = (level * 100).round();
  final stats = <String, double>{};
  final rows = <List<String>>[];
  final curves = <Map<String, Object?>>[];
  final notes = <String>[];
  final statName = dfResidual == null ? 'χ²' : 'F';
  for (final e in d.splineKnots.entries) {
    final v = e.key, knots = e.value, idx = d.splineColumns[v]!;
    final all = waldTest(beta, cov, idx, dfResidual: dfResidual);
    final nl = waldTest(beta, cov, idx.sublist(1), dfResidual: dfResidual);
    stats['spline_${v}_stat'] = all.stat;
    stats['spline_${v}_p'] = all.p;
    stats['spline_${v}_nonlinear_stat'] = nl.stat;
    stats['spline_${v}_nonlinear_p'] = nl.p;
    for (var k = 0; k < knots.length; k++) {
      stats['spline_${v}_knot${k + 1}'] = knots[k];
    }
    rows.add([v, tr('association globale', 'overall association'), '${all.df}', fmt(all.stat), fmtP(all.p)]);
    rows.add([v, tr('non-linéarité', 'nonlinearity'), '${nl.df}', fmt(nl.stat), fmtP(nl.p)]);
    // Courbe : valeurs observées de x (colonne linéaire de la base), contraste à la médiane.
    final xs = [for (final row in d.x) row[idx.first]]..sort();
    final ref = xs.length.isOdd ? xs[xs.length ~/ 2] : (xs[xs.length ~/ 2 - 1] + xs[xs.length ~/ 2]) / 2;
    final bRef = rcsBasis(ref, knots);
    final grid = [for (var g = 0; g <= 60; g++) xs.first + (xs.last - xs.first) * g / 60];
    final est = <double>[], lo = <double>[], hi = <double>[];
    for (final x in grid) {
      final b = rcsBasis(x, knots);
      final c = [for (var j = 0; j < b.length; j++) b[j] - bRef[j]];
      var m = 0.0, va = 0.0;
      for (var a = 0; a < c.length; a++) {
        m += c[a] * beta[idx[a]];
        for (var bb = 0; bb < c.length; bb++) {
          va += c[a] * c[bb] * cov(idx[a], idx[bb]);
        }
      }
      final se = math.sqrt(math.max(va, 0));
      double t(double u) => exponentiate ? math.exp(u) : u;
      est.add(t(m));
      lo.add(t(m - z * se));
      hi.add(t(m + z * se));
    }
    stats['spline_${v}_ref'] = ref;
    curves.add({'variable': v, 'ref': ref, 'knots': knots, 'x': grid, 'est': est, 'lower': lo, 'upper': hi, 'effect': effect, 'log': exponentiate});
    notes.add(nl.p < 0.05
        ? tr('« $v » : relation non linéaire (${fmtP(nl.p)}) : un coefficient unique la résumerait mal ; présenter la courbe ou des contrastes entre valeurs cliniquement choisies.',
            '"$v": nonlinear relationship (${fmtP(nl.p)}): a single coefficient would summarize it poorly; present the curve or contrasts between clinically chosen values.')
        : tr('« $v » : pas d\'écart démontré à la linéarité (${fmtP(nl.p)}) ; ce n\'est pas une preuve de linéarité (puissance limitée).',
            '"$v": no demonstrated departure from linearity (${fmtP(nl.p)}); this is not proof of linearity (limited power).'));
  }
  final anyNl = d.splineKnots.keys.any((v) => stats['spline_${v}_nonlinear_p']! < 0.05);
  return AnalysisResult(
    methodId: r.methodId,
    methodName: r.methodName,
    status: r.status,
    inputs: r.inputs,
    formula: '${r.formula} ${tr('Splines cubiques restreintes (Harrell) : x, puis (x − tⱼ)₊³ − (x − t_{k−1})₊³·(t_k − tⱼ)/(t_k − t_{k−1}) + (x − t_k)₊³·(t_{k−1} − tⱼ)/(t_k − t_{k−1}), divisés par (t_k − t₁)² ; linéaires au-delà des nœuds extrêmes. Tests de Wald : association (tous les coefficients de la variable) et non-linéarité (termes non linéaires).', 'Restricted cubic splines (Harrell): x, then (x − tⱼ)₊³ − (x − t_{k−1})₊³·(t_k − tⱼ)/(t_k − t_{k−1}) + (x − t_k)₊³·(t_{k−1} − tⱼ)/(t_k − t_{k−1}), divided by (t_k − t₁)²; linear beyond the outer knots. Wald tests: association (all coefficients of the variable) and nonlinearity (nonlinear terms).')}',
    estimates: r.estimates,
    statistics: {...r.statistics, ...stats},
    checks: [
      ...r.checks,
      Check('spline_linearity', tr('Forme de la relation (splines)', 'Shape of the relationship (splines)'), anyNl ? CheckStatus.warning : CheckStatus.ok, notes.join(' ')),
    ],
    alerts: r.alerts,
    tables: [
      ...r.tables,
      ResultTable(tr('Splines : tests de Wald', 'Splines: Wald tests'), [tr('Variable', 'Variable'), 'Test', tr('ddl', 'df'), statName, 'p'], rows),
      for (final c in curves)
        ResultTable(tr('Courbe dose-effet : ${c['variable']} (référence : médiane ${fmt(c['ref'] as double)})', 'Dose-response curve: ${c['variable']} (reference: median ${fmt(c['ref'] as double)})'),
            [c['variable'] as String, effect, tr('IC $pct %', '$pct% CI')], [
          for (var g = 0; g <= 60; g += 10)
            [fmt((c['x'] as List<double>)[g]), fmt((c['est'] as List<double>)[g]), '${fmt((c['lower'] as List<double>)[g])} – ${fmt((c['upper'] as List<double>)[g])}']
        ]),
    ],
    log: r.log,
    interpretation: Interpretation(
      whyThisMethod: '${r.interpretation.whyThisMethod} ${tr('Les splines cubiques restreintes laissent la relation avec une variable continue prendre une forme courbe, sans la découper en classes ni imposer une droite.', 'Restricted cubic splines let the relationship with a continuous variable take a curved shape, without cutting it into classes or imposing a straight line.')}',
      whatItMeans: '${r.interpretation.whatItMeans} ${notes.join(' ')}',
      notJustified: '${r.interpretation.notJustified} ${tr('Lire isolément les coefficients des termes de spline ; choisir le nombre de nœuds au vu des p ; extrapoler la courbe hors des données (bandes larges aux extrémités).', 'Reading the spline term coefficients in isolation; choosing the number of knots based on p-values; extrapolating the curve beyond the data (wide bands at the ends).')}',
    ),
    figures: {...r.figures, 'doseResponse': curves},
    lang: r.lang,
  );
}
