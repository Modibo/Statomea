import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart' hide Step;

import 'protocol_document.dart';

/// Protocole d'un projet d'exemple (fictif, avec des erreurs de méthode volontaires) au format Word : titres de section
/// mis en forme ; c'est aussi le fichier proposé au téléchargement sur la page d'accueil.
Uint8List exampleProtocolDocx(ExampleProject e) {
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  String para(String t, {String? style}) =>
      '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}<w:r><w:t xml:space="preserve">${esc(t)}</w:t></w:r></w:p>';
  final headings = e.headings.toSet();
  final lines = e.text.trim().split('\n');
  final body = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    // La ligne qui suit « Titre du projet » est le titre lui-même.
    final isTitle = i > 0 && lines[i - 1] == e.headings.first;
    body.write(para(l, style: headings.contains(l) ? 'Heading1' : (isTitle ? 'Title' : null)));
  }
  return packDocx(body.toString());
}
