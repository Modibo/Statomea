import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Étape 9 : audit contradictoire du texte de résultats et des analyses.
class AuditStep extends StatefulWidget {
  final Project p;
  const AuditStep(this.p, {super.key});
  @override
  State<AuditStep> createState() => _AuditStepState();
}

class _AuditStepState extends State<AuditStep> {
  late final c = TextEditingController(text: widget.p.resultsText);
  AuditReport? report;

  void _run() {
    widget.p.resultsText = c.text;
    context.read<AppState>().save(widget.p);
    setState(() => report = runAudit(
        question: widget.p.question, results: [for (final e in widget.p.journal) analysisResultFromJson(e.result)], text: c.text));
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    return PageBody(children: [
      Heading(tr('9. Audit contradictoire', '9. Adversarial audit')),
      Text(tr('Collez ou rédigez le texte de résultats. L\'audit le confronte au plan déclaré et aux analyses réellement journalisées. Les contrôles structurés sont fiables ; les contrôles « lexicaux » repèrent des formulations et peuvent se tromper.', 'Paste or write the results text. The audit confronts it with the declared design and with the analyses actually logged. Structured checks are reliable; "lexical" checks detect wording and can be wrong.')),
      const SizedBox(height: 10),
      TextField(
        controller: c,
        minLines: 6,
        maxLines: 16,
        decoration: InputDecoration(labelText: tr('Texte de résultats proposé', 'Proposed results text'), alignLabelWithHint: true),
      ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: _run, icon: const Icon(Icons.gavel), label: Text(tr('Lancer l\'audit', 'Run the audit')))),
      if (r != null) ...[
        const SizedBox(height: 12),
        Text(tr('${r.alerts.length} alerte(s) — ${r.findings.where((f) => f.status == AuditStatus.insufficient).length} contrôle(s) en information insuffisante', '${r.alerts.length} alert(s) — ${r.findings.where((f) => f.status == AuditStatus.insufficient).length} check(s) with insufficient information'),
            style: Theme.of(context).textTheme.titleMedium),
        for (final fam in AuditFamily.values) _FamilyCard(fam, r.of(fam)),
      ],
    ]);
  }
}

class _FamilyCard extends StatelessWidget {
  final AuditFamily fam;
  final List<AuditFinding> items;
  const _FamilyCard(this.fam, this.items);
  @override
  Widget build(BuildContext context) {
    final alerts = items.where((f) => f.status == AuditStatus.alert).toList();
    final insufficient = items.any((f) => f.status == AuditStatus.insufficient);
    final (icon, color, label) = alerts.isNotEmpty
        ? (Icons.report_outlined, severityColor(context, alerts.map((a) => a.severity).reduce((a, b) => a.index > b.index ? a : b)), tr('${alerts.length} alerte(s)', '${alerts.length} alert(s)'))
        : insufficient
            ? (Icons.help_outline, Colors.blueGrey, tr('information insuffisante', 'insufficient information'))
            : (Icons.check_circle_outline, Colors.green.shade700, 'conforme');
    return Card(
      child: ExpansionTile(
        initiallyExpanded: alerts.isNotEmpty,
        leading: Icon(icon, color: color),
        title: Text(auditFamilyLabel(fam)),
        subtitle: Text(label),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in items)
            f.status == AuditStatus.alert
                ? Banner2(f.severity, tr('${f.message}${f.lexical ? " (repérage lexical)" : ""}', '${f.message}${f.lexical ? " (lexical detection)" : ""}'), trigger: f.trigger, suggestion: f.correction)
                : Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${f.status == AuditStatus.ok ? "✓" : "?"} ${f.message}')),
        ],
      ),
    );
  }
}
