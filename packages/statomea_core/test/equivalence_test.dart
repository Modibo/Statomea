import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('equivalence_evalue');
  List<double> v(Object? l) => [for (final x in l as List) asD(x) ?? double.nan];
  final a = v(ref['a']), b = v(ref['b']), pre = v(ref['pre']), post = v(ref['post']);

  void tost(AnalysisResult r, Map m) {
    final t = v(m['t']), df = v(m['df']), p = v(m['p']), ci = v(m['ci']);
    expect(r.statistics['diff'], closeRel(asD(m['est'])!, rel: 1e-12));
    expect(r.statistics['t_nhst'], closeRel(t[0], rel: 1e-10));
    expect(r.statistics['t_lower'], closeRel(t[1], rel: 1e-10));
    expect(r.statistics['t_upper'], closeRel(t[2], rel: 1e-10));
    expect(r.statistics['df'], closeRel(df[0], rel: 1e-10));
    expect(r.statistics['p_nhst'], closeRel(p[0], rel: 1e-8));
    expect(r.statistics['p_lower'], closeRel(p[1], rel: 1e-8));
    expect(r.statistics['p_upper'], closeRel(p[2], rel: 1e-8));
    expect(r.statistics['ci_lower'], closeRel(ci[0], rel: 1e-9));
    expect(r.statistics['ci_upper'], closeRel(ci[1], rel: 1e-9));
  }

  test('TOST de deux moyennes (Welch, Student) et apparié = TOSTER::t_TOST', () {
    tost(equivalenceMeans(a, b, low: -5, high: 5), ref['welch'] as Map);
    tost(equivalenceMeans(a, b, varEqual: true, low: -5, high: 5), ref['student'] as Map);
    final pr = equivalenceMeans(post, pre, paired: true, low: -0.2, high: 0.2);
    tost(pr, ref['paired'] as Map);
    expect(pr.statistics['p'], lessThan(0.05));
  });

  test('non-infériorité (marge 4, plus haut = mieux) = t.test unilatéral', () {
    final r = equivalenceMeans(a, b, hypothesis: EquivalenceHypothesis.nonInferiorityHigherBetter, margin: 4);
    final m = ref['noninf'] as Map;
    expect(r.statistics['t'], closeRel(asD(m['t'])!, rel: 1e-10));
    expect(r.statistics['p'], closeRel(asD(m['p'])!, rel: 1e-8));
    expect(r.statistics['ci_lower'], closeRel(asD(m['lower'])!, rel: 1e-9));
  });

  test('équivalence de deux proportions = TOSTER::twoprop_test (0,62 contre 0,58, n = 150 et 140)', () {
    final m = ref['prop'] as Map;
    final ci = v(m['ci']);
    final e = equivalenceProportionsFromRates(0.62, 150, 0.58, 140, low: -0.1, high: 0.1);
    expect(e.statistics['diff'], closeRel(0.04, rel: 1e-12));
    expect(e.statistics['z'], closeRel(asD(m['z'])!, rel: 1e-10));
    expect(e.statistics['p'], closeRel(asD(m['p'])!, rel: 1e-9));
    expect(e.statistics['ci_lower'], closeRel(ci[0], rel: 1e-10));
    expect(e.statistics['ci_upper'], closeRel(ci[1], rel: 1e-10));
    // À partir des effectifs : 93/150 = 0,62 exactement, même résultat.
    expect(equivalenceProportions(93, 150, 812, 1400, low: -0.1, high: 0.1).statistics['diff'], closeRel(0.04, rel: 1e-12));
    expect(() => equivalenceProportions(3, 5, 4, 5, low: -0.1, high: 0.1), throwsA(isA<StatInputError>()));
  });

  test('valeur E : RR, RR protecteur, IC contenant 1, OR rare et fréquent, HR fréquent, différence standardisée = EValue', () {
    void ev(AnalysisResult r, String key, {required bool high}) {
      final e = v(ref[key]);
      expect(r.statistics['e_point'], closeRel(e[0], rel: 1e-12), reason: key);
      expect(r.statistics['e_ci'], closeRel(high ? e[1] : e[2], rel: 1e-12), reason: key);
    }

    ev(eValue(1.8, lower: 1.3, upper: 2.5), 'ev_rr', high: true);
    ev(eValue(0.6, lower: 0.45, upper: 0.8), 'ev_rr_protect', high: false);
    ev(eValue(1.3, lower: 0.9, upper: 1.9), 'ev_rr_null', high: true);
    ev(eValue(2.2, lower: 1.4, upper: 3.5, scale: EValueScale.oddsRatioCommon), 'ev_or_common', high: true);
    ev(eValue(2.2, lower: 1.4, upper: 3.5, scale: EValueScale.oddsRatioRare), 'ev_or_rare', high: true);
    ev(eValue(0.7, lower: 0.55, upper: 0.9, scale: EValueScale.hazardRatioCommon), 'ev_hr_common', high: false);
    ev(eValue(0.5, se: 0.15, scale: EValueScale.standardizedMeanDifference), 'ev_md', high: true);
    expect(() => eValue(1.5, lower: 1.6, upper: 2), throwsA(isA<StatInputError>()));
  });
}
