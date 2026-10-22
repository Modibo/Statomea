import 'dart:convert';
import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Project _imported(ExampleProject e) {
  final d = protocolFromText(e.text);
  final p = Project(id: e.id, title: d.title, createdAt: '2026-10-22')
    ..question = d.toQuestion()
    ..protocol = Map.of(d.fullSections)
    ..analysisPlan = d.sections['analysis'] ?? '';
  if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
  return p;
}

void main() {
  tearDown(() => setLang(Lang.fr));

  for (final e in exampleProjects) {
    for (final lang in Lang.values) {
      test('projet d\'exemple ${e.id} (${lang.name}) : protocole compris, erreurs cachées retrouvées puis corrigées', () {
        setLang(lang);
        final p = _imported(e);
        final r = reviewProject(p);
        for (final id in e.errors) {
          expect(r.findings.where((f) => f.id == id), isNotEmpty, reason: id);
        }
        expect(e.headings.length, e.text.split('\n').where((l) => e.headings.contains(l)).length, reason: 'chaque titre figure dans le texte');
        final fixable = [for (final f in r.problems) if (f.fix != null && e.errors.contains(f.id)) f.id];
        applyAllCorrections(p, date: '2026-10-22');
        final after = reviewProject(p).findings.map((f) => f.id).toSet();
        expect(after.intersection(fixable.toSet()), isEmpty);
        if (e.id == 'aghbs') {
          expect(p.question.design, StudyDesign.crossSectional);
          expect(p.question.objective, StudyObjective.explanatory);
          expect(p.question.text, contains(lang == Lang.fr ? 'résidence rurale' : 'rural residence'));
          // 1,96² × 0,08 × 0,92 / 0,025² = 452,4 → 453 ; majoration : 453 / (1 − 0,1) = 504 (et non 453 × 1,1 = 498).
          expect(r.findings.firstWhere((f) => f.id == 'loss_adjustment').problem, contains('504'));
          expect(r.findings.firstWhere((f) => f.id == 'precision_recomputed').level, ReviewLevel.ok);
          expect(p.inferred['plannedSampleSize'], '504');
        } else {
          expect(p.question.design, StudyDesign.rct);
          // power.prop.test(p1 = 0,60, p2 = 0,75, power = 0,8) : n = 151,87 → 152 ; avec 120 par bras : 0,701.
          expect(r.findings.firstWhere((f) => f.id == 'rct_sample_size_short').problem,
              allOf(contains(lang == Lang.fr ? 'n = 152 par bras' : 'n = 152 per arm'), contains(lang == Lang.fr ? 'puissance de 70 %' : 'only 70% power')));
          expect(p.inferred['plannedSampleSize'], '304');
        }
      });
    }
  }

  test('projets d\'exemple : les données simulées couvrent les variables du protocole', () {
    final aghbs = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync()).dataset!;
    expect(aghbs.names, containsAll(['age', 'residence', 'parite', 'aghbs', 'aghbe', 'enfant_suivi', 'enfant_infecte']));
    expect(aghbs.rowCount, greaterThanOrEqualTo(504));
    expect(aghbs.text('aghbs').where((v) => v == 'positif').length / aghbs.rowCount, closeTo(0.08, 0.01), reason: 'prévalence attendue : 8 %');
    // Essai : 240 enfants randomisés 1:1 (validation/r/58_demo_zinc.R).
    final ref = jsonDecode(File('test/reference/demo_zinc.json').readAsStringSync()) as Map<String, Object?>;
    final zinc = parseCsv(File('test/reference/zinc_essai_simule.csv').readAsStringSync()).dataset;
    expect(zinc.names, ['id', 'bras', 'age_mois', 'sexe', 'deshydratation', 'observance', 'guerison_j5', 'duree_h']);
    expect(zinc.rowCount, ref['n']);
    expect(zinc.text('bras').where((v) => v == 'zinc').length, 120);
    var cz = 0, cp = 0;
    for (var i = 0; i < zinc.rowCount; i++) {
      if (zinc.text('guerison_j5')[i] == 'oui') zinc.text('bras')[i] == 'zinc' ? cz++ : cp++;
    }
    expect([cz, cp], [ref['cured_zinc'], ref['cured_placebo']]);
    expect(zinc.text('observance').where((v) => v == 'incomplete'), isNotEmpty, reason: 'motif de l\'analyse en intention de traiter');
    // Effectif requis du calculateur = power.prop.test.
    final ss = sampleSizeTwoProportions(p1: 0.60, p2: 0.75);
    expect(ss.statistics['n_exact']!, closeTo(ref['n_required'] as num, 1e-6));
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
