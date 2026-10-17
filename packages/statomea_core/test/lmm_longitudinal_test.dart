import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('lmm_longitudinal');
  List<double> v(Object? l) => l is List ? [for (final x in l) asD(x)!] : [asD(l)!];
  final sleep = parseCsv(File('test/reference/sommeil_belenky.csv').readAsStringSync()).dataset;
  final hb = parseCsv(File('test/reference/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;

  LmmData data(Dataset ds, ModelFormula f, String subject, String? slope) {
    final d = buildDesign(ds, f);
    final s = ds.text(subject), sl = slope == null ? null : ds.numeric(slope);
    final ids = <String, int>{};
    return LmmData(d.x, d.y, [for (final r in d.rows) ids.putIfAbsent(s[r]!, () => ids.length)],
        [for (final r in d.rows) [1.0, if (sl != null) sl[r]!]]);
  }

  void check(String key, Dataset ds, ModelFormula f, String subject, String? slope) {
    final r = ref[key] as Map;
    final d = data(ds, f, subject, slope);
    // Déviance REML au θ de lme4 : formule exacte.
    expect(lmmRemlDeviance(d, v(r['theta'])), closeRel(asD(r['reml'])!, rel: 1e-10), reason: '$key déviance');
    final res = longitudinalMixedModel(ds, f, subject: subject, slope: slope);
    final cols = (res.inputs['model'] as Map)['columns'] as List;
    final beta = v(r['beta']), se = v(r['se']), df = v(r['df']), p = v(r['p']), ndf = v(r['nlme_df']);
    for (var j = 0; j < beta.length; j++) {
      expect(res.statistics['beta_${cols[j]}'], closeRel(beta[j], rel: 1e-6, abs: 1e-9), reason: '$key β ${cols[j]}');
      expect(res.statistics['se_${cols[j]}'], closeRel(se[j], rel: 1e-5), reason: '$key ES ${cols[j]}');
      expect(res.statistics['df_${cols[j]}'], df[j]);
      expect(res.statistics['df_${cols[j]}'], ndf[j], reason: 'ddl de nlme');
      expect(res.statistics['p_${cols[j]}'], closeRel(p[j], rel: 1e-4, abs: 1e-12));
    }
    expect(res.statistics['reml'], closeRel(asD(r['reml'])!, rel: 1e-10)); // optimum atteint
    expect(res.statistics['sigma'], closeRel(asD(r['sigma'])!, rel: 1e-5));
    final sd = v(r['vc_sdcor']); // (intercept, pente, corrélation, résidu) ou (intercept, résidu)
    expect(res.statistics['sd_intercept'], closeRel(sd[0], rel: 1e-4));
    if (slope != null) {
      expect(res.statistics['sd_slope'], closeRel(sd[1], rel: 1e-4));
      expect(res.statistics['corr'], closeRel(sd[2], rel: 1e-3, abs: 1e-4));
    }
  }

  test('sleepstudy, intercept et pente aléatoires : déviance, effets fixes, ES, ddl et p de nlme, composantes de variance = lme4', () {
    check('sleep_slope', sleep, const ModelFormula('reaction_ms', [TermSpec('jours')]), 'sujet', 'jours');
  });

  test('sleepstudy, intercept aléatoire seul : idem, et CCI', () {
    check('sleep_int', sleep, const ModelFormula('reaction_ms', [TermSpec('jours')]), 'sujet', null);
  });

  test('essai simulé HbA1c (visites manquantes) : interaction temps × bras, terme inter-sujets (âge, bras) = lme4 / nlme', () {
    check('hba1c', hb, const ModelFormula('hba1c', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')], interactions: [('mois', 'bras')]), 'patient', 'mois');
    final r = longitudinalMixedModel(hb, const ModelFormula('hba1c', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')], interactions: [('mois', 'bras')]), subject: 'patient', slope: 'mois');
    expect(r.statistics['n'], asD(ref['hba1c_n']));
    expect(r.figures['trajectories'], isNotNull);
  });
}
