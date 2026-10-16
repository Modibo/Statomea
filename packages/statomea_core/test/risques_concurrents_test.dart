import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('risques_concurrents');
  final ds = parseCsv(File('test/reference/risques_concurrents_simule.csv').readAsStringSync()).dataset;
  final t = [for (final v in ds.numeric('mois')) v!];
  final st = ds.text('statut'), bras = ds.text('bras');
  List<double> v(Object? l) => [for (final x in l as List) asD(x) ?? double.nan];

  test('incidence cumulée d\'Aalen-Johansen et variance de Gray = cmprsk::cuminc (2 groupes × 2 causes)', () {
    final cif = ref['cif'] as Map;
    for (final g in ['A', 'B']) {
      final ii = [for (var i = 0; i < t.length; i++) if (bras[i] == g) i];
      final tt = [for (final i in ii) t[i]];
      final cc = [for (final i in ii) st[i] == 'rechute' ? 1 : (st[i] == 'deces' ? 2 : 0)];
      for (final cause in [1, 2]) {
        final r = cif['$g $cause'] as Map;
        final cv = cumulativeIncidence(tt, cc, cause);
        final time = v(r['time']), est = v(r['est']), va = v(r['var']), lo = v(r['lower']), hi = v(r['upper']);
        // cuminc ajoute une marche finale à la fin du suivi du groupe (même incidence) quand ce n'est pas un temps de la cause.
        final last = tt.reduce(math.max);
        final steps = cv.steps.length == time.length - 1 && time.last == last ? time.length - 1 : time.length;
        expect([for (final s in cv.steps) s.time], time.sublist(0, steps));
        if (steps < time.length) expect(est.last, closeRel(est[steps - 1], rel: 1e-15));
        for (var k = 0; k < steps; k++) {
          expect(cv.steps[k].cif, closeRel(est[k], rel: 1e-12, abs: 1e-15));
          expect(cv.steps[k].variance, closeRel(va[k], rel: 1e-10, abs: 1e-16));
          if (!lo[k].isNaN) {
            expect(cv.steps[k].lower, closeRel(lo[k], rel: 1e-9));
            expect(cv.steps[k].upper, closeRel(hi[k], rel: 1e-9));
          }
        }
      }
    }
  });

  test('analyse complète : incidence à 24 mois, 1 − Kaplan-Meier naïf (surestimation), sHR du bras = crr', () {
    final r = competingRisksAnalysis(ds.numeric('mois'), st, 'rechute', {'censure'}, groupRaw: bras, horizon: 24, timeUnit: 'mois', groupName: 'bras');
    final a = ref['at24'] as Map;
    expect(r.statistics['cif_A'], closeRel(asD(a['A'])!, rel: 1e-12));
    expect(r.statistics['cif_B'], closeRel(asD(a['B'])!, rel: 1e-12));
    expect(r.statistics['naive_A'], closeRel(asD(a['naiveA'])!, rel: 1e-12));
    expect(r.statistics['naive_B'], closeRel(asD(a['naiveB'])!, rel: 1e-12));
    expect(r.statistics['naive_A']!, greaterThan(r.statistics['cif_A']!));
    final fg = ref['fg_group'] as Map;
    final shr = r.estimates.firstWhere((e) => e.label.startsWith('sHR'));
    expect(shr.value, closeRel(math.exp(asD(fg['coef'])!), rel: 1e-8));
    final se = asD(fg['se'])!;
    expect(r.statistics['fg_wald'], closeRel(asD(fg['coef'])! * asD(fg['coef'])! / (se * se), rel: 1e-7));
    expect(r.figures['cumulativeIncidence'], isNotNull);
    expect(r.inputs['competing'], ['deces']);
  });

  test('modèle de Fine-Gray multivarié : coefficients, ES sandwich, log-pseudo-vraisemblance = crr ; Cox spécifique de cause = coxph', () {
    final s = buildCompetingDesign(ds, 'mois', 'statut', 'rechute', {'censure'}, [
      TermSpec('bras', categorical: true, reference: 'A'),
      TermSpec('age'),
      TermSpec('sexe', categorical: true, reference: 'F'),
    ]);
    expect(s.status.where((c) => c == 2).length, 141);
    final r = fineGrayRegression(s);
    final fg = ref['fg'] as Map, cs = ref['cs'] as Map;
    final coef = v(fg['coef']), se = v(fg['se']), csCoef = v(cs['coef']), csSe = v(cs['se']);
    final cols = s.design.columns;
    for (var j = 0; j < 3; j++) {
      expect(r.statistics['beta_${cols[j]}'], closeRel(coef[j], rel: 1e-8));
      expect(r.statistics['se_${cols[j]}'], closeRel(se[j], rel: 1e-7));
      expect(r.statistics['cs_beta_${cols[j]}'], closeRel(csCoef[j], rel: 1e-8));
      expect(r.statistics['cs_se_${cols[j]}'], closeRel(csSe[j], rel: 1e-8));
    }
    expect(r.statistics['loglik'], closeRel(asD(fg['loglik'])!, rel: 1e-10));
    expect(r.statistics['loglik_null'], closeRel(asD(fg['loglik_null'])!, rel: 1e-12));
    // L'âge : HR spécifique de cause > 1 mais sHR < 1 (les sujets âgés meurent avant de rechuter).
    expect(r.statistics['cs_beta_age']!, greaterThan(0));
    expect(r.statistics['beta_age']!, lessThan(0));
  });

  test('cas limites : sans événement concurrent, Fine-Gray = Cox (Breslow) ; erreurs explicites', () {
    final tt = <double>[2, 3, 3, 5, 7, 8, 11, 12, 15, 20];
    final cc = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0];
    final x = [for (var i = 0; i < 10; i++) [i.isEven ? 1.0 : 0.0]];
    final fg = fitFineGray(x, tt, cc);
    final cox = fitCox(x, tt, [for (final c in cc) c.toDouble()], efron: false);
    expect(fg.beta.first, closeRel(cox.beta.first, rel: 1e-9));
    final cv = cumulativeIncidence(tt, cc, 1);
    final km = kaplanMeier(tt, [for (final c in cc) c.toDouble()]);
    expect(cv.steps.last.cif, closeRel(1 - km.steps.where((s) => s.events > 0).last.surv, rel: 1e-12));
    expect(() => competingRisksAnalysis(<double>[1, 2], ['a', 'b'], 'x', {'b'}), throwsA(isA<StatInputError>()));
    expect(() => competingRisksAnalysis(<double>[1, 2], ['a', 'b'], 'a', {'a'}), throwsA(isA<StatInputError>()));
  });
}
