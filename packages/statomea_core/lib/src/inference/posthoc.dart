/// Comparaisons deux à deux après une analyse globale à k groupes :
///  - Tukey HSD (ANOVA classique, variances égales) ;
///  - Games-Howell (variances inégales, après l'ANOVA de Welch) ;
///  - Dunn avec correction de Holm (après Kruskal-Wallis).
/// La loi de l'étendue studentisée suit l'algorithme de Copenhaver et
/// Holland (1988), celui de `ptukey` dans R.
library;

import 'dart:math' as math;

import '../descriptive/descriptive.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/special.dart';
import '../model/result.dart';

const _xleg = [
  0.981560634246719250690549090149,
  0.904117256370474856678465866119,
  0.769902674194304687036893833213,
  0.587317954286617447296702418941,
  0.367831498998180193752691536644,
  0.125233408511468915472441369464,
];
const _aleg = [
  0.047175336386511827194615961485,
  0.106939325995318430960254718194,
  0.160078328543346226334652529543,
  0.203167426723065921749064455810,
  0.233492536538354808760849898925,
  0.249147045813402785000562436043,
];
const _xlegq = [
  0.989400934991649932596154173450,
  0.944575023073232576077988415535,
  0.865631202387831743880467897712,
  0.755404408355003033895101194847,
  0.617876244402643748446671764049,
  0.458016777657227386342419442984,
  0.281603550779258913230460501460,
  0.950125098376374401853193354250e-1,
];
const _alegq = [
  0.271524594117540948517805724560e-1,
  0.622535239386478928628438369944e-1,
  0.951585116824927848099251076022e-1,
  0.124628971255533872052476282192,
  0.149595988816576732081501730547,
  0.169156519395002538189312079030,
  0.182603415044923588866763667969,
  0.189450610455068496285396723208,
];

/// P(étendue de cc normales ≤ w), ddl infinis (Hartley).
double _wprob(double w, double cc) {
  const bb = 8.0, wlar = 3.0, c1 = -30.0, c2 = -50.0, c3 = 60.0;
  final qsqz = w * 0.5;
  if (qsqz >= bb) return 1.0;
  var prW = 2 * normalCdf(qsqz) - 1;
  prW = prW >= math.exp(c2 / cc) ? math.pow(prW, cc).toDouble() : 0.0;
  final wincr = w > wlar ? 2 : 3;
  var blb = qsqz;
  final binc = (bb - qsqz) / wincr;
  var bub = blb + binc;
  var einsum = 0.0;
  final cc1 = cc - 1;
  for (var wi = 1; wi <= wincr; wi++) {
    var elsum = 0.0;
    final a = 0.5 * (bub + blb), b = 0.5 * (bub - blb);
    for (var jj = 1; jj <= 12; jj++) {
      final int j;
      final double xx;
      if (6 < jj) {
        j = 12 - jj + 1;
        xx = _xleg[j - 1];
      } else {
        j = jj;
        xx = -_xleg[j - 1];
      }
      final ac = a + b * xx;
      final qexpo = ac * ac;
      if (qexpo > c3) break;
      final pplus = 2 * normalCdf(ac), pminus = 2 * normalCdf(ac - w);
      var rinsum = pplus * 0.5 - pminus * 0.5;
      if (rinsum >= math.exp(c1 / cc1)) {
        rinsum = _aleg[j - 1] * math.exp(-0.5 * qexpo) * math.pow(rinsum, cc1);
        elsum += rinsum;
      }
    }
    elsum *= 2.0 * b * cc / math.sqrt(2 * math.pi);
    einsum += elsum;
    blb = bub;
    bub += binc;
  }
  prW += einsum;
  if (prW <= math.exp(c1)) return 0.0;
  return prW >= 1 ? 1.0 : prW;
}

/// P(Q ≤ q) pour l'étendue studentisée de [k] moyennes à [df] ddl.
double ptukey(double q, int k, double df) {
  if (q <= 0) return 0;
  if (k < 2 || df < 2) throw ArgumentError(tr('ptukey : k ≥ 2 et ddl ≥ 2 requis', 'ptukey: k ≥ 2 and df ≥ 2 required'));
  if (!q.isFinite) return 1;
  final cc = k.toDouble();
  if (df > 25000) return _wprob(q, cc);
  final f2 = df * 0.5;
  var f2lf = f2 * math.log(df) - df * math.ln2 - lnGamma(f2);
  final f21 = f2 - 1.0, ff4 = df * 0.25;
  final ulen = df <= 100 ? 1.0 : (df <= 800 ? 0.5 : (df <= 5000 ? 0.25 : 0.125));
  f2lf += math.log(ulen);
  var ans = 0.0;
  for (var i = 1; i <= 50; i++) {
    var otsum = 0.0;
    final twa1 = (2 * i - 1) * ulen;
    for (var jj = 1; jj <= 16; jj++) {
      final int j;
      final double t1;
      if (8 < jj) {
        j = jj - 8 - 1;
        t1 = f2lf + f21 * math.log(twa1 + _xlegq[j] * ulen) - (_xlegq[j] * ulen + twa1) * ff4;
      } else {
        j = jj - 1;
        t1 = f2lf + f21 * math.log(twa1 - _xlegq[j] * ulen) + (_xlegq[j] * ulen - twa1) * ff4;
      }
      if (t1 >= -30.0) {
        final qsqz = 8 < jj ? q * math.sqrt((_xlegq[j] * ulen + twa1) * 0.5) : q * math.sqrt((-(_xlegq[j] * ulen) + twa1) * 0.5);
        otsum += _wprob(qsqz, cc) * _alegq[j] * math.exp(t1);
      }
    }
    if (i * ulen >= 1.0 && otsum <= 1e-14) break;
    ans += otsum;
  }
  return math.min(1.0, ans);
}

/// Quantile de l'étendue studentisée (résolution précise, voir [ptukey]).
double qtukey(double p, int k, double df) => brentRoot((q) => ptukey(q, k, df) - p, 1e-6, 100, tol: 1e-13);

/// Ajustement de Holm (pas à pas descendant), dans l'ordre des p fournis.
List<double> holm(List<double> p) {
  final m = p.length;
  final order = [for (var i = 0; i < m; i++) i]..sort((a, b) => p[a].compareTo(p[b]));
  final out = List<double>.filled(m, 0);
  var running = 0.0;
  for (var r = 0; r < m; r++) {
    running = math.max(running, math.min(1.0, (m - r) * p[order[r]]));
    out[order[r]] = running;
  }
  return out;
}

/// Une comparaison deux à deux : [diff] = groupe 2 − groupe 1 (convention de R).
class Pairwise {
  final String group1, group2;
  final double diff, statistic, p;
  final double? lower, upper, pAdjusted;
  const Pairwise(this.group1, this.group2, this.diff, this.statistic, this.p, {this.lower, this.upper, this.pAdjusted});

  /// p servant à la conclusion (ajusté pour la multiplicité).
  double get pFinal => pAdjusted ?? p;
}

List<(int, int)> _pairs(int k) => [for (var i = 0; i < k - 1; i++) for (var j = i + 1; j < k; j++) (i, j)];

/// Tukey HSD : variance résiduelle commune de l'ANOVA ; p et IC simultanés.
List<Pairwise> tukeyHsd(Map<String, List<double>> groups, {double level = 0.95}) {
  final names = groups.keys.toList(), g = groups.values.toList();
  final k = g.length;
  final n = g.fold(0, (a, x) => a + x.length);
  var ssw = 0.0;
  for (final x in g) {
    final m = mean(x);
    for (final v in x) {
      ssw += (v - m) * (v - m);
    }
  }
  final df = (n - k).toDouble();
  final mse = ssw / df;
  final q = qtukey(level, k, df);
  return [
    for (final (i, j) in _pairs(k))
      () {
        final d = mean(g[j]) - mean(g[i]);
        final se = math.sqrt(mse / 2 * (1 / g[i].length + 1 / g[j].length));
        final stat = d.abs() / se;
        final p = 1 - ptukey(stat, k, df);
        return Pairwise(names[i], names[j], d, stat, p, lower: d - q * se, upper: d + q * se);
      }()
  ];
}

/// Games-Howell : variances propres à chaque groupe et ddl de Welch par paire.
List<Pairwise> gamesHowell(Map<String, List<double>> groups, {double level = 0.95}) {
  final names = groups.keys.toList(), g = groups.values.toList();
  final k = g.length;
  return [
    for (final (i, j) in _pairs(k))
      () {
        final vi = variance(g[i]) / g[i].length, vj = variance(g[j]) / g[j].length;
        final df = (vi + vj) * (vi + vj) / (vi * vi / (g[i].length - 1) + vj * vj / (g[j].length - 1));
        final d = mean(g[j]) - mean(g[i]);
        final se = math.sqrt((vi + vj) / 2);
        final stat = d.abs() / se;
        final q = qtukey(level, k, df);
        return Pairwise(names[i], names[j], d, stat, 1 - ptukey(stat, k, df), lower: d - q * se, upper: d + q * se);
      }()
  ];
}

/// Test de Dunn (rangs communs, correction des ex aequo) et ajustement de Holm.
/// [diff] = rang moyen du groupe 2 − rang moyen du groupe 1.
List<Pairwise> dunnHolm(Map<String, List<double>> groups) {
  final names = groups.keys.toList(), g = groups.values.toList();
  final all = g.expand((x) => x).toList();
  final n = all.length.toDouble();
  final rk = rankWithTies(all);
  final meanRank = <double>[];
  var idx = 0;
  for (final x in g) {
    var s = 0.0;
    for (var i = 0; i < x.length; i++) {
      s += rk.ranks[idx++];
    }
    meanRank.add(s / x.length);
  }
  final tie = rk.tieSizes.fold<double>(0, (a, t) => a + (t * t * t - t).toDouble());
  final s2 = n * (n + 1) / 12 - tie / (12 * (n - 1));
  final raw = [
    for (final (i, j) in _pairs(g.length))
      () {
        final d = meanRank[j] - meanRank[i];
        final z = d / math.sqrt(s2 * (1 / g[i].length + 1 / g[j].length));
        return (i, j, d, z, normalTwoSidedP(z));
      }()
  ];
  final adj = holm([for (final r in raw) r.$5]);
  return [for (var m = 0; m < raw.length; m++) Pairwise(names[raw[m].$1], names[raw[m].$2], raw[m].$3, raw[m].$4, raw[m].$5, pAdjusted: adj[m])];
}

/// Tableau des comparaisons pour un résultat.
ResultTable pairwiseTable(String title, List<Pairwise> c, {required bool interval, String statName = 'q', double level = 0.95}) {
  final pct = (level * 100).round();
  final adjusted = c.any((x) => x.pAdjusted != null);
  return ResultTable(title, [
    tr('Comparaison', 'Comparison'),
    tr('Différence', 'Difference'),
    if (interval) tr('IC simultané $pct %', '$pct% simultaneous CI'),
    statName,
    if (adjusted) tr('p brut', 'raw p'),
    adjusted ? tr('p ajusté (Holm)', 'adjusted p (Holm)') : tr('p ajusté', 'adjusted p'),
  ], [
    for (final x in c)
      [
        '${x.group2} − ${x.group1}',
        fmt(x.diff),
        if (interval) '${fmt(x.lower)} – ${fmt(x.upper)}',
        fmt(x.statistic),
        if (adjusted) _pCell(x.p),
        _pCell(x.pFinal),
      ]
  ]);
}

/// « 0,03 » ou « < 0,001 » (sans le « p = » de [fmtP]).
String _pCell(double p) => fmtP(p).replaceFirst(RegExp(r'^p\s*=\s*'), '').replaceFirst(RegExp(r'^p\s*'), '');

/// Phrase résumant les paires qui diffèrent au seuil 5 % après ajustement.
String pairwiseSummary(List<Pairwise> c) {
  final sig = [for (final x in c) if (x.pFinal < 0.05) '${x.group2} − ${x.group1}'];
  if (sig.isEmpty) {
    return tr('Aucune paire ne diffère au seuil de 5 % après ajustement pour la multiplicité.',
        'No pair differs at the 5% level after adjustment for multiplicity.');
  }
  return tr('Paires qui diffèrent au seuil de 5 % après ajustement pour la multiplicité : ${sig.join(", ")}.',
      'Pairs that differ at the 5% level after adjustment for multiplicity: ${sig.join(", ")}.');
}
