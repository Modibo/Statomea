import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void check(AnalysisResult r, DesignMatrix d, Map<String, dynamic> ref) {
  final b = dl(ref['coef']), lo = dl(ref['lower']), hi = dl(ref['upper']), p = dl(ref['p']);
  for (var j = 0; j < b.length; j++) {
    final c = d.columns[j];
    expect(r.statistics['beta_$c'], closeRel(b[j], rel: 1e-7, abs: 1e-9), reason: 'β $c');
    expect(r.statistics['pl_lower_$c'], closeRel(lo[j], rel: 1e-6, abs: 1e-6), reason: 'borne inf $c');
    expect(r.statistics['pl_upper_$c'], closeRel(hi[j], rel: 1e-6, abs: 1e-6), reason: 'borne sup $c');
    expect(r.statistics['pl_p_$c'], closeRel(p[j], rel: 1e-5, abs: 1e-12), reason: 'p $c');
  }
  for (var j = 1; j < b.length; j++) {
    expect(r.estimates[j - 1].lower, closeRel(math.exp(lo[j]), rel: 1e-6));
    expect(r.estimates[j - 1].upper, closeRel(math.exp(hi[j]), rel: 1e-6));
  }
}

void main() {
  final ref = loadRef('firth_profile');
  test('séparation quasi complète (n = 40) contre logistf(pl = TRUE)', () {
    final ds = parseCsv(File('test/reference/firth_data.csv').readAsStringSync()).dataset;
    final d = buildDesign(ds, const ModelFormula('y', [TermSpec('x1'), TermSpec('grp', categorical: true, reference: 'A')], eventLevel: '1'),
        binaryOutcome: true);
    check(firthRegression(d), d, ref['sep'] as Map<String, dynamic>);
  });
  test('plusieurs prédicteurs dont un facteur à 3 modalités, 12 événements', () {
    final ds = parseCsv(File('test/reference/firth_data2.csv').readAsStringSync()).dataset;
    final d = buildDesign(
        ds,
        const ModelFormula('y', [TermSpec('x1'), TermSpec('x2'), TermSpec('g', categorical: true, reference: 'a')], eventLevel: '1'),
        binaryOutcome: true);
    final r = firthRegression(d);
    check(r, d, ref['multi'] as Map<String, dynamic>);
    expect(r.checks.firstWhere((c) => c.id == 'profile_bounds').status, CheckStatus.ok);
  });
  test('démo AgHBs : IC profilé très différent de l\'IC de Wald', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final r = analysisResultFromJson(p.journal[6].result);
    final ds = subsetRows(p.dataset!, (i) => p.dataset!.cell(i, 'enfant_suivi') == 'oui', 'enfants suivis');
    final d = buildDesign(ds, const ModelFormula('enfant_infecte', [TermSpec('aghbe', categorical: true, reference: 'negatif')], eventLevel: 'oui'),
        binaryOutcome: true);
    check(r, d, ref['aghbs'] as Map<String, dynamic>);
  });
}
