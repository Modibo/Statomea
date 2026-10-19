import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/crf_workbook.dart';
import '../services/file_saver.dart';
import '../services/pdf_export.dart';
import '../services/protocol_annotate.dart';
import '../services/protocol_document.dart';
import '../state/app_state.dart';
import '../widgets/calculators.dart';
import '../widgets/common.dart';
import 'project_screen.dart';

/// Couleur et icône d'un niveau de constat.
(Color, IconData) reviewLevelStyle(BuildContext context, ReviewLevel l) => switch (l) {
      ReviewLevel.error => (Theme.of(context).colorScheme.error, Icons.error_outline),
      ReviewLevel.warning => (Colors.amber.shade800, Icons.warning_amber_outlined),
      ReviewLevel.missing => (Colors.blueGrey.shade600, Icons.help_outline),
      ReviewLevel.ok => (Colors.green.shade700, Icons.check_circle_outline),
    };

/// Relecture méthodologique : erreurs, points à revoir et manques du projet (ou du protocole importé), avec le passage
/// en cause et la correction ; les corrections proposées s'appliquent une à une ou toutes ensemble, et sont tracées.
class ReviewScreen extends StatefulWidget {
  final Project project;
  const ReviewScreen(this.project, {super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  Project get p => widget.project;

  Future<void> _save(String message) async {
    await context.read<AppState>().save(p);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyOne(ReviewFinding f) async {
    applyCorrection(p, f);
    await _save(tr('Correction appliquée : ${f.fix!.detail}', 'Correction applied: ${f.fix!.detail}'));
  }

  Future<void> _applyAll(List<ReviewFinding> fixable) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Appliquer ${fixable.length} correction(s) ?', 'Apply ${fixable.length} correction(s)?')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Le projet sera modifié ainsi (chaque correction est tracée et reprise dans le protocole prérédigé) :', 'The project will be changed as follows (each correction is logged and included in the pre-drafted protocol):')),
              const SizedBox(height: 8),
              for (final f in fixable) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  ${f.fix!.detail}')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Appliquer', 'Apply'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = applyAllCorrections(p);
    await _save(tr('${done.length} correction(s) appliquée(s).', '${done.length} correction(s) applied.'));
  }

  Future<void> _print() async {
    final bytes = await buildReviewPdf(p, generatedAt: AppState.now());
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'statomea-relecture-${p.id}.pdf');
  }

  /// Protocole Word d'origine annoté (commentaires + récapitulatif) ; pour un PDF, le protocole prérédigé intégrant les
  /// corrections.
  Future<void> _correctedWord() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['docx', 'pdf']);
    if (files.isEmpty || !mounted) return;
    final f = files.single.xFile;
    final bytes = await f.readAsBytes();
    final base = f.name.replaceFirst(RegExp(r'\.(docx|pdf)$', caseSensitive: false), '');
    String message;
    try {
      if (f.name.toLowerCase().endsWith('.docx')) {
        final a = annotateProtocolDocx(bytes, p);
        final where = await saveFile('$base-relu-Statomea.docx', a.bytes, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        message = tr('Protocole annoté enregistré ($where) : ${a.anchored} commentaire(s) dans le texte, ${a.total} point(s) récapitulé(s) en fin de document.',
            'Annotated protocol saved ($where): ${a.anchored} comment(s) in the text, ${a.total} point(s) summarised at the end.');
      } else {
        final where = await saveFile('$base-corrige-Statomea.docx', protocolDocx(p), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        message = tr('Un PDF ne peut pas être annoté : protocole prérédigé, corrections intégrées, enregistré ($where).', 'A PDF cannot be annotated: pre-drafted protocol with corrections included, saved ($where).');
      }
    } on StatInputError catch (e) {
      message = e.message;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
  }

  void _openCalculator(String id, Map<String, String> presets) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(tr('Calcul d\'effectif', 'Sample size calculation'))),
                body: PageBody(children: [CalculatorPanel(project: p, initialMethod: id, presets: presets)]),
              )));

  @override
  Widget build(BuildContext context) {
    final r = reviewProject(p);
    final theme = Theme.of(context);
    final fixable = r.fixable;
    final vars = protocolVariables(p);
    final labs = protocolLabTests(p);
    final grid = p.protocol.isEmpty ? null : protocolChecklist(p);
    Widget count(ReviewLevel l) {
      final (c, icon) = reviewLevelStyle(context, l);
      return Chip(avatar: Icon(icon, size: 18, color: c), label: Text('${reviewLevelLabel(l)} : ${r.count(l)}'), side: BorderSide(color: c.withValues(alpha: 0.5)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Relecture et corrections', 'Review and corrections')),
        actions: [IconButton(tooltip: tr('Imprimer ou enregistrer en PDF', 'Print or save as PDF'), icon: const Icon(Icons.print_outlined), onPressed: _print)],
      ),
      body: PageBody(maxWidth: 900, children: [
        Heading(p.title),
        Text(
            p.protocol.isNotEmpty
                ? tr('Statoméa relit le protocole importé : question, plan d\'étude, nombre de sujets (recalculé quand les hypothèses sont données), plan d\'analyse et éthique. Chaque point cite le passage en cause ; les corrections proposées s\'appliquent au projet, sont tracées et reprises dans le protocole prérédigé.',
                    'Statoméa reviews the imported protocol: question, study design, sample size (recomputed when the assumptions are given), analysis plan and ethics. Each point quotes the passage concerned; proposed corrections are applied to the project, logged and included in the pre-drafted protocol.')
                : tr('Statoméa relit le projet : question, plan d\'étude, nombre de sujets et plan d\'analyse. Les corrections proposées s\'appliquent au projet, sont tracées et reprises dans le protocole prérédigé.',
                    'Statoméa reviews the project: question, study design, sample size and analysis plan. Proposed corrections are applied to the project, logged and included in the pre-drafted protocol.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [for (final l in ReviewLevel.values) count(l)]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (fixable.isNotEmpty)
            FilledButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: Text(tr('Appliquer les ${fixable.length} corrections proposées', 'Apply the ${fixable.length} proposed corrections')),
                onPressed: () => _applyAll(fixable)),
          OutlinedButton.icon(icon: const Icon(Icons.print_outlined), label: Text(tr('Rapport de relecture (PDF)', 'Review report (PDF)')), onPressed: _print),
          if (p.protocol.isNotEmpty)
            OutlinedButton.icon(
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(tr('Protocole corrigé (Word)', 'Corrected protocol (Word)')),
                onPressed: _correctedWord),
        ]),
        const SizedBox(height: 12),
        if (r.problems.isEmpty)
          Card(
            child: ListTile(
              leading: Icon(Icons.verified_outlined, color: Colors.green.shade700),
              title: Text(tr('Aucun problème relevé', 'No problem found')),
              subtitle: Text(tr('Les contrôles de Statoméa ne relèvent ni erreur ni manque. Ils ne remplacent pas la relecture d\'un méthodologiste.', 'Statoméa\'s checks find no error or gap. They do not replace review by a methodologist.')),
            ),
          ),
        for (final f in r.problems) _FindingCard(f, onApply: () => _applyOne(f), onCalculator: f.calculator == null ? null : () => _openCalculator(f.calculator!, f.calculatorPresets), project: p),
        if (grid != null) ...[
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: Icon(Icons.checklist, color: grid.missing.isEmpty ? Colors.green.shade700 : Colors.amber.shade800),
              title: Text(tr('Grille ${grid.name} : ${grid.present} / ${grid.items.length} éléments trouvés', '${grid.name} checklist: ${grid.present} / ${grid.items.length} items found')),
              subtitle: Text(grid.reference, style: theme.textTheme.bodySmall),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('« Absent » : Statoméa ne l\'a pas reconnu dans le texte — à ajouter ou à vérifier.', '"Absent": Statoméa did not recognise it in the text — to add or check.'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                for (final it in grid.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(it.present ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: it.present ? Colors.green.shade700 : theme.colorScheme.error),
                      const SizedBox(width: 8),
                      SizedBox(width: 34, child: Text(it.code, style: theme.textTheme.labelSmall)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.label + (it.present ? '' : tr(' — absent', ' — absent')), style: TextStyle(fontWeight: it.present ? FontWeight.normal : FontWeight.w600)),
                          if (it.evidence != null) Text('« ${it.evidence} »', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                        ]),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
        if (vars.isNotEmpty || labs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (vars.isNotEmpty) Text(tr('Variables prévues par le protocole (${vars.length})', 'Variables planned in the protocol (${vars.length})'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(tr('Noms de colonnes et types proposés : le dictionnaire de données sert de modèle pour la saisie et s\'importe avec les données à l\'étape 4.', 'Proposed column names and types: the data dictionary serves as a template for data entry and is imported with the data at step 4.'),
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final v in vars) Chip(label: Text('${v.code} · ${v.type}'), visualDensity: VisualDensity.compact)]),
                if (labs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(tr('Examens de laboratoire prévus (${labs.length})', 'Planned laboratory tests (${labs.length})'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final l in labs) Text('• ${l.label}${l.method == null ? '' : ' — ${l.method}'}', style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                CrfButtons(p),
              ]),
            ),
          ),
        ],
        if (r.checked.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Vérifications réussies', 'Successful checks'), style: theme.textTheme.titleMedium),
          for (final f in r.checked) _FindingCard(f, project: p),
        ],
        if (p.corrections.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Corrections appliquées', 'Corrections applied'), style: theme.textTheme.titleMedium),
          for (final c in p.corrections)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 20),
              title: Text(c.title),
              subtitle: Text('${c.date} — ${c.detail}'),
            ),
        ],
        const SizedBox(height: 8),
        Text(tr('Relecture par règles explicites, sans modèle de langage : elle signale ce qu\'elle sait reconnaître et ne remplace pas la relecture d\'un méthodologiste.', 'Review by explicit rules, without a language model: it flags what it can recognise and does not replace review by a methodologist.'),
            style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final ReviewFinding f;
  final Project project;
  final VoidCallback? onApply, onCalculator;
  const _FindingCard(this.f, {required this.project, this.onApply, this.onCalculator});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon) = reviewLevelStyle(context, f.level);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.45))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(f.title, style: theme.textTheme.titleSmall)),
            const SizedBox(width: 8),
            Text(reviewLevelLabel(f.level), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          Padding(padding: const EdgeInsets.only(left: 28, top: 2), child: Text(stepLabel(f.step), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
          const SizedBox(height: 6),
          Text(f.problem),
          if (f.evidence != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3))),
              child: Text('« ${f.evidence} »', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ),
          if (f.correction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: f.level == ReviewLevel.ok ? '' : tr('Correction : ', 'Correction: '), style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: f.correction),
            ])),
          ],
          if (f.level != ReviewLevel.ok)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 10, runSpacing: 6, children: [
                if (f.fix != null && onApply != null) FilledButton.tonalIcon(icon: const Icon(Icons.auto_fix_high, size: 18), label: Text(tr('Appliquer la correction', 'Apply the correction')), onPressed: onApply),
                if (onCalculator != null) OutlinedButton.icon(icon: const Icon(Icons.calculate_outlined, size: 18), label: Text(tr('Calculer l\'effectif', 'Compute the sample size')), onPressed: onCalculator),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(tr('Ouvrir l\'étape', 'Open the step')),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: project, initialStep: f.step))),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Résumé de la relecture (erreurs, points à revoir, manques) avec accès à l'écran de relecture.
class ReviewBanner extends StatelessWidget {
  final Project project;
  final VoidCallback? onReturn;
  const ReviewBanner(this.project, {super.key, this.onReturn});

  @override
  Widget build(BuildContext context) {
    final r = reviewProject(project);
    final e = r.count(ReviewLevel.error), w = r.count(ReviewLevel.warning), m = r.count(ReviewLevel.missing);
    final level = e > 0 ? ReviewLevel.error : (w > 0 ? ReviewLevel.warning : (m > 0 ? ReviewLevel.missing : ReviewLevel.ok));
    final (color, icon) = reviewLevelStyle(context, level);
    final summary = level == ReviewLevel.ok
        ? tr('Relecture méthodologique : aucun problème relevé.', 'Methodological review: no problem found.')
        : tr('Relecture méthodologique : $e erreur(s), $w point(s) à revoir, $m élément(s) manquant(s) ; ${r.fixable.length} correction(s) applicable(s) d\'un appui.',
            'Methodological review: $e error(s), $w point(s) to review, $m missing item(s); ${r.fixable.length} correction(s) can be applied in one tap.');
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(width: 8), Expanded(child: Text(summary))]),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(tr('Relire et corriger', 'Review and correct')),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(project)));
              onReturn?.call();
            },
          ),
        ]),
      ),
    );
  }
}

/// Fiche de recueil (PDF imprimable), masque de saisie (Excel, listes et bornes) et dictionnaire de données (CSV).
class CrfButtons extends StatelessWidget {
  final Project project;
  const CrfButtons(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    final fields = crfFields(project);
    if (fields.isEmpty) return const SizedBox.shrink();
    void done(String where) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Enregistré : $where', 'Saved: $where'))));
    return Wrap(spacing: 10, runSpacing: 8, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.assignment_outlined),
        label: Text(tr('Fiche de recueil (PDF)', 'Case report form (PDF)')),
        onPressed: () async {
          final bytes = await buildCrfPdf(project, fields);
          await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'fiche-recueil-${project.id}.pdf');
        },
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.grid_on_outlined),
        label: Text(tr('Masque de saisie (Excel)', 'Data entry template (Excel)')),
        onPressed: () async {
          final where = await saveFile('saisie-${project.id}.xlsx', crfWorkbook(fields, title: project.title), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          if (context.mounted) done(where);
        },
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.table_view_outlined),
        label: Text(tr('Dictionnaire de données (CSV)', 'Data dictionary (CSV)')),
        onPressed: () async {
          final where = await saveFile('dictionnaire-${project.id}.csv', utf8.encode('\uFEFF${crfDictionaryCsv(fields)}'), 'text/csv');
          if (context.mounted) done(where);
        },
      ),
    ]);
  }
}
