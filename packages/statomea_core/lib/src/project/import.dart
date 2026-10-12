/// Import d'un projet exporté (« Projet complet (JSON) »).
///
/// L'import ne recalcule rien : il relit le projet tel qu'il a été exporté et
/// dit ce qui peut et ne peut pas être garanti — fichier modifié depuis
/// l'export, version du moteur, langue des résultats, journal calculé sur des
/// données absentes du fichier. Un identifiant déjà présent sur l'appareil
/// n'est jamais écrasé : le projet importé reçoit un nouvel identifiant.
library;

import 'dart:convert';

import '../i18n.dart';
import '../model/result.dart';
import '../version.dart';
import 'project.dart';

/// Version la plus récente du format de projet que ce moteur sait lire.
const int projectFormatVersion = 1;

/// Empreinte d'intégrité d'un projet exporté : FNV-1a du JSON compact, sans
/// le champ `checksum`. Elle détecte une modification accidentelle ou une
/// édition à la main, pas une falsification délibérée (FNV n'est pas une
/// fonction cryptographique).
String projectChecksum(Map<String, Object?> json) => fingerprint(jsonEncode({...json}..remove('checksum')));

class ProjectImport {
  final Project project;

  /// Constats sur le fichier importé, du plus grave au moins grave.
  final List<Alert> notes;

  /// Identifiant d'origine, si le projet a dû être renommé.
  final String? originalId;
  ProjectImport(this.project, this.notes, {this.originalId});
}

/// Lit un projet exporté. [existingIds] : identifiants déjà présents sur
/// l'appareil ; [newId] fournit un identifiant de remplacement en cas de
/// collision (l'application passe un identifiant horodaté).
ProjectImport importProject(String text, {Set<String> existingIds = const {}, String Function()? newId}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw StatInputError('import_not_json', tr('Fichier illisible : ce n\'est pas du JSON (${e.message}).', 'Unreadable file: this is not JSON (${e.message}).'));
  }
  if (decoded is! Map) {
    throw StatInputError('import_not_project', tr('Ce fichier JSON ne contient pas un projet Statoméa.', 'This JSON file does not contain a Statoméa project.'));
  }
  final j = decoded.cast<String, Object?>();
  final format = j['format'];
  if (format == 'statomea-journal') {
    throw StatInputError(
        'import_journal',
        tr('Ce fichier est un journal de calcul : il ne contient pas les données. Seul l\'export « Projet complet (JSON) » peut être importé.',
            'This file is a computation log: it does not contain the data. Only the "Full project (JSON)" export can be imported.'));
  }
  if (format != 'statomea-project') {
    throw StatInputError('import_not_project', tr('Ce fichier JSON ne contient pas un projet Statoméa.', 'This JSON file does not contain a Statoméa project.'));
  }
  final version = j['formatVersion'];
  if (version is! int || version > projectFormatVersion) {
    throw StatInputError(
        'import_format_version',
        tr('Format de projet $version produit par une version plus récente de Statoméa (${j['engine'] ?? '?'}) : mettre à jour l\'application.',
            'Project format $version produced by a newer version of Statoméa (${j['engine'] ?? '?'}): update the application.'));
  }

  Project p;
  try {
    p = Project.fromJson(j);
  } catch (e) {
    throw StatInputError('import_invalid',
        tr('Le projet est incomplet ou endommagé et ne peut pas être relu ($e).', 'The project is incomplete or damaged and cannot be read ($e).'));
  }

  final notes = <Alert>[];

  // Intégrité du fichier.
  final sum = j['checksum'];
  if (sum == null) {
    notes.add(Alert('import_no_checksum', Severity.info,
        tr('Fichier sans empreinte d\'intégrité (exporté avant la version 1.9.0) : une modification après l\'export ne peut pas être détectée.',
            'File without an integrity fingerprint (exported before version 1.9.0): a change after export cannot be detected.')));
  } else if (sum != projectChecksum(j)) {
    notes.add(Alert('import_modified', Severity.serious,
        tr('Le fichier a été modifié après l\'export : données, journal ou textes peuvent ne plus correspondre aux calculs enregistrés.',
            'The file was changed after export: data, log or texts may no longer match the recorded calculations.'),
        suggestion: tr('Relancer les analyses dans le projet importé avant de citer un résultat.', 'Rerun the analyses in the imported project before citing a result.')));
  }

  // Version du moteur.
  final engine = (j['engine'] as String?) ?? '';
  if (engine.isNotEmpty && engine != '$engineName $engineVersion') {
    notes.add(Alert('import_engine', Severity.info,
        tr('Projet exporté par $engine (moteur actuel : $engineName $engineVersion). Les résultats du journal sont affichés tels qu\'ils ont été calculés, sans être recalculés.',
            'Project exported by $engine (current engine: $engineName $engineVersion). The log results are shown as they were computed, without being recomputed.')));
  }

  // Journal : données d'origine présentes dans le fichier ?
  if (p.journal.isNotEmpty) {
    final fp = p.dataset == null ? null : fingerprint(jsonEncode(p.dataset!.original));
    final other = [for (final e in p.journal) if (e.datasetFingerprint.isNotEmpty && e.datasetFingerprint != fp) e.id];
    if (other.isNotEmpty) {
      notes.add(Alert('import_other_data', Severity.info,
          tr('${other.length} calcul(s) du journal (${other.take(5).join(", ")}${other.length > 5 ? "…" : ""}) portent sur d\'autres données que le jeu enregistré (sous-ensemble, cohorte externe) : ils ne peuvent pas être refaits à partir de ce seul fichier.',
              '${other.length} log computation(s) (${other.take(5).join(", ")}${other.length > 5 ? "…" : ""}) use data other than the stored dataset (subset, external cohort): they cannot be redone from this file alone.')));
    }
    final langs = {for (final e in p.journal) e.result['lang'] ?? 'fr'};
    if (langs.any((l) => l != currentLang.name)) {
      notes.add(Alert('import_lang', Severity.info,
          tr('Des résultats du journal ont été rédigés dans une autre langue ; ils restent dans leur langue de calcul.',
              'Some log results were written in another language; they stay in the language they were computed in.')));
    }
  }

  // Identifiant déjà utilisé : jamais d'écrasement.
  String? originalId;
  if (existingIds.contains(p.id)) {
    originalId = p.id;
    final id = newId?.call() ?? '${p.id}-import';
    p = Project.fromJson({...j, 'id': id, 'title': tr('${p.title} (import)', '${p.title} (imported)')});
    notes.add(Alert('import_id', Severity.caution,
        tr('Un projet portant le même identifiant existe déjà sur cet appareil : la copie importée est enregistrée à part, sans le remplacer.',
            'A project with the same identifier already exists on this device: the imported copy is saved separately, without replacing it.')));
  }
  notes.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return ProjectImport(p, notes, originalId: originalId);
}
