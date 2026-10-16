import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import 'calculators.dart';
import 'common.dart';
import 'genotype_import.dart';

/// Atelier génomique : association génétique, génomique des pathogènes, qPCR, expression différentielle
/// RNA-seq et alignement local hors ligne. Tous les calculs sont faits sur l'appareil.
class GenomicsWorkshop extends StatefulWidget {
  final Project? project;
  final OnResult onResult;
  final String? initialMethod;
  const GenomicsWorkshop({super.key, this.project, required this.onResult, this.initialMethod});
  @override
  State<GenomicsWorkshop> createState() => _GenomicsWorkshopState();
}

String genomicsToolFor(String? methodId) => switch (methodId) {
      'mutation_phenotype' || 'type_diversity' => 'pathogens',
      'qpcr_standard_curve' || 'qpcr_relative' || 'qpcr_lod' => 'qpcr',
      'differential_expression' => 'expression',
      'local_alignment' => 'alignment',
      'mendelian_randomization' || 'mendelian_randomization_mv' || 'mr_steiger' => 'mr',
      'genotype_qc' || 'genotype_pca' || 'genotype_kinship' || 'lmm_scan' || 'ldsc' || 'genetic_correlation' || 'polygenic_score' || 'glmm_scan' => 'genotypes',
      _ => 'association',
    };

class _GenomicsWorkshopState extends State<GenomicsWorkshop> {
  late String tool = genomicsToolFor(widget.initialMethod);

  @override
  Widget build(BuildContext context) {
    final ds = widget.project?.dataset;
    final tools = [
      ('association', tr('Association génétique', 'Genetic association'), Icons.account_tree_outlined),
      ('genotypes', tr('Génotypes VCF / PLINK', 'VCF / PLINK genotypes'), Icons.upload_file),
      ('pathogens', tr('Pathogènes', 'Pathogens'), Icons.coronavirus_outlined),
      ('qpcr', 'qPCR', Icons.show_chart),
      ('expression', tr('Expression (RNA-seq)', 'Expression (RNA-seq)'), Icons.scatter_plot_outlined),
      ('alignment', tr('Alignement (type BLAST)', 'Alignment (BLAST-like)'), Icons.segment),
      ('mr', tr('Randomisation mendélienne', 'Mendelian randomization'), Icons.call_split),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Atelier génomique', 'Genomics workshop'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(tr('Calculs locaux : aucune donnée ni séquence ne quitte l\'appareil.', 'Local computation: no data or sequence leaves the device.'),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label, icon) in tools)
          ChoiceChip(avatar: Icon(icon, size: 16), label: Text(label), selected: tool == id, onSelected: (_) => setState(() => tool = id)),
      ]),
      const Divider(height: 24),
      KeyedSubtree(
        key: ValueKey(tool),
        child: switch (tool) {
          'pathogens' => _PathogensTool(ds, widget.onResult, initial: widget.initialMethod),
          'qpcr' => _QpcrTool(widget.onResult, initial: widget.initialMethod),
          'expression' => _ExpressionTool(ds, widget.onResult),
          'alignment' => _AlignmentTool(widget.onResult),
          'genotypes' => GenotypeImportTool(widget.onResult),
          'mr' => MrTool(ds, widget.onResult),
          _ => _AssociationTool(ds, widget.onResult, initial: widget.initialMethod),
        },
      ),
    ]);
  }
}

// ------------------------------------------------------------------ outils communs

List<(String, String)> _cols(Dataset ds, {Set<VarType>? types}) =>
    [for (final n in ds.names) if (types == null || types.contains(ds.dictionary[n]!.type)) (n, '$n (${varTypeLabel(ds.dictionary[n]!.type)})')];

const _categorical = {VarType.binary, VarType.categorical, VarType.text, VarType.ordinal, VarType.identifier};

Widget _go(String label, VoidCallback? onPressed, {bool busy = false}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.calculate),
          label: Text(busy ? tr('Calcul en cours…', 'Computing…') : label),
        ),
      ),
    );

Widget _needData(BuildContext context, String what) => Banner2(Severity.info,
    tr('$what travaille sur un jeu de données individuelles : importez-le à l\'étape 4 d\'un projet (une ligne par sujet ou par isolat).',
        '$what works on an individual dataset: import it in step 4 of a project (one row per subject or isolate).'));

Widget _multi(BuildContext context, String label, List<String> options, Set<String> selected, VoidCallback changed) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (s) {
              s ? selected.add(o) : selected.remove(o);
              changed();
            },
          ),
      ]),
    ]);

Future<String?> _pickText(BuildContext context, List<String> ext) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ext);
  if (files.isEmpty) return null;
  return utf8.decode(await files.single.xFile.readAsBytes(), allowMalformed: true);
}

List<double> _series(TextEditingController c, String name) {
  final v = parseSeries(c.text);
  if (v.isEmpty || v.any((x) => x == null)) {
    throw StatInputError('series', tr('« $name » : valeurs numériques séparées par des espaces ou « ; ».', '"$name": numeric values separated by spaces or ";".'));
  }
  return [for (final x in v) x!];
}

// ------------------------------------------------------------------ association génétique

class _AssociationTool extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const _AssociationTool(this.ds, this.onResult, {this.initial});
  @override
  State<_AssociationTool> createState() => _AssociationToolState();
}

class _AssociationToolState extends State<_AssociationTool> {
  late String mode = switch (widget.initial) { 'hardy_weinberg' => 'hwe', 'snp_scan' => 'scan', _ => 'assoc' };
  late bool fromData = widget.ds != null;
  final aa = TextEditingController(text: '135'), ab = TextEditingController(text: '132'), bb = TextEditingController(text: '33');
  final caa = TextEditingController(text: '96'), cab = TextEditingController(text: '144'), cbb = TextEditingController(text: '60');
  final major = TextEditingController(text: 'C'), minor = TextEditingController(text: 'T');
  String? snp, outcome, caseLevel, controlsOnlyLevel;
  final snps = <String>{}, covariates = <String>{};
  PAdjust correction = PAdjust.bh;

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    final data = fromData && ds != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'hwe', label: Text(tr('Hardy-Weinberg', 'Hardy-Weinberg'))),
          ButtonSegment(value: 'assoc', label: Text(tr('Un variant', 'One variant'))),
          ButtonSegment(value: 'scan', label: Text(tr('Plusieurs variants', 'Several variants'))),
        ],
        selected: {mode},
        onSelectionChanged: (s) => setState(() => mode = s.first),
      ),
      const SizedBox(height: 10),
      if (mode != 'scan' && ds != null) SourceToggle(fromData, (v) => setState(() => fromData = v), manualLabel: tr('Effectifs génotypiques', 'Genotype counts')),
      if (mode == 'scan' && ds == null) _needData(context, tr('Le balayage de variants', 'The variant scan')),
      if (mode == 'hwe' && !data) ...[
        Text(tr('Effectifs des trois génotypes (de préférence chez les témoins)', 'Counts of the three genotypes (preferably in controls)')),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 90, child: TextField(controller: major, decoration: InputDecoration(labelText: tr('Allèle 1', 'Allele 1'), isDense: true, border: const OutlineInputBorder()))),
          SizedBox(width: 90, child: TextField(controller: minor, decoration: InputDecoration(labelText: tr('Allèle 2', 'Allele 2'), isDense: true, border: const OutlineInputBorder()))),
          NumField(tr('Homozygotes 1/1', 'Homozygotes 1/1'), aa),
          NumField(tr('Hétérozygotes 1/2', 'Heterozygotes 1/2'), ab),
          NumField(tr('Homozygotes 2/2', 'Homozygotes 2/2'), bb),
        ]),
      ],
      if (mode == 'assoc' && !data) ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 90, child: TextField(controller: major, decoration: InputDecoration(labelText: tr('Allèle 1', 'Allele 1'), isDense: true, border: const OutlineInputBorder()))),
          SizedBox(width: 90, child: TextField(controller: minor, decoration: InputDecoration(labelText: tr('Allèle 2', 'Allele 2'), isDense: true, border: const OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        Text(tr('Cas : 1/1, 1/2, 2/2', 'Cases: 1/1, 1/2, 2/2')),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 12, children: [NumField('1/1', caa), NumField('1/2', cab), NumField('2/2', cbb)]),
        const SizedBox(height: 10),
        Text(tr('Témoins : 1/1, 1/2, 2/2', 'Controls: 1/1, 1/2, 2/2')),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 12, children: [NumField('1/1', aa), NumField('1/2', ab), NumField('2/2', bb)]),
      ],
      if (ds != null && (data || mode == 'scan')) ...[
        Text(tr('Génotypes acceptés : A/G, A|G, AG ou 0/1/2 (nombre d\'allèles mineurs).', 'Accepted genotypes: A/G, A|G, AG or 0/1/2 (number of minor alleles).'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (mode != 'scan') Pick<String>(tr('Variant (génotypes)', 'Variant (genotypes)'), snp, _cols(ds, types: _categorical), (v) => setState(() => snp = v)),
          Pick<String>(mode == 'hwe' ? tr('Statut (facultatif, pour restreindre aux témoins)', 'Status (optional, to restrict to controls)') : tr('Statut cas/témoin', 'Case/control status'),
              outcome, [if (mode == 'hwe') ('', tr('— tous les sujets —', '— all subjects —')), ..._cols(ds, types: {VarType.binary, VarType.categorical})], (v) => setState(() {
                outcome = (v == null || v.isEmpty) ? null : v;
                caseLevel = null;
                controlsOnlyLevel = null;
              })),
          if (outcome != null && mode != 'hwe')
            Pick<String>(tr('Modalité « cas »', 'Case level'), caseLevel, [for (final l in ds.levels(outcome!)) (l, l)], (v) => setState(() => caseLevel = v)),
          if (outcome != null && mode == 'hwe')
            Pick<String>(tr('Modalité « témoin »', 'Control level'), controlsOnlyLevel, [for (final l in ds.levels(outcome!)) (l, l)], (v) => setState(() => controlsOnlyLevel = v)),
        ]),
        if (mode == 'scan') ...[
          _multi(context, tr('Variants à tester', 'Variants to test'), [for (final n in ds.names) if (_categorical.contains(ds.dictionary[n]!.type) && n != outcome) n], snps, () => setState(() {})),
          _multi(context, tr('Covariables d\'ajustement (facultatif)', 'Adjustment covariates (optional)'),
              [for (final n in ds.names) if (n != outcome && !snps.contains(n) && ds.dictionary[n]!.type != VarType.identifier) n], covariates, () => setState(() {})),
          const SizedBox(height: 10),
          Pick<PAdjust>(tr('Correction des tests multiples', 'Multiple-testing correction'), correction, [for (final m in PAdjust.values) (m, pAdjustLabel(m))],
              (v) => setState(() => correction = v ?? PAdjust.bh), width: 340),
        ],
      ],
      if (!(mode == 'scan' && ds == null))
        _go(tr('Calculer', 'Compute'), () {
          run(context, () {
            if (mode == 'hwe') {
              if (!data) return hardyWeinberg(readInt(aa) ?? -1, readInt(ab) ?? -1, readInt(bb) ?? -1, major: major.text.trim(), minor: minor.text.trim());
              if (snp == null) throw StatInputError('missing', tr('Choisir la colonne du variant.', 'Choose the variant column.'));
              final s = snpData(snp!, ds.text(snp!));
              final excl = ds.excludedRows;
              final y = outcome == null ? null : ds.text(outcome!);
              if (outcome != null && controlsOnlyLevel == null) throw StatInputError('missing', tr('Choisir la modalité « témoin ».', 'Choose the control level.'));
              final rows = [for (var i = 0; i < ds.rowCount; i++) if (!excl.contains(i) && (y == null || y[i] == controlsOnlyLevel)) i];
              final c = s.counts(rows);
              return hardyWeinberg(c[0], c[1], c[2], major: s.major, minor: s.minor, variant: snp!);
            }
            if (mode == 'assoc') {
              if (!data) {
                return geneticAssociation([readInt(caa) ?? -1, readInt(cab) ?? -1, readInt(cbb) ?? -1], [readInt(aa) ?? -1, readInt(ab) ?? -1, readInt(bb) ?? -1],
                    major: major.text.trim(), minor: minor.text.trim());
              }
              if (snp == null || outcome == null || caseLevel == null) {
                throw StatInputError('missing', tr('Choisir le variant, le statut et la modalité « cas ».', 'Choose the variant, the status and the case level.'));
              }
              return snpAssociation(ds, snp!, outcome!, caseLevel!);
            }
            if (outcome == null || caseLevel == null) throw StatInputError('missing', tr('Choisir le statut et la modalité « cas ».', 'Choose the status and the case level.'));
            return snpScan(ds!, snps.toList(), outcome!, caseLevel!, correction: correction, covariates: [
              for (final c in covariates) TermSpec(c, categorical: ds.dictionary[c]!.type != VarType.numeric, reference: ds.dictionary[c]!.type != VarType.numeric ? ds.levels(c).first : null)
            ]);
          }, widget.onResult, options: {'mode': mode});
        }),
    ]);
  }
}

// ------------------------------------------------------------------ pathogènes

class _PathogensTool extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  final String? initial;
  const _PathogensTool(this.ds, this.onResult, {this.initial});
  @override
  State<_PathogensTool> createState() => _PathogensToolState();
}

class _PathogensToolState extends State<_PathogensTool> {
  late String mode = widget.initial == 'type_diversity' ? 'diversity' : 'concordance';
  String? phenotype, resistant, typeCol;
  final mutations = <String>{};

  @override
  Widget build(BuildContext context) {
    final ds = widget.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'concordance', label: Text(tr('Mutations ↔ résistance', 'Mutations ↔ resistance'))),
          ButtonSegment(value: 'diversity', label: Text(tr('Pouvoir discriminant du typage', 'Typing discriminatory power'))),
        ],
        selected: {mode},
        onSelectionChanged: (s) => setState(() => mode = s.first),
      ),
      const SizedBox(height: 10),
      if (ds == null)
        _needData(context, tr('Cet outil', 'This tool'))
      else if (mode == 'concordance') ...[
        Text(tr('Une ligne par isolat : phénotype R/S (antibiogramme) et une colonne par mutation (présente/absente, oui/non, 1/0).',
            'One row per isolate: R/S phenotype (susceptibility testing) and one column per mutation (present/absent, yes/no, 1/0).'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Phénotype', 'Phenotype'), phenotype, _cols(ds, types: {VarType.binary, VarType.categorical}), (v) => setState(() {
                phenotype = v;
                resistant = v == null ? null : (ds.levels(v).contains('R') ? 'R' : null);
              })),
          if (phenotype != null) Pick<String>(tr('Modalité « résistant »', 'Resistant level'), resistant, [for (final l in ds.levels(phenotype!)) (l, l)], (v) => setState(() => resistant = v)),
        ]),
        _multi(context, tr('Mutations', 'Mutations'), [for (final n in ds.names) if (n != phenotype && ds.dictionary[n]!.type == VarType.binary) n], mutations, () => setState(() {})),
        _go(tr('Calculer', 'Compute'), () {
          run(context, () {
            if (phenotype == null || resistant == null) throw StatInputError('missing', tr('Choisir le phénotype et la modalité « résistant ».', 'Choose the phenotype and the resistant level.'));
            return mutationPhenotypeConcordance(ds, phenotype!, resistant!, mutations.toList());
          }, widget.onResult);
        }),
      ] else ...[
        Pick<String>(tr('Type (MLST, spa, lignée…)', 'Type (MLST, spa, lineage…)'), typeCol, _cols(ds, types: _categorical), (v) => setState(() => typeCol = v)),
        _go(tr('Calculer', 'Compute'), () {
          run(context, () {
            if (typeCol == null) throw StatInputError('missing', tr('Choisir la colonne des types.', 'Choose the type column.'));
            return typeDiversity(ds, typeCol!);
          }, widget.onResult);
        }),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ qPCR

class _QpcrTool extends StatefulWidget {
  final OnResult onResult;
  final String? initial;
  const _QpcrTool(this.onResult, {this.initial});
  @override
  State<_QpcrTool> createState() => _QpcrToolState();
}

class _QpcrToolState extends State<_QpcrTool> {
  late String mode = switch (widget.initial) { 'qpcr_relative' => 'relative', 'qpcr_lod' => 'lod', _ => 'curve' };
  final logq = TextEditingController(text: '1 2 3 4 5 6'), ct = TextEditingController(text: '33,2 29,9 26,5 23,2 19,8 16,5'), unk = TextEditingController(text: '25,1 28,4');
  final tc = TextEditingController(text: '24,9 25,3 25,1'), rc = TextEditingController(text: '18,0 18,2 17,9');
  final tt = TextEditingController(text: '22,8 23,1 22,7'), rt = TextEditingController(text: '18,1 17,9 17,8');
  final eT = TextEditingController(text: '2'), eR = TextEditingController(text: '2');
  final conc = TextEditingController(text: '1 2,5 5 10 25 50'), det = TextEditingController(text: '3 8 14 18 20 20'), tot = TextEditingController(text: '20 20 20 20 20 20');
  final prob = TextEditingController(text: '0,95');

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: c, decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'curve', label: Text(tr('Courbe standard', 'Standard curve'))),
          ButtonSegment(value: 'relative', label: Text(tr('ΔΔCt / Pfaffl', 'ΔΔCt / Pfaffl'))),
          ButtonSegment(value: 'lod', label: Text(tr('Limite de détection', 'Limit of detection'))),
        ],
        selected: {mode},
        onSelectionChanged: (s) => setState(() => mode = s.first),
      ),
      const SizedBox(height: 12),
      if (mode == 'curve') ...[
        _field(logq, tr('log10 quantité des standards', 'log10 quantity of the standards')),
        _field(ct, tr('Ct des standards (même ordre)', 'Ct of the standards (same order)')),
        _field(unk, tr('Ct des échantillons inconnus (facultatif)', 'Ct of the unknown samples (optional)')),
      ],
      if (mode == 'relative') ...[
        Text(tr('Un Ct par échantillon biologique (réplicats techniques déjà moyennés), cible et référence dans le même ordre.',
            'One Ct per biological sample (technical replicates already averaged), target and reference in the same order.'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _field(tc, tr('Témoins : Ct du gène cible', 'Controls: target gene Ct')),
        _field(rc, tr('Témoins : Ct du gène de référence', 'Controls: reference gene Ct')),
        _field(tt, tr('Traités : Ct du gène cible', 'Treated: target gene Ct')),
        _field(rt, tr('Traités : Ct du gène de référence', 'Treated: reference gene Ct')),
        Wrap(spacing: 12, runSpacing: 12, children: [
          NumField(tr('Facteur d\'amplification cible', 'Target amplification factor'), eT, width: 220, helper: tr('2 = efficacité 100 %', '2 = 100% efficiency')),
          NumField(tr('Facteur d\'amplification référence', 'Reference amplification factor'), eR, width: 220, helper: tr('1 + efficacité', '1 + efficiency')),
        ]),
      ],
      if (mode == 'lod') ...[
        _field(conc, tr('Concentrations testées (copies/réaction…)', 'Concentrations tested (copies/reaction…)')),
        _field(det, tr('Réplicats détectés (même ordre)', 'Replicates detected (same order)')),
        _field(tot, tr('Réplicats testés (même ordre)', 'Replicates tested (same order)')),
        NumField(tr('Probabilité de détection', 'Detection probability'), prob),
      ],
      _go(tr('Calculer', 'Compute'), () {
        run(context, () {
          switch (mode) {
            case 'curve':
              final u = parseSeries(unk.text);
              return qpcrStandardCurve(_series(logq, 'log10 q'), _series(ct, 'Ct'), unknownCt: [for (final x in u) ?x]);
            case 'relative':
              return qpcrRelativeQuantification(_series(tc, tr('Ct cible témoins', 'Control target Ct')), _series(rc, tr('Ct référence témoins', 'Control reference Ct')),
                  _series(tt, tr('Ct cible traités', 'Treated target Ct')), _series(rt, tr('Ct référence traités', 'Treated reference Ct')),
                  eTarget: readNum(eT) ?? 2, eRef: readNum(eR) ?? 2);
            default:
              List<int> ints(TextEditingController c, String n) => [for (final v in _series(c, n)) v.round()];
              return qpcrLimitOfDetection(_series(conc, tr('Concentrations', 'Concentrations')), ints(det, tr('Détectés', 'Detected')), ints(tot, tr('Testés', 'Tested')),
                  probability: (readNum(prob) ?? 0.95).clamp(0.5, 0.999));
          }
        }, widget.onResult, options: {'mode': mode});
      }),
    ]);
  }
}

// ------------------------------------------------------------------ expression différentielle

typedef _ExprArgs = (
  List<String> genes,
  List<List<double>> counts,
  List<String> samples,
  List<String> group,
  String reference,
  Map<String, List<String>> factors,
  (String, List<double>)? covariate,
  (double fdr, double minFc, double minCpm, int contrast),
  Lang lang,
  List<String>? block,
);

Map<String, Object?> _runExpression(_ExprArgs a) {
  setLang(a.$9);
  final design = ExpressionDesign(a.$4, reference: a.$5, factors: a.$6, covariates: {if (a.$7 != null) a.$7!.$1: a.$7!.$2}, block: a.$10);
  final o = a.$8;
  final r = differentialExpressionDesign(a.$1, a.$2, design, samples: a.$3, fdr: o.$1, minLogFC: o.$2, minCpm: o.$3, volcanoContrast: o.$4);
  return sanitizeJson(r.toJson()) as Map<String, Object?>;
}

List<String> _tokens(String s) => s.split(RegExp(r'[\s;,]+')).where((t) => t.isNotEmpty).toList();

/// Groupe déduit du nom d'un échantillon : chiffres et séparateurs finaux retirés (« temoin2 » → « temoin »).
String _guessGroup(String sample) {
  final g = sample.replaceAll(RegExp(r'[\s_\-.]*\d+$'), '');
  return g.isEmpty ? sample : g;
}

class _ExpressionTool extends StatefulWidget {
  final Dataset? ds;
  final OnResult onResult;
  const _ExpressionTool(this.ds, this.onResult);
  @override
  State<_ExpressionTool> createState() => _ExpressionToolState();
}

class _ExpressionToolState extends State<_ExpressionTool> {
  late bool fromProject = widget.ds != null;
  Dataset? loaded;
  String loadedName = '';
  String? geneCol, reference;
  final samples = <String>{};
  final groups = TextEditingController(), batch = TextEditingController(), covName = TextEditingController(text: 'RIN'), covValues = TextEditingController();
  final subject = TextEditingController();
  String pairing = 'auto'; // auto, fixed, block
  final fdr = TextEditingController(text: '0,05'), minFc = TextEditingController(text: '1'), minCpm = TextEditingController(text: '1');
  int contrast = 0;
  bool busy = false;

  Dataset? get matrix => fromProject ? widget.ds : loaded;
  List<String> get orderedSamples => [for (final n in matrix?.names ?? const <String>[]) if (samples.contains(n)) n];

  void _adopt(Dataset ds, String name, {List<String>? groupLabels, List<String>? batchLabels, List<String>? subjectLabels, String? ref}) {
    setState(() {
      loaded = ds;
      loadedName = name;
      fromProject = false;
      _defaults(ds, groupLabels: groupLabels, batchLabels: batchLabels, subjectLabels: subjectLabels);
      reference = ref;
    });
  }

  void _defaults(Dataset ds, {List<String>? groupLabels, List<String>? batchLabels, List<String>? subjectLabels}) {
    geneCol = ds.names.firstWhere((n) => ds.dictionary[n]!.type != VarType.numeric, orElse: () => ds.names.first);
    samples
      ..clear()
      ..addAll([for (final n in ds.names) if (n != geneCol && ds.dictionary[n]!.type == VarType.numeric) n]);
    groups.text = (groupLabels ?? [for (final s in orderedSamples) _guessGroup(s)]).join(' ');
    batch.text = (batchLabels ?? const []).join(' ');
    subject.text = (subjectLabels ?? const []).join(' ');
    pairing = 'auto';
    covValues.clear();
    reference = null;
    contrast = 0;
  }

  /// Plan lu dans les champs (null si incomplet) ; lève une erreur lisible si les longueurs ne concordent pas.
  ExpressionDesign? _design({bool strict = false}) {
    final n = orderedSamples.length;
    if (n == 0) {
      if (strict) throw StatInputError('no_samples', tr('Aucun échantillon sélectionné.', 'No sample selected.'));
      return null;
    }
    final g = _tokens(groups.text);
    if (g.length != n) {
      if (strict) {
        throw StatInputError('groups', tr('Groupes : ${g.length} valeur(s) pour $n échantillon(s) ; une valeur par échantillon, dans l\'ordre indiqué.',
            'Groups: ${g.length} value(s) for $n sample(s); one value per sample, in the order shown.'));
      }
      return null;
    }
    final b = _tokens(batch.text);
    if (b.isNotEmpty && b.length != n) {
      if (!strict) return null;
      throw StatInputError('batch', tr('Lot : ${b.length} valeur(s) pour $n échantillon(s).', 'Batch: ${b.length} value(s) for $n sample(s).'));
    }
    final c = parseSeries(covValues.text);
    if (c.isNotEmpty && (c.length != n || c.any((v) => v == null))) {
      if (!strict) return null;
      throw StatInputError('covariate', tr('Covariable : une valeur numérique par échantillon ($n attendue(s)).', 'Covariate: one numeric value per sample ($n expected).'));
    }
    final subj = _tokens(subject.text);
    if (subj.isNotEmpty && subj.length != n) {
      if (!strict) return null;
      throw StatInputError('subject', tr('Sujet : ${subj.length} valeur(s) pour $n échantillon(s).', 'Subject: ${subj.length} value(s) for $n sample(s).'));
    }
    final base = ExpressionDesign(g, reference: reference, factors: {if (b.isNotEmpty) tr('lot', 'batch'): b},
        covariates: {if (c.isNotEmpty) covName.text.trim().isEmpty ? 'covariable' : covName.text.trim(): [for (final v in c) v!]});
    if (subj.isEmpty) return base;
    final fixed = pairing == 'fixed' || (pairing == 'auto' && subjectAsFixedEffect(base, subj));
    return fixed
        ? ExpressionDesign(base.group, reference: base.reference, factors: {...base.factors, tr('sujet', 'subject'): subj}, covariates: base.covariates)
        : ExpressionDesign(base.group, reference: base.reference, factors: base.factors, covariates: base.covariates, block: subj);
  }

  @override
  void initState() {
    super.initState();
    if (widget.ds != null) _defaults(widget.ds!);
  }

  Widget _field(TextEditingController c, String label, {String? helper}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ds = matrix;
    final design = ds == null ? null : _design();
    final levels = design?.levels ?? const <String>[];
    final contrasts = design == null ? const <String>[] : expressionContrastNames(design);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Matrice de comptages BRUTS : une ligne par gène, une colonne d\'identifiant de gène, une colonne numérique par échantillon.',
          'Matrix of RAW counts: one row per gene, one gene identifier column, one numeric column per sample.'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      if (widget.ds != null)
        SourceToggle(fromProject, (v) => setState(() {
              fromProject = v;
              if (v) _defaults(widget.ds!);
            }), manualLabel: tr('Fichier ou exemple', 'File or example')),
      if (!fromProject)
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: Text(tr('Charger un fichier CSV', 'Load a CSV file')),
            onPressed: () async {
              final text = await _pickText(context, ['csv', 'txt', 'tsv']);
              if (text == null) return;
              try {
                _adopt(parseCsv(text, source: tr('matrice de comptages', 'count matrix')).dataset, tr('fichier importé', 'imported file'));
              } on StatInputError catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: Text(tr('Exemple simulé (400 gènes, 3 contre 3)', 'Simulated example (400 genes, 3 vs 3)')),
            onPressed: () {
              final e = exampleRnaSeq();
              final ds = Dataset.fromColumns({
                tr('gene', 'gene'): e.genes,
                for (var j = 0; j < e.samples.length; j++) e.samples[j]: [for (final r in e.counts) r[j].toInt()],
              }, source: tr('comptages simulés', 'simulated counts'));
              _adopt(ds, tr('exemple simulé', 'simulated example'));
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: Text(tr('Exemple à 3 groupes et 2 lots', 'Example with 3 groups and 2 batches')),
            onPressed: () {
              final e = exampleRnaSeqDesign();
              final ds = Dataset.fromColumns({
                tr('gene', 'gene'): e.genes,
                for (var j = 0; j < e.samples.length; j++) e.samples[j]: [for (final r in e.counts) r[j].toInt()],
              }, source: tr('comptages simulés', 'simulated counts'));
              _adopt(ds, tr('exemple à 3 groupes', '3-group example'), groupLabels: e.group, batchLabels: e.batch);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: Text(tr('Exemple apparié avant/après (5 patients)', 'Paired before/after example (5 patients)')),
            onPressed: () {
              final e = exampleRnaSeqPaired();
              final ds = Dataset.fromColumns({
                tr('gene', 'gene'): e.genes,
                for (var j = 0; j < e.samples.length; j++) e.samples[j]: [for (final r in e.counts) r[j].toInt()],
              }, source: tr('comptages simulés', 'simulated counts'));
              _adopt(ds, tr('exemple apparié', 'paired example'), groupLabels: e.time, subjectLabels: e.subject, ref: e.time.first);
            },
          ),
          if (loaded != null)
            Text(tr('${loadedName.isEmpty ? '' : '$loadedName : '}${loaded!.rowCount} gènes', '${loadedName.isEmpty ? '' : '$loadedName: '}${loaded!.rowCount} genes'),
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      if (ds != null && !ds.names.any((n) => ds.dictionary[n]!.type == VarType.numeric))
        Banner2(Severity.info, tr(
            'Ce jeu de données ne contient aucune colonne numérique de comptages (une colonne par échantillon). Choisir « Fichier ou exemple » pour charger une matrice de comptages.',
            'This dataset contains no numeric count column (one column per sample). Choose "File or example" to load a count matrix.'))
      else if (ds != null) ...[
        const SizedBox(height: 10),
        Pick<String>(tr('Identifiant du gène', 'Gene identifier'), geneCol, _cols(ds), (v) => setState(() {
              geneCol = v;
              samples.remove(v);
            })),
        _multi(context, tr('Échantillons analysés', 'Samples analysed'), [for (final n in ds.names) if (n != geneCol && ds.dictionary[n]!.type == VarType.numeric) n], samples,
            () => setState(() => groups.text = [for (final s in orderedSamples) _guessGroup(s)].join(' '))),
        const SizedBox(height: 6),
        Text(tr('Plan d\'expérience — une valeur par échantillon, dans cet ordre : ${orderedSamples.join(', ')}',
            'Experimental design — one value per sample, in this order: ${orderedSamples.join(', ')}'), style: Theme.of(context).textTheme.labelLarge),
        _field(groups, tr('Groupe de chaque échantillon', 'Group of each sample'), helper: tr('2 groupes ou plus ; déduits des noms, à corriger si besoin', '2 or more groups; guessed from the names, correct if needed')),
        _field(batch, tr('Lot de chaque échantillon (facultatif)', 'Batch of each sample (optional)'), helper: tr('date ou ligne de séquençage, série d\'extraction…', 'sequencing date or lane, extraction series…')),
        Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 160, child: _field(covName, tr('Covariable (nom)', 'Covariate (name)'))),
          SizedBox(width: 360, child: _field(covValues, tr('Valeurs de la covariable (facultatif)', 'Covariate values (optional)'))),
        ]),
        _field(subject, tr('Sujet de chaque échantillon (facultatif : mesures répétées, appariement)', 'Subject of each sample (optional: repeated measures, pairing)'),
            helper: tr('même identifiant pour les échantillons d\'un même patient', 'same identifier for samples from the same patient')),
        if (_tokens(subject.text).isNotEmpty) ...[
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'auto', label: Text(tr('Automatique', 'Automatic'))),
              ButtonSegment(value: 'fixed', label: Text(tr('Effet fixe', 'Fixed effect'))),
              ButtonSegment(value: 'block', label: Text(tr('Corrélation intra-sujet', 'Within-subject correlation'))),
            ],
            selected: {pairing},
            // Sans coche : à 390 px, elle coupait « Automatique » au milieu du mot ; la couleur suffit.
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => pairing = v.first),
          ),
          if (design != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  design.block == null
                      ? tr('Sujet en effet fixe : chaque sujet est observé dans plusieurs groupes (appariement), les comparaisons se font à l\'intérieur des sujets.',
                          'Subject as a fixed effect: each subject is observed in several groups (pairing); comparisons are made within subjects.')
                      : tr('Corrélation intra-sujet : le sujet est emboîté dans un groupe ; ses échantillons sont corrélés et pris en compte par moindres carrés généralisés.',
                          'Within-subject correlation: the subject is nested in one group; its samples are correlated and handled by generalized least squares.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (levels.length >= 2)
            Pick<String>(tr('Groupe de référence', 'Reference group'), levels.first, [for (final l in levels) (l, l)], (v) => setState(() {
                  reference = v;
                  contrast = 0;
                })),
          if (contrasts.length > 1)
            Pick<int>(tr('Comparaison du volcano plot', 'Comparison shown in the volcano plot'), contrast.clamp(0, contrasts.length - 1),
                [for (var i = 0; i < contrasts.length; i++) (i, contrasts[i])], (v) => setState(() => contrast = v ?? 0)),
        ]),
        if (design == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('Le plan est incomplet : une valeur par échantillon est attendue dans chaque champ rempli.', 'The design is incomplete: one value per sample is expected in each filled field.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${design.formula} — ${tr('référence', 'reference')} ${levels.first}', style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          NumField(tr('FDR', 'FDR'), fdr, helper: tr('p. ex. 0,05', 'e.g. 0.05')),
          NumField(tr('|log2 FC| minimal', 'Minimal |log2 FC|'), minFc, helper: tr('repère du volcano', 'volcano benchmark'), width: 180),
          NumField(tr('Filtre CPM', 'CPM filter'), minCpm, helper: tr('CPM ≥ seuil', 'CPM ≥ threshold')),
        ]),
        _go(tr('Analyser (TMM + voom + limma)', 'Analyse (TMM + voom + limma)'), () async {
          final cols = orderedSamples;
          try {
            if (geneCol == null || cols.length < 4) throw StatInputError('missing', tr('Choisir l\'identifiant du gène et au moins 4 échantillons.', 'Choose the gene identifier and at least 4 samples.'));
            final d = _design(strict: true)!;
            final genes = [for (final g in ds.text(geneCol!)) g ?? ''];
            final num = [for (final c in cols) ds.numeric(c)];
            if (num.any((col) => col.any((v) => v == null))) {
              throw StatInputError('missing_counts', tr('Valeurs manquantes ou non numériques dans les comptages : aucune n\'est remplacée en silence ; corriger le fichier.',
                  'Missing or non-numeric values in the counts: none is silently replaced; correct the file.'));
            }
            final counts = [for (var g = 0; g < genes.length; g++) [for (final col in num) col[g]!]];
            setState(() => busy = true);
            final cov = d.covariates.isEmpty ? null : (d.covariates.keys.first, d.covariates.values.first);
            final json = await compute(_runExpression, (
              genes,
              counts,
              cols,
              d.group,
              d.levels.first,
              d.factors,
              cov,
              ((readNum(fdr) ?? 0.05).clamp(0.001, 0.5), readNum(minFc) ?? 1, readNum(minCpm) ?? 1, contrast),
              currentLang,
              d.block,
            ));
            if (!context.mounted) return;
            widget.onResult(analysisResultFromJson(json), options: {'samples': cols, 'design': d.formula, 'reference': d.levels.first});
          } on StatInputError catch (e) {
            if (context.mounted) showError(context, e);
          } catch (e) {
            if (context.mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
          } finally {
            if (mounted) setState(() => busy = false);
          }
        }, busy: busy),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ alignement local

Map<String, Object?> _runAlignment((String, String, String, double, Lang) a) {
  setLang(a.$5);
  final type = switch (a.$3) { 'dna' => SeqType.dna, 'protein' => SeqType.protein, _ => null };
  final r = localAlignmentSearch(a.$1, parseFasta(a.$2), type: type, maxEvalue: a.$4);
  return sanitizeJson(r.toJson()) as Map<String, Object?>;
}

class _AlignmentTool extends StatefulWidget {
  final OnResult onResult;
  const _AlignmentTool(this.onResult);
  @override
  State<_AlignmentTool> createState() => _AlignmentToolState();
}

class _AlignmentToolState extends State<_AlignmentTool> {
  final query = TextEditingController(), library = TextEditingController();
  final maxE = TextEditingController(text: '10');
  String type = 'auto';
  bool busy = false;

  String _summary() {
    if (library.text.trim().isEmpty) return '';
    try {
      final s = fastaSummary(library.text);
      return tr('${s.sequences} séquence(s), ${s.letters} lettres', '${s.sequences} sequence(s), ${s.letters} letters');
    } catch (_) {
      return tr('FASTA illisible', 'Unreadable FASTA');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Banner2(Severity.info,
          tr('Recherche locale contre VOTRE bibliothèque FASTA (Smith-Waterman optimal, statistiques de BLAST) : aucune base en ligne n\'est interrogée.',
              'Local search against YOUR FASTA library (optimal Smith-Waterman, BLAST statistics): no online database is queried.')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.science_outlined),
          label: Text(tr('Exemple simulé', 'Simulated example')),
          onPressed: () {
            final e = exampleFasta();
            setState(() {
              query.text = e.query;
              library.text = e.library;
            });
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: Text(tr('Charger la requête', 'Load the query')),
          onPressed: () async {
            final t = await _pickText(context, ['fasta', 'fa', 'fna', 'faa', 'fas', 'txt', 'seq']);
            if (t != null) setState(() => query.text = t);
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.library_books_outlined),
          label: Text(tr('Charger la bibliothèque', 'Load the library')),
          onPressed: () async {
            final t = await _pickText(context, ['fasta', 'fa', 'fna', 'faa', 'fas', 'txt']);
            if (t != null) setState(() => library.text = t);
          },
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: query,
        minLines: 3,
        maxLines: 6,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: InputDecoration(labelText: tr('Séquence requête (FASTA ou texte brut)', 'Query sequence (FASTA or plain text)'), border: const OutlineInputBorder(), alignLabelWithHint: true),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: library,
        minLines: 4,
        maxLines: 10,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: InputDecoration(
            labelText: tr('Bibliothèque de référence (FASTA)', 'Reference library (FASTA)'), helperText: _summary(), border: const OutlineInputBorder(), alignLabelWithHint: true),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(tr('Type de séquence', 'Sequence type'), type, [('auto', tr('Détection automatique', 'Automatic detection')), ('dna', tr('ADN', 'DNA')), ('protein', tr('Protéine', 'Protein'))],
            (v) => setState(() => type = v ?? 'auto'), width: 220),
        NumField(tr('E-value maximale', 'Maximum E-value'), maxE),
      ]),
      _go(tr('Rechercher', 'Search'), () async {
        try {
          if (query.text.trim().isEmpty || library.text.trim().isEmpty) {
            throw StatInputError('missing', tr('Saisir une requête et une bibliothèque FASTA.', 'Enter a query and a FASTA library.'));
          }
          setState(() => busy = true);
          final json = await compute(_runAlignment, (query.text, library.text, type, readNum(maxE) ?? 10, currentLang));
          if (!context.mounted) return;
          widget.onResult(analysisResultFromJson(json), options: {'type': type, 'max_evalue': readNum(maxE) ?? 10});
        } on StatInputError catch (e) {
          if (context.mounted) showError(context, e);
        } catch (e) {
          if (context.mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
        } finally {
          if (mounted) setState(() => busy = false);
        }
      }, busy: busy),
    ]);
  }
}

// ------------------------------------------------------------------ randomisation mendélienne

/// Randomisation mendélienne à partir de statistiques résumées : quatre colonnes numériques (βX, ES, βY, ES) du projet
/// ou de l'exemple publié LDL-C → maladie coronarienne.
class MrTool extends StatefulWidget {
  final Dataset? dataset;
  final OnResult onResult;
  const MrTool(this.dataset, this.onResult, {super.key});
  @override
  State<MrTool> createState() => MrToolState();
}

class MrToolState extends State<MrTool> {
  Dataset? example;
  String? bx, bxse, by, byse, names;
  bool logOdds = true;

  /// MR multivariée : expositions supplémentaires (colonne β, colonne ES).
  bool multivariable = false;

  /// Sous-ensemble de variants (colonne, modalité) ; sens inverse (issue → exposition) ; effectifs pour le test de Steiger.
  String? subsetCol, subsetLevel;
  bool reverse = false;
  final nX = TextEditingController(), nY = TextEditingController();
  final extra = <(String?, String?)>[(null, null), (null, null)];
  final exposure = TextEditingController(), outcome = TextEditingController();

  Dataset? get data => example ?? widget.dataset;

  /// Statistiques résumées de GWAS (exposition, issue) et leur harmonisation ; seuil et fenêtre de clumping.
  GwasSumstats? gwasX, gwasY;
  GwasHarmonisation? harmonisation;
  final gwasThreshold = TextEditingController(text: '5e-8'), gwasKb = TextEditingController(text: '10000');

  /// Lit un fichier GWAS (texte ou .gz) ; quand les deux sont présents, choisit les instruments et harmonise.
  void loadGwas(List<int> bytes, String name, {required bool isExposure}) {
    try {
      final raw = name.toLowerCase().endsWith('.gz') ? const GZipDecoder().decodeBytes(bytes) : bytes;
      final g = parseGwasSumstats(utf8.decode(raw, allowMalformed: true), source: name.replaceAll(RegExp(r'\.gz$', caseSensitive: false), ''));
      setState(() => isExposure ? gwasX = g : gwasY = g);
      if (gwasX != null && gwasY != null) harmonise();
    } on FormatException catch (e) {
      showError(context, e.message);
    }
  }

  void harmonise() {
    final p = parseNumber(gwasThreshold.text.trim()), kb = parseNumber(gwasKb.text.trim());
    if (gwasX == null || gwasY == null) return;
    if (p == null || !(p > 0 && p < 1) || kb == null || kb < 0) {
      showError(context, tr('Seuil p entre 0 et 1 et fenêtre de clumping positive (kb).', 'p threshold between 0 and 1 and a positive clumping window (kb).'));
      return;
    }
    final h = harmoniseGwas(gwasX!, gwasY!, pThreshold: p, windowKb: kb);
    setState(() {
      harmonisation = h;
      example = h.toDataset();
      names = 'variant';
      bx = 'beta_x';
      bxse = 'se_x';
      by = 'beta_y';
      byse = 'se_y';
      subsetCol = subsetLevel = null;
      reverse = false;
      multivariable = false;
      logOdds = gwasY!.fromOddsRatio || logOdds;
    });
  }

  Future<void> pickGwas({required bool isExposure}) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['tsv', 'txt', 'csv', 'gz', 'ssf']);
    if (files.isEmpty || !mounted) return;
    loadGwas(await files.single.xFile.readAsBytes(), files.single.name, isExposure: isExposure);
  }

  /// Exemple simulé : deux GWAS complets (12 000 variants), l'issue au format TwoSampleMR (OR, allèles à harmoniser).
  Future<void> loadGwasExample() async {
    Future<List<int>> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final x = await b('gwas_exposition_simule.tsv.gz'), y = await b('gwas_issue_simule.tsv.gz');
    if (!mounted) return;
    exposure.text = tr('exposition simulée', 'simulated exposure');
    outcome.text = tr('issue simulée', 'simulated outcome');
    logOdds = true;
    loadGwas(x, 'gwas_exposition_simule.tsv.gz', isExposure: true);
    loadGwas(y, 'gwas_issue_simule.tsv.gz', isExposure: false);
  }

  Widget _gwasPanel() {
    final h = harmonisation;
    String fileLabel(GwasSumstats? g) => g == null ? tr('aucun fichier', 'no file') : tr('${g.source} (${g.variants.length} variants)', '${g.source} (${g.variants.length} variants)');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('À partir de deux GWAS complets (statistiques résumées)', 'From two full GWAS (summary statistics)'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(tr('Formats GWAS-SSF (GWAS Catalog), OpenGWAS / TwoSampleMR ou PLINK ; .tsv, .csv ou .gz. Instruments : seuil p puis clumping par distance ; allèles harmonisés (inversion, brin, palindromiques).',
              'GWAS-SSF (GWAS Catalog), OpenGWAS / TwoSampleMR or PLINK formats; .tsv, .csv or .gz. Instruments: p threshold then distance clumping; alleles harmonised (flip, strand, palindromic).')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(icon: const Icon(Icons.upload_file), label: Text(tr('GWAS de l\'exposition', 'Exposure GWAS')), onPressed: () => pickGwas(isExposure: true)),
            Text(fileLabel(gwasX)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(icon: const Icon(Icons.upload_file), label: Text(tr('GWAS de l\'issue', 'Outcome GWAS')), onPressed: () => pickGwas(isExposure: false)),
            Text(fileLabel(gwasY)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 140, child: TextField(controller: gwasThreshold, decoration: InputDecoration(labelText: tr('Seuil p', 'p threshold')))),
            SizedBox(width: 160, child: TextField(controller: gwasKb, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Clumping (kb)', 'Clumping (kb)')))),
            FilledButton.tonalIcon(
                icon: const Icon(Icons.join_inner), label: Text(tr('Harmoniser', 'Harmonise')), onPressed: gwasX != null && gwasY != null ? harmonise : null),
          ]),
          if (h != null) ...[
            const SizedBox(height: 10),
            Banner2(h.usable.length >= 3 ? Severity.info : Severity.caution, h.summary().join('\n')),
          ],
        ]),
      ),
    );
  }

  /// Exemple publié (28 variants, Waterworth et al. 2010, jeu du paquet R MendelianRandomization).
  /// Exemple simulé de sens causal : X cause Y ; instruments de X (« X ») et de Y (« Y »).
  Future<void> loadDirectionExample() async {
    final csv = await rootBundle.loadString('assets/demos/mr_bidirectionnel_simule.csv');
    setState(() {
      example = parseCsv(csv, source: 'mr_bidirectionnel_simule.csv').dataset;
      names = 'variant';
      bx = 'beta_x';
      bxse = 'se_x';
      by = 'beta_y';
      byse = 'se_y';
      subsetCol = 'instrument';
      subsetLevel = 'X';
      reverse = false;
      multivariable = false;
      exposure.text = 'X';
      outcome.text = 'Y';
      logOdds = false;
      nX.text = '60000';
      nY.text = '90000';
    });
  }

  /// Lignes retenues (sous-ensemble éventuel) et colonnes (β, ES) de l'exposition et de l'issue, échangées en sens inverse.
  ({List<int> rows, List<double?> bx, List<double?> sx, List<double?> by, List<double?> sy}) _columns(Dataset d) {
    List<double?> col(String c) => [for (final v in d.text(c)) v == null ? null : parseNumber(v)];
    final a = (col(bx!), col(bxse!)), b = (col(by!), col(byse!));
    final (x, y) = reverse ? (b, a) : (a, b);
    final rows = [
      for (var i = 0; i < d.rowCount; i++)
        if ((subsetCol == null || subsetLevel == null || d.cell(i, subsetCol!) == subsetLevel) && x.$1[i] != null && x.$2[i] != null && y.$1[i] != null && y.$2[i] != null) i
    ];
    return (rows: rows, bx: x.$1, sx: x.$2, by: y.$1, sy: y.$2);
  }

  String get _exposureName => reverse ? (outcome.text.trim().isEmpty ? by! : outcome.text.trim()) : exposure.text.trim();
  String get _outcomeName => reverse ? (exposure.text.trim().isEmpty ? bx! : exposure.text.trim()) : outcome.text.trim();

  void runSteiger() {
    final d = data;
    final a = int.tryParse(nX.text.trim().replaceAll(' ', '')), b = int.tryParse(nY.text.trim().replaceAll(' ', ''));
    if (d == null || bx == null || bxse == null || by == null || byse == null) return;
    if (a == null || b == null) {
      showError(context, tr('Indiquer les effectifs des deux études.', 'Enter the sample sizes of both studies.'));
      return;
    }
    final c = _columns(d);
    try {
      final r = steigerDirectionality([for (final i in c.rows) c.bx[i]!], [for (final i in c.rows) c.sx[i]!], [for (final i in c.rows) c.by[i]!], [for (final i in c.rows) c.sy[i]!],
          nX: reverse ? b : a, nY: reverse ? a : b, names: names == null ? null : [for (final i in c.rows) d.cell(i, names!) ?? '${i + 1}'],
          exposure: _exposureName, outcome: _outcomeName, outcomeBinary: logOdds && !reverse);
      widget.onResult(r.result, options: {'reverse': reverse, 'subset': subsetLevel});
    } on StatInputError catch (e) {
      showError(context, e);
    }
  }

  Future<void> loadExample() async {
    final csv = await rootBundle.loadString('assets/demos/mr_ldl_chd.csv');
    setState(() {
      example = parseCsv(csv, source: 'mr_ldl_chd.csv').dataset;
      names = 'variant';
      bx = 'beta_ldl';
      bxse = 'se_ldl';
      by = 'beta_chd';
      byse = 'se_chd';
      extra[0] = ('beta_hdl', 'se_hdl');
      extra[1] = ('beta_tg', 'se_tg');
      exposure.text = tr('LDL-cholestérol (mmol/L)', 'LDL cholesterol (mmol/L)');
      outcome.text = tr('maladie coronarienne', 'coronary heart disease');
      logOdds = true;
    });
  }

  void run() {
    final d = data;
    if (d == null || bx == null || bxse == null || by == null || byse == null) return;
    List<double?> col(String c) => [for (final v in d.text(c)) v == null ? null : parseNumber(v)];
    final cc = _columns(d);
    final cols = [cc.bx, cc.sx, cc.by, cc.sy];
    final rows = cc.rows;
    final extras = [for (final e in extra) if (e.$1 != null && e.$2 != null) e];
    if (multivariable && extras.isNotEmpty) {
      final ec = [for (final e in extras) (col(e.$1!), col(e.$2!))];
      final rows2 = [for (final i in rows) if (ec.every((c) => c.$1[i] != null && c.$2[i] != null)) i];
      try {
        final r = multivariableMendelianRandomization([
          [for (final i in rows2) cols[0][i]!],
          for (final c in ec) [for (final i in rows2) c.$1[i]!],
        ], [
          [for (final i in rows2) cols[1][i]!],
          for (final c in ec) [for (final i in rows2) c.$2[i]!],
        ], [for (final i in rows2) cols[2][i]!], [for (final i in rows2) cols[3][i]!],
            exposures: [exposure.text.trim().isEmpty ? bx! : exposure.text.trim(), for (final e in extras) e.$1!], outcome: outcome.text.trim(), outcomeLogOdds: logOdds);
        widget.onResult(r.result, options: {'columns': [bx, bxse, by, byse, for (final e in extras) ...[e.$1, e.$2]], 'example': example != null});
      } on StatInputError catch (e) {
        showError(context, e);
      }
      return;
    }
    try {
      final r = mendelianRandomization([for (final i in rows) cols[0][i]!], [for (final i in rows) cols[1][i]!], [for (final i in rows) cols[2][i]!],
          [for (final i in rows) cols[3][i]!],
          names: names == null ? null : [for (final i in rows) d.cell(i, names!) ?? '${i + 1}'],
          exposure: _exposureName, outcome: _outcomeName, outcomeLogOdds: logOdds && !reverse);
      widget.onResult(r.result, options: {'columns': [bx, bxse, by, byse], 'example': example != null, 'reverse': reverse, if (harmonisation != null && example != null) 'harmonisation': harmonisation!.summary()});
    } on StatInputError catch (e) {
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final numeric = d == null ? const <(String, String)>[] : [for (final n in d.names) if (d.dictionary[n]!.type == VarType.numeric) (n, n)];
    final all = d == null ? const <(String, String)>[] : [for (final n in d.names) (n, n)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Banner2(Severity.info,
          tr('Statistiques résumées par variant instrumental : association avec l\'exposition (βX et son ES) et avec l\'issue (βY et son ES), pour le même allèle et des variants indépendants.',
              'Summary statistics per instrumental variant: association with the exposure (βX and its SE) and with the outcome (βY and its SE), for the same allele and independent variants.')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: Text(tr('Exemple publié : LDL-C et maladie coronarienne (28 variants)', 'Published example: LDL-C and coronary disease (28 variants)')),
            onPressed: loadExample),
        OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: Text(tr('Exemple simulé : sens causal (X → Y)', 'Simulated example: causal direction (X → Y)')),
            onPressed: loadDirectionExample),
        OutlinedButton.icon(
            icon: const Icon(Icons.dataset_outlined),
            label: Text(tr('Exemple simulé : deux GWAS à harmoniser', 'Simulated example: two GWAS to harmonise')),
            onPressed: loadGwasExample),
        if (example != null && widget.dataset != null)
          TextButton(onPressed: () => setState(() => example = null), child: Text(tr('Revenir aux données du projet', 'Back to the project data'))),
      ]),
      const SizedBox(height: 10),
      _gwasPanel(),
      const SizedBox(height: 10),
      if (numeric.length < 4)
        Text(tr('Il faut au moins quatre colonnes numériques (βX, ES, βY, ES) dans le projet, ou charger l\'exemple.',
            'At least four numeric columns (βX, SE, βY, SE) are needed in the project, or load the example.'))
      else ...[
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('βX (exposition)', 'βX (exposure)'), bx, numeric, (v) => setState(() => bx = v)),
          Pick<String>(tr('ES de βX', 'SE of βX'), bxse, numeric, (v) => setState(() => bxse = v)),
          Pick<String>(tr('βY (issue)', 'βY (outcome)'), by, numeric, (v) => setState(() => by = v)),
          Pick<String>(tr('ES de βY', 'SE of βY'), byse, numeric, (v) => setState(() => byse = v)),
          Pick<String>(tr('Nom du variant (facultatif)', 'Variant name (optional)'), names, all, (v) => setState(() => names = v)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 260, child: TextField(controller: exposure, decoration: InputDecoration(labelText: tr('Exposition (nom, unité)', 'Exposure (name, unit)'), isDense: true, border: const OutlineInputBorder()))),
          SizedBox(width: 260, child: TextField(controller: outcome, decoration: InputDecoration(labelText: tr('Issue', 'Outcome'), isDense: true, border: const OutlineInputBorder()))),
        ]),
        Wrap(spacing: 12, runSpacing: 12, children: [
          Pick<String>(tr('Sélection des variants : colonne (facultatif)', 'Variant selection: column (optional)'), subsetCol, [for (final n in d!.names) if (d.dictionary[n]!.type != VarType.numeric) (n, n)],
              (v) => setState(() {
                    subsetCol = v;
                    subsetLevel = null;
                  }), width: 300),
          if (subsetCol != null)
            Pick<String>(tr('Modalité retenue', 'Level kept'), subsetLevel, [for (final l in d.levels(subsetCol!)) (l, l)], (v) => setState(() => subsetLevel = v)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: reverse,
          onChanged: (v) => setState(() => reverse = v),
          title: Text(tr('Sens inverse : l\'issue comme exposition (MR bidirectionnelle)', 'Reverse direction: the outcome as exposure (bidirectional MR)')),
          subtitle: Text(tr('Utiliser alors des variants choisis pour l\'issue.', 'Then use variants selected for the outcome.')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: multivariable,
          onChanged: (v) => setState(() => multivariable = v),
          title: Text(tr('MR multivariée : ajouter d\'autres expositions', 'Multivariable MR: add other exposures')),
          subtitle: Text(tr('Effet direct de chaque exposition, à niveau égal des autres (pléiotropie mesurée).', 'Direct effect of each exposure, holding the others fixed (measured pleiotropy).')),
        ),
        if (multivariable)
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (var q = 0; q < extra.length; q++) ...[
              Pick<String>(tr('β exposition ${q + 2}', 'β exposure ${q + 2}'), extra[q].$1, numeric, (v) => setState(() => extra[q] = (v, extra[q].$2))),
              Pick<String>(tr('ES exposition ${q + 2}', 'SE exposure ${q + 2}'), extra[q].$2, numeric, (v) => setState(() => extra[q] = (extra[q].$1, v))),
            ],
          ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: logOdds,
          onChanged: (v) => setState(() => logOdds = v),
          title: Text(tr('βY en log-odds (issue binaire) : afficher aussi l\'OR', 'βY in log-odds (binary outcome): also show the OR')),
        ),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: bx == null || bxse == null || by == null || byse == null ? null : run,
            icon: const Icon(Icons.call_split),
            label: Text(tr('Estimer l\'effet causal', 'Estimate the causal effect')),
          ),
          SizedBox(width: 170, child: TextField(controller: nX, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('N étude exposition', 'N exposure study'), isDense: true, border: const OutlineInputBorder()))),
          SizedBox(width: 170, child: TextField(controller: nY, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('N étude issue', 'N outcome study'), isDense: true, border: const OutlineInputBorder()))),
          OutlinedButton.icon(
            onPressed: bx == null || bxse == null || by == null || byse == null ? null : runSteiger,
            icon: const Icon(Icons.swap_horiz),
            label: Text(tr('Tester le sens (Steiger)', 'Test the direction (Steiger)')),
          ),
        ]),
      ],
    ]);
  }
}
