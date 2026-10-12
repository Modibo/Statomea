/// Atelier de métaanalyse : issues binaires (OR, RR, DR) et continues (DM,
/// DMS de Hedges) ; effets fixes (inverse de la variance, Mantel-Haenszel)
/// et aléatoires (DerSimonian-Laird, REML, option Hartung-Knapp) ;
/// hétérogénéité (Q, I², τ², H²), intervalle de prédiction, sensibilité
/// « leave-one-out », sous-groupes, test d'Egger. Conventions de calcul
/// alignées sur `metafor` (Viechtbauer 2010) et vérifiées contre lui.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/special.dart';
import '../model/result.dart';
import '../regression/linear.dart';

enum EffectMeasure { or, rr, rd, md, smd, generic }

String measureLabel(EffectMeasure m) => switch (m) {
      EffectMeasure.or => 'Odds ratio',
      EffectMeasure.rr => tr('Risque relatif', 'Risk ratio'),
      EffectMeasure.rd => tr('Différence de risques', 'Risk difference'),
      EffectMeasure.md => tr('Différence de moyennes', 'Mean difference'),
      EffectMeasure.smd => tr('Différence de moyennes standardisée (g de Hedges)', "Standardized mean difference (Hedges' g)"),
      EffectMeasure.generic => tr('Effet générique (inverse de la variance)', 'Generic effect (inverse variance)'),
    };

bool isRatio(EffectMeasure m) => m == EffectMeasure.or || m == EffectMeasure.rr;

/// Statut d'une valeur extraite (exigence §6 : traçabilité).
enum Provenance { reported, recalculated, assumed }

String provenanceLabel(Provenance p) => switch (p) {
      Provenance.reported => tr("rapportée par l'article", 'reported by the article'),
      Provenance.recalculated => tr('recalculée', 'recalculated'),
      Provenance.assumed => tr('hypothèse', 'assumption'),
    };

class SourcedValue {
  final double? value;
  final Provenance provenance;
  final String source; // p. ex. « Tableau 2, p. 5 »
  final String note;
  const SourcedValue(this.value, {this.provenance = Provenance.reported, this.source = '', this.note = ''});

  Map<String, Object?> toJson() => {'value': value, 'provenance': provenance.name, 'source': source, 'note': note};
  factory SourcedValue.fromJson(Map<String, Object?> j) => SourcedValue((j['value'] as num?)?.toDouble(),
      provenance: Provenance.values.byName((j['provenance'] as String?) ?? 'reported'),
      source: (j['source'] as String?) ?? '',
      note: (j['note'] as String?) ?? '');
}

/// Jugement de compatibilité d'une étude avec la question de la revue.
enum Compat { yes, no, unclear }

class StudyCompatibility {
  final Compat population, comparator, outcome, followUp, measure;
  final String comment;
  const StudyCompatibility(
      {this.population = Compat.unclear,
      this.comparator = Compat.unclear,
      this.outcome = Compat.unclear,
      this.followUp = Compat.unclear,
      this.measure = Compat.unclear,
      this.comment = ''});

  List<Compat> get all => [population, comparator, outcome, followUp, measure];
  Map<String, Object?> toJson() => {
        'population': population.name,
        'comparator': comparator.name,
        'outcome': outcome.name,
        'followUp': followUp.name,
        'measure': measure.name,
        'comment': comment,
      };
  factory StudyCompatibility.fromJson(Map<String, Object?> j) {
    Compat c(String k) => Compat.values.byName((j[k] as String?) ?? 'unclear');
    return StudyCompatibility(
        population: c('population'),
        comparator: c('comparator'),
        outcome: c('outcome'),
        followUp: c('followUp'),
        measure: c('measure'),
        comment: (j['comment'] as String?) ?? '');
  }
}

/// Ligne du tableau d'extraction. Champs binaires : e1/n1 (intervention),
/// e2/n2 (contrôle). Continus : m1, sd1, n1, m2, sd2, n2. Générique : yi, sei
/// (échelle log pour un ratio).
class Study {
  final String id;
  final String label;
  final String subgroup;
  final Map<String, SourcedValue> values;
  final StudyCompatibility compatibility;
  final bool excluded;
  final String exclusionReason;

  const Study(this.id, this.label, this.values,
      {this.subgroup = '', this.compatibility = const StudyCompatibility(), this.excluded = false, this.exclusionReason = ''});

  double? v(String k) => values[k]?.value;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'subgroup': subgroup,
        'values': {for (final e in values.entries) e.key: e.value.toJson()},
        'compatibility': compatibility.toJson(),
        'excluded': excluded,
        'exclusionReason': exclusionReason,
      };

  factory Study.fromJson(Map<String, Object?> j) => Study(j['id'] as String, j['label'] as String,
      {for (final e in (j['values'] as Map).entries) e.key as String: SourcedValue.fromJson((e.value as Map).cast())},
      subgroup: (j['subgroup'] as String?) ?? '',
      compatibility: j['compatibility'] == null ? const StudyCompatibility() : StudyCompatibility.fromJson((j['compatibility'] as Map).cast()),
      excluded: (j['excluded'] as bool?) ?? false,
      exclusionReason: (j['exclusionReason'] as String?) ?? '');

  /// Raccourci : étude binaire à valeurs rapportées.
  factory Study.binary(String label, int e1, int n1, int e2, int n2, {String subgroup = '', String source = ''}) => Study(
      label,
      label,
      {
        'e1': SourcedValue(e1.toDouble(), source: source),
        'n1': SourcedValue(n1.toDouble(), source: source),
        'e2': SourcedValue(e2.toDouble(), source: source),
        'n2': SourcedValue(n2.toDouble(), source: source),
      },
      subgroup: subgroup);

  factory Study.continuous(String label, double m1, double sd1, int n1, double m2, double sd2, int n2,
          {String subgroup = '', String source = ''}) =>
      Study(label, label, {
        'm1': SourcedValue(m1, source: source),
        'sd1': SourcedValue(sd1, source: source),
        'n1': SourcedValue(n1.toDouble(), source: source),
        'm2': SourcedValue(m2, source: source),
        'sd2': SourcedValue(sd2, source: source),
        'n2': SourcedValue(n2.toDouble(), source: source),
      }, subgroup: subgroup);
}

/// Effet individuel calculé.
class StudyEffect {
  final Study study;
  final double yi, vi;
  final bool corrected; // correction de continuité appliquée
  StudyEffect(this.study, this.yi, this.vi, {this.corrected = false});
  double get sei => math.sqrt(vi);
}

/// Calcule l'effet d'une étude. Retourne null (avec raison) si incalculable.
({StudyEffect? effect, String? reason}) computeEffect(Study s, EffectMeasure m, {double add = 0.5}) {
  switch (m) {
    case EffectMeasure.or:
    case EffectMeasure.rr:
    case EffectMeasure.rd:
      final e1 = s.v('e1'), n1 = s.v('n1'), e2 = s.v('e2'), n2 = s.v('n2');
      if ([e1, n1, e2, n2].contains(null)) return (effect: null, reason: tr('effectifs incomplets', 'incomplete counts'));
      if (e1! > n1! || e2! > n2! || n1 <= 0 || n2 <= 0) return (effect: null, reason: tr('effectifs incohérents (événements > n)', 'inconsistent counts (events > n)'));
      var a = e1, b = n1 - e1, c = e2, d = n2 - e2;
      final zero = [a, b, c, d].contains(0.0);
      if (m != EffectMeasure.rd && a == 0 && c == 0) {
        return (effect: null, reason: tr('aucun événement dans les deux bras (étude « double zéro ») : non informative pour un OR/RR', 'no event in either arm ("double-zero" study): not informative for an OR/RR'));
      }
      if (m != EffectMeasure.rd && b == 0 && d == 0) {
        return (effect: null, reason: tr("tous les sujets ont l'événement dans les deux bras : non informative pour un OR/RR", 'all subjects have the event in both arms: not informative for an OR/RR'));
      }
      if (zero) {
        a += add;
        b += add;
        c += add;
        d += add;
      }
      switch (m) {
        case EffectMeasure.or:
          return (effect: StudyEffect(s, math.log(a * d / (b * c)), 1 / a + 1 / b + 1 / c + 1 / d, corrected: zero), reason: null);
        case EffectMeasure.rr:
          return (
            effect: StudyEffect(s, math.log((a / (a + b)) / (c / (c + d))), 1 / a - 1 / (a + b) + 1 / c - 1 / (c + d), corrected: zero),
            reason: null
          );
        default:
          final p1 = a / (a + b), p2 = c / (c + d);
          return (effect: StudyEffect(s, p1 - p2, p1 * (1 - p1) / (a + b) + p2 * (1 - p2) / (c + d), corrected: zero), reason: null);
      }
    case EffectMeasure.md:
    case EffectMeasure.smd:
      final m1 = s.v('m1'), sd1 = s.v('sd1'), n1 = s.v('n1'), m2 = s.v('m2'), sd2 = s.v('sd2'), n2 = s.v('n2');
      if ([m1, sd1, n1, m2, sd2, n2].contains(null)) return (effect: null, reason: tr('moyennes, ÉT ou effectifs manquants', 'missing means, SDs or counts'));
      if (sd1! <= 0 || sd2! <= 0 || n1! < 2 || n2! < 2) return (effect: null, reason: tr('ÉT ≤ 0 ou effectif < 2', 'SD ≤ 0 or count < 2'));
      if (m == EffectMeasure.md) {
        return (effect: StudyEffect(s, m1! - m2!, sd1 * sd1 / n1 + sd2 * sd2 / n2), reason: null);
      }
      final mi = n1 + n2 - 2;
      final sp = math.sqrt(((n1 - 1) * sd1 * sd1 + (n2 - 1) * sd2 * sd2) / mi);
      // Facteur de correction exact (Hedges 1981), comme metafor.
      final j = math.exp(lnGamma(mi / 2) - math.log(math.sqrt(mi / 2)) - lnGamma((mi - 1) / 2));
      final g = j * (m1! - m2!) / sp;
      return (effect: StudyEffect(s, g, 1 / n1 + 1 / n2 + g * g / (2 * (n1 + n2))), reason: null);
    case EffectMeasure.generic:
      final y = s.v('yi'), se = s.v('sei');
      if (y == null || se == null || se <= 0) return (effect: null, reason: tr('effet ou erreur standard manquant', 'missing effect or standard error'));
      return (effect: StudyEffect(s, y, se * se), reason: null);
  }
}

enum TauMethod { fixed, dl, reml }

class PooledResult {
  final double mu, se, lower, upper, z, p;
  final double tau2, q, qp, i2, h2;
  final double? piLower, piUpper; // intervalle de prédiction
  final List<double> weights; // % normalisés
  final int k;
  final bool knha;
  PooledResult(this.mu, this.se, this.lower, this.upper, this.z, this.p, this.tau2, this.q, this.qp, this.i2, this.h2,
      this.piLower, this.piUpper, this.weights, this.k, this.knha);
}

/// Agrégation par inverse de la variance (effets fixes si [method] = fixed).
PooledResult poolInverseVariance(List<double> y, List<double> v,
    {TauMethod method = TauMethod.reml, bool knha = false, double level = 0.95}) {
  final k = y.length;
  final w0 = [for (final x in v) 1 / x];
  final sw0 = w0.fold(0.0, (a, b) => a + b);
  var muF = 0.0;
  for (var i = 0; i < k; i++) {
    muF += w0[i] * y[i];
  }
  muF /= sw0;
  var q = 0.0;
  for (var i = 0; i < k; i++) {
    q += w0[i] * (y[i] - muF) * (y[i] - muF);
  }
  final sw2 = w0.fold(0.0, (a, b) => a + b * b);
  var tau2 = 0.0;
  if (method == TauMethod.dl && k > 1) {
    tau2 = math.max(0, (q - (k - 1)) / (sw0 - sw2 / sw0));
  } else if (method == TauMethod.reml && k > 1) {
    tau2 = _remlTau2(y, v);
  }
  final w = [for (final x in v) 1 / (x + tau2)];
  final sw = w.fold(0.0, (a, b) => a + b);
  var mu = 0.0;
  for (var i = 0; i < k; i++) {
    mu += w[i] * y[i];
  }
  mu /= sw;
  var se = math.sqrt(1 / sw);
  double crit, p, stat;
  if (knha && k > 1) {
    var s = 0.0;
    for (var i = 0; i < k; i++) {
      s += w[i] * (y[i] - mu) * (y[i] - mu);
    }
    se = math.sqrt(s / ((k - 1) * sw));
    crit = tQuantile(1 - (1 - level) / 2, k - 1.0);
    stat = mu / se;
    p = tTwoSidedP(stat, k - 1.0);
  } else {
    crit = normalQuantile(1 - (1 - level) / 2);
    stat = mu / se;
    p = normalTwoSidedP(stat);
  }
  // I² et H² selon metafor : variance « typique » intra-étude s².
  final s2 = (k - 1) * sw0 / (sw0 * sw0 - sw2);
  final i2 = k > 1 ? tau2 / (tau2 + s2) : 0.0;
  final h2 = k <= 1 ? 1.0 : (method == TauMethod.fixed ? q / (k - 1) : (tau2 + s2) / s2);
  double? piL, piU;
  if (method != TauMethod.fixed && k >= 3) {
    // Intervalle de prédiction : Higgins, Thompson & Spiegelhalter (2009), t(k−2).
    final tp = tQuantile(1 - (1 - level) / 2, k - 2.0);
    final sp = math.sqrt(tau2 + se * se);
    piL = mu - tp * sp;
    piU = mu + tp * sp;
  }
  return PooledResult(mu, se, mu - crit * se, mu + crit * se, stat, p, tau2, q, k > 1 ? chiSquareUpper(q, k - 1.0) : 1.0,
      method == TauMethod.fixed ? math.max(0, (q - (k - 1)) / q) : i2, h2, piL, piU, [for (final x in w) 100 * x / sw], k, knha);
}

/// Estimateur REML de τ² par itérations de Fisher (comme metafor, départ DL).
double _remlTau2(List<double> y, List<double> v) {
  final k = y.length;
  final w0 = [for (final x in v) 1 / x];
  final sw0 = w0.fold(0.0, (a, b) => a + b);
  var muF = 0.0;
  for (var i = 0; i < k; i++) {
    muF += w0[i] * y[i];
  }
  muF /= sw0;
  var q = 0.0;
  for (var i = 0; i < k; i++) {
    q += w0[i] * (y[i] - muF) * (y[i] - muF);
  }
  final sw2 = w0.fold(0.0, (a, b) => a + b * b);
  var tau2 = math.max(0.0, (q - (k - 1)) / (sw0 - sw2 / sw0));
  for (var it = 0; it < 1000; it++) {
    final w = [for (final x in v) 1 / (x + tau2)];
    final sw = w.fold(0.0, (a, b) => a + b);
    var mu = 0.0;
    for (var i = 0; i < k; i++) {
      mu += w[i] * y[i];
    }
    mu /= sw;
    // Matrice de projection P = W − W1(1ᵀW1)⁻¹1ᵀW ; dérivées de la log-vraisemblance restreinte.
    var trP = 0.0, yPPy = 0.0, trPP = 0.0;
    final sw2b = w.fold(0.0, (a, b) => a + b * b);
    final sw3 = w.fold(0.0, (a, b) => a + b * b * b);
    trP = sw - sw2b / sw;
    // Py = w(y − μ)
    final py = [for (var i = 0; i < k; i++) w[i] * (y[i] - mu)];
    yPPy = py.fold(0.0, (a, b) => a + b * b);
    // back(PP) = Σw² − 2Σw³/Σw + (Σw²)²/(Σw)²
    trPP = sw2b - 2 * sw3 / sw + sw2b * sw2b / (sw * sw);
    final adj = (yPPy - trP) / trPP;
    var next = tau2 + adj;
    var step = adj;
    while (next < 0) {
      step /= 2;
      next = tau2 + step;
    }
    if ((next - tau2).abs() < 1e-12) {
      tau2 = next;
      break;
    }
    tau2 = next;
  }
  return tau2;
}

/// Mantel-Haenszel (effets fixes) pour OR et RR, avec les variances de
/// Robins-Breslow-Greenland (OR) et Greenland-Robins (RR). Les études à
/// cellule nulle sont utilisées sans correction (sauf doubles zéros, exclus).
({double est, double se, double lower, double upper, double p}) mantelHaenszel(List<Study> studies, EffectMeasure m,
    {double level = 0.95}) {
  var r = 0.0, s = 0.0, pr = 0.0, ps = 0.0, qs = 0.0;
  var rr = 0.0, ss = 0.0, varNum = 0.0;
  for (final st in studies) {
    final a = st.v('e1')!, n1 = st.v('n1')!, c = st.v('e2')!, n2 = st.v('n2')!;
    final b = n1 - a, d = n2 - c, n = n1 + n2;
    if (a + c == 0 || b + d == 0) continue;
    if (m == EffectMeasure.or) {
      final ri = a * d / n, si = b * c / n;
      final pi = (a + d) / n, qi = (b + c) / n;
      r += ri;
      s += si;
      pr += pi * ri;
      ps += pi * si + qi * ri;
      qs += qi * si;
    } else {
      rr += a * n2 / n;
      ss += c * n1 / n;
      varNum += (n1 * n2 * (a + c) - a * c * n) / (n * n);
    }
  }
  double est, se;
  if (m == EffectMeasure.or) {
    est = math.log(r / s);
    se = math.sqrt(pr / (2 * r * r) + ps / (2 * r * s) + qs / (2 * s * s));
  } else {
    est = math.log(rr / ss);
    se = math.sqrt(varNum / (rr * ss));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  return (est: est, se: se, lower: est - z * se, upper: est + z * se, p: normalTwoSidedP(est / se));
}

/// Test d'Egger (régression de y/ES sur 1/ES ; ordonnée à l'origine).
({double intercept, double se, double p})? eggerTest(List<double> y, List<double> v) {
  if (y.length < 3) return null;
  final x = [for (final vi in v) [1.0, 1 / math.sqrt(vi)]];
  final yy = [for (var i = 0; i < y.length; i++) y[i] / math.sqrt(v[i])];
  final f = fitOls(x, yy);
  final se = math.sqrt(f.sigma2 * f.covUnscaled.get(0, 0));
  return (intercept: f.beta[0], se: se, p: tTwoSidedP(f.beta[0] / se, f.df.toDouble()));
}

class MetaOptions {
  final EffectMeasure measure;
  final TauMethod method;
  final bool knha;
  final bool mantelHaenszelFixed;
  final double level;
  final double continuityCorrection;
  const MetaOptions(
      {required this.measure,
      this.method = TauMethod.reml,
      this.knha = false,
      this.mantelHaenszelFixed = false,
      this.level = 0.95,
      this.continuityCorrection = 0.5});

  Map<String, Object?> toJson() => {
        'measure': measure.name,
        'method': method.name,
        'knha': knha,
        'mantelHaenszelFixed': mantelHaenszelFixed,
        'level': level,
        'continuityCorrection': continuityCorrection,
      };
}

String _methodLabel(MetaOptions o) => switch (o.method) {
      TauMethod.fixed => o.mantelHaenszelFixed ? tr('effet fixe (Mantel-Haenszel)', 'fixed effect (Mantel-Haenszel)') : tr('effet fixe (inverse de la variance)', 'fixed effect (inverse variance)'),
      TauMethod.dl => tr('effets aléatoires (DerSimonian-Laird)${o.knha ? ", IC de Hartung-Knapp" : ""}', 'random effects (DerSimonian-Laird)${o.knha ? ", Hartung-Knapp CI" : ""}'),
      TauMethod.reml => tr('effets aléatoires (REML)${o.knha ? ", IC de Hartung-Knapp" : ""}', 'random effects (REML)${o.knha ? ", Hartung-Knapp CI" : ""}'),
    };

/// Métaanalyse complète : effets individuels, agrégation, hétérogénéité,
/// forest plot, leave-one-out, sous-groupes, Egger, contrôles de compatibilité.
AnalysisResult metaAnalysis(List<Study> all, MetaOptions o) {
  final alerts = <Alert>[];
  final log = <String>[];
  final included = <StudyEffect>[];
  final excludedRows = <List<String>>[];
  for (final s in all) {
    if (s.excluded) {
      excludedRows.add([s.label, tr("exclue par l'utilisateur : ${s.exclusionReason}", 'excluded by the user: ${s.exclusionReason}')]);
      continue;
    }
    final r = computeEffect(s, o.measure, add: o.continuityCorrection);
    if (r.effect == null) {
      excludedRows.add([s.label, r.reason!]);
      log.add(tr('${s.label} non incluse : ${r.reason}.', '${s.label} not included: ${r.reason}.'));
    } else {
      included.add(r.effect!);
      if (r.effect!.corrected) log.add(tr('${s.label} : cellule nulle, ${fmt(o.continuityCorrection)} ajouté à chaque cellule.', '${s.label}: zero cell, ${fmt(o.continuityCorrection)} added to each cell.'));
    }
  }
  if (included.isEmpty) {
    throw StatInputError('no_study', tr('Aucune étude ne fournit les données nécessaires à la mesure « ${measureLabel(o.measure)} ».', 'No study provides the data needed for the measure "${measureLabel(o.measure)}".'));
  }
  final k = included.length;
  final y = [for (final e in included) e.yi];
  final v = [for (final e in included) e.vi];
  final pooled = poolInverseVariance(y, v, method: o.method, knha: o.knha, level: o.level);
  final fixed = poolInverseVariance(y, v, method: TauMethod.fixed, level: o.level);
  ({double est, double se, double lower, double upper, double p})? mh;
  if (o.mantelHaenszelFixed && (o.measure == EffectMeasure.or || o.measure == EffectMeasure.rr)) {
    mh = mantelHaenszel([for (final e in included) e.study], o.measure, level: o.level);
  }
  final ratio = isRatio(o.measure);
  double back(double x) => ratio ? math.exp(x) : x;
  final mainEst = mh?.est ?? pooled.mu;
  final mainLo = mh?.lower ?? pooled.lower;
  final mainHi = mh?.upper ?? pooled.upper;
  final mainP = mh?.p ?? pooled.p;

  // Compatibilité (grille remplie par l'utilisateur).
  final incompatible = [for (final e in included) if (e.study.compatibility.all.contains(Compat.no)) e.study.label];
  final unclear = [
    for (final e in included)
      if (!e.study.compatibility.all.contains(Compat.no) && e.study.compatibility.all.contains(Compat.unclear)) e.study.label
  ];
  final checks = <Check>[
    Check(
        'compatibility',
        tr('Études compatibles (population, comparateur, critère, suivi, mesure)', 'Compatible studies (population, comparator, outcome, follow-up, measure)'),
        incompatible.isNotEmpty
            ? CheckStatus.violated
            : unclear.isNotEmpty
                ? CheckStatus.notAssessed
                : CheckStatus.ok,
        incompatible.isNotEmpty
            ? tr('Jugées incompatibles : ${incompatible.join(", ")}.', 'Judged incompatible: ${incompatible.join(", ")}.')
            : unclear.isNotEmpty
                ? tr('Information insuffisante pour ${unclear.length} étude(s) : ${unclear.take(5).join(", ")}${unclear.length > 5 ? "…" : ""}.',
                    'Insufficient information for ${unclear.length} study(ies): ${unclear.take(5).join(", ")}${unclear.length > 5 ? "…" : ""}.')
                : tr('Grille complète, aucune incompatibilité déclarée.', 'Grid complete, no incompatibility declared.')),
  ];
  if (incompatible.isNotEmpty) {
    alerts.add(Alert('incompatible_studies', Severity.serious,
        tr('Des études jugées incompatibles avec la question sont combinées : ${incompatible.join(", ")}.', 'Studies judged incompatible with the question are combined: ${incompatible.join(", ")}.'),
        suggestion: tr('Les exclure, ou les analyser en sous-groupe / sensibilité, en le justifiant.', 'Exclude them, or analyse them as a subgroup / sensitivity analysis, with justification.')));
  }
  if (unclear.isNotEmpty) {
    alerts.add(Alert('compatibility_unclear', Severity.caution,
        tr('Compatibilité non renseignée pour ${unclear.length} étude(s) : la légitimité de la combinaison ne peut pas être vérifiée (information insuffisante).',
            'Compatibility not filled in for ${unclear.length} study(ies): the legitimacy of combining cannot be checked (insufficient information).')));
  }
  // Traçabilité des valeurs.
  final assumed = <String>[];
  for (final e in included) {
    for (final kv in e.study.values.entries) {
      if (kv.value.provenance == Provenance.assumed) assumed.add(tr('${e.study.label} : ${kv.key}', '${e.study.label}: ${kv.key}'));
    }
  }
  if (assumed.isNotEmpty) {
    alerts.add(Alert('assumed_values', Severity.caution,
        tr('${assumed.length} valeur(s) saisie(s) comme hypothèses (${assumed.take(4).join(" ; ")}${assumed.length > 4 ? "…" : ""}).',
            '${assumed.length} value(s) entered as assumptions (${assumed.take(4).join("; ")}${assumed.length > 4 ? "…" : ""}).'),
        suggestion: tr('Réaliser une analyse de sensibilité excluant ces études ou faisant varier ces hypothèses.', 'Perform a sensitivity analysis excluding these studies or varying these assumptions.')));
  }
  // Hétérogénéité
  if (k > 1 && pooled.i2 > 0.75) {
    alerts.add(Alert('high_heterogeneity', Severity.serious,
        tr("Hétérogénéité importante (I² = ${fmtPct(pooled.i2)}, τ² = ${fmt(pooled.tau2)}) : un effet moyen unique peut masquer des effets de sens ou d'ampleur différents.",
            'Considerable heterogeneity (I² = ${fmtPct(pooled.i2)}, τ² = ${fmt(pooled.tau2)}): a single mean effect may hide effects of different direction or size.'),
        suggestion: tr("Rechercher les sources (sous-groupes définis a priori), présenter l'intervalle de prédiction ; envisager de ne pas combiner.",
            'Look for sources (subgroups defined a priori), present the prediction interval; consider not pooling.')));
  } else if (k > 1 && pooled.i2 > 0.5) {
    alerts.add(Alert('moderate_heterogeneity', Severity.caution, tr('Hétérogénéité substantielle (I² = ${fmtPct(pooled.i2)}).', 'Substantial heterogeneity (I² = ${fmtPct(pooled.i2)}).')));
  }
  if (k < 5 && o.method != TauMethod.fixed) {
    alerts.add(Alert('few_studies', Severity.caution,
        tr("Seulement $k étude(s) : τ² est très imprécis ; l'IC des effets aléatoires sans correction de Hartung-Knapp peut être trop étroit.",
            'Only $k study(ies): τ² is very imprecise; the random-effects CI without the Hartung-Knapp correction may be too narrow.'),
        suggestion: o.knha ? null : tr("Activer l'option Hartung-Knapp.", 'Enable the Hartung-Knapp option.')));
  }
  if (o.method == TauMethod.fixed && k > 1 && pooled.qp < 0.1) {
    alerts.add(Alert('fixed_with_heterogeneity', Severity.serious,
        tr("Modèle à effet fixe malgré une hétérogénéité détectable : l'IC suppose un effet commun et sous-estime l'incertitude.",
            'Fixed-effect model despite detectable heterogeneity: the CI assumes a common effect and underestimates uncertainty.')));
  }
  final corrected = included.where((e) => e.corrected).length;
  if (corrected > 0 && o.measure != EffectMeasure.rd) {
    alerts.add(Alert('continuity_correction', Severity.caution,
        tr('$corrected étude(s) avec cellule nulle corrigée(s) par ${fmt(o.continuityCorrection)} : biais possible quand les événements sont rares.',
            '$corrected study(ies) with a zero cell corrected by ${fmt(o.continuityCorrection)}: possible bias when events are rare.'),
        suggestion: tr('Sensibilité : Mantel-Haenszel sans correction, ou méthodes exactes (hors V1).', 'Sensitivity: Mantel-Haenszel without correction, or exact methods (outside V1).')));
  }
  final egger = k >= 10 ? eggerTest(y, v) : null;
  final checksExtra = <Check>[
    Check('small_study', tr("Effets de petites études (test d'Egger, k ≥ 10)", "Small-study effects (Egger's test, k ≥ 10)"),
        egger == null ? CheckStatus.notAssessed : (egger.p < 0.1 ? CheckStatus.warning : CheckStatus.ok),
        egger == null
            ? tr('Moins de 10 études : test non interprétable.', 'Fewer than 10 studies: test not interpretable.')
            : tr("Ordonnée à l'origine = ${fmt(egger.intercept)} (ES ${fmt(egger.se)}), ${fmtP(egger.p)}. Une asymétrie n'est pas synonyme de biais de publication.",
                'Intercept = ${fmt(egger.intercept)} (SE ${fmt(egger.se)}), ${fmtP(egger.p)}. Asymmetry is not synonymous with publication bias.')),
  ];

  // Leave-one-out
  final loo = <List<String>>[];
  final looData = <Map<String, Object?>>[];
  if (k >= 3) {
    for (var i = 0; i < k; i++) {
      final yy = [for (var j = 0; j < k; j++) if (j != i) y[j]];
      final vv = [for (var j = 0; j < k; j++) if (j != i) v[j]];
      final r = poolInverseVariance(yy, vv, method: o.method, knha: o.knha, level: o.level);
      loo.add([included[i].study.label, fmt(back(r.mu)), '${fmt(back(r.lower))} – ${fmt(back(r.upper))}', fmtPct(r.i2)]);
      looData.add({'omitted': included[i].study.label, 'est': back(r.mu), 'lower': back(r.lower), 'upper': back(r.upper), 'i2': r.i2, 'tau2': r.tau2});
    }
  }
  // Sous-groupes
  final groups = <String, List<int>>{};
  for (var i = 0; i < k; i++) {
    final g = included[i].study.subgroup;
    if (g.isNotEmpty) groups.putIfAbsent(g, () => []).add(i);
  }
  final sub = <List<String>>[];
  final subData = <Map<String, Object?>>[];
  double? qBetween, qBetweenP;
  if (groups.length >= 2) {
    final gy = <double>[], gv = <double>[];
    for (final e in groups.entries) {
      final yy = [for (final i in e.value) y[i]], vv = [for (final i in e.value) v[i]];
      final r = poolInverseVariance(yy, vv, method: o.method, knha: false, level: o.level);
      gy.add(r.mu);
      gv.add(r.se * r.se);
      sub.add([e.key, '${e.value.length}', fmt(back(r.mu)), '${fmt(back(r.lower))} – ${fmt(back(r.upper))}', e.value.length > 1 ? fmtPct(r.i2) : '—']);
      subData.add({'group': e.key, 'k': e.value.length, 'est': back(r.mu), 'lower': back(r.lower), 'upper': back(r.upper), 'i2': r.i2});
    }
    final between = poolInverseVariance(gy, gv, method: TauMethod.fixed);
    qBetween = between.q;
    qBetweenP = chiSquareUpper(between.q, groups.length - 1.0);
    alerts.add(Alert('subgroup_caution', Severity.info,
        tr("Différence entre sous-groupes : Q = ${fmt(qBetween)}, ${fmtP(qBetweenP)}. Une analyse en sous-groupes est observationnelle (comparaison entre études) ; elle n'est crédible que si elle était prévue a priori, peu nombreuse et biologiquement plausible.",
            'Difference between subgroups: Q = ${fmt(qBetween)}, ${fmtP(qBetweenP)}. A subgroup analysis is observational (between-study comparison); it is credible only if planned a priori, few in number and biologically plausible.')));
  }

  final pct = (o.level * 100).round();
  final forest = {
    'measure': o.measure.name,
    'ratio': ratio,
    'studies': [
      for (var i = 0; i < k; i++)
        {
          'label': included[i].study.label,
          'subgroup': included[i].study.subgroup,
          'est': back(y[i]),
          'lower': back(y[i] - normalQuantile(1 - (1 - o.level) / 2) * math.sqrt(v[i])),
          'upper': back(y[i] + normalQuantile(1 - (1 - o.level) / 2) * math.sqrt(v[i])),
          'weight': pooled.weights[i],
        }
    ],
    'pooled': {'est': back(mainEst), 'lower': back(mainLo), 'upper': back(mainHi), 'label': _methodLabel(o)},
    if (pooled.piLower != null) 'prediction': {'lower': back(pooled.piLower!), 'upper': back(pooled.piUpper!)},
    'nullValue': ratio ? 1.0 : 0.0,
  };
  final pooledE = Estimate(tr('${measureLabel(o.measure)} combiné(e)', 'Pooled ${measureLabel(o.measure)}'), back(mainEst),
      lower: back(mainLo), upper: back(mainHi), level: o.level, pValue: mainP, se: mh?.se ?? pooled.se);
  final estimates = <Estimate>[
    pooledE,
    if (pooled.piLower != null)
      Estimate(tr('Intervalle de prédiction (effet dans une nouvelle étude)', 'Prediction interval (effect in a new study)'), back(mainEst),
          lower: back(pooled.piLower!), upper: back(pooled.piUpper!), level: o.level, intervalKind: 'IP'),
    Estimate(tr('τ² (variance entre études)', 'τ² (between-study variance)'), pooled.tau2),
    Estimate(tr('I² (proportion, 0 à 1)', 'I² (proportion, 0 to 1)'), pooled.i2),
  ];
  // Sur l'échelle de calcul (log pour un ratio), la valeur nulle vaut 0.
  final crossesNull = mainLo < 0 && mainHi > 0;
  final piCrosses = pooled.piLower != null && pooled.piLower! < 0 && pooled.piUpper! > 0;
  return AnalysisResult(
    methodId: 'meta_${o.measure.name}',
    methodName: tr('Métaanalyse — ${measureLabel(o.measure)}, ${_methodLabel(o)}', 'Meta-analysis — ${measureLabel(o.measure)}, ${_methodLabel(o)}'),
    inputs: {'options': o.toJson(), 'k_included': k, 'k_total': all.length, 'studies': [for (final s in all) s.toJson()]},
    formula: '${tr('Effets individuels : ', 'Individual effects: ')}${switch (o.measure) {
      EffectMeasure.or => 'ln OR, v = 1/a + 1/b + 1/c + 1/d',
      EffectMeasure.rr => 'ln RR, v = 1/a − 1/n1 + 1/c − 1/n2',
      EffectMeasure.rd => 'p1 − p2, v = p1q1/n1 + p2q2/n2',
      EffectMeasure.md => 'm1 − m2, v = s1²/n1 + s2²/n2',
      EffectMeasure.smd => tr('g = J·(m1 − m2)/s_poolée, J exact, v = 1/n1 + 1/n2 + g²/(2(n1+n2))', 'g = J·(m1 − m2)/s_pooled, exact J, v = 1/n1 + 1/n2 + g²/(2(n1+n2))'),
      EffectMeasure.generic => tr('effets et ES fournis', 'effects and SEs supplied'),
    }}. ${tr('Agrégation : μ̂ = Σw_i y_i / Σw_i, w_i = 1/(v_i + τ²) ; τ² ${o.method == TauMethod.dl ? "de DerSimonian-Laird" : o.method == TauMethod.reml ? "par REML (scores de Fisher)" : "= 0"} ; Q = Σ(1/v_i)(y_i − μ̂_fixe)² ; I² = τ²/(τ² + s²) ; IP = μ̂ ± t(k−2)·√(τ² + ES²).',
        'Pooling: μ̂ = Σw_i y_i / Σw_i, w_i = 1/(v_i + τ²); τ² ${o.method == TauMethod.dl ? "by DerSimonian-Laird" : o.method == TauMethod.reml ? "by REML (Fisher scoring)" : "= 0"}; Q = Σ(1/v_i)(y_i − μ̂_fixed)²; I² = τ²/(τ² + s²); PI = μ̂ ± t(k−2)·√(τ² + SE²).')}',
    estimates: estimates,
    statistics: {
      'k': k.toDouble(),
      'mu': pooled.mu,
      'se': pooled.se,
      'z': pooled.z,
      'p': mainP,
      'tau2': pooled.tau2,
      'tau': math.sqrt(pooled.tau2),
      'Q': pooled.q,
      'Q_p': pooled.qp,
      'I2': pooled.i2,
      'H2': pooled.h2,
      'fixed_mu': fixed.mu,
      'fixed_se': fixed.se,
      if (mh != null) 'mh_est': mh.est,
      if (mh != null) 'mh_se': mh.se,
      if (pooled.piLower != null) 'pi_lower': pooled.piLower!,
      if (pooled.piUpper != null) 'pi_upper': pooled.piUpper!,
      if (egger != null) 'egger_intercept': egger.intercept,
      if (egger != null) 'egger_p': egger.p,
      'Q_between': ?qBetween,
      'Q_between_p': ?qBetweenP,
    },
    checks: [...checks, ...checksExtra],
    alerts: alerts,
    tables: [
      ResultTable(tr('Études incluses', 'Included studies'), [tr('Étude', 'Study'), if (groups.isNotEmpty) tr('Sous-groupe', 'Subgroup'), measureLabel(o.measure), tr('IC $pct %', '$pct% CI'), tr('Poids', 'Weight')], [
        for (final s in forest['studies'] as List)
          [
            (s as Map)['label'] as String,
            if (groups.isNotEmpty) s['subgroup'] as String,
            fmt(s['est'] as double),
            '${fmt(s['lower'] as double)} – ${fmt(s['upper'] as double)}',
            fmtPct((s['weight'] as double) / 100),
          ],
        [tr('Combiné', 'Pooled'), if (groups.isNotEmpty) '', fmt(back(mainEst)), '${fmt(back(mainLo))} – ${fmt(back(mainHi))}', tr('100 %', '100%')],
      ]),
      if (excludedRows.isNotEmpty) ResultTable(tr('Études non incluses dans le calcul', 'Studies not included in the calculation'), [tr('Étude', 'Study'), tr('Raison', 'Reason')], excludedRows),
      ResultTable(tr('Hétérogénéité', 'Heterogeneity'), ['Q', tr('ddl', 'df'), 'p', 'I²', 'τ²', 'H²'],
          [[fmt(pooled.q), '${k - 1}', fmtP(pooled.qp), fmtPct(pooled.i2), fmt(pooled.tau2), fmt(pooled.h2)]]),
      if (loo.isNotEmpty) ResultTable(tr("Sensibilité : retrait d'une étude à la fois", 'Sensitivity: leaving one study out at a time'), [tr('Étude retirée', 'Study omitted'), tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), 'I²'], loo),
      if (sub.isNotEmpty) ResultTable(tr('Sous-groupes', 'Subgroups'), [tr('Sous-groupe', 'Subgroup'), 'k', tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), 'I²'], sub),
    ],
    figures: {'forest': forest, if (looData.isNotEmpty) 'leaveOneOut': looData, if (subData.isNotEmpty) 'subgroups': subData},
    log: [...log, tr('Modèle : ${_methodLabel(o)} ; k = $k.', 'Model: ${_methodLabel(o)}; k = $k.')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Combiner des études jugées suffisamment semblables pour répondre à la même question. ${o.method == TauMethod.fixed ? "L'effet fixe suppose un effet unique commun à toutes les études." : "Les effets aléatoires admettent que l'effet vrai varie d'une étude à l'autre et estiment sa moyenne."}',
          'Combining studies judged similar enough to answer the same question. ${o.method == TauMethod.fixed ? "The fixed effect assumes a single effect common to all studies." : "Random effects allow the true effect to vary from one study to another and estimate its mean."}'),
      whatItMeans: tr(
          '${pooledE.label} = ${fmtCi(pooledE)}, ${fmtP(mainP)} (k = $k). ${crossesNull ? "L'IC inclut la valeur nulle : absence de preuve d'un effet moyen, pas preuve d'absence. " : ""}${pooled.piLower != null ? "Dans une nouvelle étude comparable, l'effet vrai serait attendu entre ${fmt(back(pooled.piLower!))} et ${fmt(back(pooled.piUpper!))} (intervalle de prédiction)${piCrosses ? ", y compris des valeurs de sens opposé" : ""}." : ""}',
          '${pooledE.label} = ${fmtCi(pooledE)}, ${fmtP(mainP)} (k = $k). ${crossesNull ? "The CI includes the null value: absence of evidence of a mean effect, not evidence of absence. " : ""}${pooled.piLower != null ? "In a new comparable study, the true effect would be expected between ${fmt(back(pooled.piLower!))} and ${fmt(back(pooled.piUpper!))} (prediction interval)${piCrosses ? ", including values in the opposite direction" : ""}." : ""}'),
      notJustified: tr(
          "Conclure que l'effet est le même partout quand I² est élevé ; confondre l'IC de la moyenne avec la dispersion des effets (intervalle de prédiction) ; juger la qualité des preuves à partir de la seule conformité PRISMA ; tirer des conclusions causales de sous-groupes post hoc.",
          'Concluding the effect is the same everywhere when I² is high; confusing the CI of the mean with the spread of effects (prediction interval); judging the quality of evidence from PRISMA compliance alone; drawing causal conclusions from post hoc subgroups.'),
    ),
  );
}
