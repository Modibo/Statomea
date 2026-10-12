/// Association par modèle linéaire mixte (EMMAX / « P3D », Kang et al. 2010) : y = Xβ + g + e, g ~ N(0, Vu·K),
/// e ~ N(0, Ve·I), K = matrice de parenté génomique standardisée (comme pour l'ACP). Les composantes de variance sont
/// estimées par REML une fois sous le modèle nul (décomposition spectrale de K) ; chaque variant est ensuite testé par
/// moindres carrés généralisés avec H = K + λI (λ = Ve/Vu fixé), statistique F(1, n − p) comme `rrBLUP::GWAS(P3D = TRUE)`.
/// Les apparentés sont ainsi conservés au lieu d'être exclus. Génotypes manquants : imputés par la moyenne du variant.
/// Issue quantitative, ou binaire codée 0/1 (modèle linéaire, comme EMMAX). Validé contre rrBLUP 4.6
/// (`validation/r/30_lmm.R`).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'association.dart' show gwasFigures, genomicLambda;
import 'genotype_io.dart';
import 'genotype_pca.dart';

/// Covariable d'ajustement : valeurs alignées sur les sujets ; qualitative (indicatrices, [reference] exclue) ou numérique.
class LmmCovariate {
  final String name;
  final List<String?> values;
  final bool categorical;
  final String? reference;
  const LmmCovariate(this.name, this.values, {this.categorical = false, this.reference});
}

/// Solution d'un système symétrique défini positif de petite taille.
List<double> _solve(List<List<double>> a, List<double> b) => solveSpd(Matrix.fromRows(a), b) ?? (throw StatInputError('singular', tr('Covariables colinéaires : modèle non estimable.', 'Collinear covariates: model not estimable.')));

class GenotypeLmm {
  final double lambda, vu, ve, h2;
  final List<String> variants;
  final List<double> beta, se, f, p;
  final AnalysisResult result;
  GenotypeLmm(this.lambda, this.vu, this.ve, this.h2, this.variants, this.beta, this.se, this.f, this.p, this.result);
}

/// [outcome] aligné sur g.samples (null = manquant). [grmVariants] : variants servant à K (tous par défaut ; élagage
/// LD conseillé pour de grands panels). Les sujets dont l'issue ou une covariable manque sont écartés.
GenotypeLmm lmmScan(GenotypeData g, List<double?> outcome, {List<LmmCovariate> covariates = const [], List<int>? grmVariants,
    String outcomeName = '', Map<String, (String, int)>? positions, bool loco = false}) {
  // Sujets complets.
  final rows = [
    for (var i = 0; i < g.sampleCount; i++)
      if (outcome[i] != null && outcome[i]!.isFinite && covariates.every((c) => c.values[i] != null && (c.categorical || double.tryParse(c.values[i]!.replaceAll(',', '.')) != null))) i
  ];
  final n = rows.length;
  if (n < 20) throw StatInputError('n_too_small', tr('Au moins 20 sujets complets sont requis.', 'At least 20 complete subjects are required.'));
  if (n > maxPcaSamples) {
    throw StatInputError('too_many_samples', tr('$n sujets : au-delà de $maxPcaSamples, utiliser GCTA, GEMMA ou REGENIE.', '$n subjects: beyond $maxPcaSamples, use GCTA, GEMMA or REGENIE.'));
  }
  final sub = g.subset(sampleIdx: rows);
  final y = [for (final i in rows) outcome[i]!];
  // Matrice des effets fixes : constante, puis covariables.
  final xNames = ['(constante)'];
  final xCols = <List<double>>[List<double>.filled(n, 1)];
  for (final c in covariates) {
    final v = [for (final i in rows) c.values[i]!];
    if (c.categorical) {
      final lv = v.toSet().toList()..sort();
      final ref = c.reference != null && lv.contains(c.reference) ? c.reference! : lv.first;
      for (final l in lv.where((l) => l != ref)) {
        xNames.add('${c.name}=$l');
        xCols.add([for (final x in v) x == l ? 1.0 : 0.0]);
      }
    } else {
      xNames.add(c.name);
      xCols.add([for (final x in v) double.parse(x.replaceAll(',', '.'))]);
    }
  }
  final p0 = xCols.length;
  final p1 = p0 + 1, df2 = n - p1;
  double dot(List<double> a, List<double> b, List<double> w) {
    var t = 0.0;
    for (var k = 0; k < n; k++) {
      t += a[k] * b[k] * w[k];
    }
    return t;
  }

  // Modèle nul sur une matrice K : décomposition spectrale, REML de λ = Ve/Vu (grille sur log λ puis section dorée,
  // tolérance 1e-12, bornes de rrBLUP [1e-9, 1e9]) et termes fixes précalculés pour les tests P3D.
  ({List<List<double>> u, List<double> w, double lam, double vu, double ve, List<double> ys, List<List<double>> xs, List<List<double>> aXX, List<double> aXy, double yWy})
      fitNull(List<List<double>> k) {
    final eig = symmetricEigen(k);
    final s = eig.values, u = eig.vectors;
    List<double> rot(List<double> v) {
      final out = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        final vi = v[i];
        if (vi == 0) continue;
        final ui = u[i];
        for (var q = 0; q < n; q++) {
          out[q] += ui[q] * vi;
        }
      }
      return out;
    }

    final ys = rot(y);
    final xs = [for (final c in xCols) rot(c)];
    ({double value, double rss}) reml(double lam) {
      final w = [for (final v in s) 1 / (v + lam)];
      final a = [for (var j = 0; j < p0; j++) [for (var l = 0; l < p0; l++) dot(xs[j], xs[l], w)]];
      final beta = _solve(a, [for (var j = 0; j < p0; j++) dot(xs[j], ys, w)]);
      var rss = 0.0;
      for (var q = 0; q < n; q++) {
        var fit = 0.0;
        for (var j = 0; j < p0; j++) {
          fit += xs[j][q] * beta[j];
        }
        rss += w[q] * (ys[q] - fit) * (ys[q] - fit);
      }
      var logdet = 0.0;
      for (final v in s) {
        logdet += math.log(v + lam);
      }
      return (value: (n - p0) * math.log(rss) + logdet + logDetSpd(Matrix.fromRows(a))!, rss: rss);
    }

    double f(double l) => reml(math.exp(l)).value;
    const lo0 = -20.72326583694641, hi0 = 20.72326583694641; // log(1e-9), log(1e9)
    var best = lo0, bestV = f(lo0);
    for (var q = 1; q <= 120; q++) {
      final l = lo0 + (hi0 - lo0) * q / 120;
      final v = f(l);
      if (v < bestV) {
        bestV = v;
        best = l;
      }
    }
    var a = math.max(lo0, best - (hi0 - lo0) / 120), b = math.min(hi0, best + (hi0 - lo0) / 120);
    const gr = 0.6180339887498949;
    var c = b - gr * (b - a), d = a + gr * (b - a);
    var fc = f(c), fd = f(d);
    while (b - a > 1e-12) {
      if (fc < fd) {
        b = d;
        d = c;
        fd = fc;
        c = b - gr * (b - a);
        fc = f(c);
      } else {
        a = c;
        c = d;
        fc = fd;
        d = a + gr * (b - a);
        fd = f(d);
      }
    }
    final lam = math.exp((a + b) / 2);
    final vu = reml(lam).rss / (n - p0);
    final w = [for (final v in s) 1 / (v + lam)];
    return (
      u: u, w: w, lam: lam, vu: vu, ve: lam * vu, ys: ys, xs: xs,
      aXX: [for (var j = 0; j < p0; j++) [for (var l = 0; l < p0; l++) dot(xs[j], xs[l], w)]],
      aXy: [for (var j = 0; j < p0; j++) dot(xs[j], ys, w)],
      yWy: dot(ys, ys, w),
    );
  }

  // Test P3D d'un variant (dosages imputés) avec le modèle nul [fit] : (β, ES, F, p) ou null si non estimable.
  (double, double, double, double)? testVariant(({List<List<double>> u, List<double> w, double lam, double vu, double ve, List<double> ys, List<List<double>> xs, List<List<double>> aXX, List<double> aXy, double yWy}) fit, List<double> xv) {
    final xr = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final vi = xv[i];
      if (vi == 0) continue;
      final ui = fit.u[i];
      for (var q = 0; q < n; q++) {
        xr[q] += ui[q] * vi;
      }
    }
    final cross = List<double>.filled(p0, 0);
    var xWx = 0.0, xWy = 0.0;
    for (var q = 0; q < n; q++) {
      final wx = fit.w[q] * xr[q];
      xWx += wx * xr[q];
      xWy += wx * fit.ys[q];
      for (var l = 0; l < p0; l++) {
        cross[l] += wx * fit.xs[l][q];
      }
    }
    final bigM = [for (var r = 0; r < p1; r++) [for (var q = 0; q < p1; q++) r < p0 && q < p0 ? fit.aXX[r][q] : (r < p0 ? cross[r] : (q < p0 ? cross[q] : xWx))]];
    final inv = invertSpd(Matrix.fromRows(bigM));
    if (inv == null) return null;
    final rhs = [...fit.aXy, xWy];
    final bh = [for (var r = 0; r < p1; r++) [for (var q = 0; q < p1; q++) inv.get(r, q) * rhs[q]].fold(0.0, (t, e) => t + e)];
    var fitTerm = 0.0;
    for (var r = 0; r < p1; r++) {
      fitTerm += bh[r] * rhs[r];
    }
    final s2 = (fit.yWy - fitTerm) / df2; // rᵀWr = yᵀWy − β̂ᵀXᵀWy
    final varB = s2 * inv.get(p0, p0);
    final fstat = bh[p0] * bh[p0] / varB;
    return (bh[p0], math.sqrt(varB), fstat, fUpper(fstat, 1, df2.toDouble()));
  }

  List<double>? dosageOf(int j) {
    final d = sub.dosage[j];
    var sum = 0, cnt = 0;
    for (final x in d) {
      if (x >= 0) {
        sum += x;
        cnt++;
      }
    }
    if (cnt == 0) return null;
    final mean = sum / cnt;
    final xv = [for (final x in d) x < 0 ? mean : x.toDouble()];
    return xv.every((x) => x == xv.first) ? null : xv; // monomorphe : non testé
  }

  final gv = grmVariants ?? [for (var j = 0; j < sub.variantCount; j++) j];
  final (:grm, :m, :trace) = genotypeGrm(sub, variants: gv);
  final full = fitNull(grm);
  final lam = full.lam, vu = full.vu, ve = full.ve;
  final meanDiag = trace / n;
  final h2 = vu * meanDiag / (vu * meanDiag + ve);
  final names = <String>[], beta = <double>[], se = <double>[], fs = <double>[], pv = <double>[];
  final lambdaByChrom = <String, double>{};
  void add(int j, (double, double, double, double)? t) {
    if (t == null) return;
    names.add(sub.variants[j].label);
    beta.add(t.$1);
    se.add(t.$2);
    fs.add(t.$3);
    pv.add(t.$4);
  }

  if (!loco) {
    for (var j = 0; j < sub.variantCount; j++) {
      final xv = dosageOf(j);
      if (xv != null) add(j, testVariant(full, xv));
    }
  } else {
    // LOCO : K₋c = (m·K − m_c·K_c)/(m − m_c), K_c = GRM des seuls variants du chromosome c ; REML réestimé par chromosome.
    final chroms = <String>[];
    for (final v in sub.variants) {
      if (!chroms.contains(v.chrom)) chroms.add(v.chrom);
    }
    if (chroms.length < 2) throw StatInputError('loco_one_chrom', tr('LOCO demande des variants sur au moins deux chromosomes.', 'LOCO requires variants on at least two chromosomes.'));
    final results = <int, (double, double, double, double)?>{};
    for (final c in chroms) {
      final onC = [for (final j in gv) if (sub.variants[j].chrom == c) j];
      List<List<double>> kc;
      if (onC.isEmpty) {
        kc = grm;
      } else {
        final part = genotypeGrm(sub, variants: onC, minVariants: 1);
        final mOff = m - part.m;
        if (mOff < 10) throw StatInputError('loco_few', tr('Trop peu de variants hors du chromosome $c pour la matrice LOCO.', 'Too few variants outside chromosome $c for the LOCO matrix.'));
        kc = [for (var i = 0; i < n; i++) [for (var q = 0; q < n; q++) (m * grm[i][q] - part.m * part.grm[i][q]) / mOff]];
      }
      final fit = fitNull(kc);
      lambdaByChrom[c] = fit.lam;
      for (var j = 0; j < sub.variantCount; j++) {
        if (sub.variants[j].chrom != c) continue;
        final xv = dosageOf(j);
        if (xv != null) results[j] = testVariant(fit, xv);
      }
    }
    for (var j = 0; j < sub.variantCount; j++) {
      if (results.containsKey(j)) add(j, results[j]);
    }
  }
  final lambdaGc = genomicLambda([for (final x in pv) chiSquareQuantile(1 - x, 1)]);
  final order = [for (var k = 0; k < pv.length; k++) k]..sort((x, y2) {
      final c0 = pv[x].compareTo(pv[y2]);
      return c0 != 0 ? c0 : x.compareTo(y2);
    });
  final big = pv.length > 1000;
  final statIdx = big ? order.take(500).toList() : [for (var k = 0; k < pv.length; k++) k];
  final tableIdx = order.take(200).toList();
  final gw = pv.where((x) => x < 5e-8).length;
  String pc(double v) => v < 1e-3 ? v.toStringAsExponential(2) : fmt(v, digits: 3);
  final on = outcomeName.isEmpty ? tr('issue', 'outcome') : outcomeName;
  final result = AnalysisResult(
    methodId: 'lmm_scan',
    methodName: loco
        ? tr('Balayage par modèle linéaire mixte LOCO (apparentés conservés)', 'LOCO linear mixed model scan (relatives kept)')
        : tr('Balayage par modèle linéaire mixte (apparentés conservés)', 'Linear mixed model scan (relatives kept)'),
    inputs: {'samples': n, 'variants': sub.variantCount, 'grmVariants': m, 'covariates': [for (final c in covariates) c.name], 'outcome': on, 'loco': loco},
    formula: tr(
        'y = Xβ + g + e, g ~ N(0, Vu·K), e ~ N(0, Ve·I) ; K = GRM standardisée ($m variants) ; REML sous le modèle nul (λ = Ve/Vu) ; '
            'pour chaque variant : moindres carrés généralisés avec H = K + λI fixé (P3D/EMMAX), F = β̂²/Var(β̂) à (1, n − p) ddl ; génotypes manquants imputés par la moyenne.'
            '${loco ? ' LOCO : pour les variants du chromosome c, K₋c = GRM sans les variants de c, REML réestimé par chromosome.' : ''}',
        'y = Xβ + g + e, g ~ N(0, Vu·K), e ~ N(0, Ve·I); K = standardized GRM ($m variants); REML under the null model (λ = Ve/Vu); '
            'for each variant: generalized least squares with H = K + λI fixed (P3D/EMMAX), F = β̂²/Var(β̂) with (1, n − p) df; missing genotypes imputed by the mean.'
            '${loco ? ' LOCO: for variants of chromosome c, K₋c = GRM without the variants of c, REML re-estimated per chromosome.' : ''}'),
    estimates: [
      Estimate(tr('Part de variance expliquée par les variants (h²_SNP)', 'Variance explained by the variants (h²_SNP)'), h2),
      for (final k in order.take(5)) Estimate(tr('Effet par allèle — ${names[k]}', 'Effect per allele — ${names[k]}'), beta[k],
          lower: beta[k] - 1.959963984540054 * se[k], upper: beta[k] + 1.959963984540054 * se[k], pValue: pv[k], se: se[k]),
    ],
    statistics: {
      'lambda_reml': lam,
      'vu': vu,
      've': ve,
      'h2_snp': h2,
      'variants_tested': pv.length.toDouble(),
      'n_genome_wide': gw.toDouble(),
      'lambda_gc': ?lambdaGc,
      for (final e in lambdaByChrom.entries) 'lambda_reml_chr${e.key}': e.value,
      for (final k in statIdx) ...{'beta_${names[k]}': beta[k], 'se_${names[k]}': se[k], 'p_${names[k]}': pv[k]},
    },
    checks: [
      Check('inflation', tr('Inflation génomique λ ≤ 1,10', 'Genomic inflation λ ≤ 1.10'),
          lambdaGc == null ? CheckStatus.notAssessed : (lambdaGc <= 1.1 ? CheckStatus.ok : CheckStatus.warning),
          lambdaGc == null ? tr('Moins de 50 variants.', 'Fewer than 50 variants.') : 'λ = ${fmt(lambdaGc, digits: 3)}.'),
      if (loco)
        Check('proximal', tr('Contamination proximale évitée (LOCO)', 'Proximal contamination avoided (LOCO)'), CheckStatus.ok,
            tr('Chaque variant est testé avec une matrice de parenté sans son chromosome. Un λ > 1 peut alors refléter un vrai signal polygénique et non une confusion.',
                'Each variant is tested with a relationship matrix without its chromosome. A λ > 1 may then reflect a true polygenic signal rather than confounding.'))
      else
        Check('proximal', tr('Contamination proximale (variant testé inclus dans K)', 'Proximal contamination (tested variant included in K)'), CheckStatus.notAssessed,
            tr('K inclut le variant testé, ce qui rend le test légèrement conservateur (λ un peu < 1) ; l\'option LOCO (K sans le chromosome testé) l\'évite.',
                'K includes the tested variant, which makes the test slightly conservative (λ a little < 1); the LOCO option (K without the tested chromosome) avoids it.')),
      Check('binary', tr('Issue binaire traitée par modèle linéaire', 'Binary outcome handled by a linear model'), CheckStatus.notAssessed,
          tr('Pour une issue 0/1, l\'effet est sur l\'échelle des probabilités (comme EMMAX) ; les p restent valides, les effets ne sont pas des OR.',
              'For a 0/1 outcome, the effect is on the probability scale (as in EMMAX); p-values remain valid, effects are not ORs.')),
    ],
    tables: [
      ResultTable(tr('Variants les plus associés (${tableIdx.length} sur ${pv.length})', 'Most associated variants (${tableIdx.length} of ${pv.length})'),
          [tr('Variant', 'Variant'), tr('Effet par allèle', 'Effect per allele'), tr('ES', 'SE'), 'F', 'p'], [
        for (final k in tableIdx) [names[k], fmt(beta[k], digits: 4), fmt(se[k], digits: 3), fmt(fs[k], digits: 3), pc(pv[k])]
      ]),
    ],
    figures: gwasFigures(names, pv, lambda: lambdaGc, positions: positions),
    log: [
      tr('$n sujets, ${pv.length} variants testés, K sur $m variants ; λ = Ve/Vu = ${fmt(lam, digits: 4)}.', '$n subjects, ${pv.length} variants tested, K on $m variants; λ = Ve/Vu = ${fmt(lam, digits: 4)}.'),
      tr('Effets fixes : ${xNames.join(', ')}.', 'Fixed effects: ${xNames.join(', ')}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Des sujets apparentés (ou une structure de population fine) partagent des génotypes : la régression ordinaire surestime alors les associations. Le modèle mixte en tient compte par la parenté génomique, sans exclure personne.',
          'Related subjects (or fine population structure) share genotypes: ordinary regression then overstates associations. The mixed model accounts for this through genomic relatedness, without excluding anyone.'),
      whatItMeans: tr(
          'h²_SNP ≈ ${fmtPct(h2)} de la variance de $on attribuable aux variants ; ${gw > 0 ? '$gw variant(s) au seuil pangénomique 5 × 10⁻⁸' : 'aucun variant au seuil pangénomique'}${lambdaGc == null ? '' : ' ; λ = ${fmt(lambdaGc, digits: 3)}'}.',
          'h²_SNP ≈ ${fmtPct(h2)} of the variance of $on attributable to the variants; ${gw > 0 ? '$gw variant(s) at the genome-wide threshold 5 × 10⁻⁸' : 'no variant at the genome-wide threshold'}${lambdaGc == null ? '' : '; λ = ${fmt(lambdaGc, digits: 3)}'}.'),
      notJustified: tr(
          'Interpréter h²_SNP comme l\'héritabilité totale ; lire l\'effet d\'une issue 0/1 comme un OR ; conclure sans réplication.',
          'Interpreting h²_SNP as total heritability; reading the effect on a 0/1 outcome as an OR; concluding without replication.'),
    ),
  );
  return GenotypeLmm(lam, vu, ve, h2, names, beta, se, fs, pv, result);
}
