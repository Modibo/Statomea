import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:statomea_core/statomea_core.dart';

/// Rapport PDF du projet. Même structure que le rapport HTML du moteur :
/// données saisies / résultats calculés / interprétations proposées /
/// points à vérifier, puis audit.
Future<Uint8List> buildProjectPdf(Project p, {AuditReport? audit, required String generatedAt}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final doc = pw.Document(title: p.title, author: 'Statoméa', creator: '$engineName $engineVersion');

  pw.Widget tag(String t, PdfColor c) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: pw.BoxDecoration(color: c, borderRadius: pw.BorderRadius.circular(2)),
      child: pw.Text(t, style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)));
  // Une nouvelle instance par usage : un widget pdf ne doit pas être réutilisé.
  pw.Widget tIn() => tag(tr('Données saisies', 'Entered data'), PdfColors.blueGrey600);
  pw.Widget tCalc() => tag(tr('Résultat calculé', 'Computed result'), PdfColor.fromHex('#1f4e79'));
  pw.Widget tInterp() => tag(tr('Interprétation proposée', 'Proposed interpretation'), PdfColor.fromHex('#7a5c00'));
  pw.Widget tVerify() => tag(tr('À vérifier par le chercheur', 'To be checked by the researcher'), PdfColor.fromHex('#aa3333'));

  // Au-delà de 60 lignes, le PDF ne reprend que le début du tableau (complet dans les exports HTML et CSV).
  const maxPdfRows = 60;
  // Titre et tableau rendus comme éléments distincts du document : un tableau ne se coupe entre les pages que s'il est
  // enfant direct de MultiPage ; enveloppé dans une colonne, un tableau plus haut qu'une page bouclait la pagination.
  List<pw.Widget> table(ResultTable t) => [
        pw.SizedBox(height: 6),
        pw.Text(t.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.TableHelper.fromTextArray(
          headers: t.header,
          data: t.rows.length > maxPdfRows ? t.rows.sublist(0, maxPdfRows) : t.rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellPadding: const pw.EdgeInsets.all(3),
        ),
        if (t.rows.length > maxPdfRows)
          pw.Text(tr('… ${t.rows.length - maxPdfRows} ligne(s) de plus : tableau complet dans les exports HTML et CSV.', '… ${t.rows.length - maxPdfRows} more row(s): full table in the HTML and CSV exports.'),
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ];

  final q = p.question;
  final body = <pw.Widget>[
    pw.Header(level: 0, child: pw.Text(p.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
    pw.Text(tr('Rapport Statoméa ($engineName $engineVersion) — $generatedAt — projet ${p.id}', 'Statoméa report ($engineName $engineVersion) — $generatedAt — project ${p.id}'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    if (p.demoNotice.isNotEmpty)
      pw.Container(
          margin: const pw.EdgeInsets.only(top: 6),
          padding: const pw.EdgeInsets.all(6),
          color: PdfColor.fromHex('#fff5d6'),
          child: pw.Text(p.demoNotice, style: const pw.TextStyle(fontSize: 8.5))),
    pw.SizedBox(height: 6),
    pw.Row(children: [tIn(), pw.SizedBox(width: 4), tCalc(), pw.SizedBox(width: 4), tInterp(), pw.SizedBox(width: 4), tVerify()]),
    pw.SizedBox(height: 10),
    pw.Row(children: [tIn(), pw.SizedBox(width: 6), pw.Text(tr('Question, plan et données', 'Question, design and data'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
    ...table(ResultTable(tr('Question de recherche', 'Research question'), [tr('Élément', 'Item'), tr('Contenu', 'Content')], [
      ['Question', q.text],
      ['Population', q.population],
      [tr('Exposition / intervention', 'Exposure / intervention'), q.exposure],
      [tr('Comparateur', 'Comparator'), q.comparator],
      [tr('Critère de jugement', 'Outcome'), q.outcome],
      ['Horizon', q.horizon],
      [tr('Plan d\'étude', 'Study design'), designLabel(q.design)],
      [tr('Objectif', 'Aim'), objectiveLabel(q.objective)],
      [tr('Plan d\'analyse', 'Analysis plan'), p.analysisPlan],
    ])),
    if (p.dataset != null)
      pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(tr('Données : ${p.dataset!.source} — ${p.dataset!.rowCount} lignes, ${p.dataset!.names.length} variables. ${p.dataset!.corrections.isEmpty ? "Aucune correction." : "${p.dataset!.corrections.length} correction(s) journalisée(s) :"}', 'Data: ${p.dataset!.source} — ${p.dataset!.rowCount} rows, ${p.dataset!.names.length} variables. ${p.dataset!.corrections.isEmpty ? "No correction." : "${p.dataset!.corrections.length} logged correction(s):"}'),
              style: const pw.TextStyle(fontSize: 9))),
    if (p.dataset != null)
      for (final c in p.dataset!.corrections) pw.Bullet(text: c.describe(), style: const pw.TextStyle(fontSize: 8.5)),
  ];

  for (final e in p.journal) {
    final r = analysisResultFromJson(e.result);
    body.addAll([
      pw.SizedBox(height: 14),
      pw.Header(level: 1, child: pw.Text(r.methodName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Text(tr('Calcul ${e.id} — ${e.timestamp}${e.datasetFingerprint.isEmpty ? "" : " — données ${e.datasetFingerprint}"}', 'Computation ${e.id} — ${e.timestamp}${e.datasetFingerprint.isEmpty ? "" : " — data ${e.datasetFingerprint}"}'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      if (r.status != MethodStatus.validated)
        pw.Container(
            padding: const pw.EdgeInsets.all(4),
            color: PdfColors.red100,
            child: pw.Text(tr('MÉTHODE EN DÉVELOPPEMENT : résultat non présenté comme fiable.', 'METHOD IN DEVELOPMENT: result not presented as reliable.'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      if (r.status == MethodStatus.validated && !r.reliable)
        pw.Container(
            padding: const pw.EdgeInsets.all(4),
            color: PdfColors.red100,
            child: pw.Text(tr('RÉSULTAT NON RAPPORTABLE : alerte bloquante. Estimations conservées pour la traçabilité, à ne pas citer.', 'RESULT NOT REPORTABLE: blocking alert. Estimates kept for traceability, not to be cited.'),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 4),
      tCalc(),
      pw.Text(r.formula, style: const pw.TextStyle(fontSize: 8)),
      for (final t in r.tables) ...table(t),
      if (r.estimates.isNotEmpty)
        ...table(ResultTable(tr('Estimations', 'Estimates'), [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('Intervalle', 'Interval'), 'p'], [
          for (final x in r.estimates)
            [x.label, fmt(x.value), x.hasInterval ? tr('${x.intervalKind} ${(x.level * 100).round()} % : ${fmt(x.lower)} à ${fmt(x.upper)}', '${(x.level * 100).round()}% ${intervalName(x.intervalKind)}: ${fmt(x.lower)} to ${fmt(x.upper)}') : '—', fmtP(x.pValue)]
        ])),
      ..._figures(r, regular, bold),
      if (r.checks.isNotEmpty)
        ...table(ResultTable(tr('Hypothèses et diagnostics', 'Assumptions and diagnostics'), ['Condition', tr('Statut', 'Status'), tr('Détail', 'Detail')],
            [for (final c in r.checks) [c.label, checkStatusLabel(c.status), c.detail]])),
      pw.SizedBox(height: 6),
      tInterp(),
      pw.Text(tr('Pourquoi cette méthode ? ', 'Why this method? '), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      pw.Text(r.interpretation.whyThisMethod, style: const pw.TextStyle(fontSize: 9)),
      pw.Text(tr('Que signifie le résultat ?', 'What does the result mean?'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      pw.Text(r.interpretation.whatItMeans, style: const pw.TextStyle(fontSize: 9)),
      pw.Text(tr('Quelles conclusions restent injustifiées ?', 'Which conclusions remain unjustified?'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      pw.Text(r.interpretation.notJustified, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 6),
      tVerify(),
      for (final x in pointsToVerify(r)) pw.Bullet(text: x, style: const pw.TextStyle(fontSize: 8.5)),
      if (pointsToVerify(r).isEmpty) pw.Text(tr('Aucun point signalé par le moteur.', 'No point flagged by the engine.'), style: const pw.TextStyle(fontSize: 8.5)),
    ]);
  }
  if (p.resultsText.trim().isNotEmpty) {
    body.addAll([
      pw.SizedBox(height: 14),
      pw.Row(children: [tIn(), pw.SizedBox(width: 6), pw.Text(tr('Texte rédigé par le chercheur', 'Text written by the researcher'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
      pw.Text(p.resultsText, style: const pw.TextStyle(fontSize: 9)),
    ]);
  }
  if (audit != null) {
    body.addAll([
      pw.SizedBox(height: 14),
      pw.Row(children: [tVerify(), pw.SizedBox(width: 6), pw.Text(tr('Audit contradictoire', 'Adversarial audit'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
      ...table(ResultTable(tr('Constats (« lexical » = repérage de formulations, faux positifs possibles)', 'Findings ("lexical" = wording detection, false positives possible)'), [tr('Contrôle', 'Check'), tr('Statut', 'Status'), tr('Constat', 'Finding'), 'Correction'], [
        for (final f in audit.findings)
          [
            auditFamilyLabel(f.family),
            switch (f.status) { AuditStatus.alert => tr('alerte (${severityLabel(f.severity)})', 'alert (${severityLabel(f.severity)})'), AuditStatus.ok => 'conforme', AuditStatus.insufficient => tr('information insuffisante', 'insufficient information') },
            tr('${f.message}${f.lexical ? " (lexical)" : ""}${f.trigger == null ? "" : " — « ${f.trigger} »"}', '${f.message}${f.lexical ? " (lexical)" : ""}${f.trigger == null ? "" : ' — "${f.trigger}"'}'),
            f.correction ?? '—',
          ]
      ])),
    ]);
  }
  // Avertissement et conception, en fin de rapport.
  body.addAll([
    pw.SizedBox(height: 14),
    pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.amber700, width: 0.8)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('$disclaimerTitle — $disclaimerLead', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text(disclaimerText, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 4),
        pw.Text(designedBy, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]),
    ),
  ]);
  doc.addPage(pw.MultiPage(
    // La limite par défaut (20 pages) faisait échouer l'export des projets riches (démonstration 5).
    maxPages: 500,
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(tr('Statoméa — page ${c.pageNumber}/${c.pagesCount}', 'Statoméa — page ${c.pageNumber}/${c.pagesCount}'), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
    build: (_) => body,
  ));
  return doc.save();
}

/// Figures SVG du résultat. Les textes des SVG sont rendus avec Noto Sans : la police par défaut du moteur PDF
/// (Helvetica) ne contient ni « − », ni lettres grecques, ni exposants, et l'échec de mise en page relançait la
/// pagination indéfiniment (« plus de N pages »).
List<pw.Widget> _figures(AnalysisResult r, pw.Font regular, pw.Font bold) {
  final f = r.figures;
  final out = <String>[
    if (f['forest'] is Map) forestPlotSvg((f['forest'] as Map).cast()),
    if (f['calibration'] is List) calibrationSvg((f['calibration'] as List).cast()),
    if (f['decisionCurve'] is List) decisionCurveSvg((f['decisionCurve'] as List).cast()),
    if (f['miChains'] is Map) miChainsSvg(f['miChains'] as Map),
    if (f['sroc'] is Map) srocSvg((f['sroc'] as Map).cast()),
    if (f['bubble'] is Map) bubblePlotSvg(f['bubble'] as Map),
    if (f['kaplanMeier'] is Map) kmSvg((f['kaplanMeier'] as Map).cast()),
    if (f['blandAltman'] is Map) blandAltmanSvg(f['blandAltman'] as Map),
    if (f['volcano'] is Map) volcanoSvg(f['volcano'] as Map),
    if (f['standardCurve'] is Map) standardCurveSvg(f['standardCurve'] as Map),
    if (f['pca'] is Map) pcaSvg(f['pca'] as Map),
    if (f['king'] is Map) kingSvg(f['king'] as Map),
    if (f['manhattan'] is Map) manhattanSvg(f['manhattan'] as Map),
    if (f['qq'] is Map) qqSvg(f['qq'] as Map),
    if (f['ldsc'] is Map) ldscSvg(f['ldsc'] as Map),
    if (f['prs'] is Map) prsSvg(f['prs'] as Map),
    if (f['mr'] is Map) mrSvg(f['mr'] as Map),
  ];
  final al = f['alignment'] is Map ? f['alignment'] as Map : null;
  return [
    for (final s in out) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.SvgImage(svg: s, width: 460, customFontLookup: (family, style, weight) => weight == 'bold' ? bold : regular)),
    // Alignement : texte ASCII à chasse fixe (60 colonnes par bloc).
    if (al != null) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('${al['text']}', style: pw.TextStyle(font: pw.Font.courier(), fontSize: 7))),
  ];
}
