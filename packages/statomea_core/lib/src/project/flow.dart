/// Diagramme de flux des participants (CONSORT pour un essai, STROBE sinon) : évalués pour l'éligibilité, exclus avec
/// leurs motifs, inclus (ou randomisés puis répartis par bras), perdus de vue avec motifs, analysés. Les effectifs sont
/// saisis par le chercheur ([Project.flow]) ; à défaut, les effectifs connus du projet sont proposés (lignes du fichier
/// de données, lignes exclues au contrôle des données). Les incohérences arithmétiques sont signalées.
library;

import '../i18n.dart';
import '../model/design.dart';
import 'project.dart';

class FlowBox {
  final String label;
  final int? n;
  final List<String> details; // motifs (« refus : 12 »)
  final bool side; // boîte latérale (exclusions, perdus de vue)
  const FlowBox(this.label, this.n, {this.details = const [], this.side = false});
  String get text => '$label${n == null ? '' : ' (n = $n)'}';
}

/// Une étape du diagramme : boîte principale, boîte latérale éventuelle ; pour un essai, une colonne par bras.
class FlowStage {
  final List<FlowBox> main; // une boîte (ou une par bras)
  final List<FlowBox?> side;
  const FlowStage(this.main, [this.side = const []]);
}

class FlowDiagram {
  final String guideline; // CONSORT 2010 / STROBE
  final List<FlowStage> stages;
  final List<String> warnings;
  final bool proposed; // effectifs proposés (non saisis)
  const FlowDiagram(this.guideline, this.stages, this.warnings, {this.proposed = false});
}

/// Motifs « libellé : n » (une ligne chacun) et leur total.
(List<String>, int) flowReasons(String? text) {
  final lines = <String>[];
  var total = 0;
  for (final l in (text ?? '').split(RegExp(r'[\n;]'))) {
    final t = l.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^(.*?)[\s:=–-]+(\d+)\s*$').firstMatch(t);
    if (m != null) {
      total += int.parse(m.group(2)!);
      lines.add('${m.group(1)!.trim()}${tr(' : ', ': ')}${m.group(2)}');
    } else {
      lines.add(t);
    }
  }
  return (lines, total);
}

/// Bras de l'essai : noms saisis, sinon les modalités de l'exposition déclarée (si deux), sinon « Bras A / Bras B ».
List<String> flowArms(Project p) {
  final a = p.flow['arm1_name'], b = p.flow['arm2_name'];
  if ((a ?? '').isNotEmpty && (b ?? '').isNotEmpty) return [a!, b!];
  final ex = p.roles.validFor(p.dataset).exposure;
  if (ex != null && p.dataset != null) {
    final l = p.dataset!.levels(ex);
    if (l.length == 2) return l;
  }
  return [tr('Bras A', 'Arm A'), tr('Bras B', 'Arm B')];
}

FlowDiagram flowDiagram(Project p) {
  final f = p.flow;
  int? n(String k) => int.tryParse((f[k] ?? '').trim());
  final ds = p.dataset;
  final dataRows = ds?.rowCount;
  final dataExcluded = ds?.excludedRows.length ?? 0;
  final warnings = <String>[];
  final rct = p.question.design == StudyDesign.rct;
  final proposed = f.isEmpty;
  final (exReasons, exTotal) = flowReasons(f['excluded_reasons']);
  final assessed = n('assessed');
  final included = n('included') ?? dataRows;
  if (assessed != null && included != null && exReasons.isNotEmpty && assessed - exTotal != included) {
    warnings.add(tr('Évalués ($assessed) − exclus ($exTotal) = ${assessed - exTotal}, différent des inclus ($included).', 'Assessed ($assessed) − excluded ($exTotal) = ${assessed - exTotal}, different from included ($included).'));
  }
  final stages = <FlowStage>[
    FlowStage([FlowBox(tr('Évalués pour l\'éligibilité', 'Assessed for eligibility'), assessed)],
        [FlowBox(tr('Exclus', 'Excluded'), exReasons.isEmpty ? (assessed != null && included != null ? assessed - included : null) : exTotal, details: exReasons, side: true)]),
  ];
  if (rct) {
    final arms = flowArms(p);
    stages.add(FlowStage([FlowBox(tr('Randomisés', 'Randomised'), included)]));
    final alloc = [n('arm1_allocated'), n('arm2_allocated')];
    if (included != null && alloc.every((x) => x != null) && alloc[0]! + alloc[1]! != included) {
      warnings.add(tr('Répartis (${alloc[0]! + alloc[1]!}) ≠ randomisés ($included).', 'Allocated (${alloc[0]! + alloc[1]!}) ≠ randomised ($included).'));
    }
    stages.add(FlowStage([for (var a = 0; a < 2; a++) FlowBox(tr('Alloués à ${arms[a]}', 'Allocated to ${arms[a]}'), alloc[a])]));
    final lost = <FlowBox?>[];
    final analysed = <FlowBox>[];
    for (var a = 0; a < 2; a++) {
      final (lr, lt) = flowReasons(f['arm${a + 1}_lost_reasons']);
      final lostN = n('arm${a + 1}_lost') ?? (lr.isEmpty ? null : lt);
      lost.add(FlowBox(tr('Perdus de vue / arrêts', 'Lost to follow-up / discontinued'), lostN, details: lr, side: true));
      final an = n('arm${a + 1}_analysed');
      analysed.add(FlowBox(tr('Analysés (${arms[a]})', 'Analysed (${arms[a]})'), an));
      if (alloc[a] != null && lostN != null && an != null && alloc[a]! - lostN != an) {
        warnings.add(tr('${arms[a]} : alloués (${alloc[a]}) − perdus ($lostN) = ${alloc[a]! - lostN}, différent des analysés ($an) ; préciser l\'analyse (intention de traiter ?).',
            '${arms[a]}: allocated (${alloc[a]}) − lost ($lostN) = ${alloc[a]! - lostN}, different from analysed ($an); specify the analysis (intention to treat?).'));
      }
    }
    stages.add(FlowStage([for (final b in lost) b!]));
    stages.add(FlowStage(analysed));
  } else {
    stages.add(FlowStage([FlowBox(tr('Inclus', 'Included'), included)]));
    final (lr, lt) = flowReasons(f['lost_reasons']);
    final lostN = n('lost') ?? (lr.isNotEmpty ? lt : (dataExcluded > 0 && f['analysed'] == null ? dataExcluded : null));
    final details = lr.isNotEmpty ? lr : (dataExcluded > 0 && n('lost') == null ? [tr('exclus au contrôle des données : $dataExcluded', 'excluded at data checking: $dataExcluded')] : const <String>[]);
    final analysed = n('analysed') ?? (dataRows == null ? null : dataRows - dataExcluded);
    if (included != null && lostN != null && analysed != null && included - lostN != analysed) {
      warnings.add(tr('Inclus ($included) − non analysés ($lostN) = ${included - lostN}, différent des analysés ($analysed).', 'Included ($included) − not analysed ($lostN) = ${included - lostN}, different from analysed ($analysed).'));
    }
    stages.add(FlowStage([FlowBox(tr('Analysés', 'Analysed'), analysed)],
        [FlowBox(tr('Non analysés (perdus de vue, données manquantes)', 'Not analysed (lost to follow-up, missing data)'), lostN, details: details, side: true)]));
  }
  return FlowDiagram(rct ? 'CONSORT 2010' : 'STROBE', stages, warnings, proposed: proposed);
}

/// Phrase de résultats tirée du diagramme (« Sur 812 personnes évaluées, 640 ont été incluses… »).
String flowSentence(FlowDiagram d) {
  int? first(String key) {
    for (final s in d.stages) {
      for (final b in s.main) {
        if (b.label.startsWith(key) && b.n != null) return b.n;
      }
    }
    return null;
  }

  final assessed = d.stages.first.main.first.n;
  final excluded = d.stages.first.side.isEmpty ? null : d.stages.first.side.first?.n;
  final reasons = d.stages.first.side.isEmpty ? const <String>[] : d.stages.first.side.first!.details;
  final included = first(tr('Inclus', 'Included')) ?? first(tr('Randomisés', 'Randomised'));
  final analysed = d.stages.last.main.map((b) => b.n).whereType<int>().fold(0, (a, b) => a + b);
  final parts = <String>[
    if (assessed != null) tr('Sur $assessed personnes évaluées pour l\'éligibilité', 'Of $assessed people assessed for eligibility'),
    if (excluded != null) tr('$excluded ont été exclues${reasons.isEmpty ? '' : ' (${reasons.join(' ; ')})'}', '$excluded were excluded${reasons.isEmpty ? '' : ' (${reasons.join('; ')})'}'),
    if (included != null) tr('$included ont été incluses', '$included were included'),
    if (analysed > 0) tr('$analysed ont été analysées', '$analysed were analysed'),
  ];
  if (parts.isEmpty) return '';
  return '${parts.join(tr(', ', ', '))}.';
}
