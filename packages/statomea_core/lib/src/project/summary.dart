/// Synthèse d'un projet pour le tableau de bord de l'encadrant : étapes terminées, relecture méthodologique, mode
/// tuteur, analyses du journal (nombre, dernière), effectif prévu et analysé, et un statut lisible d'un coup d'œil.
library;

import '../i18n.dart';
import '../pedagogy/tutor.dart';
import 'project.dart';
import 'review.dart';

class ProjectSummary {
  final Project project;
  final int stepsDone; // sur 10
  final int errors, warnings, missing;
  final int tutorSolved; // sur 10
  final int analyses;
  final String lastAnalysis; // nom de la dernière analyse
  final String lastDate; // AAAA-MM-JJ de la dernière analyse
  final int? planned, analysed;
  final int references;
  const ProjectSummary(this.project, this.stepsDone, this.errors, this.warnings, this.missing, this.tutorSolved, this.analyses, this.lastAnalysis,
      this.lastDate, this.planned, this.analysed, this.references);

  /// Statut : « à relire » s'il reste des erreurs, « en cours », « prêt pour la rédaction » (étapes 1 à 8 et aucune
  /// erreur), « terminé » (10 étapes).
  String get status {
    if (stepsDone >= 10) return tr('terminé', 'completed');
    if (errors > 0) return tr('à relire', 'to review');
    if (stepsDone >= 8) return tr('prêt pour la rédaction', 'ready for writing');
    if (stepsDone == 0 && analyses == 0) {
      if (project.protocol.isNotEmpty) return project.corrections.isEmpty ? tr('protocole importé', 'protocol imported') : tr('protocole relu', 'protocol reviewed');
      return tr('non commencé', 'not started');
    }
    return tr('en cours', 'in progress');
  }

  /// Points d'attention pour l'entretien avec l'étudiant.
  List<String> get attention => [
        if (errors > 0) tr('$errors erreur(s) de méthode à corriger', '$errors methodological error(s) to fix'),
        if (planned != null && analysed != null && analysed! < 0.8 * planned!) tr('effectif analysé $analysed / $planned prévus', 'analysed $analysed / $planned planned'),
        if (stepsDone >= 3 && tutorSolved < 3) tr('mode tuteur peu utilisé ($tutorSolved/10)', 'tutor mode little used ($tutorSolved/10)'),
        if (analyses > 0 && project.analysisPlan.trim().isEmpty) tr('analyses sans plan d\'analyse écrit', 'analyses without a written analysis plan'),
      ];
}

ProjectSummary summarizeProject(Project p) {
  final r = reviewProject(p);
  final journal = [for (final e in p.journal) if (!e.methodId.startsWith('describe')) e];
  final last = p.journal.isEmpty ? null : p.journal.last;
  final ds = p.dataset;
  return ProjectSummary(
    p,
    p.completed.length,
    r.count(ReviewLevel.error),
    r.count(ReviewLevel.warning),
    r.count(ReviewLevel.missing),
    tutorProgress(p).where((x) => x.solved).length,
    journal.length,
    last?.methodName ?? '',
    last == null ? '' : (last.timestamp.length >= 10 ? last.timestamp.substring(0, 10) : last.timestamp),
    int.tryParse(p.inferred['plannedSampleSize'] ?? ''),
    ds == null ? null : ds.rowCount - ds.excludedRows.length,
    p.references.length,
  );
}
