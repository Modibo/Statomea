import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('article prérédigé : IMRaD, Tableau 1 des données, résultats du journal avec IC, limites selon le plan', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final a = articleOutline(p);
    expect(a.map((s) => s.title).toList(), [
      'Résumé', 'Introduction', 'Méthodes', 'Schéma et cadre de l\'étude', 'Participants', 'Variables et mesures', 'Taille de l\'échantillon',
      'Analyse statistique', 'Considérations éthiques', 'Résultats', 'Participants', 'Résultats principaux', 'Discussion', 'Conclusion', 'Références', 'Liste de contrôle',
    ]);
    ArticleSection s(String t, {int i = 0}) => a.where((x) => x.title == t).elementAt(i);
    expect(s('Schéma et cadre de l\'étude').paragraphs.first, 'Il s\'agit d\'une étude transversale.');
    expect(s('Schéma et cadre de l\'étude').paragraphs.last, contains('STROBE'));
    final t1 = s('Participants', i: 1).tables.single;
    expect(t1.title, 'Tableau 1. Caractéristiques des participants');
    expect(t1.header[1], startsWith('Ensemble (N = ${p.dataset!.rowCount - p.dataset!.excludedRows.length})'));
    final res = s('Résultats principaux');
    final t2 = res.tables.single;
    final expected = p.journal.where((e) => !e.methodId.startsWith('describe') && !e.methodId.startsWith('sample_size') && !e.methodId.startsWith('power')).length;
    expect(t2.rows.length, expected);
    expect(t2.header, ['Analyse', 'Estimation', 'IC à 95 %', 'p']);
    expect(res.paragraphs.first, contains('(IC 95 % :'));
    final disc = s('Discussion').paragraphs.last;
    expect(disc, contains('chronologie'), reason: 'plan transversal');
    expect(disc, contains('confusion résiduelle'));
    expect(s('Conclusion').paragraphs.single, contains('association'));
    expect(s('Résumé').paragraphs[1], startsWith('Objectif : ${p.question.text}'));
    expect(s('Analyse statistique').paragraphs.last, contains('validée contre R'));
    expect(a.expand((x) => x.paragraphs).where((l) => l.contains('[À compléter')).length, greaterThan(5));
  });

  test('grille de publication selon le plan ; projet vide : squelette complet à compléter', () {
    expect(reportingGuideline(const ResearchQuestion(design: StudyDesign.rct)), 'CONSORT 2010');
    expect(reportingGuideline(const ResearchQuestion(objective: StudyObjective.predictive, design: StudyDesign.cohort)), 'TRIPOD+AI');
    expect(reportingGuideline(const ResearchQuestion(design: StudyDesign.diagnosticAccuracy)), 'STARD 2015');
    final a = articleOutline(Project(id: 'e', title: 'Vide', createdAt: ''));
    expect(a.length, 16);
    expect(a.firstWhere((x) => x.title == 'Résultats principaux').paragraphs.single, contains('[À compléter'));
    expect(a.every((x) => x.tables.isEmpty), isTrue);
  });
}
