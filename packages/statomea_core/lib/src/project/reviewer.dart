/// Réponse aux relecteurs : les commentaires (collés ou importés) sont découpés un par un ; pour chacun, Statoméa
/// reconnaît le thème (effectif, confusion, données manquantes, IC, multiplicité, langage causal, choix des tests,
/// flux des participants, généralisation, langue) et propose une réponse fondée sur le projet (effectif prévu et
/// atteint, Tableau 2, journal des analyses, diagramme de flux). Le chercheur relit et complète chaque réponse.
library;

import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'flow.dart';
import 'project.dart';

class ReviewerItem {
  final String reviewer; // « Relecteur 1 » (si indiqué)
  final String comment;
  final String topic; // thème reconnu (vide sinon)
  String response;
  String change; // modification apportée au manuscrit
  ReviewerItem(this.reviewer, this.comment, this.topic, this.response, this.change);

  Map<String, Object?> toJson() => {'reviewer': reviewer, 'comment': comment, 'topic': topic, 'response': response, 'change': change};
  factory ReviewerItem.fromJson(Map<String, Object?> j) =>
      ReviewerItem((j['reviewer'] as String?) ?? '', j['comment'] as String, (j['topic'] as String?) ?? '', (j['response'] as String?) ?? '', (j['change'] as String?) ?? '');
}

String _n(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'");
String _todo(String what) => tr('[À compléter : $what]', '[To complete: $what]');

final _reviewerHead = RegExp(r"^\s*(relecteur|reviewer|rapporteur|referee|evaluateur|examinateur)\s*(n[°o]\s*)?#?\s*(\d+|[a-c])\b[^\n]{0,40}$", caseSensitive: false);
final _itemStart = RegExp(r"^\s*((commentaire|comment|remarque|point|question|issue|major|minor|mineur|majeur)s?\s*(n[°o]\s*)?\d*\s*[.:)\-–]|\d{1,2}\s*[.)\-–]\s+|[a-h][.)]\s+|[-•*▪●]\s+)", caseSensitive: false);

/// Découpe le texte des relecteurs en commentaires (numérotés, à puces ou par paragraphes), avec le relecteur.
List<(String, String)> splitReviewerComments(String text) {
  final out = <(String, String)>[];
  var reviewer = '';
  final buf = <String>[];
  void flush() {
    final t = buf.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length >= 15) out.add((reviewer, t));
    buf.clear();
  }

  final lines = text.replaceAll('\r', '').split('\n');
  final numbered = lines.where((l) => _itemStart.hasMatch(l)).length >= 2;
  for (final line in lines) {
    final l = line.trim();
    if (l.isEmpty) {
      if (!numbered) flush();
      continue;
    }
    if (_reviewerHead.hasMatch(l)) {
      flush();
      reviewer = l.replaceAll(RegExp(r'[:\-–]+\s*$'), '').trim();
      continue;
    }
    if (numbered && _itemStart.hasMatch(l)) flush();
    buf.add(numbered ? l.replaceFirst(_itemStart, '').trim() : l);
  }
  flush();
  return out;
}

typedef _Topic = (String key, String re);
const List<_Topic> _topics = [
  ('sample', r"effectif|taille (de l'|d')?echantillon|nombre de sujets|puissance|sample size|power|underpowered|number of (patients|participants)"),
  ('confounding', r"confusion|confond|ajust|multivari|confound|adjust"),
  ('missing', r"manquant|missing|imputation|incomplet"),
  ('ci', r"intervalles? de confiance|confidence intervals?|\bic\b|\bci\b|taille d'effet|effect size|precision"),
  ('multiplicity', r"multiplicit|bonferroni|comparaisons multiples|tests multiples|multiple (testing|comparisons)"),
  ('causal', r"causal|causalit|lien de cause|effet de|impact|cause[- ]effect"),
  ('tests', r"normalit|test (de |du |statistique)|non[- ]parametrique|parametri|normality|statistical test|student|khi|chi"),
  ('flow', r"exclu|perdus? de vue|flow|diagramme|recrutement|selection des|lost to follow|recruit"),
  ('general', r"generalis|validite externe|external validity|representativ|extrapol"),
  ('language', r"anglais|english|langue|grammai|orthograph|typo|language|wording|redaction"),
];

/// Proposition de réponse et de modification pour un commentaire.
(String topic, String response, String change) proposeReviewerReply(Project p, String comment) {
  final c = _n(comment);
  String topic = '';
  for (final (k, re) in _topics) {
    if (RegExp(re).hasMatch(c)) {
      topic = k;
      break;
    }
  }
  final thanks = tr('Nous remercions le relecteur pour cette remarque. ', 'We thank the reviewer for this comment. ');
  final planned = int.tryParse(p.inferred['plannedSampleSize'] ?? '');
  final ds = p.dataset;
  final analysed = ds == null ? null : ds.rowCount - ds.excludedRows.length;
  final ests = <(String, Estimate)>[];
  for (final e in p.journal) {
    if (e.methodId.startsWith('describe') || e.methodId.startsWith('sample_size') || e.methodId.startsWith('power')) continue;
    final list = (e.result['estimates'] as List? ?? const []);
    if (list.isNotEmpty) ests.add((e.methodName, Estimate.fromJson((list.first as Map).cast())));
  }
  String est(Estimate e) => e.lower == null || e.upper == null
      ? '${e.label} = ${fmt(e.value)}'
      : tr('${e.label} = ${fmt(e.value)} (IC ${(e.level * 100).round()} % : ${fmt(e.lower!)} – ${fmt(e.upper!)})', '${e.label} = ${fmt(e.value)} (${(e.level * 100).round()}% CI: ${fmt(e.lower!)} – ${fmt(e.upper!)})');
  final where = _todo(tr('section, page et lignes modifiées', 'section, page and lines changed'));
  switch (topic) {
    case 'sample':
      final ss = (p.protocol['sampleSize'] ?? '').trim();
      return (
        topic,
        '$thanks${ss.isNotEmpty ? tr('Le nombre de sujets a été calculé a priori : ${ss.length > 300 ? '${ss.substring(0, 299)}…' : ss} ', 'The sample size was calculated a priori: ${ss.length > 300 ? '${ss.substring(0, 299)}…' : ss} ') : (planned == null ? _todo(tr('justification du nombre de sujets (hypothèses, α, puissance)', 'sample size justification (assumptions, α, power)')) : tr('L\'effectif prévu était de $planned sujets. ', 'The planned sample size was $planned subjects. '))}'
            '${analysed == null ? '' : tr('$analysed participants ont été analysés${planned == null ? '' : ' (${(100 * analysed / planned).round()} % de l\'effectif prévu)'}. ', '$analysed participants were analysed${planned == null ? '' : ' (${(100 * analysed / planned).round()}% of the planned size)'}. ')}'
            '${planned != null && analysed != null && analysed < 0.8 * planned ? tr('Nous avons ajouté cette limite à la discussion et interprétons les résultats à partir des intervalles de confiance plutôt que des valeurs de p.', 'We have added this limitation to the discussion and interpret the results through confidence intervals rather than p-values.') : ''}',
        tr('Méthodes, « Taille de l\'échantillon » : justification détaillée. $where', 'Methods, "Sample size": detailed justification. $where'),
      );
    case 'confounding':
      String? adj;
      for (final e in p.journal.reversed) {
        if (e.methodId == 'association_table') {
          final f = (e.result['inputs'] as Map?)?['formula'] as Map?;
          final terms = [for (final t in (f?['terms'] as List? ?? const [])) (t as Map)['variable'] as String];
          adj = terms.join(', ');
          break;
        }
      }
      return (
        topic,
        adj == null
            ? '$thanks${tr('Nous avons ajouté une analyse multivariable ajustée sur les facteurs de confusion identifiés a priori (graphe causal) ; les associations brutes et ajustées sont présentées dans le Tableau 2. ', 'We have added a multivariable analysis adjusted for confounders identified a priori (causal graph); crude and adjusted associations are shown in Table 2. ')}${_todo(tr('facteurs d\'ajustement et résultat ajusté', 'adjustment factors and adjusted result'))}'
            : '$thanks${tr('Les associations ont été ajustées sur les variables suivantes : $adj ; les estimations brutes et ajustées sont présentées dans le Tableau 2. Seul l\'effet de l\'exposition principale est interprété, pour éviter le « sophisme du Tableau 2 ».', 'Associations were adjusted for the following variables: $adj; crude and adjusted estimates are shown in Table 2. Only the main exposure effect is interpreted, to avoid the "Table 2 fallacy".')}',
        tr('Méthodes (analyse statistique), Résultats (Tableau 2). $where', 'Methods (statistical analysis), Results (Table 2). $where'),
      );
    case 'missing':
      String desc = '';
      if (ds != null) {
        final miss = <String>[];
        for (final name in ds.names) {
          final k = ds.text(name).where((v) => v == null).length;
          if (k > 0) miss.add('$name${tr(' : ', ': ')}$k (${fmtPct(k / ds.rowCount)})');
        }
        desc = miss.isEmpty ? tr('Aucune donnée manquante dans le fichier analysé. ', 'No missing data in the analysed file. ') : tr('Données manquantes par variable : ${miss.take(8).join(' ; ')}. ', 'Missing data per variable: ${miss.take(8).join('; ')}. ');
      }
      final imputed = p.journal.any((e) => e.methodId == 'multiple_imputation' || (e.result['methodName'] as String? ?? '').toLowerCase().contains('imput'));
      return (
        topic,
        '$thanks$desc${imputed ? tr('Une imputation multiple a été réalisée ; l\'analyse des cas complets est présentée en sensibilité.', 'Multiple imputation was performed; the complete-case analysis is presented as a sensitivity analysis.') : tr('Nous avons ajouté la description des données manquantes et une analyse de sensibilité (imputation multiple si plus de 5 % de données manquantes). ', 'We have added a description of missing data and a sensitivity analysis (multiple imputation if more than 5% missing). ') + _todo(tr('résultat de l\'analyse de sensibilité', 'sensitivity analysis result'))}',
        tr('Méthodes et Résultats (données manquantes). $where', 'Methods and Results (missing data). $where'),
      );
    case 'ci':
      return (
        topic,
        '$thanks${ests.isEmpty ? tr('Chaque estimation est désormais présentée avec son intervalle de confiance à 95 %. ', 'Each estimate is now presented with its 95% confidence interval. ') + _todo(tr('estimations', 'estimates')) : tr('Les estimations sont désormais présentées avec leur intervalle de confiance à 95 % : ${ests.take(4).map((x) => est(x.$2)).join(' ; ')}.', 'Estimates are now presented with their 95% confidence intervals: ${ests.take(4).map((x) => est(x.$2)).join('; ')}.')}',
        tr('Résultats et résumé. $where', 'Results and abstract. $where'),
      );
    case 'multiplicity':
      return (
        topic,
        '$thanks${tr('Le critère de jugement principal${p.question.outcome.isEmpty ? '' : ' (${p.question.outcome})'} fait l\'objet de l\'analyse confirmatoire au seuil de 5 % ; les analyses secondaires sont désormais présentées comme exploratoires, avec ajustement des valeurs de p par la méthode de Holm.', 'The primary outcome${p.question.outcome.isEmpty ? '' : ' (${p.question.outcome})'} is the confirmatory analysis at the 5% level; secondary analyses are now presented as exploratory, with p-values adjusted by the Holm method.')}',
        tr('Méthodes (analyse statistique), Résultats. $where', 'Methods (statistical analysis), Results. $where'),
      );
    case 'causal':
      final d = p.question.design;
      return (
        topic,
        d == StudyDesign.rct
            ? '$thanks${tr('S\'agissant d\'un essai randomisé, l\'effet de l\'intervention peut être interprété causalement pour le critère principal ; nous avons précisé que les analyses secondaires restent exploratoires.', 'As this is a randomised trial, the intervention effect may be interpreted causally for the primary outcome; we have specified that secondary analyses remain exploratory.')}'
            : '$thanks${tr('Nous avons reformulé les conclusions en termes d\'association, le plan ${d == StudyDesign.unknown ? 'observationnel' : designLabel(d).toLowerCase()} ne permettant pas d\'établir un lien de causalité ; la confusion résiduelle est mentionnée dans les limites.', 'We have rephrased the conclusions in terms of association, as the ${d == StudyDesign.unknown ? 'observational' : designLabel(d).toLowerCase()} design does not establish causation; residual confounding is mentioned in the limitations.')}',
        tr('Résumé, Discussion et Conclusion. $where', 'Abstract, Discussion and Conclusion. $where'),
      );
    case 'tests':
      return (
        topic,
        '$thanks${tr('Les variables quantitatives ont été résumées par moyenne ± écart-type lorsque leur distribution était à peu près symétrique (|asymétrie| ≤ 1), sinon par médiane [Q1 – Q3] ; les comparaisons utilisent en conséquence le test de Welch ou l\'ANOVA, sinon Mann-Whitney ou Kruskal-Wallis ; les variables qualitatives le test du χ² ou le test exact de Fisher (effectifs attendus < 5). Toutes les méthodes sont validées contre R.', 'Quantitative variables were summarised as mean ± SD when their distribution was approximately symmetric (|skewness| ≤ 1), otherwise as median [Q1 – Q3]; comparisons accordingly used Welch\'s test or ANOVA, otherwise Mann-Whitney or Kruskal-Wallis; categorical variables used the χ² test or Fisher\'s exact test (expected counts < 5). All methods are validated against R.')}',
        tr('Méthodes (analyse statistique). $where', 'Methods (statistical analysis). $where'),
      );
    case 'flow':
      final f = p.flow.isEmpty ? '' : flowSentence(flowDiagram(p));
      return (
        topic,
        '$thanks${f.isEmpty ? tr('Nous avons ajouté un diagramme de flux des participants (éligibles, exclus et motifs, inclus, analysés). ', 'We have added a participant flow diagram (eligible, excluded with reasons, included, analysed). ') + _todo(tr('effectifs', 'numbers')) : tr('$f Le diagramme de flux est présenté dans la Figure 1.', '$f The flow diagram is shown in Figure 1.')}',
        tr('Résultats (Figure 1). $where', 'Results (Figure 1). $where'),
      );
    case 'general':
      return (
        topic,
        '$thanks${tr('Nous avons précisé dans la discussion les conditions de transposition des résultats (population, lieu, période) et ajouté cette limite. ', 'We have specified in the discussion the conditions for transposing the results (population, setting, period) and added this limitation. ')}${_todo(tr('population à laquelle les résultats s\'appliquent', 'population to which the results apply'))}',
        tr('Discussion (limites). $where', 'Discussion (limitations). $where'),
      );
    case 'language':
      return (
        topic,
        '$thanks${tr('Le manuscrit a été entièrement relu ${_todo('par un locuteur natif ou un service de relecture')}.', 'The manuscript has been fully revised ${_todo('by a native speaker or an editing service')}.')}',
        tr('Ensemble du manuscrit.', 'Whole manuscript.'),
      );
    default:
      return ('', '$thanks${_todo(tr('réponse', 'response'))}', where);
  }
}

/// Analyse le texte des relecteurs et propose une réponse pour chaque commentaire.
List<ReviewerItem> analyseReviewerComments(Project p, String text) => [
      for (final (reviewer, comment) in splitReviewerComments(text))
        () {
          final (topic, response, change) = proposeReviewerReply(p, comment);
          return ReviewerItem(reviewer, comment, topic, response, change);
        }(),
    ];

String reviewerTopicLabel(String t) => switch (t) {
      'sample' => tr('effectif', 'sample size'),
      'confounding' => tr('confusion, ajustement', 'confounding, adjustment'),
      'missing' => tr('données manquantes', 'missing data'),
      'ci' => tr('intervalles de confiance', 'confidence intervals'),
      'multiplicity' => tr('multiplicité', 'multiplicity'),
      'causal' => tr('langage causal', 'causal language'),
      'tests' => tr('choix des tests', 'choice of tests'),
      'flow' => tr('flux des participants', 'participant flow'),
      'general' => tr('généralisation', 'generalisability'),
      'language' => tr('langue', 'language'),
      _ => tr('à rédiger', 'to write'),
    };
