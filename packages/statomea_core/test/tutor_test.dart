import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('questions tirées du projet : type du critère, mesure d\'effet, méthode, conditions, portée causale', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final qs = tutorQuestions(p);
    expect(qs.map((q) => q.step), Step.values);
    expect(qs.where((q) => q.personalised).map((q) => q.step), [Step.question, Step.studyPlan, Step.methodChoice, Step.diagnostics, Step.interpretation]);
    String right(Step s) => qs.firstWhere((q) => q.step == s).options[qs.firstWhere((q) => q.step == s).correct];
    expect(right(Step.question), 'binaire (oui / non)');
    expect(right(Step.studyPlan), 'Rapport de prévalences');
    expect(right(Step.interpretation), startsWith('Non : on conclut à une association'));
    expect(qs.map((q) => q.correct).toSet().length, greaterThan(1), reason: 'la bonne réponse n\'est pas toujours à la même place');
    for (final q in qs) {
      expect(q.options.length, 4, reason: q.step.name);
      expect(q.options.toSet().length, 4, reason: 'options distinctes (${q.step.name})');
    }
    const text = 'Essai randomisé : la vitamine D réduit-elle la pression artérielle systolique à 6 mois chez les adultes hypertendus ?';
    final rct = Project(id: 'r', title: 'T', createdAt: '')..question = applyInference(const ResearchQuestion(text: text), inferQuestion(text)).$1;
    final qr = tutorQuestions(rct);
    final plan = qr.firstWhere((q) => q.step == Step.studyPlan);
    expect(plan.options[plan.correct], 'Différence de moyennes', reason: 'critère quantitatif');
    final diag = qr.firstWhere((q) => q.step == Step.diagnostics);
    expect(diag.options.where((o) => o.toLowerCase().contains('indépend')).length, 1, reason: 'pas de distracteur synonyme de la bonne réponse');
    final meth = qr.firstWhere((q) => q.step == Step.methodChoice);
    expect(meth.options.any((o) => o.contains('qPCR') || o.contains('variant')), isFalse, reason: 'pas de méthode de génétique comme distracteur');
  });

  test('progression : essais, réussite datée, enregistrement ; projet vide : questions génériques', () {
    final p = Project(id: 'v', title: 'Vide', createdAt: '');
    final qs = tutorQuestions(p);
    expect(qs.every((q) => !q.personalised), isTrue);
    final q = qs[2];
    expect(answerTutor(p, q, (q.correct + 1) % 4, date: '2026-10-20'), isFalse);
    expect(answerTutor(p, q, q.correct, date: '2026-10-20'), isTrue);
    final pr = tutorProgress(p)[2];
    expect((pr.attempts, pr.solved, pr.date), (2, true, '2026-10-20'));
    expect(tutorProgress(p).where((x) => x.solved).length, 1);
    expect(Project.decode(p.encode()).tutor, p.tutor);
  });
}
