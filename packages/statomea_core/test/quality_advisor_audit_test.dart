import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  group('Contrôle des données', () {
    final csv = '''id;age;sexe;glycemie;statut;hb_avant;hb_apres
1;45;F;5,4;Oui;12,1;12,5
2;52;H;6,1;oui ;11,0;11,9
3;250;F;98;Non;13,2;13,0
4;38;F;<0,5;Non;10,5;11,2
5;61;H;5,9;Non;;12,0
6;47;F;5,2;Non;12,8;12,9
6;47;F;5,2;Non;12,8;12,9
''';
    final ds = parseCsv(csv).dataset;
    final r = checkQuality(ds, predictors: ['sexe']);
    final codes = r.issues.map((i) => i.code).toList();
    test('identifiant répété, doublons, valeur impossible, non numérique, libellés incohérents, appariement', () {
      expect(codes, containsAll(['repeated_id', 'duplicate_rows', 'out_of_range', 'non_numeric', 'inconsistent_labels', 'paired_wide', 'missing', 'reference_undefined']));
      final nn = r.issues.firstWhere((i) => i.code == 'non_numeric');
      expect(nn.suggestion, contains('censurées'));
    });
    test('les données importées ne sont jamais modifiées par le contrôle', () {
      expect(ds.original[2][1], '250');
      expect(ds.corrections, isEmpty);
    });
    test('correction journalisée appliquée sur une copie', () {
      final c = const Correction(id: 'c1', variable: 'age', action: 'set_missing', rows: [2], from: '250', reason: 'âge impossible, source illisible');
      final ds2 = ds.applyCorrection(c);
      expect(ds2.numeric('age')[2], isNull);
      expect(ds.numeric('age')[2], 250);
      expect(ds2.original[2][1], '250');
      expect(ds2.corrections.single.describe(), contains('âge impossible'));
    });
    test('mélange d\'unités suspecté (mmol/L et mg/dL)', () {
      final vals = [for (var i = 0; i < 30; i++) '${5 + (i % 7) * 0.3}'.replaceAll('.', ','), for (var i = 0; i < 6; i++) '${95 + i * 4}'];
      final d = Dataset(['glucose'], [for (final v in vals) [v]]);
      expect(checkQuality(d).issues.map((i) => i.code), contains('unit_mix_suspected'));
    });
    test('événements rares et cellule nulle avec l\'issue', () {
      final rows = [for (var i = 0; i < 40; i++) ['${i < 3 ? 1 : 0}', i < 20 ? 'A' : 'B']];
      final d = Dataset(['y', 'grp'], rows);
      final q = checkQuality(d, outcome: 'y', predictors: ['grp']).issues.map((i) => i.code);
      expect(q, containsAll(['rare_events', 'zero_cell']));
    });
    test('dénominateurs discordants', () {
      final d = Dataset(['cas', 'total'], [['5', '40'], ['12', '10']]);
      expect(checkDenominators(d, 'cas', 'total').single.severity, Severity.critical);
    });
  });

  group('Assistant de choix', () {
    test('information insuffisante : pose des questions au lieu de choisir', () {
      final a = advise(const ResearchQuestion(text: 'Le tabac est-il lié à l\'HTA ?'));
      expect(a.needsMoreInformation, isTrue);
      expect(a.questions.map((q) => q.field), containsAll(['objective', 'dataLevel', 'outcomeType']));
      expect(a.options.where((o) => o.recommended), isEmpty);
    });
    test('cohorte, issue binaire, ajustement → Poisson robuste recommandé, logistique en alternative', () {
      final a = advise(const ResearchQuestion(
          objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          outcomeType: OutcomeType.binary, exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true));
      expect(a.options.firstWhere((o) => o.recommended).methodId, 'poisson_robust');
      expect(a.options.map((o) => o.methodId), contains('logistic_regression'));
      expect(a.notes.join(), contains('causal'));
    });
    test('cas-témoins → OR uniquement', () {
      final a = advise(const ResearchQuestion(
          objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.caseControl,
          outcomeType: OutcomeType.binary, exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true));
      expect(a.options.map((o) => o.methodId), isNot(contains('poisson_robust')));
      expect(a.options.first.methodId, 'logistic_regression');
    });
    test('données appariées binaires → McNemar ; continues → t apparié / Wilcoxon', () {
      const base = ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          exposureType: ExposureType.binary, pairing: Pairing.paired, needsAdjustment: false);
      expect(advise(base.copyWith(outcomeType: OutcomeType.binary)).options.single.methodId, 'mcnemar');
      expect(advise(base.copyWith(outcomeType: OutcomeType.continuous)).options.map((o) => o.methodId), ['paired_t_test', 'wilcoxon_signed_rank']);
    });
    test('deux groupes, normalité inconnue → les deux options et une question', () {
      final a = advise(const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.rct,
          outcomeType: OutcomeType.continuous, exposureType: ExposureType.binary, pairing: Pairing.independent));
      expect(a.options.map((o) => o.methodId), containsAll(['t_test_welch', 'mann_whitney']));
      expect(a.questions.map((q) => q.field), contains('approxNormal'));
    });
    test('accord entre méthodes → Bland-Altman ; survie → Cox recommandé', () {
      final ag = advise(const ResearchQuestion(agreementQuestion: true, objective: StudyObjective.descriptive, dataLevel: DataLevel.individual)).options;
      expect(ag.map((o) => o.methodId), ['bland_altman', 'passing_bablok', 'deming']);
      expect(ag.where((o) => o.recommended).single.methodId, 'bland_altman');
      // Traitement binaire en cohorte, ajustement : score de propension proposé en alternative.
      final ps = advise(const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          outcomeType: OutcomeType.binary, exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true));
      expect(ps.options.map((o) => o.methodId), containsAll(['propensity_matching', 'propensity_weighting']));
      expect(ps.options.firstWhere((o) => o.recommended).methodId, 'poisson_robust');
      final cox = advise(const ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          outcomeType: OutcomeType.timeToEvent, exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true));
      expect(cox.options.map((o) => o.methodId), ['kaplan_meier', 'cox']);
      expect(cox.options.firstWhere((o) => o.recommended).methodId, 'cox');
    });
    test('assistant enrichi : mesures répétées, comptages, ordinal, nominal, risques concurrents, temps immortel', () {
      const base = ResearchQuestion(objective: StudyObjective.explanatory, dataLevel: DataLevel.individual, design: StudyDesign.cohort,
          exposureType: ExposureType.binary, pairing: Pairing.independent, needsAdjustment: true);
      List<String> ids(ResearchQuestion q) => [for (final o in advise(q).options) o.methodId];
      String? rec(ResearchQuestion q) => advise(q).options.where((o) => o.recommended).map((o) => o.methodId).firstOrNull;
      // Mesures répétées : modèle mixte (quantitative), GEE (binaire, comptage) ; plus de « hors V1 ».
      final rep = base.copyWith(pairing: Pairing.repeated);
      expect(ids(rep.copyWith(outcomeType: OutcomeType.continuous)), ['lmm_longitudinal', 'gee']);
      expect(rec(rep.copyWith(outcomeType: OutcomeType.binary)), 'gee');
      expect(ids(rep.copyWith(outcomeType: OutcomeType.binary)), contains('glmm_longitudinal'));
      expect(rec(rep.copyWith(outcomeType: OutcomeType.count)), 'gee');
      expect(advise(rep.copyWith(outcomeType: OutcomeType.continuous)).notes.join(' '), isNot(contains('hors')));
      // Comptages, ordinal ajusté, nominal ajusté.
      expect(rec(base.copyWith(outcomeType: OutcomeType.count)), 'count_regression');
      expect(rec(base.copyWith(outcomeType: OutcomeType.ordinal)), 'ordinal_logistic');
      expect(rec(base.copyWith(outcomeType: OutcomeType.categorical)), 'multinomial_logistic');
      // Survie : l'assistant demande s'il y a un événement concurrent et si l'exposition change pendant le suivi.
      final surv = base.copyWith(outcomeType: OutcomeType.timeToEvent);
      expect(advise(surv).questions.map((c) => c.field), containsAll(['competingRisk', 'timeVaryingExposure']));
      final cr = surv.copyWith(competingRisk: true, timeVaryingExposure: false);
      expect(ids(cr), ['cumulative_incidence', 'fine_gray', 'kaplan_meier', 'cox']);
      expect(rec(cr), 'fine_gray');
      expect(rec(cr.copyWith(needsAdjustment: false)), 'cumulative_incidence');
      final tv = surv.copyWith(competingRisk: false, timeVaryingExposure: true);
      expect(advise(tv).options.firstWhere((o) => o.methodId == 'cox').cautions.join(' '), contains('temps immortel'));
      expect(advise(tv).questions, isEmpty);
      // Description d'une survie avec événement concurrent.
      expect(rec(const ResearchQuestion(objective: StudyObjective.descriptive, dataLevel: DataLevel.individual, outcomeType: OutcomeType.timeToEvent, competingRisk: true)), 'cumulative_incidence');
      // Sérialisation des nouveaux champs.
      expect(ResearchQuestion.fromJson(cr.toJson()).competingRisk, isTrue);
    });
    test('matrice question → méthode générée depuis le registre', () {
      final md = methodMatrixMarkdown();
      expect(md, contains('| Question |'));
      // Statut lu dans le registre (toutes les méthodes de la V1 sont validées depuis la 1.7.0).
      expect(md, contains('| validée |'));
      expect(methodRegistry.where((m) => m.status == MethodStatus.validated).length, greaterThanOrEqualTo(20));
    });
  });

  group('Audit contradictoire (corpus annoté)', () {
    final logit = twoByTwo(120, 380, 80, 420, design: StudyDesign.cohort);
    final ba = blandAltman([5.1, 6.3, 4.8, 7.7, 6.0, 5.5, 8.1], [4.9, 6.8, 4.5, 7.1, 6.4, 5.0, 8.6]);
    const cohort = ResearchQuestion(design: StudyDesign.cohort, objective: StudyObjective.explanatory, pairing: Pairing.independent);
    List<AuditFinding> alertsFor(AuditFamily fam, String text, {ResearchQuestion q = cohort, List<AnalysisResult>? res}) =>
        runAudit(question: q, results: res ?? [logit], text: text).of(fam).where((f) => f.status == AuditStatus.alert).toList();

    final orVal = fmt(logit.estimate('Odds ratio (Woolf)')!.value);
    final positives = <(AuditFamily, String)>[
      (AuditFamily.orAsRr, 'Les exposés avaient un risque 1,66 fois plus élevé (OR = $orVal).'),
      (AuditFamily.orAsRr, 'L\'exposition multiplie le risque par $orVal.'),
      (AuditFamily.pValueMisread, 'Avec p = 0,03, il y a 97 % de chances que l\'effet soit réel.'),
      (AuditFamily.pValueMisread, 'La valeur p = 0,04 signifie que la probabilité que l\'hypothèse nulle soit vraie est de 4 %.'),
      (AuditFamily.pValueMisread, 'Le résultat était non significatif (p = 0,21) : il n\'y a donc pas de différence entre les groupes.'),
      (AuditFamily.pValueMisread, 'On observe une tendance à la significativité (p = 0,07).'),
      (AuditFamily.causalLanguage, 'Le tabagisme entraîne une hypertension chez ces patients.'),
      (AuditFamily.causalLanguage, 'L\'activité physique protège contre le diabète.'),
      (AuditFamily.announcedNotDone, 'Une analyse de sensibilité a confirmé la robustesse des résultats.'),
      (AuditFamily.announcedNotDone, 'Les données manquantes ont été traitées par imputation multiple.'),
      (AuditFamily.predictionOverclaim, 'Le score est validé et utilisable en pratique clinique.'),
      (AuditFamily.overPrecision, 'Ces résultats prouvent que l\'exposition est délétère.'),
      (AuditFamily.overPrecision, 'Le risque était de 0,234567 dans le groupe exposé.'),
    ];
    for (final (fam, s) in positives) {
      test('détecte [${auditFamilyLabel(fam)}] : $s', () {
        final a = alertsFor(fam, s);
        expect(a, isNotEmpty);
        expect(a.first.trigger, isNotNull);
        expect(a.first.correction, isNotNull);
      });
    }
    test('détecte une limite d\'accord présentée comme IC', () {
      final lo = ba.estimates[1].value, hi = ba.estimates[2].value;
      final t = 'Les deux méthodes concordent (intervalle de confiance à 95 % : ${fmt(lo)} à ${fmt(hi)}).';
      expect(alertsFor(AuditFamily.agreementVsCi, t, res: [ba]), isNotEmpty);
    });
    final negatives = <String>[
      'La cote de l\'événement était $orVal fois plus élevée chez les exposés (OR = $orVal ; IC à 95 % : 1,23 à 2,25).',
      'Le tabagisme était associé à une hypertension plus fréquente.',
      'L\'IC à 95 % de la différence (−0,8 à 2,1) inclut 0 : les données ne permettent pas de conclure.',
      'Les résultats suggèrent une association compatible avec l\'hypothèse étudiée.',
    ];
    for (final s in negatives) {
      test('aucune fausse alerte grave : $s', () {
        final r = runAudit(question: cohort, results: [logit], text: s);
        expect(r.alerts.where((a) => a.severity.index >= Severity.serious.index && a.lexical), isEmpty,
            reason: r.alerts.map((a) => a.message).join(' | '));
      });
    }
    test('information insuffisante plutôt que supposition', () {
      final r = runAudit(question: const ResearchQuestion(), results: [logit], text: '');
      for (final fam in [AuditFamily.methodDesign, AuditFamily.causalLanguage, AuditFamily.pValueMisread]) {
        expect(r.of(fam).first.status, AuditStatus.insufficient, reason: fam.name);
      }
      final r2 = runAudit(question: const ResearchQuestion(), results: [logit], text: 'Le tabac entraîne une HTA.');
      expect(r2.of(AuditFamily.causalLanguage).single.status, AuditStatus.insufficient);
    });
    test('incompatibilités structurées : RR en cas-témoins, test indépendant sur données appariées', () {
      final cc = const ResearchQuestion(design: StudyDesign.caseControl);
      final r = runAudit(question: cc, results: [twoByTwo(30, 70, 15, 85, design: StudyDesign.cohort)]);
      expect(r.of(AuditFamily.methodDesign).any((f) => f.status == AuditStatus.alert && f.severity == Severity.serious), isTrue);
      final paired = const ResearchQuestion(design: StudyDesign.cohort, pairing: Pairing.paired);
      final r2 = runAudit(question: paired, results: [tTestIndependent([1, 2, 3, 4.5], [2, 3, 4, 6])]);
      expect(r2.of(AuditFamily.methodDesign).first.status, AuditStatus.alert);
    });
    test('chaque famille produit au moins un constat', () {
      final r = runAudit(question: cohort, results: [logit], text: 'Texte neutre.');
      for (final fam in AuditFamily.values) {
        expect(r.of(fam), isNotEmpty, reason: fam.name);
      }
    });
  });
}
