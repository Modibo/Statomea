import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import '../widgets/common.dart';

/// Bibliographie du projet : import RIS (Zotero, Mendeley, EndNote), BibTeX ou MEDLINE (PubMed), saisie manuelle ;
/// chaque référence a une clé à citer « [@clé] » dans les textes ; numérotation et liste de Vancouver dans le
/// protocole et l'article prérédigés.
class ReferencesScreen extends StatefulWidget {
  final Project project;
  const ReferencesScreen(this.project, {super.key});
  @override
  State<ReferencesScreen> createState() => _ReferencesScreenState();
}

class _ReferencesScreenState extends State<ReferencesScreen> {
  Project get p => widget.project;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    await context.read<AppState>().save(p);
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ris', 'bib', 'nbib', 'txt']);
    if (files.isEmpty || !mounted) return;
    final text = utf8.decode(await files.single.xFile.readAsBytes(), allowMalformed: true);
    try {
      final refs = parseReferences(text, existingKeys: p.references.map((r) => r.key));
      p.references.addAll(refs);
      await _save();
      _snack(tr('${refs.length} référence(s) importée(s).', '${refs.length} reference(s) imported.'));
    } on StatInputError catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _add() async {
    final c = {for (final k in ['authors', 'title', 'journal', 'year', 'volume', 'issue', 'pages', 'doi']) k: TextEditingController()};
    final labels = {
      'authors': tr('Auteurs (un par ligne, « Nom Prénom » ou « Nom, Prénom »)', 'Authors (one per line, "Last First" or "Last, First")'),
      'title': tr('Titre', 'Title'),
      'journal': tr('Revue', 'Journal'),
      'year': tr('Année', 'Year'),
      'volume': 'Volume',
      'issue': tr('Numéro', 'Issue'),
      'pages': 'Pages',
      'doi': 'DOI',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ajouter une référence', 'Add a reference')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in c.entries)
                TextField(controller: e.value, minLines: e.key == 'authors' ? 2 : 1, maxLines: e.key == 'authors' ? 6 : 1, decoration: InputDecoration(labelText: labels[e.key])),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ajouter', 'Add'))),
        ],
      ),
    );
    if (ok != true || c['title']!.text.trim().isEmpty) return;
    final draft = Reference(
      key: '',
      authors: [for (final a in c['authors']!.text.split('\n')) if (a.trim().isNotEmpty) vancouverName(a)],
      title: c['title']!.text.trim(),
      journal: c['journal']!.text.trim(),
      year: c['year']!.text.trim(),
      volume: c['volume']!.text.trim(),
      issue: c['issue']!.text.trim(),
      pages: c['pages']!.text.trim(),
      doi: c['doi']!.text.trim(),
    );
    final first = draft.authors.isEmpty ? 'ref' : draft.authors.first.split(' ').first;
    final base = '${first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}${draft.year}';
    var key = base.isEmpty ? 'ref' : base;
    var k = 0;
    while (p.references.any((r) => r.key == key)) {
      key = '$base${String.fromCharCode(97 + k++)}';
    }
    p.references.add(draft.withKey(key));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numbers = referenceNumbers(p.references, [p.analysisPlan, p.resultsText, p.question.text]);
    final sorted = [...p.references]..sort((a, b) => numbers[a.key]!.compareTo(numbers[b.key]!));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bibliographie', 'Bibliography'))),
      body: PageBody(maxWidth: 900, children: [
        Heading(p.title),
        Text(
            tr('Importez un export RIS (Zotero, Mendeley, EndNote), BibTeX ou MEDLINE (PubMed, « Send to → Citation manager »), ou saisissez une référence. Citez-la dans vos textes (plan d\'analyse, résultats) par sa clé, p. ex. « [@smith2020] » : elle est numérotée dans l\'ordre de citation et listée au style de Vancouver dans le protocole et l\'article.',
                'Import an RIS (Zotero, Mendeley, EndNote), BibTeX or MEDLINE (PubMed, "Send to → Citation manager") export, or enter a reference. Cite it in your texts (analysis plan, results) by its key, e.g. "[@smith2020]": it is numbered in citation order and listed in Vancouver style in the protocol and the article.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(icon: const Icon(Icons.file_upload_outlined), label: Text(tr('Importer (RIS, BibTeX, PubMed)', 'Import (RIS, BibTeX, PubMed)')), onPressed: _import),
          OutlinedButton.icon(icon: const Icon(Icons.add), label: Text(tr('Ajouter à la main', 'Add manually')), onPressed: _add),
        ]),
        const SizedBox(height: 12),
        if (p.references.isEmpty) Text(tr('Aucune référence pour l\'instant.', 'No references yet.'), style: theme.textTheme.bodyMedium),
        for (final r in sorted)
          Card(
            child: ListTile(
              leading: CircleAvatar(radius: 14, child: Text('${numbers[r.key]}', style: const TextStyle(fontSize: 12))),
              title: Text(vancouver(r)),
              subtitle: Text('[@${r.key}]'),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: tr('Copier la citation', 'Copy the citation'),
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '[@${r.key}]'));
                    if (mounted) _snack(tr('Citation copiée : [@${r.key}]', 'Citation copied: [@${r.key}]'));
                  },
                ),
                IconButton(
                  tooltip: tr('Supprimer', 'Delete'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    p.references.removeWhere((x) => x.key == r.key);
                    await _save();
                  },
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
