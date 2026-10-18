import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import '../widgets/common.dart';

/// Éditeur de données : corriger une cellule, mettre une valeur en manquant, exclure ou ajouter une ligne. Chaque
/// modification est une correction justifiée et journalisée ; les cellules importées ne sont jamais modifiées.
class DataEditorScreen extends StatefulWidget {
  final Dataset dataset;
  const DataEditorScreen(this.dataset, {super.key});
  @override
  State<DataEditorScreen> createState() => _DataEditorScreenState();
}

class _DataEditorScreenState extends State<DataEditorScreen> {
  late Dataset d = widget.dataset;
  int page = 0;
  static const perPage = 25;
  final filter = TextEditingController();

  String _nextId() => 'c${d.corrections.length + 1}';

  List<int> get _rows {
    final q = filter.text.trim().toLowerCase();
    return [
      for (var i = 0; i < d.rowCount; i++)
        if (q.isEmpty || d.names.any((n) => (d.cell(i, n) ?? '').toLowerCase().contains(q))) i
    ];
  }

  Future<void> _editCell(int row, String name) async {
    final current = d.cell(row, name);
    final value = TextEditingController(text: current ?? '');
    final reason = TextEditingController();
    var missing = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Ligne ${row + 1} — $name', 'Row ${row + 1} — $name')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Valeur importée : ${d.originalCell(row, name) ?? '— (ligne ajoutée)'}', 'Imported value: ${d.originalCell(row, name) ?? '— (added row)'}')),
              if (current != d.originalCell(row, name)) Text(tr('Valeur actuelle : ${current ?? 'manquante'}', 'Current value: ${current ?? 'missing'}')),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: missing,
                onChanged: (v) => setD(() => missing = v ?? false),
                title: Text(tr('Mettre en valeur manquante', 'Set to missing')),
              ),
              if (!missing) TextField(controller: value, autofocus: true, decoration: InputDecoration(labelText: tr('Nouvelle valeur', 'New value'))),
              const SizedBox(height: 8),
              TextField(controller: reason, decoration: InputDecoration(labelText: tr('Justification (obligatoire, journalisée)', 'Justification (required, logged)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
            FilledButton(onPressed: () => reason.text.trim().isEmpty ? null : Navigator.pop(ctx, true), child: Text(tr('Appliquer', 'Apply'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final to = value.text.trim();
    if (!missing && to == (current ?? '')) return;
    setState(() => d = d.applyCorrection(Correction(
          id: _nextId(),
          variable: name,
          action: missing ? 'set_missing' : 'replace',
          rows: [row],
          from: current,
          to: missing ? null : to,
          reason: reason.text.trim(),
          timestamp: AppState.now(),
        )));
  }

  Future<void> _excludeRow(int row) async {
    final reason = await _askReason(tr('Exclure la ligne ${row + 1} de l\'analyse', 'Exclude row ${row + 1} from the analysis'));
    if (reason == null) return;
    setState(() => d = d.applyCorrection(Correction(id: _nextId(), variable: '*', action: 'exclude_row', rows: [row], reason: reason, timestamp: AppState.now())));
  }

  Future<String?> _askReason(String title) {
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

  Future<void> _addRow() async {
    final fields = {for (final n in d.names) n: TextEditingController()};
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Ajouter une ligne', 'Add a row')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final n in d.names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextField(controller: fields[n], decoration: InputDecoration(labelText: n, helperText: varTypeLabel(d.dictionary[n]!.type))),
                ),
              TextField(controller: reason, decoration: InputDecoration(labelText: tr('Justification (obligatoire, journalisée)', 'Justification (required, logged)'))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
          FilledButton(onPressed: () => reason.text.trim().isEmpty ? null : Navigator.pop(ctx, true), child: Text(tr('Ajouter', 'Add'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      d = d.addRow([for (final n in d.names) fields[n]!.text.trim().isEmpty ? null : fields[n]!.text.trim()], id: _nextId(), reason: reason.text.trim(), timestamp: AppState.now());
      page = (_rows.length - 1) ~/ perPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final pages = (rows.length / perPage).ceil().clamp(1, 1 << 30);
    page = page.clamp(0, pages - 1);
    final shown = rows.skip(page * perPage).take(perPage).toList();
    final excluded = d.excludedRows;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, d);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Modifier les données', 'Edit data')),
          leading: IconButton(tooltip: tr('Terminer', 'Done'), icon: const Icon(Icons.check), onPressed: () => Navigator.pop(context, d)),
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _addRow, icon: const Icon(Icons.add), label: Text(tr('Ajouter une ligne', 'Add a row'))),
        body: PageBody(children: [
          Text(
              tr('Touchez une cellule pour la corriger ou la mettre en manquant, ou le numéro d\'une ligne pour l\'exclure. Chaque modification est justifiée et journalisée ; les valeurs importées restent intactes et chaque correction peut être annulée depuis le journal.',
                  'Tap a cell to correct it or set it to missing, or a row number to exclude it. Each change is justified and logged; imported values remain intact and each correction can be undone from the log.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: filter,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.filter_list), labelText: tr('Filtrer les lignes (texte contenu)', 'Filter rows (contained text)')),
            onChanged: (_) => setState(() => page = 0),
          ),
          const SizedBox(height: 8),
          Text(tr('${rows.length} ligne(s) ; ${d.corrections.length} correction(s)', '${rows.length} row(s); ${d.corrections.length} correction(s)'), style: Theme.of(context).textTheme.labelLarge),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 48,
              columnSpacing: 20,
              columns: [const DataColumn(label: Text('#')), for (final n in d.names) DataColumn(label: Text(n))],
              rows: [
                for (final i in shown)
                  DataRow(
                    color: excluded.contains(i) ? WidgetStatePropertyAll(scheme.errorContainer.withValues(alpha: 0.4)) : null,
                    cells: [
                      DataCell(
                          Semantics(
                            button: true,
                            label: tr('Ligne ${i + 1}${excluded.contains(i) ? ', exclue' : ''} : exclure', 'Row ${i + 1}${excluded.contains(i) ? ', excluded' : ''}: exclude'),
                            child: Text('${i + 1}${i >= d.original.length ? ' +' : ''}'),
                          ),
                          onTap: excluded.contains(i) ? null : () => _excludeRow(i)),
                      for (final n in d.names)
                        DataCell(
                          Text(d.cell(i, n) ?? '—',
                              style: d.cell(i, n) != d.originalCell(i, n) ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w700) : null),
                          onTap: () => _editCell(i, n),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: tr('Page précédente', 'Previous page'), onPressed: page > 0 ? () => setState(() => page--) : null, icon: const Icon(Icons.chevron_left)),
            Text(tr('Page ${page + 1} / $pages', 'Page ${page + 1} / $pages')),
            IconButton(tooltip: tr('Page suivante', 'Next page'), onPressed: page < pages - 1 ? () => setState(() => page++) : null, icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 64),
        ]),
      ),
    );
  }
}
