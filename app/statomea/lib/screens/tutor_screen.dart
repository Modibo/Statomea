import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/pdf_export.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Mode tuteur : une question de compréhension par étape, tirée du projet ; indice après une erreur, explication
/// après la bonne réponse ou au second essai ; progression enregistrée ; fiche de progression pour l'encadrant.
class TutorScreen extends StatefulWidget {
  final Project project;
  const TutorScreen(this.project, {super.key});
  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  Project get p => widget.project;
  final chosen = <int, int>{};
  final feedback = <int, (bool, String)>{};

  @override
  Widget build(BuildContext context) {
    final qs = tutorQuestions(p);
    final prog = tutorProgress(p);
    final solved = prog.where((x) => x.solved).length;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Mode tuteur', 'Tutor mode')),
        actions: [
          IconButton(
            tooltip: tr('Fiche de progression (PDF)', 'Progress sheet (PDF)'),
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: () async {
              final bytes = await buildTutorPdf(p, generatedAt: AppState.now());
              await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'progression-${p.id}.pdf');
            },
          ),
        ],
      ),
      body: PageBody(maxWidth: 900, children: [
        Heading(p.title),
        Text(tr('Une question par étape, tirée de votre projet quand c\'est possible (★). Répondez avant de passer à l\'étape suivante : un indice s\'affiche après une erreur, l\'explication après la bonne réponse.',
                'One question per step, drawn from your project when possible (★). Answer before moving to the next step: a hint appears after a mistake, the explanation after the right answer.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Text(tr('Progression : $solved / ${qs.length} étapes comprises', 'Progress: $solved / ${qs.length} steps understood'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: solved / qs.length, minHeight: 8),
        const SizedBox(height: 12),
        for (var k = 0; k < qs.length; k++) _card(context, k, qs[k], prog[k]),
      ]),
    );
  }

  Widget _card(BuildContext context, int k, TutorQuestion q, TutorStepProgress pr) {
    final theme = Theme.of(context);
    final fb = feedback[k];
    final done = pr.solved;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: done ? Colors.green.shade600 : theme.colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 13, backgroundColor: done ? Colors.green.shade600 : theme.colorScheme.primaryContainer, child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : Text('${k + 1}', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(child: Text('${stepLabel(q.step)}${q.personalised ? ' ★' : ''}', style: theme.textTheme.titleSmall)),
            if (pr.attempts > 0) Text(tr('${pr.attempts} essai(s)', '${pr.attempts} attempt(s)'), style: theme.textTheme.labelSmall),
          ]),
          const SizedBox(height: 8),
          Text(q.prompt),
          RadioGroup<int>(
            groupValue: chosen[k],
            onChanged: (v) => setState(() => chosen[k] = v!),
            child: Column(children: [
              for (var i = 0; i < q.options.length; i++) RadioListTile<int>(value: i, dense: true, title: Text(q.options[i])),
            ]),
          ),
          Row(children: [
            FilledButton.tonal(
              onPressed: chosen[k] == null
                  ? null
                  : () {
                      final ok = answerTutor(p, q, chosen[k]!);
                      final attempts = int.tryParse(p.tutor['attempts_${q.step.name}'] ?? '') ?? 1;
                      setState(() => feedback[k] = ok
                          ? (true, q.explanation)
                          : (false, attempts >= 2 ? '${tr('Réponse attendue : ', 'Expected answer: ')}${q.options[q.correct]}. ${q.explanation}' : '${tr('Indice : ', 'Hint: ')}${q.hint}'));
                      context.read<AppState>().saveSoon(p);
                    },
              child: Text(tr('Vérifier', 'Check')),
            ),
          ]),
          if (fb != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (fb.$1 ? Colors.green : Colors.amber).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(fb.$1 ? Icons.check_circle_outline : Icons.lightbulb_outline, color: fb.$1 ? Colors.green.shade700 : Colors.amber.shade800, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${fb.$1 ? tr('Exact. ', 'Correct. ') : ''}${fb.$2}')),
              ]),
            ),
        ]),
      ),
    );
  }
}
