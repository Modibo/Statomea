/// Audit contradictoire final : confronte le plan d'étude, le journal des
/// analyses réellement effectuées et le texte de résultats proposé.
///
/// Deux niveaux de fiabilité, explicités dans chaque constat :
///  - contrôles STRUCTURÉS (plan × méthodes × résultats) : fiables ;
///  - contrôles LEXICAUX du texte : heuristiques, susceptibles de faux
///    positifs et de faux négatifs ; ils montrent le passage déclencheur.
/// Quand l'information manque, l'audit le dit (« information insuffisante »)
/// au lieu de supposer une erreur.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../advisor/advisor.dart';
import '../model/design.dart';
import '../model/result.dart';

enum AuditFamily {
  methodDesign,
  orAsRr,
  agreementVsCi,
  pValueMisread,
  causalLanguage,
  predictionOverclaim,
  announcedNotDone,
  overPrecision,
  genomicInflation,
}

String auditFamilyLabel(AuditFamily f) => switch (f) {
      AuditFamily.methodDesign => tr("Méthode compatible avec le plan d'étude", 'Method compatible with the study design'),
      AuditFamily.orAsRr => tr('OR présenté comme un RR', 'OR presented as an RR'),
      AuditFamily.agreementVsCi => tr("Limites d'accord confondues avec un IC", 'Limits of agreement confused with a CI'),
      AuditFamily.pValueMisread => tr('Interprétation de la valeur de p', 'Interpretation of the p-value'),
      AuditFamily.causalLanguage => tr("Conclusion causale tirée d'une association", 'Causal conclusion drawn from an association'),
      AuditFamily.predictionOverclaim => tr('Modèle prédictif présenté comme validé', 'Predictive model presented as validated'),
      AuditFamily.announcedNotDone => tr('Analyse annoncée mais non effectuée', 'Analysis announced but not performed'),
      AuditFamily.overPrecision => tr('Conclusion dépassant la précision des données', 'Conclusion exceeding the precision of the data'),
      AuditFamily.genomicInflation => tr('Inflation génomique : polygénie ou confusion', 'Genomic inflation: polygenicity or confounding'),
    };

enum AuditStatus { alert, ok, insufficient }

class AuditFinding {
  final AuditFamily family;
  final AuditStatus status;
  final Severity severity;
  final String message;
  final String? trigger;
  final String? correction;
  final bool lexical; // détecté par lexique (heuristique)
  AuditFinding(this.family, this.status, this.message,
      {this.severity = Severity.info, this.trigger, this.correction, this.lexical = false});

  Map<String, Object?> toJson() => {
        'family': family.name,
        'status': status.name,
        'severity': severity.name,
        'message': message,
        'trigger': trigger,
        'correction': correction,
        'lexical': lexical,
      };
}

class AuditReport {
  final List<AuditFinding> findings;
  AuditReport(this.findings);
  List<AuditFinding> get alerts => [for (final f in findings) if (f.status == AuditStatus.alert) f]
    ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  List<AuditFinding> of(AuditFamily f) => [for (final x in findings) if (x.family == f) x];
  Map<String, Object?> toJson() => {'findings': [for (final f in findings) f.toJson()]};
}

/// Remplace les lettres accentuées par leur équivalent non accentué, caractère
/// par caractère (les positions restent alignées sur le texte d'origine).
String foldAccents(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ’';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUY\'';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().toLowerCase();
}

/// Extrait la phrase contenant la position [pos].
String _sentenceAt(String text, int start, int end) {
  var a = start, b = end;
  bool isBoundary(int i) {
    final c = text[i];
    if (c == '\n') return true;
    if ('.!?;'.contains(c)) {
      // Pas une frontière si c'est un séparateur décimal (chiffre de part et d'autre).
      final prevDigit = i > 0 && RegExp(r'\d').hasMatch(text[i - 1]);
      final nextDigit = i + 1 < text.length && RegExp(r'\d').hasMatch(text[i + 1]);
      return !(prevDigit && nextDigit);
    }
    return false;
  }

  while (a > 0 && !isBoundary(a - 1)) {
    a--;
  }
  while (b < text.length && !isBoundary(b)) {
    b++;
  }
  final s = text.substring(a, math.min(text.length, b + 1)).trim();
  return s.length > 280 ? '${s.substring(0, 277)}…' : s;
}

class _Hit {
  final String excerpt;
  final String matched;
  _Hit(this.excerpt, this.matched);
}

List<_Hit> _find(String text, RegExp re) {
  final folded = foldAccents(text);
  return [for (final m in re.allMatches(folded)) _Hit(_sentenceAt(text, m.start, m.end), text.substring(m.start, m.end))];
}

/// Nombres présents dans le texte (virgule ou point décimal).
List<(double, int, int)> _numbers(String text) => [
      for (final m in RegExp(r'(?<![\d,.])\d+(?:[.,]\d+)?').allMatches(text))
        (double.parse(m[0]!.replaceAll(',', '.')), m.start, m.end)
    ];

/// Lance l'audit.
AuditReport runAudit({required ResearchQuestion question, required List<AnalysisResult> results, String text = ''}) {
  final f = <AuditFinding>[];
  final hasText = text.trim().isNotEmpty;
  final design = question.design;
  final ids = results.map((r) => r.methodId).toSet();
  bool any(bool Function(AnalysisResult) p) => results.any(p);

  // ------------------------------------------------ 0. Résultats non fiables
  final before = f.length;
  for (final r in results) {
    if (r.status == MethodStatus.inDevelopment) {
      f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
          tr('« ${r.methodName} » est une méthode en développement : son résultat ne peut pas être présenté comme fiable.', '"${r.methodName}" is a method in development: its result cannot be presented as reliable.'),
          severity: Severity.critical, trigger: r.methodName, correction: tr('Retirer ce résultat ou le confirmer avec un logiciel validé.', 'Remove this result or confirm it with validated software.')));
    } else if (r.alerts.any((a) => a.severity == Severity.critical)) {
      f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
          tr('« ${r.methodName} » comporte une alerte bloquante : ${r.alerts.firstWhere((a) => a.severity == Severity.critical).message}',
              '"${r.methodName}" has a blocking alert: ${r.alerts.firstWhere((a) => a.severity == Severity.critical).message}'),
          severity: Severity.critical, trigger: r.methodName, correction: tr("Ne pas rapporter ces estimations ; suivre la suggestion de l'alerte.", "Do not report these estimates; follow the alert's suggestion.")));
    }
  }

  // ------------------------------------------------ 1. Méthode × plan
  if (design == StudyDesign.unknown) {
    f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.insufficient,
        tr("Plan d'étude non renseigné : la compatibilité des méthodes avec le plan ne peut pas être vérifiée.", 'Study design not filled in: the compatibility of the methods with the design cannot be checked.'),
        correction: tr("Renseigner le plan d'étude dans la question de recherche.", 'Fill in the study design in the research question.')));
  } else {
    if (design == StudyDesign.caseControl) {
      for (final r in results) {
        final rr = r.estimates.where((e) => e.label.startsWith('Risque relatif') || e.label.startsWith('Risk ratio') || e.label.startsWith('RR') || e.label.contains('Différence de risques') || e.label.contains('Risk difference'));
        if (rr.isNotEmpty || r.methodId == 'poisson_robust') {
          f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
              tr('Plan cas-témoins : « ${r.methodName} » fournit un RR ou une différence de risques, non estimables dans ce plan.', 'Case-control design: "${r.methodName}" gives an RR or a risk difference, not estimable in this design.'),
              severity: Severity.serious, trigger: r.methodName, correction: tr('Rapporter des OR (régression logistique).', 'Report ORs (logistic regression).')));
        }
        if (r.methodId == 'proportion_ci') {
          f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
              tr('Une prévalence calculée dans un échantillon cas-témoins reflète le recrutement, pas la population.', 'A prevalence computed in a case-control sample reflects recruitment, not the population.'),
              severity: Severity.serious, trigger: r.methodName));
        }
      }
    }
    if (question.pairing == Pairing.paired) {
      for (final r in results) {
        if (const {'t_test_welch', 't_test_student', 'mann_whitney', 'two_by_two', 'chi_square_rxc'}.contains(r.methodId)) {
          f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
              tr('Données déclarées appariées, mais « ${r.methodName} » suppose des groupes indépendants.', 'Data declared as paired, but "${r.methodName}" assumes independent groups.'),
              severity: Severity.serious, trigger: r.methodName,
              correction: tr('Utiliser t apparié, Wilcoxon signé ou McNemar.', 'Use paired t, Wilcoxon signed-rank or McNemar.')));
        }
      }
    }
    if (question.objective == StudyObjective.explanatory && ids.contains('prediction_logistic_internal')) {
      f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
          tr("Objectif explicatif mais modèle de prédiction : AUC et calibration ne renseignent pas sur l'effet d'un facteur.", 'Explanatory aim but prediction model: AUC and calibration say nothing about the effect of a factor.'),
          severity: Severity.caution, correction: tr("Choisir les covariables d'après un schéma causal (DAG) et interpréter l'effet d'intérêt.", 'Choose covariates from a causal diagram (DAG) and interpret the effect of interest.')));
    }
    if (question.objective == StudyObjective.predictive &&
        results.any((r) => r.methodId == 'logistic_regression') &&
        !ids.contains('prediction_logistic_internal')) {
      f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
          tr('Objectif prédictif mais aucune évaluation de performance (discrimination, calibration, validation interne).', 'Predictive aim but no performance evaluation (discrimination, calibration, internal validation).'),
          severity: Severity.serious, correction: tr("Utiliser l'atelier de modèles de prédiction.", 'Use the prediction model workshop.')));
    }
    if (design == StudyDesign.caseControl) {
      for (final r in results.where((r) => r.methodId == 'diagnostic_accuracy')) {
        f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
            tr('Performance diagnostique estimée en cas-témoins : VPP/VPN non transposables, Se/Sp souvent surestimées.', 'Diagnostic performance estimated in a case-control design: PPV/NPV not transferable, Se/Sp often overestimated.'),
            severity: Severity.serious, trigger: r.methodName));
      }
    }
    final metas = results.where((r) => r.methodId.startsWith('meta_')).toList();
    final hasRandom = metas.any((r) => (r.inputs['options'] as Map?)?['method'] != 'fixed');
    for (final r in metas) {
      final i2 = r.statistics['I2'] ?? 0;
      final opts = (r.inputs['options'] as Map?)?['method'];
      if (opts == 'fixed' && i2 > 0.5) {
        f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.alert,
            hasRandom
                ? tr("Analyse à effet fixe (I² = ${fmtPct(i2)}) présente à côté d'une analyse à effets aléatoires : acceptable comme sensibilité, pas comme résultat principal.",
                    'Fixed-effect analysis (I² = ${fmtPct(i2)}) alongside a random-effects analysis: acceptable as a sensitivity analysis, not as the main result.')
                : tr('Métaanalyse à effet fixe malgré I² = ${fmtPct(i2)}.', 'Fixed-effect meta-analysis despite I² = ${fmtPct(i2)}.'),
            severity: hasRandom ? Severity.caution : Severity.serious,
            trigger: r.methodName,
            correction: tr("Modèle à effets aléatoires, intervalle de prédiction, recherche des sources d'hétérogénéité.", 'Random-effects model, prediction interval, search for sources of heterogeneity.')));
      }
    }
  }
  if (f.length == before && design != StudyDesign.unknown) {
    f.add(AuditFinding(AuditFamily.methodDesign, AuditStatus.ok, tr('Aucune incompatibilité détectée entre le plan déclaré et les méthodes utilisées.', 'No incompatibility detected between the declared design and the methods used.')));
  }

  // Raccourcis lexicaux
  final orResults = [for (final r in results) for (final e in r.estimates) if (e.label.contains('OR') || e.label.toLowerCase().contains('odds')) e];
  final rrComputed = any((r) => r.estimates.any((e) => e.label.startsWith('Risque relatif') || e.label.startsWith('Risk ratio') || e.label.startsWith('RR') || e.label.startsWith('Rapport de prévalences') || e.label.startsWith('Prevalence ratio')));

  // ------------------------------------------------ 2. OR présenté comme RR
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.orAsRr, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else if (orResults.isEmpty) {
    f.add(AuditFinding(AuditFamily.orAsRr, AuditStatus.ok, tr('Aucun odds ratio dans les analyses du projet.', 'No odds ratio in the project analyses.')));
  } else {
    final hits = <_Hit>[];
    hits.addAll(_find(text, RegExp(r"(risque|probabilite|chance)s?\s+(\w+\s+){0,3}(\d+[.,]?\d*\s*fois|multipli|double|triple)")));
    hits.addAll(_find(text, RegExp(r"(\d+[.,]?\d*\s*fois\s+plus\s+de\s+risque)")));
    hits.addAll(_find(text, RegExp(r"\brisque relatif\b|\brr\s*=")));
    hits.addAll(_find(text, RegExp(r"\b(risk|probability|chance|likelihood)s?\s+(\w+\s+){0,3}(\d+[.,]?\d*[\s-]*(times|fold)|multipl|doubl|tripl)")));
    hits.addAll(_find(text, RegExp(r"\d+[.,]?\d*\s*times\s+(the|a|as)?\s*(higher|greater|increased)?\s*risk")));
    hits.addAll(_find(text, RegExp(r"\brelative risk\b|\brisk ratio\b")));
    // Valeur d'un OR calculé citée avec le mot « risque » dans la même phrase.
    final orValues = [for (final e in orResults) e.value];
    for (final (v, s, e) in _numbers(text)) {
      if (orValues.any((o) => o.isFinite && (o - v).abs() <= 0.006 * math.max(1, o.abs()))) {
        final sent = foldAccents(_sentenceAt(text, s, e));
        if ((sent.contains('risque') || sent.contains('risk')) && !RegExp(r'\bor\s*[=(:]|\bors?\s+(de|of|etait|est|was|were|is)\b|odds|\bcote').hasMatch(sent)) {
          hits.add(_Hit(_sentenceAt(text, s, e), text.substring(s, e)));
        }
      }
    }
    final relevant = rrComputed
        ? hits.where((h) => !RegExp('risque relatif|relative risk|risk ratio').hasMatch(foldAccents(h.excerpt))).toList()
        : hits;
    if (relevant.isEmpty) {
      f.add(AuditFinding(AuditFamily.orAsRr, AuditStatus.ok, tr("Aucune formulation présentant un OR comme un risque relatif n'a été repérée.", 'No wording presenting an OR as a risk ratio was found.'), lexical: true));
    }
    final seen = <String>{};
    for (final h in relevant) {
      if (!seen.add(h.excerpt)) continue;
      final frequent = any((r) => r.alerts.any((a) => a.code == 'or_rr_divergence' || a.code == 'or_not_rr'));
      f.add(AuditFinding(AuditFamily.orAsRr, AuditStatus.alert,
          tr("Un odds ratio semble rédigé comme un risque relatif (« ${h.matched} »).${frequent ? " L'issue est fréquente : l'écart entre OR et RR est important." : ""}",
              'An odds ratio seems to be written as a risk ratio ("${h.matched}").${frequent ? " The outcome is common: the gap between OR and RR is large." : ""}'),
          severity: frequent ? Severity.serious : Severity.caution,
          trigger: h.excerpt,
          lexical: true,
          correction: tr("Écrire « la cote (odds) de l'événement était X fois plus élevée » ou estimer un RR (Poisson robuste) si le plan le permet.", 'Write "the odds of the event were X times higher" or estimate an RR (robust Poisson) if the design allows.')));
    }
  }

  // ------------------------------------------------ 3. Limites d'accord ≠ IC
  final ba = results.where((r) => r.methodId == 'bland_altman').toList();
  if (ba.isEmpty) {
    f.add(AuditFinding(AuditFamily.agreementVsCi, AuditStatus.ok, tr("Pas d'analyse d'accord dans le projet.", 'No agreement analysis in the project.')));
  } else if (!hasText) {
    f.add(AuditFinding(AuditFamily.agreementVsCi, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else {
    final loas = [for (final r in ba) ...r.estimates.where((e) => e.label.startsWith('Limite') || e.label.contains('limit of agreement')).map((e) => e.value)];
    var found = false;
    for (final (v, s, e) in _numbers(text)) {
      if (loas.any((l) => (l.abs() - v).abs() <= 0.006 * math.max(1, l.abs()))) {
        final sent = foldAccents(_sentenceAt(text, s, e));
        if (RegExp(r"intervalle de confiance|\bic\b|\bic95|\bic a 95|confidence interval|\bci\b|\b95\s*% ci").hasMatch(sent) && !sent.contains('limite') && !sent.contains('limit')) {
          found = true;
          f.add(AuditFinding(AuditFamily.agreementVsCi, AuditStatus.alert,
              tr("Une limite d'accord (${text.substring(s, e)}) semble présentée comme un intervalle de confiance.", 'A limit of agreement (${text.substring(s, e)}) seems to be presented as a confidence interval.'),
              severity: Severity.serious, trigger: _sentenceAt(text, s, e), lexical: true,
              correction: tr("Les limites d'accord décrivent la dispersion des différences individuelles (≈ 95 % des différences) ; l'IC du biais décrit la précision de la différence moyenne. Les nommer distinctement.",
                  'The limits of agreement describe the spread of individual differences (≈ 95% of differences); the CI of the bias describes the precision of the mean difference. Name them distinctly.')));
        }
      }
    }
    for (final h in _find(text, RegExp(r"intervalle de confiance (de l'|des? )?accord|ic (de l'|des? )?accord|confidence interval (of|for) (the )?agreement|\bci (of|for) (the )?agreement"))) {
      found = true;
      f.add(AuditFinding(AuditFamily.agreementVsCi, AuditStatus.alert, tr('Expression ambiguë « ${h.matched} ».', 'Ambiguous expression "${h.matched}".'),
          severity: Severity.caution, trigger: h.excerpt, lexical: true, correction: tr("Écrire « limites d'accord à 95 % » et, séparément, « IC des limites ».", 'Write "95% limits of agreement" and, separately, "CI of the limits".')));
    }
    if (!found) f.add(AuditFinding(AuditFamily.agreementVsCi, AuditStatus.ok, tr('Pas de confusion repérée.', 'No confusion found.'), lexical: true));
  }

  // ------------------------------------------------ 4. Valeur de p
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.pValueMisread, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else {
    final pats = <(RegExp, String, Severity)>[
      (RegExp(r"probabilite (que|pour que) (l'|les? )?(hypothese|h0|resultat|difference|effet|association)[^.]{0,40}(vrai|du(e)? au hasard|faux|nulle?)"),
          tr("La valeur de p n'est pas la probabilité qu'une hypothèse soit vraie ou que le résultat soit dû au hasard.", 'The p-value is not the probability that a hypothesis is true or that the result is due to chance.'), Severity.serious),
      (RegExp(r"\d+([.,]\d+)?\s*% de (chances?|probabilite) (que|d'?)"), tr("Formulation probabiliste sur une hypothèse à partir d'une valeur de p.", 'Probabilistic statement about a hypothesis from a p-value.'), Severity.serious),
      (RegExp(r"p\s*[<=>]\s*0[.,]\d+[^.]{0,60}(prouve|demontre|confirme)"), tr('Une valeur de p ne « prouve » ni ne « démontre ».', 'A p-value neither "proves" nor "demonstrates".'), Severity.serious),
      (RegExp(r"(p\s*>\s*0[.,]05|non significati\w*)[^.]{0,80}(pas de difference|aucune difference|absence d'effet|aucun effet|n'a pas d'effet|equivalen|identiques|similaires|sans effet)"),
          tr("Un résultat non significatif est présenté comme une preuve d'absence d'effet.", 'A non-significant result is presented as evidence of no effect.'), Severity.serious),
      (RegExp(r"(pas de difference|aucune difference|aucun effet|absence d'effet|equivalen\w*)[^.]{0,80}(p\s*>\s*0[.,]05|p\s*=\s*0[.,][1-9]|non significati)"),
          tr("Un résultat non significatif est présenté comme une preuve d'absence d'effet.", 'A non-significant result is presented as evidence of no effect.'), Severity.serious),
      (RegExp(r"probability (that|of) (the )?(null )?(hypothesis|h0|result|difference|effect|association)[^.]{0,40}(true|due to chance|false|being)"),
          tr("La valeur de p n'est pas la probabilité qu'une hypothèse soit vraie ou que le résultat soit dû au hasard.", 'The p-value is not the probability that a hypothesis is true or that the result is due to chance.'), Severity.serious),
      (RegExp(r"\d+([.,]\d+)?\s*% (chance|probability) (that|of)"), tr("Formulation probabiliste sur une hypothèse à partir d'une valeur de p.", 'Probabilistic statement about a hypothesis from a p-value.'), Severity.serious),
      (RegExp(r"p\s*[<=>]\s*0[.,]\d+[^.]{0,60}(prove|demonstrate|confirm)"), tr('Une valeur de p ne « prouve » ni ne « démontre ».', 'A p-value neither "proves" nor "demonstrates".'), Severity.serious),
      (RegExp(r"(p\s*>\s*0[.,]05|non-?\s?significan\w*|not (statistically )?significan\w*|p\s*=\s*0[.,]([1-9]|0[5-9])\d*)[^.]{0,80}(no difference|no effect|no association|identical|similar|did not differ)"),
          tr("Un résultat non significatif est présenté comme une preuve d'absence d'effet.", 'A non-significant result is presented as evidence of no effect.'), Severity.serious),
      (RegExp(r"(no difference|no effect|no association)[^.]{0,80}(p\s*>\s*0[.,]05|p\s*=\s*0[.,][1-9]|non-?\s?significan|not significan)"),
          tr("Un résultat non significatif est présenté comme une preuve d'absence d'effet.", 'A non-significant result is presented as evidence of no effect.'), Severity.serious),
      (RegExp(r"trend(ing)? towards? (statistical )?significance|approach(ed|ing) (statistical )?significance|borderline significan|marginally significan"),
          tr('« Tendance à la significativité » : formulation qui sur-interprète une valeur de p au-dessus du seuil.', '"Trend towards significance": wording that over-interprets a p-value above the threshold.'), Severity.caution),
      (RegExp(r"(very|highly|strongly) significan"), tr("« Hautement significatif » ne renseigne pas sur l'ampleur de l'effet.", '"Highly significant" says nothing about the size of the effect.'), Severity.info),
      (RegExp(r"tendance (a la |vers la )?significativite|proche de la significativite|limite de la significativite"),
          tr('« Tendance à la significativité » : formulation qui sur-interprète une valeur de p au-dessus du seuil.', '"Trend towards significance": wording that over-interprets a p-value above the threshold.'), Severity.caution),
      (RegExp(r"(tres|hautement|fortement) significati"), tr("« Hautement significatif » ne renseigne pas sur l'ampleur de l'effet.", '"Highly significant" says nothing about the size of the effect.'), Severity.info),
    ];
    var n = 0;
    for (final (re, msg, sev) in pats) {
      for (final h in _find(text, re)) {
        n++;
        f.add(AuditFinding(AuditFamily.pValueMisread, AuditStatus.alert, msg,
            severity: sev, trigger: h.excerpt, lexical: true,
            correction: tr("Rapporter l'estimation et son IC ; écrire p comme la compatibilité des données avec l'hypothèse nulle sous le modèle. Pour conclure à l'absence d'effet, fixer une marge cliniquement pertinente et vérifier que l'IC y est contenu.",
                'Report the estimate and its CI; describe p as the compatibility of the data with the null hypothesis under the model. To conclude no effect, set a clinically relevant margin and check that the CI lies within it.')));
      }
    }
    // « significatif » avec p > 0,05 dans la même phrase.
    for (final h in _find(text, RegExp(r"p\s*=\s*0[.,](0[5-9]|[1-9])\d*[^.]{0,60}\bsignifica(ti|n)"))) {
      if (RegExp(r'(non|pas|not|non-)\s?(statistically )?significa').hasMatch(foldAccents(h.excerpt))) continue;
      n++;
      f.add(AuditFinding(AuditFamily.pValueMisread, AuditStatus.alert, tr('Résultat qualifié de significatif avec p ≥ 0,05.', 'Result described as significant with p ≥ 0.05.'),
          severity: Severity.serious, trigger: h.excerpt, lexical: true));
    }
    if (n == 0) f.add(AuditFinding(AuditFamily.pValueMisread, AuditStatus.ok, tr('Aucune formulation erronée repérée.', 'No erroneous wording found.'), lexical: true));
  }

  // ------------------------------------------------ 5. Langage causal
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else if (design == StudyDesign.unknown) {
    f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.insufficient,
        tr("Plan d'étude non renseigné : impossible de juger si un langage causal est justifié.", 'Study design not filled in: impossible to judge whether causal language is justified.')));
  } else if (design == StudyDesign.rct) {
    f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.ok,
        tr("Essai randomisé : une interprétation causale de l'effet de l'intervention randomisée est défendable (pas pour les autres facteurs ni les sous-groupes).",
            'Randomized trial: a causal interpretation of the effect of the randomized intervention is defensible (not for other factors or subgroups).')));
  } else if (ids.contains('mendelian_randomization') || ids.contains('mendelian_randomization_mv')) {
    // Randomisation mendélienne : la conclusion causale est l'objet de la méthode, sous réserve de ses hypothèses
    // (instruments valides, pas de pléiotropie horizontale), qui doivent être discutées dans le texte.
    final causal = _find(text, RegExp(r"\b(caus\w*|entraine\w*|provoqu\w*|protege\w*|l'effet (de|du|des)|causes?|caused|causal\w*|protects?|the effect of)\b"));
    final discussed = RegExp(r'pleiotrop|instrument|hypothes|assumption|exclusion').hasMatch(foldAccents(text));
    // Pléiotropie directionnelle détectée (intercept MR-Egger) mais passée sous silence.
    if (!RegExp('pleiotrop').hasMatch(foldAccents(text))) {
      for (final r in results.where((r) => r.methodId == 'mendelian_randomization' && r.checks.any((c) => c.id == 'pleiotropy' && c.status == CheckStatus.warning))) {
        f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.alert,
            tr('Pléiotropie directionnelle détectée dans « ${r.methodName} » (intercept MR-Egger, ${fmtP(r.statistics['egger_intercept_p'])}) mais non discutée : l\'estimation IVW de cette exposition n\'est pas fiable.',
                'Directional pleiotropy detected in "${r.methodName}" (MR-Egger intercept, ${fmtP(r.statistics['egger_intercept_p'])}) but not discussed: the IVW estimate for this exposure is not reliable.'),
            severity: Severity.serious, trigger: r.methodName,
            correction: tr('Rapporter MR-Egger, médiane et mode pondérés et la MR multivariée ; ne pas conclure sur l\'IVW seul.', 'Report MR-Egger, weighted median and mode and multivariable MR; do not conclude on IVW alone.')));
      }
    }
    if (causal.isEmpty) {
      f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.ok, tr('Aucune formulation causale repérée.', 'No causal wording found.'), lexical: true));
    } else if (discussed) {
      f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.ok,
          tr('Randomisation mendélienne : conclusion causale accompagnée d\'une discussion des hypothèses (instruments, pléiotropie).',
              'Mendelian randomization: causal conclusion accompanied by a discussion of the assumptions (instruments, pleiotropy).'),
          lexical: true));
    } else {
      f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.alert,
          tr('Conclusion causale (« ${causal.first.matched} ») tirée d\'une randomisation mendélienne sans discuter ses hypothèses : instruments valides, absence de pléiotropie horizontale.',
              'Causal conclusion ("${causal.first.matched}") drawn from Mendelian randomization without discussing its assumptions: valid instruments, no horizontal pleiotropy.'),
          severity: Severity.serious, trigger: causal.first.excerpt, lexical: true,
          correction: tr('Discuter la validité des instruments et la pléiotropie (intercept MR-Egger, concordance des méthodes, leave-one-out) avant de conclure.',
              'Discuss instrument validity and pleiotropy (MR-Egger intercept, concordance of methods, leave-one-out) before concluding.')));
    }
  } else if (design == StudyDesign.systematicReview) {
    f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.insufficient,
        tr('Métaanalyse : la légitimité causale dépend du plan des études incluses (non renseigné étude par étude).', 'Meta-analysis: causal legitimacy depends on the design of the included studies (not filled in study by study).')));
  } else {
    final re = RegExp(r"\b(entraine\w*|provoqu\w*|caus\w*|induit|induisent|protege\w* contre|est responsable|sont responsables|conduit a|grace a|l'effet (de|du|des)|l'impact (de|du|des)|reduit le risque|augmente le risque|diminue le risque|ameliore\w*|prevenir|previent"
        r"|leads? to|led to|results? in|induces?|induced|protects? against|is responsible|are responsible|thanks to|the effect of|the impact of|reduces? the risk|increases? the risk|decreases? the risk|improves?|improved|prevents?|prevented)\b");
    final hits = _find(text, re);
    final seen = <String>{};
    for (final h in hits) {
      if (!seen.add(h.excerpt)) continue;
      final hedged = RegExp(r'associ|pourrait|suggere|compatible|hypothes|could|might|\bmay\b|suggest').hasMatch(foldAccents(h.excerpt));
      f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.alert,
          tr('Formulation causale (« ${h.matched} ») dans une ${designLabel(design)}.${hedged ? " La phrase contient une nuance ; à relire." : ""}',
              'Causal wording ("${h.matched}") in a ${designLabel(design)}.${hedged ? " The sentence contains a hedge; to be reread." : ""}'),
          severity: hedged ? Severity.caution : Severity.serious, trigger: h.excerpt, lexical: true,
          correction: tr('Écrire « était associé(e) à » et discuter confusion résiduelle, biais de sélection et sens causal.', 'Write "was associated with" and discuss residual confounding, selection bias and causal direction.')));
    }
    if (seen.isEmpty) f.add(AuditFinding(AuditFamily.causalLanguage, AuditStatus.ok, tr('Aucune formulation causale repérée.', 'No causal wording found.'), lexical: true));
  }

  // ------------------------------------------------ 6. Prédiction présentée comme validée
  final pred = results.where((r) => r.methodId.startsWith('prediction_') || r.methodId == 'external_validation').toList();
  final claims = hasText
      ? _find(text, RegExp(r"\b(valide|validee|validation|validated)\b[^.]{0,40}|\b(utilisable|applicable|recommande\w*) en (pratique|routine|clinique)|\b(usable|applicable|recommended|ready) (in|for) (clinical )?(practice|routine|clinic\w*)|\b(fiable|reliable)\b|excellent\w* (performance|pouvoir|discrimination|predictive)"))
      : <_Hit>[];
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.predictionOverclaim, pred.isEmpty ? AuditStatus.ok : AuditStatus.insufficient,
        pred.isEmpty ? tr('Pas de modèle de prédiction dans le projet.', 'No prediction model in the project.') : tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else {
    var n = 0;
    for (final h in claims) {
      final s = foldAccents(h.excerpt);
      final internalOnly = pred.isEmpty || pred.every((r) => (r.figures['stage'] ?? 'internal') == 'internal');
      final clinical = s.contains('clinique') || s.contains('clinical') || s.contains('pratique') || s.contains('practice');
      final mentionsInternal = (s.contains('interne') || s.contains('internal')) && !clinical;
      if (mentionsInternal && !s.contains('externe') && !s.contains('external')) continue;
      if (internalOnly || clinical) {
        n++;
        f.add(AuditFinding(AuditFamily.predictionOverclaim, AuditStatus.alert,
            pred.isEmpty
                ? tr("Le texte qualifie un modèle de validé ou d'utilisable, mais aucune évaluation de performance n'est dans le projet.", 'The text calls a model validated or usable, but no performance evaluation is in the project.')
                : tr('Le texte présente le modèle comme validé ou utilisable alors que seule une validation interne a été faite.', 'The text presents the model as validated or usable although only internal validation was done.'),
            severity: Severity.serious, trigger: h.excerpt, lexical: true,
            correction: tr("Écrire « performance après validation interne par bootstrap » ; une validation externe puis une étude d'impact sont nécessaires avant tout usage clinique. Une AUC élevée ne suffit pas.",
                'Write "performance after internal validation by bootstrap"; an external validation and then an impact study are needed before any clinical use. A high AUC is not enough.')));
      }
    }
    if (n == 0) {
      f.add(AuditFinding(AuditFamily.predictionOverclaim, AuditStatus.ok,
          pred.isEmpty ? tr('Pas de modèle de prédiction ni de revendication de validation.', 'No prediction model and no validation claim.') : tr('Pas de revendication excessive repérée.', 'No excessive claim found.'), lexical: true));
    }
  }

  // ------------------------------------------------ 7. Annoncé mais non effectué
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.announcedNotDone, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else {
    final checksDone = <(RegExp, bool, String)>[
      (RegExp(r"analyses? de sensibilite|sensitivity analys[ie]s"),
          any((r) => r.figures.containsKey('leaveOneOut') || r.statistics.containsKey('loo_min') || r.tables.any((t) => RegExp('sensibilit|sensitivity').hasMatch(t.title.toLowerCase()))),
          tr('analyse de sensibilité', 'sensitivity analysis')),
      (RegExp(r"sous-groupes?|subgroups?"), any((r) => r.figures.containsKey('subgroups')), tr('analyse en sous-groupes', 'subgroup analysis')),
      (RegExp(r"imputation multiple|donnees manquantes ont ete imputees|multiple imputation|missing (data|values) were imputed"),
          ids.any((i) => i.startsWith('mi_') || i.endsWith('_mi')), tr('imputation multiple', 'multiple imputation')),
      (RegExp(r"validation externe|valide (sur|dans) une (cohorte|population) (externe|independante)|external(ly)? validat\w*|validated (in|on) an? (external|independent) (cohort|population)"),
          ids.contains('external_validation'), tr('validation externe', 'external validation')),
      (RegExp(r"bootstrap|validation interne|internal validation"), ids.contains('prediction_logistic_internal'), tr('validation interne par bootstrap', 'internal validation by bootstrap')),
      (RegExp(r"ajuste\w* sur|apres ajustement|analyse multivariee|multivariable|adjusted for|after adjustment|multivariate analys[ie]s"),
          any((r) =>
              (const {'linear_regression', 'logistic_regression', 'poisson_robust', 'firth_logistic'}.contains(r.methodId) && ((r.inputs['model'] as Map?)?['columns'] as List? ?? []).length > 2) ||
              (const {'snp_scan', 'lmm_scan'}.contains(r.methodId) && ((r.inputs['covariates'] as List?) ?? const []).isNotEmpty)),
          tr('analyse ajustée', 'adjusted analysis')),
      (RegExp(r"(conditions|hypotheses) (d'application |du modele )?(ont ete |ont )?(verifiees|respectees|controlees)|normalite (a ete )?verifiee|(assumptions|conditions) (of the model )?(were |have been )?(checked|verified|met)|normality was (checked|verified)"),
          any((r) => r.checks.isNotEmpty), tr('vérification des conditions', 'checking of assumptions')),
      (RegExp(r"test d'egger|biais de publication|egger'?s? test|publication bias"), any((r) => r.statistics.containsKey('egger_p')),
          tr("test d'Egger / biais de publication", "Egger's test / publication bias")),
      (RegExp(r"calibration"), any((r) => r.figures.containsKey('calibration')), 'calibration'),
    ];
    var n = 0;
    for (final (re, done, label) in checksDone) {
      final hits = _find(text, re);
      if (hits.isNotEmpty && !done) {
        n++;
        f.add(AuditFinding(AuditFamily.announcedNotDone, AuditStatus.alert,
            tr('Le texte mentionne « $label », mais aucune analyse correspondante ne figure dans le journal du projet.', 'The text mentions "$label", but no corresponding analysis appears in the project log.'),
            severity: Severity.serious, trigger: hits.first.excerpt, lexical: true,
            correction: tr("Réaliser l'analyse dans le projet (pour qu'elle soit journalisée) ou retirer la mention.", 'Run the analysis in the project (so that it is logged) or remove the mention.')));
      }
    }
    // Vérifications signalées comme non satisfaites mais passées sous silence (un constat par condition, même répétée
    // dans plusieurs analyses).
    final unmet = <String, List<(AnalysisResult, Check)>>{};
    for (final r in results) {
      for (final c in r.checks.where((c) => c.status == CheckStatus.violated)) {
        final kw = foldAccents(c.label).split(' ').firstWhere((w) => w.length > 5, orElse: () => '');
        if (kw.isNotEmpty && !foldAccents(text).contains(kw)) (unmet[c.label] ??= []).add((r, c));
      }
    }
    for (final e in unmet.values) {
      final (r, c) = e.first;
      final more = e.length - 1;
      n++;
      f.add(AuditFinding(AuditFamily.announcedNotDone, AuditStatus.alert,
          tr('Condition non satisfaite dans « ${r.methodName} »${more > 0 ? ' et $more autre(s) analyse(s)' : ''} (« ${c.label} ») et non discutée dans le texte.',
              'Unmet condition in "${r.methodName}"${more > 0 ? ' and $more other analysis(es)' : ''} ("${c.label}") not discussed in the text.'),
          severity: Severity.caution, trigger: c.detail, correction: tr('Mentionner cette limite et ses conséquences.', 'Mention this limitation and its consequences.')));
    }
    final missingAlerted = any((r) => r.alerts.any((a) => a.code == 'complete_case' || a.code == 'missing_values'));
    if (missingAlerted && !foldAccents(text).contains('manquant') && !foldAccents(text).contains('missing')) {
      n++;
      f.add(AuditFinding(AuditFamily.announcedNotDone, AuditStatus.alert,
          tr("Des observations ont été exclues pour données manquantes, mais le texte n'en parle pas.", 'Observations were excluded for missing data, but the text does not mention it.'),
          severity: Severity.caution, correction: tr("Indiquer le nombre d'exclusions par variable et l'approche (cas complets).", 'State the number of exclusions per variable and the approach (complete cases).')));
    }
    if (n == 0) f.add(AuditFinding(AuditFamily.announcedNotDone, AuditStatus.ok, tr('Les analyses mentionnées figurent dans le journal.', 'The analyses mentioned appear in the log.'), lexical: true));
  }

  // ------------------------------------------------ 8. Précision dépassée
  if (!hasText) {
    f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.insufficient, tr('Aucun texte de résultats fourni.', 'No results text provided.')));
  } else {
    var n = 0;
    final primary = [
      for (final r in results)
        for (final e in r.estimates.take(1))
          if (e.hasInterval) (r, e)
    ];
    final absenceClaims = _find(
        text,
        RegExp(r"pas de difference|aucune difference|aucun effet|absence d'(effet|association|difference)|n'a pas d'effet|sans effet|equivalent\w*|ne modifie pas|n'influence pas|n'est pas associe"
            r"|no difference|no effect|absence of (effect|association|difference)|had no effect|without effect|did not (change|affect|influence|differ)|(is|was|were) not associated"));
    if (absenceClaims.isNotEmpty) {
      for (final (_, e) in primary) {
        final ratio = e.label.contains('OR') || e.label.contains('RR') || e.label.contains('Risque relatif') || e.label.contains('ratio') || e.label.contains('Rapport') || e.label.contains('Ratio');
        final nullV = ratio ? 1.0 : 0.0;
        if (e.lower! <= nullV && e.upper! >= nullV) {
          final wide = ratio ? (e.upper! / math.max(e.lower!, 1e-9) > 3) : true;
          n++;
          f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert,
              tr("Le texte conclut à une absence d'effet alors que l'IC de « ${e.label} » (${fmt(e.lower)} à ${fmt(e.upper)}) ${wide ? "est large et inclut des effets potentiellement importants" : "inclut la valeur nulle"}.",
                  'The text concludes no effect although the CI of "${e.label}" (${fmt(e.lower)} to ${fmt(e.upper)}) ${wide ? "is wide and includes potentially important effects" : "includes the null value"}.'),
              severity: Severity.serious, trigger: absenceClaims.first.excerpt, lexical: true,
              correction: tr("Écrire « les données ne permettent pas de conclure » et donner l'IC ; ne conclure à l'équivalence qu'avec une marge fixée a priori.",
                  'Write "the data do not allow a conclusion" and give the CI; conclude equivalence only with a margin set a priori.')));
          break;
        }
      }
    }
    // Généralisation malgré une hétérogénéité importante (métaanalyse).
    final hetero = results.where((r) => r.methodId.startsWith('meta_') && (r.statistics['I2'] ?? 0) > 0.5).toList();
    if (hetero.isNotEmpty) {
      for (final h in _find(text, RegExp(r"\bpartout\b|dans tous les (contextes|pays|cas)|toutes les populations|quel que soit|universel\w*|\beverywhere\b|in all (settings|countries|cases|contexts)|all populations|regardless of|universal\w*"))) {
        n++;
        final r = hetero.first;
        f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert,
            tr("Généralisation (« ${h.matched} ») alors que l'hétérogénéité est importante (I² = ${fmtPct(r.statistics['I2'])})${r.statistics.containsKey('pi_lower') ? " et que l'intervalle de prédiction va de ${fmt(r.estimates.length > 1 ? r.estimates[1].lower : null)} à ${fmt(r.estimates.length > 1 ? r.estimates[1].upper : null)}" : ""}.",
                'Generalization ("${h.matched}") although heterogeneity is considerable (I² = ${fmtPct(r.statistics['I2'])})${r.statistics.containsKey('pi_lower') ? " and the prediction interval runs from ${fmt(r.estimates.length > 1 ? r.estimates[1].lower : null)} to ${fmt(r.estimates.length > 1 ? r.estimates[1].upper : null)}" : ""}.'),
            severity: Severity.serious, trigger: h.excerpt, lexical: true,
            correction: tr("Décrire l'effet moyen ET sa variabilité (intervalle de prédiction) ; rechercher les sources d'hétérogénéité.", 'Describe the mean effect AND its variability (prediction interval); look for sources of heterogeneity.')));
      }
    }
    for (final h in _find(text, RegExp(r"biais de publication (a ete |est |peut etre )?(exclu|ecarte|elimine)|absence de biais de publication|pas de biais de publication|publication bias (was |is |can be )?(excluded|ruled out|eliminated)|absence of publication bias|no publication bias"))) {
      n++;
      f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert,
          tr("Un test d'asymétrie (Egger) non significatif n'exclut pas un biais de publication (faible puissance, autres causes d'asymétrie).", 'A non-significant asymmetry test (Egger) does not rule out publication bias (low power, other causes of asymmetry).'),
          severity: Severity.caution, trigger: h.excerpt, lexical: true,
          correction: tr("Écrire « le test d'Egger ne met pas en évidence d'asymétrie (p = …) ; un biais de publication ne peut être exclu ».", 'Write "Egger\'s test shows no evidence of asymmetry (p = …); publication bias cannot be ruled out".')));
    }
    for (final h in _find(text, RegExp(r"\b(prouve\w*|demontre\w*|certain\w*|definitivement|indiscutabl\w*|confirme\w*|proves?|proved|proven|demonstrates?|demonstrated|definitely|definitively|indisputabl\w*|confirms?|confirmed)\b"))) {
      n++;
      f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert, tr("Formulation catégorique (« ${h.matched} ») incompatible avec l'incertitude statistique.", 'Categorical wording ("${h.matched}") incompatible with statistical uncertainty.'),
          severity: Severity.caution, trigger: h.excerpt, lexical: true, correction: tr("Préférer « suggère », « est compatible avec », assorti de l'IC.", 'Prefer "suggests", "is compatible with", together with the CI.')));
    }
    for (final m in RegExp(r'\d+[.,]\d{4,}').allMatches(text)) {
      n++;
      f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert, tr('Nombre rapporté avec une précision excessive (« ${m[0]} »).', 'Number reported with excessive precision ("${m[0]}").'),
          severity: Severity.info, trigger: _sentenceAt(text, m.start, m.end), correction: tr('2 à 3 chiffres significatifs pour les effets, p à 2 ou 3 décimales.', '2 to 3 significant figures for effects, p to 2 or 3 decimals.')));
    }
    final smallN = results.where((r) => r.methodId == 'proportion_ci' && ((r.inputs['n'] as int?) ?? 1000) < 100).toList();
    if (smallN.isNotEmpty) {
      for (final m in RegExp(r'\d+[.,]\d{2,}\s*%').allMatches(text)) {
        n++;
        f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.alert,
            tr('Pourcentage à deux décimales ou plus (« ${m[0]} ») pour un effectif < 100.', 'Percentage with two or more decimals ("${m[0]}") for a sample < 100.'),
            severity: Severity.info, trigger: _sentenceAt(text, m.start, m.end), correction: tr("Arrondir à l'unité ou à une décimale et donner le dénominateur.", 'Round to the unit or one decimal and give the denominator.')));
      }
    }
    if (n == 0) f.add(AuditFinding(AuditFamily.overPrecision, AuditStatus.ok, tr("Aucune conclusion excédant la précision des données n'a été repérée.", 'No conclusion exceeding the precision of the data was found.'), lexical: true));
  }

  // ------------------------------------------------ 9. Inflation génomique attribuée à la polygénie
  // Un λ > 1 peut venir d'une confusion (stratification, apparentés) : l'attribuer à la polygénie demande l'intercept de la
  // régression LD score (proche de 1).
  final scans = results.where((r) => r.methodId == 'snp_scan' || r.methodId == 'lmm_scan').toList();
  final ldsc = results.where((r) => r.methodId == 'ldsc').toList();
  if (scans.isEmpty && ldsc.isEmpty) {
    f.add(AuditFinding(AuditFamily.genomicInflation, AuditStatus.ok, tr('Sans objet : aucun balayage de variants.', 'Not applicable: no variant scan.')));
  } else {
    var n = 0;
    final claims = hasText ? _find(text, RegExp(r'polygen\w*')) : const <_Hit>[];
    final confounded = ldsc.where((r) => r.checks.any((c) => c.id == 'intercept' && c.status == CheckStatus.warning)).toList();
    for (final h in claims) {
      if (confounded.isNotEmpty) {
        final r = confounded.first;
        n++;
        f.add(AuditFinding(AuditFamily.genomicInflation, AuditStatus.alert,
            tr("Le texte attribue l'inflation à la polygénie alors que l'intercept de la régression LD score vaut ${fmt(r.statistics['intercept'], digits: 3)} (ES ${fmt(r.statistics['se_intercept'], digits: 3)}), nettement > 1 : une part de l'inflation vient d'une confusion.",
                'The text attributes the inflation to polygenicity although the LD score regression intercept is ${fmt(r.statistics['intercept'], digits: 3)} (SE ${fmt(r.statistics['se_intercept'], digits: 3)}), clearly > 1: part of the inflation comes from confounding.'),
            severity: Severity.serious, trigger: h.excerpt, lexical: true,
            correction: tr("Ajuster sur les composantes principales (ou utiliser un modèle mixte) et rapporter l'intercept après ajustement.", 'Adjust for the principal components (or use a mixed model) and report the intercept after adjustment.')));
        break;
      } else if (ldsc.isEmpty) {
        n++;
        f.add(AuditFinding(AuditFamily.genomicInflation, AuditStatus.alert,
            tr("Le texte attribue l'inflation à la polygénie sans régression LD score : un λ > 1 peut aussi venir d'une stratification ou d'apparentés.",
                'The text attributes the inflation to polygenicity without LD score regression: a λ > 1 may also come from stratification or relatives.'),
            severity: Severity.caution, trigger: h.excerpt, lexical: true,
            correction: tr("Vérifier l'intercept de la régression LD score, ou écrire « inflation dont l'origine (polygénie ou confusion) n'est pas établie ».",
                'Check the LD score regression intercept, or write "inflation whose origin (polygenicity or confounding) is not established".')));
        break;
      }
    }
    if (n == 0) {
      f.add(AuditFinding(AuditFamily.genomicInflation, AuditStatus.ok,
          tr("Aucune attribution de l'inflation à la polygénie contredite ou non étayée.", 'No attribution of the inflation to polygenicity that is contradicted or unsupported.'), lexical: hasText));
    }
  }
  return AuditReport(f);
}
