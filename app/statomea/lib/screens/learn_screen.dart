import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import '../widgets/common.dart';
import 'lesson_screen.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});
  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  Level? level;
  @override
  Widget build(BuildContext context) {
    final lessons = context.read<AppState>().lessons.where((l) => level == null || l.level == level).toList();
    return PageBody(children: [
      Heading(tr('Formation', 'Training')),
      Text(tr('Chaque leçon : notions clés, exemple biomédical chiffré (calculé par le moteur), exercice corrigé, erreurs fréquentes, lien vers le calcul.', 'Each lesson: key notions, a biomedical numerical example (computed by the engine), a corrected exercise, common errors, a link to the calculation.')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: Text(tr('Toutes', 'All')), selected: level == null, onSelected: (_) => setState(() => level = null)),
        for (final l in Level.values) ChoiceChip(label: Text(levelLabel(l)), selected: level == l, onSelected: (_) => setState(() => level = l)),
      ]),
      const SizedBox(height: 10),
      for (final l in lessons)
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(switch (l.level) { Level.beginner => 'D', Level.intermediate => 'I', Level.advanced => 'A' })),
            title: Text(l.title),
            subtitle: Text(tr('${levelLabel(l.level)} · ${l.exercises.length} exercice(s)', '${levelLabel(l.level)} · ${l.exercises.length} exercise(s)')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(l))),
          ),
        ),
      const SizedBox(height: 16),
      Text(tr('Grilles de référence', 'Reference grids'), style: Theme.of(context).textTheme.titleMedium),
      for (final c in allChecklists)
        Card(
          child: ExpansionTile(
            title: Text(c.title),
            subtitle: Text(c.reference),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(c.purpose), const SizedBox(height: 6), for (final i in c.items) Text('${i.id}. ${i.text}')],
          ),
        ),
    ]);
  }
}
