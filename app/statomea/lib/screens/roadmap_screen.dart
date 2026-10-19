import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/file_saver.dart';
import '../services/pdf_export.dart';
import '../services/protocol_document.dart';
import '../state/app_state.dart';
import '../widgets/calculators.dart';
import '../widgets/common.dart';
import 'project_screen.dart';
import 'review_screen.dart';

/// Feuille de route : les 10 étapes du projet dans l'ordre, avec ce que l'application propose à chacune ; impression
/// en PDF ; chaque étape s'ouvre d'un appui.
class RoadmapScreen extends StatefulWidget {
  final Project project;
  const RoadmapScreen(this.project, {super.key});
  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  Project get project => widget.project;

  Future<void> _print(BuildContext context) async {
    final bytes = await buildRoadmapPdf(project, generatedAt: AppState.now());
    final slug = project.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'statomea-feuille-de-route-${slug.isEmpty ? project.id : slug}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final road = projectRoadmap(project);
    final scheme = Theme.of(context).colorScheme;
    (String, Color, IconData) badge(RoadmapStatus s) => switch (s) {
          RoadmapStatus.done => (tr('Fait', 'Done'), Colors.green.shade700, Icons.check_circle),
          RoadmapStatus.proposed => (tr('Proposé — à vérifier', 'Proposed — to check'), Colors.amber.shade800, Icons.auto_awesome),
          RoadmapStatus.todo => (tr('À faire', 'To do'), scheme.outline, Icons.radio_button_unchecked),
        };
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Feuille de route', 'Roadmap')),
        actions: [IconButton(tooltip: tr('Imprimer ou enregistrer en PDF', 'Print or save as PDF'), icon: const Icon(Icons.print_outlined), onPressed: () => _print(context))],
      ),
      body: PageBody(maxWidth: 900, children: [
        Heading(project.title),
        Text(tr('Les 10 étapes dans l\'ordre. Les éléments « proposés » sont déduits du texte de la question ou du protocole : vérifiez-les et complétez-les dans chaque étape.',
                'The 10 steps in order. "Proposed" items are inferred from the question or protocol text: check and complete them in each step.'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        ReviewBanner(project, onReturn: () => setState(() {})),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(icon: const Icon(Icons.print_outlined), label: Text(tr('Imprimer / PDF', 'Print / PDF')), onPressed: () => _print(context)),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(tr('Protocole (Word)', 'Protocol (Word)')),
            onPressed: () async {
              final where = await saveFile('protocole-${project.id}.docx', protocolDocx(project), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Protocole enregistré : $where', 'Protocol saved: $where'))));
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(tr('Protocole (PDF)', 'Protocol (PDF)')),
            onPressed: () async {
              final bytes = await buildProtocolPdf(project);
              await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'protocole-${project.id}.pdf');
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('Ouvrir le projet', 'Open the project')),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: project))),
          ),
        ]),
        const SizedBox(height: 12),
        for (var k = 0; k < road.length; k++)
          Card(
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: project, initialStep: road[k].step))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 14, child: Text('${k + 1}', style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(stepLabel(road[k].step), style: Theme.of(context).textTheme.titleMedium)),
                    Icon(badge(road[k].status).$3, size: 18, color: badge(road[k].status).$2),
                    const SizedBox(width: 4),
                    Text(badge(road[k].status).$1, style: TextStyle(color: badge(road[k].status).$2, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Text(stepHint(road[k].step), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  for (final l in road[k].lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(l))]),
                    ),
                  if (road[k].calculator != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calculate_outlined),
                        label: Text(tr('Calculer l\'effectif', 'Compute the sample size')),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => Scaffold(
                                      appBar: AppBar(title: Text(tr('Calcul d\'effectif', 'Sample size calculation'))),
                                      body: PageBody(children: [CalculatorPanel(project: project, initialMethod: road[k].calculator, presets: road[k].calculatorPresets)]),
                                    ))),
                      ),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
