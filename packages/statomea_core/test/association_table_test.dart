import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('Tableau 2 : OR bruts et ajustés identiques à glm de R (aghbs ~ résidence + âge + parité)', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final f = ModelFormula('aghbs', const [TermSpec('residence', categorical: true, reference: 'urbain'), TermSpec('age'), TermSpec('parite')], eventLevel: 'positif');
    final r = associationTable(p.dataset!, f, model: 'logistic', design: StudyDesign.crossSectional);
    final t = r.tables.single;
    expect(t.header, ['Variable', 'OR brut (IC 95 %)', 'p', 'OR ajusté (IC 95 %)', 'p']);
    expect(t.rows.length, 3);
    // R 4.2.3, glm(binomial), IC de Wald (confint.default).
    final ref = {
      'residence': (1.56666132, 0.89194183, 2.75178000, 0.11826995, 1.56271778, 0.88919125, 2.74641351, 0.12072399),
      'age': (1.01176993, 0.97696901, 1.04781051, 0.512322, 1.01173040, 0.97680575, 1.04790373, 0.51526732),
      'parite': (0.96370018, 0.78882511, 1.17734340, 0.71740995, 0.97079992, 0.79406868, 1.18686521, 0.77254852),
    };
    final adj = {for (final e in r.estimates) e.label: e};
    for (final e in ref.entries) {
      final a = adj.entries.firstWhere((x) => x.key.contains(e.key)).value;
      final (_, _, _, _, or, lo, hi, pv) = e.value;
      expect(a.value, closeTo(or, 1e-6), reason: e.key);
      expect(a.lower, closeTo(lo, 1e-6));
      expect(a.upper, closeTo(hi, 1e-6));
      expect(a.pValue, closeTo(pv, 1e-6));
    }
    final rowRes = t.rows.firstWhere((x) => x.first.contains('residence'));
    expect(rowRes[1], '1,57 (0,892 – 2,75)', reason: 'brut R : 1,567 [0,892 ; 2,752]');
    expect(rowRes[2], '0,12');
    expect(rowRes[3], '1,56 (0,889 – 2,75)');
    expect(r.alerts.map((a) => a.message), contains(startsWith('Brut : chaque variable seule avec « aghbs » (n = 640)')));
    expect(r.interpretation.notJustified, contains('Tableau 2'));
  });

  test('Poisson robuste (RP en transversal) et linéaire (β) ; tableau repris dans l\'article', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final f = ModelFormula('aghbs', const [TermSpec('residence', categorical: true, reference: 'urbain'), TermSpec('age')], eventLevel: 'positif');
    final rp = associationTable(p.dataset!, f, model: 'poisson', design: StudyDesign.crossSectional);
    expect(rp.tables.single.header[1], 'RP brut (IC 95 %)');
    final lin = associationTable(p.dataset!, const ModelFormula('parite', [TermSpec('age'), TermSpec('residence', categorical: true, reference: 'urbain')]), model: 'linear');
    expect(lin.tables.single.header[3], 'β (différence) ajusté (IC 95 %)');
    expect(lin.tables.single.rows.length, 2, reason: 'sans la constante');
    p.journal.add(JournalEntry.fromResult(rp, id: 't2', timestamp: '2026-10-19', data: p.dataset));
    final res = articleOutline(p).firstWhere((s) => s.title == 'Résultats principaux');
    expect(res.tables.first.title, startsWith('Tableau 2. Facteurs associés à « aghbs »'));
    expect(res.tables.last.title, 'Tableau 3. Résultats principaux');
  });
}
