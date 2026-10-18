/// Projet : parcours en 10 étapes, données, journal des analyses, audit.
/// Sérialisable en JSON (stockage local et export reproductible).
library;

import 'dart:convert';

import '../i18n.dart';
import '../advisor/advisor.dart';
import '../data/dataset.dart';
import '../meta/meta.dart';
import '../model/result.dart';
import '../prediction/model_development.dart';
import '../version.dart';

enum Step { question, studyPlan, analysisPlan, dataControl, methodChoice, computation, diagnostics, interpretation, audit, export }

String stepLabel(Step s) => switch (s) {
      Step.question => tr('Question biomédicale', 'Biomedical question'),
      Step.studyPlan => tr("Plan d'étude", 'Study design'),
      Step.analysisPlan => tr("Plan d'analyse", 'Analysis plan'),
      Step.dataControl => tr('Contrôle des données', 'Data control'),
      Step.methodChoice => tr('Choix de la méthode', 'Method choice'),
      Step.computation => tr('Calcul', 'Computation'),
      Step.diagnostics => 'Diagnostics',
      Step.interpretation => tr('Interprétation', 'Interpretation'),
      Step.audit => 'Audit',
      Step.export => 'Export',
    };

/// Ce qu'on fait à chaque étape (brève description, affichée dans le guide de démarrage et le parcours du projet).
String stepHint(Step s) => switch (s) {
      Step.question => tr('Formuler la question (population, exposition, comparateur, critère de jugement) et déclarer le type de l\'issue et de l\'exposition : ces réponses guident tout le reste.',
          'State the question (population, exposure, comparator, outcome) and declare the type of the outcome and of the exposure: these answers guide everything else.'),
      Step.studyPlan => tr('Préciser le plan (essai randomisé, cohorte, cas-témoins, transversal) et l\'objectif (décrire, expliquer, diagnostiquer, prédire) : ils fixent les mesures d\'effet légitimes.',
          'Specify the design (randomized trial, cohort, case-control, cross-sectional) and the aim (describe, explain, diagnose, predict): they set the legitimate effect measures.'),
      Step.analysisPlan => tr('Écrire, avant de voir les résultats, l\'analyse principale, les facteurs d\'ajustement et les analyses de sensibilité prévues.',
          'Write, before seeing the results, the main analysis, the adjustment factors and the planned sensitivity analyses.'),
      Step.dataControl => tr('Importer les données (CSV ou Excel, avec un dictionnaire de variables si possible), repérer les anomalies et les corriger avec une justification ; les données d\'origine ne sont jamais modifiées.',
          'Import the data (CSV or Excel, with a variable dictionary if possible), spot anomalies and correct them with a justification; the original data are never modified.'),
      Step.methodChoice => tr('L\'assistant propose les méthodes adaptées à la question déclarée, avec leurs conditions ; s\'il manque une information, il pose la question.',
          'The assistant proposes the methods suited to the declared question, with their conditions; if information is missing, it asks.'),
      Step.computation => tr('Lancer la méthode choisie (calculateur ou atelier) ; chaque résultat est ajouté au journal du projet avec ses entrées.',
          'Run the chosen method (calculator or workshop); each result is added to the project log with its inputs.'),
      Step.diagnostics => tr('Vérifier les conditions d\'application (normalité, proportionnalité des risques, événements par variable…) et lire les alertes.',
          'Check the conditions of application (normality, proportional hazards, events per variable…) and read the alerts.'),
      Step.interpretation => tr('Lire l\'interprétation proposée et rédiger la vôtre : ce que le résultat permet de conclure, et ce qu\'il ne permet pas.',
          'Read the proposed interpretation and write your own: what the result allows you to conclude, and what it does not.'),
      Step.audit => tr('Faire relire votre texte par l\'audit contradictoire : OR lu comme un RR, langage causal, p mal interprétée, analyse annoncée mais non faite…',
          'Have your text reviewed by the adversarial audit: OR read as an RR, causal language, misread p-value, analysis announced but not done…'),
      Step.export => tr('Produire le rapport PDF ou HTML, le journal des analyses et le fichier du projet (.json) pour le partager ou l\'archiver.',
          'Produce the PDF or HTML report, the analysis log and the project file (.json) to share or archive it.'),
    };

/// Démarrer un nouveau projet.
String get guideNewProject => tr(
    'Nouveau projet : « Nouveau projet », puis écrire la question de recherche à l\'étape 1. Statoméa en déduit aussitôt le plan d\'étude, l\'objectif, le type d\'issue, la population, le critère de jugement, le plan d\'analyse et le calcul d\'effectif adapté ; ces éléments sont marqués « proposé » : les vérifier et les corriger. Suivre ensuite les étapes 1 à 10 dans l\'ordre ; les données (CSV ou Excel) s\'importent à l\'étape 4. Marquer chaque étape « Terminée » ; on peut revenir à une étape à tout moment.',
    'New project: "New project", then write the research question at step 1. Statoméa immediately infers the study design, aim, outcome type, population, outcome, analysis plan and the appropriate sample-size calculation; these are marked "proposed": check and correct them. Then follow steps 1 to 10 in order; data (CSV or Excel) are imported at step 4. Mark each step "Done"; you can return to any step at any time.');

/// Projet importé : protocole Word/PDF ou fichier de projet Statoméa.
String get guideImportedProject => tr(
    'Projet importé : « Importer un projet », puis choisir un protocole Word (.docx) ou PDF, ou un fichier de projet Statoméa (.json). Pour un protocole, Statoméa en lit le titre, la question, la population, le schéma, le critère de jugement, l\'effectif prévu et le plan d\'analyse, montre ce qu\'il a compris, puis crée le projet et ouvre la feuille de route des 10 étapes dans l\'ordre. Un fichier .json (exporté à l\'étape 10) restaure tout — question, plans, données, journal, texte — après un contrôle d\'intégrité.',
    'Imported project: "Import a project", then choose a Word (.docx) or PDF protocol, or a Statoméa project file (.json). For a protocol, Statoméa reads the title, question, population, design, outcome, planned sample size and analysis plan, shows what it understood, then creates the project and opens the roadmap of the 10 steps in order. A .json file (exported at step 10) restores everything — question, plans, data, log, text — after an integrity check.');

/// Relecture méthodologique et corrections.
String get guideReview => tr(
    'Relecture et corrections : bouton « Relire et corriger » (feuille de route, étape 1 ou icône de vérification dans un projet). Statoméa relit la question, le plan, le nombre de sujets (recalculé quand les hypothèses sont données) et le plan d\'analyse — pour un protocole importé, sur son propre texte — et classe les points en erreurs, à revoir et manquants, en citant le passage en cause. « Appliquer la correction » (ou toutes d\'un coup) corrige le projet ; chaque correction est tracée et reprise dans le protocole prérédigé. Rapport de relecture imprimable en PDF.',
    'Review and corrections: "Review and correct" button (roadmap, step 1 or the check icon in a project). Statoméa reviews the question, design, sample size (recomputed when the assumptions are given) and analysis plan — for an imported protocol, on its own text — and classifies points as errors, to review and missing, quoting the passage concerned. "Apply the correction" (or all at once) fixes the project; each correction is logged and included in the pre-drafted protocol. Review report printable as PDF.');

/// Feuille de route et protocole prérédigé.
String get guideRoadmap => tr(
    'Feuille de route : bouton « Feuille de route » (icône d\'itinéraire) dans un projet. Elle donne les 10 étapes, ce qui est fait, ce qui est proposé et ce qui reste à faire ; « Calculer l\'effectif » ouvre le bon calculateur ; « Imprimer / PDF » l\'imprime. « Protocole (Word) » et « Protocole (PDF) » produisent un protocole prérédigé en 13 rubriques (format comité d\'éthique) : les passages surlignés « [À compléter : …] » sont à rédiger par le chercheur.',
    'Roadmap: "Roadmap" button (route icon) in a project. It lists the 10 steps, what is done, what is proposed and what remains; "Compute the sample size" opens the right calculator; "Print / PDF" prints it. "Protocol (Word)" and "Protocol (PDF)" produce a pre-drafted protocol in 13 sections (ethics committee format): highlighted "[To complete: …]" passages are for the researcher to write.');

/// Empreinte FNV-1a 32 bits (identifie une version de données dans le journal).
String fingerprint(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// Entrée du journal de calcul : tout ce qu'il faut pour refaire l'analyse.
/// Correction issue de la relecture méthodologique, appliquée au projet.
class AppliedCorrection {
  final String id; // identifiant du contrôle
  final String title;
  final String date; // AAAA-MM-JJ
  final String detail; // ce qui a été modifié
  const AppliedCorrection({required this.id, required this.title, required this.date, this.detail = ''});
  Map<String, Object?> toJson() => {'id': id, 'title': title, 'date': date, if (detail.isNotEmpty) 'detail': detail};
  factory AppliedCorrection.fromJson(Map<String, Object?> j) =>
      AppliedCorrection(id: j['id'] as String, title: (j['title'] as String?) ?? '', date: (j['date'] as String?) ?? '', detail: (j['detail'] as String?) ?? '');
}

class JournalEntry {
  final String id;
  final String timestamp;
  final String methodId;
  final String methodName;
  final String datasetFingerprint;
  final List<String> correctionIds;
  final Map<String, Object?> options;
  final Map<String, Object?> result; // AnalysisResult.toJson()
  final String userNote;

  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.methodId,
    required this.methodName,
    this.datasetFingerprint = '',
    this.correctionIds = const [],
    this.options = const {},
    required this.result,
    this.userNote = '',
  });

  factory JournalEntry.fromResult(AnalysisResult r,
          {required String id, required String timestamp, Dataset? data, Map<String, Object?> options = const {}, String note = ''}) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        methodId: r.methodId,
        methodName: r.methodName,
        datasetFingerprint: data == null ? '' : fingerprint(jsonEncode(data.original)),
        correctionIds: data == null ? const [] : [for (final c in data.corrections) c.id],
        options: options,
        result: r.toJson(),
        userNote: note,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'methodId': methodId,
        'methodName': methodName,
        'datasetFingerprint': datasetFingerprint,
        'correctionIds': correctionIds,
        'options': options,
        'result': result,
        'userNote': userNote,
        'engine': '$engineName $engineVersion',
      };

  factory JournalEntry.fromJson(Map<String, Object?> j) => JournalEntry(
        id: j['id'] as String,
        timestamp: j['timestamp'] as String,
        methodId: j['methodId'] as String,
        methodName: j['methodName'] as String,
        datasetFingerprint: (j['datasetFingerprint'] as String?) ?? '',
        correctionIds: [for (final c in (j['correctionIds'] as List? ?? [])) c as String],
        options: ((j['options'] as Map?) ?? {}).cast<String, Object?>(),
        result: (j['result'] as Map).cast<String, Object?>(),
        userNote: (j['userNote'] as String?) ?? '',
      );
}

/// Rôles des variables du projet (déclarés une fois à l'étape 5) : ils préremplissent les calculateurs.
class VariableRoles {
  final String? outcome, eventLevel, exposure, time, status, subject;
  final List<String> covariates;
  const VariableRoles({this.outcome, this.eventLevel, this.exposure, this.time, this.status, this.subject, this.covariates = const []});

  bool get isEmpty => outcome == null && exposure == null && time == null && status == null && subject == null && covariates.isEmpty;

  /// Rôles limités aux variables présentes dans [ds] (une variable renommée ou supprimée est ignorée).
  VariableRoles validFor(Dataset? ds) {
    if (ds == null) return const VariableRoles();
    String? ok(String? v) => v != null && ds.names.contains(v) ? v : null;
    final st = ok(status) ?? ok(outcome);
    return VariableRoles(
      outcome: ok(outcome),
      eventLevel: eventLevel != null && st != null && ds.levels(st).contains(eventLevel) ? eventLevel : null,
      exposure: ok(exposure),
      time: ok(time),
      status: ok(status),
      subject: ok(subject),
      covariates: [for (final c in covariates) if (ds.names.contains(c) && c != outcome && c != exposure) c],
    );
  }

  VariableRoles copyWith({String? outcome, String? eventLevel, String? exposure, String? time, String? status, String? subject, List<String>? covariates, bool clearEvent = false}) =>
      VariableRoles(
          outcome: outcome ?? this.outcome,
          eventLevel: clearEvent ? null : (eventLevel ?? this.eventLevel),
          exposure: exposure ?? this.exposure,
          time: time ?? this.time,
          status: status ?? this.status,
          subject: subject ?? this.subject,
          covariates: covariates ?? this.covariates);

  Map<String, Object?> toJson() => {
        'outcome': ?outcome,
        'eventLevel': ?eventLevel,
        'exposure': ?exposure,
        'time': ?time,
        'status': ?status,
        'subject': ?subject,
        if (covariates.isNotEmpty) 'covariates': covariates,
      };

  factory VariableRoles.fromJson(Map<String, Object?> j) => VariableRoles(
      outcome: j['outcome'] as String?,
      eventLevel: j['eventLevel'] as String?,
      exposure: j['exposure'] as String?,
      time: j['time'] as String?,
      status: j['status'] as String?,
      subject: j['subject'] as String?,
      covariates: [for (final c in (j['covariates'] as List? ?? [])) c as String]);
}

class Project {
  final String id;
  String title;
  final String createdAt;
  ResearchQuestion question;
  String analysisPlan;
  Dataset? dataset;
  List<Study> studies;
  PredictionSpec? predictionSpec;
  final List<JournalEntry> journal;
  String resultsText;
  Set<Step> completed;
  bool expertMode;

  /// Réponses aux grilles TRIPOD+AI / PROBAST+AI / PRISMA : « grille:item » → réponse.
  Map<String, String> checklistAnswers;

  /// Projet de démonstration (données simulées ou publiques).
  final String demoNotice;

  /// Rôles des variables (issue, exposition, ajustement…) : préremplissent les calculateurs.
  VariableRoles roles;

  /// Valeurs déduites automatiquement du texte de la question (champ → valeur) : affichées comme « déduites » et
  /// recalculées si le texte change, tant que le chercheur ne les a pas modifiées.
  Map<String, String> inferred;

  /// Rubriques du protocole importé (texte intégral, clé → texte) : base de la relecture méthodologique.
  Map<String, String> protocol;

  /// Corrections appliquées depuis la relecture méthodologique (traçabilité).
  final List<AppliedCorrection> corrections;

  Project({
    required this.id,
    required this.title,
    required this.createdAt,
    this.question = const ResearchQuestion(),
    this.analysisPlan = '',
    this.dataset,
    List<Study>? studies,
    this.predictionSpec,
    List<JournalEntry>? journal,
    this.resultsText = '',
    Set<Step>? completed,
    this.expertMode = false,
    this.demoNotice = '',
    Map<String, String>? checklistAnswers,
    this.roles = const VariableRoles(),
    Map<String, String>? inferred,
    Map<String, String>? protocol,
    List<AppliedCorrection>? corrections,
  })  : inferred = inferred ?? {},
        protocol = protocol ?? {},
        corrections = corrections ?? [],
        checklistAnswers = checklistAnswers ?? {},
        studies = studies ?? [],
        journal = journal ?? [],
        completed = completed ?? {};

  Map<String, Object?> toJson() => {
        'format': 'statomea-project',
        'formatVersion': 1,
        'engine': '$engineName $engineVersion',
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'question': question.toJson(),
        'analysisPlan': analysisPlan,
        'dataset': dataset?.toJson(),
        'studies': [for (final s in studies) s.toJson()],
        'predictionSpec': predictionSpec?.toJson(),
        'journal': [for (final e in journal) e.toJson()],
        'resultsText': resultsText,
        'completed': [for (final s in completed) s.name],
        'expertMode': expertMode,
        'demoNotice': demoNotice,
        'checklistAnswers': checklistAnswers,
        if (!roles.isEmpty) 'roles': roles.toJson(),
        if (inferred.isNotEmpty) 'inferred': inferred,
        if (protocol.isNotEmpty) 'protocol': protocol,
        if (corrections.isNotEmpty) 'corrections': [for (final c in corrections) c.toJson()],
      };

  factory Project.fromJson(Map<String, Object?> j) => Project(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAt: (j['createdAt'] as String?) ?? '',
        question: j['question'] == null ? const ResearchQuestion() : ResearchQuestion.fromJson((j['question'] as Map).cast()),
        analysisPlan: (j['analysisPlan'] as String?) ?? '',
        dataset: j['dataset'] == null ? null : Dataset.fromJson((j['dataset'] as Map).cast()),
        studies: [for (final s in (j['studies'] as List? ?? [])) Study.fromJson((s as Map).cast())],
        predictionSpec: j['predictionSpec'] == null ? null : PredictionSpec.fromJson((j['predictionSpec'] as Map).cast()),
        journal: [for (final e in (j['journal'] as List? ?? [])) JournalEntry.fromJson((e as Map).cast())],
        resultsText: (j['resultsText'] as String?) ?? '',
        completed: {for (final s in (j['completed'] as List? ?? [])) Step.values.byName(s as String)},
        expertMode: (j['expertMode'] as bool?) ?? false,
        demoNotice: (j['demoNotice'] as String?) ?? '',
        checklistAnswers: ((j['checklistAnswers'] as Map?) ?? {}).cast<String, String>(),
        roles: j['roles'] == null ? const VariableRoles() : VariableRoles.fromJson((j['roles'] as Map).cast()),
        inferred: ((j['inferred'] as Map?) ?? {}).cast<String, String>(),
        protocol: ((j['protocol'] as Map?) ?? {}).cast<String, String>(),
        corrections: [for (final c in (j['corrections'] as List? ?? [])) AppliedCorrection.fromJson((c as Map).cast())],
      );

  /// JSON exporté, avec une empreinte d'intégrité (voir `projectChecksum`).
  String encode() {
    final j = toJson();
    return const JsonEncoder.withIndent('  ').convert({...j, 'checksum': fingerprint(jsonEncode(j))});
  }

  /// Même contenu et même empreinte que [encode], sans indentation : pour le stockage local (moitié moins de place ;
  /// le stockage du navigateur est limité à quelques Mo). [encode] reste réservé à l'export lisible.
  String encodeCompact() {
    final j = toJson();
    return jsonEncode({...j, 'checksum': fingerprint(jsonEncode(j))});
  }
  static Project decode(String s) => Project.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
}
