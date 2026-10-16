/// Statistiques résumées de GWAS : lecture (GWAS-SSF, TwoSampleMR, PLINK), choix des instruments (seuil puis clumping
/// par distance) et harmonisation des allèles entre l'exposition et l'issue, avant une randomisation mendélienne.
/// Règles de TwoSampleMR (harmonise_data, action 2), validées contre validation/r/39_gwas_mr.R.
library;

import 'dart:math' as math;

import '../data/csv.dart';
import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';

/// Un variant d'un fichier de statistiques résumées (allèles en majuscules ; β = log(OR) si le fichier donne un OR).
class GwasVariant {
  final String id;
  final String? chromosome;
  final int? position;
  final String effectAllele, otherAllele;
  final double beta, se;
  final double? p, eaf;
  const GwasVariant(this.id, this.chromosome, this.position, this.effectAllele, this.otherAllele, this.beta, this.se, this.p, this.eaf);
}

/// Fichier lu : variants valides, colonnes reconnues et lignes écartées (valeurs manquantes ou illisibles).
class GwasSumstats {
  final List<GwasVariant> variants;
  final Map<String, String> columns;
  final bool fromOddsRatio;
  final int skipped;
  final String source;
  GwasSumstats(this.variants, this.columns, this.fromOddsRatio, this.skipped, this.source);
  late final Map<String, GwasVariant> byId = {for (final v in variants) v.id: v};
}

/// Alias de colonnes reconnus (insensibles à la casse), du plus spécifique au plus général.
const gwasColumnAliases = <String, List<String>>{
  'id': ['variant_id', 'rsid', 'snp', 'snpid', 'markername', 'id', 'rs_id', 'variant'],
  'chr': ['chromosome', 'chr', 'chrom', '#chrom', 'hm_chrom'],
  'pos': ['base_pair_location', 'bp', 'pos', 'position', 'hm_pos'],
  'ea': ['effect_allele', 'a1', 'ea', 'alt', 'allele1', 'tested_allele', 'hm_effect_allele'],
  'oa': ['other_allele', 'a2', 'nea', 'oa', 'ref', 'allele2', 'non_effect_allele', 'hm_other_allele'],
  'beta': ['beta', 'b', 'effect', 'hm_beta', 'log_or', 'logor'],
  'or': ['odds_ratio', 'or', 'hm_odds_ratio'],
  'se': ['standard_error', 'se', 'stderr', 'sebeta'],
  'p': ['p_value', 'p', 'pval', 'pvalue', 'p.value', 'p_bolt_lmm'],
  'eaf': ['effect_allele_frequency', 'eaf', 'af', 'freq', 'freq1', 'a1freq', 'hm_effect_allele_frequency', 'af_alt'],
};

/// Lit un fichier de statistiques résumées (tabulation, virgule ou point-virgule ; détection automatique).
GwasSumstats parseGwasSumstats(String text, {String source = 'GWAS'}) {
  final delim = text.contains('\t') ? '\t' : detectDelimiter(text);
  final rows = parseCsvRows(text, delim);
  if (rows.isEmpty) throw FormatException(tr('Fichier GWAS vide : $source.', 'Empty GWAS file: $source.'));
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  final cols = <String, int>{};
  for (final e in gwasColumnAliases.entries) {
    for (final a in e.value) {
      final i = header.indexOf(a);
      if (i >= 0) {
        cols[e.key] = i;
        break;
      }
    }
  }
  final missing = [for (final k in ['id', 'ea', 'oa', 'se']) if (!cols.containsKey(k)) k];
  if (!cols.containsKey('beta') && !cols.containsKey('or')) missing.add('beta/OR');
  if (missing.isNotEmpty) {
    throw FormatException(tr('Colonnes introuvables dans $source : ${missing.join(', ')} (attendu : variant_id, effect_allele, other_allele, beta ou OR, standard_error, p_value…).',
        'Columns not found in $source: ${missing.join(', ')} (expected: variant_id, effect_allele, other_allele, beta or OR, standard_error, p_value…).'));
  }
  final useOr = !cols.containsKey('beta');
  String? at(List<String> r, String k) {
    final i = cols[k];
    if (i == null || i >= r.length) return null;
    final s = r[i].trim();
    return s.isEmpty || s == 'NA' || s == '.' ? null : s;
  }

  final out = <GwasVariant>[];
  var skipped = 0;
  for (var j = 1; j < rows.length; j++) {
    final r = rows[j];
    if (r.length == 1 && r.first.trim().isEmpty) continue;
    final id = at(r, 'id'), ea = at(r, 'ea')?.toUpperCase(), oa = at(r, 'oa')?.toUpperCase();
    var b = parseNumber(at(r, useOr ? 'or' : 'beta'));
    final se = parseNumber(at(r, 'se'));
    if (useOr && b != null) b = b > 0 ? math.log(b) : null;
    if (id == null || ea == null || oa == null || b == null || se == null || !b.isFinite || !(se > 0)) {
      skipped++;
      continue;
    }
    out.add(GwasVariant(id, at(r, 'chr'), int.tryParse(at(r, 'pos') ?? ''), ea, oa, b, se, parseNumber(at(r, 'p')), parseNumber(at(r, 'eaf'))));
  }
  return GwasSumstats(out, {for (final e in cols.entries) e.key: rows.first[e.value].trim()}, useOr, skipped, source);
}

/// p d'un variant : celle du fichier, sinon calculée à partir de z = β/ES.
double gwasP(GwasVariant v) => v.p ?? normalTwoSidedP(v.beta / v.se);

/// Instruments : variants à p < [pThreshold], puis clumping par distance (meilleure p d'abord ; un variant retenu écarte
/// ceux du même chromosome à ≤ [windowKb] kb). Sans position, chaque variant forme son propre locus.
List<GwasVariant> selectInstruments(GwasSumstats g, {double pThreshold = 5e-8, double windowKb = 10000}) {
  final idx = [for (var i = 0; i < g.variants.length; i++) if (gwasP(g.variants[i]) < pThreshold) i];
  idx.sort((a, b) {
    final c = gwasP(g.variants[a]).compareTo(gwasP(g.variants[b]));
    return c != 0 ? c : a.compareTo(b);
  });
  final kept = <GwasVariant>[];
  final w = windowKb * 1000;
  for (final i in idx) {
    final v = g.variants[i];
    final close = v.position != null &&
        kept.any((k) => k.position != null && k.chromosome == v.chromosome && (k.position! - v.position!).abs() <= w);
    if (!close) kept.add(v);
  }
  return kept;
}

/// Résultat de l'harmonisation d'un instrument.
enum HarmonisationStatus { aligned, flipped, strand, strandFlipped, palindromicAligned, palindromicFlipped, palindromicAmbiguous, incompatible, absent }

extension HarmonisationLabel on HarmonisationStatus {
  bool get usable => index <= HarmonisationStatus.palindromicFlipped.index;
  String get label => switch (this) {
        HarmonisationStatus.aligned => tr('aligné', 'aligned'),
        HarmonisationStatus.flipped => tr('inversé', 'flipped'),
        HarmonisationStatus.strand => tr('brin corrigé', 'strand corrected'),
        HarmonisationStatus.strandFlipped => tr('brin corrigé et inversé', 'strand corrected and flipped'),
        HarmonisationStatus.palindromicAligned => tr('palindromique aligné', 'palindromic aligned'),
        HarmonisationStatus.palindromicFlipped => tr('palindromique retourné', 'palindromic flipped'),
        HarmonisationStatus.palindromicAmbiguous => tr('palindromique écarté', 'palindromic excluded'),
        HarmonisationStatus.incompatible => tr('incompatible', 'incompatible'),
        HarmonisationStatus.absent => tr('absent de l\'issue', 'missing from outcome'),
      };
}

/// Instrument harmonisé : β et ES de l'exposition et de l'issue, l'issue étant exprimée pour l'allèle à effet de l'exposition.
class HarmonisedVariant {
  final GwasVariant exposure;
  final HarmonisationStatus status;
  final double? by, byse;
  const HarmonisedVariant(this.exposure, this.status, this.by, this.byse);
}

class GwasHarmonisation {
  final List<HarmonisedVariant> variants;
  final int significant;
  final double pThreshold, windowKb, palindromeMax;
  final GwasSumstats exposure, outcome;
  GwasHarmonisation(this.variants, this.significant, this.pThreshold, this.windowKb, this.palindromeMax, this.exposure, this.outcome);

  List<HarmonisedVariant> get usable => [for (final v in variants) if (v.status.usable) v];
  Map<HarmonisationStatus, int> get counts => {for (final s in HarmonisationStatus.values) s: variants.where((v) => v.status == s).length};

  /// Tableau prêt pour l'atelier de randomisation mendélienne (les instruments écartés gardent des β vides).
  Dataset toDataset({String? exposureName, String? outcomeName}) => Dataset(
        ['variant', 'chromosome', 'position', 'effect_allele', 'other_allele', 'beta_x', 'se_x', 'beta_y', 'se_y', 'eaf_x', 'harmonisation'],
        [
          for (final h in variants)
            [
              h.exposure.id, h.exposure.chromosome, h.exposure.position?.toString(), h.exposure.effectAllele, h.exposure.otherAllele,
              h.status.usable ? '${h.exposure.beta}' : null, h.status.usable ? '${h.exposure.se}' : null,
              h.by?.toString(), h.byse?.toString(), h.exposure.eaf?.toString(), h.status.label,
            ]
        ],
        source: tr('${exposure.source} (exposition) × ${outcome.source} (issue) : ${variants.length} instruments (p < ${_sci(pThreshold)}, clumping ${windowKb.round()} kb), ${usable.length} harmonisés',
            '${exposure.source} (exposure) × ${outcome.source} (outcome): ${variants.length} instruments (p < ${_sci(pThreshold)}, ${windowKb.round()} kb clumping), ${usable.length} harmonised'),
      );

  /// Résumé lisible (une ligne par statut non nul).
  List<String> summary() => [
        tr('${exposure.variants.length} variants dans l\'exposition, $significant à p < ${_sci(pThreshold)}, ${variants.length} instruments après clumping (${windowKb.round()} kb).',
            '${exposure.variants.length} variants in the exposure, $significant at p < ${_sci(pThreshold)}, ${variants.length} instruments after clumping (${windowKb.round()} kb).'),
        if (outcome.fromOddsRatio) tr('Issue fournie en OR : β = log(OR).', 'Outcome given as OR: β = log(OR).'),
        for (final e in counts.entries) if (e.value > 0) tr('${e.key.label} : ${e.value}', '${e.key.label}: ${e.value}'),
        tr('${usable.length} instruments utilisables pour la randomisation mendélienne.', '${usable.length} instruments usable for Mendelian randomization.'),
      ];
}

String _sci(double p) {
  final e = (math.log(p) / math.ln10).floor();
  final m = p / math.pow(10, e);
  final ms = m.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return ms == '1' ? '1e$e' : '${ms}e$e';
}

const _complement = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'};
bool _palindromic(String a, String b) => _complement[a] == b;

/// Harmonisation (TwoSampleMR, action 2) : allèles identiques → aligné ; inversés → β_issue changé de signe ; sinon
/// complément de brin de l'issue puis mêmes tests ; sinon incompatible. Palindromiques (A/T, C/G) : écartés si la
/// fréquence de l'allèle à effet de l'exposition est dans ]1 − [palindromeMax] ; [palindromeMax][ ou si une fréquence
/// manque ; sinon β_issue retourné quand les deux fréquences sont de part et d'autre de 0,5.
GwasHarmonisation harmoniseGwas(GwasSumstats exposure, GwasSumstats outcome,
    {double pThreshold = 5e-8, double windowKb = 10000, double palindromeMax = 0.58}) {
  final inst = selectInstruments(exposure, pThreshold: pThreshold, windowKb: windowKb);
  final significant = exposure.variants.where((v) => gwasP(v) < pThreshold).length;
  final lo = 1 - palindromeMax;
  final out = <HarmonisedVariant>[];
  for (final e in inst) {
    final o = outcome.byId[e.id];
    if (o == null) {
      out.add(HarmonisedVariant(e, HarmonisationStatus.absent, null, null));
      continue;
    }
    final a1 = e.effectAllele, a2 = e.otherAllele;
    if (_palindromic(a1, a2)) {
      final fx = e.eaf, fy = o.eaf;
      // L'issue doit porter la même paire d'allèles (dans un sens ou dans l'autre).
      final samePair = (o.effectAllele == a1 && o.otherAllele == a2) || (o.effectAllele == a2 && o.otherAllele == a1);
      if (!samePair) {
        out.add(HarmonisedVariant(e, HarmonisationStatus.incompatible, null, null));
      } else if (fx == null || fy == null || (fx > lo && fx < palindromeMax)) {
        out.add(HarmonisedVariant(e, HarmonisationStatus.palindromicAmbiguous, null, null));
      } else {
        final flip = (fx < 0.5) != (fy < 0.5);
        out.add(HarmonisedVariant(e, flip ? HarmonisationStatus.palindromicFlipped : HarmonisationStatus.palindromicAligned, flip ? -o.beta : o.beta, o.se));
      }
      continue;
    }
    HarmonisedVariant? h;
    for (final strand in [false, true]) {
      final b1 = strand ? _complement[o.effectAllele] : o.effectAllele, b2 = strand ? _complement[o.otherAllele] : o.otherAllele;
      if (a1 == b1 && a2 == b2) {
        h = HarmonisedVariant(e, strand ? HarmonisationStatus.strand : HarmonisationStatus.aligned, o.beta, o.se);
      } else if (a1 == b2 && a2 == b1) {
        h = HarmonisedVariant(e, strand ? HarmonisationStatus.strandFlipped : HarmonisationStatus.flipped, -o.beta, o.se);
      }
      if (h != null) break;
    }
    out.add(h ?? HarmonisedVariant(e, HarmonisationStatus.incompatible, null, null));
  }
  return GwasHarmonisation(out, significant, pThreshold, windowKb, palindromeMax, exposure, outcome);
}
