import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('bayesien');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  test('proportion bêta-binomiale : a priori uniforme, Jeffreys, informatif = qbeta, pbeta', () {
    for (final (key, res) in [
      ('uniform', bayesProportion(7, 40, threshold: 0.1)),
      ('jeffreys', bayesProportion(7, 40, prior: BetaPrior.jeffreys, threshold: 0.1)),
      ('informative', bayesProportion(7, 40, prior: BetaPrior.informative, priorMean: 0.1, priorWeight: 20, threshold: 0.1)),
    ]) {
      final r = ref[key] as Map;
      expect(res.statistics['post_a'], closeRel(asD(r['a'])!, rel: 1e-12), reason: key);
      expect(res.statistics['mean'], closeRel(asD(r['mean'])!, rel: 1e-12));
      expect(res.statistics['median'], closeRel(asD(r['median'])!, rel: 1e-9));
      expect(res.statistics['mode'], closeRel(asD(r['mode'])!, rel: 1e-12));
      final ci = v(r['ci']);
      expect(res.statistics['lower'], closeRel(ci[0], rel: 1e-9), reason: key);
      expect(res.statistics['upper'], closeRel(ci[1], rel: 1e-9));
      expect(res.statistics['p_gt'], closeRel(asD(r['p_gt'])!, rel: 1e-9));
    }
  });

  test('effet publié (RR 0,75 [0,58 ; 0,97], cible 0,80) : a priori sceptique, enthousiaste, vague = qnorm, pnorm', () {
    for (final (key, prior) in [('sceptical', NormalPrior.sceptical), ('enthusiastic', NormalPrior.enthusiastic), ('vague', NormalPrior.vague)]) {
      final r = ref[key] as Map;
      final res = bayesEffect(0.75, 0.58, 0.97, target: 0.8, prior: prior);
      expect(res.statistics['se'], closeRel(asD(r['se'])!, rel: 1e-12), reason: key);
      expect(res.statistics['post_mean'], closeRel(asD(r['post_mean'])!, rel: 1e-12), reason: key);
      expect(res.statistics['post_sd'], closeRel(asD(r['post_sd'])!, rel: 1e-12));
      final ci = v(r['ci']);
      expect(res.statistics['lower'], closeRel(ci[0], rel: 1e-10));
      expect(res.statistics['upper'], closeRel(ci[1], rel: 1e-10));
      expect(res.statistics['p_benefit'], closeRel(asD(r['p_benefit'])!, rel: 1e-9));
      expect(res.statistics['p_target'], closeRel(asD(r['p_target'])!, rel: 1e-9));
    }
    expect(bayesEffect(0.75, 0.58, 0.97, target: 0.8).statistics['prior_sd'], closeRel(asD(ref['tau_sceptical'])!, rel: 1e-12));
    expect(() => bayesEffect(0.75, 0.8, 0.97, target: 0.8), throwsA(isA<StatInputError>()));
  });
}
