import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('sauvegarde de tous les projets puis restauration par l\'import (intégrité vérifiée)', () {
    final a = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final b = Project(id: 'b', title: 'Projet B', createdAt: '2026-10-20')..question = const ResearchQuestion(text: 'Question B ?');
    final text = backupAllProjects([a, b], date: '2026-10-20');
    final items = projectsInBackup(text);
    expect(items.length, 2);
    final back = [for (final t in items) importProject(t, existingIds: const {}, newId: () => 'x').project];
    expect(back.map((p) => p.title), [a.title, 'Projet B']);
    expect(back.first.dataset!.rowCount, a.dataset!.rowCount);
    expect(back.first.journal.length, a.journal.length);
    final notes = importProject(items.first, existingIds: const {}, newId: () => 'x').notes;
    expect(notes.where((n) => n.severity == Severity.serious), isEmpty, reason: 'empreinte intacte');
    expect(() => projectsInBackup('{"format": "statomea-project"}'), throwsA(isA<StatInputError>()));
    expect(() => projectsInBackup('pas du json'), throwsA(isA<StatInputError>()));
  });

  test('partage sans les données individuelles : question, plans, journal gardés ; fichier de données retiré', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final shared = importProject(shareableProject(p, includeData: false), existingIds: const {}, newId: () => 'x').project;
    expect(shared.dataset, isNull);
    expect(shared.question.text, p.question.text);
    expect(shared.analysisPlan, p.analysisPlan);
    expect(shared.journal.length, p.journal.length);
    expect(shareableProject(p, includeData: false).contains('F001'), isFalse, reason: 'aucun identifiant de participant');
    expect(importProject(shareableProject(p), existingIds: const {}, newId: () => 'x').project.dataset, isNotNull);
  });

  test('synthèse pour l\'encadrant : étapes, relecture, tuteur, analyses, effectif, statut, points d\'attention', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    p.inferred['plannedSampleSize'] = '1000';
    final s = summarizeProject(p);
    expect(s.stepsDone, p.completed.length);
    expect(s.analyses, greaterThan(3));
    expect(s.lastAnalysis, p.journal.last.methodName);
    expect((s.planned, s.analysed), (1000, 640));
    expect(s.attention, contains('effectif analysé 640 / 1000 prévus'));
    final empty = summarizeProject(Project(id: 'e', title: 'E', createdAt: ''));
    expect(empty.status, anyOf('non commencé', 'à relire'));
    expect(empty.tutorSolved, 0);
  });
}
