import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/pdf_export.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'roadmap_screen.dart';

/// Tableau de bord de l'encadrant : avancement de chaque projet (étapes, relecture, mode tuteur, analyses, effectif),
/// points d'attention, import groupé des projets des étudiants (.json), fiche de la promotion en PDF.
class SupervisorScreen extends StatefulWidget {
  const SupervisorScreen({super.key});
  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  bool demos = false;

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (files.isEmpty || !mounted) return;
    final state = context.read<AppState>();
    var ok = 0;
    final failed = <String>[];
    for (final f in files) {
      try {
        final imp = state.prepareImport(utf8.decode(await f.xFile.readAsBytes()));
        await state.addImported(imp.project);
        ok++;
      } catch (_) {
        failed.add(f.xFile.name);
      }
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('$ok projet(s) importé(s)${failed.isEmpty ? '' : ' ; illisible(s) : ${failed.join(', ')}'}.', '$ok project(s) imported${failed.isEmpty ? '' : '; unreadable: ${failed.join(', ')}'}.'))));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final sums = [for (final p in state.projects) if (demos || p.demoNotice.isEmpty) summarizeProject(p)];
    final toReview = sums.where((s) => s.errors > 0).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Tableau de bord encadrant', 'Supervisor dashboard')),
        actions: [
          IconButton(
            tooltip: tr('Fiche de la promotion (PDF)', 'Cohort sheet (PDF)'),
            icon: const Icon(Icons.print_outlined),
            onPressed: sums.isEmpty
                ? null
                : () async {
                    final bytes = await buildSupervisorPdf(sums, generatedAt: AppState.now());
                    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'tableau-de-bord.pdf');
                  },
          ),
        ],
      ),
      body: PageBody(maxWidth: 1100, children: [
        Text(tr('Importez les projets que vos étudiants vous envoient (fichiers .json exportés à l\'étape 10) : chacun apparaît avec son avancement et les points à discuter.',
                'Import the projects your students send you (.json files exported at step 10): each appears with its progress and the points to discuss.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(icon: const Icon(Icons.group_add_outlined), label: Text(tr('Importer des projets d\'étudiants', 'Import student projects')), onPressed: _import),
          FilterChip(label: Text(tr('Inclure les démonstrations', 'Include demonstrations')), selected: demos, onSelected: (v) => setState(() => demos = v)),
        ]),
        const SizedBox(height: 10),
        Text(tr('${sums.length} projet(s) ; $toReview à relire (erreurs de méthode).', '${sums.length} project(s); $toReview to review (methodological errors).'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (sums.isEmpty) Text(tr('Aucun projet d\'étudiant pour l\'instant.', 'No student project yet.')),
        for (final s in sums..sort((a, b) => b.errors.compareTo(a.errors)))
          Card(
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoadmapScreen(s.project))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s.project.title, style: theme.textTheme.titleSmall)),
                    Chip(label: Text(s.status), visualDensity: VisualDensity.compact, backgroundColor: s.errors > 0 ? theme.colorScheme.errorContainer : null),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(width: 90, child: Text(tr('Étapes', 'Steps'), style: theme.textTheme.labelMedium)),
                    Expanded(child: LinearProgressIndicator(value: s.stepsDone / 10, minHeight: 6)),
                    const SizedBox(width: 8),
                    Text('${s.stepsDone}/10'),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    Text(tr('Relecture : ${s.errors} erreur(s), ${s.warnings} à revoir, ${s.missing} manquant(s)', 'Review: ${s.errors} error(s), ${s.warnings} to review, ${s.missing} missing')),
                    Text(tr('Tuteur : ${s.tutorSolved}/10', 'Tutor: ${s.tutorSolved}/10')),
                    Text(tr('Analyses : ${s.analyses}${s.lastAnalysis.isEmpty ? '' : ' (dernière : ${s.lastAnalysis}${s.lastDate.isEmpty ? '' : ', ${s.lastDate}'})'}', 'Analyses: ${s.analyses}${s.lastAnalysis.isEmpty ? '' : ' (last: ${s.lastAnalysis}${s.lastDate.isEmpty ? '' : ', ${s.lastDate}'})'}')),
                    if (s.planned != null || s.analysed != null) Text(tr('Effectif : ${s.analysed ?? '—'} / ${s.planned ?? '—'} prévus', 'Sample: ${s.analysed ?? '—'} / ${s.planned ?? '—'} planned')),
                  ]),
                  for (final a in s.attention)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [Icon(Icons.flag_outlined, size: 16, color: Colors.amber.shade800), const SizedBox(width: 6), Expanded(child: Text(a, style: theme.textTheme.bodySmall))]),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
