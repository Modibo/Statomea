import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Project _imported(String text) {
  final d = protocolFromText(text);
  final p = Project(id: 'b', title: d.title, createdAt: '')
    ..question = d.toQuestion()
    ..protocol = Map.of(d.fullSections);
  if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
  return p;
}

void main() {
  test('chronogramme : inclusions au rythme déclaré, suivi selon l\'horizon, saisie, analyse, rédaction', () {
    final p = _imported("""
Titre du projet
Mortalité à 28 jours des blessés : étude de cohorte prospective
Objectif principal
Prédire la mortalité à 28 jours des blessés admis aux urgences.
Nombre de sujets nécessaires
Il faut 100 patients. Le service reçoit 10 patients éligibles par mois.
Variables étudiées
Les variables suivantes seront recueillies : l'âge, le sexe, l'INR, le fibrinogène et le lactate.
""");
    final pl = studyPlanning(p);
    final ph = {for (final x in pl.phases) x.key: x};
    expect((ph['prep']!.start, ph['prep']!.end), (1, 2));
    expect((ph['recruit']!.start, ph['recruit']!.end), (3, 12), reason: '100 / 10 par mois = 10 mois');
    expect((ph['follow']!.start, ph['follow']!.end), (13, 13), reason: '28 jours ≈ 1 mois après le dernier inclus');
    expect((ph['entry']!.start, ph['entry']!.end), (3, 14));
    expect((ph['analysis']!.start, ph['analysis']!.end), (15, 16));
    expect((ph['writing']!.start, ph['writing']!.end), (17, 18));
    expect(pl.totalMonths, 18);
    final q = {for (final l in pl.lines) l.key: l.quantity};
    expect(q['lab'], 300, reason: '3 examens (INR, fibrinogène, lactate) × 100');
    expect(q['participants'], 100);
    expect(q['staff'], 10);
    expect(pl.currency, 'FCFA');
    expect(pl.subtotal, 0);
  });

  test('budget : coûts saisis, quantités modifiables, imprévus 10 %, rubrique 13 du protocole, enregistrement', () {
    final p = _imported("""
Titre du projet
Anémie des femmes enceintes : étude transversale
Objectif principal
Déterminer la prévalence de l'anémie chez les femmes enceintes.
Type et durée de l'étude
Étude transversale ; la durée totale de l'étude sera de douze mois.
Nombre de sujets nécessaires
Il faut 400 femmes.
Variables étudiées
Les informations suivantes seront recueillies : l'âge, le poids, l'hémoglobine et la glycémie.
""");
    p.planning.addAll({'u_lab': '2500', 'u_participants': '1000', 'u_ethics': '50000', 'q_dissemination': '2', 'u_dissemination': '150000'});
    final pl = studyPlanning(p);
    final ph = {for (final x in pl.phases) x.key: x};
    expect(ph['recruit']!.months, 5, reason: '12 mois − 2 (préparation) − 1 (gel de la base) − 4 (analyse et rédaction)');
    expect(ph.containsKey('follow'), isFalse);
    final t = {for (final l in pl.lines) l.key: l.total};
    expect(t['lab'], 2 * 400 * 2500, reason: 'hémoglobine et glycémie');
    expect(t['participants'], 400000);
    expect(t['dissemination'], 300000);
    expect(t['crf'], isNull);
    expect(pl.subtotal, 2000000 + 400000 + 50000 + 300000);
    expect(pl.total, closeTo(2750000 * 1.1, 1e-6));
    expect(formatMoney(pl.total), '3 025 000');
    final s13 = protocolOutline(p).last;
    expect(s13.paragraphs.first, 'Calendrier prévisionnel (12 mois) :');
    expect(s13.paragraphs, contains('— mois 3 à 7 : Inclusions et recueil des données'));
    expect(s13.paragraphs.join('\n'), contains('Examens biologiques (2 par participant) : 800 examens × 2 500 FCFA = 2 000 000 FCFA'));
    expect(s13.paragraphs.join('\n'), contains('[À compléter : coût unitaire]'));
    expect(s13.paragraphs.join('\n'), contains('total 3 025 000 FCFA (lignes sans coût non comptées)'));
    final back = Project.decode(p.encode());
    expect(back.planning, p.planning);
    expect(studyPlanning(back).total, pl.total);
  });
}
