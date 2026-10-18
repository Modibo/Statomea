import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import 'common.dart';

/// Rôles des variables du projet transmis aux calculateurs (préremplissage).
class VariableRolesScope extends InheritedWidget {
  final VariableRoles roles;
  final Dataset? dataset;
  const VariableRolesScope({super.key, required this.roles, required this.dataset, required super.child});

  static VariableRolesScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<VariableRolesScope>();

  /// Variable [v] si elle existe et que son type figure dans [types] (sinon null : la liste déroulante ne la propose pas).
  String? pick(String? v, Set<VarType>? types) {
    final ds = dataset;
    if (v == null || ds == null || !ds.names.contains(v)) return null;
    return types == null || types.contains(ds.dictionary[v]!.type) ? v : null;
  }

  /// Termes de régression pour l'exposition et les covariables (référence déclarée ou première modalité).
  List<TermSpec> terms({Set<String> exclude = const {}}) {
    final ds = dataset;
    if (ds == null) return const [];
    return [
      for (final n in [?roles.exposure, ...roles.covariates])
        if (ds.names.contains(n) && !exclude.contains(n) && ds.dictionary[n]!.type != VarType.identifier)
          () {
            final v = ds.dictionary[n]!;
            final cat = v.type != VarType.numeric;
            return TermSpec(n, categorical: cat, reference: cat ? (v.reference ?? ds.levels(n).first) : null);
          }()
    ];
  }

  @override
  bool updateShouldNotify(VariableRolesScope old) => old.roles != roles || old.dataset != dataset;
}

/// Carte de l'étape 5 : déclarer une fois l'issue, l'exposition, les covariables d'ajustement et, si besoin, le temps,
/// le statut et l'identifiant du sujet. Ces rôles préremplissent les calculateurs proposés.
class VariableRolesEditor extends StatelessWidget {
  final Project project;
  final ValueChanged<VariableRoles> onChanged;
  const VariableRolesEditor(this.project, {super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ds = project.dataset!;
    final r = project.roles.validFor(ds);
    final names = [for (final n in ds.names) if (ds.dictionary[n]!.type != VarType.identifier) n];
    List<(String, String)> opts(Iterable<String> ns) => [('', tr('— aucune —', '— none —')), for (final n in ns) (n, '$n (${varTypeLabel(ds.dictionary[n]!.type)})')];
    String? v(String? x) => (x == null || x.isEmpty) ? null : x;
    final statusVar = r.status ?? r.outcome;
    final statusLevels = statusVar != null && ds.dictionary[statusVar]!.type != VarType.numeric ? ds.levels(statusVar) : const <String>[];
    final eventLevels = statusLevels.isNotEmpty ? statusLevels : (r.outcome != null && ds.levels(r.outcome!).length == 2 ? ds.levels(r.outcome!) : const <String>[]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(tr('Rôles des variables', 'Variable roles'), icon: Icons.assignment_ind_outlined),
          Text(tr('Déclarés une fois, ils préremplissent les calculateurs (vous pourrez toujours les changer dans le calcul).', 'Declared once, they prefill the calculators (you can still change them in the calculation).'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            Pick<String>(tr('Issue (critère de jugement)', 'Outcome'), r.outcome ?? '', opts(names), (x) => onChanged(VariableRoles(
                  outcome: v(x), exposure: r.exposure, time: r.time, status: r.status, subject: r.subject, covariates: [for (final c in r.covariates) if (c != x) c])), width: 260),
            if (eventLevels.isNotEmpty)
              Pick<String>(tr('Modalité « événement »', 'Event level'), r.eventLevel ?? '', [('', '—'), for (final l in eventLevels) (l, l)], (x) => onChanged(r.copyWith(eventLevel: v(x), clearEvent: v(x) == null)), width: 200),
            Pick<String>(tr('Exposition (groupe, traitement)', 'Exposure (group, treatment)'), r.exposure ?? '', opts(names.where((n) => n != r.outcome)), (x) => onChanged(VariableRoles(
                  outcome: r.outcome, eventLevel: r.eventLevel, exposure: v(x), time: r.time, status: r.status, subject: r.subject, covariates: [for (final c in r.covariates) if (c != x) c])), width: 280),
            Pick<String>(tr('Durée de suivi (survie)', 'Follow-up time (survival)'), r.time ?? '', opts(names.where((n) => ds.dictionary[n]!.type == VarType.numeric)), (x) => onChanged(VariableRoles(
                  outcome: r.outcome, eventLevel: r.eventLevel, exposure: r.exposure, time: v(x), status: r.status, subject: r.subject, covariates: r.covariates)), width: 240),
            Pick<String>(tr('Statut (survie)', 'Status (survival)'), r.status ?? '', opts(names.where((n) => ds.dictionary[n]!.type != VarType.numeric)), (x) => onChanged(VariableRoles(
                  outcome: r.outcome, exposure: r.exposure, time: r.time, status: v(x), subject: r.subject, covariates: r.covariates)), width: 220),
            Pick<String>(tr('Identifiant du sujet (mesures répétées)', 'Subject identifier (repeated measures)'), r.subject ?? '', opts(ds.names), (x) => onChanged(VariableRoles(
                  outcome: r.outcome, eventLevel: r.eventLevel, exposure: r.exposure, time: r.time, status: r.status, subject: v(x), covariates: r.covariates)), width: 300),
          ]),
          const SizedBox(height: 8),
          Text(tr('Covariables d\'ajustement (choisies a priori)', 'Adjustment covariates (chosen a priori)'), style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in names)
              if (n != r.outcome && n != r.exposure && n != r.time && n != r.status)
                FilterChip(
                  label: Text(n),
                  selected: r.covariates.contains(n),
                  onSelected: (s) => onChanged(r.copyWith(covariates: s ? [...r.covariates, n] : [for (final c in r.covariates) if (c != n) c])),
                ),
          ]),
        ]),
      ),
    );
  }
}
