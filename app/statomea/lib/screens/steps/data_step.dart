
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../services/xlsx_import.dart';
import '../data_editor_screen.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Étape 4 : import, aperçu, dictionnaire des variables, contrôle de qualité
/// et corrections journalisées (les données importées ne sont jamais modifiées).
class DataStep extends StatefulWidget {
  final Project p;
  const DataStep(this.p, {super.key});
  @override
  State<DataStep> createState() => DataStepState();
}

class DataStepState extends State<DataStep> {
  List<String> importWarnings = [];
  String? outcomeVar;

  AppState get state => context.read<AppState>();
  Dataset? get ds => widget.p.dataset;

  void _setDataset(Dataset d, List<String> warnings) {
    setState(() {
      widget.p.dataset = d;
      importWarnings = warnings;
    });
    state.save(widget.p);
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv', 'xlsx']);
    if (files.isEmpty || !mounted) return;
    final f = files.single;
    await importFileBytes(f.name, await f.xFile.readAsBytes());
  }

  /// Import d'un fichier CSV ou Excel (public pour les tests) ; un classeur à plusieurs feuilles fait choisir la feuille,
  /// et une feuille « dictionnaire » est appliquée automatiquement.
  Future<void> importFileBytes(String name, List<int> bytes, {String? sheet}) async {
    try {
      var r = datasetFromFile(name, bytes, sheet: sheet);
      final wb = r.workbook;
      if (wb != null && sheet == null) {
        final dict = dictionarySheet(wb);
        final candidates = [for (final s in wb.sheetNames) if (s != dict) s];
        if (candidates.length > 1 && mounted) {
          final chosen = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(title: Text(tr('Feuille à importer', 'Sheet to import')), children: [
              for (final s in candidates) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(s)),
            ]),
          );
          if (chosen == null) return;
          r = datasetFromFile(name, bytes, sheet: chosen);
        }
      }
      var d = r.dataset;
      final w = [...r.warnings];
      final dict = wb == null ? null : dictionarySheet(wb);
      if (wb != null && dict != null) {
        final rep = applyDataDictionary(d, wb.sheet(name: dict), timestamp: DateTime.now().toIso8601String());
        d = rep.dataset;
        w.addAll([tr('Dictionnaire « $dict » appliqué :', 'Dictionary "$dict" applied:'), ...rep.summary()]);
      }
      _setDataset(d, w);
    } catch (e) {
      if (mounted) showError(context, tr('Lecture impossible : $e', 'Reading failed: $e'));
    }
  }

  Future<void> _pickDictionary() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv', 'xlsx']);
    if (files.isEmpty || !mounted) return;
    applyDictionaryBytes(files.single.name, await files.single.xFile.readAsBytes());
  }

  /// Applique un dictionnaire de variables (CSV ou Excel) au jeu de données du projet (public pour les tests).
  void applyDictionaryBytes(String name, List<int> bytes) {
    final d = ds;
    if (d == null) return;
    try {
      final Dataset dict;
      if (name.toLowerCase().endsWith('.xlsx')) {
        final wb = openXlsx(bytes);
        dict = wb.sheet(name: dictionarySheet(wb) ?? wb.sheetNames.first, source: name);
      } else {
        dict = datasetFromFile(name, bytes).dataset;
      }
      final rep = applyDataDictionary(d, dict, timestamp: DateTime.now().toIso8601String());
      _setDataset(rep.dataset, [tr('Dictionnaire « $name » appliqué :', 'Dictionary "$name" applied:'), ...rep.summary()]);
    } catch (e) {
      showError(context, tr('Dictionnaire illisible : $e', 'Unreadable dictionary: $e'));
    }
  }

  void _import(String text, String source) {
    try {
      final res = parseCsv(text, source: source);
      _setDataset(res.dataset, [...importWarnings, ...res.warnings, tr('Séparateur détecté : « ${res.delimiter == '\t' ? 'tabulation' : res.delimiter} ».', 'Detected separator: "${res.delimiter == '\t' ? 'tab' : res.delimiter}".')]);
    } catch (e) {
      showError(context, tr('Lecture impossible : $e', 'Reading failed: $e'));
    }
  }

  Future<void> _manual() async {
    final c = TextEditingController(text: tr('id;groupe;valeur\n1;A;12,5\n2;B;14,1\n', 'id;group;value\n1;A;12.5\n2;B;14.1\n'));
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Saisie manuelle ou collage', 'Manual entry or paste')),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Une ligne par observation, en-tête en première ligne, séparateur « ; », « , » ou tabulation (collage depuis un tableur accepté).', 'One row per observation, header on the first row, separator ";", "," or tab (pasting from a spreadsheet is accepted).')),
            const SizedBox(height: 8),
            TextField(controller: c, minLines: 10, maxLines: 18, style: const TextStyle(fontFamily: 'monospace')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Importer', 'Import'))),
        ],
      ),
    );
    if (text != null) _import(text, tr('saisie manuelle', 'manual entry'));
  }

  Future<String?> _askReason(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: tr('Justification (obligatoire, journalisée)', 'Justification (required, logged)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => c.text.trim().isEmpty ? null : Navigator.pop(ctx, c.text.trim()), child: Text(tr('Appliquer', 'Apply'))),
        ],
      ),
    );
  }

  Future<void> _correct(String action, QualityIssue issue, {String? to, String? from}) async {
    final reason = await _askReason(switch (action) {
      'set_missing' => tr('Mettre ${issue.rows.length} valeur(s) en manquant', 'Set ${issue.rows.length} value(s) to missing'),
      'exclude_row' => tr('Exclure ${issue.rows.length} ligne(s) de l\'analyse', 'Exclude ${issue.rows.length} row(s) from the analysis'),
      _ => tr('Recoder « $from » en « $to »', 'Recode "$from" as "$to"'),
    });
    if (reason == null) return;
    final d = ds!;
    var rows = issue.rows;
    if (action == 'recode') rows = [for (var i = 0; i < d.rowCount; i++) if (d.cell(i, issue.variable!)?.trim() == from) i];
    final c = Correction(
      id: 'c${d.corrections.length + 1}',
      variable: issue.variable ?? '*',
      action: action,
      rows: rows,
      from: from ?? (issue.rows.isNotEmpty && issue.variable != null ? d.cell(issue.rows.first, issue.variable!) : null),
      to: to,
      reason: reason,
      timestamp: AppState.now(),
    );
    _setDataset(d.applyCorrection(c), importWarnings);
  }

  @override
  Widget build(BuildContext context) {
    final d = ds;
    final expert = context.watch<AppState>().expertMode;
    return PageBody(children: [
      Heading(tr('4. Contrôle des données', '4. Data control')),
      Text(tr('Les données importées sont conservées telles quelles. Les corrections sont des opérations justifiées et journalisées, réversibles, appliquées à une copie de travail.', 'Imported data are kept as they are. Corrections are justified, logged, reversible operations applied to a working copy.')),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_file), label: Text(tr('Importer un fichier (CSV, Excel)', 'Import a file (CSV, Excel)'))),
        if (ds != null)
          OutlinedButton.icon(onPressed: _pickDictionary, icon: const Icon(Icons.menu_book_outlined), label: Text(tr('Appliquer un dictionnaire de variables', 'Apply a variable dictionary'))),
        OutlinedButton.icon(onPressed: _manual, icon: const Icon(Icons.keyboard), label: Text(tr('Saisie manuelle / coller', 'Manual entry / paste'))),
        if (d != null)
          TextButton.icon(
            onPressed: () {
              setState(() => widget.p.dataset = null);
              state.save(widget.p);
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(tr('Retirer les données du projet', 'Remove the data from the project')),
          ),
      ]),
      const SizedBox(height: 6),
      Text(tr('Préférez des données anonymisées (pas de nom ni d\'identifiant direct).', 'Prefer anonymized data (no name or direct identifier).'), style: Theme.of(context).textTheme.bodySmall),
      for (final w in importWarnings) Banner2(Severity.info, w),
      if (d == null && widget.p.studies.isNotEmpty)
        Banner2(Severity.info, tr('Projet de métaanalyse : le tableau d\'extraction se saisit dans l\'atelier de métaanalyse (étape 6).', 'Meta-analysis project: the extraction table is entered in the meta-analysis workshop (step 6).')),
      if (d != null) ...[
        const SizedBox(height: 12),
        Text(tr('Aperçu — ${d.source} : ${d.rowCount} lignes × ${d.names.length} variables', 'Preview — ${d.source}: ${d.rowCount} rows × ${d.names.length} variables'), style: Theme.of(context).textTheme.titleMedium),
        _Preview(d),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_note),
            label: Text(tr('Modifier les données (cellules, lignes)', 'Edit data (cells, rows)')),
            onPressed: () async {
              final edited = await Navigator.push<Dataset>(context, MaterialPageRoute(builder: (_) => DataEditorScreen(d)));
              if (edited != null && edited.corrections.length != d.corrections.length) _setDataset(edited, importWarnings);
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('Dictionnaire des variables', 'Variable dictionary'), style: Theme.of(context).textTheme.titleMedium),
        Text(tr('Déclarez le type, l\'unité, les bornes plausibles et la catégorie de référence : ces déclarations priment sur l\'inférence automatique.', 'Declare the type, unit, plausible bounds and reference category: these declarations take precedence over automatic inference.')),
        for (final n in d.names) _VariableEditor(d, n, onChanged: () => setState(() => state.save(widget.p)), expert: expert),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr('Contrôle de qualité', 'Quality control'), style: Theme.of(context).textTheme.titleMedium),
          Pick<String>(tr('Issue (facultatif)', 'Outcome (optional)'), outcomeVar, [for (final n in d.names) (n, n)], (v) => setState(() => outcomeVar = v), width: 220),
        ]),
        ..._quality(d),
        if (d.corrections.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Journal des corrections', 'Correction log'), style: Theme.of(context).textTheme.titleMedium),
          for (final c in d.corrections)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text(c.describe()),
              subtitle: Text('${c.id} · ${c.timestamp}'),
              trailing: IconButton(
                tooltip: tr('Annuler cette correction', 'Undo this correction'),
                icon: const Icon(Icons.undo),
                onPressed: () => _setDataset(d.withoutCorrection(c.id), importWarnings),
              ),
            ),
        ],
      ],
    ]);
  }

  List<Widget> _quality(Dataset d) {
    final predictors = [for (final n in d.names) if (n != outcomeVar && d.dictionary[n]!.type != VarType.identifier) n];
    final rep = checkQuality(d, outcome: outcomeVar, predictors: predictors);
    if (rep.issues.isEmpty) return [Banner2(Severity.info, tr('Aucune anomalie détectée par les contrôles automatiques.', 'No anomaly detected by the automatic checks.'))];
    return [
      Text(tr('${rep.count(Severity.critical)} bloquante(s), ${rep.count(Severity.serious)} grave(s), ${rep.count(Severity.caution)} à surveiller, ${rep.count(Severity.info)} information(s).', '${rep.count(Severity.critical)} blocking, ${rep.count(Severity.serious)} serious, ${rep.count(Severity.caution)} to watch, ${rep.count(Severity.info)} information.')),
      for (final i in rep.issues)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Banner2(i.severity, i.message, suggestion: i.suggestion),
          Wrap(spacing: 6, children: [
            if (i.rows.isNotEmpty && i.variable != null && const {'out_of_range', 'non_numeric', 'negative_values'}.contains(i.code))
              TextButton(onPressed: () => _correct('set_missing', i), child: Text(tr('Mettre en manquant…', 'Set to missing…'))),
            if (i.rows.isNotEmpty && const {'duplicate_rows', 'out_of_range', 'repeated_id'}.contains(i.code))
              TextButton(onPressed: () => _correct('exclude_row', i), child: Text(tr('Exclure ces lignes…', 'Exclude these rows…'))),
            if (i.code == 'inconsistent_labels') ..._recodeButtons(d, i),
          ]),
        ]),
    ];
  }

  List<Widget> _recodeButtons(Dataset d, QualityIssue i) {
    final values = <String>{for (final v in d.text(i.variable!)) ?v};
    final groups = <String, List<String>>{};
    for (final v in values) {
      groups.putIfAbsent(v.toLowerCase().replaceAll(RegExp(r'\s+'), ' '), () => []).add(v);
    }
    final out = <Widget>[];
    for (final g in groups.values.where((g) => g.length > 1)) {
      final target = g.first.trim();
      for (final v in g.skip(1)) {
        out.add(TextButton(onPressed: () => _correct('recode', i, from: v, to: target), child: Text(tr('Recoder « $v » → « $target »…', 'Recode "$v" → "$target"…'))));
      }
      // Les valeurs avec espaces superflus sont lues après trim : proposer aussi l'inverse.
    }
    return out;
  }
}

class _Preview extends StatelessWidget {
  final Dataset d;
  const _Preview(this.d);
  @override
  Widget build(BuildContext context) {
    final rows = [for (var i = 0; i < d.rowCount && i < 30; i++) i];
    final excluded = d.excludedRows;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 26,
        dataRowMaxHeight: 30,
        columnSpacing: 18,
        columns: [
          const DataColumn(label: Text('#')),
          for (final n in d.names) DataColumn(label: Text('$n\n${varTypeLabel(d.dictionary[n]!.type)}', style: const TextStyle(fontSize: 11))),
        ],
        rows: [
          for (final i in rows)
            DataRow(
              color: excluded.contains(i) ? WidgetStatePropertyAll(Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4)) : null,
              cells: [
                DataCell(Text('${i + 2}', style: const TextStyle(fontSize: 11))),
                for (final n in d.names)
                  // Valeur corrigée : couleur d'erreur (contraste ≥ 4,5:1) ET italique soulignée, pour ne pas reposer sur la seule couleur.
                  DataCell(d.cell(i, n) != d.originalCell(i, n)
                      ? Semantics(
                          label: tr('${d.cell(i, n) ?? 'manquant'} (corrigée)', '${d.cell(i, n) ?? 'missing'} (corrected)'),
                          excludeSemantics: true,
                          child: Text(d.cell(i, n) ?? '—',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                  fontStyle: FontStyle.italic,
                                  decoration: TextDecoration.underline)))
                      : Text(d.cell(i, n) ?? '', style: const TextStyle(fontSize: 12))),
              ],
            ),
        ],
      ),
    );
  }
}

class _VariableEditor extends StatelessWidget {
  final Dataset d;
  final String name;
  final VoidCallback onChanged;
  final bool expert;
  const _VariableEditor(this.d, this.name, {required this.onChanged, required this.expert});
  @override
  Widget build(BuildContext context) {
    final v = d.dictionary[name]!;
    final levels = (v.type == VarType.categorical || v.type == VarType.binary || v.type == VarType.ordinal) ? d.levels(name) : <String>[];
    final unit = TextEditingController(text: v.unit);
    final min = TextEditingController(text: v.min?.toString() ?? '');
    final max = TextEditingController(text: v.max?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 160, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
        Pick<VarType>(tr('Type${v.declared ? " (déclaré)" : " (inféré)"}', 'Type${v.declared ? " (declared)" : " (inferred)"}'), v.type, [for (final t in VarType.values) (t, varTypeLabel(t))], (t) {
          if (t == null) return;
          v.type = t;
          v.declared = true;
          onChanged();
        }, width: 190),
        if (v.type == VarType.numeric) ...[
          SizedBox(width: 90, child: TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unité', 'Unit')), onSubmitted: (s) { v.unit = s; onChanged(); })),
          if (expert || v.min != null || v.max != null) ...[
            SizedBox(width: 90, child: TextField(controller: min, decoration: InputDecoration(labelText: tr('Min plausible', 'Plausible min')), onSubmitted: (s) { v.min = parseNumber(s); onChanged(); })),
            SizedBox(width: 90, child: TextField(controller: max, decoration: InputDecoration(labelText: tr('Max plausible', 'Plausible max')), onSubmitted: (s) { v.max = parseNumber(s); onChanged(); })),
          ],
        ],
        if (levels.length >= 2)
          Pick<String>(tr('Référence', 'Reference'), v.reference, [for (final l in levels) (l, l)], (r) {
            v.reference = r;
            onChanged();
          }, width: 170),
      ]),
    );
  }
}
