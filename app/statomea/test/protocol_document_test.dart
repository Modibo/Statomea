import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/pdf_export.dart';
import 'package:statomea/services/protocol_document.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Project _project() {
  const t = 'Essai randomisé : la vitamine D réduit-elle la pression artérielle à 12 mois chez les adultes hypertendus ?';
  final p = Project(id: 'pr', title: 'Vitamine D & HTA', createdAt: '', question: applyInference(const ResearchQuestion(text: t), inferQuestion(t)).$1);
  p.analysisPlan = draftAnalysisPlan(p.question);
  return p;
}

void main() {
  test('protocole Word : paquet .docx complet, XML bien formé (vérifié par Python), relu à l\'identique', () async {
    final bytes = protocolDocx(_project());
    final zip = ZipDecoder().decodeBytes(bytes);
    expect([for (final f in zip.files) f.name], containsAll(['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/_rels/document.xml.rels', 'word/styles.xml']));
    final dir = await Directory.systemTemp.createTemp('statomea_docx');
    final file = File('${dir.path}/protocole.docx')..writeAsBytesSync(bytes);
    final check = await Process.run('python3', ['-c', 'import sys,zipfile,xml.dom.minidom as m\nz=zipfile.ZipFile(sys.argv[1])\n[m.parseString(z.read(n)) for n in z.namelist()]\nprint("ok")', file.path]);
    expect('${check.stdout}'.trim(), 'ok', reason: '${check.stderr}');
    final text = docxText(bytes);
    expect(text, contains('Protocole de recherche'));
    expect(text, contains('Vitamine D & HTA'));
    expect(text, contains('1. Identification'));
    expect(text, contains('[À compléter : critères d\'inclusion]'));
    expect(text.indexOf('Nombre de sujets nécessaires'), lessThan(text.indexOf('Plan d\'analyse statistique')));
    await dir.delete(recursive: true);
  });

  test('protocole PDF : rubriques dans l\'ordre (relu par l\'extracteur)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = pdfText(await buildProtocolPdf(_project())).replaceAll(RegExp(r'\s+'), ' ');
    var last = -1;
    final titles = protocolOutline(_project()).map((s) => s.title).toList();
    for (var k = 0; k < titles.length; k++) {
      final h = '${k + 1}. ${titles[k]}';
      final i = text.indexOf(h);
      expect(i, greaterThan(last), reason: h);
      last = i;
    }
    expect(text, contains('[À compléter'));
  });

  test('Word : une zone de texte (forme moderne + repli VML) n\'est lue qu\'une fois', () {
    const body = '<w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><w:txbxContent><w:p><w:r><w:t>Réalisé par</w:t></w:r></w:p></w:txbxContent></w:drawing></mc:Choice>'
        '<mc:Fallback><w:pict><w:txbxContent><w:p><w:r><w:t>Réalisé par</w:t></w:r></w:p></w:txbxContent></w:pict></mc:Fallback></mc:AlternateContent></w:r></w:p>'
        '<w:p><w:r><w:t>Objectif</w:t></w:r></w:p>';
    final xml = utf8.encode('<?xml version="1.0"?><w:document xmlns:w="w" xmlns:mc="mc"><w:body>$body</w:body></w:document>');
    final zip = Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml));
    final text = docxText(Uint8List.fromList(ZipEncoder().encode(zip)));
    expect('Réalisé par'.allMatches(text).length, 1);
    expect(text, contains('Objectif'));
  });
}
