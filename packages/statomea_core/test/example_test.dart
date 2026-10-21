import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Project _imported() {
  final d = protocolFromText(exampleProtocolText);
  final p = Project(id: 'ex', title: d.title, createdAt: '2026-10-21')
    ..question = d.toQuestion()
    ..protocol = Map.of(d.fullSections)
    ..analysisPlan = d.sections['analysis'] ?? '';
  if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
  return p;
}

void main() {
  tearDown(() => setLang(Lang.fr));

  for (final lang in Lang.values) {
    test('projet d\'exemple (${lang.name}) : protocole compris, six erreurs cachées retrouvées, puis corrigées', () {
      setLang(lang);
      final p = _imported();
      expect(p.question.design, StudyDesign.crossSectional);
      expect(p.question.objective, StudyObjective.explanatory);
      expect(p.question.text, contains(lang == Lang.fr ? 'résidence rurale' : 'rural residence'));
      expect(p.inferred['plannedSampleSize'], '498');
      final r = reviewProject(p);
      for (final id in exampleProtocolErrors) {
        expect(r.findings.where((f) => f.id == id), isNotEmpty, reason: id);
      }
      // 1,96² × 0,08 × 0,92 / 0,025² = 452,4 → 453 ; majoration : 453 / (1 − 0,1) = 504 (et non 453 × 1,1 = 498).
      expect(r.findings.firstWhere((f) => f.id == 'loss_adjustment').problem, contains('504'));
      expect(r.findings.firstWhere((f) => f.id == 'precision_recomputed').level, ReviewLevel.ok);
      final done = applyAllCorrections(p, date: '2026-10-21');
      expect(done.map((c) => c.id), containsAll(['loss_adjustment', 'no_adjustment', 'ks_normality', 'missing_data']));
      expect(p.inferred['plannedSampleSize'], '504');
      expect(reviewProject(p).findings.where((f) => const ['loss_adjustment', 'no_adjustment', 'ks_normality', 'missing_data'].contains(f.id)), isEmpty);
    });
  }

  test('projet d\'exemple : les données simulées couvrent les variables du protocole et atteignent l\'effectif corrigé', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final ds = p.dataset!;
    expect(ds.names, containsAll(['age', 'residence', 'parite', 'aghbs', 'aghbe', 'enfant_suivi', 'enfant_infecte']));
    expect(ds.rowCount, greaterThanOrEqualTo(504));
    final prev = ds.text('aghbs').where((v) => v == 'positif').length / ds.rowCount;
    expect(prev, closeTo(0.08, 0.01), reason: 'prévalence attendue du protocole : 8 %');
  });

  test('objectifs spécifiques : ils complètent l\'objectif principal court sans le remplacer', () {
    final d = protocolFromText('Titre du projet\nÉtude du paludisme\nObjectif principal\nDécrire le paludisme grave chez l\'enfant.\n'
        'Objectifs spécifiques\n1. Estimer la létalité ;\n2. Décrire les signes de gravité.\n');
    expect(d.question, 'Décrire le paludisme grave chez l\'enfant.');
    expect(d.sections['objective'], allOf(startsWith('Décrire le paludisme'), contains('Estimer la létalité')));
    final d2 = protocolFromText('Titre du projet\nÉtude du paludisme\nObjectifs\n1. Décrire le paludisme grave chez l\'enfant ;\n2. Estimer la létalité.\n');
    expect(d2.question, startsWith('Décrire le paludisme grave'));
  });
}
