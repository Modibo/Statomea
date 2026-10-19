import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import '../widgets/common.dart';

/// Chronogramme (diagramme de Gantt) et budget prévisionnel : durées proposées depuis le protocole, modifiables ;
/// coûts unitaires et devise saisis par le chercheur ; repris dans le protocole prérédigé (rubrique 13).
class PlanningScreen extends StatefulWidget {
  final Project project;
  const PlanningScreen(this.project, {super.key});
  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  Project get p => widget.project;

  void _set(String key, String value) {
    setState(() {
      if (value.trim().isEmpty) {
        p.planning.remove(key);
      } else {
        p.planning[key] = value.trim();
      }
    });
    context.read<AppState>().saveSoon(p);
  }

  @override
  Widget build(BuildContext context) {
    final pl = studyPlanning(p);
    final theme = Theme.of(context);
    final months = pl.totalMonths;
    Widget numField(String key, String label, {String? hint, double width = 120}) => SizedBox(
          width: width,
          child: TextFormField(
            key: ValueKey('plan-$key'),
            initialValue: p.planning[key] ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
            onChanged: (v) => _set(key, v),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Budget et chronogramme', 'Budget and timeline'))),
      body: PageBody(maxWidth: 1000, children: [
        Heading(p.title),
        Text(tr('Durées et quantités proposées à partir du protocole (effectif, rythme de recrutement, suivi, examens de la fiche de recueil) ; modifiez-les et saisissez les coûts unitaires. Le tout est repris dans le protocole prérédigé.',
                'Durations and quantities proposed from the protocol (sample size, recruitment rate, follow-up, tests in the case report form); edit them and enter unit costs. Everything is included in the pre-drafted protocol.'),
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        SectionLabel(tr('Chronogramme ($months mois)', 'Timeline ($months months)'), icon: Icons.view_timeline_outlined),
        const SizedBox(height: 6),
        _Gantt(pl.phases, months),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          numField('m_prep', tr('Préparation (mois)', 'Preparation (months)'), width: 150),
          numField('m_recruit', tr('Inclusions (mois)', 'Enrolment (months)'), width: 150),
          numField('m_follow', tr('Suivi (mois)', 'Follow-up (months)'), width: 130),
          numField('m_analysis', tr('Analyse (mois)', 'Analysis (months)'), width: 130),
          numField('m_writing', tr('Rédaction (mois)', 'Writing (months)'), width: 140),
        ]),
        for (final a in pl.assumptions) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $a', style: theme.textTheme.bodySmall)),
        const SizedBox(height: 16),
        SectionLabel(tr('Budget prévisionnel', 'Provisional budget'), icon: Icons.account_balance_wallet_outlined),
        const SizedBox(height: 6),
        Wrap(spacing: 12, children: [
          SizedBox(
            width: 120,
            child: TextFormField(
              key: const ValueKey('plan-currency'),
              initialValue: p.planning['currency'] ?? 'FCFA',
              decoration: InputDecoration(labelText: tr('Devise', 'Currency'), isDense: true),
              onChanged: (v) => _set('currency', v),
            ),
          ),
          numField('q_n', tr('Nombre de sujets', 'Number of subjects'), hint: p.inferred['plannedSampleSize'], width: 160),
        ]),
        const SizedBox(height: 8),
        for (final l in pl.lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
                SizedBox(width: 280, child: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    key: ValueKey('plan-q_${l.key}'),
                    initialValue: p.planning['q_${l.key}'] ?? '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '${tr('Quantité', 'Quantity')} (${l.unitLabel})', hintText: formatMoney(l.quantity), isDense: true),
                    onChanged: (v) => _set('q_${l.key}', v),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    key: ValueKey('plan-u_${l.key}'),
                    initialValue: p.planning['u_${l.key}'] ?? '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Coût unitaire (${pl.currency})', 'Unit cost (${pl.currency})'), isDense: true),
                    onChanged: (v) => _set('u_${l.key}', v),
                  ),
                ),
                Text(l.total == null ? tr('—', '—') : '${formatMoney(l.total!)} ${pl.currency}', style: theme.textTheme.titleSmall),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Sous-total : ${formatMoney(pl.subtotal)} ${pl.currency}', 'Subtotal: ${formatMoney(pl.subtotal)} ${pl.currency}')),
              Text(tr('Imprévus (10 %) : ${formatMoney(pl.contingency)} ${pl.currency}', 'Contingency (10%): ${formatMoney(pl.contingency)} ${pl.currency}')),
              Text(tr('Total : ${formatMoney(pl.total)} ${pl.currency}', 'Total: ${formatMoney(pl.total)} ${pl.currency}'), style: theme.textTheme.titleMedium),
              if (!pl.complete)
                Text(tr('Lignes sans coût unitaire non comptées.', 'Lines without a unit cost are not counted.'), style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Diagramme de Gantt : une ligne par phase, une colonne par mois.
class _Gantt extends StatelessWidget {
  final List<PlanningPhase> phases;
  final int months;
  const _Gantt(this.phases, this.months);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final labelW = c.maxWidth < 600 ? 120.0 : 260.0;
      final cell = ((c.maxWidth - labelW) / months).clamp(6.0, 40.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: labelW),
            for (var m = 1; m <= months; m++)
              SizedBox(width: cell, child: Text(cell >= 16 || m % 3 == 1 ? '$m' : '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
          ]),
          for (final ph in phases)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: labelW, child: Text(ph.label, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                for (var m = 1; m <= months; m++)
                  Container(
                    width: cell,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    color: m >= ph.start && m <= ph.end ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
              ]),
            ),
        ]),
      );
    });
  }
}
