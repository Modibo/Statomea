import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

/// Nom de colonne Statoméa correspondant à un nom de coefficient R.
String colFor(SurvivalDesign s, String rName) {
  for (final c in s.design.columns) {
    final m = RegExp(r'^(\S+) = (\S+) \(vs').firstMatch(c);
    if (m != null && '${m[1]}${m[2]}' == rName) return c;
    if (c == rName) return c;
  }
  throw StateError('colonne introuvable : $rName');
}

void check(AnalysisResult r, SurvivalDesign s, Map<String, dynamic> ref) {
  final names = [for (final n in ref['names'] as List) n as String];
  final b = dl(ref['coef']), se = dl(ref['se']);
  for (var j = 0; j < names.length; j++) {
    final c = colFor(s, names[j]);
    expect(r.statistics['beta_$c'], closeRel(b[j], rel: 1e-8, abs: 1e-12), reason: 'β ${names[j]}');
    expect(r.statistics['se_$c'], closeRel(se[j], rel: 1e-7), reason: 'ES ${names[j]}');
  }
  final ll = dl(ref['loglik']);
  expect(r.statistics['loglik_null'], closeRel(ll[0], rel: 1e-10));
  expect(r.statistics['loglik'], closeRel(ll[1], rel: 1e-10));
  expect(r.statistics['lr'], closeRel(asD(ref['lr'])!, rel: 1e-7));
  expect(r.statistics['wald'], closeRel(asD(ref['wald'])!, rel: 1e-7));
  expect(r.statistics['score'], closeRel(asD(ref['score'])!, rel: 1e-9));
  expect(r.statistics['concordance'], closeRel(asD(ref['concordance'])!, rel: 1e-12));
  expect(r.statistics['n'], ref['n']);
  expect(r.statistics['events'], ref['nevent']);
  final zn = [for (final n in ref['zph_names'] as List) n as String], zv = dl(ref['zph']);
  for (var k = 0; k < zn.length; k++) {
    final key = zn[k] == 'GLOBAL' ? 'zph_global' : 'zph_${zn[k]}';
    expect(r.statistics[key], closeRel(zv[k], rel: 1e-6), reason: 'cox.zph ${zn[k]}');
  }
}

void main() {
  final ref = loadRef('cox');
  final lung = parseCsv(File('test/reference/cox_lung.csv').readAsStringSync()).dataset;
  const lungTerms = [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'H'), TermSpec('ph.ecog'), TermSpec('wt.loss')];
  test('lung (NCCTG), ex aequo d\'Efron, cas complets — contre coxph et cox.zph', () {
    final s = buildSurvivalDesign(lung, 'time', 'deces', 'oui', lungTerms);
    check(coxRegression(s), s, ref['lung_efron'] as Map<String, dynamic>);
  });
  test('lung, ex aequo de Breslow', () {
    final s = buildSurvivalDesign(lung, 'time', 'deces', 'oui', lungTerms);
    check(coxRegression(s, efron: false), s, ref['lung_breslow'] as Map<String, dynamic>);
  });
  test('veteran : facteur à 4 modalités, non-proportionnalité détectée', () {
    final vet = parseCsv(File('test/reference/cox_veteran.csv').readAsStringSync()).dataset;
    final s = buildSurvivalDesign(vet, 'time', 'deces', 'oui', const [
      TermSpec('trt', categorical: true, reference: 'standard'),
      TermSpec('celltype', categorical: true, reference: 'squamous'),
      TermSpec('karno'),
      TermSpec('age'),
    ]);
    final r = coxRegression(s);
    check(r, s, ref['vet_efron'] as Map<String, dynamic>);
    expect(r.checks.firstWhere((c) => c.id == 'proportional_hazards').status, CheckStatus.warning);
  });
  test('vraisemblance monotone (aucun événement dans un groupe) : non rapportable', () {
    final ds = Dataset.fromColumns({
      't': [for (var i = 0; i < 30; i++) 5.0 + i],
      'e': [for (var i = 0; i < 30; i++) i < 15 ? 'non' : (i.isEven ? 'oui' : 'non')],
      'g': [for (var i = 0; i < 30; i++) i < 15 ? 'A' : 'B'],
    });
    final s = buildSurvivalDesign(ds, 't', 'e', 'oui', const [TermSpec('g', categorical: true, reference: 'A')]);
    final r = coxRegression(s);
    expect(r.reliable, isFalse);
    expect(r.alerts.map((a) => a.code), contains('cox_monotone'));
  });
  test('durées négatives refusées', () {
    final ds = Dataset.fromColumns({'t': [-1, 2, 3], 'e': ['oui', 'non', 'oui'], 'x': [1, 2, 3]});
    expect(() => buildSurvivalDesign(ds, 't', 'e', 'oui', const [TermSpec('x')]), throwsA(isA<StatInputError>()));
  });
}
