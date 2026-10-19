import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

/// Masque de saisie Excel (.xlsx) : parties XML du moteur, zippées.
Uint8List crfWorkbook(List<CrfField> fields, {String title = ''}) {
  final zip = Archive();
  for (final e in crfWorkbookParts(fields, title: title).entries) {
    final b = utf8.encode(e.value);
    zip.addFile(ArchiveFile(e.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}
