import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('alignement');
  final dna = ref['dna'] as Map, prot = ref['protein'] as Map;
  final libNt = parseFasta(File('test/reference/alignement_adn.fasta').readAsStringSync());
  final libAa = parseFasta(File('test/reference/alignement_proteines.fasta').readAsStringSync());

  // BLAST affiche les bit scores ≥ 100 tronqués à l'entier, sinon à 0,1 près ; E-values à 3 chiffres significatifs.
  void checkBlast(Map part, List<FastaRecord> lib) {
    final res = alignmentSearch(part['query'] as String, lib);
    expect(res.searchSpace, asD(part['eff_space']));
    final hits = {for (final h in res.hits) h.subject.id: h};
    for (final b in (part['blast'] as List).cast<Map>()) {
      final h = hits[b['sseqid']]!;
      expect(h.alignment.score, b['score'], reason: '${b['sseqid']} score');
      final bits = asD(b['bitscore'])!;
      expect(bits >= 100 ? h.bitScore.floorToDouble() : (h.bitScore * 10).roundToDouble() / 10, bits, reason: '${b['sseqid']} bits');
      final e = asD(b['evalue'])!;
      if (e == 0) {
        expect(h.evalue, lessThan(1e-180));
      } else {
        // Comparaison à la précision affichée par BLAST (2 chiffres significatifs sous 10, 3 au-delà de la virgule sinon).
        final digits = e >= 0.1 ? 2 : 3;
        expect(double.parse(h.evalue.toStringAsPrecision(digits)), closeRel(e, rel: 1e-9, abs: 0), reason: '${b['sseqid']} evalue ${h.evalue}');
      }
      // Coordonnées et composition de l'alignement identiques à BLAST.
      expect([h.alignment.qStart, h.alignment.qEnd, h.alignment.sStart, h.alignment.sEnd], [b['qstart'], b['qend'], b['sstart'], b['send']], reason: '${b['sseqid']} coords');
      expect([h.alignment.length, h.alignment.identities, h.alignment.gaps], [b['length'], b['nident'], b['gaps']], reason: '${b['sseqid']} composition');
    }
  }

  test('lecture FASTA', () {
    expect(libNt.length, dna['db_seqs']);
    expect(libNt.fold(0, (a, r) => a + r.sequence.length), dna['db_letters']);
    expect(libAa.fold(0, (a, r) => a + r.sequence.length), prot['db_letters']);
    final f = parseFasta('>a desc libre\nac gt\n12 acg\n>b\nMKV*\n');
    expect([f[0].id, f[0].description, f[0].sequence, f[1].sequence], ['a', 'desc libre', 'ACGTACG', 'MKV']);
    expect(guessSeqType(f[0].sequence), SeqType.dna);
    expect(guessSeqType('MKVLLAGHQ'), SeqType.protein);
  });

  test('scores Smith-Waterman contre Biostrings::pairwiseAlignment (ADN, deux brins)', () {
    final q = dna['query'] as String;
    final plus = (dna['sw_plus'] as List), minus = (dna['sw_minus'] as List);
    for (var i = 0; i < libNt.length; i++) {
      expect(smithWaterman(q, libNt[i].sequence, ScoringScheme.dna)!.score, plus[i]);
      expect(smithWaterman(reverseComplement(q), libNt[i].sequence, ScoringScheme.dna)!.score, minus[i]);
    }
  });

  test('scores Smith-Waterman contre Biostrings (protéines, BLOSUM62 11/1)', () {
    final q = prot['query'] as String;
    final sw = prot['sw'] as List;
    for (var i = 0; i < libAa.length; i++) {
      expect(smithWaterman(q, libAa[i].sequence, ScoringScheme.protein)!.score, sw[i]);
    }
  });

  test('blastn 2.17 : scores, bits, E-values, espace effectif, coordonnées', () => checkBlast(dna, libNt));
  test('blastp 2.17 : scores, bits, E-values, espace effectif, coordonnées', () => checkBlast(prot, libAa));

  test('paramètres de Karlin-Altschul identiques à ceux affichés par BLAST', () {
    expect([ScoringScheme.dna.lambda, ScoringScheme.dna.k, ScoringScheme.dna.h], [asD(dna['lambda']), asD(dna['K']), asD(dna['H'])]);
    expect([ScoringScheme.protein.lambda, ScoringScheme.protein.k, ScoringScheme.protein.h], [asD(prot['lambda']), asD(prot['K']), asD(prot['H'])]);
  });

  test('requête collée avec son en-tête FASTA : l\'en-tête est ignoré', () {
    final q = dna['query'] as String;
    final a = alignmentSearch('>isolat X séquence\n${q.substring(0, 200)}\n${q.substring(200)}\n', libNt);
    final b = alignmentSearch(q, libNt);
    expect(a.hits.first.alignment.score, b.hits.first.alignment.score);
    expect(a.searchSpace, b.searchSpace);
    final e = exampleFasta();
    final r = localAlignmentSearch(e.query, parseFasta(e.library));
    expect(r.tables.first.rows.first.first, 'ref2');
    expect(r.checks.firstWhere((c) => c.id == 'quality').status, CheckStatus.ok);
  });

  test('résultat présenté', () {
    final r = localAlignmentSearch(dna['query'] as String, libNt);
    expect(r.tables.first.rows.first.first, 'ref03');
    expect(r.figures['alignment'], isNotNull);
    expect(r.statistics['score_ref03'], 844);
  });
}
