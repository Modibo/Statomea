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
    if (f['trajectories'] is Map) trajectoriesSvg(f['trajectories'] as Map),
    if (f['powerCurve'] is Map) powerCurveSvg(f['powerCurve'] as Map),
    if (f['cumulativeIncidence'] is Map) cifSvg(f['cumulativeIncidence'] as Map),
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

/// Feuille de route imprimable : les 10 étapes du projet dans l'ordre, avec ce que l'application propose à chacune
/// (pour aider le chercheur hors de l'application).
Future<Uint8List> buildRoadmapPdf(Project p, {required String generatedAt}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final doc = pw.Document(title: p.title, author: 'Statoméa', creator: '$engineName $engineVersion');
  final road = projectRoadmap(p);
  String status(RoadmapStatus s) => switch (s) {
        RoadmapStatus.done => tr('FAIT', 'DONE'),
        RoadmapStatus.proposed => tr('PROPOSÉ — À VÉRIFIER', 'PROPOSED — TO CHECK'),
        RoadmapStatus.todo => tr('À FAIRE', 'TO DO'),
      };
  PdfColor color(RoadmapStatus s) => switch (s) {
        RoadmapStatus.done => PdfColor.fromHex('#2e7d32'),
        RoadmapStatus.proposed => PdfColor.fromHex('#7a5c00'),
        RoadmapStatus.todo => PdfColors.blueGrey600,
      };
  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Statoméa — ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      pw.Text(tr('Feuille de route du projet', 'Project roadmap'), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Header(level: 0, child: pw.Text(p.title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
      pw.Text(tr('Établie par Statoméa ($engineName $engineVersion) le $generatedAt. Les éléments « proposés » sont déduits du texte : à vérifier et compléter par le chercheur.',
              'Prepared by Statoméa ($engineName $engineVersion) on $generatedAt. "Proposed" items are inferred from the text: to be checked and completed by the researcher.'),
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      for (var k = 0; k < road.length; k++)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Text('${k + 1}. ${stepLabel(road[k].step)}', style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
              pw.Spacer(),
              pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: pw.BoxDecoration(color: color(road[k].status), borderRadius: pw.BorderRadius.circular(2)),
                  child: pw.Text(status(road[k].status), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.white))),
            ]),
            pw.SizedBox(height: 2),
            pw.Text(stepHint(road[k].step), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
            pw.SizedBox(height: 3),
            for (final l in road[k].lines) pw.Bullet(text: l, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text(tr('Notes du chercheur :', 'Researcher\'s notes:'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Container(height: 22, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)))),
          ]),
        ),
      if (p.analysisPlan.trim().isNotEmpty) ...[
        pw.Header(level: 1, child: pw.Text(tr('Plan d\'analyse proposé', 'Proposed analysis plan'), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        for (final l in p.analysisPlan.split('\n')) if (l.trim().isNotEmpty) pw.Bullet(text: l.trim(), style: const pw.TextStyle(fontSize: 9)),
      ],
    ],
  ));
  return doc.save();
}

/// Protocole prérédigé en PDF (mêmes rubriques que la version Word) ; les éléments « à compléter » sont surlignés.
Future<Uint8List> buildProtocolPdf(Project p) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final doc = pw.Document(title: p.title, author: 'Statoméa', creator: '$engineName $engineVersion');
  final sections = protocolOutline(p);
  pw.Widget para(String t) {
    final spans = <pw.InlineSpan>[];
    var i = 0;
    for (final m in RegExp(r'\[(?:À compléter|To complete)[^\]]*\]').allMatches(t)) {
      if (m.start > i) spans.add(pw.TextSpan(text: t.substring(i, m.start)));
      spans.add(pw.TextSpan(text: m.group(0), style: pw.TextStyle(background: pw.BoxDecoration(color: PdfColor.fromHex('#fff176')))));
      i = m.end;
    }
    if (i < t.length) spans.add(pw.TextSpan(text: t.substring(i)));
    return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.RichText(text: pw.TextSpan(children: spans, style: const pw.TextStyle(fontSize: 10))));
  }

  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      pw.Text(tr('Protocole de recherche', 'Research protocol'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1f4e79'))),
      pw.Text(p.title, style: const pw.TextStyle(fontSize: 14)),
      pw.SizedBox(height: 4),
      pw.Text(tr('Prérédigé par Statoméa ($engineName $engineVersion) à partir du projet ; les éléments surlignés sont à compléter par l\'investigateur.',
              'Pre-drafted by Statoméa ($engineName $engineVersion) from the project; highlighted items are to be completed by the investigator.'),
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      for (var k = 0; k < sections.length; k++) ...[
        pw.SizedBox(height: 10),
        pw.Text('${k + 1}. ${sections[k].title}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1f4e79'))),
        pw.SizedBox(height: 4),
        for (final l in sections[k].paragraphs) para(l),
      ],
    ],
  ));
  return doc.save();
}

/// Rapport de relecture méthodologique : points à corriger (avec le passage en cause et la correction), vérifications
/// réussies et corrections déjà appliquées.
Future<Uint8List> buildReviewPdf(Project p, {required String generatedAt}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final doc = pw.Document(title: p.title, author: 'Statoméa', creator: '$engineName $engineVersion');
  final r = reviewProject(p);
  final grid = p.protocol.isEmpty ? null : protocolChecklist(p);
  PdfColor color(ReviewLevel l) => switch (l) {
        ReviewLevel.error => PdfColor.fromHex('#b3261e'),
        ReviewLevel.warning => PdfColor.fromHex('#7a5c00'),
        ReviewLevel.missing => PdfColors.blueGrey600,
        ReviewLevel.ok => PdfColor.fromHex('#2e7d32'),
      };
  pw.Widget card(ReviewFinding f) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: pw.BoxDecoration(color: color(f.level), borderRadius: pw.BorderRadius.circular(2)),
                child: pw.Text(reviewLevelLabel(f.level).toUpperCase(), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.white))),
            pw.SizedBox(width: 6),
            pw.Expanded(child: pw.Text(f.title, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
            pw.Text(stepLabel(f.step), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
          ]),
          pw.SizedBox(height: 3),
          pw.Text(f.problem, style: const pw.TextStyle(fontSize: 9)),
          if (f.evidence != null)
            pw.Container(
                margin: const pw.EdgeInsets.only(top: 3),
                padding: const pw.EdgeInsets.only(left: 6),
                decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 2))),
                child: pw.Text('« ${f.evidence} »', style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800))),
          if (f.correction.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text('${tr('Correction', 'Correction')} : ${f.correction}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ]),
      );
  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Statoméa — ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      pw.Text(tr('Relecture méthodologique', 'Methodological review'), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Header(level: 0, child: pw.Text(p.title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
      pw.Text(
          tr('Établie par Statoméa ($engineName $engineVersion) le $generatedAt, par des règles explicites : ${r.count(ReviewLevel.error)} erreur(s), ${r.count(ReviewLevel.warning)} point(s) à revoir, ${r.count(ReviewLevel.missing)} élément(s) manquant(s), ${r.count(ReviewLevel.ok)} vérification(s) réussie(s). Elle ne remplace pas la relecture d\'un méthodologiste.',
              'Prepared by Statoméa ($engineName $engineVersion) on $generatedAt, by explicit rules: ${r.count(ReviewLevel.error)} error(s), ${r.count(ReviewLevel.warning)} point(s) to review, ${r.count(ReviewLevel.missing)} missing item(s), ${r.count(ReviewLevel.ok)} successful check(s). It does not replace review by a methodologist.'),
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
      pw.SizedBox(height: 10),
      if (r.problems.isEmpty) pw.Text(tr('Aucun problème relevé.', 'No problem found.'), style: const pw.TextStyle(fontSize: 10)),
      for (final f in r.problems) card(f),
      if (grid != null) ...[
        pw.Header(level: 1, child: pw.Text(tr('Grille ${grid.name} : ${grid.present} / ${grid.items.length} éléments trouvés', '${grid.name} checklist: ${grid.present} / ${grid.items.length} items found'), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        pw.Text(grid.reference, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: [tr('Item', 'Item'), tr('Élément', 'Element'), tr('Trouvé', 'Found')],
          data: [for (final it in grid.items) [it.code, it.label, it.present ? tr('oui', 'yes') : tr('ABSENT', 'ABSENT')]],
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          columnWidths: {0: const pw.FixedColumnWidth(36), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(54)},
        ),
      ],
      if (r.checked.isNotEmpty) ...[
        pw.Header(level: 1, child: pw.Text(tr('Vérifications réussies', 'Successful checks'), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        for (final f in r.checked) card(f),
      ],
      if (p.corrections.isNotEmpty) ...[
        pw.Header(level: 1, child: pw.Text(tr('Corrections appliquées', 'Corrections applied'), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        for (final c in p.corrections) pw.Bullet(text: '${c.date} — ${c.title} : ${c.detail}', style: const pw.TextStyle(fontSize: 9)),
      ],
    ],
  ));
  return doc.save();
}

/// Fiche de recueil imprimable : en-tête (étude, n° de participant, date, enquêteur), puis un champ par variable avec
/// son unité et ses bornes ; cases à cocher pour les variables qualitatives ; [copies] fiches vierges.
Future<Uint8List> buildCrfPdf(Project p, List<CrfField> fields, {int copies = 1}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final doc = pw.Document(title: p.title, author: 'Statoméa', creator: '$engineName $engineVersion');
  pw.Widget box() => pw.Container(width: 9, height: 9, margin: const pw.EdgeInsets.only(right: 3), decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)));
  pw.Widget line(double w) => pw.Container(width: w, height: 14, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))));
  pw.Widget entry(CrfField f) {
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : tr('$v'.replaceAll('.', ','), '$v');
    switch (f.type) {
      case CrfType.binary:
      case CrfType.categorical when f.levels.isNotEmpty:
        return pw.Wrap(spacing: 12, runSpacing: 4, children: [
          for (final l in f.levels) pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [box(), pw.Text(l, style: const pw.TextStyle(fontSize: 9.5))]),
        ]);
      case CrfType.date:
        return pw.Text('__ __ / __ __ / __ __ __ __', style: const pw.TextStyle(fontSize: 11, letterSpacing: 1));
      case CrfType.numeric:
        return pw.Row(children: [
          line(80),
          pw.SizedBox(width: 4),
          pw.Text(f.unit, style: const pw.TextStyle(fontSize: 9.5)),
          if (f.min != null && f.max != null) pw.Text('   (${n(f.min!)} – ${n(f.max!)})', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]);
      default:
        return line(190);
    }
  }

  for (var c = 0; c < copies; c++) {
    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Expanded(child: pw.Text(p.title, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold))),
          pw.Text(tr('Fiche de recueil', 'Case report form'), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          pw.Text(tr('N° participant : ', 'Participant no.: '), style: const pw.TextStyle(fontSize: 9)), line(70), pw.SizedBox(width: 14),
          pw.Text(tr('Enquêteur : ', 'Investigator: '), style: const pw.TextStyle(fontSize: 9)), line(110), pw.SizedBox(width: 14),
          pw.Text(tr('Page ${ctx.pageNumber}', 'Page ${ctx.pageNumber}'), style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.Divider(thickness: 0.6),
      ]),
      footer: (ctx) => pw.Text(
          tr('Statoméa — fiche tirée du protocole ; bornes indicatives (refus des saisies aberrantes). Ne porter ni nom ni contact du participant sur cette fiche.',
              'Statoméa — form drawn from the protocol; indicative bounds (to reject implausible entries). Do not write the participant\'s name or contact details on this form.'),
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      build: (_) => [
        pw.Table(
          border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          columnWidths: {0: const pw.FlexColumnWidth(2.2), 1: const pw.FlexColumnWidth(3)},
          children: [
            for (final f in fields)
              pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.middle, children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(f.label, style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text(f.code, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ]),
                ),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: entry(f)),
              ]),
          ],
        ),
      ],
    ));
  }
  return doc.save();
}
