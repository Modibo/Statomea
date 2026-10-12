import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('genetique');
  final ds = parseCsv(File('test/reference/genetique_simule.csv').readAsStringSync()).dataset;
  final snps = [for (final s in ref['snps'] as List) s as String];
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  test('lecture des génotypes et allèle mineur (échantillon entier)', () {
    expect(parseGenotype('A/G'), ('A', 'G'));
    expect(parseGenotype('a|g'), ('A', 'G'));
    expect(parseGenotype('AG'), ('A', 'G'));
    expect(parseGenotype('2'), ('B', 'B'));
    expect(parseGenotype('NA'), isNull);
    expect(parseGenotype('A/G/T'), isNull);
    final minor = ref['minor'] as List, maf = ref['maf'] as List;
    for (var i = 0; i < snps.length; i++) {
      final s = snpData(snps[i], ds.text(snps[i]));
      expect(s.minor, minor[i], reason: snps[i]);
      expect(s.maf, closeRel(asD(maf[i])!, rel: 1e-12), reason: snps[i]);
    }
    expect(() => snpData('x', ['A/G', 'A/T', 'G/G']), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'not_biallelic')));
  });

  void checkVariant(String k) {
    final r = ref[k] as Map;
    final a = snpAssociation(ds, k, 'statut', 'cas');
    final s = a.statistics;
    expect([for (final x in a.inputs['cases'] as List) x], [for (final x in r['geno_cases'] as List) (x as num).toInt()]);
    expect([for (final x in a.inputs['controls'] as List) x], [for (final x in r['geno_controls'] as List) (x as num).toInt()]);
    expect(s['allelic_chi2'], closeRel(asD(r['allelic_chisq'])!, rel: 1e-10));
    expect(s['allelic_p'], closeRel(asD(r['allelic_p'])!, rel: 1e-9));
    expect(s['genotypic_chi2'], closeRel(asD(r['genotypic_chisq'])!, rel: 1e-10));
    expect(s['genotypic_p'], closeRel(asD(r['genotypic_p'])!, rel: 1e-9));
    expect(s['trend_chi2'], closeRel(asD(r['trend_chisq'])!, rel: 1e-10));
    expect(s['trend_p'], closeRel(asD(r['trend_p'])!, rel: 1e-9));
    final or = v(r['allelic_or']), dom = v(r['dominant_or']), rec = v(r['recessive_or']);
    expect([a.estimates[0].value, a.estimates[0].lower, a.estimates[0].upper], [for (final x in or) closeRel(x, rel: 1e-10)]);
    expect([a.estimates[1].value, a.estimates[1].lower, a.estimates[1].upper], [for (final x in dom) closeRel(x, rel: 1e-10)]);
    expect([a.estimates[2].value, a.estimates[2].lower, a.estimates[2].upper], [for (final x in rec) closeRel(x, rel: 1e-10)]);
    // Codominant : OR de Woolf = OR du glm à facteur (modèle saturé).
    final cod = [for (final row in r['codominant'] as List) [for (final x in row as List) asD(x)!]];
    expect(s['het_or'], closeRel(cod[0][0], rel: 1e-7));
    expect(s['hom_or'], closeRel(cod[1][0], rel: 1e-7));
    final h = r['hwe_controls'] as Map;
    expect(s['hwe_controls_p'], closeRel(asD(h['exact'])!, rel: 1e-9));
  }

  test('rs1 (associé) : allélique, génotypique, tendance, modèles, HWE — contre R/HardyWeinberg', () => checkVariant('rs1'));
  test('rs4 (hors Hardy-Weinberg) : association et contrôle de qualité', () {
    checkVariant('rs4');
    final a = snpAssociation(ds, 'rs4', 'statut', 'cas');
    expect(a.alerts.map((x) => x.code), contains('hwe_controls'));
  });
  test('rs2 (génotypes manquants exclus)', () {
    checkVariant('rs2');
    expect(snpAssociation(ds, 'rs2', 'statut', 'cas').alerts.map((x) => x.code), contains('missing_genotypes'));
  });

  test('Hardy-Weinberg : exact, mid-p, χ², F contre HardyWeinberg::HWExact et HWChisq', () {
    for (final k in ['rs1', 'rs4', 'rs2']) {
      final h = (ref[k] as Map)['hwe_controls'] as Map;
      final c = [for (final x in h['counts'] as List) (x as num).toInt()];
      final r = hardyWeinberg(c[0], c[1], c[2]);
      expect(r.statistics['p_exact'], closeRel(asD(h['exact'])!, rel: 1e-9), reason: k);
      expect(r.statistics['p_midp'], closeRel(asD(h['midp'])!, rel: 1e-9), reason: k);
      expect(r.statistics['chi2'], closeRel(asD(h['chisq'])!, rel: 1e-10), reason: k);
      expect(r.statistics['p_chi2'], closeRel(asD(h['chisq_p'])!, rel: 1e-9), reason: k);
      expect(r.statistics['f'], closeRel(asD(h['f'])!, rel: 1e-10), reason: k);
    }
  });

  test('balayage ajusté (âge, sexe) contre glm et p.adjust (Bonferroni, Holm, BH, BY)', () {
    final r = snpScan(ds, snps, 'statut', 'cas', covariates: const [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F')]);
    final b = v(ref['scan_beta']), se = v(ref['scan_se']), p = v(ref['scan_p']);
    for (var k = 0; k < snps.length; k++) {
      expect(r.statistics['beta_${snps[k]}'], closeRel(b[k], rel: 1e-7), reason: snps[k]);
      expect(r.statistics['se_${snps[k]}'], closeRel(se[k], rel: 1e-6), reason: snps[k]);
      // p de Wald : l'écart relatif s'amplifie dans la queue (p ≈ 7·10⁻⁶) à partir des écarts de convergence de glm sur β et ES.
      expect(r.statistics['p_${snps[k]}'], closeRel(p[k], rel: 1e-4), reason: snps[k]);
      expect(r.statistics['padj_${snps[k]}'], closeRel(v(ref['p_bh'])[k], rel: 1e-4), reason: snps[k]);
    }
    for (final (m, key) in [(PAdjust.bonferroni, 'p_bonferroni'), (PAdjust.holm, 'p_holm'), (PAdjust.bh, 'p_bh'), (PAdjust.by, 'p_by')]) {
      final adj = pAdjust(p, m);
      for (var k = 0; k < p.length; k++) {
        expect(adj[k], closeRel(v(ref[key])[k], rel: 1e-12), reason: '$key ${snps[k]}');
      }
    }
    expect(r.interpretation.whatItMeans, contains('rs1'));
    expect(r.checks.first.status, CheckStatus.violated); // rs4 hors HWE
  });

  test('cas limites : allèle rare sans homozygote, effectifs invalides', () {
    final h = hardyWeinberg(90, 10, 0);
    expect(h.statistics['p_exact'], inInclusiveRange(0, 1));
    expect(h.alerts.map((a) => a.code), contains('rare_homozygotes'));
    expect(() => geneticAssociation([1, 2], [3, 4, 5]), throwsA(isA<StatInputError>()));
  });
}
