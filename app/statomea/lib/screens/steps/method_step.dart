import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/variable_roles.dart';
import '../lesson_screen.dart';

/// Étape 5 : assistant de choix. Il pose les questions manquantes et
/// présente les options défendables avec leurs conditions.
class MethodStep extends StatefulWidget {
  final Project p;
  final ValueChanged<String> onUse;
  const MethodStep(this.p, {super.key, required this.onUse});
  @override
  State<MethodStep> createState() => _MethodStepState();
}

class _MethodStepState extends State<MethodStep> {
  void set(ResearchQuestion q) {
    setState(() => widget.p.question = q);
    context.read<AppState>().save(widget.p);
  }

  /// Réponses rapides aux questions de clarification.
  Widget _quickAnswer(Clarification c) {
    final q = widget.p.question;
    List<(String, ResearchQuestion)> opts = switch (c.field) {
      'objective' => [for (final o in StudyObjective.values.where((o) => o != StudyObjective.unknown)) (objectiveLabel(o), q.copyWith(objective: o))],
      'dataLevel' => [(tr('observations individuelles', 'individual observations'), q.copyWith(dataLevel: DataLevel.individual)), (tr('résultats d\'études', 'study results'), q.copyWith(dataLevel: DataLevel.aggregatedStudies))],
      'outcomeType' => [for (final t in OutcomeType.values.where((t) => t != OutcomeType.unknown)) (outcomeTypeLabel(t), q.copyWith(outcomeType: t))],
      'design' => [for (final d in StudyDesign.values.where((d) => d != StudyDesign.unknown && d != StudyDesign.systematicReview)) (designLabel(d), q.copyWith(design: d))],
      'exposureType' => [('binaire', q.copyWith(exposureType: ExposureType.binary)), (tr('qualitative > 2', 'categorical > 2'), q.copyWith(exposureType: ExposureType.categorical)), ('quantitative', q.copyWith(exposureType: ExposureType.continuous))],
      'pairing' => [(tr('indépendantes', 'independent'), q.copyWith(pairing: Pairing.independent)), (tr('appariées', 'paired'), q.copyWith(pairing: Pairing.paired)), (tr('répétées', 'repeated'), q.copyWith(pairing: Pairing.repeated))],
      'needsAdjustment' => [('oui', q.copyWith(needsAdjustment: true)), ('non', q.copyWith(needsAdjustment: false))],
      'approxNormal' => [('oui', q.copyWith(approxNormal: true)), ('non', q.copyWith(approxNormal: false))],
      'referenceStandardAvailable' => [('oui', q.copyWith(referenceStandardAvailable: true))],
      'competingRisk' => [(tr('oui', 'yes'), q.copyWith(competingRisk: true)), (tr('non', 'no'), q.copyWith(competingRisk: false))],
      'timeVaryingExposure' => [(tr('oui', 'yes'), q.copyWith(timeVaryingExposure: true)), (tr('non', 'no'), q.copyWith(timeVaryingExposure: false))],
      _ => [],
    };
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(tr('Pourquoi : ${c.why}', 'Why: ${c.why}'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (opts.isEmpty) Text(tr('Répondez à l\'étape 1 ou 2.', 'Answer in step 1 or 2.')),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final (l, nq) in opts) ActionChip(label: Text(l), onPressed: () => set(nq))]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = advise(widget.p.question);
    final lessons = context.read<AppState>().lessons;
    return PageBody(children: [
      Heading(tr('5. Choix de la méthode', '5. Method choice')),
      Text(tr('L\'assistant raisonne sur les caractéristiques DÉCLARÉES de la question et des données. S\'il manque une information, il la demande.', 'The assistant reasons on the DECLARED characteristics of the question and the data. If information is missing, it asks for it.')),
      const SizedBox(height: 12),
      if (widget.p.dataset != null)
        VariableRolesEditor(widget.p, onChanged: (r) {
          setState(() => widget.p.roles = r);
          context.read<AppState>().save(widget.p);
        }),
      if (a.needsMoreInformation) ...[
        SectionLabel(tr('Précisions nécessaires (${a.questions.length})', 'Clarifications needed (${a.questions.length})'), icon: Icons.contact_support_outlined),
        for (final c in a.questions) _quickAnswer(c),
      ],
      if (a.options.isNotEmpty) ...[
        const SizedBox(height: 8),
        SectionLabel(a.needsMoreInformation ? tr('Options provisoires (à confirmer)', 'Provisional options (to be confirmed)') : tr('Méthodes proposées', 'Proposed methods'), icon: Icons.alt_route),
        for (final o in a.options)
          Card(
            shape: o.recommended
                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))
                : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(o.name, style: Theme.of(context).textTheme.titleMedium),
                  if (o.recommended && !a.needsMoreInformation) Chip(label: Text(tr('Recommandée', 'Recommended')), visualDensity: VisualDensity.compact),
                  StatusChip(o.status),
                ]),
                const SizedBox(height: 4),
                Text(o.whenPreferred),
                const SizedBox(height: 6),
                Text(tr('Conditions :', 'Conditions:'), style: Theme.of(context).textTheme.labelLarge),
                for (final c in o.conditions) Text('• $c'),
                for (final c in o.cautions) Banner2(Severity.caution, c),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: o.status == MethodStatus.validated ? () => widget.onUse(o.methodId) : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(o.status == MethodStatus.validated ? tr('Utiliser cette méthode', 'Use this method') : tr('Indisponible (non validée)', 'Unavailable (not validated)')),
                  ),
                  if (methodInfo(o.methodId) != null && lessonById(lessons, methodInfo(o.methodId)!.lessonId) != null)
                    TextButton.icon(
                      icon: const Icon(Icons.school_outlined),
                      label: Text(tr('Leçon', 'Lesson')),
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => LessonScreen(lessonById(lessons, methodInfo(o.methodId)!.lessonId)!))),
                    ),
                ]),
              ]),
            ),
          ),
      ],
      for (final n in a.notes) Banner2(Severity.info, n),
      if (a.options.isEmpty && !a.needsMoreInformation)
        Banner2(Severity.caution, tr('Aucune méthode de la V1 ne correspond à cette combinaison : voir les notes ci-dessus.', 'No V1 method matches this combination: see the notes above.')),
    ]);
  }
}
