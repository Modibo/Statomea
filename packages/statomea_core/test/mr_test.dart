import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('mr');
  final ds = parseCsv(File('test/reference/mr_ldl_chd.csv').readAsStringSync()).dataset;
  List<double> col(String c) => [for (var i = 0; i < ds.rowCount; i++) double.parse(ds.cell(i, c)!)];
  final bx = col('beta_ldl'), bxse = col('se_ldl'), by = col('beta_chd'), byse = col('se_chd');
  final draws = [for (final r in ref['draws'] as List) [for (final x in r as List) asD(x)!]];
  final f = mendelianRandomization(bx, bxse, by, byse, exposure: 'LDL-C', outcome: 'CHD', bootstrapDraws: draws);
  void same(MrEstimate e, Map r, {double rel = 1e-10}) {
    expect(e.estimate, closeRel(asD(r['estimate'])!, rel: rel));
    expect(e.se, closeRel(asD(r['se'])!, rel: rel));
    expect(e.lower, closeRel(asD(r['lower'])!, rel: rel));
    expect(e.upper, closeRel(asD(r['upper'])!, rel: rel));
    expect(e.p, closeRel(asD(r['p'])!, rel: rel * 100));
  }

  test('IVW (effets aléatoires multiplicatifs et fixes), Q, F moyen = MendelianRandomization', () {
    final r = ref['ivw'] as Map;
    expect(f.randomEffects, isTrue);
    same(f.ivw, r);
    same(f.ivwFixed, ref['ivw_fixed'] as Map);
    expect(f.q, closeRel(asD(r['q'])!, rel: 1e-10));
    expect(f.qP, closeRel(asD(r['q_p'])!, rel: 1e-8));
    expect(f.rse, closeRel(asD(r['rse'])!, rel: 1e-10));
    expect(f.meanF, closeRel(asD(r['fstat'])!, rel: 1e-12));
  });

  test('MR-Egger : pente, intercept, Q de Rücker, I²_GX = MendelianRandomization', () {
    final r = ref['egger'] as Map;
    same(f.egger, r);
    expect(f.eggerIntercept.estimate, closeRel(asD(r['intercept'])!, rel: 1e-10));
    expect(f.eggerIntercept.se, closeRel(asD(r['se_intercept'])!, rel: 1e-10));
    expect(f.eggerIntercept.lower, closeRel(asD(r['lower_intercept'])!, rel: 1e-10));
    expect(f.eggerIntercept.p, closeRel(asD(r['p_intercept'])!, rel: 1e-8));
    expect(f.eggerQ, closeRel(asD(r['q'])!, rel: 1e-10));
    expect(f.i2gx, closeRel(asD(r['i2gx'])!, rel: 1e-12));
    expect(f.eggerRse, closeRel(asD(r['rse'])!, rel: 1e-10));
  });

  test('médiane pondérée : estimation exacte ; ES du bootstrap identique sur les mêmes 200 tirages', () {
    final r = ref['median'] as Map;
    expect(f.median.estimate, closeRel(asD(r['estimate'])!, rel: 1e-12));
    expect(f.median.se, closeRel(asD(ref['boot_sd_200'])!, rel: 1e-12));
  });

  test('bootstrap de 10 000 itérations (générateur de Statoméa) : ES dans l\'erreur de Monte-Carlo du paquet', () {
    final g = mendelianRandomization(bx, bxse, by, byse);
    final seR = asD((ref['median'] as Map)['se'])!;
    // ES d'un écart-type estimé sur 10 000 tirages ≈ ES/√(2·10 000) ≈ 0,7 % ; marge 4 %.
    expect(g.median.se, closeRel(seR, rel: 0.04));
    expect(g.median.estimate, f.median.estimate);
  });

  test('vérifications et entrées invalides', () {
    expect(f.result.checks.firstWhere((c) => c.id == 'weak_instruments').status, CheckStatus.ok);
    expect(f.result.checks.firstWhere((c) => c.id == 'pleiotropy').status, CheckStatus.ok);
    expect(f.result.checks.firstWhere((c) => c.id == 'consistency').status, CheckStatus.ok);
    expect(() => mendelianRandomization([0.1, 0.2], [0.01, 0.01], [0.1, 0.2], [0.1, 0.1]), throwsA(isA<StatInputError>()));
    expect(() => mendelianRandomization([0.1, 0.2, 0.3], [0.01, 0, 0.01], [0.1, 0.2, 0.3], [0.1, 0.1, 0.1]), throwsA(isA<StatInputError>()));
    // Moins de 4 variants : IVW à effets fixes.
    expect(mendelianRandomization(bx.sublist(0, 3), bxse.sublist(0, 3), by.sublist(0, 3), byse.sublist(0, 3), iterations: 200).randomEffects, isFalse);
  });
}
