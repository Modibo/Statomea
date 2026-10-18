import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/document_text.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'project_screen.dart';
import 'roadmap_screen.dart';

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
      ('survie', tr('Survie avancée', 'Advanced survival'),
          tr('Rechute avec décès concurrent (incidence cumulée, test de Gray, Fine-Gray) et biais du temps immortel (greffe de Stanford).',
              'Relapse with competing death (cumulative incidence, Gray test, Fine-Gray) and immortal time bias (Stanford transplant).'),
          Icons.timeline),
      ('methodes', tr('Laboratoire : plasma ou sérum ?', 'Laboratory: plasma or serum?'),
          tr('Créatinine sur 108 patients : corrélation (piège), Bland-Altman, Passing-Bablok et Deming, biais aux niveaux de décision.',
              'Creatinine in 108 patients: correlation (pitfall), Bland-Altman, Passing-Bablok and Deming, bias at decision levels.'),
          Icons.science_outlined),
      ('sante', tr('Santé publique : une politique a-t-elle marché ?', 'Public health: did a policy work?'),
          tr('Série interrompue de 48 mois : piège de la comparaison avant/après, régression segmentée, quasi-Poisson, valeur E.',
              '48-month interrupted series: the before/after pitfall, segmented regression, quasi-Poisson, E-value.'),
          Icons.show_chart),
    ];
    // En-tête : titre et description ; actions « Nouveau projet » (principale) et « Importer » côte à côte, à droite
    // du titre sur grand écran, en dessous et à parts égales sur téléphone.
    ButtonStyle big(BuildContext c) => const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(64, 48)));
    Widget fit(String s) => FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 1));
    final newBtn = FilledButton.icon(style: big(context), onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), label: fit(t.newProject));
    // Libellé court sur téléphone (« Importer »), complet sur grand écran ; l'info-bulle garde le libellé complet.
    Widget importBtn({bool short = false}) => Tooltip(
          message: tr('Importer un projet', 'Import a project'),
          child: OutlinedButton.icon(
              style: big(context), onPressed: () => _pickAndImport(context), icon: const Icon(Icons.file_open_outlined),
              label: fit(short ? tr('Importer', 'Import') : tr('Importer un projet', 'Import a project'))),
        );
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Heading(t.navProjects),
      const SizedBox(height: 4),
      Text(tr('De la question de recherche à une analyse justifiée, vérifiable et correctement interprétée — en 10 étapes.', 'From the research question to a justified, verifiable and correctly interpreted analysis — in 10 steps.'),
          style: Theme.of(context).textTheme.bodyMedium),
    ]);
    return PageBody(children: [
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 640) {
          return Row(children: [Expanded(child: title), const SizedBox(width: 16), newBtn, const SizedBox(width: 10), importBtn()]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          title,
          const SizedBox(height: 14),
          Row(children: [Expanded(child: newBtn), const SizedBox(width: 10), Expanded(child: importBtn(short: true))]),
        ]);
      }),
      const SizedBox(height: 12),
      const _StepsGuide(),
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
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'docx', 'pdf']);
  if (files.isEmpty || !context.mounted) return;
  final bytes = await files.single.xFile.readAsBytes();
  if (!context.mounted) return;
  final name = files.single.xFile.name;
  if (!name.toLowerCase().endsWith('.json')) {
    await importProtocolDocument(context, bytes, name);
    return;
  }
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

/// Guide de démarrage : nouveau projet ou projet importé, puis les 10 étapes en une phrase chacune. Ouvert tant
/// qu'aucun projet n'existe.
class _StepsGuide extends StatelessWidget {
  const _StepsGuide();
  @override
  Widget build(BuildContext context) {
    final empty = context.watch<AppState>().projects.every((p) => p.demoNotice.isNotEmpty);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: empty,
        leading: Icon(Icons.route_outlined, color: theme.colorScheme.primary),
        title: Text(tr('Comment faire : les 10 étapes d\'un projet', 'How it works: the 10 steps of a project'), style: theme.textTheme.titleMedium),
        subtitle: Text(tr('Nouveau projet ou projet importé', 'New or imported project'), style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, text) in [(Icons.add_circle_outline, guideNewProject), (Icons.file_open_outlined, guideImportedProject)])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              ]),
            ),
          const Divider(),
          for (final s in PStep.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 13, backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text('${PStep.values.indexOf(s) + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onPrimaryContainer))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${stepLabel(s)} — ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: stepHint(s)),
                  ]), style: theme.textTheme.bodyMedium),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}



/// Protocole Word ou PDF : texte extrait, sections et caractéristiques déduites, aperçu, puis création du projet et
/// ouverture de sa feuille de route (10 étapes, imprimable).
Future<Project?> importProtocolDocument(BuildContext context, Uint8List bytes, String name) async {
  final ProtocolDraft d;
  try {
    d = protocolFromText(documentText(bytes, name));
  } on StatInputError catch (e) {
    showError(context, e.message);
    return null;
  }
  final q = d.toQuestion();
  final title = TextEditingController(text: d.title);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Projet depuis « $name »', 'Project from "$name"')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: title, decoration: InputDecoration(labelText: tr('Titre du projet', 'Project title'))),
            const SizedBox(height: 10),
            Text(tr('Question retenue', 'Question retained'), style: Theme.of(ctx).textTheme.titleSmall),
            Text(d.question),
            const SizedBox(height: 8),
            Text(tr('Ce que Statoméa a compris (à vérifier)', 'What Statoméa understood (to check)'), style: Theme.of(ctx).textTheme.titleSmall),
            for (final (l, v) in [
              (tr('Plan', 'Design'), designLabel(q.design)),
              (tr('Objectif', 'Aim'), objectiveLabel(q.objective)),
              (tr('Issue', 'Outcome'), '${q.outcome.isEmpty ? '—' : q.outcome} (${outcomeTypeLabel(q.outcomeType)})'),
              ('Population', q.population.isEmpty ? '—' : q.population),
              (tr('Exposition / comparateur', 'Exposure / comparator'), '${q.exposure.isEmpty ? '—' : q.exposure} / ${q.comparator.isEmpty ? '—' : q.comparator}'),
              if (d.sampleSize != null) (tr('Effectif prévu', 'Planned sample size'), '${d.sampleSize}'),
            ])
              Text('• $l : $v'),
            const SizedBox(height: 6),
            Text(tr('Sections reconnues : ${d.sections.isEmpty ? 'aucune (question seule)' : d.sections.keys.map(_sectionLabel).join(', ')}.', 'Recognised sections: ${d.sections.isEmpty ? 'none (question only)' : d.sections.keys.map(_sectionLabel).join(', ')}.'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Créer le projet', 'Create the project'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  final state = context.read<AppState>();
  final p = state.createProject(title.text.trim().isEmpty ? d.title : title.text.trim());
  p.question = q;
  final analysis = d.sections['analysis'];
  p.analysisPlan = analysis == null
      ? draftAnalysisPlan(q)
      : '${tr('Plan d\'analyse du protocole', 'Protocol analysis plan')} : $analysis\n\n${tr('Proposition de Statoméa', 'Statoméa proposal')} :\n${draftAnalysisPlan(q)}';
  final (_, filled) = applyInference(ResearchQuestion(text: d.question, population: d.sections['population'] ?? '', exposure: d.sections['intervention'] ?? '', comparator: d.sections['comparator'] ?? '', outcome: d.sections['outcome'] ?? ''), d.inference);
  markInferred(p, filled);
  if (d.sampleSize != null) p.inferred['plannedSampleSize'] = '${d.sampleSize}';
  p.inferred['analysisPlan'] = p.analysisPlan;
  await state.save(p);
  if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => RoadmapScreen(p)));
  return p;
}

String _sectionLabel(String k) => switch (k) {
      'objective' => tr('objectif', 'objective'),
      'population' => 'population',
      'intervention' => 'intervention',
      'comparator' => tr('comparateur', 'comparator'),
      'outcome' => tr('critère de jugement', 'outcome'),
      'design' => tr('schéma', 'design'),
      'analysis' => tr('analyse statistique', 'statistical analysis'),
      'sampleSize' => tr('effectif', 'sample size'),
      _ => k,
    };
