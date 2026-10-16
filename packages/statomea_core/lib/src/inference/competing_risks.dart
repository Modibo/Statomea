/// Risques concurrents, partie descriptive : incidence cumulée d'Aalen-Johansen par cause et par groupe, avec la variance
/// de Gray (1988) comme `cmprsk::cuminc` (correction des ex aequo comprise), IC ponctuel par transformation log(−log),
/// comparaison au « 1 − Kaplan-Meier » naïf (événements concurrents traités comme des censures), et comparaison des
/// groupes par un modèle de Fine-Gray (variance robuste). Validé contre validation/r/40_risques_concurrents.R.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import '../regression/fine_gray.dart';
import 'survival.dart';

class CifStep {
  final double time, cif, variance, lower, upper;
  final int atRisk, events;
  const CifStep(this.time, this.atRisk, this.events, this.cif, this.variance, this.lower, this.upper);
}

class CifCurve {
  final String group;
  final int n, events, competing, censored;
  final List<CifStep> steps;
  const CifCurve(this.group, this.n, this.events, this.competing, this.censored, this.steps);

  /// Incidence cumulée (et IC) à l'horizon t : dernière marche ≤ t ; null au-delà du dernier temps observé.
  CifStep? at(double t, double lastTime) {
    if (t > lastTime) return null;
    CifStep? s;
    for (final st in steps) {
      if (st.time > t) break;
      s = st;
    }
    return s ?? CifStep(t, n, 0, 0, 0, 0, 0);
  }
}

/// Incidence cumulée de la cause [cause] (codes : 0 = censure, autre entier = cause). Une marche par temps d'événement
/// de cette cause, comme cuminc (la variance intègre aussi les temps des autres causes) ; variance de Gray ; IC F^exp(±z·√v/(F·log F)).
CifCurve cumulativeIncidence(List<double> time, List<int> code, int cause, {String group = 'Tous', double level = 0.95}) {
  final z = normalQuantile(1 - (1 - level) / 2);
  final n = time.length;
  final order = List<int>.generate(n, (i) => i)..sort((a, b) => time[a].compareTo(time[b]));
  final steps = <CifStep>[];
  var fk = 1.0, f = 0.0, v1 = 0.0, v2 = 0.0, v3 = 0.0;
  var q = 0;
  while (q < n) {
    final t = time[order[q]];
    var nd1 = 0, nd2 = 0, m = q;
    while (m < n && time[order[m]] == t) {
      final c = code[order[m]];
      if (c == cause) {
        nd1++;
      } else if (c != 0) {
        nd2++;
      }
      m++;
    }
    final nr = n - q;
    if (nd1 + nd2 > 0) {
      final fkn = fk * (nr - nd1 - nd2) / nr;
      f += fk * nd1 / nr;
      if (nd2 > 0 && fkn > 0) {
        final t5 = nd2 > 1 ? 1 - (nd2 - 1) / (nr - 1) : 1.0;
        final t6 = fk * fk * t5 * nd2 / (nr * nr);
        final t3 = 1 / fkn, t4 = f / fkn;
        v1 += t4 * t4 * t6;
        v2 += t3 * t4 * t6;
        v3 += t3 * t3 * t6;
      }
      if (nd1 > 0) {
        final t5 = nd1 > 1 ? 1 - (nd1 - 1) / (nr - 1) : 1.0;
        final t6 = fk * fk * t5 * nd1 / (nr * nr);
        final t3 = fkn > 0 ? 1 / fkn : 0.0, t4 = 1 + t3 * f;
        v1 += t4 * t4 * t6;
        v2 += t3 * t4 * t6;
        v3 += t3 * t3 * t6;
      }
      final v = math.max(0.0, v1 + f * f * v3 - 2 * f * v2);
      double lo = f, hi = f;
      if (f > 0 && f < 1 && v > 0) {
        final k = z * math.sqrt(v) / (f * math.log(f));
        lo = math.pow(f, math.exp(k)).toDouble();
        hi = math.pow(f, math.exp(-k)).toDouble();
      }
      if (nd1 > 0) steps.add(CifStep(t, nr, nd1, f, v, lo, hi));
      fk = fkn;
    }
    q = m;
  }
  return CifCurve(group, n, code.where((c) => c == cause).length, code.where((c) => c != 0 && c != cause).length, code.where((c) => c == 0).length, steps);
}

/// Analyse descriptive des risques concurrents à partir des colonnes brutes.
/// [censorLevels] : modalités de censure ; toute modalité autre que [causeLevel] et la censure est un événement concurrent.
AnalysisResult competingRisksAnalysis(List<double?> timeRaw, List<String?> statusRaw, String causeLevel, Set<String> censorLevels,
    {List<String?>? groupRaw, double? horizon, double level = 0.95, String timeUnit = '', String? groupName}) {
  groupName ??= tr('Groupe', 'Group');
  final all = tr('Tous', 'All');
  if (censorLevels.contains(causeLevel)) {
    throw StatInputError('cause_is_censor', tr('La modalité « $causeLevel » ne peut pas être à la fois l\'événement d\'intérêt et une censure.', 'Level "$causeLevel" cannot be both the event of interest and censoring.'));
  }
  final t = <double>[], c = <int>[], g = <String>[];
  final others = <String>{};
  var dropped = 0;
  for (var i = 0; i < timeRaw.length; i++) {
    final ti = timeRaw[i], si = statusRaw[i], gi = groupRaw == null ? all : groupRaw[i];
    if (ti == null || !ti.isFinite || si == null || gi == null) {
      dropped++;
      continue;
    }
    if (ti < 0) throw StatInputError('negative_time', tr('Durée négative (${fmt(ti)}) : vérifier les dates.', 'Negative time (${fmt(ti)}): check the dates.'));
    t.add(ti);
    g.add(gi);
    if (si == causeLevel) {
      c.add(1);
    } else if (censorLevels.contains(si)) {
      c.add(0);
    } else {
      c.add(2);
      others.add(si);
    }
  }
  if (t.isEmpty) throw StatInputError('no_data', tr('Aucune observation complète.', 'No complete observation.'));
  if (!c.contains(1)) throw StatInputError('no_event', tr('Aucun événement « $causeLevel ».', 'No "$causeLevel" event.'));
  final otherLabel = others.isEmpty ? tr('événement concurrent', 'competing event') : (others.toList()..sort()).join(' / ');
  final levels = g.toSet().toList()..sort();
  List<int> idx(String lv) => [for (var i = 0; i < t.length; i++) if (g[i] == lv) i];
  final cause = <CifCurve>[], comp = <CifCurve>[], naive = <KmCurve>[];
  final lastTime = <String, double>{};
  for (final lv in levels) {
    final ii = idx(lv);
    final tt = [for (final i in ii) t[i]], cc = [for (final i in ii) c[i]];
    cause.add(cumulativeIncidence(tt, cc, 1, group: lv, level: level));
    comp.add(cumulativeIncidence(tt, cc, 2, group: lv, level: level));
    naive.add(kaplanMeier(tt, [for (final x in cc) x == 1 ? 1.0 : 0.0], group: lv, level: level));
    lastTime[lv] = tt.reduce(math.max);
  }
  final u = timeUnit.isEmpty ? '' : ' $timeUnit';
  final pct = (level * 100).round();
  // Horizon par défaut : dernier temps commun à tous les groupes.
  final h = horizon ?? lastTime.values.reduce(math.min);
  double naiveAt(KmCurve k) {
    var s = 1.0;
    for (final st in k.steps) {
      if (st.time > h) break;
      s = st.surv;
    }
    return 1 - s;
  }

  // Comparaison des groupes : Fine-Gray avec le groupe (référence = première modalité).
  FineGrayFit? fg;
  if (levels.length > 1) {
    final x = [for (var i = 0; i < t.length; i++) [for (var l = 1; l < levels.length; l++) g[i] == levels[l] ? 1.0 : 0.0]];
    fg = fitFineGray(x, t, c);
  }
  double? fgWald;
  if (fg != null) {
    final inv = invertSpd(fg.cov);
    if (inv != null) {
      final v = inv.multiplyVector(fg.beta);
      fgWald = 0;
      for (var i = 0; i < v.length; i++) {
        fgWald = fgWald! + v[i] * fg.beta[i];
      }
    }
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final shr = fg == null
      ? const <(String, double, double, double, double)>[]
      : [
          for (var l = 1; l < levels.length; l++)
            () {
              final b = fg!.beta[l - 1], se = math.sqrt(fg.cov.get(l - 1, l - 1));
              return (levels[l], math.exp(b), math.exp(b - z * se), math.exp(b + z * se), normalTwoSidedP(b / se));
            }()
        ];
  final fgP = fgWald == null ? null : chiSquareUpper(fgWald, (levels.length - 1).toDouble());
  final alerts = <Alert>[
    if (dropped > 0) Alert('missing_values', Severity.caution, tr('$dropped ligne(s) incomplète(s) exclue(s).', '$dropped incomplete row(s) excluded.')),
    if (!c.contains(2))
      Alert('no_competing', Severity.info, tr('Aucun événement concurrent : l\'incidence cumulée est égale à 1 − Kaplan-Meier.', 'No competing event: the cumulative incidence equals 1 − Kaplan-Meier.')),
    for (final cv in cause)
      if (cv.events < 5) Alert('few_events', Severity.caution, tr('« ${cv.group} » : seulement ${cv.events} événement(s) « $causeLevel ».', '"${cv.group}": only ${cv.events} "$causeLevel" event(s).')),
  ];
  final overestimate = [
    for (var k = 0; k < levels.length; k++)
      if (cause[k].at(h, lastTime[levels[k]]!) != null) (levels[k], cause[k].at(h, lastTime[levels[k]]!)!.cif, naiveAt(naive[k]))
  ];
  final groupsTxt = levels.length > 1;
  return AnalysisResult(
    methodId: 'cumulative_incidence',
    methodName: tr('Risques concurrents : incidence cumulée de « $causeLevel »', 'Competing risks: cumulative incidence of "$causeLevel"'),
    inputs: {'n': t.length, 'dropped': dropped, 'groups': levels, 'horizon': h, 'level': level, 'cause': causeLevel, 'censoring': censorLevels.toList()..sort(), 'competing': others.toList()..sort()},
    formula: tr(
        'Aalen-Johansen : F₁(t) = Σ_{t_j ≤ t} Ŝ(t_j⁻)·d₁ⱼ/nⱼ, Ŝ = Kaplan-Meier toutes causes ; variance de Gray (1988), correction des ex aequo comme cuminc ; IC ponctuel F^exp(±z·√v/(F·log F)). '
            '1 − Kaplan-Meier « naïf » : événements concurrents comptés comme censures (surestime l\'incidence).${groupsTxt ? ' Comparaison des groupes : modèle de Fine-Gray (sHR, variance sandwich), test de Wald.' : ''}',
        'Aalen-Johansen: F₁(t) = Σ_{t_j ≤ t} Ŝ(t_j⁻)·d₁ⱼ/nⱼ, Ŝ = all-cause Kaplan-Meier; Gray (1988) variance, tie correction as in cuminc; pointwise CI F^exp(±z·√v/(F·log F)). '
            '"Naive" 1 − Kaplan-Meier: competing events counted as censoring (overestimates the incidence).${groupsTxt ? ' Group comparison: Fine-Gray model (sHR, sandwich variance), Wald test.' : ''}'),
    estimates: [
      for (var k = 0; k < levels.length; k++)
        if (cause[k].at(h, lastTime[levels[k]]!) case final st?)
          Estimate(tr('Incidence cumulée à ${fmt(h)}$u — ${levels[k]}', 'Cumulative incidence at ${fmt(h)}$u — ${levels[k]}'), st.cif, lower: st.lower, upper: st.upper, level: level),
      for (final s in shr) Estimate(tr('sHR ${s.$1} vs ${levels.first}', 'sHR ${s.$1} vs ${levels.first}'), s.$2, lower: s.$3, upper: s.$4, level: level, pValue: s.$5),
    ],
    statistics: {
      'n': t.length.toDouble(),
      'events': c.where((x) => x == 1).length.toDouble(),
      'competing': c.where((x) => x == 2).length.toDouble(),
      'censored': c.where((x) => x == 0).length.toDouble(),
      'horizon': h,
      for (final o in overestimate) 'cif_${o.$1}': o.$2,
      for (final o in overestimate) 'naive_${o.$1}': o.$3,
      'fg_wald': ?fgWald,
      'fg_wald_p': ?fgP,
    },
    checks: [
      Check('censoring', tr('Censure non informative', 'Non-informative censoring'), CheckStatus.notAssessed,
          tr('Les sujets censurés doivent avoir le même pronostic (pour les deux types d\'événement) que ceux qui restent suivis.', 'Censored subjects must have the same prognosis (for both event types) as those still followed.')),
      Check('competing_handled', tr('Événement concurrent pris en compte (et non censuré)', 'Competing event accounted for (not censored)'), c.contains(2) ? CheckStatus.ok : CheckStatus.notAssessed,
          overestimate.isEmpty
              ? ''
              : tr('À ${fmt(h)}$u : ${[for (final o in overestimate) '« ${o.$1} » ${fmt(o.$2 * 100)} % (1 − KM naïf : ${fmt(o.$3 * 100)} %)'].join(' ; ')}.',
                  'At ${fmt(h)}$u: ${[for (final o in overestimate) '"${o.$1}" ${fmt(o.$2 * 100)}% (naive 1 − KM: ${fmt(o.$3 * 100)}%)'].join('; ')}.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Résumé par groupe', 'Summary by group'), [
        groupName, 'n', causeLevel, otherLabel, tr('Censures', 'Censored'), tr('Incidence à ${fmt(h)}$u', 'Incidence at ${fmt(h)}$u'), tr('IC $pct %', '$pct% CI'), tr('1 − KM naïf', 'Naive 1 − KM'),
      ], [
        for (var k = 0; k < levels.length; k++)
          () {
            final st = cause[k].at(h, lastTime[levels[k]]!);
            return [
              levels[k], '${cause[k].n}', '${cause[k].events}', '${cause[k].competing}', '${cause[k].censored}',
              st == null ? '—' : fmt(st.cif), st == null ? '—' : '${fmt(st.lower)} – ${fmt(st.upper)}', fmt(naiveAt(naive[k])),
            ];
          }()
      ]),
      if (fg != null)
        ResultTable(tr('Comparaison des groupes (Fine-Gray)', 'Group comparison (Fine-Gray)'), [groupName, 'sHR', tr('IC $pct %', '$pct% CI'), 'p'], [
          [levels.first, '1', tr('référence', 'reference'), ''],
          for (final s in shr) [s.$1, fmt(s.$2), '${fmt(s.$3)} – ${fmt(s.$4)}', fmtP(s.$5)],
          [tr('Wald global', 'Global Wald'), 'χ² = ${fmt(fgWald)}', tr('ddl ${levels.length - 1}', 'df ${levels.length - 1}'), fgP == null ? '—' : fmtP(fgP)],
        ]),
      for (final cv in cause)
        ResultTable(tr('Incidence cumulée — ${cv.group}', 'Cumulative incidence — ${cv.group}'),
            [tr('Temps', 'Time'), tr('À risque', 'At risk'), causeLevel, tr('Incidence', 'Incidence'), tr('IC $pct %', '$pct% CI')], [
          for (final st in cv.steps.where((s) => s.events > 0)) [fmt(st.time), '${st.atRisk}', '${st.events}', fmt(st.cif), '${fmt(st.lower)} – ${fmt(st.upper)}']
        ]),
    ],
    figures: {
      'cumulativeIncidence': {
        'unit': timeUnit,
        'cause': causeLevel,
        'competing': otherLabel,
        'curves': [
          for (var k = 0; k < levels.length; k++)
            {
              'group': levels[k],
              'time': [for (final s in cause[k].steps) s.time],
              'cif': [for (final s in cause[k].steps) s.cif],
              'lower': [for (final s in cause[k].steps) s.lower],
              'upper': [for (final s in cause[k].steps) s.upper],
              'compTime': [for (final s in comp[k].steps) s.time],
              'compCif': [for (final s in comp[k].steps) s.cif],
              'naiveTime': [for (final s in naive[k].steps) s.time],
              'naive': [for (final s in naive[k].steps) 1 - s.surv],
              'last': lastTime[levels[k]],
            }
        ],
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Un événement concurrent (« $otherLabel ») empêche « $causeLevel » de survenir : l\'incidence cumulée d\'Aalen-Johansen estime la proportion de sujets qui connaissent réellement « $causeLevel », alors que 1 − Kaplan-Meier, qui traite l\'événement concurrent comme une censure, la surestime.',
          'A competing event ("$otherLabel") prevents "$causeLevel" from occurring: the Aalen-Johansen cumulative incidence estimates the proportion of subjects who actually experience "$causeLevel", whereas 1 − Kaplan-Meier, which treats the competing event as censoring, overestimates it.'),
      whatItMeans: [
        for (final o in overestimate)
          tr('« ${o.$1} » : ${fmt(o.$2 * 100)} % à ${fmt(h)}$u (1 − Kaplan-Meier naïf : ${fmt(o.$3 * 100)} %).', '"${o.$1}": ${fmt(o.$2 * 100)}% at ${fmt(h)}$u (naive 1 − Kaplan-Meier: ${fmt(o.$3 * 100)}%).'),
        for (final s in shr) tr('sHR ${s.$1} vs ${levels.first} = ${fmt(s.$2)} (IC ${fmt(s.$3)} à ${fmt(s.$4)}), ${fmtP(s.$5)}.', 'sHR ${s.$1} vs ${levels.first} = ${fmt(s.$2)} (CI ${fmt(s.$3)} to ${fmt(s.$4)}), ${fmtP(s.$5)}.'),
      ].join(' '),
      notJustified: tr(
          'Rapporter 1 − Kaplan-Meier comme une probabilité d\'événement en présence de décès ou d\'un autre événement concurrent ; additionner des incidences obtenues par Kaplan-Meier (le total peut dépasser 100 %) ; conclure sur la biologie de « $causeLevel » à partir de l\'incidence seule (elle dépend aussi de l\'événement concurrent).',
          'Reporting 1 − Kaplan-Meier as an event probability in the presence of death or another competing event; adding up incidences obtained by Kaplan-Meier (the total can exceed 100%); drawing conclusions on the biology of "$causeLevel" from the incidence alone (it also depends on the competing event).'),
    ),
  );
}
