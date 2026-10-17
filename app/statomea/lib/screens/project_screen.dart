import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;
import 'package:statomea_core/statomea_core.dart' as core show Step;

import '../state/app_state.dart';
import '../widgets/common.dart';
import 'projects_screen.dart';
import 'steps/audit_step.dart';
import 'steps/compute_step.dart';
import 'steps/data_step.dart';
import 'steps/export_step.dart';
import 'steps/method_step.dart';
import 'steps/question_steps.dart';
import 'steps/review_steps.dart';

typedef PStep = core.Step;

IconData stepIcon(PStep s) => switch (s) {
      PStep.question => Icons.help_outline,
      PStep.studyPlan => Icons.account_tree_outlined,
      PStep.analysisPlan => Icons.edit_note,
      PStep.dataControl => Icons.table_view_outlined,
      PStep.methodChoice => Icons.alt_route,
      PStep.computation => Icons.calculate_outlined,
      PStep.diagnostics => Icons.fact_check_outlined,
      PStep.interpretation => Icons.lightbulb_outline,
      PStep.audit => Icons.gavel_outlined,
      PStep.export => Icons.ios_share,
    };

/// Projet : parcours en 10 étapes. Rail d'étapes à gauche sur grand écran,
/// bandeau défilant en haut sur téléphone.
class ProjectScreen extends StatefulWidget {
  final Project project;
  final PStep initialStep;
  const ProjectScreen({super.key, required this.project, this.initialStep = PStep.question});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late PStep step = widget.initialStep;
  String? preselectedMethod;

  void go(PStep s, {String? method}) => setState(() {
        step = s;
        if (method != null) preselectedMethod = method;
      });

  Widget _content(Project p) => switch (step) {
        PStep.question => QuestionStep(p),
        PStep.studyPlan => StudyPlanStep(p),
        PStep.analysisPlan => AnalysisPlanStep(p),
        PStep.dataControl => DataStep(p),
        PStep.methodChoice => MethodStep(p, onUse: (id) => go(PStep.computation, method: id)),
        PStep.computation => ComputeStep(p, initialMethod: preselectedMethod, key: ValueKey(preselectedMethod)),
        PStep.diagnostics => DiagnosticsStep(p),
        PStep.interpretation => InterpretationStep(p),
        PStep.audit => AuditStep(p),
        PStep.export => ExportStep(p),
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final state = context.watch<AppState>();
    final idx = PStep.values.indexOf(step);
    Widget footerFor(double width) {
      // Le texte agrandi (réglage système) réduit la place utile : on en tient compte.
      final narrow = width / MediaQuery.textScalerOf(context).scale(1) < 520;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          if (idx > 0)
            narrow
                ? IconButton.outlined(tooltip: tr('Étape précédente', 'Previous step'), onPressed: () => go(PStep.values[idx - 1]), icon: const Icon(Icons.chevron_left))
                : OutlinedButton.icon(onPressed: () => go(PStep.values[idx - 1]), icon: const Icon(Icons.chevron_left), label: Text(tr('Précédente', 'Previous'))),
          const Spacer(),
          FilterChip(
            label: Text(narrow ? tr('Terminée', 'Done') : tr('Étape terminée', 'Step done')),
            selected: p.completed.contains(step),
            onSelected: (v) {
              setState(() => v ? p.completed.add(step) : p.completed.remove(step));
              state.save(p);
            },
          ),
          const SizedBox(width: 8),
          if (idx < PStep.values.length - 1)
            narrow
                ? IconButton.filled(tooltip: tr('Étape suivante', 'Next step'), onPressed: () => go(PStep.values[idx + 1]), icon: const Icon(Icons.chevron_right))
                : FilledButton.icon(onPressed: () => go(PStep.values[idx + 1]), icon: const Icon(Icons.chevron_right), label: Text(tr('Suivante', 'Next'))),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final appBar = AppBar(
        title: Text(p.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr('Supprimer le projet', 'Delete project'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDelete(context, p) && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      );
      final demoBanner = p.demoNotice.isEmpty
          ? const SizedBox.shrink()
          : MaterialBanner(
              content: Text(p.demoNotice, style: TextStyle(fontSize: 12, color: demoBannerColors(Theme.of(context).brightness).foreground)),
              leading: Icon(Icons.science_outlined, color: demoBannerColors(Theme.of(context).brightness).foreground),
              backgroundColor: demoBannerColors(Theme.of(context).brightness).background,
              actions: const [SizedBox.shrink()],
            );
      // Rappel de ce qu'on fait à cette étape (brève description).
      final cs = Theme.of(context).colorScheme;
      final hint = Container(
        width: double.infinity,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(stepIcon(step), size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${tr('Étape', 'Step')} ${idx + 1} — ${stepHint(step)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ]),
      );
      final content = Column(children: [
        demoBanner,
        hint,
        Expanded(child: _content(p)),
        const Divider(height: 1),
        footerFor(c.maxWidth),
      ]);
      if (wide) {
        return Scaffold(
          appBar: appBar,
          body: Row(children: [
            SizedBox(
              width: 250,
              child: ListView(children: [
                for (final s in PStep.values)
                  ListTile(
                    dense: true,
                    selected: s == step,
                    leading: Icon(p.completed.contains(s) ? Icons.check_circle : stepIcon(s),
                        color: p.completed.contains(s) ? Colors.green.shade700 : null),
                    title: Text('${PStep.values.indexOf(s) + 1}. ${stepLabel(s)}'),
                    onTap: () => go(s),
                  ),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ]),
        );
      }
      return Scaffold(
        appBar: appBar,
        body: Column(children: [
          // 64 = cible tactile de 48 dp + marges : en dessous, les puces sont écrasées (règles Android/iOS).
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final s in PStep.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(p.completed.contains(s) ? Icons.check_circle : stepIcon(s), size: 16),
                      label: Text('${PStep.values.indexOf(s) + 1}. ${stepLabel(s)}'),
                      selected: s == step,
                      onSelected: (_) => go(s),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: content),
        ]),
      );
    });
  }
}
