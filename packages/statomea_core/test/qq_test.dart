import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('qq');
  final acp = loadRef('acp');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];

  test('QQ : quantiles attendus = ppoints(n), bande = qbeta(0,025 ; 0,975 ; k, n − k + 1)', () {
    final q = qqPoints(v(acp['p_unadj']));
    final e = v(ref['expected']), lo = v(ref['lower']), hi = v(ref['upper']);
    expect(q.observed.length, ref['n']);
    for (var k = 0; k < e.length; k++) {
      expect(q.expected[k], closeRel(e[k], rel: 1e-14), reason: 'attendu $k');
      expect(q.lower[k], closeRel(lo[k], rel: 1e-8), reason: 'bande basse $k');
      expect(q.upper[k], closeRel(hi[k], rel: 1e-8), reason: 'bande haute $k');
    }
    expect(qqPoints(v(ref['small_p'])).expected, [for (final x in v(ref['small_expected'])) closeRel(x, rel: 1e-14)]);
  });

  test('balayage : figures QQ et Manhattan (positions du .bim), λ reporté, sous-échantillonnage au-delà de 4 000 points', () {
    const dir = 'test/reference/genotypes';
    final g = parsePlinkBed(File('$dir/strat.bed').readAsBytesSync(), File('$dir/strat.bim').readAsStringSync(), File('$dir/strat.fam').readAsStringSync());
    final snps = [for (final x in g.variants) x.id];
    final r = snpScan(genotypeDataset(g), snps, 'statut', 'cas', positions: {for (final x in g.variants) x.id: (x.chrom, x.pos)});
    final qq = r.figures['qq'] as Map, mh = r.figures['manhattan'] as Map;
    expect((qq['observed'] as List).length, 1000);
    expect(qq['lambda'], r.statistics['lambda_gc']);
    expect((mh['chrom'] as List).toSet(), {'1', '2', '3', '4'});
    expect(mh['genomeWide'], 5e-8);
    final svgM = manhattanSvg(mh), svgQ = qqSvg(qq);
    expect(svgM, contains('<svg'));
    expect(svgQ, contains('λ'));
    // Sans positions : pas de Manhattan.
    expect(snpScan(genotypeDataset(g), snps.take(30).toList(), 'statut', 'cas').figures.containsKey('manhattan'), isFalse);
  });
}
