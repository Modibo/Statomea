import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('prs');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/prs.bed').readAsBytesSync(), File('$dir/prs.bim').readAsStringSync(), File('$dir/prs.fam').readAsStringSync());
  final y = [for (final p in g.phenotype) p == null ? null : (p == 2 ? 1.0 : 0.0)];
  final f = polygenicRiskScore(g, y, outcomeName: 'maladie');

  test('découverte : β et p de Wald des 3 000 régressions logistiques = glm de R', () {
    final b = v(ref['beta']), p = v(ref['p']);
    for (var j = 0; j < b.length; j++) {
      expect(f.beta[j], closeRel(b[j], rel: 1e-6), reason: g.variants[j].id);
      expect(f.p[j], closeRel(p[j], rel: 1e-5), reason: g.variants[j].id);
    }
  });

  test('clumping : mêmes variants index que R', () {
    expect([for (final j in f.index) j + 1], [for (final x in ref['index'] as List) (x as num).toInt()]);
  });

  test('validation : mesures par seuil et seuil retenu = R ; test : OR par ET, AUC (DeLong), R² de Nagelkerke = R', () {
    final val = ref['validation'] as List;
    expect(f.validation.length, val.length);
    for (var k = 0; k < val.length; k++) {
      final r = val[k] as Map;
      final (t, n, m) = f.validation[k];
      expect(t, asD(r['T']));
      expect(n, asD(r['k'])!.round());
      expect(m.beta, closeRel(asD(r['beta'])!, rel: 1e-6));
      expect(m.p, closeRel(asD(r['p'])!, rel: 1e-5));
      expect(m.auc, closeRel(asD(r['auc'])!, rel: 1e-12));
      expect(m.r2, closeRel(asD(r['r2'])!, rel: 1e-6));
    }
    expect(f.bestThreshold, asD(ref['best_T']));
    final t = ref['test'] as Map;
    expect(f.test.beta, closeRel(asD(t['beta'])!, rel: 1e-6));
    expect(f.test.se, closeRel(asD(t['se'])!, rel: 1e-6));
    expect(f.testAuc.auc, closeRel(asD(t['auc'])!, rel: 1e-12));
    expect(f.testAuc.lower, closeRel(asD(t['auc_lower'])!, rel: 1e-9));
    expect(f.testAuc.upper, closeRel(asD(t['auc_upper'])!, rel: 1e-9));
    expect(f.test.r2, closeRel(asD(t['r2'])!, rel: 1e-6));
    expect(f.result.statistics['n_discovery'], asD(ref['n_disc']));
    expect(f.result.statistics['n_test'], asD(ref['n_test']));
    // Le seuil choisi sur la validation y surestime la performance : optimisme signalé.
    expect(f.result.checks.firstWhere((c) => c.id == 'optimism').status, CheckStatus.warning);
  });

  test('issue non binaire ou échantillon trop petit refusés', () {
    expect(() => polygenicRiskScore(g, [for (var i = 0; i < g.sampleCount; i++) 2.0]), throwsA(isA<StatInputError>()));
    expect(() => polygenicRiskScore(g.subset(sampleIdx: [for (var i = 0; i < 60; i++) i]), y.sublist(0, 60)), throwsA(isA<StatInputError>()));
  });

  group('score ajusté sur le sexe et l\'âge', () {
    final cov = parseCsv(File('$dir/prs_covariables.csv').readAsStringSync()).dataset;
    final byId = {for (var i = 0; i < cov.rowCount; i++) cov.cell(i, 'id')!: i};
    final sexe = LmmCovariate('sexe', [for (final s in g.samples) cov.cell(byId[s]!, 'sexe')], categorical: true, reference: 'H');
    final age = LmmCovariate('age', [for (final s in g.samples) cov.cell(byId[s]!, 'age')]);
    final a = polygenicRiskScore(g, y, covariates: [sexe, age], outcomeName: 'maladie');
    final r = ref['adjusted'] as Map;

    test('découverte ajustée : β et p = glm de R ; mêmes variants index', () {
      final b = v(r['beta']), p = v(r['p']);
      for (var j = 0; j < b.length; j++) {
        expect(a.beta[j], closeRel(b[j], rel: 1e-6), reason: g.variants[j].id);
        expect(a.p[j], closeRel(p[j], rel: 1e-5), reason: g.variants[j].id);
      }
      expect([for (final j in a.index) j + 1], [for (final x in r['index'] as List) (x as num).toInt()]);
    });

    test('validation : R² incrémental, AUC du score et du modèle complet ; seuil retenu = R', () {
      final val = r['validation'] as List;
      expect(a.validation.length, val.length);
      for (var k = 0; k < val.length; k++) {
        final rr = val[k] as Map;
        final (t, n, m) = a.validation[k];
        expect(t, asD(rr['T']));
        expect(n, asD(rr['k'])!.round());
        expect(m.beta, closeRel(asD(rr['beta'])!, rel: 1e-6));
        expect(m.r2, closeRel(asD(rr['r2'])!, rel: 1e-6, abs: 1e-9));
        expect(m.r2Base, closeRel(asD(rr['r2_base'])!, rel: 1e-6));
        expect(m.auc, closeRel(asD(rr['auc'])!, rel: 1e-12));
        expect(m.aucBase, closeRel(asD(rr['auc_base'])!, rel: 1e-9));
        expect(m.aucFull, closeRel(asD(rr['auc_full'])!, rel: 1e-9));
      }
      expect(a.bestThreshold, asD(r['best_T']));
    });

    test('test : OR ajusté, AUC du modèle complet (DeLong), gain d\'AUC apparié et sa p = pROC', () {
      final t = r['test'] as Map;
      expect(a.test.beta, closeRel(asD(t['beta'])!, rel: 1e-6));
      expect(a.test.r2, closeRel(asD(t['r2'])!, rel: 1e-6));
      expect(a.testAuc.auc, closeRel(asD(t['auc_full'])!, rel: 1e-9));
      expect(a.testAuc.lower, closeRel(asD(t['auc_full_lower'])!, rel: 1e-7));
      expect(a.testAuc.upper, closeRel(asD(t['auc_full_upper'])!, rel: 1e-7));
      expect(a.deltaAuc!.diff, closeRel(asD(t['delta_auc'])!, rel: 1e-7));
      expect(a.deltaAuc!.lower, closeRel(asD(t['delta_lower'])!, rel: 1e-6));
      expect(a.deltaAuc!.upper, closeRel(asD(t['delta_upper'])!, rel: 1e-6));
      expect(a.deltaAuc!.p, closeRel(asD(t['delta_p'])!, rel: 1e-5));
      expect(a.result.methodName, contains('ajusté sur sexe, age'));
      expect(a.result.tables, hasLength(2));
    });
  });
}
