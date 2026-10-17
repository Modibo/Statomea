import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('propension');
  List<double> v(Object? l) => [for (final x in l as List) asD(x) ?? double.nan];
  final sim = parseCsv(File('test/reference/statines_observationnel_simule.csv').readAsStringSync()).dataset;
  final lal = parseCsv(File('test/reference/lalonde.csv').readAsStringSync()).dataset;
  const simCov = [
    TermSpec('age'),
    TermSpec('sexe', categorical: true, reference: 'F'),
    TermSpec('diabete', categorical: true, reference: 'non'),
    TermSpec('ldl'),
    TermSpec('tabac', categorical: true, reference: 'non'),
  ];
  const lalCov = [TermSpec('age'), TermSpec('educ'), TermSpec('race', categorical: true, reference: 'black'), TermSpec('married'), TermSpec('nodegree'), TermSpec('re74'), TermSpec('re75')];
  const simMap = {'distance': 'ps', 'prop.score': 'ps', 'age': 'age', 'sexe_H': 'sexe = H (vs F)', 'diabete_oui': 'diabete = oui (vs non)', 'ldl': 'ldl', 'tabac_oui': 'tabac = oui (vs non)'};
  const lalMap = {
    'distance': 'ps', 'prop.score': 'ps', 'age': 'age', 'educ': 'educ', 'race_hispan': 'race = hispan (vs black)', 'race_white': 'race = white (vs black)', 'married': 'married', 'nodegree': 'nodegree', 're74': 're74', 're75': 're75'
  };

  void balance(AnalysisResult res, Map r, Map<String, String> map, {String? prefix}) {
    final rows = [for (final x in r['rows'] as List) x as String];
    final un = v(r['smd_un']), adj = v(r['smd']), vr = v(r['vr']);
    for (var k = 0; k < rows.length; k++) {
      final key = map[rows[k]];
      if (key == null) continue; // modalité de référence (cobalt les affiche toutes)
      expect(res.statistics['smd_un_$key'], closeRel(un[k], rel: 1e-8, abs: 1e-10), reason: 'DMS avant ${rows[k]}');
      expect(res.statistics['smd_$key'], closeRel(adj[k], rel: 1e-8, abs: 1e-10), reason: 'DMS après ${rows[k]}');
      if (!vr[k].isNaN && res.statistics['vr_$key'] != null) expect(res.statistics['vr_$key'], closeRel(vr[k], rel: 1e-8), reason: 'RV ${rows[k]}');
    }
  }

  for (final (name, ds, cov, map, tVar, yVar, yEv, cal) in [
    ('simulée (issue binaire, caliper 0,2)', sim, simCov, simMap, 'statine', 'evenement', '1', 0.2),
    ('lalonde (issue continue, sans caliper)', lal, lalCov, lalMap, 'traite', 're78', null, null),
  ]) {
    final r = ref[name.startsWith('sim') ? 'sim' : 'lalonde'] as Map;
    test('appariement $name : paires, équilibre, effet (ES par paire) = MatchIt, cobalt, sandwich', () {
      final res = propensityAnalysis(ds, treatment: tVar, treatedLevel: 'oui', covariates: cov, outcome: yVar, outcomeEvent: yEv, caliper: cal);
      final t = ds.text(tVar);
      final treated = [for (var i = 0; i < ds.rowCount; i++) if (t[i] == 'oui') i];
      final ps = v(r['ps']);
      final d = buildDesign(ds, ModelFormula(tVar, cov, eventLevel: 'oui'), binaryOutcome: true);
      final fit = fitLogistic(d.x, d.y);
      for (var i = 0; i < ps.length; i += 37) {
        expect(fit.mu[i], closeRel(ps[i], rel: 1e-9));
      }
      final pairs = nearestNeighborMatch(fit.mu, [for (final y in d.y) y.toInt()], caliper: cal == null ? null : asD(r['caliper_width']));
      final rp = v(r['pairs']);
      for (var k = 0; k < treated.length; k++) {
        final m = pairs[treated[k]];
        expect(m == null ? double.nan : m + 1.0, rp[k].isNaN ? isNaN : rp[k], reason: 'traité ${treated[k] + 1}');
      }
      expect(res.statistics['n_matched'], asD(r['n_matched']));
      if (cal != null) expect(res.statistics['caliper_width'], closeRel(asD(r['caliper_width'])!, rel: 1e-9));
      balance(res, r, map);
      final e = v(r['effect_m']);
      expect(res.statistics['effect'], closeRel(e[0], rel: 1e-9));
      expect(res.statistics['effect_se'], closeRel(e[1], rel: 1e-8));
      expect(res.figures['lovePlot'], isA<Map>());
    });

    for (final (est, method) in [('ate', PropensityMethod.iptwAte), ('att', PropensityMethod.iptwAtt)]) {
      test('pondération ${est.toUpperCase()} $name : équilibre, taille effective, effet (HC0) = WeightIt, cobalt, sandwich', () {
        final res = propensityAnalysis(ds, treatment: tVar, treatedLevel: 'oui', covariates: cov, outcome: yVar, outcomeEvent: yEv, method: method);
        final w = r[est] as Map;
        balance(res, w, map);
        final ess = v(w['ess']);
        expect(res.statistics['ess_control'], closeRel(ess[0], rel: 1e-9));
        expect(res.statistics['ess_treated'], closeRel(ess[1], rel: 1e-9));
        final e = v(w['effect']);
        expect(res.statistics['effect'], closeRel(e[0], rel: 1e-9));
        expect(res.statistics['effect_se'], closeRel(e[1], rel: 1e-8));
      });
    }
  }

  test('sans covariable, ou traitement parmi les covariables : refus', () {
    expect(() => propensityAnalysis(sim, treatment: 'statine', treatedLevel: 'oui', covariates: const []), throwsA(isA<StatInputError>()));
    expect(() => propensityAnalysis(sim, treatment: 'statine', treatedLevel: 'oui', covariates: const [TermSpec('statine', categorical: true, reference: 'non')]), throwsA(isA<StatInputError>()));
  });
}
