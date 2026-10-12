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
