import 'dart:typed_data';

import 'package:statomea_core/statomea_core.dart' hide Step;

import 'protocol_document.dart';

/// Nom du fichier Word du protocole d'exemple (proposé aussi au téléchargement sur la page d'accueil).
String get exampleProtocolFileName => tr('protocole-exemple-aghbs.docx', 'example-protocol-hbsag.docx');

/// Nom du fichier de données simulées qui accompagne le protocole d'exemple.
String get exampleDataFileName => tr('exemple-donnees-aghbs.csv', 'example-data-hbsag.csv');

/// Protocole d'exemple (fictif, avec des erreurs de méthode volontaires) au format Word : titres de section mis en forme.
Uint8List exampleProtocolDocx() {
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  String para(String t, {String? style}) =>
      '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}<w:r><w:t xml:space="preserve">${esc(t)}</w:t></w:r></w:p>';
  final headings = exampleHeadings.toSet();
  final lines = exampleProtocolText.trim().split('\n');
  final body = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    // La ligne qui suit « Titre du projet » est le titre lui-même.
    final isTitle = i > 0 && lines[i - 1] == exampleHeadings.first;
    body.write(para(l, style: headings.contains(l) ? 'Heading1' : (isTitle ? 'Title' : null)));
  }
  return packDocx(body.toString());
}
