import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('diapositives : titre, contexte, objectif, méthodes, flux, Tableau 1, résultats, limites, conclusion, merci', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    p.flow.addAll({'assessed': '700', 'excluded_reasons': 'refus : 60', 'included': '640', 'analysed': '640'});
    final s = presentationSlides(p, date: '2026-10-19');
    expect(s.map((x) => x.title).toList(), [
      p.title, 'Contexte et justification', 'Objectif', 'Méthodes', 'Participants', 'Caractéristiques des participants', 'Résultats', 'Résultat principal', 'Limites', 'Conclusion', 'Merci de votre attention',
    ]);
    expect(s.first.titleSlide, isTrue);
    expect(s.first.bullets.last, '2026-10-19');
    expect(s[3].bullets.first, 'Il s\'agit d\'une étude transversale.');
    expect(s[4].table!.title, startsWith('Figure 1'));
    expect(s[4].bullets.single, startsWith('Sur 700 personnes évaluées'));
    expect(s[5].table!.rows.length, 9, reason: 'au plus 9 lignes, la dernière renvoie à l\'article');
    expect(s[5].table!.rows.last.first, contains('tableau complet dans l\'article'));
    expect(s[7].highlight, contains('IC 95 %'));
    expect(s[8].bullets, contains(contains('chronologie')));
    expect(s[9].bullets.last, contains('association'));
  });

  test('projet vide : squelette complet ; références si présentes', () {
    final p = Project(id: 'v', title: 'Projet', createdAt: '');
    final s = presentationSlides(p);
    expect(s.map((x) => x.title), ['Projet', 'Contexte et justification', 'Objectif', 'Méthodes', 'Limites', 'Conclusion', 'Merci de votre attention']);
    expect(s.expand((x) => x.bullets).where((b) => b.startsWith('[À compléter')).length, greaterThan(5));
    p.references.addAll(parseReferences('TY  - JOUR\nTI  - A study\nAU  - Smith, John\nPY  - 2020\nJO  - Lancet\nER  - \n'));
    expect(presentationSlides(p).map((x) => x.title), contains('Références'));
  });
}
