import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../services/pdf_export.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Diagramme de flux des participants : saisie des effectifs et motifs, dessin immédiat (CONSORT pour un essai,
/// STROBE sinon), contrôles arithmétiques, impression ; repris dans l'article prérédigé (Figure 1).
class FlowScreen extends StatefulWidget {
  final Project project;
  const FlowScreen(this.project, {super.key});
  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen> {
  Project get p => widget.project;

  void _set(String key, String value) {
    setState(() {
      if (value.trim().isEmpty) {
        p.flow.remove(key);
      } else {
        p.flow[key] = value.trim();
      }
    });
    context.read<AppState>().saveSoon(p);
  }

  Widget _field(String key, String label, {bool multiline = false, double width = 180, String? hint}) => SizedBox(
        width: multiline ? 360 : width,
        child: TextFormField(
          key: ValueKey('flow-$key'),
          initialValue: p.flow[key] ?? '',
          keyboardType: multiline ? TextInputType.multiline : TextInputType.number,
          minLines: multiline ? 2 : 1,
          maxLines: multiline ? 5 : 1,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: (v) => _set(key, v),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = flowDiagram(p);
    final rct = p.question.design == StudyDesign.rct;
    final theme = Theme.of(context);
    final arms = flowArms(p);
    final reasonsHint = tr('une ligne par motif, p. ex. « refus : 12 »', 'one line per reason, e.g. "declined: 12"');
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Diagramme de flux', 'Flow diagram')),
        actions: [
          IconButton(
            tooltip: tr('Imprimer ou enregistrer en PDF', 'Print or save as PDF'),
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              final bytes = await buildFlowPdf(p);
              await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'diagramme-flux-${p.id}.pdf');
            },
          ),
        ],
      ),
      body: PageBody(maxWidth: 1000, children: [
        Heading(p.title),
        Text(
            tr('Diagramme ${d.guideline} : saisissez les effectifs à chaque étape et les motifs d\'exclusion. ${d.proposed ? 'Les valeurs affichées sont proposées à partir du fichier de données. ' : ''}Il est repris dans l\'article prérédigé (Figure 1).',
                '${d.guideline} diagram: enter the numbers at each stage and the reasons for exclusion. ${d.proposed ? 'The values shown are proposed from the data file. ' : ''}It is included in the pre-drafted article (Figure 1).'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
          _field('assessed', tr('Évalués pour l\'éligibilité', 'Assessed for eligibility')),
          _field('excluded_reasons', tr('Exclus et motifs', 'Excluded and reasons'), multiline: true, hint: reasonsHint),
          _field('included', rct ? tr('Randomisés', 'Randomised') : tr('Inclus', 'Included'), hint: p.dataset == null ? null : '${p.dataset!.rowCount}'),
        ]),
        const SizedBox(height: 10),
        if (rct)
          for (var a = 0; a < 2; a++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
                _field('arm${a + 1}_name', tr('Bras ${a + 1}', 'Arm ${a + 1}'), width: 160, hint: arms[a]),
                _field('arm${a + 1}_allocated', tr('Alloués', 'Allocated'), width: 120),
                _field('arm${a + 1}_lost_reasons', tr('Perdus de vue / arrêts et motifs', 'Lost / discontinued and reasons'), multiline: true, hint: reasonsHint),
                _field('arm${a + 1}_analysed', tr('Analysés', 'Analysed'), width: 120),
              ]),
            )
        else
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
            _field('lost_reasons', tr('Non analysés et motifs', 'Not analysed and reasons'), multiline: true, hint: reasonsHint),
            _field('analysed', tr('Analysés', 'Analysed')),
          ]),
        for (final w in d.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [Icon(Icons.warning_amber_outlined, color: Colors.amber.shade800, size: 18), const SizedBox(width: 6), Expanded(child: Text(w))]),
          ),
        const SizedBox(height: 16),
        _FlowDrawing(d),
      ]),
    );
  }
}

class _FlowDrawing extends StatelessWidget {
  final FlowDiagram d;
  const _FlowDrawing(this.d);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget box(FlowBox b, {bool side = false}) => Container(
          width: side ? 240 : 230,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: side ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.primaryContainer.withValues(alpha: 0.4),
            border: Border.all(color: side ? scheme.outline : scheme.primary),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(b.n == null ? 'n = —' : 'n = ${b.n}'),
            for (final r in b.details) Text('• $r', style: const TextStyle(fontSize: 12)),
          ]),
        );
    final rows = <Widget>[];
    for (var i = 0; i < d.stages.length; i++) {
      final st = d.stages[i];
      if (i > 0) rows.add(Icon(Icons.arrow_downward, color: scheme.primary));
      rows.add(Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        for (var k = 0; k < st.main.length; k++) ...[
          if (k > 0) const SizedBox(width: 24),
          box(st.main[k], side: st.main[k].side),
        ],
        for (final s in st.side.whereType<FlowBox>()) ...[
          Icon(Icons.arrow_forward, color: scheme.outline),
          box(s, side: true),
        ],
      ]));
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(children: rows));
  }
}
