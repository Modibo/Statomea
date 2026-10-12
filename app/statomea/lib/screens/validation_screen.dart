import 'package:flutter/material.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import 'package:provider/provider.dart';

import '../app_version.dart';
import '../services/update/update_check.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Statut de validation de chaque méthode (registre du moteur).
class ValidationScreen extends StatelessWidget {
  const ValidationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final validated = methodRegistry.where((m) => m.status == MethodStatus.validated).toList();
    final dev = methodRegistry.where((m) => m.status != MethodStatus.validated).toList();
    return PageBody(children: [
      Heading(tr('Validation des méthodes', 'Validation of methods')),
      Text(tr('Moteur $engineName $engineVersion. Chaque méthode « validée » a été comparée à des valeurs de référence produites par R 4.x (et metafor, logistf, pROC, sandwich, car, pmsampsize, survival, mada, mice), avec des tolérances écrites, sur des jeux de tests versionnés (validation/r/ et packages/statomea_core/test/). Une méthode « en développement » ne produit aucun résultat présenté comme fiable.', 'Engine $engineName $engineVersion. Each "validated" method was compared with reference values produced by R 4.x (and metafor, logistf, pROC, sandwich, car, pmsampsize, survival, mada, mice), with written tolerances, on versioned test sets (validation/r/ and packages/statomea_core/test/). A method "in development" produces no result presented as reliable.')),
      const SizedBox(height: 12),
      Text(tr('Validées (${validated.length})', 'Validated (${validated.length})'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      ResponsiveGrid(minItemWidth: 440, spacing: 8, equalHeights: false, children: [for (final m in validated) _tile(context, m)]),
      const SizedBox(height: 12),
      Text(tr('En développement (${dev.length})', 'In development (${dev.length})'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      ResponsiveGrid(minItemWidth: 440, spacing: 8, equalHeights: false, children: [for (final m in dev) _tile(context, m)]),
      const SizedBox(height: 12),
      Banner2(Severity.info,
          tr('Validation logicielle ≠ validation clinique : un calcul exact peut être appliqué à une question mal posée. Le parcours en 10 étapes et l\'audit servent à le prévenir.', 'Software validation ≠ clinical validation: an exact calculation can be applied to a badly posed question. The 10-step pathway and the audit are there to prevent this.')),
      const SizedBox(height: 16),
      const UpdateSettings(),
      const SizedBox(height: 16),
      const DisclaimerFooter(),
    ]);
  }

  Widget _tile(BuildContext context, MethodInfo m) => Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          leading: Icon(m.status == MethodStatus.validated ? Icons.verified_outlined : Icons.construction,
              color: m.status == MethodStatus.validated ? Colors.green.shade700 : Theme.of(context).colorScheme.error),
          title: Text(m.name),
          subtitle: Text('${m.category} · ${m.reference}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Question : ${m.question}', 'Question: ${m.question}')),
            Text(tr('Données requises : ${m.requiredData}', 'Required data: ${m.requiredData}')),
            Text(tr('Conditions : ${m.conditions.join(" ; ")}', 'Conditions: ${m.conditions.join("; ")}')),
            Text(tr('Diagnostics : ${m.diagnostics.join(" ; ")}', 'Diagnostics: ${m.diagnostics.join("; ")}')),
            Text(tr('Résultat : ${m.output}', 'Output: ${m.output}')),
          ],
        ),
      );
}

/// Version installée et vérification des nouvelles versions (réglage, vérification à la demande).
class UpdateSettings extends StatefulWidget {
  const UpdateSettings({super.key});
  @override
  State<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends State<UpdateSettings> {
  bool busy = false;
  String? message;

  Future<void> checkNow() async {
    setState(() => busy = true);
    final u = await context.read<AppState>().checkForUpdate(manual: true);
    if (!mounted) return;
    setState(() {
      busy = false;
      message = u == null
          ? tr('Statoméa $appVersion est à jour (ou le site n\'est pas joignable).', 'Statoméa $appVersion is up to date (or the site cannot be reached).')
          : tr('Nouvelle version ${u.version} disponible.', 'New version ${u.version} available.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final u = state.updateAvailable;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Mises à jour', 'Updates'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(tr('Version installée : $appVersion (moteur $engineVersion).', 'Installed version: $appVersion (engine $engineVersion).')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.checkUpdates,
            onChanged: state.setCheckUpdates,
            title: Text(tr('Vérifier les nouvelles versions', 'Check for new versions')),
            subtitle: Text(tr('Lit seulement le numéro de version publié sur $statomeaSite ; aucune donnée n\'est envoyée.',
                'Only reads the version number published on $statomeaSite; no data is sent.')),
          ),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: busy ? null : checkNow,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
              label: Text(tr('Vérifier maintenant', 'Check now')),
            ),
            if (u != null)
              FilledButton.icon(
                onPressed: () => applyUpdate(u),
                icon: Icon(u.url == null ? Icons.refresh_rounded : Icons.download_rounded),
                label: Text(u.url == null ? tr('Recharger (${u.version})', 'Reload (${u.version})') : tr('Télécharger ${u.version}', 'Download ${u.version}')),
              ),
          ]),
          if (message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message!, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
}
