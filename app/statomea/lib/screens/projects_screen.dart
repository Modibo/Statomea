import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart';

import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'project_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final c = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).newProject),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Titre du projet', 'Project title'), hintText: tr('p. ex. Tabac et HTA chez l\'adulte', 'e.g. Smoking and hypertension in adults')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Créer', 'Create'))),
        ],
      ),
    );
    if (title == null || !context.mounted) return;
    final p = context.read<AppState>().createProject(title);
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: p)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final user = state.projects.where((p) => p.demoNotice.isEmpty).toList();
    final demos = [
      ('aghbs', tr('Prévalence de l\'AgHBs et événements rares', 'HBsAg prevalence and rare events'), tr('Proportions exactes, règle de trois, rapport de prévalences, séparation et Firth.', 'Exact proportions, rule of three, prevalence ratio, separation and Firth.'), Icons.bloodtype_outlined),
      ('meta', tr('Métaanalyse avec forest plot', 'Meta-analysis with forest plot'), tr('13 essais publiés du BCG : RR, REML, I², intervalle de prédiction, sensibilité, sous-groupes.', '13 published BCG trials: RR, REML, I², prediction interval, sensitivity, subgroups.'), Icons.stacked_bar_chart),
      ('prediction', tr('Modèle de risque cardiométabolique', 'Cardiometabolic risk model'), tr('Développement, validation interne par bootstrap, calibration, courbe de décision.', 'Development, internal validation by bootstrap, calibration, decision curve.'), Icons.monitor_heart_outlined),
      ('tb', tr('Tuberculose résistante : que vaut le génotypage ?', 'Resistant tuberculosis: what is genotyping worth?'),
          tr('Mutations rpoB et antibiogramme (Se, Sp, kappa), lignées, limite de détection, identification par alignement.', 'rpoB mutations and susceptibility testing (Se, Sp, kappa), lineages, limit of detection, identification by alignment.'),
          Icons.coronavirus_outlined),
      ('gwas', tr('Étude d\'association pangénomique', 'Genome-wide association study'),
          tr('Contrôle de qualité, apparentement, ACP, inflation λ, Manhattan et QQ plots, seuil 5 × 10⁻⁸.', 'Quality control, relatedness, PCA, inflation λ, Manhattan and QQ plots, 5 × 10⁻⁸ threshold.'),
          Icons.biotech),
      ('polygenic', tr('Polygénie ou confusion ?', 'Polygenicity or confounding?'),
          tr('Inflation λ, régression LD score avant et après ajustement sur l\'ascendance, corrélation génétique diabète–coronaropathie.',
              'Inflation λ, LD score regression before and after adjustment for ancestry, diabetes–coronary disease genetic correlation.'),
          Icons.stacked_line_chart),
      ('mr', tr('Causalité : LDL, HDL et cœur', 'Causality: LDL, HDL and the heart'),
          tr('Randomisation mendélienne sur 28 variants publiés : IVW, MR-Egger, médiane et mode, leave-one-out, multivariée.',
              'Mendelian randomization on 28 published variants: IVW, MR-Egger, median and mode, leave-one-out, multivariable.'),
          Icons.call_split),
    ];
    return PageBody(children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Heading(t.navProjects),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add), label: Text(t.newProject)),
        OutlinedButton.icon(
            onPressed: () => _pickAndImport(context),
            icon: const Icon(Icons.file_open_outlined),
            label: Text(tr('Importer un projet', 'Import a project'))),
      ]),
      const SizedBox(height: 4),
      Text(tr('De la question de recherche à une analyse justifiée, vérifiable et correctement interprétée — en 10 étapes.', 'From the research question to a justified, verifiable and correctly interpreted analysis — in 10 steps.'),
          style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 12),
      if (user.isEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('Aucun projet. Créez-en un, ou ouvrez une démonstration ci-dessous pour voir le parcours complet.', 'No project. Create one, or open a demonstration below to see the full pathway.'),
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ResponsiveGrid(minItemWidth: 420, equalHeights: false, spacing: 8, children: [for (final p in user) _ProjectTile(p)]),
      const SizedBox(height: 20),
      Heading(t.demos, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      ResponsiveGrid(minItemWidth: 300, children: [
        for (final (id, title, sub, icon) in demos)
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(SnackBar(content: Text(tr('Calcul de la démonstration…', 'Computing the demonstration…')), duration: Duration(seconds: 1)));
                final p = await context.read<AppState>().openDemo(id);
                if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: p)));
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 26, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(sub, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      ResponsiveGrid(minItemWidth: 420, equalHeights: false, spacing: 8, children: [
        for (final p in state.projects.where((p) => p.demoNotice.isNotEmpty)) _ProjectTile(p),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Icon(Icons.cloud_off, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(t.offlineNote, style: Theme.of(context).textTheme.bodySmall)),
      ]),
      const SizedBox(height: 6),
      Text(tr('Utilisez de préférence des données anonymisées : pas de nom, de date de naissance complète ni d\'identifiant direct.', 'Preferably use anonymized data: no name, full date of birth or direct identifier.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      const DisclaimerFooter(),
    ]);
  }
}

Future<void> _pickAndImport(BuildContext context) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (files.isEmpty || !context.mounted) return;
  final bytes = await files.single.xFile.readAsBytes();
  if (!context.mounted) return;
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    showError(context, tr('Fichier illisible : un projet exporté est en UTF-8.', 'Unreadable file: an exported project is in UTF-8.'));
    return;
  }
  await importProjectText(context, text);
}

/// Aperçu d'un projet exporté, constats d'intégrité, puis import sur confirmation.
Future<Project?> importProjectText(BuildContext context, String text) async {
  final state = context.read<AppState>();
  final ProjectImport imp;
  try {
    imp = state.prepareImport(text);
  } on StatInputError catch (e) {
    showError(context, e.message);
    return null;
  }
  final p = imp.project;
  final d = p.dataset;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Importer « ${p.title} »', 'Import "${p.title}"')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text([
              d == null
                  ? tr('Pas de jeu de données individuelles', 'No individual dataset')
                  : tr('Données : ${d.rowCount} lignes × ${d.names.length} variables, ${d.corrections.length} correction(s)',
                      'Data: ${d.rowCount} rows × ${d.names.length} variables, ${d.corrections.length} correction(s)'),
              if (p.studies.isNotEmpty) tr('${p.studies.length} étude(s) extraite(s)', '${p.studies.length} extracted study(ies)'),
              tr('${p.journal.length} analyse(s) dans le journal', '${p.journal.length} analysis(es) in the log'),
              tr('${p.completed.length}/10 étapes', '${p.completed.length}/10 steps'),
            ].join(' · ')),
            const SizedBox(height: 8),
            if (imp.notes.isEmpty)
              Text(tr('Fichier intact (empreinte vérifiée), exporté par ce moteur.', 'File intact (fingerprint verified), exported by this engine.')),
            for (final a in imp.notes) Banner2(a.severity, a.message, suggestion: a.suggestion),
            const SizedBox(height: 8),
            Text(tr('Les résultats sont relus tels qu\'ils ont été enregistrés ; rien n\'est recalculé à l\'import.',
                    'Results are read as they were recorded; nothing is recomputed on import.'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx).cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Importer', 'Import'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  await state.addImported(p);
  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: p)));
  return p;
}

class _ProjectTile extends StatelessWidget {
  final Project p;
  const _ProjectTile(this.p);
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final done = p.completed.length;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$done')),
        title: Text(p.title),
        subtitle: Text(tr('${p.demoNotice.isNotEmpty ? "Démonstration — " : ""}$done/10 étapes · ${p.journal.length} analyse(s) · ${designLabel(p.question.design)}', '${p.demoNotice.isNotEmpty ? "Demonstration — " : ""}$done/10 steps · ${p.journal.length} analysis(es) · ${designLabel(p.question.design)}')),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(project: p))),
        trailing: IconButton(
          tooltip: t.deleteProject,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => confirmDelete(context, p),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, Project p) async {
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.deleteProject),
      content: Text(t.deleteConfirm(p.title)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete)),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await context.read<AppState>().delete(p);
    if (context.mounted) showError(context, tr('Projet supprimé de cet appareil.', 'Project deleted from this device.'));
    return true;
  }
  return false;
}
