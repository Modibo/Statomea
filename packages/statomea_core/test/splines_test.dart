import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('splines');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  Dataset csv(String f, {int? rows}) {
    final lines = File('test/reference/$f').readAsLinesSync();
    return parseCsv((rows == null ? lines : lines.take(rows + 1)).join('\n')).dataset;
  }

  final reg = csv('regression_data.csv');
  final cm = csv('cardiometabolique_simule.csv');
  final lung = csv('cox_lung.csv');

  void same(AnalysisResult res, Map r, String variable, List<String> cols, {double rel = 1e-8}) {
    final knots = v(r['knots']);
    for (var k = 0; k < knots.length; k++) {
      expect(res.statistics['spline_${variable}_knot${k + 1}'], closeRel(knots[k], rel: 1e-12), reason: 'nœud ${k + 1}');
    }
    final coef = v(r['coef']), se = v(r['se']);
    for (var j = 0; j < cols.length; j++) {
      final e = res.estimates.where((e) => e.label == cols[j]).firstOrNull;
      expect(e?.value ?? res.statistics['beta_${cols[j]}'], closeRel(coef[j], rel: rel), reason: 'β ${cols[j]}');
      expect(e?.se ?? res.statistics['se_${cols[j]}'], closeRel(se[j], rel: rel), reason: 'ES ${cols[j]}');
    }
    final o = v(r['overall']), n = v(r['nonlinear']);
    expect(res.statistics['spline_${variable}_stat'], closeRel(o[0], rel: rel));
    expect(res.statistics['spline_${variable}_p'], closeRel(o[2], rel: 1e-6, abs: 1e-12));
    expect(res.statistics['spline_${variable}_nonlinear_stat'], closeRel(n[0], rel: rel));
    expect(res.statistics['spline_${variable}_nonlinear_p'], closeRel(n[2], rel: 1e-7));
    expect(res.statistics['spline_${variable}_ref'], asD(r['ref']));
    final curve = (res.figures['doseResponse'] as List).cast<Map>().firstWhere((c) => c['variable'] == variable);
    final x = v(r['x']), est = v(r['est']), lo = v(r['lower']), hi = v(r['upper']);
    final exp = curve['log'] == true;
    for (var k = 0; k < 5; k++) {
      final g = k * 15;
      expect((curve['x'] as List<double>)[g], closeRel(x[k], rel: 1e-12));
      // rms::Predict donne le contraste sur l'échelle du prédicteur linéaire : la courbe exponentiée est ramenée au log.
      double back(double u) => exp ? math.log(u) : u;
      expect(back((curve['est'] as List<double>)[g]), closeRel(est[k], rel: 1e-7, abs: 1e-10), reason: 'contraste x = ${x[k]}');
      expect(back((curve['lower'] as List<double>)[g]), closeRel(lo[k], rel: 1e-7, abs: 1e-10));
      expect(back((curve['upper'] as List<double>)[g]), closeRel(hi[k], rel: 1e-7, abs: 1e-10));
    }
  }

  test('nœuds de Hmisc::rcspline.eval : quantiles, et 5e plus petite/plus grande valeur sous 100 observations', () {
    for (final (k, vals, nk) in [
      ('linear', reg.numeric('age'), 4),
      ('small', reg.numeric('age').take(60).toList(), 5),
      ('logistic', cm.numeric('imc'), 4),
      ('cox', lung.numeric('age'), 3),
    ]) {
      final knots = rcsKnots([for (final x in vals) x!], nk);
      final r = v((ref[k] as Map)['knots_hmisc']);
      expect(knots.length, r.length);
      for (var j = 0; j < r.length; j++) {
        expect(knots[j], closeRel(r[j], rel: 1e-12), reason: '$k nœud $j');
      }
    }
  });

  test('linéaire : pas ~ rcs(âge, 4) + sexe = rms::ols, anova (F) et Predict', () {
    final d = buildDesign(reg, const ModelFormula('pas', [TermSpec('age', transform: TermTransform.rcs4), TermSpec('sexe', categorical: true, reference: 'F')]));
    expect(d.columns, ['Constante', 'age', "age'", "age''", 'sexe = H (vs F)']);
    same(linearRegression(d), ref['linear'] as Map, 'age', d.columns, rel: 1e-9);
  });

  test('moins de 100 observations : rcs(âge, 5) = rms::ols', () {
    final d = buildDesign(csv('regression_data.csv', rows: 60), const ModelFormula('pas', [TermSpec('age', transform: TermTransform.rcs5)]));
    same(linearRegression(d), ref['small'] as Map, 'age', d.columns, rel: 1e-8);
  });

  test('logistique : événement ~ rcs(IMC, 4) + âge + sexe = rms::lrm, Wald et Predict', () {
    final d = buildDesign(cm, const ModelFormula('evenement_5ans', [TermSpec('imc', transform: TermTransform.rcs4), TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F')], eventLevel: '1'),
        binaryOutcome: true);
    final res = logisticRegression(d);
    same(res, ref['logistic'] as Map, 'imc', d.columns, rel: 1e-7);
    expect(res.checks.any((c) => c.id == 'spline_linearity'), isTrue);
  });

  test('Cox : rcs(âge, 3) + sexe = rms::cph (Efron)', () {
    final s = buildSurvivalDesign(lung, 'time', 'deces', 'oui', const [TermSpec('age', transform: TermTransform.rcs3), TermSpec('sexe', categorical: true, reference: 'F')]);
    same(coxRegression(s), ref['cox'] as Map, 'age', s.design.columns, rel: 1e-7);
  });

  test('nœuds figés : une équation réappliquée garde les nœuds du développement ; interaction refusée', () {
    final d = buildDesign(reg, const ModelFormula('pas', [TermSpec('age', transform: TermTransform.rcs4)]));
    final frozen = const TermSpec('age', transform: TermTransform.rcs4).withKnotsFrom(d);
    expect(frozen.knots, d.splineKnots['age']);
    final back = TermSpec.fromJson(frozen.toJson());
    final d2 = buildDesign(csv('regression_data.csv', rows: 60), ModelFormula('pas', [back]));
    expect(d2.splineKnots['age'], d.splineKnots['age']);
    expect(() => buildDesign(reg, const ModelFormula('pas', [TermSpec('age', transform: TermTransform.rcs3), TermSpec('imc')], interactions: [('age', 'imc')])),
        throwsA(isA<StatInputError>()));
  });
}
