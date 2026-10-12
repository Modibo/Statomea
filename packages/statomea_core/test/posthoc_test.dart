import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('posthoc');
  Map<String, List<double>> groupsOf(Map m) => {for (final e in m.entries) e.key as String: [for (final v in e.value as List) asD(v)!]};
  final simCsv = parseCsv(File('test/reference/posthoc_sim.csv').readAsStringSync()).dataset;
  final sim = <String, List<double>>{};
  final g = simCsv.text('groupe'), y = simCsv.numeric('y');
  for (var i = 0; i < simCsv.rowCount; i++) {
    (sim[g[i]!] ??= []).add(y[i]!);
  }

  test('loi de l\'étendue studentisée : 96 valeurs de ptukey (R) à 1e-10', () {
    for (final r in ref['ptukey'] as List) {
      final m = r as Map;
      final p = 1 - ptukey(asD(m['q'])!, (m['k'] as num).toInt(), asD(m['df'])!);
      expect(p, closeRel(asD(m['p'])!, rel: 1e-9, abs: 1e-12), reason: '$m');
    }
  });

  test('quantiles qtukey : précis (référence uniroot serrée)', () {
    for (final r in ref['qtukey'] as List) {
      final m = r as Map;
      expect(qtukey(0.95, (m['k'] as num).toInt(), asD(m['df'])!), closeRel(asD(m['q95'])!, rel: 1e-10), reason: '$m');
    }
  });

  void checkTukey(Map<String, List<double>> groups, Map t) {
    final c = tukeyHsd(groups);
    final pairs = [for (final x in c) '${x.group2}-${x.group1}'];
    expect(pairs, [for (final p in t['pairs'] as List) p as String]);
    for (var i = 0; i < c.length; i++) {
      expect(c[i].diff, closeRel(asD((t['diff'] as List)[i])!, rel: 1e-12, abs: 1e-12));
      expect(c[i].p, closeRel(asD((t['p'] as List)[i])!, rel: 1e-9, abs: 1e-12));
      expect(c[i].lower, closeRel(asD((t['lwr'] as List)[i])!, rel: 1e-10));
      expect(c[i].upper, closeRel(asD((t['upr'] as List)[i])!, rel: 1e-10));
      // L'IC de TukeyHSD (qtukey de R, précision ~1e-9) reste proche à 1e-7.
      expect(c[i].lower, closeRel(asD((t['lwr_r'] as List)[i])!, rel: 1e-7));
    }
  }

  test('Tukey HSD contre stats::TukeyHSD (PlantGrowth, effectifs égaux)', () => checkTukey(groupsOf(ref['plant'] as Map), ref['tukey_plant'] as Map));
  test('Tukey HSD contre stats::TukeyHSD (jeu simulé, effectifs inégaux : Tukey-Kramer)', () => checkTukey(sim, ref['tukey_sim'] as Map));

  test('Games-Howell : recalcul R exact et rstatix::games_howell_test', () {
    final c = gamesHowell(sim);
    final gh = ref['gh'] as Map, rs = ref['gh_rstatix'] as Map;
    for (var i = 0; i < c.length; i++) {
      expect(c[i].diff, closeRel(asD((gh['diff'] as List)[i])!, rel: 1e-12));
      expect(c[i].p, closeRel(asD((gh['p'] as List)[i])!, rel: 1e-9, abs: 1e-12));
      expect(c[i].lower, closeRel(asD((gh['low'] as List)[i])!, rel: 1e-10));
      expect(c[i].upper, closeRel(asD((gh['high'] as List)[i])!, rel: 1e-10));
      // rstatix utilise qtukey() de R (précision ~1e-7 avec des ddl non entiers).
      expect(c[i].lower, closeRel(asD((rs['low'] as List)[i])!, rel: 1e-6));
      // rstatix arrondit p.adj (3 décimales, ou 3 chiffres significatifs sous 0,001) : comparaison à l'arrondi près.
      expect(c[i].p, closeTo(asD((rs['p_adj'] as List)[i])!, 5e-4));
    }
  });

  void checkDunn(Map<String, List<double>> groups, Map d) {
    final c = dunnHolm(groups);
    for (var i = 0; i < c.length; i++) {
      expect('${c[i].group1}/${c[i].group2}', '${(d['g1'] as List)[i]}/${(d['g2'] as List)[i]}');
      expect(c[i].statistic, closeRel(asD((d['z'] as List)[i])!, rel: 1e-10));
      expect(c[i].p, closeRel(asD((d['p'] as List)[i])!, rel: 1e-9, abs: 1e-14));
      expect(c[i].pAdjusted, closeRel(asD((d['p_adj'] as List)[i])!, rel: 1e-9, abs: 1e-14));
    }
  }

  test('Dunn + Holm contre rstatix::dunn_test (InsectSprays : 6 groupes, nombreux ex aequo)', () => checkDunn(groupsOf(ref['insects'] as Map), ref['dunn_insects'] as Map));
  test('Dunn + Holm contre rstatix::dunn_test (jeu simulé)', () => checkDunn(sim, ref['dunn_sim'] as Map));

  test('intégration : ANOVA → Tukey, ANOVA de Welch → Games-Howell, Kruskal-Wallis → Dunn-Holm', () {
    final plant = groupsOf(ref['plant'] as Map);
    final a = anovaOneWay(plant);
    expect(a.statistics['p'], closeRel(asD(ref['anova_plant_p'])!, rel: 1e-9));
    expect(a.tables.map((t) => t.title), contains('Comparaisons deux à deux (Tukey HSD)'));
    expect(a.statistics['posthoc_p_trt1_trt2'], closeRel(asD((ref['tukey_plant'] as Map)['p'][2])!, rel: 1e-9));
    expect(a.interpretation.whatItMeans, contains('trt2 − trt1'));
    expect(a.alerts.map((x) => x.code), contains('posthoc_exploratory'));
    final w = anovaOneWay(sim, welch: true);
    expect(w.tables.map((t) => t.title), contains('Comparaisons deux à deux (Games-Howell)'));
    expect(w.statistics['posthoc_p_A_C'], closeRel(asD((ref['gh'] as Map)['p'][1])!, rel: 1e-9));
    final k = kruskalWallis(groupsOf(ref['insects'] as Map));
    expect(k.tables.single.title, 'Comparaisons deux à deux (Dunn, Holm)');
    expect(k.tables.single.rows, hasLength(15));
    final cells = [for (final r in a.tables.last.rows) r.last];
    expect(cells.every((c) => !c.startsWith('=') && !c.startsWith('p')), isTrue, reason: '$cells');
    // Deux groupes : pas de comparaisons supplémentaires.
    expect(anovaOneWay({'A': plant['ctrl']!, 'B': plant['trt1']!}).tables, hasLength(1));
    expect(kruskalWallis({'A': plant['ctrl']!, 'B': plant['trt1']!}).tables, isEmpty);
  });

  test('Holm : propriétés (monotone, ≥ p brut, ≤ 1)', () {
    final adj = holm([0.01, 0.04, 0.03, 0.005, 0.5]);
    expect(adj, [0.04, 0.09, 0.09, 0.025, 0.5].map((v) => closeRel(v, rel: 1e-12)).toList());
  });
}
