/// Diaporama de soutenance ou de congrès tiré du projet : titre, contexte, objectif, méthodes, diagramme de flux,
/// Tableau 1, résultats (Tableau 2, résultats principaux), résultat clé, limites, conclusion, références. Le contenu
/// reprend l'article prérédigé ; ce qui revient à l'orateur est marqué « à compléter ».
library;

import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'article.dart';
import 'flow.dart';
import 'project.dart';
import 'references.dart';

class Slide {
  final String title;
  final List<String> bullets;
  final ResultTable? table;
  final String? highlight; // grand chiffre ou phrase clé
  final bool titleSlide;
  const Slide(this.title, {this.bullets = const [], this.table, this.highlight, this.titleSlide = false});
}

String _todo(String what) => tr('[À compléter : $what]', '[To complete: $what]');

ResultTable _trim(ResultTable t, int maxRows) =>
    t.rows.length <= maxRows ? t : ResultTable(t.title, t.header, [...t.rows.take(maxRows - 1), [tr('… (tableau complet dans l\'article)', '… (full table in the article)'), for (var i = 1; i < t.header.length; i++) '']]);

/// Diapositives du projet (au plus 8 lignes par tableau pour rester lisible).
List<Slide> presentationSlides(Project p, {String date = ''}) {
  final q = p.question;
  final art = articleOutline(p);
  List<String> para(String title, [int i = 0]) {
    final s = art.where((x) => x.title == title);
    return s.length > i ? s.elementAt(i).paragraphs : const [];
  }

  List<ResultTable> tables(String title, [int i = 0]) {
    final s = art.where((x) => x.title == title);
    return s.length > i ? s.elementAt(i).tables : const [];
  }

  String short(String s, [int max = 160]) => s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
  final methods = <String>[
    ...para(tr('Schéma et cadre de l\'étude', 'Study design and setting')).take(2),
    ...para(tr('Participants', 'Participants')).take(1),
    if (q.outcome.isNotEmpty) '${tr('Critère principal : ', 'Primary outcome: ')}${q.outcome}${q.horizon.isEmpty ? '' : ' (${q.horizon})'}',
    ...para(tr('Taille de l\'échantillon', 'Sample size')).take(1),
    ...para(tr('Analyse statistique', 'Statistical analysis')).take(2),
  ].map(short).toList();
  final participants = tables(tr('Participants', 'Participants'), 1);
  final flowFig = participants.where((t) => t.title.startsWith(tr('Figure 1', 'Figure 1'))).firstOrNull;
  final t1 = participants.where((t) => t.title.startsWith(tr('Tableau 1', 'Table 1'))).firstOrNull;
  final resultTables = tables(tr('Résultats principaux', 'Main results'));
  final mainResults = para(tr('Résultats principaux', 'Main results'));
  final key = mainResults.isEmpty || mainResults.first.startsWith('[') ? null : mainResults.first;
  final limits = para(tr('Discussion', 'Discussion')).where((l) => l.startsWith(tr('Limites', 'Limitations'))).expand((l) {
    final body = l.substring(l.indexOf(':') + 1).trim();
    return body.split(RegExp(r'(?<=\.)\s+(?=[A-Z\[])')).map((x) => x.trim()).where((x) => x.isNotEmpty);
  }).toList();
  final flow = p.flow.isEmpty ? null : flowDiagram(p);
  final refs = p.references.isEmpty ? const <String>[] : referenceList(p.references, referenceNumbers(p.references, art.expand((s) => s.paragraphs))).take(6).toList();
  return [
    Slide(p.title, bullets: [_todo(tr('auteur(s), directeur(s), institution', 'author(s), supervisor(s), institution')), if (date.isNotEmpty) date], titleSlide: true),
    Slide(tr('Contexte et justification', 'Background and rationale'), bullets: [
      _todo(tr('problème de santé et son poids', 'health problem and its burden')),
      _todo(tr('ce que l\'on sait déjà', 'what is already known')),
      _todo(tr('ce qui manque : la question de l\'étude', 'what is missing: the study question')),
    ]),
    Slide(tr('Objectif', 'Objective'), bullets: [
      if (q.text.isNotEmpty) q.text else _todo(tr('question de recherche', 'research question')),
      if (q.objective != StudyObjective.unknown) '${tr('Objectif : ', 'Aim: ')}${objectiveLabel(q.objective)}',
    ]),
    Slide(tr('Méthodes', 'Methods'), bullets: methods.isEmpty ? [_todo(tr('plan, population, critère, analyse', 'design, population, outcome, analysis'))] : methods),
    if (flow != null && flowFig != null)
      Slide(tr('Participants', 'Participants'), bullets: [flowSentence(flow)].where((s) => s.isNotEmpty).toList(), table: flowFig),
    if (t1 != null) Slide(tr('Caractéristiques des participants', 'Participant characteristics'), table: _trim(t1, 9)),
    for (final t in resultTables) Slide(tr('Résultats', 'Results'), table: _trim(t, 9)),
    if (key != null) Slide(tr('Résultat principal', 'Main result'), highlight: short(key, 220)),
    Slide(tr('Limites', 'Limitations'), bullets: limits.isEmpty ? [_todo(tr('limites', 'limitations'))] : limits.map((l) => short(l)).take(5).toList()),
    Slide(tr('Conclusion', 'Conclusion'), bullets: [
      _todo(tr('message principal en une phrase', 'main message in one sentence')),
      _todo(tr('implications pour la pratique ou la recherche', 'implications for practice or research')),
      if (q.design != StudyDesign.rct && q.design != StudyDesign.unknown)
        tr('Étude ${designLabel(q.design).replaceFirst(RegExp('^étude '), '')} : conclure en termes d\'association.', '${designLabel(q.design)}: conclude in terms of association.'),
    ]),
    if (refs.isNotEmpty) Slide(tr('Références', 'References'), bullets: refs.map((r) => short(r, 200)).toList()),
    Slide(tr('Merci de votre attention', 'Thank you'), bullets: [_todo(tr('remerciements, contact', 'acknowledgements, contact'))], titleSlide: true),
  ];
}
