import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('gwas_mr');
  final expo = parseGwasSumstats(File('test/reference/gwas_exposition_simule.tsv').readAsStringSync(), source: 'gwas_exposition_simule.tsv');
  final outc = parseGwasSumstats(File('test/reference/gwas_issue_simule.tsv').readAsStringSync(), source: 'gwas_issue_simule.tsv');
  final h = harmoniseGwas(expo, outc);
  const rStatus = {
    'aligned': HarmonisationStatus.aligned,
    'flipped': HarmonisationStatus.flipped,
    'strand': HarmonisationStatus.strand,
    'strand_flipped': HarmonisationStatus.strandFlipped,
    'pal_aligned': HarmonisationStatus.palindromicAligned,
    'pal_flipped': HarmonisationStatus.palindromicFlipped,
    'pal_ambiguous': HarmonisationStatus.palindromicAmbiguous,
    'incompatible': HarmonisationStatus.incompatible,
    'absent': HarmonisationStatus.absent,
  };

  test('lecture : colonnes GWAS-SSF et TwoSampleMR reconnues ; OR → log(OR), allèles en majuscules', () {
    expect(expo.variants.length, 12000);
    expect(expo.columns['id'], 'variant_id');
    expect(expo.fromOddsRatio, isFalse);
    expect(outc.variants.length, 11500);
    expect(outc.columns['ea'], 'A1');
    expect(outc.fromOddsRatio, isTrue);
    expect(outc.variants.every((v) => v.effectAllele == v.effectAllele.toUpperCase()), isTrue);
  });

  test('instruments : seuil 5e-8 puis clumping 10 000 kb = R (mêmes variants, même ordre)', () {
    expect(h.significant, asD(ref['n_significant'])!.round());
    expect([for (final v in h.variants) v.exposure.id], [for (final x in ref['instruments'] as List) x as String]);
  });

  test('harmonisation : statut de chaque instrument et β de l\'issue alignés = R ; tous les cas présents', () {
    final st = ref['status'] as Map;
    for (final v in h.variants) {
      expect(v.status, rStatus[st[v.exposure.id]], reason: v.exposure.id);
    }
    expect(h.counts.values.every((n) => n > 0), isTrue);
    final used = [for (final x in ref['used'] as List) x as String], by = [for (final x in ref['by'] as List) asD(x)!];
    expect([for (final v in h.usable) v.exposure.id], used);
    for (var j = 0; j < by.length; j++) {
      expect(h.usable[j].by, closeRel(by[j], rel: 1e-12));
    }
  });

  test('randomisation mendélienne sur les variants harmonisés = MendelianRandomization (IVW, Egger, médiane)', () {
    final u = h.usable;
    final fit = mendelianRandomization([for (final v in u) v.exposure.beta], [for (final v in u) v.exposure.se], [for (final v in u) v.by!], [for (final v in u) v.byse!],
        names: [for (final v in u) v.exposure.id], iterations: 200);
    final iv = ref['ivw'] as Map, eg = ref['egger'] as Map;
    expect(fit.ivw.estimate, closeRel(asD(iv['estimate'])!, rel: 1e-10));
    expect(fit.ivw.se, closeRel(asD(iv['se'])!, rel: 1e-10));
    expect(fit.egger.estimate, closeRel(asD(eg['estimate'])!, rel: 1e-10));
    expect(fit.egger.se, closeRel(asD(eg['se'])!, rel: 1e-10));
    expect(fit.eggerIntercept.estimate, closeRel(asD(eg['intercept'])!, rel: 1e-10));
    expect(fit.median.estimate, closeRel(asD(ref['median'])!, rel: 1e-10));
    expect(fit.ivw.lower < 0.3 && 0.3 < fit.ivw.upper, isTrue); // θ simulé
  });

  test('tableau pour l\'atelier : instruments écartés sans β ; source et résumé lisibles', () {
    final d = h.toDataset();
    expect(d.rowCount, h.variants.length);
    expect([for (var i = 0; i < d.rowCount; i++) if (d.cell(i, 'beta_x') != null) i].length, h.usable.length);
    expect(d.source, contains('gwas_issue_simule.tsv'));
    expect(h.summary().join('\n'), contains('OR'));
  });

  test('erreurs : colonnes manquantes signalées ; p absente calculée à partir de z ; virgule acceptée', () {
    expect(() => parseGwasSumstats('rsid\tbeta\nrs1\t0.1\n'), throwsFormatException);
    final g = parseGwasSumstats('SNP,A1,A2,BETA,SE\nrs1,a,g,0.1,0.02\nrs2,c,t,NA,0.02\n');
    expect(g.variants.length, 1);
    expect(g.skipped, 1);
    expect(gwasP(g.variants.first), closeRel(5.733031437583878e-7, rel: 1e-9)); // 2·pnorm(-5)
  });
}
