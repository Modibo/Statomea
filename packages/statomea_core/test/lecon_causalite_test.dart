import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  for (final lang in Lang.values) {
    test('leçon causalité (${lang.name}) : réponses cohérentes avec le moteur, liens du registre', () {
      withLang(lang, () {
        final l = lessonById(buildLessons(), 'causal_mr')!;
        final num = l.exercises.where((e) => e.isNumeric).toList();
        expect(num, hasLength(3));
        // OR de Wald : exp(βY/βX), par le moteur (un rapport de Wald = IVW d'un variant).
        expect(num[0].check(fmtFixed(math.exp(0.10 / 0.20), 2)), isTrue);
        expect(num[1].check('25'), isTrue);
        // r² de Steiger (moteur) : F/(N − 2 + F), en %
        expect(num[2].check(fmtFixed(100 * mrRFromBsen(10, 1, 10000) * mrRFromBsen(10, 1, 10000), 2)), isTrue);
        expect(l.calculatorId, 'mendelian_randomization');
        for (final m in ['mendelian_randomization', 'mendelian_randomization_mv', 'mr_steiger']) {
          expect(methodInfo(m)!.lessonId, 'causal_mr', reason: m);
        }
      });
    });
  }

  test('données intégrées identiques au fichier publié ; exemple = estimations validées contre R', () {
    final ref = loadRef('mr'), refS = loadRef('mr_sensibilite');
    final d = mrLipidExample;
    final f = mendelianRandomization(d.bldl, d.sldl, d.bchd, d.schd, iterations: 100);
    expect(f.ivw.estimate, closeRel(asD((ref['ivw'] as Map)['estimate'])!, rel: 1e-12));
    expect(f.egger.estimate, closeRel(asD((ref['egger'] as Map)['estimate'])!, rel: 1e-12));
    final mv = multivariableMendelianRandomization([d.bldl, d.bhdl, d.btg], [d.sldl, d.shdl, d.stg], d.bchd, d.schd, exposures: const ['LDL', 'HDL', 'TG']);
    expect(mv.estimates[1].estimate, closeRel(asD(((refS['mv'] as Map)['estimate'] as List)[1])!, rel: 1e-10));
    final l = withLang(Lang.fr, () => lessonById(buildLessons(), 'causal_mr')!);
    expect(l.example, contains('IVW 2,83'));
    expect(l.example, contains('effet direct du HDL vaut −0,59'));
  });

  test('construction des leçons rapide (exemples calculés au démarrage)', () {
    final sw = Stopwatch()..start();
    buildLessons();
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
