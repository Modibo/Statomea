import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:statomea/services/document_text.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  const lines = [
    'Efficacité de la vitamine D chez l\'adulte hypertendu',
    'Question de recherche : La supplémentation en vitamine D réduit-elle la pression artérielle systolique à 12 mois chez les adultes hypertendus ?',
    'Schéma de l\'étude',
    'Essai randomisé contrôlé, deux bras parallèles.',
    'Critère de jugement principal',
    'Pression artérielle systolique à 12 mois (mmHg).',
  ];

  test('PDF avec police embarquée (accents, CMap ToUnicode) : texte et protocole relus', () async {
    final font = pw.Font.ttf(ByteData.sublistView(File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync()));
    final doc = pw.Document();
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [for (final l in lines) pw.Text(l, style: pw.TextStyle(font: font))])));
    final bytes = await doc.save();
    final text = pdfText(Uint8List.fromList(bytes));
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains('Efficacité de la vitamine D'));
    expect(flat, contains('réduit-elle la pression artérielle'));
    final d = protocolFromText(text);
    expect(d.question, contains('réduit-elle la pression artérielle systolique'));
    expect(d.toQuestion().design, StudyDesign.rct);
  });

  test('PDF à police standard (WinAnsi)', () async {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (_) => pw.Column(children: [pw.Text('Population : adultes de 30 a 70 ans'), pw.Text('Analyse statistique : regression lineaire ajustee')])));
    final text = pdfText(Uint8List.fromList(await doc.save()));
    expect(text.split('\n'), contains('Population : adultes de 30 a 70 ans'));
    expect(text, contains('regression lineaire'));
  });

  test('Word (.docx) : paragraphes, entités XML ; refus des formats non pris en charge et d\'un PDF sans texte', () {
    final xml = '<?xml version="1.0"?><w:document xmlns:w="w"><w:body>'
        '${[for (final l in lines) '<w:p><w:r><w:t xml:space="preserve">${l.replaceAll("'", '&apos;')}</w:t></w:r></w:p>'].join()}'
        '<w:p><w:r><w:t>A &amp; B &lt; 5</w:t></w:r></w:p></w:body></w:document>';
    final a = Archive()..addFile(ArchiveFile('word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(a));
    final text = documentText(bytes, 'protocole.docx');
    expect(text.split('\n').first, lines.first);
    expect(text, contains('A & B < 5'));
    expect(protocolFromText(text).sections['outcome'], contains('Pression artérielle systolique'));
    expect(() => documentText(bytes, 'protocole.odt'), throwsA(isA<StatInputError>()));
    expect(() => pdfText(Uint8List.fromList(latin1.encode('%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF'))), throwsA(isA<StatInputError>()));
  });
}
