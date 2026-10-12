import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('parente');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/parente.bed').readAsBytesSync(), File('$dir/parente.bim').readAsStringSync(), File('$dir/parente.fam').readAsStringSync());
  final kin = genotypeKinship(g);

  test('φ KING-robust et IBS0 de toutes les paires = formule R et SNPRelate (écart R–SNPRelate ≈ 1e-16)', () {
    expect(asD(ref['snprelate_max_diff_kinship']), lessThan(1e-12));
    final phi = v(ref['phi_upper']), ibs0 = v(ref['ibs0_upper']);
    expect(kin.phiUpper.length, phi.length);
    // R : upper.tri parcourt la matrice par colonnes (j croissant, puis i < j).
    var k = 0;
    for (var j = 1; j < kin.n; j++) {
      for (var i = 0; i < j; i++, k++) {
        expect(kin.phi(i, j), closeRel(phi[k], rel: 1e-12, abs: 1e-14), reason: 'paire ($i, $j)');
        expect(kin.ibs0Upper[i * kin.n - i * (i + 1) ~/ 2 + (j - i - 1)], closeRel(ibs0[k], rel: 1e-12, abs: 1e-15), reason: 'paire ($i, $j)');
      }
    }
  });

  test('paires apparentées et degrés : 4 doublons, 25 au 1er degré, 1 au 2e (demi-frères), 1 au 3e (cousins)', () {
    final p = ref['pairs'] as Map;
    final i = [for (final x in p['i'] as List) (x as num).toInt() - 1], j = [for (final x in p['j'] as List) (x as num).toInt() - 1];
    final rel = [...kin.related]..sort((a, b) => a.i != b.i ? a.i.compareTo(b.i) : a.j.compareTo(b.j));
    expect([for (final r in rel) (r.i, r.j)], [for (var k = 0; k < i.length; k++) (i[k], j[k])]);
    expect([for (final r in rel) r.degree], [for (final d in p['degree'] as List) (d as num).toInt()]);
    expect([kin.result.statistics['pairs_duplicate'], kin.result.statistics['pairs_degree1'], kin.result.statistics['pairs_degree2'], kin.result.statistics['pairs_degree3']],
        [4, 25, 1, 1]);
    // Parent–enfant : IBS0 ≈ 0 ; frères/sœurs : IBS0 > 0.
    final e1 = rel.firstWhere((r) => g.samples[r.j] == 'E1');
    expect(kinshipDegreeLabel(e1.degree, e1.ibs0), contains('parent'));
    final fr = rel.firstWhere((r) => g.samples[r.i] == 'FR1_1' && g.samples[r.j] == 'FR1_2');
    expect(kinshipDegreeLabel(fr.degree, fr.ibs0), contains('frères'));
  });

  test('ensemble non apparenté : mêmes sujets écartés que la règle gloutonne de R', () {
    expect(kin.removed, [for (final x in ref['removed'] as List) (x as num).toInt() - 1]);
    final kept = g.subset(sampleIdx: [for (var i = 0; i < g.sampleCount; i++) if (!kin.removed.contains(i)) i]);
    expect(genotypeKinship(kept).related.where((p) => p.phi > 0.0884), isEmpty);
  });

  test('peu de variants : densité insuffisante signalée', () {
    final small = g.subset(variantIdx: [for (var j = 0; j < 3000; j++) j]);
    expect(genotypeKinship(small).result.checks.firstWhere((c) => c.id == 'density').status, CheckStatus.warning);
  });
}
