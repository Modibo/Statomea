import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('ordinal');
  List<double> v(Object? l) => [for (final x in l as List) asD(x)!];
  final ds = parseCsv(File('test/reference/satisfaction_logement.csv').readAsStringSync()).dataset;
  const f = ModelFormula('satisfaction', [
    TermSpec('influence', categorical: true, reference: 'faible'), TermSpec('logement', categorical: true, reference: 'tour'),
    TermSpec('contact', categorical: true, reference: 'faible'),
  ]);
  const order = ['1_faible', '2_moyenne', '3_elevee'];
  // Ordre des coefficients de R (niveaux de facteur) ; Statoméa trie les modalités : appariement par nom.
  const rNames = ['influence = moyenne (vs faible)', 'influence = forte (vs faible)', 'logement = appartement (vs tour)', 'logement = atrium (vs tour)',
    'logement = maison_rangee (vs tour)', 'contact = fort (vs faible)'];

  test('cotes proportionnelles : β, seuils ζ, ES et log-vraisemblance = MASS::polr', () {
    final r = ordinalRegression(ds, f, levels: order);
    final po = ref['polr'] as Map;
    final b = v(po['beta']), z = v(po['zeta']), se = v(po['se']);
    for (var j = 0; j < b.length; j++) {
      expect(r.statistics['beta_${rNames[j]}'], closeRel(b[j], rel: 1e-7), reason: 'β ${rNames[j]}');
      expect(r.statistics['se_${rNames[j]}'], closeRel(se[j], rel: 1e-5), reason: 'ES ${rNames[j]}');
    }
    for (var j = 0; j < 2; j++) {
      expect(r.statistics['zeta_$j'], closeRel(z[j], rel: 1e-7));
      expect(r.statistics['se_zeta_$j'], closeRel(se[b.length + j], rel: 1e-5));
    }
    expect(r.statistics['loglik'], closeRel(asD(po['loglik'])!, rel: 1e-11));
    expect(r.statistics['n'], asD(ref['n']));
  });

  test('multinomiale : coefficients, ES, log-vraisemblance = nnet::multinom', () {
    final r = multinomialRegression(ds, f, levels: order);
    final mn = ref['multinom'] as Map;
    final c = v(mn['coef']), se = v(mn['se']);
    final cols = ['Constante', ...rNames];
    expect(((r.inputs['model'] as Map)['columns'] as List).first, 'Constante');
    var i = 0;
    for (final lvl in order.sublist(1)) {
      for (final col in cols) {
        expect(r.statistics['beta_${lvl}_$col'], closeRel(c[i], rel: 1e-6, abs: 1e-9), reason: '$lvl $col');
        expect(r.statistics['se_${lvl}_$col'], closeRel(se[i], rel: 1e-5), reason: 'ES $lvl $col');
        i++;
      }
    }
    expect(r.statistics['loglik'], closeRel(asD(mn['loglik'])!, rel: 1e-10));
  });

  test('test des cotes proportionnelles (RV polr contre multinom) et erreurs', () {
    final r = ordinalRegression(ds, f, levels: order);
    final lr = 2 * (asD((ref['multinom'] as Map)['loglik'])! - asD((ref['polr'] as Map)['loglik'])!);
    expect(r.statistics['po_lr'], closeRel(lr, rel: 1e-7));
    final two = Dataset(['y', 'x'], [['a', '1'], ['b', '0'], ['a', '0']]);
    expect(() => ordinalRegression(two, const ModelFormula('y', [TermSpec('x')])), throwsA(isA<StatInputError>()));
  });
}
