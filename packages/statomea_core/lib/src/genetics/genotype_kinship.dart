/// Apparentement entre sujets : coefficient de parenté KING-robust (Manichaikul et al. 2010, estimateur de KING et
/// de `plink2 --make-king`) et IBS0, classement par degré, choix d'un ensemble maximal de sujets non apparentés.
///   φ = (N_Aa,Aa − 2 N_AA,aa) / (2 N_Aa(i)) + 1/2 − (N_Aa(i) + N_Aa(j)) / (4 N_Aa(i)), N_Aa(i) ≤ N_Aa(j),
///   comptes sur les variants non manquants chez les deux sujets ; IBS0 = N_AA,aa / N.
/// Seuils de KING : > 0,354 doublon ou jumeaux monozygotes ; > 0,177 1er degré ; > 0,0884 2e ; > 0,0442 3e.
/// Calcul par masques de bits (mots de 32 bits, compatibles avec le web). Validé contre SNPRelate
/// (`snpgdsIBDKING`, `validation/r/27_parente.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../model/result.dart';
import 'genotype_io.dart';

/// Nombre de bits à 1 d'un mot de 32 bits (sans multiplication : exact aussi en JavaScript).
int _popcount(int x) {
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  x = x + (x >> 8);
  x = x + (x >> 16);
  return x & 0x3F;
}

class KinshipPair {
  final int i, j;
  final double phi, ibs0;
  const KinshipPair(this.i, this.j, this.phi, this.ibs0);

  /// 0 doublon/jumeaux MZ, 1, 2, 3 ; null si non apparentés au sens de KING.
  int? get degree => phi > 0.354 ? 0 : (phi > 0.177 ? 1 : (phi > 0.0884 ? 2 : (phi > 0.0442 ? 3 : null)));
}

String kinshipDegreeLabel(int? d, double ibs0) => switch (d) {
      0 => tr('doublon ou jumeaux monozygotes', 'duplicate or monozygotic twins'),
      1 => ibs0 < 0.005 ? tr('1er degré (parent–enfant)', '1st degree (parent–offspring)') : tr('1er degré (frères/sœurs)', '1st degree (full siblings)'),
      2 => tr('2e degré', '2nd degree'),
      3 => tr('3e degré', '3rd degree'),
      _ => tr('non apparentés', 'unrelated'),
    };

class GenotypeKinship {
  final int n;

  /// φ et IBS0 pour toutes les paires i < j, rangées ligne par ligne.
  final Float64List phiUpper, ibs0Upper;
  final List<KinshipPair> related; // φ > 0,0442
  final List<int> removed;
  final AnalysisResult result;
  GenotypeKinship(this.n, this.phiUpper, this.ibs0Upper, this.related, this.removed, this.result);

  int _k(int i, int j) => i * n - i * (i + 1) ~/ 2 + (j - i - 1);
  double phi(int i, int j) => i < j ? phiUpper[_k(i, j)] : phiUpper[_k(j, i)];
}

/// Limite de travail (paires × mots de 32 bits) pour un calcul raisonnable sur l'appareil.
const maxKinshipWork = 3e9;

GenotypeKinship genotypeKinship(GenotypeData g, {double exclusionThreshold = 0.0884}) {
  final n = g.sampleCount, m = g.variantCount;
  if (n < 2 || m < 100) throw StatInputError('n_too_small', tr('Au moins 2 sujets et 100 variants sont requis.', 'At least 2 subjects and 100 variants are required.'));
  final words = (m + 31) >> 5;
  if (n * (n - 1) / 2 * words > maxKinshipWork) {
    throw StatInputError('too_large', tr('Trop de sujets × variants pour l\'appareil : utiliser KING ou plink2 --make-king, puis importer la liste des apparentés.',
        'Too many subjects × variants for the device: use KING or plink2 --make-king, then import the list of related subjects.'));
  }
  Uint32List mask() => Uint32List(n * words);
  final het = mask(), h0 = mask(), h2 = mask(), nm = mask();
  for (var v = 0; v < m; v++) {
    final w = v >> 5, bit = 1 << (v & 31);
    final d = g.dosage[v];
    for (var i = 0; i < n; i++) {
      final x = d[i];
      if (x < 0) continue;
      final o = i * words + w;
      nm[o] |= bit;
      if (x == 1) {
        het[o] |= bit;
      } else if (x == 0) {
        h0[o] |= bit;
      } else {
        h2[o] |= bit;
      }
    }
  }
  final callRate = [for (var i = 0; i < n; i++) () {
    var c = 0;
    for (var w = 0; w < words; w++) {
      c += _popcount(nm[i * words + w]);
    }
    return c / m;
  }()];
  final np = n * (n - 1) ~/ 2;
  final phiU = Float64List(np), ibsU = Float64List(np);
  final related = <KinshipPair>[];
  var k = 0;
  for (var i = 0; i < n; i++) {
    final oi = i * words;
    for (var j = i + 1; j < n; j++) {
      final oj = j * words;
      var hh = 0, opp = 0, hi = 0, hj = 0, both = 0;
      for (var w = 0; w < words; w++) {
        final ai = het[oi + w], aj = het[oj + w], ni = nm[oi + w], nj = nm[oj + w];
        hh += _popcount(ai & aj);
        opp += _popcount((h0[oi + w] & h2[oj + w]) | (h2[oi + w] & h0[oj + w]));
        hi += _popcount(ai & nj);
        hj += _popcount(aj & ni);
        both += _popcount(ni & nj);
      }
      final hMin = math.min(hi, hj), hMax = math.max(hi, hj);
      final phi = hMin == 0 ? double.nan : (hh - 2 * opp) / (2 * hMin) + 0.5 - (hMin + hMax) / (4 * hMin);
      final ibs0 = both == 0 ? double.nan : opp / both;
      phiU[k] = phi;
      ibsU[k] = ibs0;
      k++;
      if (phi > 0.0442) related.add(KinshipPair(i, j, phi, ibs0));
    }
  }
  // Ensemble maximal non apparenté (glouton) : retirer le sujet impliqué dans le plus de paires au-dessus du seuil ;
  // à égalité, le plus faible taux d'appel, puis le dernier dans le fichier.
  final keep = List<bool>.filled(n, true);
  for (;;) {
    final cnt = List<int>.filled(n, 0);
    var any = false;
    for (final p in related) {
      if (p.phi > exclusionThreshold && keep[p.i] && keep[p.j]) {
        cnt[p.i]++;
        cnt[p.j]++;
        any = true;
      }
    }
    if (!any) break;
    final maxC = cnt.reduce(math.max);
    var cand = [for (var i = 0; i < n; i++) if (cnt[i] == maxC) i];
    final minCall = cand.map((i) => callRate[i]).reduce(math.min);
    cand = [for (final i in cand) if (callRate[i] == minCall) i];
    keep[cand.last] = false;
  }
  final removed = [for (var i = 0; i < n; i++) if (!keep[i]) i];
  final byDegree = [for (var d = 0; d <= 3; d++) related.where((p) => p.degree == d).length];
  String id(int i) => g.samples[i];
  final result = AnalysisResult(
    methodId: 'genotype_kinship',
    methodName: tr('Apparentement entre sujets (KING-robust)', 'Relatedness between subjects (KING-robust)'),
    inputs: {'samples': n, 'variants': m, 'exclusionThreshold': exclusionThreshold},
    formula: tr(
        'φ = (N_Aa,Aa − 2·N_AA,aa)/(2·N_Aa(i)) + 1/2 − (N_Aa(i) + N_Aa(j))/(4·N_Aa(i)), N_Aa(i) ≤ N_Aa(j), sur les variants non manquants chez les deux sujets ; '
            'IBS0 = N_AA,aa/N. Degrés (KING) : > 0,354 doublon/MZ ; > 0,177 1er ; > 0,0884 2e ; > 0,0442 3e. Exclusion gloutonne au-delà de φ = ${fmt(exclusionThreshold, digits: 4)}.',
        'φ = (N_Aa,Aa − 2·N_AA,aa)/(2·N_Aa(i)) + 1/2 − (N_Aa(i) + N_Aa(j))/(4·N_Aa(i)), N_Aa(i) ≤ N_Aa(j), over variants non-missing in both subjects; '
            'IBS0 = N_AA,aa/N. Degrees (KING): > 0.354 duplicate/MZ; > 0.177 1st; > 0.0884 2nd; > 0.0442 3rd. Greedy exclusion beyond φ = ${fmt(exclusionThreshold, digits: 4)}.'),
    estimates: [
      Estimate(tr('Paires apparentées (≤ 3e degré)', 'Related pairs (≤ 3rd degree)'), related.length.toDouble()),
      Estimate(tr('Sujets à écarter pour un ensemble non apparenté', 'Subjects to remove for an unrelated set'), removed.length.toDouble()),
    ],
    statistics: {
      'pairs_duplicate': byDegree[0].toDouble(),
      'pairs_degree1': byDegree[1].toDouble(),
      'pairs_degree2': byDegree[2].toDouble(),
      'pairs_degree3': byDegree[3].toDouble(),
      'removed': removed.length.toDouble(),
      'kept': (n - removed.length).toDouble(),
    },
    checks: [
      Check('duplicates', tr('Absence de doublons', 'No duplicates'), byDegree[0] == 0 ? CheckStatus.ok : CheckStatus.violated,
          byDegree[0] == 0
              ? tr('Aucune paire au-delà de φ = 0,354.', 'No pair beyond φ = 0.354.')
              : tr('${byDegree[0]} paire(s) : doublons d\'échantillon (erreur de manipulation) ou jumeaux monozygotes, à vérifier au laboratoire.',
                  '${byDegree[0]} pair(s): sample duplicates (handling error) or monozygotic twins, to check in the laboratory.')),
      Check('density', tr('Densité de variants suffisante pour le 3e degré', 'Variant density sufficient for 3rd degree'), m >= 10000 ? CheckStatus.ok : CheckStatus.warning,
          m >= 10000
              ? tr('$m variants.', '$m variants.')
              : tr('$m variants : l\'estimateur est trop bruité pour distinguer le 3e degré des non apparentés (faux positifs attendus) ; 1er et 2e degrés restent fiables.',
                  '$m variants: the estimator is too noisy to distinguish 3rd degree from unrelated (false positives expected); 1st and 2nd degrees remain reliable.')),
      Check('declared', tr('Concordance avec les liens déclarés', 'Agreement with declared relationships'), CheckStatus.notAssessed,
          tr('Comparer aux pedigrees déclarés : un apparentement inattendu peut révéler une erreur d\'échantillon.', 'Compare with declared pedigrees: unexpected relatedness can reveal a sample error.')),
    ],
    tables: [
      ResultTable(tr('Paires apparentées', 'Related pairs'), [tr('Sujet 1', 'Subject 1'), tr('Sujet 2', 'Subject 2'), 'φ (KING)', 'IBS0', tr('Relation estimée', 'Estimated relationship')], [
        for (final p in [...related]..sort((a, b) => b.phi.compareTo(a.phi))) [id(p.i), id(p.j), fmt(p.phi, digits: 4), fmt(p.ibs0, digits: 4), kinshipDegreeLabel(p.degree, p.ibs0)]
      ]),
      ResultTable(tr('Sujets écartés (ensemble non apparenté)', 'Subjects removed (unrelated set)'), [tr('Sujet', 'Subject')], [for (final i in removed) [id(i)]]),
    ],
    figures: {
      'king': {
        'phi': [for (final p in related) p.phi],
        'ibs0': [for (final p in related) p.ibs0],
        'background_phi': [for (var q = 0; q < phiU.length; q += math.max(1, phiU.length ~/ 2000)) (phiU[q] * 1e4).roundToDouble() / 1e4],
        'background_ibs0': [for (var q = 0; q < ibsU.length; q += math.max(1, ibsU.length ~/ 2000)) (ibsU[q] * 1e4).roundToDouble() / 1e4],
      },
    },
    log: [tr('$np paires évaluées sur $m variants.', '$np pairs assessed over $m variants.')],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Les analyses d\'association et l\'ACP supposent des sujets indépendants : des apparentés partagent des génotypes, ce qui gonfle les associations et déforme les composantes. KING-robust reste valable en présence de structure de population.',
          'Association analyses and PCA assume independent subjects: relatives share genotypes, which inflates associations and distorts components. KING-robust remains valid in the presence of population structure.'),
      whatItMeans: tr(
          '${byDegree[0]} doublon(s), ${byDegree[1]} paire(s) au 1er degré, ${byDegree[2]} au 2e, ${byDegree[3]} au 3e. Écarter ${removed.length} sujet(s) donne un ensemble de ${n - removed.length} sujets sans apparentement au-delà du 2e degré.',
          '${byDegree[0]} duplicate(s), ${byDegree[1]} 1st-degree pair(s), ${byDegree[2]} 2nd-degree, ${byDegree[3]} 3rd-degree. Removing ${removed.length} subject(s) gives a set of ${n - removed.length} subjects without relatedness beyond 2nd degree.'),
      notJustified: tr(
          'Déduire un lien de parenté précis (père, oncle…) du seul φ ; garder deux doublons comme deux sujets ; écarter des apparentés sans le documenter (préférer, si nécessaire, un modèle mixte qui les conserve).',
          'Inferring a precise relationship (father, uncle…) from φ alone; keeping two duplicates as two subjects; removing relatives without documenting it (prefer, if needed, a mixed model that keeps them).'),
    ),
  );
  return GenotypeKinship(n, phiU, ibsU, related, removed, result);
}
