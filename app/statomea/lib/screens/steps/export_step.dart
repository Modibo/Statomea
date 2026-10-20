import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../services/article_document.dart';
import '../../services/presentation_document.dart';
import '../../services/file_saver.dart';
import '../../services/pdf_export.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../projects_screen.dart';

/// Étape 10 : exports reproductibles et suppression du projet.
class ExportStep extends StatelessWidget {
  final Project p;
  const ExportStep(this.p, {super.key});

  String get _slug => p.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  AuditReport _audit() => runAudit(question: p.question, results: [for (final e in p.journal) analysisResultFromJson(e.result)], text: p.resultsText);

  Future<void> _save(BuildContext context, String name, String content, String mime) async {
    try {
      final where = await saveFile(name, Uint8List.fromList(utf8.encode(content)), mime);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Enregistré : $where', 'Saved: $where'))));
    } catch (e) {
      if (context.mounted) showError(context, tr('Enregistrement impossible : $e', 'Saving failed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = [for (final e in p.journal) (e, analysisResultFromJson(e.result))];
    return PageBody(children: [
      Heading('10. Export'),
      Text(tr('Chaque export distingue les données saisies, les résultats calculés, les interprétations proposées et les points à vérifier. Le journal contient la version du moteur, l\'empreinte des données, les corrections et les options de chaque calcul.', 'Each export separates entered data, computed results, proposed interpretations and points to check. The log contains the engine version, the data fingerprint, the corrections and the options of each computation.')),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(tr('Rapport PDF', 'PDF report')),
          onPressed: () async {
            final bytes = await buildProjectPdf(p, audit: _audit(), generatedAt: AppState.now());
            await Printing.sharePdf(bytes: bytes, filename: 'statomea-$_slug.pdf');
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.dashboard_outlined),
          label: Text(tr('Poster (PowerPoint)', 'Poster (PowerPoint)')),
          onPressed: () async {
            final where = await saveFile('poster-$_slug.pptx', posterPptx(p), 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Poster enregistré : $where', 'Poster saved: $where'))));
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(tr('Poster (PDF A0)', 'Poster (PDF A0)')),
          onPressed: () async {
            final bytes = await buildPosterPdf(p);
            await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'poster-$_slug.pdf');
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.slideshow_outlined),
          label: Text(tr('Présentation (PowerPoint)', 'Presentation (PowerPoint)')),
          onPressed: () async {
            final where = await saveFile('presentation-$_slug.pptx', presentationPptx(p, date: AppState.now().substring(0, 10)), 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Présentation enregistrée : $where', 'Presentation saved: $where'))));
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.article_outlined),
          label: Text(tr('Article prérédigé (Word)', 'Pre-drafted article (Word)')),
          onPressed: () async {
            final where = await saveFile('article-$_slug.docx', articleDocx(p), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Article enregistré : $where', 'Article saved: $where'))));
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.html_outlined),
          label: Text(tr('Rapport HTML', 'HTML report')),
          onPressed: () => _save(context, 'statomea-$_slug.html', projectReportHtml(p, audit: _audit(), generatedAt: AppState.now()), 'text/html'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(tr('Journal de calcul (JSON)', 'Computation log (JSON)')),
          onPressed: () => _save(context, 'statomea-$_slug-journal.json', journalJson(p), 'application/json'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text(tr('Projet complet (JSON)', 'Full project (JSON)')),
          onPressed: () => _save(context, 'statomea-$_slug-projet.json', p.encode(), 'application/json'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.share_outlined),
          label: Text(tr('Partager sans les données individuelles (JSON)', 'Share without individual data (JSON)')),
          onPressed: () => _save(context, 'statomea-$_slug-partage.json', shareableProject(p, includeData: false), 'application/json'),
        ),
      ]),
      const SizedBox(height: 16),
      Text(tr('Tableaux et résultats (CSV)', 'Tables and results (CSV)'), style: Theme.of(context).textTheme.titleMedium),
      if (rs.isEmpty) Text(tr('Aucune analyse à exporter.', 'No analysis to export.')),
      for (final (e, r) in rs)
        ListTile(
          dense: true,
          leading: const Icon(Icons.table_chart_outlined),
          title: Text('${e.id} — ${r.methodName}'),
          subtitle: Text(e.timestamp),
          trailing: IconButton(
            tooltip: tr('Exporter en CSV', 'Export as CSV'),
            icon: const Icon(Icons.download),
            onPressed: () => _save(context, 'statomea-$_slug-${e.id}.csv', resultToCsv(r), 'text/csv'),
          ),
        ),
      const SizedBox(height: 24),
      const Divider(),
      Text(tr('Suppression', 'Deletion'), style: Theme.of(context).textTheme.titleMedium),
      Text(tr('Efface de cet appareil le projet, ses données, son journal et les réponses aux grilles. Les fichiers déjà exportés ne sont pas concernés.', 'Erases the project, its data, its log and the grid answers from this device. Files already exported are not affected.')),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(tr('Supprimer définitivement ce projet', 'Permanently delete this project')),
          onPressed: () async {
            if (await confirmDelete(context, p) && context.mounted) Navigator.pop(context);
          },
        ),
      ),
      const SizedBox(height: 8),
      Text(tr('Moteur : $engineName $engineVersion', 'Engine: $engineName $engineVersion'), style: Theme.of(context).textTheme.bodySmall),
      Consumer<AppState>(builder: (_, s, _) => const SizedBox.shrink()),
    ]);
  }
}
