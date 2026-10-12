import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double?> dln(Object? v) => [for (final x in v as List) asD(x)];

void checkCurve(KmCurve c, Map<String, dynamic> r) {
  final ev = [for (final s in c.steps) if (s.events > 0) s];
  final t = dln(r['time']), s = dln(r['surv']), se = dln(r['se']), lo = dln(r['lower']), hi = dln(r['upper']);
  expect(ev.length, t.length);
  for (var i = 0; i < t.length; i++) {
    expect(ev[i].time, t[i]);
    expect(ev[i].atRisk, (r['n_risk'] as List)[i]);
    expect(ev[i].surv, closeRel(s[i]!, rel: 1e-12, abs: 1e-15));
    if (se[i] != null && se[i]!.isFinite) expect(ev[i].se, closeRel(se[i]!, rel: 1e-10));
    if (lo[i] != null && !lo[i]!.isNaN) expect(ev[i].lower, closeRel(lo[i]!, rel: 1e-10));
    if (hi[i] != null && !hi[i]!.isNaN) expect(ev[i].upper, closeRel(hi[i]!, rel: 1e-10));
  }
  expect(c.median, asD(r['median']));
  expect(c.medianLower, asD(r['mlo']));
  expect(c.medianUpper, asD(r['mhi']));
  expect(c.at(365)!.s, closeRel(asD(r['s365'])!, rel: 1e-12));
}

void main() {
  final ref = loadRef('kaplan_meier');
  final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
  final t = lung.numeric('time'), st = lung.text('deces'), sexe = lung.text('sexe');
  List<double> sub(List<double?> x, String? g) => [for (var i = 0; i < x.length; i++) if (g == null || sexe[i] == g) x[i]!];
  final d = [for (final v in st) v == 'oui' ? 1.0 : 0.0];
  test('Kaplan-Meier (lung, tous) : survie, ES de Greenwood, IC log, à risque, médiane et IC, S(365) — contre survfit', () {
    checkCurve(kaplanMeier(sub(t, null), [for (final v in d) v]), ref['lung_all'] as Map<String, dynamic>);
  });
  test('Kaplan-Meier par sexe', () {
    for (final g in ['F', 'H']) {
      checkCurve(kaplanMeier(sub(t, g), [for (var i = 0; i < d.length; i++) if (sexe[i] == g) d[i]]), ref['lung_$g'] as Map<String, dynamic>);
    }
  });
  test('log-rank 2 groupes (lung, sexe) et 4 groupes (veteran, type cellulaire) — contre survdiff', () {
    final r = survivalAnalysis(t, st, 'oui', groupRaw: sexe, horizon: 365);
    final lr = ref['lung_lr'] as Map<String, dynamic>;
    expect(r.statistics['logrank_chi2'], closeRel(asD(lr['chi2'])!, rel: 1e-10));
    final vet = parseCsv(File('test/reference/cox_veteran.csv').readAsStringSync()).dataset;
    final rv = survivalAnalysis(vet.numeric('time'), vet.text('deces'), 'oui', groupRaw: vet.text('celltype'));
    final vl = ref['vet_lr'] as Map<String, dynamic>;
    expect(rv.statistics['logrank_chi2'], closeRel(asD(vl['chi2'])!, rel: 1e-10));
    expect(rv.statistics['logrank_df'], 3);
    expect(kmSvg((rv.figures['kaplanMeier'] as Map).cast()), startsWith('<svg'));
  });
  test('médiane sur un palier exactement à 0,5 (moyenne avec le temps suivant)', () {
    final c = kaplanMeier([1, 2, 3, 4], [1, 1, 1, 0]);
    expect(c.median, asD(ref['half_median']));
  });
  test('aucun événement : erreur explicite', () {
    expect(() => survivalAnalysis([1, 2, 3], ['non', 'non', 'non'], 'oui'), throwsA(isA<StatInputError>()));
  });
}
