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
    'Nouveau projet : « Nouveau projet », puis suivre les étapes 1 à 10 dans l\'ordre. Les données (CSV ou Excel) s\'importent à l\'étape 4. Marquer chaque étape « Terminée » pour suivre l\'avancement ; on peut revenir à une étape à tout moment.',
    'New project: "New project", then follow steps 1 to 10 in order. Data (CSV or Excel) are imported at step 4. Mark each step "Done" to track progress; you can return to any step at any time.');

/// Reprendre un projet importé.
String get guideImportedProject => tr(
    'Projet importé : « Importer » un fichier de projet (.json) exporté depuis Statoméa (étape 10). Tout est restauré — question, plans, données et corrections, journal, texte — après un contrôle d\'intégrité. Reprendre à l\'étape en cours ; si les données ou le texte changent, refaire les calculs puis relancer l\'audit.',
    'Imported project: "Import" a project file (.json) exported from Statoméa (step 10). Everything is restored — question, plans, data and corrections, log, text — after an integrity check. Resume at the current step; if the data or the text change, redo the computations and run the audit again.');

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
  })  : checklistAnswers = checklistAnswers ?? {},
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
