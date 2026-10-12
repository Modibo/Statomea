import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('mr_sensibilite');
  final ds = parseCsv(File('test/reference/mr_ldl_chd.csv').readAsStringSync()).dataset;
  List<double> col(String c) => [for (var i = 0; i < ds.rowCount; i++) double.parse(ds.cell(i, c)!)];
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final bx = col('beta_ldl'), bxse = col('se_ldl'), by = col('beta_chd'), byse = col('se_chd');
  final ratio = [for (var j = 0; j < bx.length; j++) by[j] / bx[j]];
  // ES par la méthode delta (défaut de mr_mbe).
  final se = [for (var j = 0; j < bx.length; j++) mrDeltaSe(bx[j], bxse[j], by[j], byse[j])];

  test('mode pondéré : estimation = mr_mbe (densité de R reproduite) ; 200 estimations bootstrap et leur MAD = R', () {
    final m = ref['mbe'] as Map;
    expect(modeBasedEstimate(ratio, se), closeRel(asD(m['estimate'])!, rel: 1e-12));
    final draws = [for (final r in ref['mbe_draws'] as List) v(r)];
    final boot = v(ref['mbe_boot']);
    for (var i = 0; i < draws.length; i++) {
      expect(modeBasedEstimate(draws[i], se), closeRel(boot[i], rel: 1e-12), reason: 'tirage $i');
    }
    expect(modeBasedBootstrapSe(ratio, se, draws: draws), closeRel(asD(ref['mbe_mad_200'])!, rel: 1e-12));
  });

  test('mode pondéré : ES à 10 000 tirages (générateur de Statoméa) dans l\'erreur de Monte-Carlo de mr_mbe', () {
    final m = ref['mbe'] as Map;
    // La MAD d'un échantillon de 10 000 a une ES relative ≈ 1,1 % ; marge 6 %.
    expect(modeBasedBootstrapSe(ratio, se), closeRel(asD(m['se'])!, rel: 0.06));
  });

  test('leave-one-out : 28 estimations IVW et IC = mr_loo', () {
    final l = leaveOneOutIvw(bx, by, byse);
    final e = v(ref['loo_estimate']), lo = v(ref['loo_lower']), hi = v(ref['loo_upper']);
    for (var j = 0; j < l.length; j++) {
      expect(l[j].estimate, closeRel(e[j], rel: 1e-10));
      expect(l[j].lower, closeRel(lo[j], rel: 1e-10));
      expect(l[j].upper, closeRel(hi[j], rel: 1e-10));
    }
  });

  test('MR multivariée LDL, HDL, triglycérides : effets directs, ES, IC, p, Q = mr_mvivw', () {
    final m = ref['mv'] as Map;
    final f = multivariableMendelianRandomization([bx, col('beta_hdl'), col('beta_tg')], [bxse, col('se_hdl'), col('se_tg')], by, byse,
        exposures: ['LDL', 'HDL', 'TG'], outcome: 'CHD');
    final e = v(m['estimate']), se2 = v(m['se']), lo = v(m['lower']), hi = v(m['upper']), p = v(m['p']);
    for (var r = 0; r < 3; r++) {
      expect(f.estimates[r].estimate, closeRel(e[r], rel: 1e-10));
      expect(f.estimates[r].se, closeRel(se2[r], rel: 1e-10));
      expect(f.estimates[r].lower, closeRel(lo[r], rel: 1e-10));
      expect(f.estimates[r].upper, closeRel(hi[r], rel: 1e-10));
      expect(f.estimates[r].p, closeRel(p[r], rel: 1e-8));
    }
    expect(f.q, closeRel(asD(m['q'])!, rel: 1e-10));
    expect(f.qP, closeRel(asD(m['q_p'])!, rel: 1e-8));
    expect(f.rse, closeRel(asD(m['rse'])!, rel: 1e-10));
    expect(f.randomEffects, m['model'] == 'random');
    expect(() => multivariableMendelianRandomization([bx], [bxse], by, byse, exposures: ['LDL']), throwsA(isA<StatInputError>()));
  });

  test('analyse principale : mode pondéré et leave-one-out intégrés au résultat', () {
    final f = mendelianRandomization(bx, bxse, by, byse, modeDraws: [for (final r in ref['mbe_draws'] as List) v(r)]);
    expect(f.mode.estimate, closeRel(asD((ref['mbe'] as Map)['estimate'])!, rel: 1e-12));
    expect(f.mode.se, closeRel(asD(ref['mbe_mad_200'])!, rel: 1e-12));
    expect(f.leaveOneOut, hasLength(28));
    expect(f.result.checks.firstWhere((c) => c.id == 'influence').status, CheckStatus.ok);
    expect(f.result.tables.map((t) => t.title), contains('Leave-one-out (IVW sans le variant)'));
  });
}
