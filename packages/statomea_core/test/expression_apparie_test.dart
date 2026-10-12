import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('expression_apparie');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  List<String> s(Object? l) => [for (final x in l as List) '$x'];
  (List<String>, List<List<double>>) read(String f) {
    final lines = File('test/reference/$f').readAsLinesSync().skip(1).where((l) => l.isNotEmpty).toList();
    return ([for (final l in lines) l.split(',').first.replaceAll('"', '')], [for (final l in lines) [for (final c in l.split(',').skip(1)) double.parse(c)]]);
  }

  void check(ExpressionContrast c, Map r, {bool withAdj = true}) {
    final lfc = v(r['logFC']), t = v(r['t']), p = v(r['p']);
    for (var g = 0; g < lfc.length; g++) {
      expect(c.logFC[g], closeRel(lfc[g], rel: 1e-9, abs: 1e-11), reason: 'logFC $g');
      expect(c.t[g], closeRel(t[g], rel: 1e-9, abs: 1e-10), reason: 't $g');
      expect(c.p[g], closeRel(p[g], rel: 1e-9, abs: 0), reason: 'p $g');
      if (withAdj) expect(c.adjP[g], closeRel(v(r['adj'])[g], rel: 1e-9, abs: 0), reason: 'adj $g');
    }
  }

  test('avant/après apparié : sujet en effet fixe = limma ~ patient + temps', () {
    final r = ref['paired'] as Map;
    final (genes, counts) = read('rnaseq_apparie_simule.csv');
    final fit = voomLimmaDesign(genes, counts, ExpressionDesign(s(r['temps']), reference: 'avant', factors: {'patient': s(r['patient'])}), minSamples: 6);
    expect(fit.genes, r['kept']);
    expect(fit.dfPrior, closeRel(asD(r['df_prior'])!, rel: 1e-8));
    expect(fit.s2Prior, closeRel(asD(r['s2_prior'])!, rel: 1e-8));
    check(fit.contrasts.single, r);
    expect(fit.contrasts.single.adjP.where((p) => p < 0.05).length, r['n_sig']);
  });

  group('patients/témoins, 2 sites par sujet : corrélation intra-sujet (duplicateCorrelation) et GLS', () {
    final r = ref['block'] as Map;
    final (genes, counts) = read('rnaseq_bloc_simule.csv');
    final design = ExpressionDesign(s(r['statut']), reference: 'temoin', factors: {'site': s(r['site'])}, block: s(r['sujet']));
    final fit = voomLimmaDesign(genes, counts, design, minSamples: 8);

    test('corrélations consensuelles des deux passes', () {
      expect(fit.genes, r['kept']);
      expect(fit.blockCorrelation1, closeRel(asD(r['rho1'])!, rel: 1e-12));
      expect(fit.blockCorrelation2, closeRel(asD(r['rho2'])!, rel: 1e-12));
    });

    test('poids voom de la seconde passe (GLS par bloc)', () {
      final w = [for (final row in r['w_head'] as List) v(row)];
      for (var g = 0; g < 3; g++) {
        expect(fit.weights[g], [for (final x in w[g]) closeRel(x, rel: 1e-9)]);
      }
    });

    test('eBayes et statut patient − témoin (coefficient) = limma lmFit(block, correlation)', () {
      expect(fit.dfPrior, closeRel(asD(r['df_prior'])!, rel: 1e-10));
      expect(fit.s2Prior, closeRel(asD(r['s2_prior'])!, rel: 1e-10));
      check(fit.contrasts.single, r['status'] as Map);
      expect(fit.contrasts.single.adjP.where((p) => p < 0.05).length, r['n_sig']);
    });
  });

  test('corrélations par gène (atanh) de duplicateCorrelation, passe 1', () {
    final r = ref['block'] as Map;
    final (genes, counts) = read('rnaseq_bloc_simule.csv');
    // On reconstitue la passe 1 : voom sans bloc, puis duplicateCorrelation avec ses poids.
    final d = ExpressionDesign(s(r['statut']), reference: 'temoin', factors: {'site': s(r['site'])});
    final f0 = voomLimmaDesign(genes, counts, d, minSamples: 8);
    final x = [for (var i = 0; i < 16; i++) [1.0, s(r['statut'])[i] == 'patient' ? 1.0 : 0.0, s(r['site'])[i] == 'sang' ? 1.0 : 0.0]];
    final dc = duplicateCorrelation(f0.logCpm, x, s(r['sujet']), weights: f0.weights);
    final head = v(r['atanh1_head']);
    for (var g = 0; g < head.length; g++) {
      expect(dc.atanh[g], closeRel(head[g], rel: 1e-9, abs: 1e-11), reason: 'gène $g');
    }
  });

  test('sujet déjà dans le modèle, sujets à un seul échantillon : refus explicites', () {
    final r = ref['paired'] as Map;
    final (genes, counts) = read('rnaseq_apparie_simule.csv');
    expect(() => voomLimmaDesign(genes, counts, ExpressionDesign(s(r['temps']), factors: {'patient': s(r['patient'])}, block: s(r['patient']))),
        throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'block_in_design')));
    expect(() => voomLimmaDesign(genes, counts, ExpressionDesign(s(r['temps']), block: [for (var i = 0; i < 12; i++) 'S$i'])),
        throwsA(isA<StatInputError>().having((e) => e.code, 'code', 'block_size')));
  });

  test('choix automatique : effet fixe si le sujet croise la comparaison, corrélation s\'il y est emboîté', () {
    final a = ref['paired'] as Map, b = ref['block'] as Map;
    expect(subjectAsFixedEffect(ExpressionDesign(s(a['temps'])), s(a['patient'])), isTrue);
    expect(subjectAsFixedEffect(ExpressionDesign(s(b['statut']), factors: {'site': s(b['site'])}), s(b['sujet'])), isFalse);
  });

  test('résultat présenté avec corrélation intra-sujet', () {
    final r = ref['block'] as Map;
    final (genes, counts) = read('rnaseq_bloc_simule.csv');
    final res = differentialExpressionDesign(genes, counts,
        ExpressionDesign(s(r['statut']), reference: 'temoin', factors: {'site': s(r['site'])}, block: s(r['sujet'])), minSamples: 8);
    expect(res.statistics['block_correlation'], closeRel(asD(r['rho2'])!, rel: 1e-12));
    expect(res.statistics['n_sig'], r['n_sig']);
    expect(res.checks.firstWhere((c) => c.id == 'pairing').status, CheckStatus.ok);
    expect(res.formula, contains('corrélation intra-sujet'));
  });
}
