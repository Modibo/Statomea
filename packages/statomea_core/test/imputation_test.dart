import 'dart:io';
import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

List<double> dl(Object? v) => [for (final x in v as List) asD(x)!];

void main() {
  final ref = loadRef('imputation');
  group('Règles de Rubin exactes sur les jeux complétés par mice', () {
    final long = parseCsv(File('test/reference/mi_mice_completed.csv').readAsStringSync()).dataset;
    final imps = [
      for (var k = 1; k <= 5; k++) subsetRows(long, (i) => long.cell(i, '.imp') == '$k', 'imputation mice $k')
    ];
    void check(AnalysisResult r, Map<String, dynamic> m) {
      final est = dl(m['est']), se = dl(m['se']), df = dl(m['df']), fmi = dl(m['fmi']), riv = dl(m['riv']), b = dl(m['b']), p = dl(m['p']);
      final cols = r.statistics.keys.where((k) => k.startsWith('beta_')).map((k) => k.substring(5)).toList();
      expect(cols.length, est.length);
      for (var j = 0; j < est.length; j++) {
        final c = cols[j];
        expect(r.statistics['beta_$c'], closeRel(est[j], rel: 1e-8, abs: 1e-12), reason: 'Q̄ $c');
        expect(r.statistics['se_$c'], closeRel(se[j], rel: 1e-7), reason: 'ES $c');
        expect(r.statistics['b_$c'], closeRel(b[j], rel: 1e-6, abs: 1e-14), reason: 'B $c');
        expect(r.statistics['riv_$c'], closeRel(riv[j], rel: 1e-6, abs: 1e-12), reason: 'riv $c');
        expect(r.statistics['df_$c'], closeRel(df[j], rel: 1e-6), reason: 'ddl $c');
        expect(r.statistics['fmi_$c'], closeRel(fmi[j], rel: 1e-6), reason: 'fmi $c');
      }
      // p de l'effet principal (première covariable).
      expect(r.estimates.first.pValue, closeRel(p[1], rel: 1e-5, abs: 1e-14));
    }
    test('logistique (8 prédicteurs)', () {
      const f = ModelFormula('evenement_5ans', [
        TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('tour_taille'), TermSpec('pas'),
        TermSpec('glycemie'), TermSpec('hdl'), TermSpec('tabac', categorical: true, reference: 'non'),
        TermSpec('atcd_familial', categorical: true, reference: 'non'),
      ], eventLevel: '1');
      check(pooledRegression(imps, f, PooledModel.logistic), (ref['rubin'] as Map)['logistic'] as Map<String, dynamic>);
    });
    test('linéaire', () {
      const f = ModelFormula('pas', [TermSpec('age'), TermSpec('sexe', categorical: true, reference: 'F'), TermSpec('glycemie'), TermSpec('hdl')]);
      check(pooledRegression(imps, f, PooledModel.linear), (ref['rubin'] as Map)['linear'] as Map<String, dynamic>);
    });
  });

  group('Imputation MICE de Statoméa contre mice (simulation MAR, vérité connue)', () {
    final s = ref['sim'] as Map<String, dynamic>;
    final ds = parseCsv(File('test/reference/mi_simulation.csv').readAsStringSync()).dataset;
    final imp = multipleImputation(ds, const MiceOptions(m: 40, maxit: 10, seed: 11));
    const f = ModelFormula('y', [TermSpec('x1'), TermSpec('x2', categorical: true, reference: 'non'), TermSpec('x3')]);
    final r = pooledRegression(imp.completed, f, PooledModel.linear, imputation: imp);
    final est = [for (final k in r.statistics.keys.where((k) => k.startsWith('beta_'))) r.statistics[k]!];
    final se = [for (final k in r.statistics.keys.where((k) => k.startsWith('se_'))) r.statistics[k]!];
    final truth = dl(s['truth']), cc = dl(s['cc_est']);
    test('valeurs observées inchangées ; seules les cellules manquantes sont imputées', () {
      for (final c in imp.completed.take(3)) {
        for (var i = 0; i < ds.rowCount; i++) {
          for (final v in ['y', 'x1', 'x2', 'x3']) {
            final o = ds.cell(i, v);
            if (!isMissingToken(o)) expect(parseNumber(c.cell(i, v)) ?? c.cell(i, v), parseNumber(o) ?? o);
            if (isMissingToken(o)) expect(isMissingToken(c.cell(i, v)), isFalse);
          }
        }
      }
      expect(imp.diagnostics.map((d) => d.variable), ['x1', 'x2']);
      expect(imp.diagnostics.first.missing, s['missing_x1']);
    });
    test('distribution des estimations et des ES comparable à mice (6 graines Statoméa, 12 graines mice)', () {
      final mMean = dl(s['seeds_est_mean']), mSd = dl(s['seeds_est_sd']), mSeMean = dl(s['seeds_se_mean']), mSeSd = dl(s['seeds_se_sd']);
      final runs = [
        for (var sd = 1; sd <= 6; sd++)
          pooledRegression(multipleImputation(ds, MiceOptions(m: 40, maxit: 10, seed: 100 + sd)).completed, f, PooledModel.linear)
      ];
      for (var j = 0; j < 4; j++) {
        final key = r.statistics.keys.where((k) => k.startsWith('beta_')).elementAt(j).substring(5);
        final e = [for (final x in runs) x.statistics['beta_$key']!];
        final se = [for (final x in runs) x.statistics['se_$key']!];
        final eMean = e.fold(0.0, (a, b) => a + b) / e.length, seMean = se.fold(0.0, (a, b) => a + b) / se.length;
        double sdOf(List<double> v, double m) => math.sqrt(v.fold(0.0, (a, b) => a + (b - m) * (b - m)) / (v.length - 1));
        // Tolérance : 3 erreurs de Monte-Carlo de la différence des moyennes, plus 1 % de l'ES (arrondis).
        final tolEst = 3 * math.sqrt(math.pow(sdOf(e, eMean), 2) / 6 + mSd[j] * mSd[j] / 12) + 0.01 * mSeMean[j];
        final tolSe = 3 * math.sqrt(math.pow(sdOf(se, seMean), 2) / 6 + mSeSd[j] * mSeSd[j] / 12) + 0.01 * mSeMean[j];
        expect((eMean - mMean[j]).abs(), lessThanOrEqualTo(tolEst), reason: 'β$j : Statoméa $eMean vs mice ${mMean[j]} (tol $tolEst)');
        expect((seMean - mSeMean[j]).abs(), lessThanOrEqualTo(tolSe), reason: 'ES$j : Statoméa $seMean vs mice ${mSeMean[j]} (tol $tolSe)');
      }
    });
    test('l\'imputation réduit le biais des cas complets (biais total)', () {
      double bias(List<double> e) => [for (var j = 0; j < 4; j++) (e[j] - truth[j]).abs()].fold(0.0, (a, b) => a + b);
      expect(bias(est), lessThan(bias(cc)));
      for (var j = 0; j < 4; j++) {
        expect((est[j] - truth[j]).abs(), lessThan(3 * se[j]), reason: 'β$j compatible avec la vérité');
      }
    });
    test('reproductible à graine égale', () {
      final again = multipleImputation(ds, const MiceOptions(m: 2, maxit: 3, seed: 5));
      final again2 = multipleImputation(ds, const MiceOptions(m: 2, maxit: 3, seed: 5));
      expect(again.completed[1].text('x1'), again2.completed[1].text('x1'));
    });
  });
}
