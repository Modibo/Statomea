/// Chronogramme et budget prévisionnels tirés du projet : durée de l'étude, effectif, rythme de recrutement, horizon de
/// suivi et examens de la fiche de recueil. Les durées et quantités sont proposées ; les coûts unitaires et la devise
/// sont saisis par le chercheur ([Project.planning]) ; les imprévus valent 10 % du sous-total.
library;

import 'dart:math' as math;

import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import 'crf.dart';
import 'project.dart';
import 'review.dart' show protocolCentres, protocolRecruitmentPerMonth, protocolStudyMonths;

class PlanningPhase {
  final String key, label;
  final int start, end; // mois, de 1 à end inclus
  const PlanningPhase(this.key, this.label, this.start, this.end);
  int get months => end - start + 1;
}

class BudgetLine {
  final String key, label, unitLabel;
  final double quantity;
  final double? unitCost;
  const BudgetLine(this.key, this.label, this.quantity, this.unitLabel, this.unitCost);
  double? get total => unitCost == null ? null : quantity * unitCost!;
}

class StudyPlanning {
  final List<PlanningPhase> phases;
  final List<BudgetLine> lines;
  final String currency;
  final List<String> assumptions; // hypothèses retenues (à vérifier)
  const StudyPlanning(this.phases, this.lines, this.currency, this.assumptions);
  int get totalMonths => phases.map((p) => p.end).fold(0, math.max);
  double get subtotal => lines.map((l) => l.total ?? 0).fold(0.0, (a, b) => a + b);
  double get contingency => subtotal * 0.10;
  double get total => subtotal + contingency;
  bool get complete => lines.every((l) => l.unitCost != null);
}

String _n(String s) => foldAccents(s.toLowerCase());

int? _months(String horizon) {
  final m = RegExp(r"(\d+)\s*(jours?|semaines?|mois|ans?|annees?|days?|weeks?|months?|years?)").firstMatch(_n(horizon));
  if (m == null) return null;
  final v = int.parse(m.group(1)!);
  final u = m.group(2)!;
  if (u.startsWith('jour') || u.startsWith('day')) return (v / 30.4).ceil();
  if (u.startsWith('semaine') || u.startsWith('week')) return (v / 4.35).ceil();
  if (u.startsWith('mois') || u.startsWith('month')) return v;
  return v * 12;
}

final _lab = RegExp(r"glycemie|glucose|hba1c|hemoglobine|creatinine|uree|sodium|potassium|chlor|calcium|bicarbonate|hco3|cholesterol|triglycer|\binr\b|^inr|tca|cephaline|fibrinog|plaquet|leucocyt|lactate|\bph\b|^ph|sao2|pco2|po2|^na$|^k$|^cl$|^ica");

/// Chronogramme et budget du projet.
StudyPlanning studyPlanning(Project p) {
  final cfg = p.planning;
  int? cfgInt(String k) => int.tryParse(cfg[k] ?? '');
  double? cfgNum(String k) => double.tryParse((cfg[k] ?? '').replaceAll(' ', '').replaceAll(',', '.'));
  final assumptions = <String>[];
  final n = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
  final rate = protocolRecruitmentPerMonth(p);
  final studyMonths = protocolStudyMonths(p);
  final horizon = _months(p.question.horizon) ?? 0;
  final centres = protocolCentres(p) ?? 1;

  // Durées (mois) : préparation, inclusions, suivi, saisie, analyse, rédaction.
  final prep = cfgInt('m_prep') ?? 2;
  final analysis = cfgInt('m_analysis') ?? 2, writing = cfgInt('m_writing') ?? 2;
  int recruit;
  if (cfgInt('m_recruit') != null) {
    recruit = cfgInt('m_recruit')!;
  } else if (n != null && rate != null && rate > 0) {
    recruit = (n / rate).ceil();
    assumptions.add(tr('Inclusions : $n sujets au rythme de ${rate.toStringAsFixed(1)} par mois.', 'Enrolment: $n subjects at ${rate.toStringAsFixed(1)} per month.'));
  } else if (studyMonths != null) {
    recruit = math.max(1, studyMonths - prep - horizon - 1 - analysis - writing);
    assumptions.add(tr('Inclusions : durée de l\'étude ($studyMonths mois) moins préparation, suivi, gel de la base, analyse et rédaction.', 'Enrolment: study duration ($studyMonths months) minus preparation, follow-up, database lock, analysis and writing.'));
  } else {
    recruit = 6;
    assumptions.add(tr('Inclusions : 6 mois par défaut (ni durée ni rythme dans le protocole) — à ajuster.', 'Enrolment: 6 months by default (no duration or rate in the protocol) — to adjust.'));
  }
  recruit = math.max(1, recruit);
  final follow = cfgInt('m_follow') ?? horizon;
  if (follow > 0 && cfgInt('m_follow') == null) assumptions.add(tr('Suivi du dernier inclus : $follow mois (horizon du critère principal).', 'Follow-up of the last enrolled: $follow months (primary outcome horizon).'));
  var m = 1;
  final phases = <PlanningPhase>[];
  PlanningPhase phase(String key, String label, int len, {int? start}) {
    final s = start ?? m;
    final ph = PlanningPhase(key, label, s, s + len - 1);
    phases.add(ph);
    m = math.max(m, ph.end + 1);
    return ph;
  }

  phase('prep', tr('Préparation : avis éthique, autorisations, formation, achats', 'Preparation: ethics approval, authorisations, training, purchases'), prep);
  final inc = phase('recruit', tr('Inclusions et recueil des données', 'Enrolment and data collection'), recruit);
  if (follow > 0) phase('follow', tr('Suivi jusqu\'au critère principal', 'Follow-up to the primary outcome'), follow, start: inc.end + 1);
  final dataEnd = math.max(inc.end, follow > 0 ? inc.end + follow : inc.end) + 1;
  phases.add(PlanningPhase('entry', tr('Saisie, contrôle et gel de la base', 'Data entry, checking and database lock'), inc.start, dataEnd));
  m = dataEnd + 1;
  phase('analysis', tr('Analyse statistique', 'Statistical analysis'), analysis);
  phase('writing', tr('Rédaction, diffusion et publication', 'Writing, dissemination and publication'), writing);

  // Budget : quantités tirées de l'effectif, de la fiche et du chronogramme.
  final nn = cfgNum('q_n') ?? n?.toDouble() ?? 0;
  if (n == null && cfgNum('q_n') == null) assumptions.add(tr('Effectif inconnu : renseigner le nombre de sujets.', 'Sample size unknown: enter the number of subjects.'));
  final fields = crfFields(p);
  final labs = fields.where((f) => _lab.hasMatch(_n('${f.code} ${f.label}'))).length;
  final pages = math.max(1, (fields.length / 20).ceil());
  final staffMonths = recruit * centres;
  if (centres > 1) assumptions.add(tr('Enquêteurs : un par centre ($centres centres) pendant les inclusions.', 'Investigators: one per centre ($centres centres) during enrolment.'));
  BudgetLine line(String key, String label, double q, String unit) => BudgetLine(key, label, cfgNum('q_$key') ?? q, unit, cfgNum('u_$key'));
  final lines = [
    line('ethics', tr('Avis du comité d\'éthique (frais de dossier)', 'Ethics committee review (fees)'), 1, tr('dossier', 'application')),
    line('crf', tr('Fiches de recueil imprimées', 'Printed case report forms'), nn * pages, tr('page', 'page')),
    if (labs > 0) line('lab', tr('Examens biologiques ($labs par participant)', 'Laboratory tests ($labs per participant)'), nn * labs, tr('examen', 'test')),
    line('participants', tr('Transport ou compensation des participants', 'Participant transport or compensation'), nn, tr('participant', 'participant')),
    line('staff', tr('Enquêteurs (inclusions et recueil)', 'Investigators (enrolment and data collection)'), staffMonths.toDouble(), tr('mois-personne', 'person-month')),
    line('entry', tr('Saisie et contrôle des données', 'Data entry and checking'), nn, tr('fiche', 'form')),
    line('dissemination', tr('Diffusion (frais de publication, congrès)', 'Dissemination (publication fees, conference)'), 1, tr('forfait', 'lump sum')),
  ];
  return StudyPlanning(phases, lines, (cfg['currency'] ?? '').isEmpty ? 'FCFA' : cfg['currency']!, assumptions);
}

/// Montant arrondi avec séparateur de milliers (espace fine).
String formatMoney(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

/// Paragraphes de la rubrique « Calendrier, budget et diffusion » du protocole prérédigé.
List<String> planningParagraphs(Project p, String Function(String) todo) {
  final pl = studyPlanning(p);
  String q(double v) => v == v.roundToDouble() ? formatMoney(v) : v.toStringAsFixed(1);
  return [
    tr('Calendrier prévisionnel (${pl.totalMonths} mois) :', 'Provisional timeline (${pl.totalMonths} months):'),
    for (final ph in pl.phases) tr('— mois ${ph.start} à ${ph.end} : ${ph.label}', '— months ${ph.start} to ${ph.end}: ${ph.label}'),
    tr('Budget prévisionnel (${pl.currency}) :', 'Provisional budget (${pl.currency}):'),
    for (final l in pl.lines)
      '— ${l.label}${tr(' : ', ': ')}${q(l.quantity)} ${l.unitLabel}${l.quantity > 1 ? 's' : ''} × ${l.unitCost == null ? todo(tr('coût unitaire', 'unit cost')) : '${formatMoney(l.unitCost!)} ${pl.currency}'}${l.total == null ? '' : ' = ${formatMoney(l.total!)} ${pl.currency}'}',
    if (pl.subtotal > 0)
      tr('Sous-total ${formatMoney(pl.subtotal)} ${pl.currency} ; imprévus (10 %) ${formatMoney(pl.contingency)} ; total ${formatMoney(pl.total)} ${pl.currency}${pl.complete ? '' : ' (lignes sans coût non comptées)'}.',
          'Subtotal ${formatMoney(pl.subtotal)} ${pl.currency}; contingency (10%) ${formatMoney(pl.contingency)}; total ${formatMoney(pl.total)} ${pl.currency}${pl.complete ? '' : ' (lines without cost not counted)'}.'),
    if (pl.assumptions.isNotEmpty) '${tr('Hypothèses : ', 'Assumptions: ')}${pl.assumptions.join(' ')}',
    tr('Diffusion : ${todo('revue visée, communications, restitution aux participants et aux autorités sanitaires')}', 'Dissemination: ${todo('target journal, presentations, feedback to participants and health authorities')}'),
  ];
}
