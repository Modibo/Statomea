import 'dart:io';
import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('genotypes');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  List<int> idx(Object? l) => [for (final x in l as List) (x as num).toInt() - 1]; // R : indices à partir de 1
  final vcf = parseVcf(File('$dir/simule.vcf').readAsStringSync());
  final bed = parsePlinkBed(File('$dir/simule.bed').readAsBytesSync(), File('$dir/simule.bim').readAsStringSync(), File('$dir/simule.fam').readAsStringSync());
  final ped = parsePlinkPed(File('$dir/simule.ped').readAsStringSync(), File('$dir/simule.map').readAsStringSync());

  test('VCF : sujets, variants bialléliques, dosages ALT (relecture vcfR identique dans le script R)', () {
    expect(vcf.samples, ref['ids']);
    expect(vcf.variantCount, 250);
    expect(vcf.notes.single, contains('2 site(s) multiallélique(s)'));
    expect([for (final x in vcf.variants) x.id], ref['snp']);
    expect([for (final x in vcf.variants) x.counted], ref['alt']);
    final head = ref['dosage_first'] as List; // 5 sujets × 6 variants
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 6; j++) {
        expect(vcf.dosage[j][i], (head[i] as List)[j], reason: 'sujet $i variant $j');
      }
    }
  });

  test('PLINK binaire : mêmes dosages que le VCF (A1 = ALT écrit par genio), sexe et phénotype du .fam', () {
    expect(bed.samples, vcf.samples);
    expect([for (final x in bed.variants) x.counted], ref['alt']);
    for (var j = 0; j < 250; j++) {
      expect(bed.dosage[j], vcf.dosage[j], reason: bed.variants[j].id);
    }
    expect(bed.phenotype.where((p) => p == 2).length, 150);
    expect(bed.sex.every((s) => s == 1 || s == 2), isTrue);
  });

  test('PLINK texte : même information, allèle compté = allèle mineur', () {
    expect(ped.samples, vcf.samples);
    for (var j = 0; j < 250; j++) {
      final flip = ped.variants[j].counted != vcf.variants[j].counted;
      for (var i = 0; i < 300; i++) {
        final a = ped.dosage[j][i], b = vcf.dosage[j][i];
        expect(a < 0 ? -1 : (flip ? 2 - a : a), b, reason: '${ped.variants[j].id} sujet $i');
      }
    }
  });

  test('résumés sur données brutes = snpStats (col.summary, row.summary)', () {
    final s = ref['snpstats'] as Map;
    final callV = v(s['call_rate']), maf = v(s['maf']), callS = v(s['sample_call']), het = v(s['sample_het']);
    final all = genotypeQc(bed, options: const GenotypeQcOptions(minSampleCallRate: 0, hetSd: 1e9, minVariantCallRate: 0, minMaf: 0, hweP: 0));
    for (var j = 0; j < 250; j++) {
      expect(all.variantCallRate[j], closeRel(callV[j], rel: 1e-12));
      expect(all.maf[j], closeRel(maf[j], rel: 1e-12, abs: 1e-15));
    }
    for (var i = 0; i < 300; i++) {
      expect(all.sampleCallRate[i], closeRel(callS[i], rel: 1e-12));
      expect(all.sampleHet[i], closeRel(het[i], rel: 1e-12));
    }
  });

  test('contrôle de qualité : sujets et variants écartés, métriques, HWE exact chez les témoins', () {
    final q = ref['qc'] as Map;
    final qc = genotypeQc(bed);
    expect(qc.removedSampleCall, idx(q['removed_call']));
    expect(qc.removedSampleHet, idx(q['removed_het']));
    expect(qc.removedVariantCall, idx(q['removed_snp_call']));
    expect(qc.removedVariantMaf, idx(q['removed_snp_maf']));
    expect(qc.removedVariantHwe, idx(q['removed_snp_hwe']));
    expect(qc.hweInControls, isTrue);
    final z = v(q['het_z']), call = v(q['call_rate']), maf = v(q['maf']), hwe = v(q['hwe_p']);
    for (var i = 0; i < 300; i++) {
      expect(qc.hetZ[i], closeRel(z[i], rel: 1e-10, abs: 1e-12));
    }
    for (var j = 0; j < 250; j++) {
      expect(qc.variantCallRate[j], closeRel(call[j], rel: 1e-12));
      expect(qc.maf[j], closeRel(maf[j], rel: 1e-12, abs: 1e-15));
      expect(qc.hweP[j], closeRel(hwe[j], rel: 1e-9, abs: 0), reason: 'HWE ${bed.variants[j].id}');
    }
    expect(qc.cleaned.sampleCount, (q['keep_samples'] as List).length);
    expect(qc.cleaned.variantCount, (q['keep_snps'] as List).length);
    expect(qc.result.statistics['kept_variants'], 237);
  });

  test('balayage ajusté (sexe, âge) sur les données nettoyées = glm de R', () {
    final qc = genotypeQc(bed);
    final age = {for (final l in File('$dir/simule_age.txt').readAsLinesSync()) l.split(' ')[0]: l.split(' ')[1]};
    final ds = genotypeDataset(qc.cleaned, covariates: {'age': age});
    final s = ref['scan'] as Map;
    final snps = [for (final x in s['snps'] as List) '$x'];
    final r = snpScan(ds, snps, 'statut', 'cas', covariates: const [TermSpec('sexe', categorical: true, reference: 'H'), TermSpec('age')]);
    final p = v(s['p']), b = v(s['abs_beta']), adj = v(s['padj_bh']);
    for (var k = 0; k < snps.length; k++) {
      expect(r.statistics['p_${snps[k]}'], closeRel(p[k], rel: 1e-6), reason: snps[k]);
      expect(r.statistics['beta_${snps[k]}']!.abs(), closeRel(b[k], rel: 1e-7), reason: snps[k]);
      expect(r.statistics['padj_${snps[k]}'], closeRel(adj[k], rel: 1e-6), reason: snps[k]);
    }
  });

  test('erreurs lisibles : fichiers non reconnus ou incohérents', () {
    expect(() => parseVcf('chr1\t1\trs1\tA\tG'), throwsA(isA<StatInputError>()));
    expect(() => parsePlinkBed(File('$dir/simule.fam').readAsBytesSync(), '', ''), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'bed_magic')));
    expect(() => parsePlinkPed('F1 S1 0 0 1 2 A A', '1 rs1 0 10\n1 rs2 0 20'), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'ped_columns')));
  });

  test('choix du lecteur d\'après les extensions ; jeux incomplets refusés', () {
    Map<String, Uint8List> f(List<String> names) => {for (final n in names) n.split('/').last: File('$dir/$n').readAsBytesSync()};
    expect(readGenotypeFiles(f(['simule.bed', 'simule.bim', 'simule.fam'])).variantCount, 250);
    expect(readGenotypeFiles(f(['simule.ped', 'simule.map'])).sampleCount, 300);
    expect(readGenotypeFiles(f(['simule.vcf'])).notes, isNotEmpty);
    expect(() => readGenotypeFiles(f(['simule.bed', 'simule.bim'])), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'plink_incomplete')));
    expect(() => readGenotypeFiles(f(['simule_age.txt'])), throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'no_genotype_file')));
  });
}
