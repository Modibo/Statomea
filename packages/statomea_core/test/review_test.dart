import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

/// Projet tel que l'import d'un protocole le construit (question déduite, plan proposé, rubriques conservées).
Project imported(String text) {
  final d = protocolFromText(text);
  final p = Project(id: 'p', title: d.title, createdAt: '2026-10-19');
  p.question = d.toQuestion();
  p.analysisPlan = 'Plan d\'analyse du protocole : ${d.sections['analysis'] ?? ''}\n\nProposition de Statoméa :\n${draftAnalysisPlan(p.question)}';
  if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
  p.protocol = Map.of(d.fullSections);
  return p;
}

ReviewFinding? find(ProjectReview r, String id) {
  for (final f in r.findings) {
    if (f.id == id) return f;
  }
  return null;
}

// Structures relevées sur deux vrais protocoles (contenu reformulé et anonymisé).
const these = """
Thème : Suivi de l'hémoglobine glyquée chez les diabétiques de type 2 à l'hôpital régional.
OBJECTIFS
Objectif général :
Évaluer la relation entre l'hémoglobine glyquée et les autres paramètres au cours du suivi des patients diabétiques de type 2.
Objectifs spécifiques
1. Décrire les caractéristiques des patients,
2. Évaluer la corrélation entre l'hémoglobine glyquée et la glycémie à jeun,
3. Rechercher les associations entre l'hémoglobine glyquée et les troubles lipidiques,
4. Déterminer la prévalence du syndrome métabolique,
5. Déterminer la prévalence de l'atteinte rénale,
6. Explorer les associations avec les complications.
MATERIEL ET METHODES
2. Type et design de l'étude
Il s'agira d'une étude transversale par recrutement consécutif.
Calcul de la taille de l'échantillon
La taille a été calculée selon la prévalence du diabète en milieu hospitalier qui était de sept pourcent (7%). Avec la formule N = (Z^2*pq)/i^2, une marge d'erreur de 5 % et un niveau de confiance de 95 %, le nombre requis sera de 100. Pour couvrir les refus et les perdus de vue, nous ajouterons 10% ce qui nous ramènera à 110 sujets nécessaires.
La population d'étude
Les diabétiques de type 2 âgés de 18 ans ou plus suivis en médecine.
Gestion et analyse des données
Les données seront analysées avec le logiciel R. Les proportions seront comparées par le khi2 de Pearson ou le test exact de Fisher. Le test de Kolmogorov Smirnov sera utilisé pour évaluer la normalité. Le test de Student ou le Kruskall Wallis seront utilisés selon que la variable soit paramétrique ou non. La corrélation de Pearson sera utilisée pour la relation entre la glycémie et l'hémoglobine glyquée. Le seuil de signification sera fixé à 0,05.
Considération Éthique
Un consentement éclairé écrit sera recueilli.
""";

const recherche = """
Titre du projet
Biomarqueurs de l'hémostase et pronostic des blessés par arme à feu : étude multicentrique prospective
II. Objectifs
1. Objectif principal
Évaluer la valeur pronostique des anomalies précoces de l'hémostase, combinées dans un score, pour prédire la mortalité à 28 jours et le recours à une transfusion massive.
III. Matériel et méthodes
1. Type et durée de l'étude
Il s'agira d'une étude multicentrique prospective observationnelle.
2. Population d'étude
Blessés par arme à feu admis dans les six heures, âgés de 18 ans ou plus.
3. Taille d'échantillon
p : nombre de paramètres prédictifs ; S : facteur de shrinkage cible (ici fixé à 0,90) ; R² (Cox–Snell) attendu compris entre 0,15 et 0,20, (0,18 dans la présente étude).
La taille n0 requise sera approximativement de 268,889 patients.
Le nombre de sujet nécessaire sera donc n = 550 patients.
Vérification événements (mortalité 15%) : n = 110. Événements par prédicteur : p = 6.
8. Gestion des données et analyse statistique
b. Analyse statistique
Seuil de significativité p < 0,05. Régression logistique avec sélection pénalisée LASSO, variables continues. La calibration sera analysée par la courbe de calibration, la pente et le test de Hosmer-Lemeshow. Validation interne par bootstrap. Les données manquantes seront traitées par imputation multiple. Les seuils finaux seront définis à partir des performances observées dans la cohorte.
9. Considérations éthiques
Avis du comité d'éthique et consentement.
""";

void main() {
  test('protocole de thèse : erreurs relevées, effectif recalculé, corrections appliquées et tracées', () {
    final p = imported(these);
    final r = reviewProject(p);
    final loss = find(r, 'loss_adjustment')!;
    expect(loss.level, ReviewLevel.error);
    expect(loss.problem, contains('n = 100 / (1 − 0,1) = 112'));
    expect(loss.evidence, contains('110'));
    expect(find(r, 'precision_recomputed')!.level, ReviewLevel.ok, reason: '1,96² × 0,07 × 0,93 / 0,05² = 100, comme le protocole');
    expect(find(r, 'precision_too_wide')!.correction, contains('n = 626'));
    expect(find(r, 'sample_size_basis')!.correction, allOf(contains('r = 0,3 → 85'), contains('r = 0,2 → 194')));
    expect(find(r, 'no_adjustment')!.level, ReviewLevel.error);
    expect(find(r, 'test_pairing')!.evidence, contains('Kruskall Wallis'));
    expect(find(r, 'ks_normality'), isNotNull);
    expect(find(r, 'pearson_only')!.evidence, contains('corrélation de Pearson'));
    expect(find(r, 'missing_data'), isNotNull);
    expect(find(r, 'multiplicity')!.problem, startsWith('6 objectifs'));
    expect(find(r, 'alpha'), isNull, reason: 'le seuil est donné');
    expect(find(r, 'ethics'), isNull);
    expect(find(r, 'cross_sectional_incidence'), isNull, reason: '« au cours du suivi » n\'est pas une incidence');

    final done = applyAllCorrections(p, date: '2026-10-19');
    expect(done.map((c) => c.id), containsAll(['loss_adjustment', 'no_adjustment', 'test_pairing', 'ks_normality', 'missing_data', 'multiplicity', 'pearson_only']));
    expect(p.inferred['plannedSampleSize'], '112');
    expect(p.analysisPlan, contains('Correction Statoméa — effectif corrigé pour les pertes'));
    expect(p.analysisPlan, contains('Mann-Whitney'));
    expect(p.corrections.first.date, '2026-10-19');
    // Restent les points qui demandent une décision du chercheur.
    expect(reviewProject(p).problems.map((f) => f.id).toSet(), {'precision_too_wide', 'sample_size_basis'});
    expect(applyAllCorrections(p), isEmpty, reason: 'une correction n\'est jamais appliquée deux fois');
    // Le protocole prérédigé reprend l'effectif corrigé et les corrections.
    final outline = protocolOutline(p).map((s) => s.paragraphs.join('\n')).join('\n');
    expect(outline, contains('112'));
    expect(outline, contains('imputation multiple'));
    // Enregistrement et relecture identiques après rechargement.
    final back = Project.decode(p.encode());
    expect(back.protocol['sampleSize'], p.protocol['sampleSize']);
    expect(back.corrections.length, p.corrections.length);
    expect(reviewProject(back).problems.length, 2);
  });

  test('protocole de prédiction : critères de Riley refaits ; critère principal, calibration, seuils, effet centre', () {
    final p = imported(recherche);
    expect(p.inferred['plannedSampleSize'], '550');
    final r = reviewProject(p);
    expect(find(r, 'riley_recomputed')!.problem, contains('268,9'));
    final all = find(r, 'riley_all')!;
    expect(all.problem, allOf(contains('i : 269'), contains('ii : 188'), contains('iii : 196'), contains('82,5 événements'), contains('13,8 événements par paramètre')));
    final prim = find(r, 'primary_outcomes')!;
    expect(prim.problem, allOf(contains('mortalité à 28 jours'), contains('transfusion massive')));
    for (final id in ['hosmer_lemeshow', 'data_driven_cutoffs', 'centre_effect']) {
      expect(find(r, id), isNotNull, reason: id);
    }
    for (final id in ['prediction_validation', 'prediction_calibration', 'missing_data', 'stepwise', 'alpha', 'ethics']) {
      expect(find(r, id), isNull, reason: '$id : déjà traité par le protocole');
    }
    applyAllCorrections(p, date: '2026-10-19');
    expect(p.question.outcome, 'mortalité à 28 jours');
    expect(reviewProject(p).problems, isEmpty);
  });

  test('nouveau projet : manques, formulation causale reformulée, plan corrigé', () {
    const text = 'Quel est l\'effet du tabac sur le risque d\'infarctus chez les adultes suivis pendant 10 ans ?';
    final p = Project(id: 'n', title: 'Tabac', createdAt: '');
    p.question = applyInference(const ResearchQuestion(text: text), inferQuestion(text)).$1.copyWith(design: StudyDesign.cohort, needsAdjustment: true);
    p.analysisPlan = 'Comparaison des groupes par le test du khi-deux.';
    final r = reviewProject(p);
    final causal = find(r, 'causal_wording')!;
    expect(causal.correction, contains('Quelle est l\'association entre le tabac et le risque d\'infarctus'));
    expect(find(r, 'sample_size_missing')!.calculator, isNotNull);
    expect(find(r, 'no_adjustment')!.correction, contains('Poisson'));
    expect(find(r, 'alpha')!.level, ReviewLevel.missing);
    applyAllCorrections(p);
    expect(p.question.text, startsWith('Quelle est l\'association entre le tabac'));
    expect(p.analysisPlan, allOf(contains('ajustée'), contains('bilatéraux'), contains('imputation')));
    expect(reviewProject(p).problems.map((f) => f.id), ['sample_size_missing']);
  });

  test('plan et objectif incompatibles : cas-témoins (fréquence, risque relatif), transversal (incidence), plan absent', () {
    final cc = Project(id: 'c', title: 'CC', createdAt: '');
    cc.question = const ResearchQuestion(text: 'Quelle est la prévalence de l\'exposition au plomb chez les cas de saturnisme et chez les témoins ?', design: StudyDesign.caseControl, objective: StudyObjective.descriptive);
    cc.analysisPlan = 'Le risque relatif sera estimé avec son IC à 95 % au seuil de 5 %.';
    final r = reviewProject(cc);
    expect(find(r, 'case_control_frequency')!.level, ReviewLevel.error);
    expect(find(r, 'case_control_rr')!.evidence, contains('risque relatif'));
    applyAllCorrections(cc);
    expect(cc.question.objective, StudyObjective.explanatory);
    expect(cc.analysisPlan, startsWith('Le odds ratio sera estimé'));

    final cs = Project(id: 's', title: 'CS', createdAt: '');
    cs.question = const ResearchQuestion(text: 'Quelle est l\'incidence du diabète chez les adultes de Bamako ?', design: StudyDesign.crossSectional, objective: StudyObjective.descriptive);
    final r2 = reviewProject(cs);
    expect(find(r2, 'cross_sectional_incidence')!.level, ReviewLevel.error);
    expect(find(r2, 'plan_missing')!.fix, isNotNull);
    applyAllCorrections(cs);
    expect(cs.question.text, contains('prévalence du diabète'));
    expect(cs.question.outcomeType, OutcomeType.binary);
    expect(cs.analysisPlan, contains('Analyse principale'));
  });
}
