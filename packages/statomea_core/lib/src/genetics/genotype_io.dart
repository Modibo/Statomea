/// Import de génotypes et contrôle de qualité, sans dépendance externe :
///  - VCF 4.x texte (champ GT ; génotypes phasés ou non ; sites multialléliques écartés et décomptés) ;
///  - PLINK texte (.ped/.map ; allèle compté = allèle mineur, convention de PLINK) ;
///  - PLINK binaire (.bed/.bim/.fam, mode « SNP-major » ; allèle compté = A1, 5e colonne du .bim).
/// Contrôle de qualité, dans cet ordre (à la manière de PLINK --mind, --het, --geno, --maf, --hwe) :
///  1) sujets : taux d'appel < seuil ; 2) sujets : hétérozygotie à plus de k ET de la moyenne (contamination,
///  consanguinité) ; 3) sur les sujets retenus, variants : taux d'appel, MAF, Hardy-Weinberg exact chez les témoins.
/// Validé contre vcfR, snpStats (relecture du PLINK binaire écrit par genio) et HardyWeinberg
/// (`validation/r/25_genotypes.R`).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../data/dataset.dart';
import '../i18n.dart';
import '../model/result.dart';
import 'association.dart' show hweExact;

class GenotypeVariant {
  final String chrom, id;
  final int pos;

  /// Allèle compté par le dosage (ALT pour un VCF, A1 pour PLINK) et autre allèle.
  final String counted, other;
  const GenotypeVariant(this.chrom, this.id, this.pos, this.counted, this.other);
  String get label => id.isEmpty || id == '.' ? '$chrom:$pos' : id;
}

/// Génotypes d'un ensemble de sujets : dosage = nombre de copies de l'allèle compté (0, 1, 2), −1 si manquant.
class GenotypeData {
  final List<String> samples;

  /// Sexe (PLINK : 1 homme, 2 femme ; null inconnu) et phénotype (PLINK : 1 témoin, 2 cas ; null inconnu).
  final List<int?> sex, phenotype;
  final List<GenotypeVariant> variants;
  final List<Int8List> dosage;
  final String source;
  final List<String> notes;
  GenotypeData(this.samples, this.variants, this.dosage, {required this.sex, required this.phenotype, required this.source, this.notes = const []});

  int get sampleCount => samples.length;
  int get variantCount => variants.length;

  GenotypeData subset({List<int>? sampleIdx, List<int>? variantIdx, List<String> notes = const []}) {
    final si = sampleIdx ?? [for (var i = 0; i < sampleCount; i++) i];
    final vi = variantIdx ?? [for (var j = 0; j < variantCount; j++) j];
    return GenotypeData([for (final i in si) samples[i]], [for (final j in vi) variants[j]],
        [for (final j in vi) Int8List.fromList([for (final i in si) dosage[j][i]])],
        sex: [for (final i in si) sex[i]], phenotype: [for (final i in si) phenotype[i]], source: source, notes: [...this.notes, ...notes]);
  }
}

int? _plinkCode(String s) => switch (s.trim()) { '1' => 1, '2' => 2, _ => null };

List<String> _lines(String text) => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.endsWith('\r') ? l.substring(0, l.length - 1) : l];

/// Lecture d'un VCF texte (décompresser un .vcf.gz au préalable).
GenotypeData parseVcf(String text, {String source = 'VCF'}) {
  List<String>? samples;
  final variants = <GenotypeVariant>[];
  final dosage = <Int8List>[];
  var multi = 0, noGt = 0, haploid = 0, malformed = 0;
  for (final line in _lines(text)) {
    if (line.startsWith('##')) continue;
    final f = line.split('\t');
    if (line.startsWith('#CHROM')) {
      if (f.length < 10) throw StatInputError('vcf_no_samples', tr('VCF sans colonne d\'échantillon : aucun génotype à lire.', 'VCF without sample columns: no genotype to read.'));
      samples = f.sublist(9);
      continue;
    }
    if (samples == null) throw StatInputError('vcf_header', tr('Ligne d\'en-tête #CHROM absente : fichier VCF non reconnu.', '#CHROM header line missing: VCF file not recognized.'));
    if (f.length != 9 + samples.length) {
      malformed++;
      continue;
    }
    if (f[4].contains(',')) {
      multi++;
      continue;
    }
    final gtIdx = f[8].split(':').indexOf('GT');
    if (gtIdx < 0) {
      noGt++;
      continue;
    }
    final d = Int8List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final parts = f[9 + i].split(':');
      final gt = gtIdx < parts.length ? parts[gtIdx] : '.';
      final a = gt.split(RegExp(r'[/|]'));
      if (a.length != 2) {
        if (gt != '.' && a.length == 1) haploid++;
        d[i] = -1;
      } else if (a[0] == '.' || a[1] == '.') {
        d[i] = -1;
      } else {
        final x = int.tryParse(a[0]), y = int.tryParse(a[1]);
        d[i] = x == null || y == null || x > 1 || y > 1 ? -1 : x + y;
      }
    }
    variants.add(GenotypeVariant(f[0], f[2], int.tryParse(f[1]) ?? 0, f[4], f[3]));
    dosage.add(d);
  }
  if (samples == null) throw StatInputError('vcf_header', tr('Ligne d\'en-tête #CHROM absente : fichier VCF non reconnu.', '#CHROM header line missing: VCF file not recognized.'));
  if (variants.isEmpty) throw StatInputError('vcf_empty', tr('Aucun variant biallélique lisible dans ce VCF.', 'No readable biallelic variant in this VCF.'));
  return GenotypeData(samples, variants, dosage,
      sex: List.filled(samples.length, null), phenotype: List.filled(samples.length, null), source: source, notes: [
    if (multi > 0) tr('$multi site(s) multiallélique(s) écarté(s).', '$multi multiallelic site(s) removed.'),
    if (noGt > 0) tr('$noGt site(s) sans champ GT écarté(s).', '$noGt site(s) without GT field removed.'),
    if (haploid > 0) tr('$haploid génotype(s) haploïde(s) (chromosomes sexuels ?) traités comme manquants.', '$haploid haploid genotype(s) (sex chromosomes?) treated as missing.'),
    if (malformed > 0) tr('$malformed ligne(s) au nombre de colonnes incorrect écartée(s).', '$malformed line(s) with a wrong number of columns removed.'),
  ]);
}

/// Lecture PLINK texte (.ped/.map). L'allèle compté est l'allèle mineur de l'échantillon (convention de PLINK).
GenotypeData parsePlinkPed(String ped, String map, {String source = 'PLINK .ped/.map'}) {
  final mapLines = [for (final l in _lines(map)) l.trim().split(RegExp(r'\s+'))];
  final m = mapLines.length;
  final rows = [for (final l in _lines(ped)) l.trim().split(RegExp(r'\s+'))];
  final samples = <String>[], sex = <int?>[], pheno = <int?>[];
  for (final r in rows) {
    if (r.length != 6 + 2 * m) {
      throw StatInputError('ped_columns', tr('Fichier .ped : ${r.length} colonnes pour ${r.isEmpty ? '?' : r[1]}, ${6 + 2 * m} attendues (6 + 2 × $m variants du .map).',
          '.ped file: ${r.length} columns for ${r.isEmpty ? '?' : r[1]}, ${6 + 2 * m} expected (6 + 2 × $m variants in the .map).'));
    }
    samples.add(r[1]);
    sex.add(_plinkCode(r[4]));
    pheno.add(_plinkCode(r[5]));
  }
  final variants = <GenotypeVariant>[];
  final dosage = <Int8List>[];
  var skipped = 0;
  for (var j = 0; j < m; j++) {
    final counts = <String, int>{};
    for (final r in rows) {
      for (final a in [r[6 + 2 * j], r[7 + 2 * j]]) {
        if (a != '0') counts[a] = (counts[a] ?? 0) + 1;
      }
    }
    if (counts.length > 2 || counts.isEmpty) {
      skipped++;
      continue;
    }
    final al = counts.keys.toList()..sort((a, b) => counts[a]!.compareTo(counts[b]!));
    final minor = al.first, major = al.length > 1 ? al.last : '0';
    final d = Int8List(rows.length);
    for (var i = 0; i < rows.length; i++) {
      final a = rows[i][6 + 2 * j], b = rows[i][7 + 2 * j];
      d[i] = a == '0' || b == '0' ? -1 : (a == minor ? 1 : 0) + (b == minor ? 1 : 0);
    }
    final ml = mapLines[j];
    variants.add(GenotypeVariant(ml[0], ml[1], int.tryParse(ml.last) ?? 0, minor, major));
    dosage.add(d);
  }
  return GenotypeData(samples, variants, dosage, sex: sex, phenotype: pheno, source: source, notes: [
    if (skipped > 0) tr('$skipped variant(s) non bialléliques ou sans génotype écarté(s).', '$skipped non-biallelic or empty variant(s) removed.'),
  ]);
}

/// Lecture PLINK binaire (.bed/.bim/.fam), mode SNP-major. Codes à 2 bits : 00 homozygote A1, 10 hétérozygote,
/// 11 homozygote A2, 01 manquant ; le dosage compte les copies de A1.
GenotypeData parsePlinkBed(Uint8List bed, String bim, String fam, {String source = 'PLINK .bed/.bim/.fam'}) {
  if (bed.length < 3 || bed[0] != 0x6c || bed[1] != 0x1b) {
    throw StatInputError('bed_magic', tr('Fichier .bed non reconnu (signature PLINK absente).', 'Unrecognized .bed file (PLINK signature missing).'));
  }
  if (bed[2] != 1) {
    throw StatInputError('bed_mode', tr('Fichier .bed en mode « individu-major » : le convertir en mode SNP-major (plink --make-bed).',
        '.bed file in individual-major mode: convert it to SNP-major (plink --make-bed).'));
  }
  final famRows = [for (final l in _lines(fam)) l.trim().split(RegExp(r'\s+'))];
  final bimRows = [for (final l in _lines(bim)) l.trim().split(RegExp(r'\s+'))];
  final n = famRows.length, m = bimRows.length, bytesPerSnp = (n + 3) ~/ 4;
  if (bed.length != 3 + m * bytesPerSnp) {
    throw StatInputError('bed_size', tr('Taille du .bed incohérente avec le .bim ($m variants) et le .fam ($n sujets).',
        '.bed size inconsistent with the .bim ($m variants) and the .fam ($n subjects).'));
  }
  final dosage = <Int8List>[];
  for (var j = 0; j < m; j++) {
    final d = Int8List(n);
    final off = 3 + j * bytesPerSnp;
    for (var i = 0; i < n; i++) {
      final code = (bed[off + (i >> 2)] >> ((i & 3) * 2)) & 3;
      d[i] = switch (code) { 0 => 2, 2 => 1, 3 => 0, _ => -1 };
    }
    dosage.add(d);
  }
  return GenotypeData([for (final r in famRows) r[1]], [for (final r in bimRows) GenotypeVariant(r[0], r[1], int.tryParse(r[3]) ?? 0, r[4], r[5])], dosage,
      sex: [for (final r in famRows) _plinkCode(r[4])], phenotype: [for (final r in famRows) r.length > 5 ? _plinkCode(r[5]) : null], source: source);
}

/// Lecture d'un jeu de fichiers de génotypes choisi par l'utilisateur, d'après les extensions :
/// .vcf (déjà décompressé) ; .ped + .map ; .bed + .bim + .fam. Erreur explicite si le jeu est incomplet ou ambigu.
GenotypeData readGenotypeFiles(Map<String, Uint8List> files) {
  String? find(String ext) {
    final k = files.keys.where((f) => f.toLowerCase().endsWith(ext)).toList();
    if (k.length > 1) {
      throw StatInputError('ambiguous_files', tr('Plusieurs fichiers $ext : n\'en choisir qu\'un.', 'Several $ext files: choose only one.'));
    }
    return k.isEmpty ? null : k.single;
  }

  String text(String name) => utf8.decode(files[name]!, allowMalformed: true);
  final vcf = find('.vcf'), bed = find('.bed'), bim = find('.bim'), fam = find('.fam'), ped = find('.ped'), map = find('.map');
  if (bed != null || bim != null || fam != null) {
    if (bed == null || bim == null || fam == null) {
      throw StatInputError('plink_incomplete', tr('PLINK binaire : les trois fichiers .bed, .bim et .fam sont nécessaires.', 'Binary PLINK: the three files .bed, .bim and .fam are required.'));
    }
    return parsePlinkBed(files[bed]!, text(bim), text(fam), source: '$bed / $bim / $fam');
  }
  if (ped != null || map != null) {
    if (ped == null || map == null) {
      throw StatInputError('plink_incomplete', tr('PLINK texte : les deux fichiers .ped et .map sont nécessaires.', 'Text PLINK: both .ped and .map files are required.'));
    }
    return parsePlinkPed(text(ped), text(map), source: '$ped / $map');
  }
  if (vcf != null) return parseVcf(text(vcf), source: vcf);
  throw StatInputError('no_genotype_file', tr('Aucun fichier de génotypes reconnu (.vcf, .vcf.gz, .ped/.map ou .bed/.bim/.fam).',
      'No recognized genotype file (.vcf, .vcf.gz, .ped/.map or .bed/.bim/.fam).'));
}

/// Seuils du contrôle de qualité (valeurs usuelles de PLINK et des guides de GWAS).
class GenotypeQcOptions {
  final double minSampleCallRate, hetSd, minVariantCallRate, minMaf, hweP;
  const GenotypeQcOptions({this.minSampleCallRate = 0.95, this.hetSd = 3, this.minVariantCallRate = 0.95, this.minMaf = 0.01, this.hweP = 1e-6});
}

/// Résultat détaillé du contrôle de qualité.
class GenotypeQc {
  final GenotypeData cleaned;
  final List<double> sampleCallRate, sampleHet, hetZ;
  final List<double> variantCallRate, maf, hweP; // calculés sur les sujets retenus
  final List<int> removedSampleCall, removedSampleHet, removedVariantCall, removedVariantMaf, removedVariantHwe;
  final bool hweInControls;
  final AnalysisResult result;
  GenotypeQc(this.cleaned, this.sampleCallRate, this.sampleHet, this.hetZ, this.variantCallRate, this.maf, this.hweP, this.removedSampleCall,
      this.removedSampleHet, this.removedVariantCall, this.removedVariantMaf, this.removedVariantHwe, this.hweInControls, this.result);
}

double _mean(List<double> x) => x.fold(0.0, (a, b) => a + b) / x.length;

GenotypeQc genotypeQc(GenotypeData g, {GenotypeQcOptions options = const GenotypeQcOptions()}) {
  final n = g.sampleCount, m = g.variantCount;
  if (n < 10 || m < 1) throw StatInputError('n_too_small', tr('Au moins 10 sujets et 1 variant sont requis.', 'At least 10 subjects and 1 variant are required.'));
  // 1) Taux d'appel et hétérozygotie par sujet (sur tous les variants).
  final call = <double>[], het = <double>[];
  for (var i = 0; i < n; i++) {
    var called = 0, h = 0;
    for (var j = 0; j < m; j++) {
      final d = g.dosage[j][i];
      if (d >= 0) {
        called++;
        if (d == 1) h++;
      }
    }
    call.add(called / m);
    het.add(called == 0 ? double.nan : h / called);
  }
  final keep1 = [for (var i = 0; i < n; i++) if (call[i] >= options.minSampleCallRate) i];
  if (keep1.length < 3) {
    throw StatInputError('qc_samples', tr('Moins de 3 sujets passent le seuil de taux d\'appel : vérifier le fichier.', 'Fewer than 3 subjects pass the call-rate threshold: check the file.'));
  }
  final hk = [for (final i in keep1) het[i]];
  final hm = _mean(hk);
  final hsd = math.sqrt(hk.fold(0.0, (a, v) => a + (v - hm) * (v - hm)) / (hk.length - 1));
  final z = [for (final h in het) hsd > 0 ? (h - hm) / hsd : 0.0];
  final keepS = [for (final i in keep1) if (z[i].abs() <= options.hetSd) i];
  final removedCall = [for (var i = 0; i < n; i++) if (call[i] < options.minSampleCallRate) i];
  final removedHet = [for (final i in keep1) if (z[i].abs() > options.hetSd) i];
  // 2) Variants, sur les sujets retenus.
  final controls = [for (final i in keepS) if (g.phenotype[i] == 1) i];
  final hweInControls = controls.length >= 10;
  final hweSet = hweInControls ? controls : keepS;
  final vCall = <double>[], maf = <double>[], hwe = <double>[];
  for (var j = 0; j < m; j++) {
    var called = 0, alleles = 0;
    for (final i in keepS) {
      final d = g.dosage[j][i];
      if (d >= 0) {
        called++;
        alleles += d;
      }
    }
    vCall.add(called / keepS.length);
    final p = called == 0 ? 0.0 : alleles / (2 * called);
    maf.add(math.min(p, 1 - p));
    var a = 0, b = 0, c = 0;
    for (final i in hweSet) {
      switch (g.dosage[j][i]) {
        case 0:
          a++;
        case 1:
          b++;
        case 2:
          c++;
      }
    }
    hwe.add(a + b + c == 0 ? double.nan : hweExact(a, b, c).p);
  }
  final rCall = [for (var j = 0; j < m; j++) if (vCall[j] < options.minVariantCallRate) j];
  final rMaf = [for (var j = 0; j < m; j++) if (maf[j] < options.minMaf) j];
  final rHwe = [for (var j = 0; j < m; j++) if (hwe[j] < options.hweP) j];
  final drop = {...rCall, ...rMaf, ...rHwe};
  final keepV = [for (var j = 0; j < m; j++) if (!drop.contains(j)) j];
  final cleaned = g.subset(sampleIdx: keepS, variantIdx: keepV);
  String reasonsV(int j) => [
        if (rCall.contains(j)) tr('taux d\'appel ${fmtPct(vCall[j])}', 'call rate ${fmtPct(vCall[j])}'),
        if (rMaf.contains(j)) 'MAF ${fmt(maf[j], digits: 3)}',
        if (rHwe.contains(j)) 'HWE p = ${hwe[j].toStringAsExponential(1)}',
      ].join(' ; ');
  final result = AnalysisResult(
    methodId: 'genotype_qc',
    methodName: tr('Contrôle de qualité des génotypes', 'Genotype quality control'),
    inputs: {'source': g.source, 'samples': n, 'variants': m, 'minSampleCallRate': options.minSampleCallRate, 'hetSd': options.hetSd,
      'minVariantCallRate': options.minVariantCallRate, 'minMaf': options.minMaf, 'hweP': options.hweP},
    formula: tr(
        'Sujets : taux d\'appel ≥ ${fmtPct(options.minSampleCallRate)} ; hétérozygotie (hétérozygotes / génotypes appelés) à moins de ${fmt(options.hetSd)} ET de la moyenne. '
            'Puis variants, sur les sujets retenus : taux d\'appel ≥ ${fmtPct(options.minVariantCallRate)} ; MAF ≥ ${fmt(options.minMaf)} ; Hardy-Weinberg exact ${hweInControls ? 'chez les témoins' : 'sur tous les sujets'} p ≥ ${options.hweP}.',
        'Subjects: call rate ≥ ${fmtPct(options.minSampleCallRate)}; heterozygosity (heterozygotes / called genotypes) within ${fmt(options.hetSd)} SD of the mean. '
            'Then variants, on retained subjects: call rate ≥ ${fmtPct(options.minVariantCallRate)}; MAF ≥ ${fmt(options.minMaf)}; exact Hardy-Weinberg ${hweInControls ? 'in controls' : 'in all subjects'} p ≥ ${options.hweP}.'),
    estimates: [
      Estimate(tr('Sujets retenus', 'Subjects retained'), keepS.length.toDouble()),
      Estimate(tr('Variants retenus', 'Variants retained'), keepV.length.toDouble()),
    ],
    statistics: {
      'samples': n.toDouble(),
      'variants': m.toDouble(),
      'removed_sample_call': removedCall.length.toDouble(),
      'removed_sample_het': removedHet.length.toDouble(),
      'removed_variant_call': rCall.length.toDouble(),
      'removed_variant_maf': rMaf.length.toDouble(),
      'removed_variant_hwe': rHwe.length.toDouble(),
      'kept_samples': keepS.length.toDouble(),
      'kept_variants': keepV.length.toDouble(),
    },
    checks: [
      Check('hwe_controls', tr('Hardy-Weinberg évalué chez les témoins', 'Hardy-Weinberg assessed in controls'), hweInControls ? CheckStatus.ok : CheckStatus.warning,
          hweInControls
              ? tr('${controls.length} témoins.', '${controls.length} controls.')
              : tr('Phénotype absent ou moins de 10 témoins : HWE évalué sur tous les sujets ; un vrai variant associé peut alors être écarté à tort.',
                  'Phenotype missing or fewer than 10 controls: HWE assessed in all subjects; a truly associated variant may then be wrongly removed.')),
      Check('sex_check', tr('Concordance du sexe déclaré et génétique', 'Agreement of declared and genetic sex'), CheckStatus.notAssessed,
          tr('Nécessite les variants du chromosome X (non évalué ici).', 'Requires chromosome X variants (not assessed here).')),
      Check('relatedness', tr('Apparentement et doublons', 'Relatedness and duplicates'), CheckStatus.notAssessed,
          tr('Parenté cryptique et échantillons dupliqués (IBD) non évalués : à vérifier avec PLINK --genome ou KING.', 'Cryptic relatedness and duplicate samples (IBD) not assessed: check with PLINK --genome or KING.')),
      Check('stratification', tr('Stratification de population', 'Population stratification'), CheckStatus.notAssessed,
          tr('Composantes principales non calculées : ajuster sur l\'ascendance ou des CP calculées sur des variants indépendants.', 'Principal components not computed: adjust for ancestry or PCs computed on independent variants.')),
    ],
    alerts: [
      for (final note in g.notes) Alert('import_note', Severity.info, note),
      if (keepS.length < n * 0.9)
        Alert('many_samples_removed', Severity.caution,
            tr('Plus de 10 % des sujets écartés : problème de génotypage à rechercher avant toute analyse.', 'More than 10% of subjects removed: look for a genotyping problem before any analysis.')),
    ],
    tables: [
      ResultTable(tr('Étapes du contrôle', 'QC steps'), [tr('Étape', 'Step'), tr('Écartés', 'Removed'), tr('Restants', 'Remaining')], [
        [tr('Sujets : taux d\'appel', 'Subjects: call rate'), '${removedCall.length}', '${keep1.length}'],
        [tr('Sujets : hétérozygotie', 'Subjects: heterozygosity'), '${removedHet.length}', '${keepS.length}'],
        [tr('Variants : taux d\'appel', 'Variants: call rate'), '${rCall.length}', ''],
        [tr('Variants : MAF', 'Variants: MAF'), '${rMaf.length}', ''],
        [tr('Variants : Hardy-Weinberg', 'Variants: Hardy-Weinberg'), '${rHwe.length}', '${keepV.length}'],
      ]),
      ResultTable(tr('Sujets écartés', 'Subjects removed'), [tr('Sujet', 'Subject'), tr('Taux d\'appel', 'Call rate'), tr('Hétérozygotie', 'Heterozygosity'), 'z'], [
        for (final i in [...removedCall, ...removedHet]) [g.samples[i], fmtPct(call[i]), fmt(het[i], digits: 3), fmt(z[i], digits: 2)]
      ]),
      ResultTable(tr('Variants écartés', 'Variants removed'), [tr('Variant', 'Variant'), tr('Motif', 'Reason')], [
        for (final j in drop.toList()..sort()) [g.variants[j].label, reasonsV(j)]
      ]),
    ],
    log: [tr('Source : ${g.source}.', 'Source: ${g.source}.'), ...g.notes],
    interpretation: Interpretation(
      whyThisMethod: tr('Les erreurs de génotypage (sujets ou variants de mauvaise qualité) créent de fausses associations : on les écarte selon des seuils fixés avant l\'analyse.',
          'Genotyping errors (poor-quality subjects or variants) create false associations: they are removed using thresholds fixed before the analysis.'),
      whatItMeans: tr('${keepS.length} sujets sur $n et ${keepV.length} variants sur $m retenus pour l\'analyse d\'association.',
          '${keepS.length} subjects out of $n and ${keepV.length} variants out of $m retained for the association analysis.'),
      notJustified: tr('Ajuster les seuils après avoir vu les résultats d\'association ; écarter un variant associé sur un écart à Hardy-Weinberg calculé chez les cas.',
          'Adjusting thresholds after seeing the association results; removing an associated variant because of a Hardy-Weinberg departure computed in cases.'),
    ),
  );
  return GenotypeQc(cleaned, call, het, z, vCall, maf, hwe, removedCall, removedHet, rCall, rMaf, rHwe, hweInControls, result);
}

/// Table d'analyse : une ligne par sujet ; colonnes id, statut, sexe (si connus), covariables jointes par
/// identifiant, puis un génotype « allèle/allèle » par variant (utilisable par le balayage de variants).
Dataset genotypeDataset(GenotypeData g, {Map<String, Map<String, String>> covariates = const {}}) {
  final caseL = tr('cas', 'case'), ctlL = tr('temoin', 'control');
  final hasPheno = g.phenotype.any((p) => p != null), hasSex = g.sex.any((s) => s != null);
  final used = <String>{};
  String colName(GenotypeVariant v) {
    var name = v.label;
    var k = 2;
    while (used.contains(name)) {
      name = '${v.label}_${k++}';
    }
    used.add(name);
    return name;
  }

  final cols = <String, List<Object?>>{
    'id': g.samples,
    if (hasPheno) tr('statut', 'status'): [for (final p in g.phenotype) p == 2 ? caseL : (p == 1 ? ctlL : null)],
    if (hasSex) tr('sexe', 'sex'): [for (final s in g.sex) s == 1 ? 'H' : (s == 2 ? 'F' : null)],
    for (final e in covariates.entries) e.key: [for (final id in g.samples) e.value[id]],
  };
  used.addAll(cols.keys);
  for (var j = 0; j < g.variantCount; j++) {
    final v = g.variants[j];
    cols[colName(v)] = [
      for (final d in g.dosage[j]) d < 0 ? null : (d == 2 ? '${v.counted}/${v.counted}' : (d == 1 ? '${v.other}/${v.counted}' : '${v.other}/${v.other}'))
    ];
  }
  return Dataset.fromColumns(cols, source: g.source);
}
