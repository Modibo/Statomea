import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void main() {
  final ref = loadRef('fondamentaux');

  group('Proportions (R prop.test / binom.test)', () {
    for (final c in (ref['proportions'] as List).cast<Map<String, dynamic>>()) {
      test('${c['x']}/${c['n']}', () {
        final x = c['x'] as int, n = c['n'] as int;
        final w = wilsonCi(x, n), cp = clopperPearsonCi(x, n);
        final rw = dl(c['wilson']), rc = dl(c['exact']);
        expect(w.lower, closeRel(rw[0], rel: 1e-9));
        expect(w.upper, closeRel(rw[1], rel: 1e-9));
        expect(cp.lower, closeRel(rc[0], rel: 1e-8));
        expect(cp.upper, closeRel(rc[1], rel: 1e-8));
        final r = proportionCi(x, n);
        expect(r.estimates.first.value, closeRel(x / n));
        if (x == 0) expect(r.alerts.map((a) => a.code), contains('zero_events'));
      });
    }
  });

  group('Tableaux 2 × 2 (R fisher.test, chisq.test)', () {
    for (final c in (ref['two_by_two'] as List).cast<Map<String, dynamic>>()) {
      final a = c['a'] as int, b = c['b'] as int, cc = c['c'] as int, d = c['d'] as int;
      test('[$a $b / $cc $d]', () {
        final f = fisherExact(a, b, cc, d);
        expect(f.pValue, closeRel(asD(c['fisher_p'])!, rel: 1e-9));
        // R résout l'OR conditionnel avec uniroot (tolérance ≈ 1e-4) : tolérance 1e-3.
        expect(f.conditionalOr, closeRel(asD(c['fisher_or'])!, rel: 1e-3));
        // Bornes comparées à une résolution R de haute précision (même
        // équation, tol = 1e-14) ; fisher.test lui-même est à 5 % près.
        final ci = dl(c['fisher_ci_precise']);
        final ciR = dl(c['fisher_ci']);
        expect(f.lower, closeRel(ci[0], rel: 1e-7, abs: 1e-9));
        if (ci[1].isFinite) expect(f.upper, closeRel(ci[1], rel: 1e-7));
        if (ciR[1].isFinite) expect(f.upper, closeRel(ciR[1], rel: 0.05));
        final r = twoByTwo(a, b, cc, d, design: StudyDesign.cohort);
        expect(r.statistics['chi2'], closeRel(asD(c['chi2'])!, rel: 1e-10));
        expect(r.statistics['chi2_p'], closeRel(asD(c['chi2_p'])!, rel: 1e-9));
        expect(r.statistics['chi2_yates'], closeRel(asD(c['chi2_yates'])!, rel: 1e-10));
        expect(r.statistics['chi2_yates_p'], closeRel(asD(c['chi2_yates_p'])!, rel: 1e-9));
        final or = r.estimate('Odds ratio (Woolf)')!;
        expect(or.value, closeRel(asD(c['or'])!, rel: 1e-12));
        expect(or.lower, closeRel(dl(c['or_ci'])[0], rel: 1e-9));
        expect(or.upper, closeRel(dl(c['or_ci'])[1], rel: 1e-9));
        final rr = r.estimate('Risque relatif')!;
        expect(rr.value, closeRel(asD(c['rr'])!, rel: 1e-12));
        expect(rr.lower, closeRel(dl(c['rr_ci'])[0], rel: 1e-9));
        expect(rr.upper, closeRel(dl(c['rr_ci'])[1], rel: 1e-9));
        final rd = r.estimate('Différence de risques')!;
        expect(rd.value, closeRel(asD(c['rd'])!, rel: 1e-12));
        expect(rd.lower, closeRel(dl(c['rd_ci'])[0], rel: 1e-9));
        expect(rd.upper, closeRel(dl(c['rd_ci'])[1], rel: 1e-9));
      });
    }
    test('cas-témoins : RR et DR refusés, seul l\'OR est rapporté', () {
      final r = twoByTwo(30, 70, 15, 85, design: StudyDesign.caseControl);
      expect(r.estimate('Risque relatif'), isNull);
      expect(r.estimate('Différence de risques'), isNull);
      expect(r.alerts.map((a) => a.code), contains('cc_no_risk'));
    });
    test('issue fréquente : divergence OR/RR signalée', () {
      final r = twoByTwo(120, 380, 80, 420, design: StudyDesign.cohort);
      expect(r.alerts.map((a) => a.code), contains('or_rr_divergence'));
    });
    test('cellule nulle : correction signalée ; colonne vide refusée', () {
      expect(twoByTwo(0, 25, 6, 19).alerts.map((a) => a.code), contains('zero_cell'));
      expect(() => twoByTwo(0, 25, 0, 19), throwsA(isA<StatInputError>()));
    });
  });

  group('Groupes indépendants', () {
    final g = ref['groups'] as Map<String, dynamic>;
    final g1 = dl(g['g1']), g2 = dl(g['g2']), g3 = dl(g['g3']);
    test('Welch', () {
      final r = tTestIndependent(g1, g2);
      final w = g['welch'] as Map<String, dynamic>;
      expect(r.statistics['t'], closeRel(asD(w['t'])!, rel: 1e-10));
      expect(r.statistics['df'], closeRel(asD(w['df'])!, rel: 1e-10));
      expect(r.statistics['p'], closeRel(asD(w['p'])!, rel: 1e-8));
      expect(r.estimates.first.lower, closeRel(dl(w['ci'])[0], rel: 1e-9));
      expect(r.estimates.first.upper, closeRel(dl(w['ci'])[1], rel: 1e-9));
    });
    test('Student', () {
      final r = tTestIndependent(g1, g2, welch: false);
      final w = g['student'] as Map<String, dynamic>;
      expect(r.statistics['t'], closeRel(asD(w['t'])!, rel: 1e-10));
      expect(r.statistics['p'], closeRel(asD(w['p'])!, rel: 1e-8));
      expect(r.estimates.first.lower, closeRel(dl(w['ci'])[0], rel: 1e-9));
    });
    test('Mann-Whitney exact, avec ex aequo, grand échantillon', () {
      for (final k in [('mw_exact', 's1', 's2'), ('mw_ties', 'ti1', 'ti2'), ('mw_large', 'g1', 'g2')]) {
        final r = mannWhitney(dl(g[k.$2]), dl(g[k.$3]));
        final w = g[k.$1] as Map<String, dynamic>;
        expect(r.statistics['W'], closeRel(asD(w['W'])!), reason: k.$1);
        expect(r.statistics['p'], closeRel(asD(w['p'])!, rel: 1e-8), reason: k.$1);
      }
    });
    test('ANOVA, ANOVA de Welch, Kruskal-Wallis', () {
      final m = {'A': g1, 'B': g2, 'C': g3};
      final a = anovaOneWay(m);
      final ra = g['anova'] as Map<String, dynamic>;
      expect(a.statistics['F'], closeRel(asD(ra['F'])!, rel: 1e-10));
      expect(a.statistics['p'], closeRel(asD(ra['p'])!, rel: 1e-8));
      final w = anovaOneWay(m, welch: true);
      final rw = g['welch_anova'] as Map<String, dynamic>;
      expect(w.statistics['F'], closeRel(asD(rw['F'])!, rel: 1e-10));
      expect(w.statistics['df2'], closeRel(asD(rw['df2'])!, rel: 1e-10));
      expect(w.statistics['p'], closeRel(asD(rw['p'])!, rel: 1e-8));
      final k = kruskalWallis(m);
      final rk = g['kruskal'] as Map<String, dynamic>;
      expect(k.statistics['H'], closeRel(asD(rk['H'])!, rel: 1e-10));
      expect(k.statistics['p'], closeRel(asD(rk['p'])!, rel: 1e-8));
    });
    test('χ² r × c', () {
      final rx = g['rxc'] as Map<String, dynamic>;
      final t = [for (final row in rx['table'] as List) [for (final v in row as List) v as int]];
      final r = chiSquareRxC(t);
      expect(r.statistics['chi2'], closeRel(asD(rx['chi2'])!, rel: 1e-10));
      expect(r.statistics['p'], closeRel(asD(rx['p'])!, rel: 1e-8));
    });
  });

  group('Appariés', () {
    final p = ref['paired'] as Map<String, dynamic>;
    test('t apparié', () {
      final r = pairedTTest(dl(p['pa']), dl(p['pb']));
      final t = p['t'] as Map<String, dynamic>;
      expect(r.statistics['t'], closeRel(asD(t['t'])!, rel: 1e-10));
      expect(r.statistics['p'], closeRel(asD(t['p'])!, rel: 1e-8));
      expect(r.estimates.first.lower, closeRel(dl(t['ci'])[0], rel: 1e-9));
    });
    test('Wilcoxon signé', () {
      for (final k in [('w_exact', 'pc', 'pd'), ('w_ties', 'pa', 'pb')]) {
        final r = wilcoxonSignedRank(dl(p[k.$2]), dl(p[k.$3]));
        final w = p[k.$1] as Map<String, dynamic>;
        expect(r.statistics['V'], closeRel(asD(w['V'])!), reason: k.$1);
        expect(r.statistics['p'], closeRel(asD(w['p'])!, rel: 1e-8), reason: k.$1);
      }
    });
    test('McNemar', () {
      final m = p['mcnemar'] as Map<String, dynamic>;
      final r = mcNemar(40, 14, 5, 41);
      expect(r.statistics['chi2'], closeRel(asD(m['chi2'])!, rel: 1e-12));
      expect(r.statistics['p_asymptotic'], closeRel(asD(m['p'])!, rel: 1e-9));
      expect(r.statistics['p_exact'], closeRel(asD(m['p_exact'])!, rel: 1e-9));
      expect(r.estimates.first.lower, closeRel(dl(m['or_ci'])[0], rel: 1e-8));
      expect(r.estimates.first.upper, closeRel(dl(m['or_ci'])[1], rel: 1e-8));
    });
  });

  group('Corrélation et accord', () {
    final c = ref['correlation'] as Map<String, dynamic>;
    final x = dl(c['x']), y = dl(c['y']);
    test('Pearson', () {
      final r = correlation(x, y);
      final pe = c['pearson'] as Map<String, dynamic>;
      expect(r.estimates.first.value, closeRel(asD(pe['r'])!, rel: 1e-12));
      expect(r.statistics['p'], closeRel(asD(pe['p'])!, rel: 1e-8));
      expect(r.estimates.first.lower, closeRel(dl(pe['ci'])[0], rel: 1e-9));
      expect(r.estimates.first.upper, closeRel(dl(pe['ci'])[1], rel: 1e-9));
    });
    test('Spearman', () {
      final r = correlation(x, y, spearman: true);
      final sp = c['spearman'] as Map<String, dynamic>;
      expect(r.estimates.first.value, closeRel(asD(sp['rho'])!, rel: 1e-12));
      expect(r.statistics['p'], closeRel(asD(sp['p'])!, rel: 1e-8));
    });
    test('Bland-Altman : biais, limites d\'accord et leurs IC', () {
      final r = blandAltman(x, y);
      final b = c['bland_altman'] as Map<String, dynamic>;
      expect(r.estimates[0].value, closeRel(asD(b['bias'])!, rel: 1e-12, abs: 1e-14));
      expect(r.estimates[0].lower, closeRel(dl(b['bias_ci'])[0], rel: 1e-9));
      expect(r.estimates[1].value, closeRel(dl(b['loa'])[0], rel: 1e-12));
      expect(r.estimates[2].value, closeRel(dl(b['loa'])[1], rel: 1e-12));
      expect(r.estimates[1].lower, closeRel(dl(b['loa_low_ci'])[0], rel: 1e-9));
      expect(r.estimates[2].upper, closeRel(dl(b['loa_high_ci'])[1], rel: 1e-9));
    });
  });

  group('Tailles d\'échantillon (R power.t.test, power.prop.test)', () {
    final s = ref['sample_size'] as Map<String, dynamic>;
    for (final c in (s['nct'] as List).cast<Map<String, dynamic>>()) {
      test('t non centrale ${c['t']}, ${c['df']}, ${c['ncp']}', () {
        expect(noncentralTCdf(asD(c['t'])!, asD(c['df'])!, asD(c['ncp'])!), closeRel(asD(c['p'])!, rel: 1e-9));
      });
    }
    for (final c in (s['means'] as List).cast<Map<String, dynamic>>()) {
      test('deux moyennes Δ=${c['delta']}', () {
        final r = sampleSizeTwoMeans(delta: asD(c['delta'])!, sd: asD(c['sd'])!, alpha: asD(c['alpha'])!, power: asD(c['power'])!);
        // R : uniroot, tol ≈ 1e-10 relative au n.
        expect(r.statistics['n_exact'], closeRel(asD(c['n'])!, rel: 1e-6));
      });
    }
    for (final c in (s['props'] as List).cast<Map<String, dynamic>>()) {
      test('deux proportions ${c['p1']} vs ${c['p2']}', () {
        final r = sampleSizeTwoProportions(p1: asD(c['p1'])!, p2: asD(c['p2'])!, alpha: asD(c['alpha'])!, power: asD(c['power'])!);
        expect(r.statistics['n_exact'], closeRel(asD(c['n'])!, rel: 1e-6));
      });
    }
  });
}
