/// Régression sur les scores de déséquilibre de liaison (LD score regression, Bulik-Sullivan et al. 2015) : sous un modèle
/// polygénique, E[χ²_j] = N·h²·ℓ_j/M + N·a + 1 ; la pente (en fonction du score LD ℓ_j) mesure la polygénie (h²), l'intercept
/// mesure l'inflation qui ne dépend pas du DL (stratification, apparentement cryptique). Un λ_GC élevé avec un intercept
/// proche de 1 traduit donc un vrai signal polygénique, et non une confusion.
/// Scores LD calculés dans l'échantillon (pas de panel de référence) : ℓ_j = Σ_k r²_adj(j, k) sur les variants du même
/// chromosome à moins de [windowBp] paires de bases (k = j inclus), r²_adj = r² − (1 − r²)/(n − 2). Régression pondérée en
/// deux itérations, erreurs types par jackknife sur blocs contigus. Validé contre R (`validation/r/32_ldsc.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import 'genotype_io.dart';

/// Scores LD dans l'échantillon, alignés sur g.variants (null pour un variant monomorphe). Génotypes manquants imputés par
/// la moyenne du variant.
List<double?> ldScores(GenotypeData g, {int windowBp = 1000000}) {
  final n = g.sampleCount;
  if (n < 3) throw StatInputError('n_too_small', tr('Au moins 3 sujets sont requis.', 'At least 3 subjects are required.'));
  // Colonnes centrées réduites (norme 1) : r = produit scalaire.
  final z = <Float64List?>[];
  for (final d in g.dosage) {
    var sum = 0, cnt = 0;
    for (final x in d) {
      if (x >= 0) {
        sum += x;
        cnt++;
      }
    }
    if (cnt == 0) {
      z.add(null);
      continue;
    }
    final mean = sum / cnt;
    final v = Float64List(n);
    var ss = 0.0;
    for (var i = 0; i < n; i++) {
      v[i] = d[i] < 0 ? 0 : d[i] - mean;
      ss += v[i] * v[i];
    }
    if (ss <= 0) {
      z.add(null);
      continue;
    }
    final s = 1 / math.sqrt(ss);
    for (var i = 0; i < n; i++) {
      v[i] *= s;
    }
    z.add(v);
  }
  final ell = List<double?>.generate(g.variantCount, (j) => z[j] == null ? null : 0.0);
  double adj(double r2) => r2 - (1 - r2) / (n - 2);
  final byChrom = <String, List<int>>{};
  for (var j = 0; j < g.variantCount; j++) {
    if (z[j] != null) (byChrom[g.variants[j].chrom] ??= []).add(j);
  }
  for (final idx in byChrom.values) {
    idx.sort((a, b) {
      final c = g.variants[a].pos.compareTo(g.variants[b].pos);
      return c != 0 ? c : a.compareTo(b);
    });
    for (var a = 0; a < idx.length; a++) {
      final j = idx[a], zj = z[j]!;
      ell[j] = ell[j]! + adj(1);
      for (var b = a + 1; b < idx.length && g.variants[idx[b]].pos - g.variants[j].pos <= windowBp; b++) {
        final k = idx[b], zk = z[k]!;
        var r = 0.0;
        for (var i = 0; i < n; i++) {
          r += zj[i] * zk[i];
        }
        final v = adj(r * r);
        ell[j] = ell[j]! + v;
        ell[k] = ell[k]! + v;
      }
    }
  }
  return ell;
}

/// χ² à 1 ddl correspondant à une p bilatérale (précis pour les très petites p).
double chiSquareFromP(double p) {
  final zq = normalQuantile(math.max(p, 1e-300) / 2);
  return zq * zq;
}

class LdscFit {
  final double intercept, h2, seIntercept, seH2, meanChi2;
  final double? ratio;
  final int used, excluded, blocks, m, n;
  final AnalysisResult result;
  LdscFit(this.intercept, this.h2, this.seIntercept, this.seH2, this.meanChi2, this.ratio, this.used, this.excluded, this.blocks, this.m, this.n, this.result);
}

double _mean(List<double> v) => v.fold(0.0, (s, x) => s + x) / v.length;

/// Moindres carrés pondérés de y sur (1, ℓ), restreints aux indices k tels que sel(k) : (intercept, pente).
(double, double) _wls(List<double> l, List<double> y, List<double> w, bool Function(int) sel) {
  var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  for (var k = 0; k < l.length; k++) {
    if (!sel(k)) continue;
    sw += w[k];
    sx += w[k] * l[k];
    sy += w[k] * y[k];
    sxx += w[k] * l[k] * l[k];
    sxy += w[k] * l[k] * y[k];
  }
  final det = sw * sxx - sx * sx;
  if (det.abs() <= 1e-12 * sw * sxx) throw StatInputError('ldsc_flat', tr('Scores LD sans variation : régression impossible.', 'LD scores without variation: regression impossible.'));
  final slope = (sw * sxy - sx * sy) / det;
  return ((sy - slope * sx) / sw, slope);
}

/// Régression LD score univariée (deux itérations de poids) : intercept, h² et poids finals.
({double a, double h2, List<double> w}) _univariate(List<double> c, List<double> l, int n, int m) {
  var a = 1.0;
  var h2 = m * (_mean(c) - 1) / (n * _mean(l));
  var w = <double>[];
  for (var it = 0; it < 2; it++) {
    final hw = h2.clamp(0.0, 1.0);
    w = [for (var k = 0; k < l.length; k++) 1 / (math.max(l[k], 1) * math.pow(a + n * hw * l[k] / m, 2))];
    final f = _wls(l, c, w, (_) => true);
    a = f.$1;
    h2 = f.$2 * m / n;
  }
  return (a: a, h2: h2, w: w);
}

/// Régression de [chi2] sur [ldScore] (listes alignées ; null = variant non testé ou sans score). [n] : effectif du
/// balayage ; [m] : nombre de variants ayant servi aux scores LD. Les variants de χ² > max(80 ; 0,001·N) sont exclus.
LdscFit ldscRegression(List<double?> chi2, List<double?> ldScore, {required int n, required int m, String scanName = ''}) {
  final c = <double>[], l = <double>[];
  var excluded = 0;
  final maxChi2 = math.max(80.0, 0.001 * n);
  for (var j = 0; j < chi2.length; j++) {
    final x = chi2[j], s = ldScore[j];
    if (x == null || s == null || !x.isFinite) continue;
    if (x > maxChi2) {
      excluded++;
      continue;
    }
    c.add(x);
    l.add(s);
  }
  final jn = c.length;
  if (jn < 200) {
    throw StatInputError('ldsc_few', tr('$jn variants utilisables : la régression LD score demande au moins 200 variants (idéalement plusieurs centaines de milliers).',
        '$jn usable variants: LD score regression requires at least 200 variants (ideally several hundred thousand).'));
  }
  final meanChi2 = _mean(c), meanL = _mean(l);
  final (:a, :h2, :w) = _univariate(c, l, n, m);
  final b = math.min(50, jn ~/ 10);
  final jk = <(double, double)>[];
  for (var q = 0; q < b; q++) {
    final f = _wls(l, c, w, (k) => (k * b) ~/ jn != q);
    jk.add((f.$1, f.$2 * m / n));
  }
  double jse(double Function((double, double)) get) {
    final v = [for (final e in jk) get(e)];
    final mu = _mean(v);
    return math.sqrt((b - 1) / b * v.fold(0.0, (s, x) => s + (x - mu) * (x - mu)));
  }

  final seA = jse((e) => e.$1), seH = jse((e) => e.$2);
  final ratio = meanChi2 > 1 ? (a - 1) / (meanChi2 - 1) : null;
  final zA = (a - 1) / seA;
  final pA = normalUpper(zA); // test unilatéral : intercept > 1
  final confounded = a - 1 > 1.959963984540054 * seA;
  final sn = scanName.isEmpty ? tr('le balayage', 'the scan') : scanName;
  String f3(double v) => fmt(v, digits: 3);
  final result = AnalysisResult(
    methodId: 'ldsc',
    methodName: tr('Régression LD score (polygénie ou confusion ?)', 'LD score regression (polygenicity or confounding?)'),
    inputs: {'variants': jn, 'excluded': excluded, 'samples': n, 'ldVariants': m, 'scan': sn},
    formula: tr(
        'E[χ²_j] = N·h²·ℓ_j/M + intercept ; ℓ_j = Σ_k r²_adj(j, k) sur les variants du même chromosome à moins de 1 Mb, r²_adj = r² − (1 − r²)/(N − 2) (DL de l\'échantillon) ; '
            'moindres carrés pondérés (poids 1/(max(ℓ, 1)·(a + N·h²·ℓ/M)²), deux itérations) ; χ² > max(80 ; 0,001·N) exclus ; ES par jackknife sur $b blocs contigus ; '
            'ratio = (intercept − 1)/(χ̄² − 1).',
        'E[χ²_j] = N·h²·ℓ_j/M + intercept; ℓ_j = Σ_k r²_adj(j, k) over variants of the same chromosome within 1 Mb, r²_adj = r² − (1 − r²)/(N − 2) (in-sample LD); '
            'weighted least squares (weights 1/(max(ℓ, 1)·(a + N·h²·ℓ/M)²), two iterations); χ² > max(80; 0.001·N) excluded; SE by jackknife over $b contiguous blocks; '
            'ratio = (intercept − 1)/(mean χ² − 1).'),
    estimates: [
      Estimate(tr('Intercept (1 = pas de confusion)', 'Intercept (1 = no confounding)'), a,
          lower: a - 1.959963984540054 * seA, upper: a + 1.959963984540054 * seA, se: seA, pValue: pA),
      Estimate(tr('Héritabilité h²_SNP (pente)', 'Heritability h²_SNP (slope)'), h2, lower: h2 - 1.959963984540054 * seH, upper: h2 + 1.959963984540054 * seH, se: seH),
      if (ratio != null) Estimate(tr('Ratio (part de l\'inflation due à la confusion)', 'Ratio (share of inflation due to confounding)'), ratio),
    ],
    statistics: {
      'intercept': a,
      'se_intercept': seA,
      'p_intercept': pA,
      'h2': h2,
      'se_h2': seH,
      'mean_chi2': meanChi2,
      'mean_ld_score': meanL,
      'ratio': ?ratio,
      'variants_used': jn.toDouble(),
      'variants_excluded': excluded.toDouble(),
      'jackknife_blocks': b.toDouble(),
    },
    checks: [
      Check('intercept', tr('Intercept compatible avec 1 (pas de confusion)', 'Intercept compatible with 1 (no confounding)'), confounded ? CheckStatus.warning : CheckStatus.ok,
          tr('Intercept ${f3(a)} (ES ${f3(seA)}).${confounded ? ' Inflation indépendante du DL : stratification ou apparentement cryptique ; ajuster sur les composantes principales ou utiliser un modèle mixte.' : ''}',
              'Intercept ${f3(a)} (SE ${f3(seA)}).${confounded ? ' Inflation independent of LD: stratification or cryptic relatedness; adjust for principal components or use a mixed model.' : ''}')),
      Check('size', tr('Panel assez dense (≥ 200 000 variants)', 'Dense enough panel (≥ 200,000 variants)'), jn >= 200000 ? CheckStatus.ok : CheckStatus.warning,
          tr('$jn variants : en deçà, les erreurs types sont larges et l\'estimation reste indicative.', '$jn variants: below this, standard errors are wide and the estimate remains indicative.')),
      Check('ld_sample', tr('Scores LD calculés dans l\'échantillon', 'LD scores computed in the sample'), CheckStatus.notAssessed,
          tr('Sans panel de référence (1000 Genomes) : convient si l\'échantillon est grand et d\'ascendance homogène ; un mélange de populations biaise ℓ.',
              'Without a reference panel (1000 Genomes): suitable if the sample is large and of homogeneous ancestry; a mixture of populations biases ℓ.')),
    ],
    tables: [
      ResultTable(tr('Décomposition de l\'inflation', 'Decomposition of the inflation'), [tr('Quantité', 'Quantity'), tr('Valeur', 'Value'), tr('ES', 'SE')], [
        [tr('χ² moyen', 'Mean χ²'), f3(meanChi2), ''],
        [tr('Intercept', 'Intercept'), f3(a), f3(seA)],
        [tr('h²_SNP', 'h²_SNP'), f3(h2), f3(seH)],
        if (ratio != null) [tr('Ratio', 'Ratio'), f3(ratio), ''],
        [tr('Score LD moyen', 'Mean LD score'), f3(meanL), ''],
      ]),
    ],
    figures: {
      'ldsc': {
        'bins': _bins(l, c),
        'intercept': a,
        'slope': h2 * n / m,
      },
    },
    log: [
      tr('$jn variants ($excluded exclus pour χ² > ${fmt(maxChi2, digits: 3)}), N = $n, M = $m ; $b blocs de jackknife.',
          '$jn variants ($excluded excluded for χ² > ${fmt(maxChi2, digits: 3)}), N = $n, M = $m; $b jackknife blocks.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Un λ_GC > 1 peut venir d\'une confusion (stratification, apparentés) ou d\'un vrai signal polygénique. Les variants en fort DL captent davantage de signal polygénique, mais pas davantage de confusion : la pente sur le score LD sépare les deux.',
          'A λ_GC > 1 may come from confounding (stratification, relatives) or from a true polygenic signal. Variants in strong LD capture more polygenic signal, but not more confounding: the slope on the LD score separates the two.'),
      whatItMeans: tr(
          'Pour $sn : intercept ${f3(a)} (ES ${f3(seA)})${confounded ? ', nettement > 1 : une part de l\'inflation vient d\'une confusion' : ', compatible avec 1 : l\'inflation s\'explique par la polygénie'}${ratio != null ? ' (ratio ${f3(ratio)})' : ''} ; h²_SNP ≈ ${f3(h2)}.',
          'For $sn: intercept ${f3(a)} (SE ${f3(seA)})${confounded ? ', clearly > 1: part of the inflation comes from confounding' : ', compatible with 1: the inflation is explained by polygenicity'}${ratio != null ? ' (ratio ${f3(ratio)})' : ''}; h²_SNP ≈ ${f3(h2)}.'),
      notJustified: tr(
          'Conclure sur quelques milliers de variants (ES larges) ; appliquer la régression après un modèle mixte LOCO ou un contrôle génomique (intercept alors < 1 ou artificiellement 1) ; lire h² d\'une issue cas-témoins comme l\'héritabilité sur l\'échelle de liability.',
          'Concluding on a few thousand variants (wide SEs); applying the regression after a LOCO mixed model or genomic control (intercept then < 1 or artificially 1); reading h² of a case-control outcome as liability-scale heritability.'),
    ),
  );
  return LdscFit(a, h2, seA, seH, meanChi2, ratio, jn, excluded, b, m, n, result);
}

/// χ² moyen par classe de score LD (20 classes d'effectifs égaux) pour la figure.
List<List<double>> _bins(List<double> l, List<double> c) {
  final idx = [for (var k = 0; k < l.length; k++) k]..sort((x, y) => l[x].compareTo(l[y]));
  const nb = 20;
  return [
    for (var q = 0; q < nb; q++)
      () {
        final part = idx.sublist(q * idx.length ~/ nb, (q + 1) * idx.length ~/ nb);
        var sl = 0.0, sc = 0.0;
        for (final k in part) {
          sl += l[k];
          sc += c[k];
        }
        return [sl / part.length, sc / part.length];
      }(),
  ];
}

/// Scores LD de [g] puis régression des [chi2] du balayage (alignés sur g.variants ; null = non testé).
LdscFit ldscFromScan(GenotypeData g, List<double?> chi2, {required int n, String scanName = ''}) {
  final ell = ldScores(g);
  final m = ell.where((x) => x != null).length;
  return ldscRegression(chi2, ell, n: n, m: m, scanName: scanName);
}

class GeneticCorrelationFit {
  final double rg, seRg, pRg, rhoG, seRhoG, rho, seRho, h2a, h2b, seH2a, seH2b;
  final int used, blocks;
  final AnalysisResult result;
  GeneticCorrelationFit(this.rg, this.seRg, this.pRg, this.rhoG, this.seRhoG, this.rho, this.seRho, this.h2a, this.h2b, this.seH2a, this.seH2b, this.used,
      this.blocks, this.result);
}

/// Corrélation génétique par régression LD score croisée (Bulik-Sullivan et al. 2015b) : E[z₁z₂] = N·ρg·ℓ/M + ρ, à partir
/// des z SIGNÉS de deux balayages sur les mêmes sujets (alignés sur [ldScore] ; null = non testé). rg = ρg/√(h²₁·h²₂).
/// Variants retenus si z₁² et z₂² ≤ max(80 ; 0,001·N). Validé contre R (`validation/r/33_rg.R`).
GeneticCorrelationFit geneticCorrelation(List<double?> z1, List<double?> z2, List<double?> ldScore,
    {required int n, required int m, String trait1 = '', String trait2 = ''}) {
  final a1 = <double>[], a2 = <double>[], l = <double>[];
  final maxChi2 = math.max(80.0, 0.001 * n);
  for (var j = 0; j < ldScore.length; j++) {
    final x = z1[j], y = z2[j], s = ldScore[j];
    if (x == null || y == null || s == null || !x.isFinite || !y.isFinite) continue;
    if (x * x > maxChi2 || y * y > maxChi2) continue;
    a1.add(x);
    a2.add(y);
    l.add(s);
  }
  final jn = l.length;
  if (jn < 200) {
    throw StatInputError('ldsc_few', tr('$jn variants utilisables : la corrélation génétique demande au moins 200 variants (idéalement plusieurs centaines de milliers).',
        '$jn usable variants: genetic correlation requires at least 200 variants (ideally several hundred thousand).'));
  }
  final c1 = [for (final x in a1) x * x], c2 = [for (final x in a2) x * x], y = [for (var k = 0; k < jn; k++) a1[k] * a2[k]];
  final u1 = _univariate(c1, l, n, m), u2 = _univariate(c2, l, n, m);
  var rho = 0.0, rhoG = m * _mean(y) / (n * _mean(l));
  var w = <double>[];
  for (var it = 0; it < 2; it++) {
    final h1 = u1.h2.clamp(0.0, 1.0), h2 = u2.h2.clamp(0.0, 1.0), rc = rhoG.clamp(-1.0, 1.0);
    w = [
      for (var k = 0; k < jn; k++)
        1 / (math.max(l[k], 1) * ((u1.a + n * h1 * l[k] / m) * (u2.a + n * h2 * l[k] / m) + math.pow(rho + n * rc * l[k] / m, 2)))
    ];
    final f = _wls(l, y, w, (_) => true);
    rho = f.$1;
    rhoG = f.$2 * m / n;
  }
  final defined = u1.h2 > 0 && u2.h2 > 0;
  final rg = defined ? rhoG / math.sqrt(u1.h2 * u2.h2) : double.nan;
  final b = math.min(50, jn ~/ 10);
  final jk = <List<double>>[];
  for (var q = 0; q < b; q++) {
    bool sel(int k) => (k * b) ~/ jn != q;
    final e1 = _wls(l, c1, u1.w, sel), e2 = _wls(l, c2, u2.w, sel), ec = _wls(l, y, w, sel);
    final h1 = e1.$2 * m / n, h2 = e2.$2 * m / n, g = ec.$2 * m / n;
    jk.add([ec.$1, g, g / math.sqrt(h1 * h2), h1, h2]);
  }
  double jse(int i) {
    final v = [for (final e in jk) e[i]];
    final mu = _mean(v);
    return math.sqrt((b - 1) / b * v.fold(0.0, (s, x) => s + (x - mu) * (x - mu)));
  }

  final seRho = jse(0), seG = jse(1), seRg = defined ? jse(2) : double.nan, seH1 = jse(3), seH2 = jse(4);
  final pRg = defined && seRg.isFinite ? normalTwoSidedP(rg / seRg) : double.nan;
  const zq = 1.959963984540054;
  final t1 = trait1.isEmpty ? tr('trait 1', 'trait 1') : trait1, t2 = trait2.isEmpty ? tr('trait 2', 'trait 2') : trait2;
  String f3(double v) => fmt(v, digits: 3);
  final weakH2 = !(u1.h2 > 2 * seH1 && u2.h2 > 2 * seH2);
  final result = AnalysisResult(
    methodId: 'genetic_correlation',
    methodName: tr('Corrélation génétique ($t1 – $t2, régression LD score croisée)', 'Genetic correlation ($t1 – $t2, cross-trait LD score regression)'),
    inputs: {'variants': jn, 'samples': n, 'ldVariants': m, 'trait1': t1, 'trait2': t2},
    formula: tr(
        'E[z₁z₂] = N·ρg·ℓ/M + ρ (z signés des deux balayages, mêmes sujets) ; h²₁ et h²₂ par régression LD score univariée ; rg = ρg/√(h²₁·h²₂) ; '
            'moindres carrés pondérés (poids 1/(max(ℓ, 1)·[(a₁ + N·h²₁·ℓ/M)(a₂ + N·h²₂·ℓ/M) + (ρ + N·ρg·ℓ/M)²]), deux itérations) ; '
            'variants avec z² > max(80 ; 0,001·N) exclus ; ES par jackknife sur $b blocs contigus.',
        'E[z₁z₂] = N·ρg·ℓ/M + ρ (signed z of the two scans, same subjects); h²₁ and h²₂ by univariate LD score regression; rg = ρg/√(h²₁·h²₂); '
            'weighted least squares (weights 1/(max(ℓ, 1)·[(a₁ + N·h²₁·ℓ/M)(a₂ + N·h²₂·ℓ/M) + (ρ + N·ρg·ℓ/M)²]), two iterations); '
            'variants with z² > max(80; 0.001·N) excluded; SE by jackknife over $b contiguous blocks.'),
    estimates: [
      if (defined) Estimate(tr('Corrélation génétique rg', 'Genetic correlation rg'), rg, lower: rg - zq * seRg, upper: rg + zq * seRg, se: seRg, pValue: pRg),
      Estimate(tr('Covariance génétique ρg', 'Genetic covariance ρg'), rhoG, lower: rhoG - zq * seG, upper: rhoG + zq * seG, se: seG),
      Estimate(tr('h²_SNP — $t1', 'h²_SNP — $t1'), u1.h2, lower: u1.h2 - zq * seH1, upper: u1.h2 + zq * seH1, se: seH1),
      Estimate(tr('h²_SNP — $t2', 'h²_SNP — $t2'), u2.h2, lower: u2.h2 - zq * seH2, upper: u2.h2 + zq * seH2, se: seH2),
      Estimate(tr('Intercept croisé ρ (recouvrement des échantillons)', 'Cross-trait intercept ρ (sample overlap)'), rho, lower: rho - zq * seRho, upper: rho + zq * seRho, se: seRho),
    ],
    statistics: {
      if (defined) ...{'rg': rg, 'se_rg': seRg, 'p_rg': pRg},
      'rho_g': rhoG,
      'se_rho_g': seG,
      'h2_1': u1.h2,
      'h2_2': u2.h2,
      'se_h2_1': seH1,
      'se_h2_2': seH2,
      'intercept_1': u1.a,
      'intercept_2': u2.a,
      'intercept_cross': rho,
      'se_intercept_cross': seRho,
      'variants_used': jn.toDouble(),
      'jackknife_blocks': b.toDouble(),
    },
    checks: [
      Check('h2_signal', tr('Héritabilité nettement non nulle pour les deux traits (h² > 2 ES)', 'Heritability clearly non-zero for both traits (h² > 2 SE)'),
          !defined ? CheckStatus.violated : (weakH2 ? CheckStatus.warning : CheckStatus.ok),
          tr('h²₁ = ${f3(u1.h2)} (ES ${f3(seH1)}), h²₂ = ${f3(u2.h2)} (ES ${f3(seH2)}).${!defined ? ' rg non défini (h² ≤ 0).' : weakH2 ? ' rg instable : le dénominateur √(h²₁·h²₂) est mal estimé.' : ''}',
              'h²₁ = ${f3(u1.h2)} (SE ${f3(seH1)}), h²₂ = ${f3(u2.h2)} (SE ${f3(seH2)}).${!defined ? ' rg undefined (h² ≤ 0).' : weakH2 ? ' Unstable rg: the denominator √(h²₁·h²₂) is poorly estimated.' : ''}')),
      if (defined)
        Check('range', tr('rg dans [−1 ; 1]', 'rg within [−1; 1]'), rg.abs() <= 1 ? CheckStatus.ok : CheckStatus.warning,
            rg.abs() <= 1
                ? 'rg = ${f3(rg)}.'
                : tr('rg = ${f3(rg)} : l\'estimateur n\'est pas borné ; une valeur hors de [−1 ; 1] traduit l\'imprécision (lire l\'IC).',
                    'rg = ${f3(rg)}: the estimator is not bounded; a value outside [−1; 1] reflects imprecision (read the CI).')),
      Check('size', tr('Panel assez dense (≥ 200 000 variants)', 'Dense enough panel (≥ 200,000 variants)'), jn >= 200000 ? CheckStatus.ok : CheckStatus.warning,
          tr('$jn variants : en deçà, les erreurs types sont larges et l\'estimation reste indicative.', '$jn variants: below this, standard errors are wide and the estimate remains indicative.')),
    ],
    tables: [
      ResultTable(tr('Corrélation génétique', 'Genetic correlation'), [tr('Quantité', 'Quantity'), tr('Valeur', 'Value'), tr('ES', 'SE')], [
        if (defined) ['rg', f3(rg), f3(seRg)],
        [tr('Covariance génétique ρg', 'Genetic covariance ρg'), f3(rhoG), f3(seG)],
        ['h²_SNP — $t1', f3(u1.h2), f3(seH1)],
        ['h²_SNP — $t2', f3(u2.h2), f3(seH2)],
        [tr('Intercept croisé ρ', 'Cross-trait intercept ρ'), f3(rho), f3(seRho)],
      ]),
    ],
    figures: {
      'ldsc': {'bins': _bins(l, y), 'intercept': rho, 'slope': rhoG * n / m, 'cross': true},
    },
    log: [tr('$jn variants communs, N = $n, M = $m ; $b blocs de jackknife.', '$jn shared variants, N = $n, M = $m; $b jackknife blocks.')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Deux maladies peuvent partager des facteurs génétiques. Les variants en fort DL captent davantage de signal commun : la pente du produit z₁z₂ sur le score LD mesure la covariance génétique, que rg ramène sur l\'échelle d\'une corrélation. L\'intercept absorbe la corrélation non génétique due aux sujets communs.',
          'Two diseases may share genetic factors. Variants in strong LD capture more shared signal: the slope of the product z₁z₂ on the LD score measures the genetic covariance, which rg puts on a correlation scale. The intercept absorbs the non-genetic correlation due to shared subjects.'),
      whatItMeans: defined
          ? tr('Corrélation génétique entre $t1 et $t2 : rg = ${f3(rg)} (IC 95 % ${f3(rg - zq * seRg)} à ${f3(rg + zq * seRg)}, ${fmtP(pRg)}).',
              'Genetic correlation between $t1 and $t2: rg = ${f3(rg)} (95% CI ${f3(rg - zq * seRg)} to ${f3(rg + zq * seRg)}, ${fmtP(pRg)}).')
          : tr('rg non défini : l\'héritabilité estimée d\'au moins un trait est ≤ 0.', 'rg undefined: the estimated heritability of at least one trait is ≤ 0.'),
      notJustified: tr(
          'Conclure à une causalité (une rg peut venir de la pléiotropie ou d\'un facteur commun) ; conclure sur quelques milliers de variants ; interpréter rg si l\'un des h² n\'est pas nettement > 0.',
          'Concluding causality (rg may come from pleiotropy or a shared factor); concluding on a few thousand variants; interpreting rg if one of the h² is not clearly > 0.'),
    ),
  );
  return GeneticCorrelationFit(rg, seRg, pRg, rhoG, seG, rho, seRho, u1.h2, u2.h2, seH1, seH2, jn, b, result);
}

/// Scores LD de [g] puis corrélation génétique entre deux balayages ([z1], [z2] signés, alignés sur g.variants).
GeneticCorrelationFit geneticCorrelationFromScans(GenotypeData g, List<double?> z1, List<double?> z2, {required int n, String trait1 = '', String trait2 = ''}) {
  final ell = ldScores(g);
  return geneticCorrelation(z1, z2, ell, n: n, m: ell.where((x) => x != null).length, trait1: trait1, trait2: trait2);
}
