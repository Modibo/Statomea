import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../widgets/calculators.dart';
import '../widgets/common.dart';

class LessonScreen extends StatelessWidget {
  final Lesson lesson;
  const LessonScreen(this.lesson, {super.key});
  @override
  Widget build(BuildContext context) {
    final l = lesson;
    return Scaffold(
      appBar: AppBar(title: Text(l.title)),
      body: PageBody(maxWidth: 820, children: [
        Chip(label: Text(tr('Niveau ${levelLabel(l.level)}', 'Level ${levelLabel(l.level)}'))),
        const SizedBox(height: 8),
        for (final p in l.body) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p, style: Theme.of(context).textTheme.bodyLarge)),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionLabel(tr('Exemple chiffré', 'Numerical example'), icon: Icons.science_outlined),
              Text(l.exampleTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(l.example),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        SectionLabel(tr('Exercices', 'Exercises'), icon: Icons.edit_outlined),
        for (final e in l.exercises) _ExerciseCard(e),
        const SizedBox(height: 8),
        SectionLabel(tr('Erreurs fréquentes', 'Common errors'), icon: Icons.warning_amber_outlined),
        for (final e in l.commonErrors) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('✗ $e')),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.calculate_outlined),
            label: Text(tr('Ouvrir le calcul correspondant', 'Open the corresponding calculation')),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(tr('Calcul', 'Calculation'))),
                        body: PageBody(children: [CalculatorPanel(initialMethod: l.calculatorId)])))),
          ),
        ),
      ]),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  final Exercise e;
  const _ExerciseCard(this.e);
  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  final c = TextEditingController();
  int? choice;
  bool? correct;
  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (e.isNumeric)
            Row(children: [
              NumField(tr('Votre réponse', 'Your answer'), c, width: 180),
              const SizedBox(width: 12),
              FilledButton(onPressed: () => setState(() => correct = e.check(c.text)), child: Text(tr('Vérifier', 'Check'))),
            ])
          else
            RadioGroup<int>(
              groupValue: choice,
              onChanged: (v) => setState(() {
                choice = v;
                correct = e.check('$v');
              }),
              child: Column(children: [
                for (var i = 0; i < e.choices.length; i++)
                  RadioListTile<int>(contentPadding: EdgeInsets.zero, value: i, title: Text(e.choices[i])),
              ]),
            ),
          if (correct != null)
            Banner2(correct! ? Severity.info : Severity.caution, correct! ? tr('Correct. ${e.correction}', 'Correct. ${e.correction}') : tr('Pas tout à fait. ${e.correction}', 'Not quite. ${e.correction}')),
        ]),
      ),
    );
  }
}
