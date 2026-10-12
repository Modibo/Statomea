import 'dart:io';
import 'dart:math' show exp;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];
List<List<double>> dm(Object? v) => [for (final r in v as List) dl(r)];

void main() {
  final ref = loadRef('regression');
  final ds = parseCsv(File('test/reference/regression_data.csv').readAsStringSync()).dataset;
  const terms = [
    TermSpec('age'),
    TermSpec('sexe', categorical: true, reference: 'F'),
    TermSpec('imc'),
    TermSpec('tabac', categorical: true, reference: 'non'),
  ];

  test('import : types inférés et identifiant reconnu', () {
    expect(ds.dictionary['id']!.type, VarType.identifier);
    expect(ds.dictionary['age']!.type, VarType.numeric);
    expect(ds.dictionary['sexe']!.type, VarType.binary);
    expect(ds.dictionary['tabac']!.type, VarType.categorical);
  });

  group('Régression linéaire contre R lm / car::vif', () {
    final d = buildDesign(ds, const ModelFormula('pas', terms));
    final r = linearRegression(d);
    final l = ref['linear'] as Map<String, dynamic>;
    test('observations en cas complets', () {
      expect(d.n, ref['n_complete']);
      expect(d.excludedBy['imc'], 3);
      expect(r.alerts.map((a) => a.code), contains('complete_case'));
    });
    test('coefficients, ES, p, IC', () {
      final b = dl(l['coef']), se = dl(l['se']), p = dl(l['p']);
      final ci = dm(l['ci']);
      for (var j = 0; j < b.length; j++) {
        final e = r.estimates[j];
        expect(e.value, closeRel(b[j], rel: 1e-9), reason: 'β$j');
        expect(e.se, closeRel(se[j], rel: 1e-9), reason: 'ES$j');
        expect(e.pValue, closeRel(p[j], rel: 1e-6, abs: 1e-15), reason: 'p$j');
        expect(e.lower, closeRel(ci[j][0], rel: 1e-9));
        expect(e.upper, closeRel(ci[j][1], rel: 1e-9));
      }
    });
    test('R², σ, F, Breusch-Pagan, Cook, GVIF', () {
      expect(r.statistics['r2'], closeRel(asD(l['r2'])!, rel: 1e-10));
      expect(r.statistics['adj_r2'], closeRel(asD(l['adj_r2'])!, rel: 1e-10));
      expect(r.statistics['sigma'], closeRel(asD(l['sigma'])!, rel: 1e-10));
      expect(r.statistics['F'], closeRel(asD(l['F'])!, rel: 1e-9));
      expect(r.statistics['bp'], closeRel(asD(l['bp'])!, rel: 1e-8));
      expect(r.statistics['max_cook'], closeRel(asD(l['max_cook'])!, rel: 1e-8));
      final g = l['gvif'] as Map<String, dynamic>;
      for (final k in g.keys) {
        expect(r.statistics['gvif_$k'], closeRel(asD(g[k])!, rel: 1e-8), reason: k);
      }
    });
  });

  group('Régression logistique contre R glm', () {
    final d = buildDesign(ds, const ModelFormula('hta', terms, eventLevel: '1'), binaryOutcome: true);
    final r = logisticRegression(d, design: StudyDesign.cohort);
    final l = ref['logistic'] as Map<String, dynamic>;
    test('β, ES, p, IC de Wald, déviance, AIC', () {
      final b = dl(l['coef']), se = dl(l['se']), p = dl(l['p']);
      final ci = dm(l['ci_wald']);
      final names = d.columns;
      for (var j = 0; j < b.length; j++) {
        expect(r.statistics['beta_${names[j]}'], closeRel(b[j], rel: 1e-7), reason: 'β$j');
        expect(r.statistics['se_${names[j]}'], closeRel(se[j], rel: 1e-6), reason: 'ES$j');
      }
      for (var j = 1; j < b.length; j++) {
        final e = r.estimates[j - 1];
        expect(e.pValue, closeRel(p[j], rel: 1e-5), reason: 'p$j');
        expect(e.lower, closeRel(exp(ci[j][0]), rel: 1e-6));
        expect(e.upper, closeRel(exp(ci[j][1]), rel: 1e-6));
      }
      expect(r.statistics['deviance'], closeRel(asD(l['deviance'])!, rel: 1e-9));
      expect(r.statistics['null_deviance'], closeRel(asD(l['null_deviance'])!, rel: 1e-9));
      expect(r.statistics['aic'], closeRel(asD(l['aic'])!, rel: 1e-9));
      expect(r.checks.firstWhere((c) => c.id == 'separation').status, CheckStatus.ok);
    });
  });

  group('Poisson à variance robuste contre R glm + sandwich HC0', () {
    final d = buildDesign(ds, const ModelFormula('hta', terms, eventLevel: '1'), binaryOutcome: true);
    final r = poissonRobustRegression(d, design: StudyDesign.cohort);
    final l = ref['poisson'] as Map<String, dynamic>;
    test('β et ES robustes', () {
      final b = dl(l['coef']), se = dl(l['se']);
      for (var j = 0; j < b.length; j++) {
        expect(r.statistics['beta_${d.columns[j]}'], closeRel(b[j], rel: 1e-7), reason: 'β$j');
        expect(r.statistics['se_${d.columns[j]}'], closeRel(se[j], rel: 1e-6), reason: 'ES$j');
      }
    });
    test('refusée en cas-témoins', () {
      expect(() => poissonRobustRegression(d, design: StudyDesign.caseControl), throwsA(isA<StatInputError>()));
    });
  });

  group('Séparation et Firth contre R logistf', () {
    final fd = parseCsv(File('test/reference/firth_data.csv').readAsStringSync()).dataset;
    final d = buildDesign(fd, const ModelFormula('y', [TermSpec('x1'), TermSpec('grp', categorical: true, reference: 'A')], eventLevel: '1'),
        binaryOutcome: true);
    final f = ref['firth'] as Map<String, dynamic>;
    test('le maximum de vraisemblance détecte la séparation et bloque le résultat', () {
      final r = logisticRegression(d);
      expect(r.checks.firstWhere((c) => c.id == 'separation').status, CheckStatus.violated);
      expect(r.alerts.any((a) => a.code == 'separation' && a.severity == Severity.critical), isTrue);
      expect(r.reliable, isFalse);
      expect(r.alerts.map((a) => a.code), contains('epv_very_low'));
    });
    test('Firth : β, ES, IC de Wald, log-vraisemblance pénalisée', () {
      final r = firthRegression(d);
      final b = dl(f['coef']), se = dl(f['se']);
      final ci = dm(f['ci']);
      for (var j = 0; j < b.length; j++) {
        expect(r.statistics['beta_${d.columns[j]}'], closeRel(b[j], rel: 1e-7), reason: 'β$j');
        expect(r.statistics['se_${d.columns[j]}'], closeRel(se[j], rel: 1e-6), reason: 'ES$j');
      }
      // IC de Wald (logistf, pl = FALSE) : tableau « OR (Wald) » ; les estimations portent les IC profilés
      // (validés dans firth_profile_test.dart).
      final wald = r.tables.firstWhere((t) => t.title == 'Coefficients');
      for (var j = 1; j < b.length; j++) {
        final se = r.statistics['se_${d.columns[j]}']!;
        expect(b[j] - 1.959963984540054 * se, closeRel(ci[j][0], rel: 1e-6));
        expect(b[j] + 1.959963984540054 * se, closeRel(ci[j][1], rel: 1e-6));
        expect(wald.rows[j][0], d.columns[j]);
      }
      expect(r.statistics['penalized_loglik'], closeRel(asD(f['loglik'])!, rel: 1e-8));
    });
  });
}

