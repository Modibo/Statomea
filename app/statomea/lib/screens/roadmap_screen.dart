import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/article_document.dart';
import '../services/presentation_document.dart';
import '../services/file_saver.dart';
import '../services/pdf_export.dart';
import '../services/protocol_document.dart';
import '../state/app_state.dart';
import '../widgets/calculators.dart';
import '../widgets/common.dart';
import 'flow_screen.dart';
import 'planning_screen.dart';
import 'project_screen.dart';
import 'references_screen.dart';
import 'reviewer_screen.dart';
import 'tutor_screen.dart';
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

  static const _docx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const _pptx = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

  Future<void> _save(String name, Uint8List bytes, String mime, String done) async {
    final where = await saveFile(name, bytes, mime);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$done : $where')));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  Widget _tool(IconData icon, String label, VoidCallback onPressed) => OutlinedButton.icon(icon: Icon(icon, size: 18), label: Text(label), onPressed: onPressed);

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
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('Ouvrir le projet', 'Open the project')),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: project))),
          ),
        ]),
        const SizedBox(height: 12),
        _ToolGroups([
          _ToolGroup(Icons.description_outlined, tr('Protocole', 'Protocol'), tr('Rédiger, chiffrer et documenter le protocole avant le comité d\'éthique.', 'Write, cost and document the protocol before the ethics committee.'), [
            _tool(Icons.description_outlined, tr('Protocole (Word)', 'Protocol (Word)'),
                () => _save('protocole-${project.id}.docx', protocolDocx(project), _docx, tr('Protocole enregistré', 'Protocol saved'))),
            _tool(Icons.picture_as_pdf_outlined, tr('Protocole (PDF)', 'Protocol (PDF)'), () async {
              final bytes = await buildProtocolPdf(project);
              await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'protocole-${project.id}.pdf');
            }),
            _tool(Icons.view_timeline_outlined, tr('Budget et chronogramme', 'Budget and timeline'), () => _open(PlanningScreen(project))),
            _tool(Icons.menu_book_outlined, tr('Bibliographie (${project.references.length})', 'Bibliography (${project.references.length})'), () => _open(ReferencesScreen(project))),
          ]),
          _ToolGroup(Icons.assignment_outlined, tr('Recueil des données', 'Data collection'), tr('Fiche de recueil, masque de saisie et dictionnaire tirés des variables du protocole.', 'Case report form, data-entry template and dictionary drawn from the protocol\'s variables.'), [
            if (crfFields(project).isEmpty)
              Text(tr('Disponible dès que le protocole importé décrit ses variables ou que des données sont importées.', 'Available once the imported protocol describes its variables or data are imported.'), style: Theme.of(context).textTheme.bodySmall)
            else
              CrfButtons(project),
          ]),
          _ToolGroup(Icons.article_outlined, tr('Résultats et publication', 'Results and publication'), tr('Flux des participants et article prérédigé avec Tableaux 1 et 2.', 'Participant flow and pre-drafted article with Tables 1 and 2.'), [
            _tool(Icons.account_tree_outlined, tr('Diagramme de flux', 'Flow diagram'), () => _open(FlowScreen(project))),
            _tool(Icons.article_outlined, tr('Article (Word)', 'Article (Word)'), () => _save('article-${project.id}.docx', articleDocx(project), _docx, tr('Article enregistré', 'Article saved'))),
          ]),
          _ToolGroup(Icons.campaign_outlined, tr('Communication', 'Communication'), tr('Soutenance, congrès et réponse aux relecteurs.', 'Defence, conference and response to reviewers.'), [
            _tool(Icons.slideshow_outlined, tr('Présentation (PowerPoint)', 'Presentation (PowerPoint)'),
                () => _save('presentation-${project.id}.pptx', presentationPptx(project, date: AppState.now().substring(0, 10)), _pptx, tr('Présentation enregistrée', 'Presentation saved'))),
            _tool(Icons.dashboard_outlined, tr('Poster (PowerPoint)', 'Poster (PowerPoint)'), () => _save('poster-${project.id}.pptx', posterPptx(project), _pptx, tr('Poster enregistré', 'Poster saved'))),
            _tool(Icons.picture_as_pdf_outlined, tr('Poster (PDF A0)', 'Poster (PDF A0)'), () async {
              final bytes = await buildPosterPdf(project);
              await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'poster-${project.id}.pdf');
            }),
            _tool(Icons.forum_outlined, tr('Réponse aux relecteurs', 'Response to reviewers'), () => _open(ReviewerScreen(project))),
          ]),
          _ToolGroup(Icons.school_outlined, tr('Formation', 'Training'), tr('Vérifier sa compréhension, étape par étape, avec une fiche pour l\'encadrant.', 'Check understanding step by step, with a sheet for the supervisor.'), [
            _tool(Icons.school_outlined, tr('Mode tuteur (${tutorProgress(project).where((x) => x.solved).length}/10)', 'Tutor mode (${tutorProgress(project).where((x) => x.solved).length}/10)'), () => _open(TutorScreen(project))),
          ]),
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

/// Groupe d'outils de la feuille de route : icône, titre, une ligne d'aide, boutons.
class _ToolGroup {
  final IconData icon;
  final String title, help;
  final List<Widget> children;
  const _ToolGroup(this.icon, this.title, this.help, this.children);
}

/// Groupes d'outils sur deux colonnes (une sur téléphone).
class _ToolGroups extends StatelessWidget {
  final List<_ToolGroup> groups;
  const _ToolGroups(this.groups);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final two = c.maxWidth >= 700;
      final w = two ? (c.maxWidth - 12) / 2 : c.maxWidth;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final g in groups)
          SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(g.icon, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Semantics(header: true, child: Text(g.title, style: theme.textTheme.titleSmall))),
                  ]),
                  const SizedBox(height: 4),
                  Text(g.help, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: g.children),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}
