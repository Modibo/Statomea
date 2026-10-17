/// Calibration d'un modèle de risque à partir des probabilités prédites et des issues observées :
///  - test de Hosmer-Lemeshow (déciles de risque prédit, ResourceSelection::hoslem.test) ;
///  - test z de Spiegelhalter ; score de Brier ; intercept et pente de recalibration logistique ; calibration « dans
///    l'ensemble » (logit prédit en offset) ;
///  - courbe de calibration lissée (lowess sans itération de robustesse, comme rms::val.prob) et écarts moyen, 90e
///    centile et maximal entre risque prédit et risque lissé (Eavg, E90, Emax).
/// Validé contre validation/r/52_calibration.R (ResourceSelection 0.3.6, rms 6.7, stats::lowess).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/glm.dart';
import 'performance.dart';

/// Quantile de type 7 calculé comme R : (1 − h)·x₍ₗₒ₎ + h·x₍ₕᵢ₎.
double _q7(List<double> sorted, double p) {
  final index = (sorted.length - 1) * p;
  final lo = index.floor(), hi = index.ceil();
  final h = index - lo;
  return h == 0 || sorted[hi] == sorted[lo] ? sorted[lo] : (1 - h) * sorted[lo] + h * sorted[hi];
}

/// Lissage lowess de Cleveland (stats::lowess, iter = 0, f = 2/3, delta = 1 % de l'étendue) : valeurs lissées aux x
/// triés. [x] doit être trié par ordre croissant.
List<double> lowessFit(List<double> x, List<double> y, {double f = 2 / 3, double? delta}) {
  final n = x.length;
  if (n < 2) return [...y];
  final range = x.last - x.first;
  final dl = delta ?? 0.01 * range;
  final ns = math.max(2, math.min(n, (f * n + 1e-7).floor()));
  final ys = List<double>.filled(n, 0);
  final w = List<double>.filled(n, 0);
  // Ajustement local en xs avec les points nleft..nright (indices 0-based) ; null si tous les poids sont nuls.
  double? lowest(double xs, int nleft, int nright) {
    final h = math.max(xs - x[nleft], x[nright] - xs);
    final h9 = 0.999 * h, h1 = 0.001 * h;
    var a = 0.0;
    var j = nleft;
    while (j < n) {
      w[j] = 0;
      final r = (x[j] - xs).abs();
      if (r <= h9) {
        if (r <= h1) {
          w[j] = 1;
        } else {
          final u = r / h;
          final c = 1 - u * u * u;
          w[j] = c * c * c;
        }
        a += w[j];
      } else if (x[j] > xs) {
        break;
      }
      j++;
    }
    final nrt = j - 1;
    if (a <= 0) return null;
    for (var k = nleft; k <= nrt; k++) {
      w[k] /= a;
    }
    if (h > 0) {
      var m = 0.0;
      for (var k = nleft; k <= nrt; k++) {
        m += w[k] * x[k];
      }
      var b = xs - m, c = 0.0;
      for (var k = nleft; k <= nrt; k++) {
        c += w[k] * (x[k] - m) * (x[k] - m);
      }
      if (math.sqrt(c) > 0.001 * range) {
        b /= c;
        for (var k = nleft; k <= nrt; k++) {
          w[k] *= b * (x[k] - m) + 1;
        }
      }
    }
    var out = 0.0;
    for (var k = nleft; k <= nrt; k++) {
      out += w[k] * y[k];
    }
    return out;
  }

  var nleft = 0, nright = ns - 1, last = -1, i = 0;
  for (;;) {
    if (nright < n - 1) {
      final d1 = x[i] - x[nleft], d2 = x[nright + 1] - x[i];
      if (d1 > d2) {
        nleft++;
        nright++;
        continue;
      }
    }
    ys[i] = lowest(x[i], nleft, nright) ?? y[i];
    if (last < i - 1) {
      final denom = x[i] - x[last];
      for (var j = last + 1; j < i; j++) {
        final alpha = (x[j] - x[last]) / denom;
        ys[j] = alpha * ys[i] + (1 - alpha) * ys[last];
      }
    }
    last = i;
    final cut = x[last] + dl;
    for (i = last + 1; i < n; i++) {
      if (x[i] > cut) break;
      if (x[i] == x[last]) {
        ys[i] = ys[last];
        last = i;
      }
    }
    i = math.max(last + 1, i - 1);
    if (last >= n - 1) break;
  }
  return ys;
}

/// Hosmer-Lemeshow : groupes par quantiles uniques du risque prédit (intervalles fermés à droite, premier fermé des
/// deux côtés). Renvoie χ², ddl = G − 2, p et le détail par groupe.
({double chi2, int df, double p, List<({double lo, double hi, int n, double obs, double exp})> groups}) hosmerLemeshow(List<double> p, List<double> y, {int g = 10}) {
  final sorted = [...p]..sort();
  final breaks = <double>[];
  for (var k = 0; k <= g; k++) {
    final b = _q7(sorted, k * (1 / g));
    if (breaks.isEmpty || breaks.last != b) breaks.add(b);
  }
  final m = breaks.length - 1;
  if (m < 2) throw StatInputError('hl_groups', tr('Risques prédits trop peu variés pour former des groupes.', 'Predicted risks too little varied to form groups.'));
  final n = List<int>.filled(m, 0);
  final o = List<double>.filled(m, 0), e = List<double>.filled(m, 0);
  for (var i = 0; i < p.length; i++) {
    var k = 0;
    while (k < m - 1 && p[i] > breaks[k + 1]) {
      k++;
    }
    n[k]++;
    o[k] += y[i];
    e[k] += p[i];
  }
  var chi2 = 0.0, groups = 0;
  for (var k = 0; k < m; k++) {
    if (n[k] == 0) continue;
    groups++;
    chi2 += (o[k] - e[k]) * (o[k] - e[k]) / e[k] + ((n[k] - o[k]) - (n[k] - e[k])) * ((n[k] - o[k]) - (n[k] - e[k])) / (n[k] - e[k]);
  }
  final df = groups - 2;
  return (chi2: chi2, df: df, p: df > 0 ? chiSquareUpper(chi2, df.toDouble()) : double.nan, groups: [for (var k = 0; k < m; k++) (lo: breaks[k], hi: breaks[k + 1], n: n[k], obs: o[k], exp: e[k])]);
}

/// Test z de Spiegelhalter (calibration globale des probabilités individuelles).
({double z, double p}) spiegelhalter(List<double> p, List<double> y) {
  var num = 0.0, den = 0.0;
  for (var i = 0; i < p.length; i++) {
    num += (y[i] - p[i]) * (1 - 2 * p[i]);
    den += (1 - 2 * p[i]) * (1 - 2 * p[i]) * p[i] * (1 - p[i]);
  }
  final z = num / math.sqrt(den);
  return (z: z, p: normalTwoSidedP(z));
}

/// Évaluation de la calibration de probabilités prédites [pRaw] pour une issue binaire [yRaw] (1 = événement).
AnalysisResult calibrationAssessment(List<double?> pRaw, List<double?> yRaw, {int groups = 10, double level = 0.95, String? predictedName}) {
  predictedName ??= tr('Risque prédit', 'Predicted risk');
  final p = <double>[], y = <double>[];
  var dropped = 0;
  for (var i = 0; i < math.min(pRaw.length, yRaw.length); i++) {
    final a = pRaw[i], b = yRaw[i];
    if (a == null || b == null || !a.isFinite) {
      dropped++;
      continue;
    }
    if (a <= 0 || a >= 1) {
      throw StatInputError('prob_range', tr('Les probabilités prédites doivent être strictement entre 0 et 1 (valeur ${fmt(a)}, ligne ${i + 1}).', 'Predicted probabilities must be strictly between 0 and 1 (value ${fmt(a)}, row ${i + 1}).'));
    }
    if (b != 0 && b != 1) throw StatInputError('outcome_binary', tr('L\'issue doit être codée 0/1.', 'The outcome must be coded 0/1.'));
    p.add(a);
    y.add(b);
  }
  final n = p.length;
  final events = y.where((v) => v == 1).length;
  if (n < 20 || events == 0 || events == n) {
    throw StatInputError('n_too_small', tr('Au moins 20 observations comprenant des événements et des non-événements sont requises.', 'At least 20 observations including events and non-events are required.'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final pct = (level * 100).round();
  final hl = hosmerLemeshow(p, y, g: groups);
  final sp = spiegelhalter(p, y);
  final brier = brierScore(p, y);
  final lp = [for (final v in p) math.log(v / (1 - v))];
  final recal = fitLogistic([for (final v in lp) [1.0, v]], y);
  final cal = calibrationSlopeIntercept(p, y);
  // Lissage (ordre stable des ex aequo, comme order() de R) puis écarts |p − lissé(p)|.
  final idx = List<int>.generate(n, (i) => i)..sort((a, b) {
      final c = p[a].compareTo(p[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  final xs = [for (final i in idx) p[i]], yv = [for (final i in idx) y[i]];
  final sm = lowessFit(xs, yv);
  final er = [for (var k = 0; k < n; k++) (xs[k] - sm[k]).abs()];
  final eavg = er.fold(0.0, (a, b) => a + b) / n;
  final erS = [...er]..sort();
  final e90 = _q7(erS, 0.9), emax = erS.last;
  final prev = events / n, meanP = p.fold(0.0, (a, b) => a + b) / n;
  final slopeLo = cal.slope - z * cal.slopeSe, slopeHi = cal.slope + z * cal.slopeSe;
  final citlLo = cal.intercept - z * cal.interceptSe, citlHi = cal.intercept + z * cal.interceptSe;
  final alerts = <Alert>[];
  if (n > 1000) {
    alerts.add(Alert('hl_large_n', Severity.caution,
        tr('Avec $n observations, le test de Hosmer-Lemeshow détecte des écarts cliniquement négligeables : juger sur la courbe, la pente et l\'intercept.',
            'With $n observations, the Hosmer-Lemeshow test detects clinically negligible departures: judge from the curve, slope and intercept.')));
  }
  if (events < 100 || n - events < 100) {
    alerts.add(Alert('calibration_precision', Severity.caution,
        tr('${math.min(events, n - events)} observations dans la classe la plus rare : la calibration est estimée avec imprécision (viser ≥ 100 événements et ≥ 100 non-événements).',
            '${math.min(events, n - events)} observations in the rarer class: calibration is estimated imprecisely (aim for ≥ 100 events and ≥ 100 non-events).')));
  }
  final slopeOk = slopeLo <= 1 && slopeHi >= 1, citlOk = citlLo <= 0 && citlHi >= 0;
  final smoothPts = <Map<String, double>>[];
  for (var k = 0; k < n; k += math.max(1, n ~/ 200)) {
    smoothPts.add({'p': xs[k], 'smooth': sm[k]});
  }
  smoothPts.add({'p': xs.last, 'smooth': sm.last});
  return AnalysisResult(
    methodId: 'calibration',
    methodName: tr('Calibration d\'un modèle de risque (Hosmer-Lemeshow, courbe lissée)', 'Calibration of a risk model (Hosmer-Lemeshow, smoothed curve)'),
    inputs: {'n': n, 'dropped': dropped, 'groups': groups, 'level': level, 'predicted': predictedName},
    formula: tr(
        'Hosmer-Lemeshow : G groupes par quantiles du risque prédit, χ² = Σ_g [(O₁ − E₁)²/E₁ + (O₀ − E₀)²/E₀], ddl = G − 2. Spiegelhalter : z = Σ(y − p)(1 − 2p)/√Σ(1 − 2p)²p(1 − p). Recalibration : logit P(Y = 1) = a + b·logit(p̂) ; dans l\'ensemble : a avec b = 1. Brier = moyenne (p̂ − y)². Courbe lissée : lowess (f = 2/3) ; Eavg, E90, Emax = moyenne, 90e centile et maximum de |p̂ − lissé(p̂)|.',
        'Hosmer-Lemeshow: G groups by quantiles of predicted risk, χ² = Σ_g [(O₁ − E₁)²/E₁ + (O₀ − E₀)²/E₀], df = G − 2. Spiegelhalter: z = Σ(y − p)(1 − 2p)/√Σ(1 − 2p)²p(1 − p). Recalibration: logit P(Y = 1) = a + b·logit(p̂); in the large: a with b = 1. Brier = mean (p̂ − y)². Smoothed curve: lowess (f = 2/3); Eavg, E90, Emax = mean, 90th percentile and maximum of |p̂ − smoothed(p̂)|.'),
    estimates: [
      Estimate(tr('Pente de calibration', 'Calibration slope'), cal.slope, lower: slopeLo, upper: slopeHi, se: cal.slopeSe, level: level),
      Estimate(tr('Calibration dans l\'ensemble (intercept)', 'Calibration in the large (intercept)'), cal.intercept, lower: citlLo, upper: citlHi, se: cal.interceptSe, level: level),
      Estimate(tr('Rapport observé / attendu', 'Observed / expected ratio'), prev / meanP),
      Estimate('Brier', brier),
    ],
    statistics: {
      'n': n.toDouble(),
      'events': events.toDouble(),
      'hl_chi2': hl.chi2,
      'hl_df': hl.df.toDouble(),
      'hl_p': hl.p,
      'spiegelhalter_z': sp.z,
      'spiegelhalter_p': sp.p,
      'brier': brier,
      'recal_intercept': recal.beta[0],
      'recal_slope': recal.beta[1],
      'citl': cal.intercept,
      'eavg': eavg,
      'e90': e90,
      'emax': emax,
      'oe_ratio': prev / meanP,
    },
    checks: [
      Check('calibration_slope', tr('Pente de calibration compatible avec 1', 'Calibration slope compatible with 1'), slopeOk ? CheckStatus.ok : CheckStatus.warning,
          tr('Pente = ${fmt(cal.slope)} (IC ${fmt(slopeLo)} à ${fmt(slopeHi)}) ; < 1 : prédictions trop extrêmes (surajustement) ; > 1 : trop resserrées.',
              'Slope = ${fmt(cal.slope)} (CI ${fmt(slopeLo)} to ${fmt(slopeHi)}); < 1: predictions too extreme (overfitting); > 1: too narrow.')),
      Check('calibration_in_the_large', tr('Risque moyen correctement prédit', 'Mean risk correctly predicted'), citlOk ? CheckStatus.ok : CheckStatus.warning,
          tr('Intercept = ${fmt(cal.intercept)} (IC ${fmt(citlLo)} à ${fmt(citlHi)}) ; observé ${fmtPct(prev)} contre prédit ${fmtPct(meanP)}.',
              'Intercept = ${fmt(cal.intercept)} (CI ${fmt(citlLo)} to ${fmt(citlHi)}); observed ${fmtPct(prev)} vs predicted ${fmtPct(meanP)}.')),
      Check('hosmer_lemeshow', tr('Test de Hosmer-Lemeshow', 'Hosmer-Lemeshow test'), hl.p < 0.05 ? CheckStatus.warning : CheckStatus.ok,
          tr('χ² = ${fmt(hl.chi2)}, ${hl.df} ddl, ${fmtP(hl.p)} ; un test non significatif ne prouve pas la calibration (faible puissance, groupes arbitraires).',
              'χ² = ${fmt(hl.chi2)}, ${hl.df} df, ${fmtP(hl.p)}; a non-significant test does not prove calibration (low power, arbitrary groups).')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Hosmer-Lemeshow par groupe de risque prédit', 'Hosmer-Lemeshow by predicted-risk group'),
          [tr('Groupe', 'Group'), tr('Risque prédit', 'Predicted risk'), 'n', tr('Événements observés', 'Observed events'), tr('Événements attendus', 'Expected events')], [
        for (var k = 0; k < hl.groups.length; k++)
          if (hl.groups[k].n > 0) ['${k + 1}', '${fmt(hl.groups[k].lo, digits: 3)} – ${fmt(hl.groups[k].hi, digits: 3)}', '${hl.groups[k].n}', fmt(hl.groups[k].obs), fmt(hl.groups[k].exp)]
      ]),
      ResultTable(tr('Indicateurs de calibration', 'Calibration measures'), [tr('Indicateur', 'Measure'), tr('Valeur', 'Value'), tr('IC $pct %', '$pct% CI')], [
        [tr('Pente de calibration', 'Calibration slope'), fmt(cal.slope), '${fmt(slopeLo)} – ${fmt(slopeHi)}'],
        [tr('Calibration dans l\'ensemble', 'Calibration in the large'), fmt(cal.intercept), '${fmt(citlLo)} – ${fmt(citlHi)}'],
        [tr('Spiegelhalter z', 'Spiegelhalter z'), '${fmt(sp.z)} (${fmtP(sp.p)})', '—'],
        ['Brier', fmt(brier, digits: 4), '—'],
        ['Eavg / E90 / Emax', '${fmt(eavg, digits: 3)} / ${fmt(e90, digits: 3)} / ${fmt(emax, digits: 3)}', '—'],
      ]),
    ],
    figures: {
      'calibration': calibrationGroups(p, y, groups: groups),
      'calibrationSmooth': smoothPts,
    },
    interpretation: Interpretation(
      whyThisMethod: tr('Un modèle de risque doit être bien calibré (risques prédits proches des fréquences observées), pas seulement discriminant ; la calibration se juge sur la courbe, la pente et l\'intercept, le test de Hosmer-Lemeshow n\'étant qu\'un complément.',
          'A risk model must be well calibrated (predicted risks close to observed frequencies), not just discriminating; calibration is judged from the curve, slope and intercept, the Hosmer-Lemeshow test being only a complement.'),
      whatItMeans: tr(
          'Pente ${fmt(cal.slope)} (IC ${fmt(slopeLo)} à ${fmt(slopeHi)}), intercept ${fmt(cal.intercept)} ; écart moyen entre risque prédit et risque lissé ${fmtPct(eavg)} (maximum ${fmtPct(emax)}). Hosmer-Lemeshow ${fmtP(hl.p)}.',
          'Slope ${fmt(cal.slope)} (CI ${fmt(slopeLo)} to ${fmt(slopeHi)}), intercept ${fmt(cal.intercept)}; mean difference between predicted and smoothed risk ${fmtPct(eavg)} (maximum ${fmtPct(emax)}). Hosmer-Lemeshow ${fmtP(hl.p)}.'),
      notJustified: tr('Conclure à une bonne calibration sur un test de Hosmer-Lemeshow non significatif ; juger la calibration sur les données de développement seulement (optimiste) ; comparer des modèles par le seul p du test.',
          'Concluding good calibration from a non-significant Hosmer-Lemeshow test; judging calibration on development data only (optimistic); comparing models by the test p-value alone.'),
    ),
  );
}
