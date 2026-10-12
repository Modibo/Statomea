import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('ldsc');
  const dir = 'test/reference/genotypes';
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final g = parsePlinkBed(File('$dir/ldsc.bed').readAsBytesSync(), File('$dir/ldsc.bim').readAsStringSync(), File('$dir/ldsc.fam').readAsStringSync());
  final n = asD(ref['n'])!.round(), m = asD(ref['m'])!.round();
  final ell = ldScores(g);

  test('scores LD dans l\'échantillon (r² corrigé, fenêtre 1 Mb) = R', () {
    final r = v(ref['ell']);
    expect(ell.length, m);
    for (var j = 0; j < m; j++) {
      expect(ell[j], closeRel(r[j], rel: 1e-10), reason: g.variants[j].id);
    }
  });

  for (final sc in ['A', 'B']) {
    test('régression scénario $sc : intercept, h², ES jackknife, ratio = R', () {
      final t = ref[sc] as Map;
      final f = ldscRegression(v(ref['chi2_$sc']), ell, n: n, m: m);
      expect(f.intercept, closeRel(asD(t['intercept'])!, rel: 1e-10));
      expect(f.h2, closeRel(asD(t['h2'])!, rel: 1e-9));
      expect(f.seIntercept, closeRel(asD(t['se_intercept'])!, rel: 1e-9));
      expect(f.seH2, closeRel(asD(t['se_h2'])!, rel: 1e-9));
      expect(f.meanChi2, closeRel(asD(t['mean_chi2'])!, rel: 1e-12));
      expect(f.ratio, closeRel(asD(t['ratio'])!, rel: 1e-9));
      expect(f.used, asD(t['J'])!.round());
      expect(f.blocks, asD(t['B'])!.round());
      final ok = f.result.checks.firstWhere((c) => c.id == 'intercept').status == CheckStatus.ok;
      expect(ok, sc == 'A', reason: 'A sans confusion, B stratifié');
    });
  }

  test('chaîne de l\'exemple : balayage logistique (χ² de Wald, convergence IRLS ~1e-7) → scores LD → régression = R', () {
    final t = ref['app'] as Map;
    final ga = parsePlinkBed(File('$dir/ldsc_app.bed').readAsBytesSync(), File('$dir/ldsc_app.bim').readAsStringSync(), File('$dir/ldsc_app.fam').readAsStringSync());
    final ds = genotypeDataset(ga);
    final names = ds.names.sublist(ds.names.length - ga.variantCount);
    final chi2 = <double>[];
    snpScan(ds, names, 'statut', 'cas', chi2Out: chi2);
    final wald = v(t['chi2']);
    for (var j = 0; j < wald.length; j++) {
      expect(chi2[j], closeRel(wald[j], rel: 1e-6), reason: names[j]);
    }
    final ea = ldScores(ga), er = v(t['ell']);
    for (var j = 0; j < er.length; j++) {
      expect(ea[j], closeRel(er[j], rel: 1e-10));
    }
    final f = ldscFromScan(ga, chi2, n: ga.sampleCount);
    expect(f.intercept, closeRel(asD(t['intercept'])!, rel: 1e-6));
    expect(f.h2, closeRel(asD(t['h2'])!, rel: 1e-5));
    expect(f.seIntercept, closeRel(asD(t['se_intercept'])!, rel: 1e-5));
    expect(f.result.checks.firstWhere((c) => c.id == 'intercept').status, CheckStatus.warning);
  });

  test('p → χ² précis pour les petites p ; trop peu de variants refusé', () {
    expect(chiSquareFromP(0.05), closeRel(3.841458820694124, rel: 1e-12));
    expect(chiSquareFromP(1e-30), closeRel(132.799892705014, rel: 1e-10));
    expect(() => ldscRegression(List.filled(100, 1.0), List.filled(100, 1.5), n: 100, m: 100), throwsA(isA<StatInputError>()));
  });
}
