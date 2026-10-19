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
    expect(reviewProject(p).problems.map((f) => f.id).toSet(), {'precision_too_wide', 'sample_size_basis', 'exclusion_criteria', 'variables_missing'},
        reason: 'le texte abrégé du test n\'a ni critères de non-inclusion ni liste de variables');
    expect(applyAllCorrections(p), isEmpty, reason: 'une correction n\'est jamais appliquée deux fois');
    // Le protocole prérédigé reprend l'effectif corrigé et les corrections.
    final outline = protocolOutline(p).map((s) => s.paragraphs.join('\n')).join('\n');
    expect(outline, contains('112'));
    expect(outline, contains('imputation multiple'));
    // Enregistrement et relecture identiques après rechargement.
    final back = Project.decode(p.encode());
    expect(back.protocol['sampleSize'], p.protocol['sampleSize']);
    expect(back.corrections.length, p.corrections.length);
    expect(reviewProject(back).problems.length, 4);
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
    expect(reviewProject(p).problems.map((f) => f.id).toSet(), {'exclusion_criteria', 'variables_missing'});
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

  test('calculateur prérempli : hypothèses du protocole transmises ; effectif d\'une corrélation (R) et de Riley (pmsampsize)', () {
    final r = reviewProject(imported(these));
    expect(find(r, 'precision_too_wide')!.calculatorPresets, {'type': 'prop', 'p': '0,07', 'd': '0,02'});
    expect(find(r, 'sample_size_basis')!.calculatorPresets, {'type': 'correlation', 'r': '0,3', 'drop': '0,1'});
    final p = imported(recherche)..inferred['plannedSampleSize'] = '200';
    final ins = find(reviewProject(p), 'riley_insufficient')!;
    expect(ins.calculator, 'sample_size');
    expect(ins.calculatorPresets, {'type': 'riley', 'params': '6', 'r2': '0,18', 's': '0,9', 'prev': '0,15'});
    // Corrélation : n = ((z₁₋α/2 + z₁₋β) / atanh r)² + 3, valeurs de référence calculées dans R 4.2.3.
    for (final (rr, a, pw, ref) in [(0.3, 0.05, 0.8, 84.927811115775), (0.2, 0.05, 0.8, 193.968040183989), (0.5, 0.01, 0.9, 52.312398957553), (-0.25, 0.05, 0.8, 123.315704377499)]) {
      final x = sampleSizeCorrelation(r: rr, alpha: a, power: pw);
      expect(x.statistics['n_exact'], closeTo(ref, 1e-9));
      expect(x.statistics['n'], ref.ceilToDouble());
    }
    expect(sampleSizeCorrelation(r: 0.3, dropout: 0.1).statistics['n'], 95, reason: '84,93 / 0,9 = 94,4 → 95');
    // Riley : mêmes entiers que pmsampsize (validé dans prediction_test) ; majoration n / (1 − pertes).
    final m = sampleSizePredictionModel(parameters: 6, prevalence: 0.15, r2CoxSnell: 0.18);
    expect([m.statistics['n1']!.ceil(), m.statistics['n2']!.ceil(), m.statistics['n3']!.ceil()], [269, 188, 196]);
    expect(m.statistics['n'], 269);
    expect(m.statistics['epp'], closeTo(269 * 0.15 / 6, 1e-12));
    expect(sampleSizePredictionModel(parameters: 6, prevalence: 0.15, r2CoxSnell: 0.18, dropout: 0.1).statistics['n'], 299, reason: '269 / 0,9 = 298,9 → 299');
    expect(() => sampleSizePredictionModel(parameters: 6, prevalence: 0.15, r2CoxSnell: 0.95), throwsA(isA<StatInputError>()));
  });

  test('relecture élargie : essai randomisé, critères d\'inclusion, faisabilité du recrutement', () {
    final p = imported("""
Titre du projet
Vitamine D et pression artérielle
Objectif principal
La vitamine D réduit-elle la pression artérielle systolique à 6 mois par rapport au placebo ?
Schéma de l'étude
Essai randomisé contrôlé contre placebo.
Population d'étude
Patients hypertendus suivis en consultation.
Période d'étude : janvier à juin 2025
Nombre de sujets nécessaires
Il faut 100 patients au total. Le service reçoit 10 patients éligibles par mois.
Analyse statistique
Comparaison des moyennes par le test t de Student au seuil de 5 %, analyse per protocole ; données manquantes imputées.
""");
    final r = reviewProject(p);
    for (final id in ['rct_randomisation', 'rct_concealment', 'rct_blinding']) {
      expect(find(r, id)!.level, ReviewLevel.missing, reason: id);
    }
    expect(find(r, 'rct_itt')!.level, ReviewLevel.error);
    expect(find(r, 'inclusion_age'), isNotNull);
    expect(find(r, 'exclusion_criteria')!.level, ReviewLevel.missing);
    final rec = find(r, 'recruitment_unrealistic')!;
    expect(rec.problem, contains('6 mois permettent d\'inclure 60 sujets'));
    expect(rec.correction, contains('10 mois'));
    applyAllCorrections(p);
    expect(p.analysisPlan, allOf(contains('intention de traiter'), contains('enveloppes'), contains('blocs'), contains('évaluateur')));
    final left = reviewProject(p).problems.map((f) => f.id).toSet();
    expect(left.intersection({'rct_randomisation', 'rct_concealment', 'rct_blinding', 'rct_itt'}), isEmpty);
    expect(left, containsAll(['inclusion_age', 'exclusion_criteria', 'recruitment_unrealistic']), reason: 'à corriger par le chercheur');
  });

  test('variables du protocole : noms de colonnes, types, dictionnaire de données, variables absentes des données', () {
    final p = imported("""
Titre du projet
Hémostase des blessés
Variables étudiées
Les informations suivantes seront recueillies : le sexe, l'âge, le niveau d'instruction et le poids.
Pour l'hémostase, il s'agissait de l'INR (temps de prothrombine), du temps de céphaline plus activateur (TCA), du fibrinogène et de la numération plaquettaire.
Les paramètres incluront le pH sanguin, la saturation en oxygène (SaO₂), les bicarbonates (HCO₃⁻) et le potassium (K⁺).
Enfin, la fonction rénale sera évaluée à travers la créatinine et l'urée.
""");
    final vars = protocolVariables(p);
    expect(vars.map((v) => v.code), ['sexe', 'age', 'niveau_instruction', 'poids', 'inr', 'tca', 'fibrinogene', 'numeration_plaquettaire', 'ph_sanguin', 'sao2', 'hco3', 'k', 'creatinine', 'uree']);
    expect(vars.firstWhere((v) => v.code == 'sexe').type, 'catégorielle');
    expect(vars.firstWhere((v) => v.code == 'inr').type, 'numérique');
    final csv = protocolDictionaryCsv(p).split('\r\n');
    expect(csv[0], 'variable;type;libelle;unite');
    expect(csv[1], startsWith('id;identifiant;'));
    expect(csv, contains('tca;numérique;temps de céphaline plus activateur;'));
    // Le dictionnaire tiré du protocole est lu par l'import de l'étape 4.
    final dict = Dataset(['variable', 'type', 'libelle', 'unite'], [for (final l in csv.skip(1).where((l) => l.isNotEmpty)) l.split(';')]);
    final data = Dataset(['id', 'sexe', 'Age', 'INR', 'creatinine'], [['1', 'F', '34', '1.1', '80']]);
    final rep = applyDataDictionary(data, dict);
    expect(rep.applied, containsAll(['sexe', 'Age', 'INR', 'creatinine']), reason: 'correspondance sans casse ni accents');
    p.dataset = data;
    final absent = find(reviewProject(p), 'variables_absent')!;
    expect(absent.problem, startsWith('10 variable(s)'));
    expect(absent.problem, contains('niveau d\'instruction'));
    expect(absent.problem, isNot(contains('âge')));
  });

  test('grilles internationales : STROBE (observationnel), TRIPOD (prédiction), SPIRIT (essai), avant et après corrections', () {
    final obs = imported(these);
    final c = protocolChecklist(obs)!;
    expect(c.name, 'STROBE');
    String? ev(ProtocolChecklist c, String code) => c.items.firstWhere((i) => i.code == code).evidence;
    bool has(ProtocolChecklist c, String code) => c.items.firstWhere((i) => i.code == code).present;
    expect(ev(c, '3'), 'OBJECTIFS', reason: 'l\'intitulé de rubrique est préféré à une mention en passant');
    expect(ev(c, '4'), contains('Type et design de l\'étude'));
    expect(c.missing.map((i) => i.code), containsAll(['9', '12a', '12c', '12e', '22']));
    expect(has(c, '12a'), isFalse, reason: '« ajustée sur l\'âge et le sexe » (calcul d\'effectif) n\'est pas une analyse ajustée');
    applyAllCorrections(obs);
    final after = protocolChecklist(obs)!;
    expect(has(after, '12a') && has(after, '12c'), isTrue, reason: 'les corrections ajoutent l\'ajustement et les données manquantes');
    expect(after.present, greaterThan(c.present));

    final pred = protocolChecklist(imported(recherche))!;
    expect(pred.name, 'TRIPOD');
    expect(has(pred, '8') && has(pred, '10e') && has(pred, '9'), isTrue);
    expect([for (final i in pred.missing) i.code], ['3', '5', '10d', '11'], reason: 'texte abrégé : ni contexte, ni critères d\'inclusion nommés, ni AUC, ni groupes de risque');

    final rct = imported("""
Titre du projet
Essai randomisé vitamine D et pression artérielle
Objectif principal
Comparer la pression artérielle à 6 mois entre vitamine D et placebo.
Critère de jugement principal
Pression artérielle systolique à 6 mois.
Analyse statistique
Test t de Student au seuil de 5 %.
""");
    final sp = protocolChecklist(rct)!;
    expect(sp.name, 'SPIRIT 2013');
    expect(has(sp, '1'), isTrue);
    expect(sp.missing.map((i) => i.code), containsAll(['2', '16a', '16b', '17', '20', '22', '24', '26']));
    applyAllCorrections(rct);
    final sp2 = protocolChecklist(rct)!;
    expect(['16a', '16b', '17', '20'].every((k) => has(sp2, k)), isTrue);
    expect(sp2.missing.map((i) => i.code), containsAll(['2', '22', '24', '26']), reason: 'enregistrement, événements indésirables, éthique : à rédiger par le chercheur');
    expect(protocolChecklist(Project(id: 'u', title: 'U', createdAt: '')), isNull, reason: 'plan non précisé : pas de grille');
  });

  test('résultats confrontés au protocole : critère changé, effectif non atteint, analyse non prévue, sous-groupes, p sans IC', () {
    final p = imported(recherche);
    p.question = p.question.copyWith(outcome: 'mortalité à 28 jours');
    p.journal.add(const JournalEntry(id: 'j1', timestamp: '2026-10-19', methodId: 'cox', methodName: 'Modèle de Cox', result: {}));
    p.journal.add(const JournalEntry(id: 'j2', timestamp: '2026-10-19', methodId: 'logistic_regression', methodName: 'Régression logistique', result: {}));
    p.resultsText = '300 patients ont été inclus. Le critère principal était la transfusion massive, plus fréquente en cas de fibrinogène bas (p = 0,03). Chez les hommes, l\'effet était plus marqué (p = 0,01).';
    final r = reviewProject(p);
    expect(find(r, 'outcome_switch')!.level, ReviewLevel.error);
    expect(find(r, 'sample_attained')!.problem, startsWith('300 sujets analysés pour 550 prévus (55 %)'));
    final un = find(r, 'unplanned_analysis')!;
    expect(un.problem, startsWith('Modèle de Cox'), reason: 'la régression logistique était prévue, pas Cox');
    expect(un.problem, isNot(contains('Régression logistique')));
    expect(find(r, 'subgroups')!.evidence, contains('Chez les hommes'));
    expect(find(r, 'p_without_ci'), isNotNull);
    applyAllCorrections(p);
    expect(p.resultsText, allOf(contains('présentées à titre exploratoire : Modèle de Cox'), contains('sous-groupes n\'étaient pas prévues')));
    final left = reviewProject(p).problems.map((f) => f.id).toSet();
    expect(left.intersection({'unplanned_analysis', 'subgroups'}), isEmpty);
    expect(left, containsAll(['outcome_switch', 'sample_attained', 'p_without_ci']), reason: 'à corriger par le chercheur');

    // Résultats conformes : critère rapporté avec IC, effectif atteint.
    final ok = imported(recherche)..question = p.question;
    ok.resultsText = '560 patients ont été inclus. La mortalité à 28 jours était de 14 % (IC à 95 % : 11–17 %).';
    final r2 = reviewProject(ok);
    expect(find(r2, 'outcome_switch'), isNull);
    expect(find(r2, 'outcome_not_reported'), isNull);
    expect(find(r2, 'sample_attained_ok')!.level, ReviewLevel.ok);
    expect(find(r2, 'p_without_ci'), isNull);
  });
}
