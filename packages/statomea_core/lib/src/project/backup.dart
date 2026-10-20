/// Sauvegarde et partage sans serveur : tous les projets dans un seul fichier (chacun avec son empreinte d'intégrité,
/// restauré par l'import habituel), et partage d'un projet avec ou sans les données individuelles (pour l'encadrant).
library;

import 'dart:convert';

import '../i18n.dart';
import '../model/result.dart' show StatInputError;
import '../version.dart';
import 'project.dart';

/// Fichier de sauvegarde : liste des projets exportés (format d'export habituel, empreinte comprise).
String backupAllProjects(List<Project> projects, {required String date}) => const JsonEncoder.withIndent(' ').convert({
      'format': 'statomea-backup',
      'formatVersion': 1,
      'engine': '$engineName $engineVersion',
      'date': date,
      'projects': [for (final p in projects) p.encode()],
    });

/// Projets contenus dans une sauvegarde (textes d'export, à passer à l'import qui vérifie l'intégrité de chacun).
List<String> projectsInBackup(String text) {
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    throw StatInputError('backup_invalid', tr('Fichier de sauvegarde illisible.', 'Unreadable backup file.'));
  }
  if (j is! Map || j['format'] != 'statomea-backup' || j['projects'] is! List) {
    throw StatInputError('backup_invalid', tr('Ce fichier n\'est pas une sauvegarde Statoméa (un projet seul s\'importe avec « Importer un projet »).', 'This file is not a Statoméa backup (a single project is imported with "Import a project").'));
  }
  return [for (final p in j['projects'] as List) p as String];
}

/// Projet à partager : avec [includeData] faux, le fichier de données (valeurs individuelles) et les corrections sont
/// retirés ; restent la question, le protocole, les plans, la relecture, le journal (résultats agrégés), le texte.
String shareableProject(Project p, {bool includeData = true}) {
  if (includeData) return p.encode();
  final j = p.toJson()..['dataset'] = null;
  return Project.fromJson(j).encode();
}
