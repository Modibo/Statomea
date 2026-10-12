import 'dart:typed_data';

import 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Enregistre un fichier : téléchargement sur le web, dossier Documents de
/// l'application ailleurs. Retourne une description de l'emplacement.
Future<String> saveFile(String name, Uint8List bytes, String mime) => impl.saveFile(name, bytes, mime);
