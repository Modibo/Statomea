/// Stratification de population :
///  - élagage des variants corrélés (déséquilibre de liaison) en fenêtres glissantes, à la manière de
///    `plink --indep-pairwise 50 5 0.2` (règle documentée ci-dessous ; ne prétend pas reproduire PLINK) ;
///  - ACP des génotypes standardisés (Patterson, Price et Reich 2006, EIGENSTRAT) : x = (g − 2p)/√(2p(1 − p)),
///    manquants mis à 0 (moyenne), G = X Xᵀ / m, décomposition propre complète ;
///  - sujets atypiques : |CP| > 6 ET sur l'une des 10 premières composantes (règle par défaut d'EIGENSOFT).
/// Validé contre R (`validation/r/26_acp.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'genotype_io.dart';

/// r² de Pearson entre deux variants (observations complètes deux à deux) ; 0 si l'un est constant.
double _r2(Int8List a, Int8List b) {
  var n = 0;
  var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] < 0 || b[i] < 0) continue;
    n++;
    sa += a[i];
    sb += b[i];
    saa += a[i] * a[i];
    sbb += b[i] * b[i];
    sab += a[i] * b[i];
  }
  if (n < 3) return 0;
  final va = saa - sa * sa / n, vb = sbb - sb * sb / n, cov = sab - sa * sb / n;
  if (va <= 1e-12 || vb <= 1e-12) return 0;
  return cov * cov / (va * vb);
}

double _maf(Int8List g) {
  var s = 0, c = 0;
  for (final x in g) {
    if (x >= 0) {
      s += x;
      c++;
    }
  }
  if (c == 0) return 0;
  final p = s / (2 * c);
  return math.min(p, 1 - p);
}

/// Élagage LD : par chromosome (ordre des positions), fenêtres de [window] variants avançant de [step] ; dans une
/// fenêtre, paires (i < j) encore retenues parcourues dans l'ordre ; si r² > [r2Max], on écarte le variant de plus
/// faible MAF (à égalité, le second). Retourne les indices retenus, dans l'ordre d'origine.
List<int> ldPrune(GenotypeData g, {int window = 50, int step = 5, double r2Max = 0.2}) {
  final keep = List<bool>.filled(g.variantCount, true);
  final maf = [for (final d in g.dosage) _maf(d)];
  final byChrom = <String, List<int>>{};
  for (var j = 0; j < g.variantCount; j++) {
    byChrom.putIfAbsent(g.variants[j].chrom, () => []).add(j);
  }
  for (final idx in byChrom.values) {
    idx.sort((a, b) {
      final k = g.variants[a].pos.compareTo(g.variants[b].pos);
      return k != 0 ? k : a.compareTo(b);
    });
    for (var s = 0; s < idx.length; s += step) {
      final w = idx.sublist(s, math.min(s + window, idx.length));
      for (var a = 0; a < w.length; a++) {
        for (var b = a + 1; b < w.length; b++) {
          final i = w[a], j = w[b];
          if (!keep[i] || !keep[j]) continue;
          if (_r2(g.dosage[i], g.dosage[j]) > r2Max) {
            if (maf[j] <= maf[i]) {
              keep[j] = false;
            } else {
              keep[i] = false;
            }
          }
        }
      }
    }
  }
  return [for (var j = 0; j < g.variantCount; j++) if (keep[j]) j];
}

/// Nombre maximal de sujets pour l'ACP sur l'appareil (décomposition O(n³)).
const maxPcaSamples = 1500;

class GenotypePca {
  final List<String> samples;
  final List<double> eigenvalues; // k premières
  final double trace;
  final List<List<double>> pcs; // n × k, signe : plus grande coordonnée positive
  final List<int> keptVariants;
  final List<int> outliers;
  final AnalysisResult result;
  GenotypePca(this.samples, this.eigenvalues, this.trace, this.pcs, this.keptVariants, this.outliers, this.result);

  /// Composantes en covariables, par identifiant de sujet (pour [genotypeDataset]).
  Map<String, Map<String, String>> covariates(int k) => {
        for (var c = 0; c < math.min(k, eigenvalues.length); c++) 'PC${c + 1}': {for (var i = 0; i < samples.length; i++) samples[i]: pcs[i][c].toString()}
      };
}

/// Matrice de parenté génomique standardisée (GRM) : x = (g − 2p)/√(2p(1 − p)) sur les variants polymorphes de
/// [variants] (tous par défaut), manquants mis à 0 (moyenne), G = XXᵀ/m. Partagée par l'ACP et le modèle mixte.
/// Produit scalaire, sommé dans l'ordre des variants (même ordre que l'ancienne mise à jour de rang 1 : résultats
/// identiques au bit près, ce qui compte pour l'optimum REML plat du modèle mixte). Petite fonction : vite optimisée.
double _dot(Float64List a, Float64List b) {
  var s = 0.0;
  for (var k = 0; k < a.length; k++) {
    s += a[k] * b[k];
  }
  return s;
}

({List<List<double>> grm, int m, double trace}) genotypeGrm(GenotypeData g, {List<int>? variants, int minVariants = 10}) {
  final n = g.sampleCount;
  final cols = <Float64List>[];
  for (final j in variants ?? [for (var v = 0; v < g.variantCount; v++) v]) {
    final d = g.dosage[j];
    var s = 0, c = 0;
    for (final x in d) {
      if (x >= 0) {
        s += x;
        c++;
      }
    }
    if (c == 0) continue;
    final p = s / (2 * c);
    if (p <= 0 || p >= 1) continue;
    final sd = math.sqrt(2 * p * (1 - p));
    cols.add(Float64List.fromList([for (final x in d) x < 0 ? 0.0 : (x - 2 * p) / sd]));
  }
  final m = cols.length;
  if (m < minVariants) throw StatInputError('too_few_variants', tr('Moins de 10 variants polymorphes : matrice de parenté génomique non estimable.', 'Fewer than 10 polymorphic variants: genomic relationship matrix not estimable.'));
  // X (n × m) par lignes de sujets, puis G = XXᵀ par produits scalaires de lignes (accès contigus, en cache).
  final rowsX = [for (var i = 0; i < n; i++) Float64List(m)];
  for (var j = 0; j < m; j++) {
    final col = cols[j];
    for (var i = 0; i < n; i++) {
      rowsX[i][j] = col[i];
    }
  }
  final grm = [for (var i = 0; i < n; i++) Float64List(n)];
  for (var i = 0; i < n; i++) {
    final xi = rowsX[i], gi = grm[i];
    for (var k = i; k < n; k++) {
      gi[k] = _dot(xi, rowsX[k]);
    }
  }
  var trace = 0.0;
  for (var i = 0; i < n; i++) {
    for (var k = i; k < n; k++) {
      grm[i][k] /= m;
      grm[k][i] = grm[i][k];
    }
    trace += grm[i][i];
  }
  return (grm: grm, m: m, trace: trace);
}

GenotypePca genotypePca(GenotypeData g, {int components = 10, bool prune = true, int window = 50, int step = 5, double r2Max = 0.2, double outlierSd = 6}) {
  final n = g.sampleCount;
  if (n < 10) throw StatInputError('n_too_small', tr('Au moins 10 sujets sont requis pour l\'ACP.', 'At least 10 subjects are required for PCA.'));
  if (n > maxPcaSamples) {
    throw StatInputError('too_many_samples', tr('$n sujets : au-delà de $maxPcaSamples, calculer l\'ACP avec PLINK (--pca) ou FlashPCA puis importer les composantes en covariables.',
        '$n subjects: beyond $maxPcaSamples, compute the PCA with PLINK (--pca) or FlashPCA, then import the components as covariates.'));
  }
  final kept = prune ? ldPrune(g, window: window, step: step, r2Max: r2Max) : [for (var j = 0; j < g.variantCount; j++) j];
  final (:grm, :m, :trace) = genotypeGrm(g, variants: kept);
  final eig = symmetricEigen(grm);
  final k = math.min(components, n);
  final pcs = [for (var i = 0; i < n; i++) [for (var c = 0; c < k; c++) eig.vectors[i][c]]];
  for (var c = 0; c < k; c++) {
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (pcs[i][c].abs() > pcs[best][c].abs()) best = i;
    }
    if (pcs[best][c] < 0) {
      for (var i = 0; i < n; i++) {
        pcs[i][c] = -pcs[i][c];
      }
    }
  }
  final values = eig.values.sublist(0, k);
  // Sujets atypiques.
  final outliers = <int>{};
  for (var c = 0; c < k; c++) {
    final col = [for (var i = 0; i < n; i++) pcs[i][c]];
    final mu = col.fold(0.0, (a, b) => a + b) / n;
    final sd = math.sqrt(col.fold(0.0, (a, b) => a + (b - mu) * (b - mu)) / (n - 1));
    for (var i = 0; i < n; i++) {
      if (sd > 0 && ((col[i] - mu) / sd).abs() > outlierSd) outliers.add(i);
    }
  }
  final pct = [for (final v in values) v / trace];
  final caseL = tr('cas', 'case'), ctlL = tr('témoin', 'control');
  final groups = [for (final p in g.phenotype) p == 2 ? caseL : (p == 1 ? ctlL : tr('inconnu', 'unknown'))];
  // Écart entre la 1re valeur propre et la suivante : structure marquée si λ1 dépasse nettement le « bruit ».
  final structured = values.length > 2 && values[0] > 2 * values[2];
  final result = AnalysisResult(
    methodId: 'genotype_pca',
    methodName: tr('ACP des génotypes (stratification de population)', 'Genotype PCA (population stratification)'),
    inputs: {'samples': n, 'variants': g.variantCount, 'prune': prune, 'window': window, 'step': step, 'r2Max': r2Max, 'components': k, 'outlierSd': outlierSd},
    formula: tr(
        'Élagage LD (fenêtres de $window variants, pas de $step, r² > ${fmt(r2Max)} : variant de plus faible MAF écarté) ; x = (g − 2p)/√(2p(1 − p)), manquants à 0 ; '
            'G = XXᵀ/m (m = $m variants) ; composantes = vecteurs propres de G ; part de variance = λ/trace(G) ; atypiques : |CP| > ${fmt(outlierSd)} ET.',
        'LD pruning (windows of $window variants, step $step, r² > ${fmt(r2Max)}: variant with lower MAF removed); x = (g − 2p)/√(2p(1 − p)), missing set to 0; '
            'G = XXᵀ/m (m = $m variants); components = eigenvectors of G; variance share = λ/trace(G); outliers: |PC| > ${fmt(outlierSd)} SD.'),
    estimates: [
      for (var c = 0; c < math.min(3, k); c++) Estimate(tr('Valeur propre CP${c + 1} (${fmtPct(pct[c])} de la variance)', 'Eigenvalue PC${c + 1} (${fmtPct(pct[c])} of variance)'), values[c]),
    ],
    statistics: {
      'variants_used': m.toDouble(),
      'variants_pruned': (g.variantCount - kept.length).toDouble(),
      'trace': trace,
      'outliers': outliers.length.toDouble(),
      for (var c = 0; c < k; c++) 'eigenvalue_${c + 1}': values[c],
    },
    checks: [
      Check('structure', tr('Structure de population apparente', 'Apparent population structure'), structured ? CheckStatus.warning : CheckStatus.ok,
          structured
              ? tr('λ1 = ${fmt(values[0])} dépasse nettement les suivantes : sous-populations probables ; ajuster l\'analyse d\'association sur les premières CP.',
                  'λ1 = ${fmt(values[0])} clearly exceeds the next ones: probable subpopulations; adjust the association analysis for the first PCs.')
              : tr('Pas de composante dominante.', 'No dominant component.')),
      Check('outliers', tr('Sujets atypiques (|CP| > ${fmt(outlierSd)} ET)', 'Outlying subjects (|PC| > ${fmt(outlierSd)} SD)'), outliers.isEmpty ? CheckStatus.ok : CheckStatus.warning,
          outliers.isEmpty ? tr('Aucun.', 'None.') : (outliers.toList()..sort()).map((i) => g.samples[i]).join(', ')),
      Check('ld_pruning', tr('Variants approximativement indépendants', 'Approximately independent variants'), prune ? CheckStatus.ok : CheckStatus.warning,
          prune
              ? tr('${g.variantCount - kept.length} variant(s) écarté(s) par l\'élagage LD.', '${g.variantCount - kept.length} variant(s) removed by LD pruning.')
              : tr('Sans élagage, des blocs de LD peuvent dominer les composantes.', 'Without pruning, LD blocks may dominate the components.')),
    ],
    tables: [
      ResultTable(tr('Valeurs propres', 'Eigenvalues'), [tr('Composante', 'Component'), tr('Valeur propre', 'Eigenvalue'), tr('Part de variance', 'Variance share')], [
        for (var c = 0; c < k; c++) ['PC${c + 1}', fmt(values[c], digits: 4), fmtPct(pct[c])]
      ]),
    ],
    figures: {
      'pca': {
        'pc1': [for (final r in pcs) r[0]],
        'pc2': [for (final r in pcs) k > 1 ? r[1] : 0.0],
        'groups': groups,
        'var1': pct[0],
        'var2': k > 1 ? pct[1] : 0.0,
      },
    },
    log: [tr('$m variants utilisés sur ${g.variantCount} ; $n sujets.', '$m variants used out of ${g.variantCount}; $n subjects.')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Si les cas et les témoins n\'ont pas la même ascendance, tout variant dont la fréquence diffère entre populations paraît associé à la maladie. Les composantes principales résument l\'ascendance ; on les ajoute en covariables.',
          'If cases and controls differ in ancestry, any variant whose frequency differs between populations appears associated with the disease. Principal components summarize ancestry; they are added as covariates.'),
      whatItMeans: tr(
          'CP1 explique ${fmtPct(pct[0])} de la variance génotypique${structured ? ' : structure marquée, à prendre en compte' : ''}. ${outliers.length} sujet(s) atypique(s).',
          'PC1 explains ${fmtPct(pct[0])} of genotypic variance${structured ? ': marked structure, to be accounted for' : ''}. ${outliers.length} outlying subject(s).'),
      notJustified: tr(
          'Interpréter une composante comme une origine ethnique précise ; conclure à l\'absence de stratification sur la seule ACP (vérifier aussi l\'inflation λ du balayage) ; écarter des sujets atypiques sans motif documenté.',
          'Interpreting a component as a precise ethnic origin; concluding there is no stratification from the PCA alone (also check the scan\'s inflation λ); removing outlying subjects without a documented reason.'),
    ),
  );
  return GenotypePca(g.samples, values, trace, pcs, kept, outliers.toList()..sort(), result);
}
