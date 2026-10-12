/// Analyse de survie descriptive : estimateur de Kaplan-Meier (variance de
/// Greenwood, IC « log » comme `survfit`), médiane de survie et son IC
/// (convention de `quantile.survfit`), survie à un horizon, et test du
/// log-rank (`survdiff`, rho = 0) pour k groupes.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';

class KmStep {
  final double time;
  final int atRisk, events, censored;
  final double surv, se, lower, upper; // se = ES de −log S (comme survfit$std.err)
  KmStep(this.time, this.atRisk, this.events, this.censored, this.surv, this.se, this.lower, this.upper);
}

class KmCurve {
  final String group;
  final int n, events;
  final List<KmStep> steps;
  final double? median, medianLower, medianUpper;
  KmCurve(this.group, this.n, this.events, this.steps, this.median, this.medianLower, this.medianUpper);

  /// Survie (et IC) à l'horizon t (dernière valeur ≤ t).
  ({double s, double lower, double upper})? at(double t) {
    if (steps.isEmpty) return null;
    if (t > steps.last.time && steps.last.atRisk - steps.last.events - steps.last.censored <= 0) return null;
    var s = 1.0, lo = 1.0, hi = 1.0;
    for (final st in steps) {
      if (st.time > t) break;
      s = st.surv;
      lo = st.lower;
      hi = st.upper;
    }
    return (s: s, lower: lo, upper: hi);
  }
}

/// Premier temps où une courbe en escalier passe sous 0,5 ; si elle vaut
/// exactement 0,5 sur un palier, moyenne avec le temps d'événement suivant.
double? _crossHalf(List<double> times, List<double> s) {
  for (var i = 0; i < s.length; i++) {
    if ((s[i] - 0.5).abs() < 1e-12) {
      for (var j = i + 1; j < s.length; j++) {
        if (s[j] < s[i] - 1e-12) return (times[i] + times[j]) / 2;
      }
      return null;
    }
    if (s[i] < 0.5) return times[i];
  }
  return null;
}

KmCurve kaplanMeier(List<double> time, List<double> status, {String group = 'Tous', double level = 0.95}) {
  final z = normalQuantile(1 - (1 - level) / 2);
  final times = {...time}.toList()..sort();
  var nRisk = time.length;
  var s = 1.0, cumVar = 0.0;
  final steps = <KmStep>[];
  for (final t in times) {
    var d = 0, c = 0;
    for (var i = 0; i < time.length; i++) {
      if (time[i] == t) status[i] == 1 ? d++ : c++;
    }
    if (d > 0) {
      s *= 1 - d / nRisk;
      if (nRisk - d > 0) {
        cumVar += d / (nRisk * (nRisk - d));
      } else {
        cumVar = double.nan;
      }
    }
    final se = math.sqrt(cumVar);
    final lo = s == 0 || se.isNaN ? double.nan : s * math.exp(-z * se);
    final hi = s == 0 || se.isNaN ? double.nan : math.min(1.0, s * math.exp(z * se));
    steps.add(KmStep(t, nRisk, d, c, s, se, lo, hi));
    nRisk -= d + c;
  }
  // Médiane et IC : seuls les temps d'événement comptent pour les paliers.
  final ev = [for (final st in steps) if (st.events > 0) st];
  final et = [for (final st in ev) st.time];
  final med = _crossHalf(et, [for (final st in ev) st.surv]);
  // La bande inférieure passe sous 0,5 la première : elle donne la borne basse.
  final medLo = _crossHalf(et, [for (final st in ev) st.lower.isNaN ? 0.0 : st.lower]);
  final medHi = _crossHalf(et, [for (final st in ev) st.upper.isNaN ? 0.0 : st.upper]);
  return KmCurve(group, time.length, status.where((v) => v == 1).length, steps, med, medLo, medHi);
}

/// Test du log-rank (k groupes) : χ² = (O − E)ᵀ V⁻ (O − E), ddl k − 1.
({double chi2, int df, double p, List<double> observed, List<double> expected}) logRank(
    List<double> time, List<double> status, List<int> group, int k) {
  final o = List<double>.filled(k, 0), e = List<double>.filled(k, 0);
  final v = Matrix(k, k);
  final times = {for (var i = 0; i < time.length; i++) if (status[i] == 1) time[i]}.toList()..sort();
  for (final t in times) {
    final nj = List<double>.filled(k, 0), dj = List<double>.filled(k, 0);
    for (var i = 0; i < time.length; i++) {
      if (time[i] >= t) nj[group[i]]++;
      if (time[i] == t && status[i] == 1) dj[group[i]]++;
    }
    final n = nj.fold(0.0, (a, b) => a + b), d = dj.fold(0.0, (a, b) => a + b);
    for (var g = 0; g < k; g++) {
      o[g] += dj[g];
      e[g] += d * nj[g] / n;
    }
    if (n > 1) {
      final f = d * (n - d) / (n * n * (n - 1));
      for (var a = 0; a < k; a++) {
        for (var b = 0; b < k; b++) {
          v.data[a * k + b] += f * (a == b ? nj[a] * (n - nj[a]) : -nj[a] * nj[b]);
        }
      }
    }
  }
  final m = k - 1;
  final sub = Matrix(m, m);
  for (var a = 0; a < m; a++) {
    for (var b = 0; b < m; b++) {
      sub.set(a, b, v.get(a, b));
    }
  }
  final diff = [for (var g = 0; g < m; g++) o[g] - e[g]];
  final sol = solveSpd(sub, diff);
  var chi = 0.0;
  if (sol != null) {
    for (var a = 0; a < m; a++) {
      chi += sol[a] * diff[a];
    }
  }
  return (chi2: chi, df: m, p: chiSquareUpper(chi, m.toDouble()), observed: o, expected: e);
}

/// Analyse descriptive de survie : Kaplan-Meier par groupe, médianes,
/// survie à un horizon, log-rank si plusieurs groupes.
AnalysisResult survivalAnalysis(List<double?> timeRaw, List<String?> statusRaw, String eventLevel,
    {List<String?>? groupRaw, double? horizon, double level = 0.95, String timeUnit = '', String? groupName}) {
  groupName ??= tr('Groupe', 'Group');
  final all = tr('Tous', 'All');
  final t = <double>[], d = <double>[], g = <String>[];
  var dropped = 0;
  for (var i = 0; i < timeRaw.length; i++) {
    final ti = timeRaw[i], si = statusRaw[i], gi = groupRaw == null ? all : groupRaw[i];
    if (ti == null || !ti.isFinite || si == null || gi == null) {
      dropped++;
      continue;
    }
    if (ti < 0) throw StatInputError('negative_time', tr('Durée négative (${fmt(ti)}) : vérifier les dates.', 'Negative time (${fmt(ti)}): check the dates.'));
    t.add(ti);
    d.add(si == eventLevel ? 1 : 0);
    g.add(gi);
  }
  if (t.isEmpty) throw StatInputError('no_data', tr('Aucune observation complète (durée, statut${groupRaw == null ? "" : ", groupe"}).', 'No complete observation (time, status${groupRaw == null ? "" : ", group"}).'));
  if (!d.contains(1)) throw StatInputError('no_event', tr('Aucun événement « $eventLevel » : la survie ne peut pas être estimée.', 'No "$eventLevel" event: survival cannot be estimated.'));
  final levels = g.toSet().toList()..sort();
  final curves = [
    for (final lv in levels)
      kaplanMeier([for (var i = 0; i < t.length; i++) if (g[i] == lv) t[i]], [for (var i = 0; i < t.length; i++) if (g[i] == lv) d[i]],
          group: lv, level: level)
  ];
  final u = timeUnit.isEmpty ? '' : ' $timeUnit';
  final pct = (level * 100).round();
  final alerts = <Alert>[
    if (dropped > 0) Alert('missing_values', Severity.caution, tr('$dropped ligne(s) incomplète(s) exclue(s).', '$dropped incomplete row(s) excluded.')),
    for (final c in curves)
      if (c.median == null)
        Alert('median_not_reached', Severity.info, tr('« ${c.group} » : médiane de survie non atteinte (la survie reste > 50 % sur le suivi).', '"${c.group}": median survival not reached (survival stays > 50% over follow-up).')),
    for (final c in curves)
      if (c.events < 5) Alert('few_events', Severity.caution, tr('« ${c.group} » : seulement ${c.events} événement(s) ; courbe très imprécise.', '"${c.group}": only ${c.events} event(s); very imprecise curve.')),
  ];
  ({double chi2, int df, double p, List<double> observed, List<double> expected})? lr;
  if (levels.length > 1) {
    lr = logRank(t, d, [for (final x in g) levels.indexOf(x)], levels.length);
  }
  final estimates = <Estimate>[
    for (final c in curves)
      if (c.median != null) Estimate(tr('Médiane de survie — ${c.group}', 'Median survival — ${c.group}'), c.median!, lower: c.medianLower, upper: c.medianUpper ?? double.infinity, level: level),
    if (horizon != null)
      for (final c in curves)
        if (c.at(horizon) != null)
          Estimate(tr('Survie à ${fmt(horizon)}$u — ${c.group}', 'Survival at ${fmt(horizon)}$u — ${c.group}'), c.at(horizon)!.s, lower: c.at(horizon)!.lower, upper: c.at(horizon)!.upper, level: level),
  ];
  return AnalysisResult(
    methodId: 'kaplan_meier',
    methodName: levels.length > 1 ? tr('Survie : Kaplan-Meier et test du log-rank', 'Survival: Kaplan-Meier and log-rank test') : tr('Survie : Kaplan-Meier', 'Survival: Kaplan-Meier'),
    inputs: {'n': t.length, 'dropped': dropped, 'groups': levels, 'horizon': horizon, 'level': level, 'eventLevel': eventLevel},
    formula: tr('Ŝ(t) = Π_{t_j ≤ t} (1 − d_j/n_j) ; Greenwood : Var(log Ŝ) = Σ d_j/[n_j(n_j − d_j)] ; IC = Ŝ·exp(± z·ES) ; médiane = premier t où Ŝ(t) ≤ 0,5 (IC : idem sur les bornes) ; log-rank : χ² = (O − E)ᵀV⁻¹(O − E), ddl k − 1.',
        'Ŝ(t) = Π_{t_j ≤ t} (1 − d_j/n_j); Greenwood: Var(log Ŝ) = Σ d_j/[n_j(n_j − d_j)]; CI = Ŝ·exp(± z·SE); median = first t where Ŝ(t) ≤ 0.5 (CI: same on the bounds); log-rank: χ² = (O − E)ᵀV⁻¹(O − E), df k − 1.'),
    estimates: estimates,
    statistics: {
      'n': t.length.toDouble(),
      'events': d.where((v) => v == 1).length.toDouble(),
      if (lr != null) 'logrank_chi2': lr.chi2,
      if (lr != null) 'logrank_df': lr.df.toDouble(),
      if (lr != null) 'logrank_p': lr.p,
      for (final c in curves) 'median_${c.group}': c.median ?? double.nan,
    },
    checks: [
      Check('censoring', tr('Censure non informative', 'Non-informative censoring'), CheckStatus.notAssessed,
          tr('Les sujets censurés doivent avoir le même pronostic que ceux qui restent suivis ; à argumenter.', 'Censored subjects must have the same prognosis as those still followed; to be argued.')),
      if (lr != null)
        Check('crossing', tr('Courbes qui ne se croisent pas (puissance du log-rank)', 'Non-crossing curves (log-rank power)'), CheckStatus.notAssessed,
            tr('Le log-rank est le plus puissant quand le rapport des risques est constant ; si les courbes se croisent, il peut ne rien détecter.',
                'The log-rank test is most powerful when the hazard ratio is constant; if the curves cross, it may detect nothing.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Résumé par groupe', 'Summary by group'), [groupName, 'n', tr('Événements', 'Events'), tr('Médiane$u', 'Median$u'), tr('IC $pct %', '$pct% CI'), if (lr != null) tr('Observés', 'Observed'), if (lr != null) tr('Attendus', 'Expected')], [
        for (var k = 0; k < curves.length; k++)
          [
            curves[k].group,
            '${curves[k].n}',
            '${curves[k].events}',
            curves[k].median == null ? tr('non atteinte', 'not reached') : fmt(curves[k].median),
            curves[k].median == null ? '—' : '${fmt(curves[k].medianLower)} – ${curves[k].medianUpper == null ? "NA" : fmt(curves[k].medianUpper)}',
            if (lr != null) fmt(lr.observed[k]),
            if (lr != null) fmt(lr.expected[k]),
          ]
      ]),
      if (lr != null) ResultTable(tr('Test du log-rank', 'Log-rank test'), ['χ²', tr('ddl', 'df'), 'p'], [[fmt(lr.chi2), '${lr.df}', fmtP(lr.p)]]),
      for (final c in curves)
        ResultTable(tr('Table de survie — ${c.group}', 'Life table — ${c.group}'), [tr('Temps', 'Time'), tr('À risque', 'At risk'), tr('Événements', 'Events'), tr('Censures', 'Censored'), tr('Survie', 'Survival'), tr('IC $pct %', '$pct% CI')], [
          for (final st in c.steps.where((s) => s.events > 0))
            [fmt(st.time), '${st.atRisk}', '${st.events}', '${st.censored}', fmt(st.surv), '${fmt(st.lower)} – ${fmt(st.upper)}']
        ]),
    ],
    figures: {
      'kaplanMeier': {
        'unit': timeUnit,
        'curves': [
          for (final c in curves)
            {
              'group': c.group,
              'time': [for (final s in c.steps) s.time],
              'surv': [for (final s in c.steps) s.surv],
              'censored': [for (final s in c.steps) s.censored],
              'atRisk': [for (final s in c.steps) s.atRisk],
            }
        ],
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr("Délai jusqu'à un événement avec censure : Kaplan-Meier estime la survie sans exclure les censurés${lr != null ? " ; le log-rank compare les groupes sur toute la durée du suivi." : "."}",
          'Time to an event with censoring: Kaplan-Meier estimates survival without excluding censored subjects${lr != null ? "; the log-rank test compares groups over the whole follow-up." : "."}'),
      whatItMeans: [
        for (final c in curves)
          tr('« ${c.group} » : ${c.events} événement(s) sur ${c.n}, médiane ${c.median == null ? "non atteinte" : "${fmt(c.median)}$u (IC ${fmt(c.medianLower)} à ${c.medianUpper == null ? "non atteinte" : fmt(c.medianUpper)})"}.',
              '"${c.group}": ${c.events} event(s) out of ${c.n}, median ${c.median == null ? "not reached" : "${fmt(c.median)}$u (CI ${fmt(c.medianLower)} to ${c.medianUpper == null ? "not reached" : fmt(c.medianUpper)})"}.'),
        if (lr != null) tr('Log-rank : χ² = ${fmt(lr.chi2)} (ddl ${lr.df}), ${fmtP(lr.p)}.', 'Log-rank: χ² = ${fmt(lr.chi2)} (df ${lr.df}), ${fmtP(lr.p)}.'),
      ].join(' '),
      notJustified: tr("Lire la fin de la courbe (peu de sujets à risque) comme une estimation précise ; conclure à l'absence de différence parce que le log-rank n'est pas significatif ; attribuer une différence au facteur de groupe sans ajustement (modèle de Cox) ni randomisation.",
          'Reading the tail of the curve (few subjects at risk) as a precise estimate; concluding no difference because the log-rank test is not significant; attributing a difference to the grouping factor without adjustment (Cox model) or randomization.'),
    ),
  );
}
