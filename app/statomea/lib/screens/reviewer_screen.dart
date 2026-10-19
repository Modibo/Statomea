import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/document_text.dart';
import '../services/file_saver.dart';
import '../services/reviewer_document.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Réponse aux relecteurs : commentaires collés ou importés (Word, PDF, texte), découpés un par un, avec une réponse
/// proposée à partir du projet (effectif, Tableau 2, IC du journal, flux, données manquantes) ; réponses modifiables ;
/// lettre de réponse en Word.
class ReviewerScreen extends StatefulWidget {
  final Project project;
  const ReviewerScreen(this.project, {super.key});
  @override
  State<ReviewerScreen> createState() => _ReviewerScreenState();
}

class _ReviewerScreenState extends State<ReviewerScreen> {
  Project get p => widget.project;
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _analyse(String text) {
    final items = analyseReviewerComments(p, text);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Aucun commentaire reconnu.', 'No comment recognised.'))));
      return;
    }
    setState(() => p.reviewerItems
      ..clear()
      ..addAll(items));
    context.read<AppState>().saveSoon(p);
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['docx', 'pdf', 'txt']);
    if (files.isEmpty || !mounted) return;
    final f = files.single.xFile;
    final bytes = await f.readAsBytes();
    try {
      final text = f.name.toLowerCase().endsWith('.txt') ? utf8.decode(bytes, allowMalformed: true) : documentText(bytes, f.name);
      input.text = text;
      _analyse(text);
    } on StatInputError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Réponse aux relecteurs', 'Response to reviewers'))),
      body: PageBody(maxWidth: 1000, children: [
        Heading(p.title),
        Text(
            tr('Collez les commentaires des relecteurs (ou importez le courrier de la revue) : Statoméa les sépare, reconnaît le thème de chacun et propose une réponse fondée sur le projet. Relisez et complétez chaque réponse, puis enregistrez la lettre en Word.',
                'Paste the reviewers\' comments (or import the journal\'s letter): Statoméa splits them, recognises the topic of each and proposes a response based on the project. Review and complete each response, then save the letter in Word.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        TextField(controller: input, minLines: 4, maxLines: 10, decoration: InputDecoration(labelText: tr('Commentaires des relecteurs', 'Reviewers\' comments'), border: const OutlineInputBorder())),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(icon: const Icon(Icons.auto_fix_high), label: Text(tr('Analyser et proposer les réponses', 'Analyse and propose responses')), onPressed: () => _analyse(input.text)),
          OutlinedButton.icon(icon: const Icon(Icons.file_upload_outlined), label: Text(tr('Importer (Word, PDF, texte)', 'Import (Word, PDF, text)')), onPressed: _import),
          if (p.reviewerItems.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: Text(tr('Lettre de réponse (Word)', 'Response letter (Word)')),
              onPressed: () async {
                final where = await saveFile('reponse-relecteurs-${p.id}.docx', reviewerLetterDocx(p), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Lettre enregistrée : $where', 'Letter saved: $where'))));
              },
            ),
        ]),
        const SizedBox(height: 12),
        for (var k = 0; k < p.reviewerItems.length; k++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${p.reviewerItems[k].reviewer.isEmpty ? '' : '${p.reviewerItems[k].reviewer} — '}${tr('Commentaire ${k + 1}', 'Comment ${k + 1}')}', style: theme.textTheme.titleSmall)),
                  Chip(label: Text(reviewerTopicLabel(p.reviewerItems[k].topic)), visualDensity: VisualDensity.compact),
                ]),
                Text(p.reviewerItems[k].comment, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('resp-$k-${p.reviewerItems[k].comment.hashCode}'),
                  initialValue: p.reviewerItems[k].response,
                  minLines: 2,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: tr('Réponse', 'Response'), border: const OutlineInputBorder()),
                  onChanged: (v) {
                    p.reviewerItems[k].response = v;
                    context.read<AppState>().saveSoon(p);
                  },
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey('change-$k-${p.reviewerItems[k].comment.hashCode}'),
                  initialValue: p.reviewerItems[k].change,
                  decoration: InputDecoration(labelText: tr('Modification apportée', 'Change made'), isDense: true),
                  onChanged: (v) {
                    p.reviewerItems[k].change = v;
                    context.read<AppState>().saveSoon(p);
                  },
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
