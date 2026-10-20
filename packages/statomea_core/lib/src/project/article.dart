/// Article prérédigé (structure IMRaD) à partir du projet : méthodes reprises du protocole et du plan d'analyse,
/// Tableau 1 tiré des données, tableau des résultats principaux tiré du journal (estimation, IC, p), limites déduites
/// du plan d'étude et de la relecture ; tout ce qui demande l'auteur est marqué « à compléter ».
library;

import '../advisor/advisor.dart';
import '../data/dataset.dart' show VarType;
import '../descriptive/table1.dart';
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import '../version.dart';
import 'checklist_protocol.dart';
import 'crf.dart';
import 'flow.dart';
import 'project.dart';
import 'references.dart';
import 'review.dart';

class ArticleSection {
  final String title;
  final List<String> paragraphs;
  final List<ResultTable> tables;
  final bool sub; // sous-section
  const ArticleSection(this.title, this.paragraphs, {this.tables = const [], this.sub = false});
}

/// Minuscule initiale en milieu de phrase (« Femmes enceintes » → « femmes enceintes »), sauf sigle (« VIH »).
String _lc(String s) => s.length > 1 && s[1] == s[1].toLowerCase() ? s[0].toLowerCase() + s.substring(1) : s;

String _todo(String what) => tr('[À compléter : $what]', '[To complete: $what]');

String _first(String? s, [int max = 400]) {
  if (s == null || s.trim().isEmpty) return '';
  final m = RegExp(r"^.{20,}?[.;](?=\s|$)").firstMatch(s.trim());
  final t = (m?.group(0) ?? s).trim();
  return t.length > max ? '${t.substring(0, max - 1)}…' : t;
}

String _est(Estimate e) {
  final lv = (e.level * 100).round();
  final ci = e.lower == null || e.upper == null ? '' : tr(' (IC $lv % : ${fmt(e.lower!)} – ${fmt(e.upper!)})', ' ($lv% CI: ${fmt(e.lower!)} – ${fmt(e.upper!)})');
  return '${e.label} = ${fmt(e.value)}$ci';
}

/// Grille de publication adaptée au plan (CONSORT, STROBE, STARD, TRIPOD, PRISMA).
String reportingGuideline(ResearchQuestion q) => switch ((q.design, q.objective)) {
      (StudyDesign.rct, _) => 'CONSORT 2010',
      (StudyDesign.systematicReview, _) => 'PRISMA 2020',
      (_, StudyObjective.predictive) => 'TRIPOD+AI',
      (StudyDesign.diagnosticAccuracy, _) || (_, StudyObjective.diagnostic) => 'STARD 2015',
      _ => 'STROBE',
    };

/// Sections de l'article ; les citations « [@clé] » sont numérotées et la liste des références remplie.
List<ArticleSection> articleOutline(Project p) => _withReferences(p, _articleSections(p));

List<ArticleSection> _withReferences(Project p, List<ArticleSection> sections) {
  if (p.references.isEmpty) return sections;
  final numbers = referenceNumbers(p.references, sections.expand((s) => s.paragraphs));
  return [
    for (final s in sections)
      ArticleSection(s.title, s.title == tr('Références', 'References') ? referenceList(p.references, numbers) : [for (final l in s.paragraphs) formatCitations(l, numbers)],
          tables: s.tables, sub: s.sub),
  ];
}

List<ArticleSection> _articleSections(Project p) {
  final q = p.question;
  final prot = p.protocol;
  final design = q.design == StudyDesign.unknown ? _todo(tr('plan d\'étude', 'study design')) : designLabel(q.design);
  final planned = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
  final ds = p.dataset;
  final analysed = ds == null ? null : ds.rowCount - ds.excludedRows.length;
  final guideline = reportingGuideline(q);

  // Résultats du journal (hors description, effectif et puissance).
  final mains = <(String, Estimate?, String)>[];
  for (final e in p.journal) {
    final id = e.methodId;
    if (id.startsWith('describe') || id.startsWith('sample_size') || id.startsWith('power') || id == 'association_table') continue;
    final ests = [for (final x in (e.result['estimates'] as List? ?? const [])) Estimate.fromJson((x as Map).cast())];
    final interp = (e.result['interpretation'] as Map?)?['whatItMeans'] as String? ?? '';
    mains.add((e.methodName, ests.isEmpty ? null : ests.first, interp));
  }
  // Tableau 2 des associations brutes et ajustées (le dernier calculé), s'il existe.
  ResultTable? assoc;
  for (final e in p.journal.reversed) {
    if (e.methodId == 'association_table' && (e.result['tables'] as List?)?.isNotEmpty == true) {
      assoc = ResultTable.fromJson(((e.result['tables'] as List).first as Map).cast());
      break;
    }
  }
  final mainNo = assoc == null ? 2 : 3;
  final resultsTable = mains.isEmpty
      ? null
      : ResultTable(tr('Tableau $mainNo. Résultats principaux', 'Table $mainNo. Main results'), [tr('Analyse', 'Analysis'), tr('Estimation', 'Estimate'), tr('IC à 95 %', '95% CI'), 'p'], [
          for (final (name, e, _) in mains)
            [
              name,
              e == null ? '—' : '${e.label} = ${fmt(e.value)}',
              e == null || e.lower == null || e.upper == null ? '—' : '${fmt(e.lower!)} – ${fmt(e.upper!)}',
              e?.pValue == null ? '—' : fmtP(e!.pValue).replaceFirst(RegExp(r'^p [=<] ?'), e.pValue! < 0.001 ? '< ' : ''),
            ]
        ]);

  // Tableau 1 : selon l'exposition déclarée si elle a 2 à 6 modalités.
  ResultTable? t1;
  List<String> t1notes = const [];
  if (ds != null) {
    String? group = p.roles.validFor(ds).exposure;
    if (group != null && (ds.dictionary[group]?.type == VarType.numeric || ds.levels(group).length < 2 || ds.levels(group).length > 6)) group = null;
    try {
      final t = table1(ds, group: group);
      t1 = ResultTable(tr('Tableau 1. Caractéristiques des participants', 'Table 1. Participant characteristics'), t.header, t.cells);
      t1notes = t.notes;
    } on StatInputError {
      t1 = null;
    }
  }

  // Plan d'analyse : pour un protocole importé, sa rubrique d'analyse et les corrections appliquées (pas la proposition
  // rédigée par Statoméa à l'import) ; sinon le plan du chercheur ; sans les intitulés techniques.
  final marker = RegExp(r'(Correction Statoméa|Statoméa correction) — ').firstMatch(p.analysisPlan);
  var protocolPlan = (prot['analysis'] ?? '').replaceAll(RegExp(r'\s+'), ' ');
  // Les phrases corrigées (citées par chaque correction) sont remplacées par leur correction.
  for (final c in p.corrections) {
    final ev = c.evidence?.replaceAll(RegExp(r'\s+'), ' ').replaceAll('…', '').trim();
    if (ev != null && ev.length > 20) protocolPlan = protocolPlan.replaceAll(ev, '');
  }
  final planSource = prot.isNotEmpty && protocolPlan.trim().isNotEmpty
      ? [protocolPlan.trim(), if (marker != null) p.analysisPlan.substring(marker.start)].join('\n')
      : p.analysisPlan;
  final plan = planSource
      .replaceAll(RegExp(r'(Correction Statoméa|Statoméa correction) — [^\n]*\n'), '')
      .replaceAll(RegExp(r"^(Plan d'analyse du protocole|Protocol analysis plan) : ", multiLine: true), '')
      .replaceAll(RegExp(r' \((et non|not) [^)]*\)'), '')
      .split(RegExp(r'\n+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !RegExp(r"^(Proposition de Statoméa|Statoméa proposal) :$").hasMatch(l))
      .toList();
  final labs = protocolLabTests(p);
  final fields = crfFields(p);
  final review = reviewProject(p);
  final grid = prot.isEmpty ? null : protocolChecklist(p);

  // Diagramme de flux : phrase et figure (tableau d'étapes) si des effectifs ont été saisis.
  final flow = p.flow.isEmpty ? null : flowDiagram(p);
  final flowText = flow == null ? '' : flowSentence(flow);
  final flowFigure = flow == null
      ? null
      : ResultTable(tr('Figure 1. Diagramme de flux des participants (${flow.guideline})', 'Figure 1. Participant flow diagram (${flow.guideline})'),
          [tr('Étape', 'Stage'), tr('Exclusions, perdus de vue', 'Exclusions, losses')], [
          for (final st in flow.stages)
            [
              st.main.map((b) => b.text).join(' | '),
              st.side.whereType<FlowBox>().map((b) => [b.text, ...b.details].join(' ; ')).join(' | '),
            ]
        ]);

  final limits = <String>[
    if (q.design == StudyDesign.crossSectional) tr('Le plan transversal ne permet pas d\'établir la chronologie entre exposition et issue.', 'The cross-sectional design does not establish the temporal order of exposure and outcome.'),
    if (q.design == StudyDesign.cohort || q.design == StudyDesign.caseControl || q.design == StudyDesign.crossSectional)
      tr('Malgré l\'ajustement, une confusion résiduelle par des facteurs non mesurés reste possible.', 'Despite adjustment, residual confounding by unmeasured factors remains possible.'),
    if (q.design == StudyDesign.caseControl) tr('Un biais de mémorisation ou de sélection des témoins est possible.', 'Recall bias or control selection bias is possible.'),
    if (planned != null && analysed != null && analysed < 0.8 * planned)
      tr('L\'effectif analysé ($analysed) est inférieur à l\'effectif prévu ($planned) : la puissance est réduite.', 'The analysed sample ($analysed) is smaller than planned ($planned): power is reduced.'),
    if (review.findings.any((f) => f.id == 'unplanned_analysis' || f.id == 'subgroups'))
      tr('Certaines analyses n\'étaient pas prévues au protocole et sont exploratoires.', 'Some analyses were not planned in the protocol and are exploratory.'),
    if (q.objective == StudyObjective.predictive) tr('Le modèle n\'a pas encore été validé sur une population externe.', 'The model has not yet been validated in an external population.'),
    _todo(tr('autres limites (mesure, sélection, généralisation)', 'other limitations (measurement, selection, generalisability)')),
  ];
  final causalWarning = q.design == StudyDesign.rct
      ? ''
      : tr(' Dans une étude ${designLabel(q.design).toLowerCase()}, formuler les conclusions en termes d\'association.', ' In a ${designLabel(q.design).toLowerCase()}, phrase conclusions in terms of association.');

  return [
    ArticleSection(tr('Résumé', 'Abstract'), [
      '${tr('Contexte : ', 'Background: ')}${_todo(tr('une à deux phrases', 'one or two sentences'))}',
      '${tr('Objectif : ', 'Objective: ')}${q.text.isEmpty ? _todo(tr('objectif', 'objective')) : q.text}',
      '${tr('Méthodes : ', 'Methods: ')}$design${q.population.isEmpty ? '' : tr(' chez ${_lc(q.population)}', ' in ${_lc(q.population)}')}${analysed == null ? '' : tr(' ; $analysed participants', '; $analysed participants')}${mains.isEmpty ? '' : tr(' ; ${mains.first.$1}', '; ${mains.first.$1}')}.',
      '${tr('Résultats : ', 'Results: ')}${mains.isEmpty || mains.first.$2 == null ? _todo(tr('résultat principal avec IC à 95 %', 'main result with 95% CI')) : _est(mains.first.$2!)}.',
      '${tr('Conclusion : ', 'Conclusion: ')}${_todo(tr('conclusion prudente, limitée à ce que montrent les données', 'cautious conclusion, limited to what the data show'))}',
    ]),
    ArticleSection(tr('Introduction', 'Introduction'), [
      _todo(tr('contexte, état des connaissances, lacune que l\'étude comble', 'background, state of knowledge, gap the study fills')),
      if (q.text.isNotEmpty) tr('L\'objectif de cette étude était de répondre à la question suivante : ${q.text}', 'The aim of this study was to answer the following question: ${q.text}'),
    ]),
    ArticleSection(tr('Méthodes', 'Methods'), const []),
    ArticleSection(tr('Schéma et cadre de l\'étude', 'Study design and setting'), [
      tr('Il s\'agit d\'une $design.', 'This is a $design.'),
      if (_first(prot['period']).isNotEmpty) _first(prot['period']) else _todo(tr('lieu et période', 'setting and period')),
      tr('Le rapport suit les recommandations $guideline.', 'Reporting follows the $guideline guideline.'),
    ], sub: true),
    ArticleSection(tr('Participants', 'Participants'), [
      if (q.population.isNotEmpty) q.population else _todo(tr('population et critères d\'inclusion', 'population and inclusion criteria')),
      if (_first(prot['population'], 600).isNotEmpty && _first(prot['population'], 600) != q.population) _first(prot['population'], 600),
    ], sub: true),
    ArticleSection(tr('Variables et mesures', 'Variables and measurements'), [
      '${tr('Critère de jugement principal : ', 'Primary outcome: ')}${q.outcome.isEmpty ? _todo(tr('définition', 'definition')) : q.outcome}${q.horizon.isEmpty ? '' : ' (${q.horizon})'}.',
      if (q.exposure.isNotEmpty) '${tr('Exposition : ', 'Exposure: ')}${q.exposure}${q.comparator.isEmpty ? '' : tr(' ; comparateur : ${q.comparator}', '; comparator: ${q.comparator}')}.',
      if (fields.length > 3) '${tr('Variables recueillies : ', 'Variables collected: ')}${fields.skip(2).where((f) => !f.code.startsWith('critere_principal')).map((f) => f.label + (f.unit.isEmpty ? '' : ' (${f.unit})')).join(', ')}.',
      for (final l in labs)
        if (l.method != null) tr('${l.label} : ${l.method}.', '${l.label}: ${l.method}.'),
    ], sub: true),
    ArticleSection(tr('Taille de l\'échantillon', 'Sample size'), [
      if (_first(prot['sampleSize'], 600).isNotEmpty) _first(prot['sampleSize'], 600),
      if (planned != null) tr('L\'effectif prévu était de $planned sujets.', 'The planned sample size was $planned subjects.'),
      if (planned == null && _first(prot['sampleSize']).isEmpty) _todo(tr('justification du nombre de sujets', 'sample size justification')),
    ], sub: true),
    ArticleSection(tr('Analyse statistique', 'Statistical analysis'), [
      ...plan,
      if (plan.isEmpty) _todo(tr('méthodes statistiques', 'statistical methods')),
      tr('Les analyses ont été réalisées avec Statoméa ($engineName $engineVersion), dont chaque méthode est validée contre R.', 'Analyses were performed with Statoméa ($engineName $engineVersion), each method of which is validated against R.'),
    ], sub: true),
    ArticleSection(tr('Considérations éthiques', 'Ethical considerations'), [
      if (_first(prot['ethics'], 600).isNotEmpty) _first(prot['ethics'], 600) else _todo(tr('comité d\'éthique, numéro d\'avis, consentement', 'ethics committee, approval number, consent')),
    ], sub: true),
    ArticleSection(tr('Résultats', 'Results'), const []),
    ArticleSection(tr('Participants', 'Participants'), [
      if (flowText.isNotEmpty)
        '$flowText${planned == null ? '' : tr(' L\'effectif prévu était de $planned.', ' The planned sample size was $planned.')} ${tr('Le flux des participants est présenté dans la Figure 1.', 'Participant flow is shown in Figure 1.')}'
      else if (analysed == null)
        _todo(tr('nombre de sujets éligibles, inclus, analysés (diagramme de flux)', 'number of eligible, included, analysed subjects (flow diagram)'))
      else
        tr('$analysed participants ont été analysés${planned == null ? '' : ' (effectif prévu : $planned)'}. ${_todo('diagramme de flux : éligibles, inclus, exclus et motifs')}', '$analysed participants were analysed${planned == null ? '' : ' (planned: $planned)'}. ${_todo('flow diagram: eligible, included, excluded and reasons')}'),
      ...?flow?.warnings.map((w) => _todo(tr('vérifier les effectifs : $w', 'check the numbers: $w'))),
      if (t1 != null) tr('Leurs caractéristiques sont présentées dans le Tableau 1.', 'Their characteristics are shown in Table 1.'),
      ...t1notes,
    ], tables: [?flowFigure, ?t1], sub: true),
    ArticleSection(tr('Résultats principaux', 'Main results'), [
      if (mains.isEmpty) _todo(tr('résultat du critère principal (effet et IC à 95 %)', 'primary outcome result (effect and 95% CI)')),
      for (final (name, e, interp) in mains) '$name${e == null ? '' : '${tr(' : ', ': ')}${_est(e)}'}${interp.isEmpty ? '.' : '. $interp'}',
      if (p.resultsText.trim().isNotEmpty) p.resultsText.trim(),
    ], tables: [?assoc, ?resultsTable], sub: true),
    ArticleSection(tr('Discussion', 'Discussion'), [
      '${tr('Principaux résultats : ', 'Main findings: ')}${_todo(tr('résumé en deux phrases', 'two-sentence summary'))}',
      '${tr('Comparaison avec la littérature : ', 'Comparison with the literature: ')}${_todo(tr('études comparables et explications des différences', 'comparable studies and explanations of differences'))}',
      '${tr('Forces : ', 'Strengths: ')}${_todo(tr('plan, mesures standardisées, plan d\'analyse fixé à l\'avance', 'design, standardised measurements, analysis plan set in advance'))}',
      '${tr('Limites : ', 'Limitations: ')}${limits.join(' ')}',
    ]),
    ArticleSection(tr('Conclusion', 'Conclusion'), ['${_todo(tr('conclusion et implications pratiques', 'conclusion and practical implications'))}$causalWarning']),
    ArticleSection(tr('Références', 'References'), [_todo(tr('références (style de la revue visée)', 'references (target journal style)'))]),
    ArticleSection(tr('Liste de contrôle', 'Checklist'), [
      tr('Vérifier l\'article avec la liste $guideline${grid == null ? '' : ' ; protocole : grille ${grid.name}, ${grid.present} / ${grid.items.length} éléments'}.', 'Check the article against the $guideline checklist${grid == null ? '' : '; protocol: ${grid.name} checklist, ${grid.present} / ${grid.items.length} items'}.'),
    ]),
  ];
}
