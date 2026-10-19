import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

const report = '''Reviewer 1:
1. The sample size calculation is not justified. Please explain how the
   number of participants was chosen.
2. The authors should adjust for potential confounders such as age.
3. Please report confidence intervals for all estimates.

Reviewer 2
- How were missing data handled?
- The conclusion implies causality; please rephrase.
- Some typos remain in the English text.
- Why did you choose this hospital?
''';

void main() {
  test('commentaires découpés par relecteur ; thèmes ; réponses fondées sur le projet', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    p.inferred['plannedSampleSize'] = '600';
    final items = analyseReviewerComments(p, report);
    expect(items.length, 7);
    expect(items.map((i) => i.reviewer).toSet(), {'Reviewer 1', 'Reviewer 2'});
    expect(items.first.comment, 'The sample size calculation is not justified. Please explain how the number of participants was chosen.');
    expect(items.map((i) => i.topic).toList(), ['sample', 'confounding', 'ci', 'missing', 'causal', 'language', '']);
    expect(items[0].response, contains('L\'effectif prévu était de 600 sujets.'));
    expect(items[0].response, contains('640 participants ont été analysés (107 % de l\'effectif prévu)'));
    expect(items[2].response, contains('(IC 95 % : 0,0652 – 0,108)'), reason: 'estimation du journal avec son IC');
    expect(items[3].response, contains('aghbe : 586 (91,6 %)'));
    expect(items[4].response, contains('termes d\'association'));
    expect(items[4].response, contains('étude transversale'));
    expect(items[6].response, contains('[À compléter : réponse]'));
    expect(items.every((i) => i.change.isNotEmpty), isTrue);
    p.reviewerItems.addAll(items);
    final back = Project.decode(p.encode());
    expect(back.reviewerItems.map((i) => i.response), items.map((i) => i.response));
  });

  test('paragraphes sans numérotation ; Tableau 2 cité pour la confusion ; flux pour les exclusions', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final t2 = associationTable(p.dataset!, const ModelFormula('aghbs', [TermSpec('residence', categorical: true, reference: 'urbain'), TermSpec('age')], eventLevel: 'positif'));
    p.journal.add(JournalEntry.fromResult(t2, id: 't2', timestamp: '', data: p.dataset));
    p.flow.addAll({'assessed': '700', 'excluded_reasons': 'refus : 60', 'included': '640', 'analysed': '640'});
    final items = analyseReviewerComments(p, 'Il faudrait ajuster sur les facteurs de confusion.\n\nCombien de femmes ont été exclues et pourquoi ?');
    expect(items.length, 2);
    expect(items[0].response, contains('ajustées sur les variables suivantes : residence, age'));
    expect(items[1].topic, 'flow');
    expect(items[1].response, contains('Sur 700 personnes évaluées'));
  });
}
