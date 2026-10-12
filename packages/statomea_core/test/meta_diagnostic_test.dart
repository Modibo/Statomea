import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

List<Study> load(String name) {
  final ds = parseCsv(File('test/reference/diagmeta_$name.csv').readAsStringSync()).dataset;
  return [
    for (var i = 0; i < ds.rowCount; i++)
      Study('s$i', 'Étude ${i + 1}', {
        'tp': SourcedValue(parseNumber(ds.cell(i, 'TP'))),
        'fp': SourcedValue(parseNumber(ds.cell(i, 'FP'))),
        'fn': SourcedValue(parseNumber(ds.cell(i, 'FN'))),
        'tn': SourcedValue(parseNumber(ds.cell(i, 'TN'))),
      })
  ];
}

void main() {
  final ref = loadRef('meta_diagnostic');
  for (final name in ['auditc', 'dementia']) {
    test('$name : modèle bivarié contre mada::reitsma', () {
      final r = diagnosticMetaAnalysis(load(name));
      final m = ref[name] as Map<String, dynamic>;
      final c = dl(m['coef']);
      final v = [for (final row in m['vcov'] as List) dl(row)];
      final psi = [for (final row in m['Psi'] as List) dl(row)];
      final st = r.statistics;
      expect(st['mu_sens'], closeRel(c[0], rel: 1e-6), reason: 'μ Se');
      expect(st['mu_fpr'], closeRel(c[1], rel: 1e-6), reason: 'μ FPR');
      expect(st['se_mu_sens']! * st['se_mu_sens']!, closeRel(v[0][0], rel: 1e-6), reason: 'var μ Se');
      expect(st['se_mu_fpr']! * st['se_mu_fpr']!, closeRel(v[1][1], rel: 1e-6), reason: 'var μ FPR');
      expect(st['cov_mu'], closeRel(v[0][1], rel: 1e-6), reason: 'cov');
      expect(st['tau2_sens'], closeRel(psi[0][0], rel: 1e-6), reason: 'τ² Se');
      expect(st['tau2_fpr'], closeRel(psi[1][1], rel: 1e-6), reason: 'τ² FPR');
      expect(st['rho']! * math.sqrt(st['tau2_sens']! * st['tau2_fpr']!), closeRel(psi[0][1], rel: 1e-6), reason: 'cov Ψ');
      expect(st['loglik_mada'], closeRel(asD(m['logLik'])!, rel: 1e-7), reason: 'logLik');
      expect(st['auc'], closeRel(asD(m['auc'])!, rel: 1e-6), reason: 'AUC');
      final sci = dl(m['sens_ci']), fci = dl(m['fpr_ci']);
      expect(r.estimates[0].lower, closeRel(sci[0], rel: 1e-6));
      expect(r.estimates[0].upper, closeRel(sci[1], rel: 1e-6));
      expect(r.estimates[1].lower, closeRel(1 - fci[1], rel: 1e-6));
      expect(r.estimates[1].upper, closeRel(1 - fci[0], rel: 1e-6));
      expect(srocSvg((r.figures['sroc'] as Map).cast()), startsWith('<svg'));
    });
  }
  test('cellule nulle : correction 0,5 de toutes les études signalée ; trop peu d\'études refusé', () {
    final r = diagnosticMetaAnalysis(load('auditc'));
    expect(r.alerts.map((a) => a.code), contains('diag_meta_correction'));
    expect(() => diagnosticMetaAnalysis(load('auditc').take(2).toList()), throwsA(isA<StatInputError>()));
  });
}

