/// Modèle mixte logistique pour une issue cas-témoins avec apparentés (GMMAT, Chen et al. 2016) :
/// logit P(y = 1) = Xα + b, b ~ N(0, τK), K = GRM standardisée. Modèle nul par quasi-vraisemblance pénalisée (PQL) :
/// à chaque itération, W = μ(1 − μ), réponse de travail Y = η + (y − μ)/W, Σ = W⁻¹ + τK ; τ maximise la vraisemblance
/// REML du modèle de travail (dispersion 1), calculée sur la décomposition spectrale de W^½KW^½ ; α = (XᵀΣ⁻¹X)⁻¹XᵀΣ⁻¹Y,
/// η = Xα + τKΣ⁻¹(Y − Xα), jusqu'au point fixe (variations relatives < 1e-10). Puis test du score par variant (dosage
/// imputé par la moyenne) : U = gᵀ(y − μ̂), V = gᵀPg, U²/V ~ χ²₁ ; effet approché β ≈ U/V (log-OR), ES 1/√V, comme
/// `GMMAT::glmm.score`. Validé contre GMMAT 1.4.2 et un recalcul R serré (`validation/r/35_glmm.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import '../regression/glm.dart';
import 'association.dart' show gwasFigures, genomicLambda;
import 'genotype_io.dart';
import 'genotype_lmm.dart' show LmmCovariate;
import 'genotype_pca.dart';

class GenotypeGlmm {
  final double tau;
  final List<double> alpha;
  final int iterations;
  final List<String> variants;
  final List<double> score, variance, beta, se, p;
  final AnalysisResult result;
  GenotypeGlmm(this.tau, this.alpha, this.iterations, this.variants, this.score, this.variance, this.beta, this.se, this.p, this.result);
}

double _dotF(Float64List a, Float64List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// [outcome] binaire 0/1 aligné sur g.samples (null = manquant). [grmVariants] : variants de K (tous par défaut).
GenotypeGlmm glmmScan(GenotypeData g, List<double?> outcome,
    {List<LmmCovariate> covariates = const [], List<int>? grmVariants, String outcomeName = '', Map<String, (String, int)>? positions}) {
  final rows = [
    for (var i = 0; i < g.sampleCount; i++)
      if (outcome[i] != null && covariates.every((c) => c.values[i] != null && (c.categorical || double.tryParse(c.values[i]!.replaceAll(',', '.')) != null))) i
  ];
  final n = rows.length;
  if (rows.any((i) => outcome[i] != 0 && outcome[i] != 1)) {
    throw StatInputError('glmm_binary', tr('Le modèle mixte logistique demande une issue binaire (0/1).', 'The logistic mixed model requires a binary outcome (0/1).'));
  }
  final cases = rows.where((i) => outcome[i] == 1).length;
  if (cases < 10 || n - cases < 10) throw StatInputError('n_too_small', tr('Au moins 10 cas et 10 témoins sont requis.', 'At least 10 cases and 10 controls are required.'));
  if (n > maxPcaSamples) {
    throw StatInputError('too_many_samples', tr('$n sujets : au-delà de $maxPcaSamples, utiliser GMMAT, SAIGE ou REGENIE.', '$n subjects: beyond $maxPcaSamples, use GMMAT, SAIGE or REGENIE.'));
  }
  final sub = g.subset(sampleIdx: rows);
  final y = Float64List.fromList([for (final i in rows) outcome[i]!]);
  final xNames = ['(constante)'];
  final xCols = <Float64List>[Float64List(n)..fillRange(0, n, 1)];
  for (final c in covariates) {
    final v = [for (final i in rows) c.values[i]!];
    if (c.categorical) {
      final lv = v.toSet().toList()..sort();
      final ref = c.reference != null && lv.contains(c.reference) ? c.reference! : lv.first;
      for (final l in lv.where((l) => l != ref)) {
        xNames.add('${c.name}=$l');
        xCols.add(Float64List.fromList([for (final x in v) x == l ? 1.0 : 0.0]));
      }
    } else {
      xNames.add(c.name);
      xCols.add(Float64List.fromList([for (final x in v) double.parse(x.replaceAll(',', '.'))]));
    }
  }
  final p0 = xCols.length;
  final gv = grmVariants ?? [for (var j = 0; j < sub.variantCount; j++) j];
  final k = genotypeGrm(sub, variants: gv).grm;
  final kRows = [for (final r in k) r is Float64List ? r : Float64List.fromList(r)];

  // Départ : régression logistique sans effet aléatoire.
  final f0 = fitLogistic([for (var i = 0; i < n; i++) Float64List.fromList([for (final c in xCols) c[i]])], y, keepTrace: false);
  var alpha = List<double>.of(f0.beta);
  final eta = Float64List(n);
  for (var i = 0; i < n; i++) {
    var e = 0.0;
    for (var j = 0; j < p0; j++) {
      e += xCols[j][i] * alpha[j];
    }
    eta[i] = e;
  }
  var tau = 0.1;
  var iterations = 0;
  var converged = false;

  // Base spectrale de W^½KW^½ pour des poids donnés : vecteurs propres en lignes (ut[q][i]), λ ≥ 0, et M = UᵀD (lignes).
  ({List<Float64List> m, Float64List lam, Float64List d}) basis(Float64List mu) {
    final d = Float64List(n);
    for (var i = 0; i < n; i++) {
      d[i] = math.sqrt(mu[i] * (1 - mu[i]));
    }
    final a = [for (var i = 0; i < n; i++) Float64List.fromList([for (var q = 0; q < n; q++) d[i] * d[q] * kRows[i][q]])];
    final e = symmetricEigen(a);
    final lam = Float64List.fromList([for (final v in e.values) math.max(v, 0.0)]);
    final m = [for (var q = 0; q < n; q++) Float64List.fromList([for (var i = 0; i < n; i++) e.vectors[i][q] * d[i]])];
    return (m: m, lam: lam, d: d);
  }

  Float64List rot(List<Float64List> m, Float64List v) => Float64List.fromList([for (final row in m) _dotF(row, v)]);

  // Produits pondérés dans la base spectrale.
  List<List<double>> xwx(List<Float64List> xt, Float64List w) => [
        for (var a = 0; a < p0; a++) [for (var b = 0; b < p0; b++) () { var s = 0.0; for (var q = 0; q < n; q++) { s += xt[a][q] * w[q] * xt[b][q]; } return s; }()]
      ];
  List<double> xwv(List<Float64List> xt, Float64List w, Float64List v) => [
        for (var a = 0; a < p0; a++) () { var s = 0.0; for (var q = 0; q < n; q++) { s += xt[a][q] * w[q] * v[q]; } return s; }()
      ];
  List<double> solve(List<List<double>> a, List<double> b) =>
      solveSpd(Matrix.fromRows(a), b) ?? (throw StatInputError('singular', tr('Covariables colinéaires : modèle non estimable.', 'Collinear covariates: model not estimable.')));

  for (iterations = 1; iterations <= 200; iterations++) {
    final mu = Float64List.fromList([for (final e in eta) 1 / (1 + math.exp(-e))]);
    final yw = Float64List.fromList([for (var i = 0; i < n; i++) eta[i] + (y[i] - mu[i]) / (mu[i] * (1 - mu[i]))]);
    final b = basis(mu);
    final yt = rot(b.m, yw);
    final xt = [for (final c in xCols) rot(b.m, c)];
    double objective(double lt) {
      final t = math.exp(lt);
      final w = Float64List.fromList([for (final l in b.lam) 1 / (1 + t * l)]);
      final a2 = xwx(xt, w);
      final beta = solve(a2, xwv(xt, w, yt));
      var s = 0.0, logdet = 0.0;
      for (var q = 0; q < n; q++) {
        var fit = 0.0;
        for (var j = 0; j < p0; j++) {
          fit += xt[j][q] * beta[j];
        }
        s += w[q] * (yt[q] - fit) * (yt[q] - fit);
        logdet += math.log(1 + t * b.lam[q]);
      }
      return logdet + logDetSpd(Matrix.fromRows(a2))! + s;
    }

    // Grille sur log τ puis section dorée (tolérance 1e-12), bornes [1e-8, 1e5].
    const lo0 = -18.420680743952367, hi0 = 11.512925464970229;
    var best = lo0, bestV = objective(lo0);
    for (var q = 1; q <= 60; q++) {
      final l = lo0 + (hi0 - lo0) * q / 60;
      final v = objective(l);
      if (v < bestV) {
        bestV = v;
        best = l;
      }
    }
    var lo = math.max(lo0, best - (hi0 - lo0) / 60), hi = math.min(hi0, best + (hi0 - lo0) / 60);
    const gr = 0.6180339887498949;
    var c = hi - gr * (hi - lo), dd = lo + gr * (hi - lo);
    var fc = objective(c), fd = objective(dd);
    while (hi - lo > 1e-12) {
      if (fc < fd) {
        hi = dd;
        dd = c;
        fd = fc;
        c = hi - gr * (hi - lo);
        fc = objective(c);
      } else {
        lo = c;
        c = dd;
        fc = fd;
        dd = lo + gr * (hi - lo);
        fd = objective(dd);
      }
    }
    final tauN = math.exp((lo + hi) / 2);
    final w = Float64List.fromList([for (final l in b.lam) 1 / (1 + tauN * l)]);
    final alphaN = solve(xwx(xt, w), xwv(xt, w, yt));
    // Σ⁻¹r = D·U·diag(w)·Uᵀ·D·r = Mᵀ diag(w) M r.
    final r = Float64List.fromList([for (var i = 0; i < n; i++) yw[i] - [for (var j = 0; j < p0; j++) xCols[j][i] * alphaN[j]].fold(0.0, (s, x) => s + x)]);
    final mr = rot(b.m, r);
    final sir = Float64List(n);
    for (var q = 0; q < n; q++) {
      final wq = w[q] * mr[q];
      final row = b.m[q];
      for (var i = 0; i < n; i++) {
        sir[i] += row[i] * wq;
      }
    }
    for (var i = 0; i < n; i++) {
      var e = 0.0;
      for (var j = 0; j < p0; j++) {
        e += xCols[j][i] * alphaN[j];
      }
      eta[i] = e + tauN * _dotF(kRows[i], sir);
    }
    var conv = (tauN - tau).abs() / (tau + 1e-10) < 1e-10;
    for (var j = 0; j < p0 && conv; j++) {
      if ((alphaN[j] - alpha[j]).abs() / (alpha[j].abs() + 1e-10) >= 1e-10) conv = false;
    }
    tau = tauN;
    alpha = alphaN;
    if (conv) {
      converged = true;
      break;
    }
  }
  iterations = math.min(iterations, 200);

  // Tests du score avec le modèle nul final.
  final mu = Float64List.fromList([for (final e in eta) 1 / (1 + math.exp(-e))]);
  final b = basis(mu);
  final w = Float64List.fromList([for (final l in b.lam) 1 / (1 + tau * l)]);
  final xt = [for (final c in xCols) rot(b.m, c)];
  final a2 = xwx(xt, w);
  final a2inv = invertSpd(Matrix.fromRows(a2))!;
  final res = Float64List.fromList([for (var i = 0; i < n; i++) y[i] - mu[i]]);
  final names = <String>[], us = <double>[], vs = <double>[], betas = <double>[], ses = <double>[], pv = <double>[];
  for (var j = 0; j < sub.variantCount; j++) {
    final d = sub.dosage[j];
    var sum = 0, cnt = 0;
    for (final x in d) {
      if (x >= 0) {
        sum += x;
        cnt++;
      }
    }
    if (cnt == 0) continue;
    final mean = sum / cnt;
    final gx = Float64List.fromList([for (final x in d) x < 0 ? mean : x.toDouble()]);
    if (gx.every((x) => x == gx.first)) continue;
    final gt = rot(b.m, gx);
    var v = 0.0;
    for (var q = 0; q < n; q++) {
      v += w[q] * gt[q] * gt[q];
    }
    final xg = xwv(xt, w, gt);
    for (var a = 0; a < p0; a++) {
      for (var c = 0; c < p0; c++) {
        v -= xg[a] * a2inv.get(a, c) * xg[c];
      }
    }
    final u = _dotF(gx, res);
    if (v <= 0) continue;
    names.add(sub.variants[j].label);
    us.add(u);
    vs.add(v);
    betas.add(u / v);
    ses.add(1 / math.sqrt(v));
    pv.add(chiSquareUpper(u * u / v, 1));
  }
  final lambdaGc = genomicLambda([for (var q = 0; q < us.length; q++) us[q] * us[q] / vs[q]]);
  final order = [for (var q = 0; q < pv.length; q++) q]..sort((x, z) {
      final c0 = pv[x].compareTo(pv[z]);
      return c0 != 0 ? c0 : x.compareTo(z);
    });
  final big = pv.length > 1000;
  final statIdx = big ? order.take(500).toList() : [for (var q = 0; q < pv.length; q++) q];
  final tableIdx = order.take(200).toList();
  final gw = pv.where((x) => x < 5e-8).length;
  String pc(double v) => v < 1e-3 ? v.toStringAsExponential(2) : fmt(v, digits: 3);
  final on = outcomeName.isEmpty ? tr('issue', 'outcome') : outcomeName;
  const zq = 1.959963984540054;
  final result = AnalysisResult(
    methodId: 'glmm_scan',
    methodName: tr('Balayage par modèle mixte logistique (apparentés conservés)', 'Logistic mixed model scan (relatives kept)'),
    inputs: {'samples': n, 'cases': cases, 'variants': sub.variantCount, 'grmVariants': gv.length, 'covariates': [for (final c in covariates) c.name], 'outcome': on},
    formula: tr(
        'logit P(y = 1) = Xα + b, b ~ N(0, τK) ; K = GRM standardisée (${gv.length} variants) ; modèle nul par PQL (τ par REML sur le modèle de travail, dispersion 1) ; '
            'pour chaque variant, test du score : U = gᵀ(y − μ̂), V = gᵀPg, U²/V ~ χ²₁ ; effet approché β ≈ U/V (log-OR par allèle), ES = 1/√V ; génotypes manquants imputés par la moyenne.',
        'logit P(y = 1) = Xα + b, b ~ N(0, τK); K = standardized GRM (${gv.length} variants); null model by PQL (τ by REML on the working model, dispersion 1); '
            'for each variant, score test: U = gᵀ(y − μ̂), V = gᵀPg, U²/V ~ χ²₁; approximate effect β ≈ U/V (log-OR per allele), SE = 1/√V; missing genotypes imputed by the mean.'),
    estimates: [
      Estimate(tr('Variance de l\'effet génétique aléatoire τ (échelle logit)', 'Variance of the random genetic effect τ (logit scale)'), tau),
      for (final q in order.take(5))
        Estimate(tr('OR par allèle (approché) — ${names[q]}', 'OR per allele (approximate) — ${names[q]}'), math.exp(betas[q]),
            lower: math.exp(betas[q] - zq * ses[q]), upper: math.exp(betas[q] + zq * ses[q]), pValue: pv[q]),
    ],
    statistics: {
      'tau': tau,
      'iterations': iterations.toDouble(),
      'variants_tested': pv.length.toDouble(),
      'n_genome_wide': gw.toDouble(),
      'lambda_gc': ?lambdaGc,
      for (var j = 0; j < p0; j++) 'alpha_${xNames[j]}': alpha[j],
      for (final q in statIdx) ...{'beta_${names[q]}': betas[q], 'se_${names[q]}': ses[q], 'p_${names[q]}': pv[q]},
    },
    checks: [
      Check('convergence', tr('Convergence du modèle nul (PQL)', 'Convergence of the null model (PQL)'), converged ? CheckStatus.ok : CheckStatus.violated,
          tr('$iterations itération(s)${converged ? '' : ' : NON convergé, résultats non fiables'}.', '$iterations iteration(s)${converged ? '' : ': NOT converged, unreliable results'}.')),
      Check('inflation', tr('Inflation génomique λ ≤ 1,10', 'Genomic inflation λ ≤ 1.10'),
          lambdaGc == null ? CheckStatus.notAssessed : (lambdaGc <= 1.1 ? CheckStatus.ok : CheckStatus.warning),
          lambdaGc == null ? tr('Moins de 50 variants.', 'Fewer than 50 variants.') : 'λ = ${fmt(lambdaGc, digits: 3)}.'),
      Check('boundary', tr('Variance génétique non nulle', 'Non-zero genetic variance'), tau > 1e-6 ? CheckStatus.ok : CheckStatus.notAssessed,
          tau > 1e-6
              ? 'τ = ${fmt(tau, digits: 3)}.'
              : tr('τ ≈ 0 : pas de parenté détectable ; le test revient à la régression logistique.', 'τ ≈ 0: no detectable relatedness; the test reduces to logistic regression.')),
      Check('approx_effect', tr('Effets approchés par le test du score', 'Effects approximated by the score test'), CheckStatus.notAssessed,
          tr('β ≈ U/V est une approximation à un pas (fiable pour de petits effets) ; les p du score sont valides. Pour estimer un OR précis, ajuster le variant dans le modèle.',
              'β ≈ U/V is a one-step approximation (reliable for small effects); score p-values are valid. For a precise OR, fit the variant in the model.')),
    ],
    tables: [
      ResultTable(tr('Variants les plus associés (${tableIdx.length} sur ${pv.length})', 'Most associated variants (${tableIdx.length} of ${pv.length})'),
          [tr('Variant', 'Variant'), tr('OR par allèle (approché)', 'OR per allele (approximate)'), 'U', 'V', 'p'], [
        for (final q in tableIdx) [names[q], fmt(math.exp(betas[q]), digits: 3), fmt(us[q], digits: 4), fmt(vs[q], digits: 4), pc(pv[q])]
      ]),
    ],
    figures: gwasFigures(names, pv, lambda: lambdaGc, positions: positions),
    log: [
      tr('$n sujets ($cases cas), ${pv.length} variants testés, K sur ${gv.length} variants ; τ = ${fmt(tau, digits: 4)} après $iterations itérations PQL.',
          '$n subjects ($cases cases), ${pv.length} variants tested, K on ${gv.length} variants; τ = ${fmt(tau, digits: 4)} after $iterations PQL iterations.'),
      tr('Effets fixes : ${xNames.join(', ')}.', 'Fixed effects: ${xNames.join(', ')}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Des apparentés partagent génotypes et risque : la régression logistique ordinaire surestime alors les associations. Le modèle mixte logistique tient compte de la parenté génomique sans exclure de sujets, et garde l\'échelle logit adaptée à une issue cas-témoins.',
          'Relatives share genotypes and risk: ordinary logistic regression then overstates associations. The logistic mixed model accounts for genomic relatedness without excluding subjects, and keeps the logit scale suited to a case-control outcome.'),
      whatItMeans: tr(
          'τ = ${fmt(tau, digits: 3)} ; ${gw > 0 ? '$gw variant(s) au seuil pangénomique 5 × 10⁻⁸' : 'aucun variant au seuil pangénomique'}${lambdaGc == null ? '' : ' ; λ = ${fmt(lambdaGc, digits: 3)}'}.',
          'τ = ${fmt(tau, digits: 3)}; ${gw > 0 ? '$gw variant(s) at the genome-wide threshold 5 × 10⁻⁸' : 'no variant at the genome-wide threshold'}${lambdaGc == null ? '' : '; λ = ${fmt(lambdaGc, digits: 3)}'}.'),
      notJustified: tr(
          'Lire les OR approchés comme des estimations précises de forts effets ; utiliser le test du score avec un déséquilibre cas-témoins extrême et des variants rares (préférer SAIGE) ; conclure sans réplication.',
          'Reading the approximate ORs as precise estimates of strong effects; using the score test with extreme case-control imbalance and rare variants (prefer SAIGE); concluding without replication.'),
    ),
  );
  return GenotypeGlmm(tau, alpha, iterations, names, us, vs, betas, ses, pv, result);
}
