import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('pathogenes');
  final ds = parseCsv(File('test/reference/pathogenes_simule.csv').readAsStringSync()).dataset;
  final muts = ['rpoB_S450L', 'rpoB_H445Y', 'rpoB_D435V'];
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  test('concordance mutations ↔ rifampicine : effectifs, Se, Sp, VPP, VPN (Wilson), kappa et son ES', () {
    final r = mutationPhenotypeConcordance(ds, 'rifampicine', 'R', muts);
    final names = {'S450L': 'rpoB_S450L', 'H445Y': 'rpoB_H445Y', 'D435V': 'rpoB_D435V', 'any': 'Au moins une mutation listée'};
    for (final e in names.entries) {
      final x = ref[e.key] as Map;
      final c = v(x['counts']);
      final s = r.statistics;
      expect([s['tp_${e.value}'], s['fp_${e.value}'], s['fn_${e.value}'], s['tn_${e.value}']], c, reason: e.key);
      expect(s['kappa_${e.value}'], closeRel(asD(x['kappa'])!, rel: 1e-12), reason: e.key);
      expect(s['kappa_se_${e.value}'], closeRel(asD(x['kappa_se'])!, rel: 1e-10), reason: e.key);
    }
    final any = ref['any'] as Map;
    final se = v(any['se']), sp = v(any['sp']), k = v(any['kappa_ci']);
    expect([r.estimates[0].value, r.estimates[0].lower, r.estimates[0].upper], [for (final x in se) closeRel(x, rel: 1e-9)]);
    expect([r.estimates[1].value, r.estimates[1].lower, r.estimates[1].upper], [for (final x in sp) closeRel(x, rel: 1e-9)]);
    expect([r.estimates[2].lower, r.estimates[2].upper], [for (final x in k) closeRel(x, rel: 1e-10)]);
    expect(r.alerts.map((a) => a.code), contains('missing_genotypes'));
  });

  test('diversité des lignées : Hunter-Gaston, IC de Grundmann, Shannon', () {
    final r = typeDiversity(ds, 'lignee');
    expect(r.statistics['hunter_gaston'], closeRel(asD(ref['hg'])!, rel: 1e-12));
    expect([r.statistics['hg_lower'], r.statistics['hg_upper']], [for (final x in v(ref['hg_ci'])) closeRel(x, rel: 1e-12)]);
    expect(r.statistics['shannon'], closeRel(asD(ref['shannon'])!, rel: 1e-12));
    expect(r.statistics['types'], 6);
    expect(r.alerts.map((a) => a.code), contains('discrimination'));
  });
}
