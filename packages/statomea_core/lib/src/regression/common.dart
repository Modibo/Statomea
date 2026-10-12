/// Éléments communs aux modèles de régression : tableau des coefficients,
/// facteurs d'inflation de la variance (GVIF), événements par paramètre.
library;

import 'dart:math' as math;

import '../i18n.dart';
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
