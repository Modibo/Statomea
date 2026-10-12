/// Génétique d'association (variants bialléliques, études cas-témoins) :
///  - lecture des génotypes (« A/G », « A|G », « AG », ou 0/1/2 = nombre d'allèles B) ;
///  - équilibre de Hardy-Weinberg : test exact (Wigginton et al. 2005), χ², coefficient F ;
///  - association d'un variant : test allélique (OR par allèle), génotypique (2 ddl),
///    tendance d'Armitage, modèles dominant, récessif et codominant ;
///  - balayage de plusieurs variants : logistique additive ajustable, correction des tests multiples.
/// L'allèle « à risque » codé est l'allèle MINEUR de l'échantillon entier (convention de PLINK).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/dataset.dart';
import '../i18n.dart';
import '../inference/multiplicity.dart';
import '../inference/proportion.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../regression/design_matrix.dart';
import '../regression/glm.dart';

/// Allèles d'un génotype, ou null s'il est manquant ou illisible.
(String, String)? parseGenotype(String? s) {
  if (s == null) return null;
  final t = s.trim().toUpperCase();
  if (t.isEmpty || isMissingToken(t)) return null;
  if (t == '0' || t == '1' || t == '2') {
    final k = int.parse(t);
    return (k >= 2 ? 'B' : 'A', k >= 1 ? 'B' : 'A');
  }
  final parts = t.split(RegExp(r'[/|]'));
  if (parts.length == 2 && parts.every((p) => p.isNotEmpty)) return (parts[0], parts[1]);
  if (parts.length == 1 && t.length == 2) return (t[0], t[1]);
  return null;
}

/// Résumé d'un variant : allèles, allèle mineur, dosage (nombre d'allèles mineurs) par ligne.
class SnpData {
  final String name, major, minor;
  final List<int?> dosage;
  final int unreadable;
  SnpData(this.name, this.major, this.minor, this.dosage, this.unreadable);
  int get typed => dosage.where((d) => d != null).length;
  double get maf => dosage.fold<int>(0, (a, d) => a + (d ?? 0)) / (2 * typed);

  /// Effectifs [majeur/majeur, hétérozygotes, mineur/mineur] sur les lignes retenues.
  List<int> counts([Iterable<int>? rows]) {
    final c = [0, 0, 0];
    for (final i in rows ?? List<int>.generate(dosage.length, (i) => i)) {
      final d = dosage[i];
      if (d != null) c[d]++;
    }
    return c;
  }
}

SnpData snpData(String name, List<String?> raw) {
  final parsed = [for (final s in raw) parseGenotype(s)];
  final unreadable = [for (var i = 0; i < raw.length; i++) if (parsed[i] == null && raw[i] != null && !isMissingToken(raw[i]!.trim())) i].length;
  final freq = <String, int>{};
  for (final g in parsed) {
    if (g == null) continue;
    freq[g.$1] = (freq[g.$1] ?? 0) + 1;
    freq[g.$2] = (freq[g.$2] ?? 0) + 1;
  }
  if (freq.length > 2) {
    throw StatInputError('not_biallelic',
        tr('« $name » a ${freq.length} allèles (${freq.keys.join(", ")}) : seuls les variants bialléliques sont analysés.',
            '"$name" has ${freq.length} alleles (${freq.keys.join(", ")}): only biallelic variants are analysed.'));
  }
  if (freq.isEmpty) throw StatInputError('no_genotype', tr('« $name » : aucun génotype lisible.', '"$name": no readable genotype.'));
  final alleles = freq.keys.toList()..sort();
  // Allèle mineur : le moins fréquent ; à égalité, le second dans l'ordre alphabétique.
  final minor = alleles.length == 1 ? '—' : (freq[alleles[0]]! < freq[alleles[1]]! ? alleles[0] : alleles[1]);
  final major = alleles.firstWhere((a) => a != minor);
  final dosage = [for (final g in parsed) g == null ? null : (g.$1 == minor ? 1 : 0) + (g.$2 == minor ? 1 : 0)];
  return SnpData(name, major, minor, dosage, unreadable);
}

/// Test exact de Hardy-Weinberg (Wigginton, Cutler et Abecasis 2005) : p bilatéral et mid-p.
({double p, double midp}) hweExact(int nAA, int nAB, int nBB) {
  final n = nAA + nAB + nBB;
  final homr = math.min(nAA, nBB);
  final rare = 2 * homr + nAB;
  if (n == 0 || rare == 0) return (p: 1.0, midp: 1.0);
  final probs = List<double>.filled(rare + 1, 0);
  var mid = (rare * (2 * n - rare) / (2 * n)).floor();
  if (mid % 2 != rare % 2) mid++;
  probs[mid] = 1;
  var sum = 1.0;
  var cr = (rare - mid) ~/ 2, cc = n - mid - cr;
  for (var h = mid; h > 1; h -= 2) {
    probs[h - 2] = probs[h] * h * (h - 1) / (4.0 * (cr + 1) * (cc + 1));
    sum += probs[h - 2];
    cr++;
    cc++;
  }
  cr = (rare - mid) ~/ 2;
  cc = n - mid - cr;
  for (var h = mid; h <= rare - 2; h += 2) {
    probs[h + 2] = probs[h] * 4.0 * cr * cc / ((h + 2.0) * (h + 1.0));
    sum += probs[h + 2];
    cr--;
    cc--;
  }
  for (var i = 0; i <= rare; i++) {
    probs[i] /= sum;
  }
  final obs = probs[nAB];
  var p = 0.0;
  for (final v in probs) {
    if (v <= obs * (1 + 1e-7)) p += v;
  }
  return (p: math.min(1.0, p), midp: math.min(1.0, p - 0.5 * obs));
}

({double chi2, double p, double f}) _hweChi2(int aa, int ab, int bb) {
  final n = (aa + ab + bb).toDouble();
  final p = (2 * aa + ab) / (2 * n), q = 1 - p;
  final e = [n * p * p, 2 * n * p * q, n * q * q];
  final o = [aa, ab, bb];
  var x2 = 0.0;
  for (var i = 0; i < 3; i++) {
    if (e[i] > 0) x2 += (o[i] - e[i]) * (o[i] - e[i]) / e[i];
  }
  return (chi2: x2, p: chiSquareUpper(x2, 1), f: 1 - ab / (2 * n * p * q));
}

/// Équilibre de Hardy-Weinberg à partir des effectifs génotypiques.
AnalysisResult hardyWeinberg(int nAA, int nAB, int nBB, {String major = 'A', String minor = 'B', double level = 0.95, String variant = ''}) {
  final n = nAA + nAB + nBB;
  if (n < 2) throw StatInputError('n_too_small', tr('Au moins 2 génotypes sont requis.', 'At least 2 genotypes are required.'));
  final ex = hweExact(nAA, nAB, nBB);
  final c = _hweChi2(nAA, nAB, nBB);
  final b = 2 * nBB + nAB;
  final w = wilsonCi(b, 2 * n, level: level);
  final q = b / (2 * n);
  final exp = [n * (1 - q) * (1 - q), 2 * n * q * (1 - q), n * q * q];
  final v = variant.isEmpty ? '' : ' ($variant)';
  final dev = ex.p < 0.05;
  return AnalysisResult(
    methodId: 'hardy_weinberg',
    methodName: tr('Équilibre de Hardy-Weinberg$v', 'Hardy-Weinberg equilibrium$v'),
    inputs: {'AA': nAA, 'AB': nAB, 'BB': nBB, 'major': major, 'minor': minor, 'level': level},
    formula: tr(
        'Fréquence allélique q = (2·BB + AB)/(2N). Attendus : N(1−q)², 2Nq(1−q), Nq². Test exact (Wigginton 2005) : somme des probabilités des configurations à hétérozygotes ≤ probabilité observée, à nombre d\'allèles fixé. χ² à 1 ddl sans correction. F = 1 − H_obs/H_att.',
        'Allele frequency q = (2·BB + AB)/(2N). Expected: N(1−q)², 2Nq(1−q), Nq². Exact test (Wigginton 2005): sum of the probabilities of heterozygote configurations ≤ the observed probability, allele counts fixed. 1-df χ² without correction. F = 1 − H_obs/H_exp.'),
    estimates: [
      Estimate(tr('Fréquence de l\'allèle $minor', 'Frequency of allele $minor'), q, lower: w.lower, upper: w.upper, level: level),
      Estimate(tr('Coefficient F (excès d\'homozygotes si > 0)', 'F coefficient (excess homozygosity if > 0)'), c.f),
      Estimate(tr('p exact de Hardy-Weinberg', 'Exact Hardy-Weinberg p'), ex.p, pValue: ex.p),
    ],
    statistics: {'n': n.toDouble(), 'maf': math.min(q, 1 - q), 'q': q, 'f': c.f, 'p_exact': ex.p, 'p_midp': ex.midp, 'chi2': c.chi2, 'p_chi2': c.p},
    checks: [
      Check('hwe', tr('Proportions génotypiques compatibles avec Hardy-Weinberg', 'Genotype proportions compatible with Hardy-Weinberg'),
          dev ? CheckStatus.violated : CheckStatus.ok,
          tr('p exact = ${fmtP(ex.p).replaceFirst("p ", "")} ; F = ${fmt(c.f)}.', 'exact p = ${fmtP(ex.p).replaceFirst("p ", "")}; F = ${fmt(c.f)}.')),
    ],
    alerts: [
      if (dev)
        Alert('hwe_deviation', Severity.caution,
            tr("Écart à Hardy-Weinberg. Chez des témoins, il évoque d'abord une erreur de génotypage, une stratification de la population ou une consanguinité, avant toute explication biologique.",
                'Departure from Hardy-Weinberg. In controls, it first suggests genotyping error, population stratification or inbreeding, before any biological explanation.'),
            suggestion: tr('Vérifier la qualité du génotypage (taux d\'appel, contrôles) et la structure de la population.', 'Check genotyping quality (call rate, controls) and population structure.')),
      if (n * math.min(q, 1 - q) * math.min(q, 1 - q) < 5)
        Alert('rare_homozygotes', Severity.info,
            tr('Peu d\'homozygotes attendus pour l\'allèle rare : le test exact est à préférer au χ².', 'Few expected homozygotes for the rare allele: prefer the exact test to the χ².')),
    ],
    tables: [
      ResultTable(tr('Génotypes', 'Genotypes'), [tr('Génotype', 'Genotype'), tr('Observés', 'Observed'), tr('Attendus', 'Expected')], [
        ['$major/$major', '$nAA', fmt(exp[0])],
        ['$major/$minor', '$nAB', fmt(exp[1])],
        ['$minor/$minor', '$nBB', fmt(exp[2])],
      ]),
      ResultTable(tr('Tests', 'Tests'), ['Test', tr('Statistique', 'Statistic'), 'p'], [
        [tr('Exact (Wigginton)', 'Exact (Wigginton)'), '—', fmtP(ex.p).replaceFirst(RegExp(r'^p\s*=?\s*'), '')],
        ['mid-p', '—', fmtP(ex.midp).replaceFirst(RegExp(r'^p\s*=?\s*'), '')],
        [tr('χ² (1 ddl)', 'χ² (1 df)'), fmt(c.chi2), fmtP(c.p).replaceFirst(RegExp(r'^p\s*=?\s*'), '')],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Contrôle de qualité des données génétiques : sous Hardy-Weinberg, les génotypes se déduisent des fréquences alléliques. Le test exact reste valide pour les allèles rares.',
          'Quality control of genetic data: under Hardy-Weinberg, genotypes follow from allele frequencies. The exact test remains valid for rare alleles.'),
      whatItMeans: tr('Fréquence de l\'allèle $minor ${fmtPct(q)} (IC ${fmtPct(w.lower)} à ${fmtPct(w.upper)}) ; test exact ${fmtP(ex.p)} ; F = ${fmt(c.f)}.',
          'Frequency of allele $minor ${fmtPct(q)} (CI ${fmtPct(w.lower)} to ${fmtPct(w.upper)}); exact test ${fmtP(ex.p)}; F = ${fmt(c.f)}.'),
      notJustified: tr("Conclure à l'équilibre parce que p > 0,05 (faible puissance pour les allèles rares) ; tester Hardy-Weinberg chez les cas pour juger la qualité du génotypage (un écart peut y refléter l'association elle-même).",
          'Concluding equilibrium because p > 0.05 (low power for rare alleles); testing Hardy-Weinberg in cases to judge genotyping quality (a departure there may reflect the association itself).'),
    ),
  );
}

({double or, double lower, double upper}) _woolf(num a, num b, num c, num d, double z) {
  final or = (a * d) / (b * c);
  final s = math.sqrt(1 / a + 1 / b + 1 / c + 1 / d);
  return (or: or, lower: math.exp(math.log(or) - z * s), upper: math.exp(math.log(or) + z * s));
}

/// Association d'un variant biallélique dans une étude cas-témoins, à partir des effectifs
/// génotypiques [majeur/majeur, hétérozygote, mineur/mineur] chez les cas et les témoins.
AnalysisResult geneticAssociation(List<int> cases, List<int> controls,
    {String major = 'A', String minor = 'B', String variant = '', double level = 0.95, int excludedMissing = 0}) {
  if (cases.length != 3 || controls.length != 3 || [...cases, ...controls].any((v) => v < 0)) {
    throw StatInputError('bad_counts', tr('Trois effectifs génotypiques positifs par groupe sont requis.', 'Three non-negative genotype counts per group are required.'));
  }
  final z = normalQuantile(1 - (1 - level) / 2);
  final nCa = cases.fold(0, (a, b) => a + b), nCo = controls.fold(0, (a, b) => a + b);
  if (nCa == 0 || nCo == 0) throw StatInputError('n_too_small', tr('Cas et témoins sont tous deux nécessaires.', 'Both cases and controls are required.'));
  // Allèles : cas (mineur, majeur), témoins (mineur, majeur).
  final aCaB = 2 * cases[2] + cases[1], aCaA = 2 * cases[0] + cases[1];
  final aCoB = 2 * controls[2] + controls[1], aCoA = 2 * controls[0] + controls[1];
  final allelic = _woolf(aCaB, aCaA, aCoB, aCoA, z);
  double chi2Table(List<List<num>> t) {
    final rs = [for (final r in t) r.fold<num>(0, (a, b) => a + b)];
    final cs = [for (var j = 0; j < t.first.length; j++) t.fold<num>(0, (a, r) => a + r[j])];
    final tot = rs.fold<num>(0, (a, b) => a + b);
    var x = 0.0;
    for (var i = 0; i < t.length; i++) {
      for (var j = 0; j < cs.length; j++) {
        final e = rs[i] * cs[j] / tot;
        if (e > 0) x += (t[i][j] - e) * (t[i][j] - e) / e;
      }
    }
    return x;
  }

  final allelicChi2 = chi2Table([
    [aCaA, aCaB],
    [aCoA, aCoB]
  ]);
  final colsNonEmpty = [for (var j = 0; j < 3; j++) if (cases[j] + controls[j] > 0) j];
  final genoChi2 = chi2Table([
    [for (final j in colsNonEmpty) cases[j]],
    [for (final j in colsNonEmpty) controls[j]]
  ]);
  final genoDf = colsNonEmpty.length - 1.0;
  // Tendance d'Armitage (scores 0, 1, 2), comme prop.trend.test.
  final nTot = (nCa + nCo).toDouble();
  final pBar = nCa / nTot;
  final nj = [for (var j = 0; j < 3; j++) cases[j] + controls[j]];
  var tStat = 0.0, sn = 0.0, sn2 = 0.0;
  for (var j = 0; j < 3; j++) {
    tStat += j * (cases[j] - nj[j] * pBar);
    sn += nj[j] * j;
    sn2 += nj[j] * j * j;
  }
  final trendVar = pBar * (1 - pBar) * (sn2 - sn * sn / nTot);
  final trendChi2 = trendVar > 0 ? tStat * tStat / trendVar : 0.0;
  final trendP = chiSquareUpper(trendChi2, 1);
  final dom = _woolf(cases[1] + cases[2], cases[0], controls[1] + controls[2], controls[0], z);
  final rec = _woolf(cases[2], cases[0] + cases[1], controls[2], controls[0] + controls[1], z);
  final het = _woolf(cases[1], cases[0], controls[1], controls[0], z);
  final hom = _woolf(cases[2], cases[0], controls[2], controls[0], z);
  final hweCo = hweExact(controls[0], controls[1], controls[2]);
  final mafCo = aCoB / (2 * nCo);
  final v = variant.isEmpty ? '' : ' — $variant';
  final zeroCell = [...cases, ...controls].contains(0);
  String or3(({double or, double lower, double upper}) o) =>
      o.or.isFinite && o.or > 0 ? '${fmt(o.or)} (${fmt(o.lower)} – ${fmt(o.upper)})' : tr('non estimable (cellule nulle)', 'not estimable (zero cell)');
  String pc(double p) => fmtP(p).replaceFirst(RegExp(r'^p\s*=?\s*'), '');
  return AnalysisResult(
    methodId: 'genetic_association',
    methodName: tr('Association génétique cas-témoins$v', 'Case-control genetic association$v'),
    inputs: {'cases': cases, 'controls': controls, 'major': major, 'minor': minor, 'level': level},
    formula: tr(
        'Allèle à risque codé : allèle mineur $minor. Test allélique : χ² sur le tableau 2 × 2 des allèles (2N copies), OR de Woolf. Génotypique : χ² 2 × 3 (2 ddl). Tendance d\'Armitage : scores 0/1/2, χ² à 1 ddl (comme prop.trend.test). Dominant : $major$minor + $minor$minor contre $major$major ; récessif : $minor$minor contre le reste.',
        'Coded risk allele: minor allele $minor. Allelic test: χ² on the 2 × 2 allele table (2N copies), Woolf OR. Genotypic: 2 × 3 χ² (2 df). Armitage trend: scores 0/1/2, 1-df χ² (as prop.trend.test). Dominant: $major$minor + $minor$minor vs $major$major; recessive: $minor$minor vs the rest.'),
    estimates: [
      Estimate(tr('OR par allèle $minor (allélique)', 'OR per allele $minor (allelic)'), allelic.or,
          lower: allelic.lower, upper: allelic.upper, level: level, pValue: chiSquareUpper(allelicChi2, 1)),
      Estimate(tr('OR dominant', 'Dominant OR'), dom.or, lower: dom.lower, upper: dom.upper, level: level),
      Estimate(tr('OR récessif', 'Recessive OR'), rec.or, lower: rec.lower, upper: rec.upper, level: level),
      Estimate(tr('Fréquence de $minor chez les témoins', 'Frequency of $minor in controls'), mafCo),
    ],
    statistics: {
      'n_cases': nCa.toDouble(),
      'n_controls': nCo.toDouble(),
      'allelic_chi2': allelicChi2,
      'allelic_p': chiSquareUpper(allelicChi2, 1),
      'allelic_or': allelic.or,
      'genotypic_chi2': genoChi2,
      'genotypic_p': chiSquareUpper(genoChi2, genoDf),
      'trend_chi2': trendChi2,
      'trend_p': trendP,
      'dominant_or': dom.or,
      'recessive_or': rec.or,
      'het_or': het.or,
      'hom_or': hom.or,
      'hwe_controls_p': hweCo.p,
      'maf_controls': mafCo,
    },
    checks: [
      Check('hwe_controls', tr('Hardy-Weinberg chez les témoins (qualité du génotypage)', 'Hardy-Weinberg in controls (genotyping quality)'),
          hweCo.p < 0.05 ? CheckStatus.violated : CheckStatus.ok, tr('p exact = ${pc(hweCo.p)}.', 'exact p = ${pc(hweCo.p)}.')),
      Check('allelic_hwe', tr('Test allélique valide (suppose Hardy-Weinberg)', 'Allelic test valid (assumes Hardy-Weinberg)'),
          hweCo.p < 0.05 ? CheckStatus.warning : CheckStatus.ok,
          tr("Le test allélique compte 2 copies par sujet comme indépendantes ; en cas d'écart à Hardy-Weinberg, préférer la tendance d'Armitage.",
              'The allelic test counts 2 copies per subject as independent; under departure from Hardy-Weinberg, prefer the Armitage trend test.')),
      Check('stratification', tr('Absence de stratification de la population', 'No population stratification'), CheckStatus.notAssessed,
          tr('Cas et témoins doivent provenir de la même population (ascendance) ; sinon, ajuster (composantes principales) ou apparier.',
              'Cases and controls must come from the same population (ancestry); otherwise adjust (principal components) or match.')),
    ],
    alerts: [
      if (hweCo.p < 0.05)
        Alert('hwe_controls', Severity.serious,
            tr("Écart à Hardy-Weinberg chez les témoins (p = ${pc(hweCo.p)}) : erreur de génotypage ou stratification probables ; interpréter l'association avec prudence.",
                'Departure from Hardy-Weinberg in controls (p = ${pc(hweCo.p)}): genotyping error or stratification likely; interpret the association with caution.')),
      Alert('one_model', Severity.info,
          tr("Plusieurs modèles génétiques sont montrés : le modèle principal (souvent additif, tendance d'Armitage) doit être fixé AVANT l'analyse ; choisir après coup le modèle le plus significatif gonfle le risque d'erreur.",
              'Several genetic models are shown: the main model (often additive, Armitage trend) must be fixed BEFORE the analysis; choosing the most significant model afterwards inflates the error rate.')),
      if (zeroCell)
        Alert('zero_cell', Severity.caution,
            tr('Cellule nulle : certains OR ne sont pas estimables ; préférer la tendance d\'Armitage ou un test exact.', 'Zero cell: some ORs are not estimable; prefer the Armitage trend test or an exact test.')),
      if (excludedMissing > 0)
        Alert('missing_genotypes', Severity.caution,
            tr('$excludedMissing sujet(s) sans génotype lisible exclu(s).', '$excludedMissing subject(s) without a readable genotype excluded.')),
    ],
    tables: [
      ResultTable(tr('Génotypes', 'Genotypes'), [tr('Groupe', 'Group'), '$major/$major', '$major/$minor', '$minor/$minor', tr('Fréquence de $minor', 'Frequency of $minor')], [
        [tr('Cas', 'Cases'), '${cases[0]}', '${cases[1]}', '${cases[2]}', fmtPct(aCaB / (2 * nCa))],
        [tr('Témoins', 'Controls'), '${controls[0]}', '${controls[1]}', '${controls[2]}', fmtPct(mafCo)],
      ]),
      ResultTable(tr('Modèles génétiques', 'Genetic models'), [tr('Modèle', 'Model'), tr('OR (IC ${(level * 100).round()} %)', 'OR (${(level * 100).round()}% CI)'), 'χ²', 'p'], [
        [tr('Allélique (par copie de $minor)', 'Allelic (per copy of $minor)'), or3(allelic), fmt(allelicChi2), pc(chiSquareUpper(allelicChi2, 1))],
        [tr("Additif — tendance d'Armitage", 'Additive — Armitage trend'), '—', fmt(trendChi2), pc(trendP)],
        [tr('Génotypique (${genoDf.toInt()} ddl)', 'Genotypic (${genoDf.toInt()} df)'), '—', fmt(genoChi2), pc(chiSquareUpper(genoChi2, genoDf))],
        [tr('Codominant : $major$minor vs $major$major', 'Codominant: $major$minor vs $major$major'), or3(het), '—', '—'],
        [tr('Codominant : $minor$minor vs $major$major', 'Codominant: $minor$minor vs $major$major'), or3(hom), '—', '—'],
        [tr('Dominant', 'Dominant'), or3(dom), '—', '—'],
        [tr('Récessif', 'Recessive'), or3(rec), '—', '—'],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Variant biallélique, étude cas-témoins : comparer les fréquences alléliques et génotypiques. La tendance d'Armitage (modèle additif) est le test principal usuel ; elle ne suppose pas Hardy-Weinberg.",
          'Biallelic variant, case-control study: compare allele and genotype frequencies. The Armitage trend test (additive model) is the usual main test; it does not assume Hardy-Weinberg.'),
      whatItMeans: tr(
          "Chaque copie de l'allèle $minor multiplie la cote de la maladie par ${fmt(allelic.or)} (IC ${fmt(allelic.lower)} à ${fmt(allelic.upper)}) ; tendance d'Armitage ${fmtP(trendP)}.",
          'Each copy of allele $minor multiplies the odds of disease by ${fmt(allelic.or)} (CI ${fmt(allelic.lower)} to ${fmt(allelic.upper)}); Armitage trend ${fmtP(trendP)}.'),
      notJustified: tr(
          "Conclure qu'un variant est causal (déséquilibre de liaison avec le vrai variant causal) ; présenter le modèle le plus significatif choisi après coup ; ignorer la correction des tests multiples quand plusieurs variants sont testés ; négliger la réplication dans une cohorte indépendante.",
          'Concluding a variant is causal (linkage disequilibrium with the true causal variant); presenting the most significant model chosen afterwards; ignoring multiple-testing correction when several variants are tested; neglecting replication in an independent cohort.'),
    ),
  );
}

/// Association d'un variant à partir d'un jeu de données (colonne de génotypes + statut cas/témoin).
AnalysisResult snpAssociation(Dataset ds, String snp, String outcome, String caseLevel, {double level = 0.95}) {
  final s = snpData(snp, ds.text(snp));
  final y = ds.text(outcome);
  final excluded = ds.excludedRows;
  final caseRows = <int>[], ctrlRows = <int>[];
  var missing = 0;
  for (var i = 0; i < ds.rowCount; i++) {
    if (excluded.contains(i) || y[i] == null) continue;
    if (s.dosage[i] == null) {
      missing++;
      continue;
    }
    (y[i] == caseLevel ? caseRows : ctrlRows).add(i);
  }
  return geneticAssociation(s.counts(caseRows), s.counts(ctrlRows), major: s.major, minor: s.minor, variant: snp, level: level, excludedMissing: missing);
}

/// Balayage de plusieurs variants : régression logistique additive (dosage de l'allèle mineur),
/// ajustable sur des covariables, puis correction des tests multiples.
/// QQ plot : p observés triés, quantiles attendus `ppoints(n)` (a = 3/8 si n ≤ 10, sinon 1/2) et bande de confiance
/// ponctuelle à [level] (k-ième plus petite p ~ Beta(k, n − k + 1)), tous dans l'ordre croissant des p.
({List<double> observed, List<double> expected, List<double> lower, List<double> upper}) qqPoints(List<double> p, {double level = 0.95}) {
  final o = [for (final v in p) if (v.isFinite) v]..sort();
  final n = o.length;
  final a = n <= 10 ? 3 / 8 : 0.5;
  final alpha = (1 - level) / 2;
  return (
    observed: o,
    expected: [for (var k = 1; k <= n; k++) (k - a) / (n + 1 - 2 * a)],
    lower: [for (var k = 1; k <= n; k++) betaQuantile(alpha, k.toDouble(), (n - k + 1).toDouble())],
    upper: [for (var k = 1; k <= n; k++) betaQuantile(1 - alpha, k.toDouble(), (n - k + 1).toDouble())],
  );
}

/// Indices à tracer quand il y a beaucoup de points : tous ceux de p < 10⁻³, et un sous-échantillon régulier des autres
/// (au plus [maxOthers]) — ce qui ne change pas la lecture d'un Manhattan ou d'un QQ plot.
List<int> _thin(List<double> p, {int maxOthers = 4000}) {
  final others = [for (var i = 0; i < p.length; i++) if (!(p[i] < 1e-3)) i];
  final step = others.length <= maxOthers ? 1 : others.length / maxOthers;
  final kept = <int>{for (var i = 0; i < p.length; i++) if (p[i] < 1e-3) i};
  for (var x = 0.0; x < others.length; x += step) {
    kept.add(others[x.floor()]);
  }
  return kept.toList()..sort();
}

double _mlog10(double v) => v > 0 ? -math.log(v) / math.ln10 : 300;

/// Arrondi des coordonnées de figure (lecture inchangée, résultats et projets bien plus légers).
double _r4(double v) => (v * 1e4).roundToDouble() / 1e4;

/// Figures d'un balayage de variants : QQ plot (≥ 10 variants) et Manhattan plot (si les positions sont connues).
/// Partagées par le balayage logistique et le modèle mixte.
Map<String, Object?> gwasFigures(List<String> names, List<double> p, {double? lambda, Map<String, (String, int)>? positions, double level = 0.95}) => {
      if (p.length >= 10) 'qq': () {
        final q = qqPoints(p, level: level);
        final keep = _thin(q.observed, maxOthers: 1500);
        return {
          'observed': [for (final i in keep) _r4(_mlog10(q.observed[i]))],
          'expected': [for (final i in keep) _r4(_mlog10(q.expected[i]))],
          'bandHigh': [for (final i in keep) _r4(_mlog10(q.lower[i]))],
          'bandLow': [for (final i in keep) _r4(_mlog10(q.upper[i]))],
          'lambda': ?lambda,
          'n': p.length,
        };
      }(),
      if (positions != null && p.length >= 2) 'manhattan': () {
        final keep = _thin(p);
        return {
          'chrom': [for (final i in keep) positions[names[i]]?.$1 ?? '?'],
          'pos': [for (final i in keep) positions[names[i]]?.$2 ?? i],
          'logp': [for (final i in keep) _r4(_mlog10(p[i]))],
          // Noms seulement pour les points susceptibles d'être étiquetés (p < 10⁻⁵).
          'names': [for (final i in keep) p[i] < 1e-5 ? names[i] : ''],
          'genomeWide': 5e-8,
          'suggestive': 1e-5,
        };
      }(),
    };

/// Inflation génomique λ (contrôle génomique) à partir de statistiques χ²₁ ; null sous 50 variants.
double? genomicLambda(List<double> chi2) {
  if (chi2.length < 50) return null;
  final c = [...chi2]..sort();
  final med = c.length.isOdd ? c[c.length ~/ 2] : (c[c.length ~/ 2 - 1] + c[c.length ~/ 2]) / 2;
  return med / 0.45493642311957283;
}

AnalysisResult snpScan(Dataset ds, List<String> snps, String outcome, String caseLevel,
    {List<TermSpec> covariates = const [], PAdjust correction = PAdjust.bh, double level = 0.95, Map<String, (String, int)>? positions, List<double>? chi2Out, List<double>? zOut, Map<String, SnpData>? parsedSnps}) {
  if (snps.isEmpty) throw StatInputError('no_snp', tr('Choisir au moins un variant.', 'Choose at least one variant.'));
  final z = normalQuantile(1 - (1 - level) / 2);
  final rows = <(SnpData, double, double, double, int, double)>[]; // variant, β, ES, p, n, HWE témoins
  final y = ds.text(outcome);
  // Table minimale (issue, covariables, dosage) : copier toute la table à chaque variant coûtait O(variants²).
  // Les lignes exclues sont retirées d'emblée ; le dictionnaire (types, références) de l'utilisateur est conservé.
  const dosageCol = '__dosage__';
  final keepCols = {outcome, for (final c in covariates) c.variable}.toList();
  final excluded = ds.excludedRows;
  final rowIdx = [for (var i = 0; i < ds.rowCount; i++) if (!excluded.contains(i)) i];
  final base = [for (final i in rowIdx) [for (final n in keepCols) ds.cell(i, n)]];
  final dict = {for (final n in keepCols) n: ds.dictionary[n]!, dosageCol: Variable(dosageCol, type: VarType.numeric)};
  // Chemin rapide : la matrice de l'issue et des covariables est construite une fois ; pour un variant sans génotype
  // manquant sur ces lignes, seule la colonne de dosage (insérée après la constante, comme dans le chemin complet) change.
  DesignMatrix? baseDesign;
  try {
    baseDesign = buildDesign(Dataset(keepCols, base, source: ds.source, dictionary: {for (final n in keepCols) n: dict[n]!}),
        ModelFormula(outcome, covariates, eventLevel: caseLevel), binaryOutcome: true);
  } on StatInputError {
    baseDesign = null;
  }
  final ctrl = [for (var i = 0; i < ds.rowCount; i++) if (y[i] != null && y[i] != caseLevel && !excluded.contains(i)) i];
  // Matrice du chemin rapide allouée une fois : seule la colonne 1 (dosage) est réécrite à chaque variant.
  final bd0 = baseDesign;
  final xFast = bd0 == null ? const <Float64List>[] : [for (final row in bd0.x) Float64List.fromList([row[0], 0, ...row.skip(1)])];
  final dataRow = bd0 == null ? const <int>[] : [for (final k in bd0.rows) rowIdx[k]];
  for (final name in snps) {
    // [parsedSnps] : génotypes déjà lus (plusieurs balayages d'une même table), complété au passage.
    final s = parsedSnps == null ? snpData(name, ds.text(name)) : (parsedSnps[name] ??= snpData(name, ds.text(name)));
    final bd = baseDesign;
    late final double b, se;
    late final int nUsed;
    if (bd != null && dataRow.every((i) => s.dosage[i] != null)) {
      for (var r = 0; r < xFast.length; r++) {
        xFast[r][1] = s.dosage[dataRow[r]]!.toDouble();
      }
      final fit = fitLogistic(xFast, bd.y, keepTrace: false);
      b = fit.beta[1];
      se = math.sqrt(fit.cov.get(1, 1));
      nUsed = xFast.length;
    } else {
      final aug = Dataset([...keepCols, dosageCol], [
        for (var k = 0; k < rowIdx.length; k++) [...base[k], s.dosage[rowIdx[k]]?.toString()]
      ], source: ds.source, dictionary: dict);
      final d = buildDesign(aug, ModelFormula(outcome, [const TermSpec(dosageCol), ...covariates], eventLevel: caseLevel), binaryOutcome: true);
      final fit = fitLogistic(d.x, d.y, keepTrace: false);
      final j = d.columns.indexOf(dosageCol);
      b = fit.beta[j];
      se = math.sqrt(fit.cov.get(j, j));
      nUsed = d.n;
    }
    final c = s.counts(ctrl);
    rows.add((s, b, se, normalTwoSidedP(b / se), nUsed, hweExact(c[0], c[1], c[2]).p));
  }
  final p = [for (final r in rows) r.$4];
  // χ² et z de Wald par variant, dans l'ordre de [snps] (régression LD score et corrélation génétique sur le balayage complet).
  chi2Out?.addAll([for (final r in rows) (r.$2 / r.$3) * (r.$2 / r.$3)]);
  zOut?.addAll([for (final r in rows) r.$2 / r.$3]);
  final adj = pAdjust(p, correction);
  final sig = [for (var k = 0; k < rows.length; k++) if (adj[k] < 0.05) rows[k].$1.name];
  final hweBad = [for (final r in rows) if (r.$6 < 1e-3) r.$1.name];
  // Inflation génomique (contrôle génomique, Devlin et Roeder 1999) : médiane des χ² de Wald / médiane de χ²₁.
  // Significative seulement sur de nombreux variants (≥ 50).
  final chi2 = [for (final r in rows) (r.$2 / r.$3) * (r.$2 / r.$3)]..sort();
  final lambdaGc = rows.length < 50
      ? null
      : (chi2.length.isOdd ? chi2[chi2.length ~/ 2] : (chi2[chi2.length ~/ 2 - 1] + chi2[chi2.length ~/ 2]) / 2) / 0.45493642311957283;
  final adjustedForPcs = covariates.any((c) => RegExp(r'^PC\d+$').hasMatch(c.variable));
  // Balayages étendus (> 1 000 variants) : le détail par variant est limité aux meilleurs p (estimations 50,
  // tableau 200, statistiques 500) pour garder un projet léger ; λ et les figures portent sur tous les variants.
  final big = rows.length > 1000;
  final gwCount = rows.where((r) => r.$4 < 5e-8).length;
  final byP = [for (var k = 0; k < rows.length; k++) k]..sort((a, b) {
      final c = rows[a].$4.compareTo(rows[b].$4);
      return c != 0 ? c : a.compareTo(b);
    });
  final estIdx = big ? byP.take(50).toList() : [for (var k = 0; k < rows.length; k++) k];
  final statIdx = big ? byP.take(500).toList() : estIdx;
  final tableIdx = big ? byP.take(200).toList() : estIdx;
  String names10(List<String> l) => l.length <= 10 ? l.join(', ') : '${l.take(10).join(', ')}… (${l.length})';
  String pc(double v) => fmtP(v).replaceFirst(RegExp(r'^p\s*=?\s*'), '');
  final covText = covariates.isEmpty ? tr('sans ajustement', 'unadjusted') : tr('ajusté sur ${covariates.map((c) => c.variable).join(", ")}', 'adjusted for ${covariates.map((c) => c.variable).join(", ")}');
  return AnalysisResult(
    methodId: 'snp_scan',
    methodName: tr('Balayage de variants : logistique additive ($covText)', 'Variant scan: additive logistic regression ($covText)'),
    inputs: {'snps': snps, 'outcome': outcome, 'caseLevel': caseLevel, 'covariates': [for (final c in covariates) c.toJson()], 'correction': correction.name, 'level': level},
    formula: tr(
        'Pour chaque variant : logit P(cas) = β₀ + β·dosage + covariables, dosage = nombre d\'allèles mineurs (0, 1, 2) ; OR par allèle = exp(β), IC de Wald ; correction : ${pAdjustLabel(correction)}.',
        'For each variant: logit P(case) = β₀ + β·dosage + covariates, dosage = number of minor alleles (0, 1, 2); OR per allele = exp(β), Wald CI; correction: ${pAdjustLabel(correction)}.'),
    estimates: [
      for (final k in estIdx)
        Estimate(tr('OR par allèle ${rows[k].$1.minor} — ${rows[k].$1.name}', 'OR per allele ${rows[k].$1.minor} — ${rows[k].$1.name}'), math.exp(rows[k].$2),
            lower: math.exp(rows[k].$2 - z * rows[k].$3), upper: math.exp(rows[k].$2 + z * rows[k].$3), level: level, pValue: rows[k].$4),
    ],
    statistics: {
      'variants_tested': rows.length.toDouble(),
      for (final k in statIdx) ...{
        'beta_${rows[k].$1.name}': rows[k].$2,
        'se_${rows[k].$1.name}': rows[k].$3,
        'p_${rows[k].$1.name}': rows[k].$4,
        'padj_${rows[k].$1.name}': adj[k],
        'maf_${rows[k].$1.name}': rows[k].$1.maf,
        'hwe_${rows[k].$1.name}': rows[k].$6,
      },
      'lambda_gc': ?lambdaGc,
      'n_genome_wide': gwCount.toDouble(),
    },
    log: [
      if (big)
        tr('Balayage de ${rows.length} variants : détail conservé pour les 500 plus petits p (estimations : 50 ; tableau : 200) ; λ et figures sur tous les variants.',
            'Scan of ${rows.length} variants: detail kept for the 500 smallest p (estimates: 50; table: 200); λ and figures over all variants.'),
    ],
    checks: [
      Check('hwe_controls', tr('Hardy-Weinberg chez les témoins (seuil 10⁻³)', 'Hardy-Weinberg in controls (threshold 10⁻³)'),
          hweBad.isEmpty ? CheckStatus.ok : CheckStatus.violated,
          hweBad.isEmpty ? tr('Aucun variant en écart marqué.', 'No variant with a marked departure.') : tr('Écart marqué : ${names10(hweBad)}.', 'Marked departure: ${names10(hweBad)}.')),
      if (lambdaGc == null)
        Check('stratification', tr('Absence de stratification de la population', 'No population stratification'), CheckStatus.notAssessed,
            tr('À contrôler (ascendance commune, composantes principales comme covariables) ; l\'inflation λ n\'est interprétable qu\'à partir d\'environ 50 variants.',
                'To be controlled (common ancestry, principal components as covariates); the inflation λ is interpretable only from about 50 variants.'))
      else
        Check('stratification', tr('Inflation génomique λ ≤ 1,10', 'Genomic inflation λ ≤ 1.10'), lambdaGc <= 1.1 ? CheckStatus.ok : CheckStatus.warning,
            tr('λ = ${fmt(lambdaGc, digits: 3)}${lambdaGc > 1.1 ? (adjustedForPcs ? ' malgré l\'ajustement sur les CP : stratification résiduelle, parenté ou vrai signal polygénique' : ' : stratification ou parenté probables ; ajuster sur les composantes principales') : ''}.',
                'λ = ${fmt(lambdaGc, digits: 3)}${lambdaGc > 1.1 ? (adjustedForPcs ? ' despite PC adjustment: residual stratification, relatedness or true polygenic signal' : ': stratification or relatedness likely; adjust for principal components') : ''}.')),
    ],
    alerts: [
      if (hweBad.isNotEmpty)
        Alert('hwe_controls', Severity.serious,
            tr('Écart à Hardy-Weinberg chez les témoins pour ${names10(hweBad)} : vérifier le génotypage avant d\'interpréter.', 'Departure from Hardy-Weinberg in controls for ${names10(hweBad)}: check genotyping before interpreting.')),
      Alert('replication', Severity.info,
          tr('Une association issue d\'un balayage est exploratoire tant qu\'elle n\'est pas répliquée dans une cohorte indépendante.', 'An association from a scan is exploratory until replicated in an independent cohort.')),
    ],
    tables: [
      ResultTable(big ? tr('Variants : les ${tableIdx.length} plus significatifs sur ${rows.length}', 'Variants: the ${tableIdx.length} most significant of ${rows.length}') : tr('Variants', 'Variants'), [
        tr('Variant', 'Variant'),
        tr('Allèle mineur', 'Minor allele'),
        'MAF',
        'n',
        tr('OR par allèle (IC ${(level * 100).round()} %)', 'OR per allele (${(level * 100).round()}% CI)'),
        'p',
        tr('p ajusté', 'adjusted p'),
        tr('HWE témoins', 'HWE controls'),
      ], [
        for (final k in tableIdx)
          [
            rows[k].$1.name,
            rows[k].$1.minor,
            fmt(rows[k].$1.maf),
            '${rows[k].$5}',
            '${fmt(math.exp(rows[k].$2))} (${fmt(math.exp(rows[k].$2 - z * rows[k].$3))} – ${fmt(math.exp(rows[k].$2 + z * rows[k].$3))})',
            pc(rows[k].$4),
            pc(adj[k]),
            pc(rows[k].$6),
          ]
      ]),
    ],
    figures: gwasFigures([for (final r in rows) r.$1.name], p, lambda: lambdaGc, positions: positions, level: level),
    interpretation: Interpretation(
      whyThisMethod: tr('Plusieurs variants testés : chaque test est un modèle logistique additif ; la correction (${pAdjustLabel(correction)}) contrôle le risque de fausses découvertes lié à la multiplicité.',
          'Several variants tested: each test is an additive logistic model; the correction (${pAdjustLabel(correction)}) controls the false-discovery risk due to multiplicity.'),
      whatItMeans: sig.isEmpty
          ? tr('Aucun variant ne reste associé au seuil de 5 % après correction.', 'No variant remains associated at the 5% level after correction.')
          : tr('Variant(s) associé(s) au seuil de 5 % après correction : ${names10(sig)}.${gwCount > 0 ? ' $gwCount au seuil pangénomique 5 × 10⁻⁸.' : ''}',
              'Variant(s) associated at the 5% level after correction: ${names10(sig)}.${gwCount > 0 ? ' $gwCount at the genome-wide threshold 5 × 10⁻⁸.' : ''}'),
      notJustified: tr('Interpréter les p non corrigés ; conclure à la causalité d\'un variant ; ignorer la réplication et la stratification.',
          'Interpreting uncorrected p-values; concluding a variant is causal; ignoring replication and stratification.'),
    ),
  );
}
