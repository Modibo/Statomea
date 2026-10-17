/// Comparaison de deux méthodes de mesure (laboratoire) : régressions de Passing-Bablok et de Deming.
///  - Passing-Bablok (1983) : pente = médiane décalée des pentes de toutes les paires (pentes < −1 comptées en tête, K
///    fois ; pente −1 et paires identiques exclues) ; IC analytique par les rangs M1 = arrondi((N − C)/2) et
///    M2 = N − M1 + 1, C = z·√(n(n−1)(2n+5)/18) ; ordonnée = médiane(yᵢ − b·xᵢ). Suppose une corrélation positive
///    (τ de Kendall) et une relation linéaire ;
///  - Deming : erreurs de mesure sur les deux méthodes, rapport des variances d'erreur λ = σ²(x)/σ²(y) (1 : orthogonale) ;
///    IC jackknife (pseudo-valeurs, quantile t à n − 2 ddl, comme mcr) ;
///  - biais au niveau de décision X꜀ : a + (b − 1)·X꜀ ; biais constant si l'IC de a exclut 0, proportionnel si l'IC de b
///    exclut 1.
/// Validé contre validation/r/51_comparaison_methodes.R (mcr 1.3.3).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';

enum MethodComparisonKind { passingBablok, deming }

/// Arrondi de R (à l'entier pair en cas d'égalité à ,5).
int _roundHalfEven(double v) {
  final f = v.floorToDouble(), d = v - f;
  if ((d - 0.5).abs() < 1e-12) return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
  return v.round();
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Passing-Bablok : (pente, IC), (ordonnée, IC), N pentes retenues, K pentes < −1.
({List<double> slope, List<double> intercept, int n, int k}) passingBablok(List<double> x, List<double> y, {double level = 0.95}) {
  final n = x.length;
  final s = <double>[];
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      final dx = x[j] - x[i], dy = y[j] - y[i];
      if (dx == 0 && dy == 0) continue;
      final v = dx == 0 ? (dy > 0 ? double.infinity : double.negativeInfinity) : dy / dx;
      if (v == -1) continue;
      s.add(v);
    }
  }
  s.sort();
  final nn = s.length, k = s.where((v) => v < -1).length;
  if (nn < 2) throw StatInputError('pb_degenerate', tr('Trop peu de paires distinctes pour Passing-Bablok.', 'Too few distinct pairs for Passing-Bablok.'));
  double at(int rank) => s[(rank - 1).clamp(0, nn - 1)]; // rang 1-indexé
  final b = nn.isOdd ? at((nn + 1) ~/ 2 + k) : (at(nn ~/ 2 + k) + at(nn ~/ 2 + 1 + k)) / 2;
  final c = normalQuantile(1 - (1 - level) / 2) * math.sqrt(n * (n - 1) * (2 * n + 5) / 18);
  final m1 = _roundHalfEven((nn - c) / 2), m2 = nn - m1 + 1;
  final bl = m1 + k >= 1 ? at(m1 + k) : double.negativeInfinity, bu = m2 + k <= nn ? at(m2 + k) : double.infinity;
  double a(double bb) => _median([for (var i = 0; i < n; i++) y[i] - bb * x[i]]);
  return (slope: [b, bl, bu], intercept: [a(b), bu.isFinite ? a(bu) : double.negativeInfinity, bl.isFinite ? a(bl) : double.infinity], n: nn, k: k);
}

/// Régression de Deming (λ = σ²(x)/σ²(y)) : (ordonnée, pente).
({double intercept, double slope}) deming(List<double> x, List<double> y, {double errorRatio = 1}) {
  final n = x.length;
  final mx = x.fold(0.0, (a, b) => a + b) / n, my = y.fold(0.0, (a, b) => a + b) / n;
  var u = 0.0, q = 0.0, p = 0.0;
  for (var i = 0; i < n; i++) {
    u += (x[i] - mx) * (x[i] - mx);
    q += (y[i] - my) * (y[i] - my);
    p += (x[i] - mx) * (y[i] - my);
  }
  final l = errorRatio;
  final b = (l * q - u + math.sqrt((u - l * q) * (u - l * q) + 4 * l * p * p)) / (2 * l * p);
  return (intercept: my - b * mx, slope: b);
}

/// τ-b de Kendall et test normal avec correction des ex aequo (cor.test, exact = FALSE).
({double tau, double p}) kendallTau(List<double> x, List<double> y) {
  final n = x.length;
  var sStat = 0.0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      sStat += (x[j] - x[i]).sign * (y[j] - y[i]).sign;
    }
  }
  Map<double, int> ties(List<double> v) {
    final m = <double, int>{};
    for (final e in v) {
      m[e] = (m[e] ?? 0) + 1;
    }
    return m;
  }

  final tx = ties(x).values.where((t) => t > 1), ty = ties(y).values.where((t) => t > 1);
  final n0 = n * (n - 1) / 2;
  final n1 = tx.fold(0.0, (a, t) => a + t * (t - 1) / 2), n2 = ty.fold(0.0, (a, t) => a + t * (t - 1) / 2);
  final tau = sStat / math.sqrt((n0 - n1) * (n0 - n2));
  final v0 = n * (n - 1) * (2 * n + 5.0);
  final vt = tx.fold(0.0, (a, t) => a + t * (t - 1) * (2 * t + 5)), vu = ty.fold(0.0, (a, t) => a + t * (t - 1) * (2 * t + 5));
  final v1 = tx.fold(0.0, (a, t) => a + t * (t - 1)) * ty.fold(0.0, (a, t) => a + t * (t - 1));
  final v2 = tx.fold(0.0, (a, t) => a + t * (t - 1) * (t - 2)) * ty.fold(0.0, (a, t) => a + t * (t - 1) * (t - 2));
  final varS = (v0 - vt - vu) / 18 + v1 / (2 * n * (n - 1)) + v2 / (9 * n * (n - 1) * (n - 2));
  return (tau: tau, p: normalTwoSidedP(sStat / math.sqrt(varS)));
}

AnalysisResult methodComparison(List<double?> xr, List<double?> yr,
    {MethodComparisonKind kind = MethodComparisonKind.passingBablok,
    double errorRatio = 1,
    double level = 0.95,
    List<double> decisionLevels = const [],
    String? xName,
    String? yName,
    String unit = ''}) {
  xName ??= tr('Méthode de référence', 'Reference method');
  yName ??= tr('Méthode évaluée', 'Test method');
  final x = <double>[], y = <double>[];
  var dropped = 0;
  for (var i = 0; i < math.min(xr.length, yr.length); i++) {
    final a = xr[i], b = yr[i];
    if (a == null || b == null || !a.isFinite || !b.isFinite) {
      dropped++;
      continue;
    }
    x.add(a);
    y.add(b);
  }
  final n = x.length;
  if (n < 10) throw StatInputError('n_too_small', tr('Au moins 10 paires complètes sont requises (40 recommandées, CLSI EP09).', 'At least 10 complete pairs are required (40 recommended, CLSI EP09).'));
  if (errorRatio <= 0) throw StatInputError('error_ratio', tr('Le rapport des variances d\'erreur doit être > 0.', 'The error variance ratio must be > 0.'));
  final pct = (level * 100).round();
  final u = unit.isEmpty ? '' : ' $unit';
  final kt = kendallTau(x, y);
  late final List<double> sl, ic;
  double? seA, seB;
  int? nSlopes, kNeg;
  if (kind == MethodComparisonKind.passingBablok) {
    final r = passingBablok(x, y, level: level);
    sl = r.slope;
    ic = r.intercept;
    nSlopes = r.n;
    kNeg = r.k;
  } else {
    final full = deming(x, y, errorRatio: errorRatio);
    final ja = <double>[], jb = <double>[];
    for (var i = 0; i < n; i++) {
      final f = deming([for (var j = 0; j < n; j++) if (j != i) x[j]], [for (var j = 0; j < n; j++) if (j != i) y[j]], errorRatio: errorRatio);
      ja.add(f.intercept);
      jb.add(f.slope);
    }
    final tq = tQuantile(1 - (1 - level) / 2, n - 2.0);
    double se(List<double> jk, double est) {
      final pv = [for (final v in jk) n * est - (n - 1) * v];
      final m = pv.fold(0.0, (a, b) => a + b) / n;
      return math.sqrt(pv.fold(0.0, (a, v) => a + (v - m) * (v - m)) / (n - 1)) / math.sqrt(n);
    }

    seA = se(ja, full.intercept);
    seB = se(jb, full.slope);
    sl = [full.slope, full.slope - tq * seB, full.slope + tq * seB];
    ic = [full.intercept, full.intercept - tq * seA, full.intercept + tq * seA];
  }
  final constantBias = ic[1] > 0 || ic[2] < 0, propBias = sl[1] > 1 || sl[2] < 1;
  final biasRows = [for (final xc in decisionLevels) [fmt(xc), fmt(ic[0] + (sl[0] - 1) * xc), xc == 0 ? '—' : fmtPct((ic[0] + (sl[0] - 1) * xc) / xc)]];
  final biasText = decisionLevels.isEmpty
      ? ''
      : ' ${tr('Biais aux niveaux de décision : ', 'Bias at decision levels: ')}${[for (final xc in decisionLevels) '${fmt(xc)}$u → ${fmt(ic[0] + (sl[0] - 1) * xc)}$u${xc == 0 ? '' : ' (${fmtPct((ic[0] + (sl[0] - 1) * xc) / xc)})'}'].join(tr(' ; ', '; '))}.';
  final name = kind == MethodComparisonKind.passingBablok
      ? tr('Régression de Passing-Bablok', 'Passing-Bablok regression')
      : tr('Régression de Deming (λ = ${fmt(errorRatio)})', 'Deming regression (λ = ${fmt(errorRatio)})');
  final xs = [...x]..sort();
  return AnalysisResult(
    methodId: kind == MethodComparisonKind.passingBablok ? 'passing_bablok' : 'deming',
    methodName: name,
    inputs: {'n': n, 'dropped': dropped, 'level': level, 'x': xName, 'y': yName, if (kind == MethodComparisonKind.deming) 'errorRatio': errorRatio, 'decisionLevels': decisionLevels},
    formula: kind == MethodComparisonKind.passingBablok
        ? tr('Pentes Sᵢⱼ = (yⱼ − yᵢ)/(xⱼ − xᵢ) pour toutes les paires (Sᵢⱼ = −1 exclues) ; K = nombre de Sᵢⱼ < −1 ; b = médiane décalée de K rangs ; IC : rangs M1 = arrondi((N − C)/2) + K et M2 = N − M1 + 1 + K, C = z·√(n(n−1)(2n+5)/18) ; a = médiane(yᵢ − b·xᵢ), IC de a par les bornes de b.',
            'Slopes Sᵢⱼ = (yⱼ − yᵢ)/(xⱼ − xᵢ) for all pairs (Sᵢⱼ = −1 excluded); K = number of Sᵢⱼ < −1; b = median shifted by K ranks; CI: ranks M1 = round((N − C)/2) + K and M2 = N − M1 + 1 + K, C = z·√(n(n−1)(2n+5)/18); a = median(yᵢ − b·xᵢ), CI of a from the bounds of b.')
        : tr('b = [λS_yy − S_xx + √((S_xx − λS_yy)² + 4λS_xy²)]/(2λS_xy), λ = σ²(erreur x)/σ²(erreur y) ; a = ȳ − b·x̄ ; IC jackknife : pseudo-valeurs n·θ̂ − (n − 1)·θ̂₍₋ᵢ₎, ES = s/√n, θ̂ ± t(n − 2)·ES.',
            'b = [λS_yy − S_xx + √((S_xx − λS_yy)² + 4λS_xy²)]/(2λS_xy), λ = σ²(x error)/σ²(y error); a = ȳ − b·x̄; jackknife CI: pseudo-values n·θ̂ − (n − 1)·θ̂₍₋ᵢ₎, SE = s/√n, θ̂ ± t(n − 2)·SE.'),
    estimates: [
      Estimate(tr('Ordonnée à l\'origine (biais constant)', 'Intercept (constant bias)'), ic[0], lower: ic[1], upper: ic[2], level: level, se: seA),
      Estimate(tr('Pente (biais proportionnel)', 'Slope (proportional bias)'), sl[0], lower: sl[1], upper: sl[2], level: level, se: seB),
    ],
    statistics: {
      'n': n.toDouble(),
      'slope': sl[0],
      'slope_lower': sl[1],
      'slope_upper': sl[2],
      'intercept': ic[0],
      'intercept_lower': ic[1],
      'intercept_upper': ic[2],
      'intercept_se': ?seA,
      'slope_se': ?seB,
      if (nSlopes != null) 'n_slopes': nSlopes.toDouble(),
      if (kNeg != null) 'k_negative': kNeg.toDouble(),
      'kendall_tau': kt.tau,
      'kendall_p': kt.p,
      for (final xc in decisionLevels) 'bias_at_${xc == xc.roundToDouble() ? xc.toInt() : xc}': ic[0] + (sl[0] - 1) * xc,
    },
    checks: [
      Check('sample_size', tr('Au moins 40 échantillons (CLSI EP09)', 'At least 40 samples (CLSI EP09)'), n >= 40 ? CheckStatus.ok : CheckStatus.warning,
          tr('$n paires ; des IC larges ne permettent pas de conclure à l\'absence de biais.', '$n pairs; wide CIs do not allow concluding that there is no bias.')),
      Check('positive_correlation', tr('Corrélation positive entre méthodes (τ de Kendall)', 'Positive correlation between methods (Kendall\'s τ)'),
          kt.tau > 0 && kt.p < 0.05 ? CheckStatus.ok : CheckStatus.violated, 'τ = ${fmt(kt.tau)}, ${fmtP(kt.p)}.'),
      Check('measuring_range', tr('Plage de mesure couverte', 'Measuring range covered'), CheckStatus.notAssessed,
          tr('Valeurs de ${fmt(xs.first)} à ${fmt(xs.last)}$u : les conclusions ne valent que dans cette plage, qui doit inclure les niveaux de décision.',
              'Values from ${fmt(xs.first)} to ${fmt(xs.last)}$u: conclusions hold only within this range, which must include the decision levels.')),
      Check('linearity', tr('Relation linéaire entre méthodes', 'Linear relationship between methods'), CheckStatus.notAssessed,
          tr('Examiner le nuage de points et les résidus ; une courbure invalide la droite.', 'Inspect the scatter plot and residuals; curvature invalidates the line.')),
    ],
    tables: [
      ResultTable(tr('Coefficients', 'Coefficients'), [tr('Paramètre', 'Parameter'), tr('Estimation', 'Estimate'), tr('IC $pct %', '$pct% CI'), tr('Valeur d\'absence de biais', 'No-bias value'), tr('Conclusion', 'Conclusion')], [
        [tr('Ordonnée (a)', 'Intercept (a)'), fmt(ic[0]), '${fmt(ic[1])} – ${fmt(ic[2])}', '0', constantBias ? tr('biais constant', 'constant bias') : tr('pas de biais constant démontré', 'no constant bias shown')],
        [tr('Pente (b)', 'Slope (b)'), fmt(sl[0]), '${fmt(sl[1])} – ${fmt(sl[2])}', '1', propBias ? tr('biais proportionnel', 'proportional bias') : tr('pas de biais proportionnel démontré', 'no proportional bias shown')],
      ]),
      if (biasRows.isNotEmpty)
        ResultTable(tr('Biais aux niveaux de décision', 'Bias at decision levels'), [tr('Niveau X꜀', 'Level X꜀'), tr('Biais a + (b − 1)·X꜀', 'Bias a + (b − 1)·X꜀'), tr('Biais relatif', 'Relative bias')], biasRows),
    ],
    figures: {
      'methodComparison': {'x': x, 'y': y, 'slope': sl[0], 'intercept': ic[0], 'xName': xName, 'yName': yName, 'method': name},
    },
    interpretation: Interpretation(
      whyThisMethod: kind == MethodComparisonKind.passingBablok
          ? tr('Comparer une méthode à une autre sur les mêmes échantillons sans supposer d\'erreurs normales : Passing-Bablok est non paramétrique et robuste aux valeurs extrêmes, et ne privilégie aucune des deux méthodes.',
              'Comparing one method with another on the same samples without assuming normal errors: Passing-Bablok is nonparametric, robust to outliers, and favours neither method.')
          : tr('Comparer deux méthodes entachées toutes deux d\'erreur de mesure : la régression ordinaire, qui suppose x exact, sous-estime la pente ; Deming tient compte des deux erreurs.',
              'Comparing two methods both subject to measurement error: ordinary regression, which assumes x is exact, underestimates the slope; Deming accounts for both errors.'),
      whatItMeans: tr(
          '$yName ≈ ${fmt(ic[0])} + ${fmt(sl[0])} × $xName. Ordonnée ${fmt(ic[0])}$u (IC ${fmt(ic[1])} à ${fmt(ic[2])}) : ${constantBias ? 'biais constant' : 'pas de biais constant démontré'} ; pente ${fmt(sl[0])} (IC ${fmt(sl[1])} à ${fmt(sl[2])}) : ${propBias ? 'biais proportionnel de ${fmtPct(sl[0] - 1)}' : 'pas de biais proportionnel démontré'}.$biasText',
          '$yName ≈ ${fmt(ic[0])} + ${fmt(sl[0])} × $xName. Intercept ${fmt(ic[0])}$u (CI ${fmt(ic[1])} to ${fmt(ic[2])}): ${constantBias ? 'constant bias' : 'no constant bias shown'}; slope ${fmt(sl[0])} (CI ${fmt(sl[1])} to ${fmt(sl[2])}): ${propBias ? 'proportional bias of ${fmtPct(sl[0] - 1)}' : 'no proportional bias shown'}.$biasText'),
      notJustified: tr('Conclure à l\'interchangeabilité parce que les IC contiennent 0 et 1 (manque de puissance possible) : comparer le biais aux niveaux de décision à un biais acceptable fixé a priori ; utiliser le coefficient de corrélation comme preuve d\'accord ; extrapoler hors de la plage mesurée.',
          'Concluding interchangeability because the CIs contain 0 and 1 (possible lack of power): compare the bias at decision levels with an acceptable bias set a priori; using the correlation coefficient as proof of agreement; extrapolating beyond the measured range.'),
    ),
  );
}
