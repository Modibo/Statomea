import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('puissance');
  final m = ref['means'] as Map, cc = ref['cc'] as Map, s = ref['surv'] as Map, g = ref['gwas'] as Map;

  test('deux moyennes : pwr.t2n.test (groupes inégaux) ; apparié et un échantillon : power.t.test(strict = TRUE)', () {
    expect(powerTwoMeansD(40, 80, 0.5), closeRel(asD(m['power_40_80'])!, rel: 1e-9));
    expect(solveSampleSize((n) => powerTwoMeansD(n, 2 * n, 0.5), 0.9, lo: 2.0001), closeRel(asD(m['n1_ratio2'])!, rel: 1e-7));
    expect(solveSampleSize((n) => powerTwoMeansD(n, n, 0.4), 0.8, lo: 2.0001), closeRel(asD(m['n_equal_d04'])!, rel: 1e-7));
    expect(solveSampleSize((n) => powerOneSampleD(n, 3 / 8), 0.85, lo: 2.0001), closeRel(asD(m['paired_n'])!, rel: 1e-7));
    expect(powerOneSampleD(50, 3 / 8), closeRel(asD(m['paired_power'])!, rel: 1e-9));
    expect(solveSampleSize((n) => powerOneSampleD(n, 0.3), 0.8, lo: 2.0001), closeRel(asD(m['one_n'])!, rel: 1e-7));
    final r = powerMeans(delta: 5, sd: 10, ratio: 2, power: 0.9);
    expect(r.statistics['n_exact'], closeRel(asD(m['n1_ratio2'])!, rel: 1e-7));
    expect(r.statistics['n_0'], 64);
    expect(r.statistics['n_1'], 128);
    expect(r.statistics['power']!, greaterThanOrEqualTo(0.9));
  });

  test('deux proportions : puissance pour n donné = power.prop.test', () {
    expect(powerTwoProportionsN(150, 0.30, 0.18), closeRel(asD((ref['props'] as Map)['power_150'])!, rel: 1e-12));
    final r = powerProportions(p1: 0.30, p2: 0.18, n: 150);
    expect(r.statistics['power'], closeRel(asD((ref['props'] as Map)['power_150'])!, rel: 1e-12));
    expect(r.alerts.any((a) => a.code == 'low_power'), isTrue);
  });

  test('cas-témoins (OR 2, exposition 20 %, 2 témoins par cas) = pwr.2p2n.test', () {
    expect(exposureInCases(2, 0.2), closeRel(asD(cc['p1'])!, rel: 1e-14));
    final r = powerCaseControl(or: 2, p0: 0.2, ratio: 2);
    expect(r.statistics['h'], closeRel(asD(cc['h'])!, rel: 1e-14));
    expect(r.statistics['n_exact'], closeRel(asD(cc['n_cases'])!, rel: 1e-7));
    expect(r.statistics['n_0'], 128);
    expect(r.statistics['n_1'], 256);
    final p = powerCaseControl(or: 2, p0: 0.2, ratio: 2, nCases: 120);
    expect(p.statistics['power'], closeRel(asD(cc['power_120_240'])!, rel: 1e-12));
  });

  test('survie (HR 0,7, 45 % d\'événements en contrôle) : Freedman = powerSurvEpi ; Schoenfeld', () {
    final r = powerSurvival(hr: 0.7, pC: 0.45);
    expect(r.statistics['pE'], closeRel(asD(s['pE'])!, rel: 1e-14));
    expect(r.statistics['events_freedman'], closeRel(asD(s['m'])!, rel: 1e-12));
    expect(r.statistics['n_0'], asD(s['nE']));
    expect(r.statistics['n_1'], asD(s['nC']));
    expect(r.statistics['events_schoenfeld'], closeRel(asD(s['schoenfeld'])!, rel: 1e-12));
    final p = powerSurvival(hr: 0.7, pC: 0.45, nControl: 300);
    expect(p.statistics['power'], closeRel(asD(s['power_300'])!, rel: 1e-12));
  });

  test('GWAS : non-centralité et puissance au seuil 5e-8 = pchisq non central ; effectif pour 80 %', () {
    final a = gwasAllelicPower(0.25, 1.2, 5000, 5000), b = gwasAllelicPower(0.05, 1.3, 3000, 6000);
    expect(a.lambda, closeRel(asD(g['lambda1'])!, rel: 1e-12));
    expect(a.power, closeRel(asD(g['power1'])!, rel: 1e-9));
    expect(b.lambda, closeRel(asD(g['lambda2'])!, rel: 1e-12));
    expect(b.power, closeRel(asD(g['power2'])!, rel: 1e-9));
    final r = powerGwas(maf: 0.25, or: 1.15);
    expect(r.statistics['n_exact'], closeRel(asD(g['n_equal'])!, rel: 1e-7));
    expect(r.figures['powerCurve'], isNotNull);
  });

  test('paramètres invalides refusés', () {
    expect(() => powerMeans(delta: 0, sd: 1), throwsA(isA<StatInputError>()));
    expect(() => powerCaseControl(or: 1, p0: 0.2), throwsA(isA<StatInputError>()));
    expect(() => powerSurvival(hr: 0.7, pC: 1.2), throwsA(isA<StatInputError>()));
    expect(() => powerGwas(maf: 0, or: 1.2), throwsA(isA<StatInputError>()));
  });
}
