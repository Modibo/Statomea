import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  ResearchQuestion q(String t) => applyInference(ResearchQuestion(text: t), inferQuestion(t)).$1;
  String? main(ResearchQuestion r) {
    final a = advise(r);
    return a.options.where((o) => o.recommended).map((o) => o.methodId).firstOrNull ?? a.options.firstOrNull?.methodId;
  }

  test('essai : PICO, horizon, issue binaire ; le plan non dit est demandé, jamais inventé', () {
    final i = inferQuestion('Chez les patients diabétiques de type 2, la metformine versus les sulfamides réduit-elle la mortalité cardiovasculaire à 5 ans ?');
    expect(i.population, 'patients diabétiques de type 2');
    expect(i.exposure, 'metformine');
    expect(i.comparator, 'sulfamides');
    expect(i.outcome, 'mortalité cardiovasculaire');
    expect(i.horizon, '5 ans');
    expect(i.outcomeType, OutcomeType.binary);
    expect(i.design, isNull);
    expect(advise(q('Chez les patients diabétiques de type 2, la metformine versus les sulfamides réduit-elle la mortalité cardiovasculaire à 5 ans ?')).questions.map((c) => c.field), contains('design'));
  });

  test('prévalence → transversal, descriptif, proportion avec IC', () {
    final r = q('Quelle est la prévalence de l\'AgHBs chez les femmes enceintes à Bamako ?');
    expect(r.design, StudyDesign.crossSectional);
    expect(r.objective, StudyObjective.descriptive);
    expect(r.outcome, 'AgHBs');
    expect(main(r), 'proportion_ci');
  });

  test('cohorte, issue continue, ajustement → régression linéaire ; score de propension proposé', () {
    final r = q('La supplémentation en vitamine D est-elle associée à une baisse de la pression artérielle chez les adultes hypertendus, dans une cohorte suivie pendant 2 ans ?');
    expect([r.design, r.outcomeType, r.needsAdjustment, r.exposure], [StudyDesign.cohort, OutcomeType.continuous, true, 'supplémentation en vitamine D']);
    expect(main(r), 'linear_regression');
  });

  test('diagnostic : test évalué, référence, performance diagnostique', () {
    final r = q('Quelles sont la sensibilité et la spécificité du test rapide du paludisme par rapport à la microscopie chez les enfants fébriles ?');
    expect([r.design, r.objective, r.exposure, r.comparator, r.referenceStandardAvailable], [StudyDesign.diagnosticAccuracy, StudyObjective.diagnostic, 'test rapide du paludisme', 'microscopie', true]);
    expect(main(r), 'diagnostic_accuracy');
  });

  test('prédiction ; essai avec risque concurrent ; accord entre méthodes ; cas-témoins en anglais', () {
    expect(main(q('Peut-on prédire le risque d\'événement cardiovasculaire à 5 ans chez les adultes de 40 à 70 ans ?')), 'prediction_logistic_internal');
    expect(inferQuestion('Peut-on prédire le risque d\'événement cardiovasculaire à 5 ans chez les adultes de 40 à 70 ans ?').population, 'adultes de 40 à 70 ans');
    final rct = q('Essai randomisé : l\'effet d\'un programme d\'exercice sur le délai jusqu\'à la rechute chez des patients en rémission, le décès étant un risque concurrent ?');
    expect([rct.design, rct.outcomeType, rct.competingRisk, rct.needsAdjustment, rct.exposure], [StudyDesign.rct, OutcomeType.timeToEvent, true, false, 'programme d\'exercice']);
    expect(main(rct), 'cumulative_incidence');
    expect(main(q('Is the new point-of-care assay interchangeable with the laboratory method for creatinine (agreement between two methods)?')), 'bland_altman');
    final cc = inferQuestion('Does smoking increase the risk of lung cancer in adults compared with non-smokers? A case-control study.');
    expect([cc.design, cc.exposure, cc.comparator, cc.outcome, cc.population], [StudyDesign.caseControl, 'smoking', 'non-smokers', 'lung cancer', 'adults']);
  });

  test('une valeur déclarée n\'est jamais écrasée par une déduction', () {
    const declared = ResearchQuestion(text: 'Essai randomisé de la metformine', design: StudyDesign.cohort, population: 'adultes');
    final (r, filled) = applyInference(declared, inferQuestion(declared.text));
    expect(r.design, StudyDesign.cohort);
    expect(r.population, 'adultes');
    expect(filled, isNot(contains('design')));
  });

  test('protocole : sections, question, effectif, plan d\'analyse, feuille de route en 10 étapes', () {
    const text = '''Efficacité de la vitamine D chez l'adulte hypertendu
Question de recherche : La supplémentation en vitamine D réduit-elle la pression artérielle systolique à 12 mois chez les adultes hypertendus ?
Schéma de l'étude
Essai randomisé contrôlé en double aveugle, deux bras parallèles.
Population
Adultes de 30 à 70 ans avec une hypertension artérielle non contrôlée.
Intervention : vitamine D3 100 000 UI par mois.
Comparateur : placebo.
Critère de jugement principal
Pression artérielle systolique à 12 mois (mmHg).
Nombre de sujets nécessaires
240 patients (120 par bras) pour une différence de 5 mmHg.
Analyse statistique
Comparaison des moyennes ajustée sur la valeur initiale.''';
    final d = protocolFromText(text);
    expect(d.title, startsWith('Efficacité de la vitamine D'));
    expect(d.question, contains('réduit-elle la pression artérielle'));
    expect(d.sections['comparator'], 'placebo.');
    expect(d.sections['outcome'], contains('Pression artérielle systolique'));
    expect(d.sampleSize, 240);
    final r = d.toQuestion();
    expect([r.design, r.outcomeType, r.exposureType], [StudyDesign.rct, OutcomeType.continuous, ExposureType.binary]);
    final p = Project(id: 'x', title: d.title, createdAt: '', question: r, analysisPlan: draftAnalysisPlan(r));
    expect(p.analysisPlan, contains('Analyse principale'));
    final road = projectRoadmap(p);
    expect(road.map((s) => s.step), Step.values);
    expect(road.first.status, RoadmapStatus.proposed);
    expect(() => protocolFromText('   \n  '), throwsA(isA<StatInputError>()));
  });

  test('saisie de la question : déduction, re-déduction quand le texte change, choix du chercheur conservés', () {
    final p = Project(id: 'q', title: 't', createdAt: '');
    p.question = p.question.copyWith(text: 'Quelle est la prévalence de l\'AgHBs chez les femmes enceintes ?');
    autoCompleteProject(p);
    expect(p.question.design, StudyDesign.crossSectional);
    expect(p.inferred['design'], 'crossSectional');
    expect(p.analysisPlan, contains('Proportion'));
    // Le chercheur fixe lui-même l'objectif ; puis le texte change.
    p.question = p.question.copyWith(objective: StudyObjective.explanatory);
    p.question = p.question.copyWith(text: 'Dans une cohorte, le tabac est-il associé au risque d\'infarctus chez les adultes ?');
    autoCompleteProject(p);
    expect(p.question.design, StudyDesign.cohort); // déduit, recalculé
    expect(p.question.objective, StudyObjective.explanatory); // choisi, conservé
    expect(p.inferred.containsKey('objective'), isFalse);
    expect(p.question.outcome, 'infarctus');
    expect(p.analysisPlan, isNot(contains('Proportion'))); // plan automatique remis à jour
    final back = Project.decode(p.encode());
    expect(back.inferred['design'], 'cohort');
  });

  test('calcul d\'effectif adapté à la question ; protocole prérédigé (rubriques, éléments à compléter)', () {
    String? calc(String t) => sampleSizePlan(q(t))?.calculator;
    expect(calc('Quelle est la prévalence de l\'AgHBs chez les femmes enceintes ?'), 'sample_size');
    expect(calc('Essai randomisé : le traitement A versus placebo réduit-il le délai jusqu\'à la rechute ?'), 'power_survival');
    expect(calc('Essai randomisé : la vitamine D réduit-elle la pression artérielle chez les adultes ?'), 'power_means');
    expect(calc('Dans une cohorte, le tabac augmente-t-il le risque d\'infarctus ?'), 'power_proportions');
    expect(calc('Does smoking increase the risk of lung cancer? A case-control study.'), 'power_case_control');
    expect(calc('Peut-on prédire le risque de réadmission à 30 jours ?'), 'sample_size');
    expect(sampleSizePlan(q('Peut-on prédire le risque de réadmission à 30 jours ?'))!.presets, {'type': 'riley'});
    final p = Project(id: 'pr', title: 'Vitamine D', createdAt: '', question: q('Essai randomisé : la vitamine D réduit-elle la pression artérielle à 12 mois chez les adultes hypertendus ?'));
    p.analysisPlan = draftAnalysisPlan(p.question);
    p.inferred['plannedSampleSize'] = '240';
    expect(projectRoadmap(p)[2].calculator, 'power_means');
    expect(projectRoadmap(p)[2].lines.join(' '), contains('240'));
    final o = protocolOutline(p);
    expect(o.map((x) => x.title), containsAll(['Question de recherche et objectifs', 'Nombre de sujets nécessaires', 'Plan d\'analyse statistique', 'Aspects éthiques et réglementaires']));
    final text = [for (final x in o) ...x.paragraphs].join('\n');
    expect(text, contains('adultes hypertendus'));
    expect(text, contains('Effectif prévu : 240 sujets.'));
    expect(text, contains('[À compléter : critères d\'inclusion]'));
    expect(text, contains('Randomisation, aveugle et allocation'));
  });

  // Structures relevées sur de vrais protocoles de thèse et de recherche (contenu reformulé et anonymisé).
  test('vrais protocoles : page de garde, intitulés numérotés, chronogramme, références, effectif après ajustements', () {
    const these = """
Réalisé par :
Étudiant X
REPUBLIQUE DU MALI
MINISTERE DE L'ENSEIGNEMENT SUPERIEUR
PROTOCOLE DE THESE DE FIN D'ETUDE
Thème : Suivi de l'hémoglobine glyquée chez les diabétiques de type 2 à l'hôpital régional.
Thème : Suivi de l'hémoglobine glyquée chez les diabétiques de type 2 à l'hôpital régional.
Type d'étude : Étude transversale par recrutement consécutif.
Lieu d'étude 1
Hôpital régional, route principale
Tel: +000 00 00 00 00
INTRODUCTION
Le diabète est une maladie chronique dont le suivi repose sur l'HbA1c.
OBJECTIFS
Objectif général :
Évaluer la relation entre l'hémoglobine glyquée et les autres paramètres au cours du suivi des patients diabétiques de type 2.
MATERIEL ET METHODES
1.\tLieu d'étude
L'hôpital est situé au centre du pays.
2. Type et design de l'étude
Il s'agira d'une étude transversale.
Calcul de la taille de l'échantillon
Avec une prévalence de 7 % et une marge d'erreur de 5 %, le nombre requis sera de 100. En ajoutant 10 % nous aurons 110 sujets nécessaires pour cette étude.
Période d'étude
Activité
01/23
02/23
Saisie et analyse des données
Rédaction de la thèse
La population d'étude
Cette étude portera sur les diabétiques de type 2 âgés de 18 ans ou plus. Les sujets seront en phase stable.
Les critères d'inclusion
Patients de 18 ans ou plus.
Gestion et analyse des données
Les données seront analysées avec le logiciel R ; les proportions seront comparées par le test du khi-deux.
Considération Éthique
Le consentement éclairé sera recueilli.
REFERENCE
1. Auteur A. Glycated haemoglobin: where do we stand? Revue. 2022.
""";
    final d = protocolFromText(these);
    expect(d.title, startsWith('Suivi de l\'hémoglobine glyquée'));
    expect(d.question, startsWith('Évaluer la relation'), reason: 'la question vient de l\'objectif, pas du titre d\'une référence');
    expect(d.sections['design'], isNot(contains('Tel:')), reason: 'la page de garde est close par « Lieu d\'étude »');
    expect(d.sections['analysis'], contains('khi-deux'));
    expect(d.sections['analysis'], isNot(contains('Rédaction')), reason: 'la cellule du chronogramme est remplacée par la vraie rubrique');
    expect(d.sections['population'], contains('18 ans'));
    expect(d.sampleSize, 110);
    final q = d.toQuestion();
    expect(q.design, StudyDesign.crossSectional);
    expect(q.outcomeType, isNot(OutcomeType.timeToEvent), reason: '« au cours du suivi » ne fait pas une analyse de survie');
    expect(q.population, 'Cette étude portera sur les diabétiques de type 2 âgés de 18 ans ou plus.');

    const recherche = """
PROTOCOLE DE RECHERCHE
Titre du projet
Biomarqueurs de l'hémostase et pronostic des blessés par arme à feu : étude multicentrique prospective
I. Contexte et Justification
Les scores existants ont été comparés (Auteur, 2019). Where do we stand? reste une question ouverte.
II. Objectifs
1. Objectif principal
Évaluer la valeur pronostique des anomalies précoces de l'hémostase pour prédire la mortalité à 28 jours.
III. Matériel et méthodes
1. Type et durée de l'étude
Il s'agira d'une étude multicentrique prospective observationnelle.
2. Population d'étude
a. Critères d'inclusion
Blessés par arme à feu admis dans les six heures. Âge de 18 ans ou plus.
3. Taille d'échantillon
La taille n0 requise sera approximativement de 268,889 patients.
La taille globale d'échantillon finale sera ≈ 545 patients
Le nombre de sujet nécessaire sera donc n = 550 patients.
Taille par centre (5 centres) : 110 patients par centre
Vérification événements (mortalité 15%) : n = 110
b. Critère de jugement principal
mortalité à J28 : oui ou non b.
8. Gestion des données et analyse statistique
b. Analyse statistique
Régression logistique pénalisée, validation interne par bootstrap.
IX. Références
Auteur B (2019). Scoring systems in trauma: where do we stand? Shock.
""";
    final r = protocolFromText(recherche);
    expect(r.title, startsWith('Biomarqueurs de l\'hémostase'));
    expect(r.sampleSize, 550, reason: 'ni le décimal 268,889, ni l\'effectif par centre, ni la vérification des événements');
    expect(r.sections['analysis'], contains('bootstrap'));
    expect(r.sections['population'], contains('six heures'));
    final rq = r.toQuestion();
    expect(rq.design, StudyDesign.cohort);
    expect(rq.objective, StudyObjective.predictive);
    expect(rq.outcome, 'mortalité à J28 : oui ou non');
  });
}
