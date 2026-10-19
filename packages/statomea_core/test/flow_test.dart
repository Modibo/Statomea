import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  test('étude observationnelle : effectifs proposés, saisie avec motifs, contrôles, phrase et Figure 1 de l\'article', () {
    final p = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
    final proposed = flowDiagram(p);
    expect(proposed.guideline, 'STROBE');
    expect(proposed.proposed, isTrue);
    expect(proposed.stages[1].main.single.n, p.dataset!.rowCount, reason: 'inclus = lignes du fichier');
    p.flow.addAll({'assessed': '700', 'excluded_reasons': 'refus : 40\ndossier incomplet : 20', 'included': '640', 'lost_reasons': 'prélèvement non analysable : 0', 'analysed': '640'});
    final d = flowDiagram(p);
    expect(d.stages.first.side.single!.n, 60);
    expect(d.stages.first.side.single!.details, ['refus : 40', 'dossier incomplet : 20']);
    expect(d.warnings, isEmpty);
    expect(flowSentence(d), 'Sur 700 personnes évaluées pour l\'éligibilité, 60 ont été exclues (refus : 40 ; dossier incomplet : 20), 640 ont été incluses, 640 ont été analysées.');
    final a = articleOutline(p).where((s) => s.title == 'Participants').elementAt(1);
    expect(a.paragraphs.first, startsWith('Sur 700 personnes évaluées'));
    expect(a.tables.first.title, 'Figure 1. Diagramme de flux des participants (STROBE)');
    expect(a.tables.first.rows.first, ['Évalués pour l\'éligibilité (n = 700)', 'Exclus (n = 60) ; refus : 40 ; dossier incomplet : 20']);
    p.flow['included'] = '650';
    expect(flowDiagram(p).warnings, [startsWith('Évalués (700) − exclus (60) = 640, différent des inclus (650)'), startsWith('Inclus (650) − non analysés (0) = 650, différent des analysés (640)')]);
    expect(articleOutline(p).where((s) => s.title == 'Participants').elementAt(1).paragraphs, contains(contains('[À compléter : vérifier les effectifs')));
    expect(Project.decode(p.encode()).flow, p.flow);
  });

  test('essai randomisé : bras, alloués, perdus de vue, analysés ; incohérences signalées', () {
    final p = Project(id: 'r', title: 'Essai', createdAt: '')..question = const ResearchQuestion(design: StudyDesign.rct);
    p.flow.addAll({
      'assessed': '300', 'excluded_reasons': 'non éligibles : 80\nrefus : 20', 'included': '200',
      'arm1_name': 'Vitamine D', 'arm2_name': 'Placebo', 'arm1_allocated': '100', 'arm2_allocated': '100',
      'arm1_lost_reasons': 'perdus de vue : 6\narrêt du traitement : 2', 'arm1_analysed': '92', 'arm2_lost': '5', 'arm2_analysed': '100',
    });
    final d = flowDiagram(p);
    expect(d.guideline, 'CONSORT 2010');
    expect(d.stages.map((s) => s.main.length), [1, 1, 2, 2, 2]);
    expect(d.stages[2].main.map((b) => b.text), ['Alloués à Vitamine D (n = 100)', 'Alloués à Placebo (n = 100)']);
    expect(d.stages[3].main.first.n, 8);
    expect(d.warnings.single, startsWith('Placebo : alloués (100) − perdus (5) = 95, différent des analysés (100)'));
    expect(flowSentence(d), contains('192 ont été analysées'));
  });
}
