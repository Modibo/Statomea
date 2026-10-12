import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('qpcr');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  test('courbe standard : pente, R², efficacité et IC, inconnues — contre lm', () {
    final s = ref['std'] as Map;
    final r = qpcrStandardCurve(v(s['log10q']), v(s['ct']), unknownCt: v(s['unknown_ct']));
    expect(r.statistics['slope'], closeRel(asD(s['slope'])!, rel: 1e-12));
    expect(r.statistics['intercept'], closeRel(asD(s['intercept'])!, rel: 1e-12));
    expect(r.statistics['r2'], closeRel(asD(s['r2'])!, rel: 1e-12));
    expect(r.estimates[1].lower, closeRel(v(s['slope_ci'])[0], rel: 1e-10));
    expect(r.statistics['efficiency'], closeRel(asD(s['eff'])!, rel: 1e-12));
    expect([r.statistics['efficiency_lower'], r.statistics['efficiency_upper']], [for (final x in v(s['eff_ci'])) closeRel(x, rel: 1e-10)]);
    final u = v(s['unknown_log10q']);
    for (var i = 0; i < u.length; i++) {
      expect(r.statistics['unknown_log10q_$i'], closeRel(u[i], rel: 1e-12));
    }
  });

  test('ΔΔCt (Welch) et Pfaffl contre t.test', () {
    final d = ref['dd'] as Map;
    final r = qpcrRelativeQuantification(v(d['tgt_c']), v(d['ref_c']), v(d['tgt_t']), v(d['ref_t']));
    expect(r.statistics['ddct'], closeRel(asD(d['ddct'])!, rel: 1e-12));
    expect([r.statistics['ddct_lower'], r.statistics['ddct_upper']], [for (final x in v(d['ddct_ci'])) closeRel(x, rel: 1e-10)]);
    expect(r.statistics['df'], closeRel(asD(d['df'])!, rel: 1e-10));
    expect(r.statistics['p'], closeRel(asD(d['p'])!, rel: 1e-8));
    expect(r.statistics['fold'], closeRel(asD(d['fold'])!, rel: 1e-12));
    expect([r.statistics['fold_lower'], r.statistics['fold_upper']], [for (final x in v(d['fold_ci'])) closeRel(x, rel: 1e-10)]);
    final p = qpcrRelativeQuantification(v(d['tgt_c']), v(d['ref_c']), v(d['tgt_t']), v(d['ref_t']), eTarget: asD(d['Et'])!, eRef: asD(d['Er'])!);
    expect(p.statistics['pfaffl'], closeRel(asD(d['pfaffl'])!, rel: 1e-12));
  });

  test('limite de détection probit contre glm et MASS::dose.p', () {
    final l = ref['lod'] as Map;
    final r = qpcrLimitOfDetection(v(l['conc']), [for (final x in l['det'] as List) (x as num).toInt()], [for (final x in l['n'] as List) (x as num).toInt()]);
    final c = v(l['coef']);
    expect(r.statistics['b0'], closeRel(c[0], rel: 1e-8));
    expect(r.statistics['b1'], closeRel(c[1], rel: 1e-8));
    expect(r.statistics['log10_lod'], closeRel(asD(l['log10_lod95'])!, rel: 1e-8));
    expect(r.statistics['log10_lod_se'], closeRel(asD(l['se'])!, rel: 1e-6));
    expect(r.statistics['lod'], closeRel(asD(l['lod95'])!, rel: 1e-8));
    expect([r.statistics['lod_lower'], r.statistics['lod_upper']], [for (final x in v(l['lod95_ci'])) closeRel(x, rel: 1e-6)]);
  });
}
