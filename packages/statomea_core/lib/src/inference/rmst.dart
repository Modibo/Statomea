/// Survie : temps moyen de survie restreint (RMST) et analyse landmark.
///  - RMST(τ) = ∫₀^τ S(t) dt (Kaplan-Meier) ; variance Σⱼ (∫_{tⱼ}^τ S)² dⱼ/[nⱼ(nⱼ − dⱼ)] (survRM2::rmst1) ; RMTL = τ − RMST ;
///    deux groupes : différence, rapport des RMST et des RMTL (échelle log, méthode delta), IC et p normaux (rmst2) ;
///  - landmark à L : sujets encore suivis à L, exposition figée à L, temps repris depuis L ; Kaplan-Meier, log-rank, Cox.
/// Validé contre validation/r/48_rmst_landmark.R (survRM2 1.0.4, survival 3.5).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/cox.dart';
import '../regression/design_matrix.dart';
import 'survival.dart';

/// RMST et sa variance jusqu'à [tau] à partir d'une courbe de Kaplan-Meier (marches à tous les temps observés).
({double rmst, double variance}) rmstFromKm(KmCurve km, double tau) {
  final st = [for (final s in km.steps) if (s.time <= tau) s];
  final m = st.length;
  // areas[0] = t₁·1 ; areas[k] = (t_{k+1} − t_k)·S_k, t_{m+1} = τ.
  final times = [for (final s in st) s.time, tau];
  final areas = <double>[times.first];
  for (var k = 0; k < m; k++) {
    areas.add((times[k + 1] - times[k]) * st[k].surv);
  }
  final rmst = areas.fold(0.0, (a, b) => a + b);
  var v = 0.0, tail = 0.0;
  for (var j = m - 1; j >= 0; j--) {
    tail += areas[j + 1]; // ∫_{t_j}^τ S
    final n = st[j].atRisk, d = st[j].events;
    final w = n - d == 0 ? 0.0 : d / (n * (n - d));
    v += tail * tail * w;
  }
  return (rmst: rmst, variance: v);
}

/// Analyse RMST par groupe ; avec deux groupes, contraste « second − premier » (modalités triées).
AnalysisResult rmstAnalysis(List<double?> timeRaw, List<String?> statusRaw, String eventLevel,
    {List<String?>? groupRaw, double? tau, double level = 0.95, String timeUnit = '', String? groupName}) {
  groupName ??= tr('Groupe', 'Group');
  final all = tr('Tous', 'All');
  final t = <double>[], d = <double>[], g = <String>[];
  for (var i = 0; i < timeRaw.length; i++) {
    final ti = timeRaw[i], si = statusRaw[i], gi = groupRaw == null ? all : groupRaw[i];
    if (ti == null || si == null || gi == null || !ti.isFinite) continue;
    if (ti < 0) throw StatInputError('negative_time', tr('Durée négative : vérifier les dates.', 'Negative time: check the dates.'));
    t.add(ti);
    d.add(si == eventLevel ? 1 : 0);
    g.add(gi);
  }
  if (!d.contains(1)) throw StatInputError('no_event', tr('Aucun événement « $eventLevel ».', 'No "$eventLevel" event.'));
  final levels = g.toSet().toList()..sort();
  final curves = [
    for (final lv in levels) kaplanMeier([for (var i = 0; i < t.length; i++) if (g[i] == lv) t[i]], [for (var i = 0; i < t.length; i++) if (g[i] == lv) d[i]], group: lv, level: level)
  ];
  // τ par défaut : le plus petit des derniers temps observés des groupes (comme survRM2).
  final tauMax = curves.map((c) => c.steps.last.time).reduce(math.min);
  final tt = tau ?? tauMax;
  if (tt <= 0 || tt > tauMax) {
    throw StatInputError('tau_range', tr('τ doit être compris entre 0 et ${fmt(tauMax)} (dernier temps observé du groupe le plus court).', 'τ must be between 0 and ${fmt(tauMax)} (last observed time of the shortest group).'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final res = [for (final c in curves) rmstFromKm(c, tt)];
  final u = timeUnit.isEmpty ? '' : ' $timeUnit';
  final pct = (level * 100).round();
  ({double est, double lo, double hi, double p})? diff, ratio, rmtlRatio;
  if (levels.length == 2) {
    final a = res[1], b = res[0];
    final dEst = a.rmst - b.rmst, dSe = math.sqrt(a.variance + b.variance);
    diff = (est: dEst, lo: dEst - z * dSe, hi: dEst + z * dSe, p: normalTwoSidedP(dEst / dSe));
    final lr = math.log(a.rmst) - math.log(b.rmst), lrSe = math.sqrt(a.variance / (a.rmst * a.rmst) + b.variance / (b.rmst * b.rmst));
    ratio = (est: math.exp(lr), lo: math.exp(lr - z * lrSe), hi: math.exp(lr + z * lrSe), p: normalTwoSidedP(lr / lrSe));
    final la = tt - a.rmst, lb = tt - b.rmst;
    final ll = math.log(la) - math.log(lb), llSe = math.sqrt(a.variance / (la * la) + b.variance / (lb * lb));
    rmtlRatio = (est: math.exp(ll), lo: math.exp(ll - z * llSe), hi: math.exp(ll + z * llSe), p: normalTwoSidedP(ll / llSe));
  }
  return AnalysisResult(
    methodId: 'rmst',
    methodName: tr('Temps moyen de survie restreint (RMST) à τ = ${fmt(tt)}$u', 'Restricted mean survival time (RMST) at τ = ${fmt(tt)}$u'),
    inputs: {'n': t.length, 'groups': levels, 'tau': tt, 'level': level, 'eventLevel': eventLevel},
    formula: tr(
        'RMST(τ) = ∫₀^τ Ŝ(t) dt (aire sous la courbe de Kaplan-Meier) ; Var = Σⱼ (∫_{tⱼ}^τ Ŝ)²·dⱼ/[nⱼ(nⱼ − dⱼ)] ; RMTL = τ − RMST (temps perdu). Deux groupes : différence (ES = √(v₁ + v₀)), rapports des RMST et des RMTL sur l\'échelle log (méthode delta) ; IC et p par la loi normale (comme survRM2).',
        'RMST(τ) = ∫₀^τ Ŝ(t) dt (area under the Kaplan-Meier curve); Var = Σⱼ (∫_{tⱼ}^τ Ŝ)²·dⱼ/[nⱼ(nⱼ − dⱼ)]; RMTL = τ − RMST (time lost). Two groups: difference (SE = √(v₁ + v₀)), ratios of RMSTs and RMTLs on the log scale (delta method); normal CIs and p-values (as survRM2).'),
    estimates: [
      for (var k = 0; k < levels.length; k++)
        Estimate(tr('RMST — ${levels[k]}', 'RMST — ${levels[k]}'), res[k].rmst,
            lower: res[k].rmst - z * math.sqrt(res[k].variance), upper: res[k].rmst + z * math.sqrt(res[k].variance), se: math.sqrt(res[k].variance), level: level),
      if (diff != null) Estimate(tr('Différence de RMST ${levels[1]} − ${levels[0]}', 'RMST difference ${levels[1]} − ${levels[0]}'), diff.est, lower: diff.lo, upper: diff.hi, pValue: diff.p, level: level),
      if (ratio != null) Estimate(tr('Rapport des RMST ${levels[1]} / ${levels[0]}', 'RMST ratio ${levels[1]} / ${levels[0]}'), ratio.est, lower: ratio.lo, upper: ratio.hi, pValue: ratio.p, level: level),
      if (rmtlRatio != null) Estimate(tr('Rapport des RMTL ${levels[1]} / ${levels[0]}', 'RMTL ratio ${levels[1]} / ${levels[0]}'), rmtlRatio.est, lower: rmtlRatio.lo, upper: rmtlRatio.hi, pValue: rmtlRatio.p, level: level),
    ],
    statistics: {
      'tau': tt,
      for (var k = 0; k < levels.length; k++) 'rmst_${levels[k]}': res[k].rmst,
      for (var k = 0; k < levels.length; k++) 'se_${levels[k]}': math.sqrt(res[k].variance),
      if (diff != null) ...{'diff': diff.est, 'diff_p': diff.p, 'diff_lower': diff.lo},
      if (ratio != null) ...{'ratio': ratio.est, 'ratio_lower': ratio.lo, 'ratio_p': ratio.p},
      if (rmtlRatio != null) ...{'rmtl_ratio': rmtlRatio.est, 'rmtl_ratio_upper': rmtlRatio.hi},
    },
    checks: [
      Check('tau_prespecified', tr('τ fixé à l\'avance (protocole)', 'τ fixed in advance (protocol)'), CheckStatus.notAssessed,
          tr('Choisir τ après avoir vu les courbes permet d\'orienter le résultat ; il doit être cliniquement pertinent et couvert par le suivi des deux groupes.',
              'Choosing τ after seeing the curves can steer the result; it must be clinically relevant and covered by the follow-up of both groups.')),
      Check('censoring', tr('Censure non informative', 'Non-informative censoring'), CheckStatus.notAssessed, ''),
    ],
    tables: [
      ResultTable(tr('RMST par groupe (τ = ${fmt(tt)}$u)', 'RMST by group (τ = ${fmt(tt)}$u)'), [groupName, 'n', 'RMST', 'ES', tr('IC $pct %', '$pct% CI'), 'RMTL'], [
        for (var k = 0; k < levels.length; k++)
          [levels[k], '${curves[k].n}', fmt(res[k].rmst), fmt(math.sqrt(res[k].variance)), '${fmt(res[k].rmst - z * math.sqrt(res[k].variance))} – ${fmt(res[k].rmst + z * math.sqrt(res[k].variance))}', fmt(tt - res[k].rmst)]
      ]),
      if (diff != null)
        ResultTable(tr('Comparaison', 'Comparison'), [tr('Contraste', 'Contrast'), tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), 'p'], [
          [tr('Différence de RMST', 'RMST difference'), fmt(diff.est), '${fmt(diff.lo)} – ${fmt(diff.hi)}', fmtP(diff.p)],
          [tr('Rapport des RMST', 'RMST ratio'), fmt(ratio!.est), '${fmt(ratio.lo)} – ${fmt(ratio.hi)}', fmtP(ratio.p)],
          [tr('Rapport des RMTL', 'RMTL ratio'), fmt(rmtlRatio!.est), '${fmt(rmtlRatio.lo)} – ${fmt(rmtlRatio.hi)}', fmtP(rmtlRatio.p)],
        ]),
    ],
    figures: {
      'kaplanMeier': {
        'unit': timeUnit,
        'tau': tt,
        'curves': [
          for (final c in curves)
            {'group': c.group, 'time': [for (final s in c.steps) s.time], 'surv': [for (final s in c.steps) s.surv], 'censored': [for (final s in c.steps) s.censored], 'atRisk': [for (final s in c.steps) s.atRisk]}
        ],
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr('Le RMST résume la survie par une durée (le temps moyen vécu sans événement jusqu\'à τ), interprétable même quand les risques ne sont pas proportionnels, contrairement au HR.',
          'The RMST summarizes survival as a duration (the mean event-free time lived up to τ), interpretable even when hazards are not proportional, unlike the HR.'),
      whatItMeans: [
        for (var k = 0; k < levels.length; k++) tr('« ${levels[k]} » : ${fmt(res[k].rmst)}$u en moyenne sans événement sur ${fmt(tt)}$u.', '"${levels[k]}": ${fmt(res[k].rmst)}$u on average without event over ${fmt(tt)}$u.'),
        if (diff != null) tr('Différence ${fmt(diff.est)}$u (IC ${fmt(diff.lo)} à ${fmt(diff.hi)}), ${fmtP(diff.p)}.', 'Difference ${fmt(diff.est)}$u (CI ${fmt(diff.lo)} to ${fmt(diff.hi)}), ${fmtP(diff.p)}.'),
      ].join(' '),
      notJustified: tr('Extrapoler le RMST au-delà de τ ; présenter le RMST comme une espérance de vie ; choisir τ a posteriori.', 'Extrapolating the RMST beyond τ; presenting the RMST as a life expectancy; choosing τ post hoc.'),
    ),
  );
}

/// Analyse landmark : sujets encore suivis au temps [landmark], exposition « [switchTime] ≤ landmark » figée, temps
/// repris depuis le landmark ; Kaplan-Meier et log-rank par exposition, Cox ajusté sur [terms].
AnalysisResult landmarkAnalysis(Dataset ds, {required String time, required String status, required String eventLevel, required String switchTime,
    required double landmark, List<TermSpec> terms = const [], String exposureName = 'expose_au_landmark', double level = 0.95}) {
  final tm = ds.numeric(time), sw = ds.numeric(switchTime), st = ds.text(status);
  final yes = tr('oui', 'yes'), no = tr('non', 'no');
  final keepCols = [for (final n in ds.names) if (n != time && n != switchTime && n != status) n];
  final rows = <List<String?>>[];
  var excluded = 0;
  for (var i = 0; i < ds.rowCount; i++) {
    final ti = tm[i];
    if (ti == null || st[i] == null) continue;
    if (ti <= landmark) {
      excluded++;
      continue;
    }
    final exposed = sw[i] != null && sw[i]! <= landmark;
    rows.add([for (final n in keepCols) ds.cell(i, n), '${ti - landmark}', st[i], exposed ? yes : no]);
  }
  const tName = 'temps_depuis_landmark';
  final sub = Dataset([...keepCols, tName, status, exposureName], rows, source: tr('${ds.source}, sujets suivis au-delà de ${fmt(landmark)}', '${ds.source}, subjects followed beyond ${fmt(landmark)}'));
  if (rows.length < 10 || !sub.text(exposureName).contains(yes) || !sub.text(exposureName).contains(no)) {
    throw StatInputError('landmark_groups', tr('Au landmark ${fmt(landmark)}, il faut des sujets exposés et non exposés encore suivis.', 'At landmark ${fmt(landmark)}, exposed and unexposed subjects still followed are needed.'));
  }
  final km = survivalAnalysis(sub.numeric(tName), sub.text(status), eventLevel, groupRaw: sub.text(exposureName), groupName: exposureName);
  final cox = coxRegression(buildSurvivalDesign(sub, tName, status, eventLevel, [TermSpec(exposureName, categorical: true, reference: no), ...terms]));
  final hr = cox.estimates.first;
  final nExp = sub.text(exposureName).where((v) => v == yes).length;
  return AnalysisResult(
    methodId: 'landmark',
    methodName: tr('Analyse landmark à ${fmt(landmark)} (exposition « $switchTime » figée au landmark)', 'Landmark analysis at ${fmt(landmark)} (exposure "$switchTime" fixed at the landmark)'),
    inputs: {'landmark': landmark, 'switchTime': switchTime, 'n': rows.length, 'excluded': excluded, 'cox': cox.inputs['model']},
    formula: tr(
        'Sujets encore suivis à L = ${fmt(landmark)} ; exposé = « $switchTime » ≤ L ; temps repris depuis L ; Kaplan-Meier et log-rank par exposition ; Cox (Efron) de l\'exposition${terms.isEmpty ? '' : ' ajusté sur ${terms.map((e) => e.variable).join(', ')}'}. Une exposition survenant après L est comptée comme non exposée (dilution).',
        'Subjects still followed at L = ${fmt(landmark)}; exposed = "$switchTime" ≤ L; time restarted from L; Kaplan-Meier and log-rank by exposure; Cox (Efron) of the exposure${terms.isEmpty ? '' : ' adjusted for ${terms.map((e) => e.variable).join(', ')}'}. An exposure occurring after L is counted as unexposed (dilution).'),
    estimates: [...cox.estimates.where((e) => e.label.startsWith('HR')), ...km.estimates],
    statistics: {
      'n': rows.length.toDouble(), 'excluded': excluded.toDouble(), 'exposed': nExp.toDouble(),
      'logrank_chi2': km.statistics['logrank_chi2'] ?? double.nan, 'logrank_p': km.statistics['logrank_p'] ?? double.nan,
      for (final e in cox.statistics.entries) if (e.key.startsWith('beta_') || e.key.startsWith('se_')) e.key: e.value,
      'events': cox.statistics['events'] ?? 0,
    },
    checks: [
      Check('landmark_prespecified', tr('Landmark fixé à l\'avance', 'Landmark fixed in advance'), CheckStatus.notAssessed,
          tr('Le choix de L doit précéder l\'analyse ; plusieurs landmarks rapportés ensemble montrent la robustesse.', 'The choice of L must precede the analysis; several landmarks reported together show robustness.')),
      Check('excluded', tr('Sujets exclus (événement ou censure avant le landmark)', 'Subjects excluded (event or censoring before the landmark)'), CheckStatus.ok,
          tr('$excluded sujet(s) exclu(s) ; $nExp exposé(s) et ${rows.length - nExp} non exposé(s) au landmark.', '$excluded subject(s) excluded; $nExp exposed and ${rows.length - nExp} unexposed at the landmark.')),
      ...cox.checks.where((c) => c.id == 'proportional_hazards'),
    ],
    alerts: [...cox.alerts, ...km.alerts],
    tables: [...cox.tables.take(1), ...km.tables.take(2)],
    figures: km.figures,
    interpretation: Interpretation(
      whyThisMethod: tr('Une exposition acquise pendant le suivi ne peut pas être codée à l\'inclusion (temps immortel) ; le landmark compare, à partir d\'une date commune, les sujets déjà exposés aux autres.',
          'An exposure acquired during follow-up cannot be coded at inclusion (immortal time); the landmark compares, from a common date, subjects already exposed with the others.'),
      whatItMeans: tr('À partir de ${fmt(landmark)} : HR des exposés = ${fmt(hr.value)} (IC ${fmt(hr.lower)} à ${fmt(hr.upper)}), ${fmtP(hr.pValue)} ; $excluded sujet(s) exclu(s) car sortis avant le landmark.',
          'From ${fmt(landmark)}: HR of the exposed = ${fmt(hr.value)} (CI ${fmt(hr.lower)} to ${fmt(hr.upper)}), ${fmtP(hr.pValue)}; $excluded subject(s) excluded as they left before the landmark.'),
      notJustified: tr('Généraliser le résultat aux sujets décédés avant le landmark ; ignorer les expositions survenues après le landmark ; choisir L a posteriori.',
          'Generalizing the result to subjects who died before the landmark; ignoring exposures occurring after the landmark; choosing L post hoc.'),
    ),
  );
}
