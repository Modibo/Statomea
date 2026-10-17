import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('comptages');
  List<double> v(Object? l) => l is List ? [for (final x in l) asD(x)!] : [asD(l)!];
  final quine = parseCsv(File('test/reference/absences_quine.csv').readAsStringSync()).dataset;
  final ins = parseCsv(File('test/reference/sinistres_assurance.csv').readAsStringSync()).dataset;
  const fq = ModelFormula('jours_absence', [
    TermSpec('origine', categorical: true, reference: 'aborigene'), TermSpec('sexe', categorical: true, reference: 'F'),
    TermSpec('age', categorical: true, reference: 'F0'), TermSpec('apprentissage', categorical: true, reference: 'lent'),
  ]);
  const fi = ModelFormula('sinistres', [
    TermSpec('district', categorical: true, reference: 'D1'), TermSpec('puissance', categorical: true, reference: 'p1_moins_1l'),
    TermSpec('age', categorical: true, reference: 'a1_moins_25'),
  ]);

  void coefs(AnalysisResult r, Map ref0, {double tb = 1e-9, double ts = 1e-8, bool se = true}) {
    final cols = (r.inputs['model'] as Map)['columns'] as List;
    final b = v(ref0['beta']), s = se ? v(ref0['se']) : <double>[];
    for (var j = 0; j < b.length; j++) {
      expect(r.statistics['beta_${cols[j]}'], closeRel(b[j], rel: tb, abs: 1e-12), reason: 'β ${cols[j]}');
      if (se) expect(r.statistics['se_${cols[j]}'], closeRel(s[j], rel: ts), reason: 'ES ${cols[j]}');
    }
  }

  test('Poisson (quine) : β, ES, déviance, χ² de Pearson, log-vraisemblance = glm', () {
    final r = countRegression(quine, fq, model: CountModel.poisson);
    final p = ref['quine_pois'] as Map;
    coefs(r, p);
    expect(r.statistics['deviance'], closeRel(asD(p['deviance'])!, rel: 1e-10));
    expect(r.statistics['pearson'], closeRel(asD(p['pearson'])!, rel: 1e-10));
    expect(r.statistics['loglik'], closeRel(asD(p['loglik'])!, rel: 1e-10));
    expect(r.alerts.any((a) => a.code == 'overdispersion'), isTrue);
  });

  test('quasi-Poisson : ES × √φ = glm(quasipoisson)', () {
    final r = countRegression(quine, fq, model: CountModel.quasiPoisson);
    final q = ref['quine_quasi'] as Map;
    expect(r.statistics['dispersion_poisson'], closeRel(asD(q['dispersion'])!, rel: 1e-10));
    final cols = (r.inputs['model'] as Map)['columns'] as List;
    final se = v(q['se']);
    for (var j = 0; j < se.length; j++) {
      expect(r.statistics['se_${cols[j]}'], closeRel(se[j], rel: 1e-8));
    }
  });

  test('binomiale négative (quine) : β, ES, θ, ES(θ), log-vraisemblance = MASS::glm.nb ; RV contre Poisson', () {
    final r = countRegression(quine, fq);
    final nb = ref['quine_nb'] as Map;
    coefs(r, nb, tb: 1e-6, ts: 1e-6);
    expect(r.statistics['theta'], closeRel(asD(nb['theta'])!, rel: 1e-6));
    expect(r.statistics['se_theta'], closeRel(asD(nb['se_theta'])!, rel: 1e-5));
    expect(r.statistics['loglik'], closeRel(asD(nb['loglik'])!, rel: 1e-10));
    final l = ref['quine_lrt'] as Map;
    expect(r.statistics['lrt_nb'], closeRel(asD(l['stat'])!, rel: 1e-7));
  });

  test('Poisson avec offset log(assurés) (Insurance) = glm ; binomiale négative : θ → ∞, signalé, β = Poisson', () {
    final r = countRegression(ins, fi, model: CountModel.poisson, exposure: 'assures');
    final p = ref['ins_pois'] as Map;
    coefs(r, p);
    expect(r.statistics['deviance'], closeRel(asD(p['deviance'])!, rel: 1e-10));
    final nb = countRegression(ins, fi, exposure: 'assures');
    expect(nb.alerts.any((a) => a.code == 'theta_infinite'), isTrue);
    coefs(nb, p, tb: 1e-4, se: false);
  });

  test('erreurs : comptage négatif ou non entier refusé', () {
    final bad = Dataset(['y', 'x'], [['1.5', '1'], ['2', '0'], ['0', '1']]);
    expect(() => countRegression(bad, const ModelFormula('y', [TermSpec('x')])), throwsA(isA<StatInputError>()));
  });
}
