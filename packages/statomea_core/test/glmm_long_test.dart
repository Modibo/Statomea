import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

import 'ref_util.dart';

void main() {
  final ref = loadRef('glmm_long');
  List<double> v(Object? l) => l is List ? [for (final x in l) asD(x)!] : [asD(l)!];
  final base = parseCsv(File('test/reference/hba1c_longitudinal_simule.csv').readAsStringSync()).dataset;
  final hb = Dataset([...base.names, 'controle'], [
    for (var i = 0; i < base.rowCount; i++) [for (final n in base.names) base.cell(i, n), double.parse(base.cell(i, 'hba1c')!) < 7.8 ? '1' : '0']
  ]);
  final ticks = parseCsv(File('test/reference/tiques_lagopede.csv').readAsStringSync()).dataset;
  const fb = ModelFormula('controle', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A'), TermSpec('age')], interactions: [('mois', 'bras')], eventLevel: '1');
  // Ordre des colonnes de R : (Intercept), anneea96, anneea97, altitude ; Statoméa : modalités triées, même ordre ici.
  const ft = ModelFormula('tiques', [TermSpec('annee', categorical: true, reference: 'a95'), TermSpec('altitude')]);

  void check(String key, Dataset ds, ModelFormula f, String subject, GlmmFamily fam) {
    final r = ref[key] as Map;
    final lap = glmmLongitudinal(ds, f, subject: subject, family: fam);
    final cols = (lap.inputs['model'] as Map)['columns'] as List;
    // 1) Laplace exacte (recalculée dans R) : β, σ, log-vraisemblance, ES.
    final l = r['laplace'] as Map;
    final b = v(l['beta']), se = v(l['se']);
    // Optimum sur une crête parfois très plate (constante et covariable non centrée) : écart toléré de 1e-3 erreur type,
    // et la log-vraisemblance atteinte doit égaler celle de R.
    for (var j = 0; j < b.length; j++) {
      expect(lap.statistics['beta_${cols[j]}'], closeTo(b[j], 1e-3 * se[j]), reason: '$key Laplace β ${cols[j]}');
      // Deux hessiennes numériques (gradient différencié dans R, dérivées secondes ici) : accord à 5e-3.
      expect(lap.statistics['se_${cols[j]}'], closeRel(se[j], rel: 5e-3), reason: '$key Laplace ES ${cols[j]}');
    }
    expect(lap.statistics['sigma'], closeRel(asD(l['sigma'])!, rel: 1e-4), reason: '$key Laplace σ');
    // La fonction de référence R (mode par optimize) est elle-même précise à ~1e-7 près.
    expect(lap.statistics['loglik'], closeTo(asD(l['loglik'])!, 2e-7), reason: '$key Laplace log-vraisemblance');
    // 2) Quadrature adaptative à 25 points → maximum de vraisemblance exact (intégration numérique dans R).
    final agq = glmmLongitudinal(ds, f, subject: subject, family: fam, nAgq: 25);
    final e = r['exact'] as Map;
    final be = v(e['beta']);
    for (var j = 0; j < be.length; j++) {
      expect(agq.statistics['beta_${cols[j]}'], closeRel(be[j], rel: 1e-3, abs: 1e-4), reason: '$key exact β ${cols[j]}');
    }
    expect(agq.statistics['sigma'], closeRel(asD(e['sigma'])!, rel: 1e-3), reason: '$key exact σ');
    // σ élevé (≈ 4 en binaire) : loi a posteriori asymétrique pour les sujets aux réponses identiques, quadrature à 25 points
    // à ~1e-5 près de l'intégrale exacte.
    expect(agq.statistics['loglik'], closeRel(asD(e['loglik'])!, rel: 2e-5), reason: '$key exact log-vraisemblance');
    // 3) glmer (PIRLS) : même modèle à 2 % près.
    final g1 = r['glmer1'] as Map, g10 = r['glmer10'] as Map;
    final q10 = glmmLongitudinal(ds, f, subject: subject, family: fam, nAgq: 10);
    for (var j = 0; j < b.length; j++) {
      expect(lap.statistics['beta_${cols[j]}'], closeRel(v(g1['beta'])[j], rel: 2e-2, abs: 2e-3), reason: '$key glmer nAGQ=1 β ${cols[j]}');
      expect(lap.statistics['se_${cols[j]}'], closeRel(v(g1['se'])[j], rel: 5e-2), reason: '$key glmer ES ${cols[j]}');
      expect(q10.statistics['beta_${cols[j]}'], closeRel(v(g10['beta'])[j], rel: 2e-2, abs: 2e-3));
    }
  }

  test('logistique (contrôle glycémique) : Laplace exacte, vraisemblance exacte (AGQ 25), glmer', () {
    check('bin', hb, fb, 'patient', GlmmFamily.binomial);
  });

  test('Poisson (grouseticks, couvées) : idem', () {
    check('ticks', ticks, ft, 'couvee', GlmmFamily.poisson);
  });

  test('Poisson sans variance entre sujets (hypoglycémies) : σ négligeable, test de σ = 0 non significatif, β = glmer (frontière)', () {
    final r = glmmLongitudinal(hb, const ModelFormula('hypoglycemies', [TermSpec('mois'), TermSpec('bras', categorical: true, reference: 'A')]), subject: 'patient', family: GlmmFamily.poisson);
    expect(r.statistics['sigma']!, lessThan(0.1));
    expect(r.statistics['lrt_sigma_p']!, greaterThan(0.3));
    final b = v((ref['pois_singular'] as Map)['beta']);
    expect(r.statistics['beta_mois'], closeRel(b[1], rel: 1e-3));
  });

  test('nœuds de Gauss-Hermite : ∫e^{−x²}x² = √π/2', () {
    final g = gaussHermite(10);
    var s = 0.0;
    for (var k = 0; k < 10; k++) {
      s += g.weights[k] * g.nodes[k] * g.nodes[k];
    }
    expect(s, closeTo(1.7724538509055159 / 2, 1e-12));
  });
}
