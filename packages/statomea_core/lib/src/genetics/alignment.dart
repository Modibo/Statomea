/// Recherche par alignement local de type BLAST, entièrement hors ligne, contre une bibliothèque FASTA fournie
/// par l'utilisateur (aucune base en ligne n'est interrogée, aucune séquence ne quitte l'appareil) :
///  - alignement optimal de Smith-Waterman (1981) à pénalités de gap affines (Gotoh 1982) : une brèche de
///    longueur k coûte « ouverture + k × extension » (convention de BLAST et de Biostrings) ;
///  - ADN : récompense/pénalité 2/−3, gaps 5/2 (paramètres de `blastn -task blastn`), deux brins ;
///    protéines : BLOSUM62, gaps 11/1 (paramètres de `blastp`) ;
///  - statistiques de Karlin-Altschul (1990) : bit score S' = (λS − ln K)/ln 2, E = K·m'·n'·e^(−λS) sur
///    l'espace de recherche effectif après ajustement de longueur (algorithme de BLAST+, Altschul et al. 2001) ;
///    pour les protéines, correction de taille finie de Spouge (Park, Sheetlin, Spouge 2012), comme blastp.
/// Contrairement à BLAST, l'alignement n'est pas heuristique (pas de graines) : il est toujours optimal.
/// Validé contre Biostrings::pairwiseAlignment et BLAST+ 2.17 local (`validation/r/21_alignement.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import 'blosum62.dart';

enum SeqType { dna, protein }

class FastaRecord {
  final String id;
  final String description;
  final String sequence;
  const FastaRecord(this.id, this.sequence, {this.description = ''});
}

/// Lecture FASTA : en-têtes « >identifiant description », séquences sur une ou plusieurs lignes ;
/// espaces, chiffres et caractères de fin (*) d'alignement ignorés ; majuscules.
List<FastaRecord> parseFasta(String text) {
  final out = <FastaRecord>[];
  String? id;
  var desc = '';
  final buf = StringBuffer();
  void flush() {
    if (id != null) {
      final s = buf.toString();
      if (s.isEmpty) {
        throw StatInputError('empty_sequence', tr('Séquence vide pour « $id ».', 'Empty sequence for "$id".'));
      }
      out.add(FastaRecord(id, s, description: desc));
    }
    buf.clear();
  }

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(';')) continue;
    if (line.startsWith('>')) {
      flush();
      final h = line.substring(1).trim();
      final sp = h.indexOf(RegExp(r'\s'));
      id = sp < 0 ? h : h.substring(0, sp);
      if (id.isEmpty) id = 'seq${out.length + 1}';
      desc = sp < 0 ? '' : h.substring(sp + 1).trim();
    } else {
      if (id == null) {
        id = 'seq1';
        desc = '';
      }
      buf.write(line.toUpperCase().replaceAll(RegExp(r'[^A-Z\-]'), '').replaceAll('-', ''));
    }
  }
  flush();
  if (out.isEmpty) throw StatInputError('no_sequence', tr('Aucune séquence lue.', 'No sequence read.'));
  return out;
}

/// ADN si au moins 90 % de A, C, G, T, U, N.
SeqType guessSeqType(String s) {
  if (s.isEmpty) return SeqType.dna;
  final n = RegExp('[ACGTUN]').allMatches(s).length;
  return n >= 0.9 * s.length ? SeqType.dna : SeqType.protein;
}

String reverseComplement(String s) {
  const comp = {'A': 'T', 'T': 'A', 'G': 'C', 'C': 'G', 'U': 'A', 'N': 'N', 'R': 'Y', 'Y': 'R', 'K': 'M', 'M': 'K', 'S': 'S', 'W': 'W', 'B': 'V', 'V': 'B', 'D': 'H', 'H': 'D'};
  return [for (var i = s.length - 1; i >= 0; i--) comp[s[i]] ?? 'N'].join();
}

/// Système de notation et paramètres statistiques (tables de BLAST+, `blast_stat.c`) pour les alignements avec gaps.
class ScoringScheme {
  final SeqType type;
  final int match, mismatch, gapOpen, gapExtend;
  final double lambda, k, h, alpha, beta;

  /// Paramètres de Gumbel de la correction de taille finie (a, α, σ avec gaps ; a, α sans gaps) ; null : pas de correction.
  final ({double a, double alpha, double sigma, double aUn, double alphaUn})? gumbel;
  const ScoringScheme._(this.type, this.match, this.mismatch, this.gapOpen, this.gapExtend, this.lambda, this.k, this.h, this.alpha, this.beta, [this.gumbel]);

  /// blastn -task blastn : 2/−3, gaps 5/2 (λ = 0,625 ; K = 0,41 ; H = 0,78 ; α = 0,8 ; β = −2).
  static const dna = ScoringScheme._(SeqType.dna, 2, -3, 5, 2, 0.625, 0.41, 0.78, 0.8, -2);

  /// blastp : BLOSUM62, gaps 11/1 (λ = 0,267 ; K = 0,041 ; H = 0,14 ; α = 1,9 ; β = −30).
  static const protein =
      ScoringScheme._(SeqType.protein, 0, 0, 11, 1, 0.267, 0.041, 0.14, 1.9, -30, (a: 1.9, alpha: 42.6, sigma: 43.6, aUn: 0.7916, alphaUn: 4.964660));

  String get label => type == SeqType.dna
      ? tr('ADN : +$match/$mismatch, gaps $gapOpen/$gapExtend (comme blastn -task blastn)', 'DNA: +$match/$mismatch, gaps $gapOpen/$gapExtend (as blastn -task blastn)')
      : tr('Protéines : BLOSUM62, gaps $gapOpen/$gapExtend (comme blastp)', 'Proteins: BLOSUM62, gaps $gapOpen/$gapExtend (as blastp)');

  double bitScore(int score) => (lambda * score - math.log(k)) / math.ln2;
  /// E-value de Karlin-Altschul sur l'espace effectif ; pour les protéines, correction de Spouge
  /// (`BLAST_SpougeStoE`) avec [queryLength], [subjectLength] et [dbLength] réels.
  double evalue(int score, double searchSpace, {int? queryLength, int? subjectLength, int? dbLength}) {
    final g = gumbel;
    if (g == null || queryLength == null || subjectLength == null || dbLength == null) return k * searchSpace * math.exp(-lambda * score);
    final gg = (gapOpen + gapExtend).toDouble();
    final b = 2 * gg * (g.aUn - g.a), betaG = 2 * gg * (g.alphaUn - g.alpha), tau = 2 * gg * (g.alphaUn - g.sigma);
    final y = score.toDouble();
    double side(int len) => len - (g.a * y + b);
    final v = math.max(2 * g.alpha / lambda, g.alpha * y + betaG);
    final sv = math.sqrt(v);
    final mL = side(queryLength), nL = side(subjectLength);
    final mF = mL / sv, nF = nL / sv;
    final pm = normalCdf(mF), pn = normalCdf(nF);
    final p1 = mL * pm + sv * normalPdf(mF), p2 = nL * pn + sv * normalPdf(nF);
    final c = math.max(2 * g.sigma / lambda, g.sigma * y + tau);
    final area = p1 * p2 + c * pm * pn;
    return area * k * math.exp(-lambda * y) * dbLength / subjectLength;
  }
}

final _aaIndex = {for (var i = 0; i < blosum62Letters.length; i++) blosum62Letters[i]: i};

/// Codage des résidus en indices de matrice.
Int32List _encode(String s, SeqType t) {
  final out = Int32List(s.length);
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (t == SeqType.dna) {
      out[i] = switch (c) { 'A' => 0, 'C' => 1, 'G' => 2, 'T' || 'U' => 3, _ => 4 };
    } else {
      out[i] = _aaIndex[c] ?? _aaIndex['X']!;
    }
  }
  return out;
}

/// Alignement local (coordonnées 1-indexées ; sur le brin moins, sStart > sEnd comme dans BLAST).
class LocalAlignment {
  final int score;
  final int qStart, qEnd, sStart, sEnd;
  final String alignedQuery, midline, alignedSubject;
  final int identities, positives, gaps, length;
  final bool minusStrand;
  const LocalAlignment(this.score, this.qStart, this.qEnd, this.sStart, this.sEnd, this.alignedQuery, this.midline, this.alignedSubject,
      {required this.identities, required this.positives, required this.gaps, required this.length, this.minusStrand = false});
  double get identity => length == 0 ? 0 : identities / length;
}

/// Nombre maximal de cellules de programmation dynamique par paire (mémoire de la matrice de retour arrière).
const maxAlignmentCells = 60000000;

/// Smith-Waterman–Gotoh optimal. Retourne null si aucun score positif.
LocalAlignment? smithWaterman(String query, String subject, ScoringScheme sc) {
  final m = query.length, n = subject.length;
  if (m == 0 || n == 0) return null;
  if (m * n > maxAlignmentCells) {
    throw StatInputError('too_long', tr('Séquences trop longues pour un alignement optimal sur l\'appareil ($m×$n positions).',
        'Sequences too long for an optimal alignment on the device ($m×$n positions).'));
  }
  final a = _encode(query, sc.type), b = _encode(subject, sc.type);
  int sub(int x, int y) => sc.type == SeqType.dna ? (x == y && x < 4 ? sc.match : sc.mismatch) : blosum62[x][y];
  final openExt = sc.gapOpen + sc.gapExtend, ext = sc.gapExtend;
  const neg = -1 << 40;
  // Ligne courante de H et E ; F par colonne.
  final hPrev = List<int>.filled(n + 1, 0), hCur = List<int>.filled(n + 1, 0);
  final f = List<int>.filled(n + 1, neg);
  // Retour arrière : bits 0–1 origine de H (0 arrêt, 1 diagonale, 2 E, 3 F) ; bit 2 E étendu ; bit 3 F étendu.
  final tb = Uint8List((m + 1) * (n + 1));
  var best = 0, bi = 0, bj = 0;
  for (var i = 1; i <= m; i++) {
    var e = neg;
    hCur[0] = 0;
    final ai = a[i - 1];
    for (var j = 1; j <= n; j++) {
      var code = 0;
      // E : brèche dans la requête (avance dans le sujet).
      final eOpen = hCur[j - 1] - openExt, eExt = e - ext;
      if (eExt > eOpen) {
        e = eExt;
        code |= 4;
      } else {
        e = eOpen;
      }
      // F : brèche dans le sujet (avance dans la requête).
      final fOpen = hPrev[j] - openExt, fExt = f[j] - ext;
      if (fExt > fOpen) {
        f[j] = fExt;
        code |= 8;
      } else {
        f[j] = fOpen;
      }
      final d = hPrev[j - 1] + sub(ai, b[j - 1]);
      var h = 0, src = 0;
      if (d > h) {
        h = d;
        src = 1;
      }
      if (e > h) {
        h = e;
        src = 2;
      }
      if (f[j] > h) {
        h = f[j];
        src = 3;
      }
      hCur[j] = h;
      tb[i * (n + 1) + j] = code | src;
      if (h > best) {
        best = h;
        bi = i;
        bj = j;
      }
    }
    for (var j = 0; j <= n; j++) {
      hPrev[j] = hCur[j];
    }
  }
  if (best <= 0) return null;
  final qa = StringBuffer(), sa = StringBuffer(), mid = StringBuffer();
  final qs = <String>[], ss = <String>[], ms = <String>[];
  var i = bi, j = bj, state = 0; // 0 : H, 1 : E, 2 : F
  var ident = 0, pos = 0, gaps = 0;
  while (i > 0 && j > 0) {
    final t = tb[i * (n + 1) + j];
    if (state == 0) {
      final src = t & 3;
      if (src == 0) break;
      if (src == 1) {
        final x = a[i - 1], y = b[j - 1];
        final s = sub(x, y);
        qs.add(query[i - 1]);
        ss.add(subject[j - 1]);
        if (query[i - 1] == subject[j - 1] && (sc.type == SeqType.protein || x < 4)) {
          ident++;
          pos++;
          ms.add(sc.type == SeqType.dna ? '|' : query[i - 1]);
        } else if (sc.type == SeqType.protein && s > 0) {
          pos++;
          ms.add('+');
        } else {
          ms.add(' ');
        }
        i--;
        j--;
      } else {
        state = src == 2 ? 1 : 2;
      }
    } else if (state == 1) {
      qs.add('-');
      ss.add(subject[j - 1]);
      ms.add(' ');
      gaps++;
      if (t & 4 == 0) state = 0;
      j--;
    } else {
      qs.add(query[i - 1]);
      ss.add('-');
      ms.add(' ');
      gaps++;
      if (t & 8 == 0) state = 0;
      i--;
    }
  }
  for (var k = qs.length - 1; k >= 0; k--) {
    qa.write(qs[k]);
    sa.write(ss[k]);
    mid.write(ms[k]);
  }
  return LocalAlignment(best, i + 1, bi, j + 1, bj, qa.toString(), mid.toString(), sa.toString(),
      identities: ident, positives: pos, gaps: gaps, length: qs.length);
}

/// Meilleur alignement sur les deux brins (ADN) ; coordonnées exprimées sur la requête directe.
LocalAlignment? alignBothStrands(String query, String subject, ScoringScheme sc) {
  final plus = smithWaterman(query, subject, sc);
  if (sc.type != SeqType.dna) return plus;
  final minus = smithWaterman(query, reverseComplement(subject), sc);
  if (minus == null || (plus != null && plus.score >= minus.score)) return plus;
  final n = subject.length;
  // Alignement de la requête contre le complément inverse du sujet : on ramène les positions au sujet direct.
  return LocalAlignment(minus.score, minus.qStart, minus.qEnd, n - minus.sStart + 1, n - minus.sEnd + 1, minus.alignedQuery, minus.midline, minus.alignedSubject,
      identities: minus.identities, positives: minus.positives, gaps: minus.gaps, length: minus.length, minusStrand: true);
}

/// Ajustement de longueur de BLAST+ (`BLAST_ComputeLengthAdjustment`) : ℓ tel que
/// ℓ = (α/λ)·ln(K·(m − ℓ)(n − N·ℓ)) + β, arrondi à l'entier inférieur.
int lengthAdjustment(ScoringScheme sc, int queryLength, int dbLength, int dbSeqs) {
  final m = queryLength.toDouble(), n = dbLength.toDouble(), nn = dbSeqs.toDouble();
  final alphaDLambda = sc.alpha / sc.lambda, logK = math.log(sc.k);
  final a = nn, mb = m * nn + n, c = n * m - math.max(m, n) / sc.k;
  if (c < 0) return 0;
  var ellMin = 0.0, ellMax = 2 * c / (mb + math.sqrt(mb * mb - 4 * a * c));
  var ellNext = 0.0, converged = false;
  for (var i = 1; i <= 20; i++) {
    final ell = ellNext;
    final ss = (m - ell) * (n - nn * ell);
    final ellBar = alphaDLambda * (logK + math.log(ss)) + sc.beta;
    if (ellBar >= ell) {
      ellMin = ell;
      if (ellBar - ellMin <= 1.0) {
        converged = true;
        break;
      }
      if (ellMin == ellMax) break;
    } else {
      ellMax = ell;
    }
    ellNext = ellMin <= ellBar && ellBar <= ellMax ? ellBar : (i == 1 ? ellMax : (ellMin + ellMax) / 2);
  }
  var adj = ellMin.toInt();
  if (converged) {
    final ell = ellMin.ceilToDouble();
    if (ell <= ellMax) {
      final ss = (m - ell) * (n - nn * ell);
      if (alphaDLambda * (logK + math.log(ss)) + sc.beta >= ell) adj = ell.toInt();
    }
  }
  return adj;
}

/// Espace de recherche effectif (m − ℓ)(n − N·ℓ).
double effectiveSearchSpace(ScoringScheme sc, int queryLength, int dbLength, int dbSeqs) {
  final l = lengthAdjustment(sc, queryLength, dbLength, dbSeqs);
  return (queryLength - l).toDouble() * (dbLength - dbSeqs * l).toDouble();
}

class AlignmentHit {
  final FastaRecord subject;
  final LocalAlignment alignment;
  final double bitScore, evalue;
  const AlignmentHit(this.subject, this.alignment, this.bitScore, this.evalue);
}

/// Séquence requête nettoyée : en-tête FASTA éventuel retiré (première séquence seulement), lettres en majuscules.
String cleanQuery(String query) {
  final q = query.trimLeft().startsWith('>') ? parseFasta(query).first.sequence : query.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (q.isEmpty) throw StatInputError('no_sequence', tr('Séquence requête vide.', 'Empty query sequence.'));
  return q;
}

/// Recherche de la requête contre toute la bibliothèque ; un alignement (le meilleur) par séquence.
({List<AlignmentHit> hits, double searchSpace, int lengthAdjustment, ScoringScheme scheme}) alignmentSearch(String query, List<FastaRecord> library, {SeqType? type}) {
  final q = cleanQuery(query);
  if (library.isEmpty) throw StatInputError('no_library', tr('Bibliothèque de référence vide.', 'Empty reference library.'));
  final t = type ?? guessSeqType(q);
  final sc = t == SeqType.dna ? ScoringScheme.dna : ScoringScheme.protein;
  final dbLen = library.fold<int>(0, (a, r) => a + r.sequence.length);
  final adj = lengthAdjustment(sc, q.length, dbLen, library.length);
  final space = (q.length - adj).toDouble() * (dbLen - library.length * adj).toDouble();
  final hits = <AlignmentHit>[];
  for (final r in library) {
    final al = alignBothStrands(q, r.sequence, sc);
    if (al == null) continue;
    hits.add(AlignmentHit(r, al, sc.bitScore(al.score), sc.evalue(al.score, space, queryLength: q.length, subjectLength: r.sequence.length, dbLength: dbLen)));
  }
  hits.sort((x, y) {
    final k = y.alignment.score.compareTo(x.alignment.score);
    return k != 0 ? k : x.subject.id.compareTo(y.subject.id);
  });
  return (hits: hits, searchSpace: space, lengthAdjustment: adj, scheme: sc);
}

/// « E = 1,2e-5 » ou « E < 1e−180 » (pas « E = < … »).
String _eq(double e) => e < 1e-180 ? 'E < 1e−180' : 'E = ${_e(e)}';

String _e(double e) => e < 1e-180 ? '< 1e−180' : (e < 1e-3 ? tr(e.toStringAsExponential(2).replaceAll('.', ','), e.toStringAsExponential(2)) : fmt(e, digits: 3));

/// Résultat présenté : tableau des correspondances, alignement détaillé de la meilleure, repères d'identification.
AnalysisResult localAlignmentSearch(String query, List<FastaRecord> library, {SeqType? type, double maxEvalue = 10, int maxHits = 50, String queryName = ''}) {
  final res = alignmentSearch(query, library, type: type);
  final sc = res.scheme;
  final q = cleanQuery(query);
  final shown = [for (final h in res.hits) if (h.evalue <= maxEvalue) h].take(maxHits).toList();
  final qn = queryName.isEmpty ? tr('requête', 'query') : queryName;
  final top = shown.isEmpty ? null : shown.first;
  final second = shown.length > 1 ? shown[1] : null;
  final cover = top == null ? 0.0 : (top.alignment.qEnd - top.alignment.qStart + 1) / q.length;
  final nonStd = RegExp(sc.type == SeqType.dna ? '[^ACGTU]' : '[BJZXUO*]').allMatches(q).length;
  String strand(LocalAlignment a) => sc.type == SeqType.protein ? '' : (a.minusStrand ? tr(' (brin −)', ' (− strand)') : ' (+)');
  String block(LocalAlignment a) {
    final sb = StringBuffer();
    var qi = a.qStart, si = a.sStart;
    final dir = a.minusStrand ? -1 : 1;
    for (var k = 0; k < a.length; k += 60) {
      final end = math.min(a.length, k + 60);
      final qs = a.alignedQuery.substring(k, end), ss = a.alignedSubject.substring(k, end);
      final qLen = qs.replaceAll('-', '').length, sLen = ss.replaceAll('-', '').length;
      sb.writeln('Q ${qi.toString().padLeft(6)}  $qs  ${qi + qLen - 1}');
      sb.writeln('         ${a.midline.substring(k, end)}');
      sb.writeln('S ${si.toString().padLeft(6)}  $ss  ${si + dir * (sLen - 1)}');
      sb.writeln();
      qi += qLen;
      si += dir * sLen;
    }
    return sb.toString();
  }

  return AnalysisResult(
    methodId: 'local_alignment',
    methodName: tr('Alignement local hors ligne (type BLAST)', 'Offline local alignment (BLAST-like)'),
    inputs: {'query_length': q.length, 'library_sequences': library.length, 'library_letters': library.fold<int>(0, (a, r) => a + r.sequence.length), 'type': sc.type.name, 'max_evalue': maxEvalue},
    formula: tr(
        'Smith-Waterman optimal à gaps affines (coût d\'une brèche de longueur k = ${sc.gapOpen} + ${sc.gapExtend}k) ; ${sc.label}. Bit score = (λS − ln K)/ln 2 ; E = K·m\'·n\'·e^(−λS), '
            'm\' = m − ℓ, n\' = n − N·ℓ (ajustement de longueur ℓ de BLAST+) ; λ = ${sc.lambda}, K = ${sc.k}${sc.gumbel != null ? " ; correction de taille finie de Spouge (comme blastp)" : ""}.',
        'Optimal Smith-Waterman with affine gaps (cost of a gap of length k = ${sc.gapOpen} + ${sc.gapExtend}k); ${sc.label}. Bit score = (λS − ln K)/ln 2; E = K·m\'·n\'·e^(−λS), '
            'm\' = m − ℓ, n\' = n − N·ℓ (BLAST+ length adjustment ℓ); λ = ${sc.lambda}, K = ${sc.k}${sc.gumbel != null ? "; Spouge finite-size correction (as blastp)" : ""}.'),
    estimates: [
      if (top != null) ...[
        Estimate(tr('Identité avec ${top.subject.id}', 'Identity with ${top.subject.id}'), top.alignment.identity),
        Estimate(tr('Couverture de la requête', 'Query coverage'), cover),
        Estimate(tr('E-value', 'E-value'), top.evalue),
      ],
    ],
    statistics: {
      'search_space': res.searchSpace,
      'length_adjustment': res.lengthAdjustment.toDouble(),
      'hits': shown.length.toDouble(),
      for (final h in res.hits) ...{
        'score_${h.subject.id}': h.alignment.score.toDouble(),
        'bits_${h.subject.id}': h.bitScore,
        'evalue_${h.subject.id}': h.evalue,
        'identity_${h.subject.id}': h.alignment.identity,
      },
    },
    checks: [
      Check('library', tr('Bibliothèque de référence pertinente et curée', 'Relevant, curated reference library'), CheckStatus.notAssessed,
          tr('Le résultat ne vaut que ce que vaut la bibliothèque : une espèce absente ne peut pas être trouvée, et une séquence mal annotée donne une identification fausse.',
              'The result is only as good as the library: an absent species cannot be found, and a misannotated sequence gives a wrong identification.')),
      Check('coverage', tr('Couverture de la requête ≥ 80 %', 'Query coverage ≥ 80%'), top == null ? CheckStatus.notAssessed : (cover >= 0.8 ? CheckStatus.ok : CheckStatus.warning),
          top == null ? tr('Aucune correspondance.', 'No match.') : tr('${fmtPct(cover)} de la requête est alignée.', '${fmtPct(cover)} of the query is aligned.')),
      Check('quality', tr('Séquence sans ambiguïtés', 'Sequence without ambiguities'), nonStd == 0 ? CheckStatus.ok : CheckStatus.warning,
          nonStd == 0
              ? tr('Aucun caractère ambigu.', 'No ambiguous character.')
              : tr('$nonStd position(s) ambiguë(s), comptées comme discordances : contrôler l\'électrophorégramme.', '$nonStd ambiguous position(s), counted as mismatches: check the chromatogram.')),
      if (second != null && sc.type == SeqType.dna)
        Check('separation', tr('Écart avec la 2e correspondance', 'Gap with the 2nd match'), (top!.alignment.identity - second.alignment.identity) >= 0.008 ? CheckStatus.ok : CheckStatus.warning,
            tr('${top.subject.id} : ${fmtPct(top.alignment.identity)} ; ${second.subject.id} : ${fmtPct(second.alignment.identity)}. Un écart < 0,8 point ne permet pas de trancher entre les deux.',
                '${top.subject.id}: ${fmtPct(top.alignment.identity)}; ${second.subject.id}: ${fmtPct(second.alignment.identity)}. A difference < 0.8 point does not discriminate between them.')),
    ],
    alerts: [
      if (top == null)
        Alert('no_hit', Severity.info, tr('Aucune correspondance avec E ≤ ${fmt(maxEvalue)}.', 'No match with E ≤ ${fmt(maxEvalue)}.')),
      if (top != null && top.evalue > 1e-3)
        Alert('weak', Severity.caution,
            tr('Meilleure E-value ${_e(top.evalue)} : une similarité de cet ordre est attendue par hasard ; ne pas conclure à une homologie.',
                'Best E-value ${_e(top.evalue)}: similarity of this order is expected by chance; do not conclude homology.')),
    ],
    tables: [
      ResultTable(tr('Correspondances', 'Matches'), [
        tr('Séquence', 'Sequence'), 'Description', 'Score', 'Bits', 'E-value', tr('Identité', 'Identity'), tr('Longueur', 'Length'), 'Gaps', tr('Requête', 'Query'), tr('Sujet', 'Subject')
      ], [
        for (final h in shown)
          [
            h.subject.id,
            h.subject.description,
            '${h.alignment.score}',
            fmt(h.bitScore, digits: 1),
            _e(h.evalue),
            '${h.alignment.identities}/${h.alignment.length} (${fmtPct(h.alignment.identity)})',
            '${h.alignment.length}',
            '${h.alignment.gaps}',
            '${h.alignment.qStart}–${h.alignment.qEnd}',
            '${h.alignment.sStart}–${h.alignment.sEnd}${strand(h.alignment)}',
          ]
      ]),
    ],
    figures: {
      if (top != null) 'alignment': {'subject': top.subject.id, 'text': block(top.alignment)},
    },
    log: [
      tr('$qn : ${q.length} ${sc.type == SeqType.dna ? "nt" : "aa"} ; bibliothèque : ${library.length} séquence(s).', '$qn: ${q.length} ${sc.type == SeqType.dna ? "nt" : "aa"}; library: ${library.length} sequence(s).'),
      tr('Ajustement de longueur ℓ = ${res.lengthAdjustment} ; espace de recherche effectif ${res.searchSpace.toStringAsFixed(0)}.',
          'Length adjustment ℓ = ${res.lengthAdjustment}; effective search space ${res.searchSpace.toStringAsFixed(0)}.'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Rechercher les séquences de référence les plus semblables (identification d\'un isolat par l\'ARNr 16S, d\'un gène de résistance, d\'une protéine) sans envoyer la séquence sur Internet ; l\'E-value indique combien de correspondances aussi bonnes on attendrait par hasard dans cette bibliothèque.',
          'Finding the most similar reference sequences (identifying an isolate by 16S rRNA, a resistance gene, a protein) without sending the sequence over the Internet; the E-value tells how many matches this good would be expected by chance in this library.'),
      whatItMeans: top == null
          ? tr('Aucune séquence de la bibliothèque n\'est significativement semblable.', 'No library sequence is significantly similar.')
          : tr(
              'Meilleure correspondance : ${top.subject.id}${top.subject.description.isEmpty ? "" : " (${top.subject.description})"}, identité ${fmtPct(top.alignment.identity)} sur ${top.alignment.length} positions, couverture ${fmtPct(cover)}, ${_eq(top.evalue)}.'
                  '${sc.type == SeqType.dna ? " Repères usuels pour l'ARNr 16S (CLSI MM18) : ≥ 99 % d'identité pour l'espèce, ≥ 97 % pour le genre, sur une séquence de qualité couvrant la région." : ""}',
              'Best match: ${top.subject.id}${top.subject.description.isEmpty ? "" : " (${top.subject.description})"}, identity ${fmtPct(top.alignment.identity)} over ${top.alignment.length} positions, coverage ${fmtPct(cover)}, ${_eq(top.evalue)}.'
                  '${sc.type == SeqType.dna ? " Usual benchmarks for 16S rRNA (CLSI MM18): ≥ 99% identity for species, ≥ 97% for genus, on a good-quality sequence covering the region." : ""}'),
      notJustified: tr(
          'Conclure à une espèce sur l\'identité seule quand plusieurs espèces sont proches (le 16S ne sépare pas certaines espèces) ; comparer des E-values obtenues sur des bibliothèques différentes ; inférer une fonction ou une résistance à partir d\'une similarité partielle.',
          'Concluding a species from identity alone when several species are close (16S does not separate some species); comparing E-values obtained on different libraries; inferring a function or resistance from partial similarity.'),
    ),
  );
}
