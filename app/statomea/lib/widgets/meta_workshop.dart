import 'package:file_picker/file_picker.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import 'calculators.dart';
import 'common.dart';

const _binaryKeys = ['e1', 'n1', 'e2', 'n2'];
const _contKeys = ['m1', 'sd1', 'n1', 'm2', 'sd2', 'n2'];
const _diagKeys = ['tp', 'fp', 'fn', 'tn'];
Map<String, String> get _keyLabels => {
  'e1': tr('Évén. gr. 1', 'Events gr. 1'),
  'n1': 'n gr. 1',
  'e2': tr('Évén. gr. 2', 'Events gr. 2'),
  'n2': 'n gr. 2',
  'm1': tr('Moy. 1', 'Mean 1'),
  'sd1': tr('ÉT 1', 'SD 1'),
  'm2': tr('Moy. 2', 'Mean 2'),
  'sd2': tr('ÉT 2', 'SD 2'),
  'tp': tr('VP', 'TP'),
  'fp': 'FP',
  'fn': 'FN',
  'tn': tr('VN', 'TN'),
};

/// Atelier de métaanalyse : tableau d'extraction traçable (source et statut
/// de chaque valeur), grille de compatibilité, options du modèle.
class MetaWorkshop extends StatefulWidget {
  final Project? project;
  final OnResult onResult;
  const MetaWorkshop({super.key, required this.project, required this.onResult});
  @override
  State<MetaWorkshop> createState() => _MetaWorkshopState();
}

class _MetaWorkshopState extends State<MetaWorkshop> {
  late List<Study> studies = [...?widget.project?.studies];
  late bool continuous = studies.isNotEmpty && studies.first.values.containsKey('m1');
  late bool diagnostic = studies.isNotEmpty && studies.first.values.containsKey('tp');
  List<String> get _keys => diagnostic ? _diagKeys : (continuous ? _contKeys : _binaryKeys);
  String get _kind => diagnostic ? 'diag' : (continuous ? 'cont' : 'bin');
  EffectMeasure measure = EffectMeasure.rr;
  TauMethod method = TauMethod.reml;
  bool knha = false, mh = false;
  final Set<String> mods = {};
  bool modSubgroup = false;

  /// Valeurs extraites qui ne servent pas au calcul de l'effet : modérateurs potentiels.
  List<String> get moderatorKeys {
    final effectKeys = {..._binaryKeys, ..._contKeys, ..._diagKeys, 'yi', 'sei'};
    return {for (final st in studies) ...st.values.keys.where((k) => !effectKeys.contains(k))}.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    if (continuous) measure = EffectMeasure.md;
  }

  void _persist() {
    final p = widget.project;
    if (p == null) return;
    p.studies = studies;
    context.read<AppState>().saveSoon(p);
  }

  Future<void> _importCsv() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    if (files.isEmpty) return;
    final file = files.single;
    final ds = parseCsv(utf8.decode(await file.xFile.readAsBytes(), allowMalformed: true), source: file.name).dataset;
    final keys = _keys;
    // Noms de colonnes insensibles à la casse (TP, FP, FN, TN acceptés).
    String? col(String k) => ds.names.where((n) => n.toLowerCase() == k).firstOrNull;
    final missing = keys.where((k) => col(k) == null).toList();
    if (missing.isNotEmpty) {
      if (mounted) showError(context, tr('Colonnes attendues : étude ; ${keys.join(" ; ")} [; sous_groupe]. Manquantes : ${missing.join(", ")}.', 'Expected columns: etude; ${keys.join("; ")} [; sous_groupe]. Missing: ${missing.join(", ")}.'));
      return;
    }
    final label = ds.names.first;
    setState(() {
      studies = [
        for (var i = 0; i < ds.rowCount; i++)
          Study('s${i + 1}', ds.cell(i, label) ?? tr('Étude ${i + 1}', 'Study ${i + 1}'), {
            for (final k in keys) k: SourcedValue(parseNumber(ds.cell(i, col(k)!)), source: file.name),
          }, subgroup: ds.names.contains('sous_groupe') ? (ds.cell(i, 'sous_groupe') ?? '') : '')
      ];
    });
    _persist();
  }

  Future<void> _edit([int? index]) async {
    final keys = _keys;
    final s = index == null ? null : studies[index];
    final label = TextEditingController(text: s?.label ?? tr('Étude ${studies.length + 1}', 'Study ${studies.length + 1}'));
    final sub = TextEditingController(text: s?.subgroup ?? '');
    final ctrl = {for (final k in keys) k: TextEditingController(text: s?.v(k) == null ? '' : _num(s!.v(k)!))};
    final src = {for (final k in keys) k: TextEditingController(text: s?.values[k]?.source ?? '')};
    final prov = {for (final k in keys) k: s?.values[k]?.provenance ?? Provenance.reported};
    var compat = s?.compatibility ?? const StudyCompatibility();
    var excluded = s?.excluded ?? false;
    final reason = TextEditingController(text: s?.exclusionReason ?? '');
    final modText = TextEditingController(text: [
      for (final e in (s?.values ?? const <String, SourcedValue>{}).entries)
        if (!keys.contains(e.key) && e.value.value != null) '${e.key}=${_num(e.value.value!)}'
    ].join(' ; '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(index == null ? tr('Ajouter une étude', 'Add a study') : tr('Modifier l\'étude', 'Edit the study')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: label, decoration: InputDecoration(labelText: tr('Étude (auteur, année)', 'Study (author, year)'))),
                const SizedBox(height: 8),
                TextField(controller: sub, decoration: InputDecoration(labelText: tr('Sous-groupe prévu a priori (facultatif)', 'Subgroup planned a priori (optional)'))),
                const SizedBox(height: 12),
                Text(tr('Données extraites — pour chaque valeur : source et statut', 'Extracted data — for each value: source and status'), style: TextStyle(fontWeight: FontWeight.w600)),
                for (final k in keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      NumField(_keyLabels[k] ?? k, ctrl[k]!, width: 120),
                      Pick<Provenance>(tr('Statut', 'Status'), prov[k], [for (final pv in Provenance.values) (pv, provenanceLabel(pv))], (v) => setD(() => prov[k] = v ?? Provenance.reported), width: 190),
                      SizedBox(width: 200, child: TextField(controller: src[k], decoration: InputDecoration(labelText: tr('Source (tableau, page)', 'Source (table, page)')))),
                    ]),
                  ),
                const SizedBox(height: 8),
                TextField(
                    controller: modText,
                    decoration: InputDecoration(
                        labelText: tr('Caractéristiques de l\'étude pour la méta-régression (facultatif)', 'Study characteristics for meta-regression (optional)'),
                        hintText: tr('p. ex. latitude=44 ; annee=1948 ; dose=10', 'e.g. latitude=44; year=1948; dose=10'))),
                const SizedBox(height: 12),
                Text(tr('Compatibilité avec la question (obligatoire avant de combiner)', 'Compatibility with the question (required before pooling)'), style: TextStyle(fontWeight: FontWeight.w600)),
                for (final (name, get, set) in <(String, Compat Function(StudyCompatibility), StudyCompatibility Function(Compat))>[
                  ('Population', (c) => c.population, (v) => StudyCompatibility(population: v, comparator: compat.comparator, outcome: compat.outcome, followUp: compat.followUp, measure: compat.measure, comment: compat.comment)),
                  (tr('Comparateur', 'Comparator'), (c) => c.comparator, (v) => StudyCompatibility(population: compat.population, comparator: v, outcome: compat.outcome, followUp: compat.followUp, measure: compat.measure, comment: compat.comment)),
                  (tr('Critère de jugement', 'Outcome'), (c) => c.outcome, (v) => StudyCompatibility(population: compat.population, comparator: compat.comparator, outcome: v, followUp: compat.followUp, measure: compat.measure, comment: compat.comment)),
                  (tr('Durée de suivi', 'Follow-up duration'), (c) => c.followUp, (v) => StudyCompatibility(population: compat.population, comparator: compat.comparator, outcome: compat.outcome, followUp: v, measure: compat.measure, comment: compat.comment)),
                  (tr('Mesure d\'effet', 'Effect measure'), (c) => c.measure, (v) => StudyCompatibility(population: compat.population, comparator: compat.comparator, outcome: compat.outcome, followUp: compat.followUp, measure: v, comment: compat.comment)),
                ])
                  Row(children: [
                    SizedBox(width: 150, child: Text(name)),
                    SegmentedButton<Compat>(
                      segments: const [
                        ButtonSegment(value: Compat.yes, label: Text('oui')),
                        ButtonSegment(value: Compat.unclear, label: Text('incertain')),
                        ButtonSegment(value: Compat.no, label: Text('non')),
                      ],
                      selected: {get(compat)},
                      onSelectionChanged: (x) => setD(() => compat = set(x.first)),
                    ),
                  ]),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: excluded,
                  onChanged: (v) => setD(() => excluded = v ?? false),
                  title: Text(tr('Exclure cette étude du calcul', 'Exclude this study from the calculation')),
                ),
                if (excluded) TextField(controller: reason, decoration: InputDecoration(labelText: tr('Raison de l\'exclusion', 'Reason for exclusion'))),
              ]),
            ),
          ),
          actions: [
            if (index != null)
              TextButton(
                  onPressed: () {
                    setState(() => studies.removeAt(index));
                    Navigator.pop(ctx, false);
                  },
                  child: Text(tr('Supprimer', 'Delete'))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer', 'Save'))),
          ],
        ),
      ),
    );
    if (saved == true) {
      final st = Study(s?.id ?? 's${DateTime.now().microsecondsSinceEpoch}', label.text.trim(), {
        for (final k in keys) k: SourcedValue(parseNumber(ctrl[k]!.text), provenance: prov[k]!, source: src[k]!.text),
        for (final part in modText.text.split(';'))
          if (part.contains('=') && part.split('=')[0].trim().isNotEmpty && !keys.contains(part.split('=')[0].trim()))
            part.split('=')[0].trim(): SourcedValue(parseNumber(part.split('=')[1]), source: tr('saisie (caractéristique de l\'étude)', 'entered (study characteristic)')),
      },
          subgroup: sub.text.trim(), compatibility: compat, excluded: excluded, exclusionReason: reason.text);
      setState(() => index == null ? studies.add(st) : studies[index] = st);
    }
    _persist();
  }

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final expert = context.watch<AppState>().expertMode;
    final keys = _keys;
    final measures = continuous
        ? [(EffectMeasure.md, tr('Différence de moyennes', 'Mean difference')), (EffectMeasure.smd, tr('DMS (g de Hedges)', "SMD (Hedges' g)"))]
        : [(EffectMeasure.rr, tr('Risque relatif', 'Risk ratio')), (EffectMeasure.or, 'Odds ratio'), (EffectMeasure.rd, tr('Différence de risques', 'Risk difference'))];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Atelier de métaanalyse', 'Meta-analysis workshop'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'bin', label: Text(tr('Issue binaire', 'Binary outcome'))),
          ButtonSegment(value: 'cont', label: Text(tr('Issue continue', 'Continuous outcome'))),
          ButtonSegment(value: 'diag', label: Text(tr('Test diagnostique', 'Diagnostic test'))),
        ],
        selected: {_kind},
        onSelectionChanged: studies.isEmpty
            ? (s) => setState(() {
                  continuous = s.first == 'cont';
                  diagnostic = s.first == 'diag';
                  measure = continuous ? EffectMeasure.md : EffectMeasure.rr;
                })
            : null,
      ),
      const SizedBox(height: 10),
      Text(tr('Tableau d\'extraction (${studies.length} étude(s))', 'Extraction table (${studies.length} study(ies))'), style: Theme.of(context).textTheme.titleSmall),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          headingRowHeight: 32,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 40,
          columns: [
            DataColumn(label: Text(tr('Étude', 'Study'))),
            for (final k in keys) DataColumn(label: Text(_keyLabels[k] ?? k)),
            DataColumn(label: Text(tr('Sous-groupe', 'Subgroup'))),
            const DataColumn(label: Text('Compat.')),
          ],
          rows: [
            for (var i = 0; i < studies.length; i++)
              DataRow(
                onSelectChanged: (_) => _edit(i),
                color: studies[i].excluded ? WidgetStatePropertyAll(Colors.grey.withValues(alpha: 0.2)) : null,
                cells: [
                  DataCell(Text(studies[i].label)),
                  for (final k in keys)
                    DataCell(Text(
                        '${studies[i].v(k) == null ? "—" : _num(studies[i].v(k)!)}${studies[i].values[k]?.provenance == Provenance.assumed ? " (H)" : studies[i].values[k]?.provenance == Provenance.recalculated ? " (R)" : ""}')),
                  DataCell(Text(studies[i].subgroup)),
                  DataCell(Icon(
                    studies[i].compatibility.all.contains(Compat.no)
                        ? Icons.cancel_outlined
                        : studies[i].compatibility.all.contains(Compat.unclear)
                            ? Icons.help_outline
                            : Icons.check_circle_outline,
                    size: 18,
                  )),
                ],
              ),
          ],
        ),
      ),
      Text(tr('(H) = hypothèse, (R) = recalculée. Touchez une ligne pour modifier sa source, son statut et sa compatibilité.', '(H) = assumption, (R) = recalculated. Tap a row to edit its source, status and compatibility.'),
          style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(tr('Ajouter une étude', 'Add a study'))),
        TextButton.icon(onPressed: _importCsv, icon: const Icon(Icons.upload_file), label: Text(tr('Importer un CSV d\'extraction', 'Import an extraction CSV'))),
      ]),
      const Divider(),
      if (diagnostic) ...[
        Text(tr('Modèle bivarié de Reitsma (REML) : sensibilité et spécificité combinées, courbe SROC, régions de confiance et de prédiction.', 'Reitsma bivariate model (REML): pooled sensitivity and specificity, SROC curve, confidence and prediction regions.')),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.calculate),
          label: Text(tr('Lancer la métaanalyse diagnostique', 'Run the diagnostic meta-analysis')),
          onPressed: () {
            _persist();
            run(context, () => diagnosticMetaAnalysis(studies), widget.onResult, options: const {'model': 'reitsma'});
          },
        ),
      ] else ...[
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<EffectMeasure>(tr('Mesure d\'effet', 'Effect measure'), measure, measures, (v) => setState(() => measure = v ?? measure)),
        Pick<TauMethod>(tr('Modèle', 'Model'), method, [
          (TauMethod.reml, tr('Effets aléatoires (REML)', 'Random effects (REML)')),
          (TauMethod.dl, tr('Effets aléatoires (DerSimonian-Laird)', 'Random effects (DerSimonian-Laird)')),
          (TauMethod.fixed, tr('Effet fixe', 'Fixed effect')),
        ], (v) => setState(() => method = v ?? method)),
      ]),
      if (method != TauMethod.fixed)
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('IC de Hartung-Knapp (recommandé si peu d\'études)', 'Hartung-Knapp CI (recommended with few studies)')),
            value: knha,
            onChanged: (v) => setState(() => knha = v)),
      if (expert && method == TauMethod.fixed && (measure == EffectMeasure.or || measure == EffectMeasure.rr))
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Mantel-Haenszel (sans correction de continuité)', 'Mantel-Haenszel (without continuity correction)')), value: mh, onChanged: (v) => setState(() => mh = v)),
      FilledButton.icon(
        icon: const Icon(Icons.calculate),
        label: Text(tr('Lancer la métaanalyse', 'Run the meta-analysis')),
        onPressed: () {
          _persist();
          final o = MetaOptions(measure: measure, method: method, knha: knha, mantelHaenszelFixed: mh);
          run(context, () => metaAnalysis(studies, o), widget.onResult, options: o.toJson());
        },
      ),
      const SizedBox(height: 6),
      Text(tr('Les effets combinés, poids, hétérogénéité, forest plot, retrait d\'une étude à la fois et sous-groupes figurent dans le résultat. Les synthèses diagnostiques se font en mode « Test diagnostique ».', 'Pooled effects, weights, heterogeneity, forest plot, leave-one-out and subgroups appear in the result. Diagnostic syntheses are in the "Diagnostic test" mode.'), style: Theme.of(context).textTheme.bodySmall),
      const Divider(height: 28),
      Text(tr('Méta-régression (exploration de l\'hétérogénéité)', 'Meta-regression (exploring heterogeneity)'), style: Theme.of(context).textTheme.titleSmall),
      Text(tr('Choisir des modérateurs prévus dans le protocole, en petit nombre (repère : 10 études par modérateur). Le modèle et la mesure d\'effet sont ceux choisis ci-dessus.', 'Choose moderators planned in the protocol, few in number (benchmark: 10 studies per moderator). The model and effect measure are those chosen above.')),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in moderatorKeys)
          FilterChip(label: Text(k), selected: mods.contains(k), onSelected: (v) => setState(() => v ? mods.add(k) : mods.remove(k))),
        if (studies.any((st) => st.subgroup.isNotEmpty))
          FilterChip(label: Text(tr('sous-groupe (qualitatif)', 'subgroup (categorical)')), selected: modSubgroup, onSelected: (v) => setState(() => modSubgroup = v)),
      ]),
      if (moderatorKeys.isEmpty && !studies.any((st) => st.subgroup.isNotEmpty))
        Text(tr('Aucune caractéristique d\'étude saisie : les ajouter dans la fiche de chaque étude (« latitude=44 ; annee=1948 »).', 'No study characteristic entered: add them in each study\'s sheet ("latitude=44; year=1948").'),
            style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.show_chart),
        label: Text(tr('Lancer la méta-régression', 'Run the meta-regression')),
        onPressed: () {
          _persist();
          final o = MetaOptions(measure: measure, method: method, knha: knha);
          final m = [for (final k in mods) Moderator(k), if (modSubgroup) const Moderator('sous-groupe', categorical: true)];
          run(context, () => metaRegression(studies, o, m), widget.onResult, options: {...o.toJson(), 'moderators': [for (final x in m) x.toJson()]});
        },
      ),
      ],
    ]);
  }
}
