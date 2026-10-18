/// Exports reproductibles : CSV des tableaux, journal JSON, rapport HTML
/// imprimable (PDF via l'impression). Chaque export sépare explicitement :
///   1. les DONNÉES SAISIES,
///   2. les RÉSULTATS CALCULÉS par le moteur,
///   3. les INTERPRÉTATIONS PROPOSÉES (gabarits déterministes),
///   4. les POINTS À VÉRIFIER par le chercheur.
library;

import 'dart:convert';

import '../about.dart';
import '../i18n.dart';
import '../advisor/registry.dart';
import '../audit/audit.dart';
import '../data/csv.dart';
import '../model/design.dart';
import '../model/result.dart';
import '../project/project.dart';
import '../version.dart';
import 'figures.dart';

/// CSV d'un résultat : estimations puis tableaux.
String resultToCsv(AnalysisResult r) {
  final rows = <List<String>>[
    ['# Statoméa', '$engineName $engineVersion', r.methodName, r.status == MethodStatus.validated ? tr('méthode validée', 'validated method') : tr('MÉTHODE EN DÉVELOPPEMENT', 'METHOD IN DEVELOPMENT')],
    ['Section', tr('Libellé', 'Label'), tr('Valeur', 'Value'), tr('Borne inférieure', 'Lower bound'), tr('Borne supérieure', 'Upper bound'), tr('Niveau', 'Level'), tr('Intervalle', 'Interval'), 'p', tr('ES', 'SE')],
    for (final e in r.estimates)
      [
        tr('Résultat calculé', 'Computed result'),
        e.label,
        _raw(e.value),
        _raw(e.lower),
        _raw(e.upper),
        e.hasInterval ? '${e.level}' : '',
        e.hasInterval ? e.intervalKind : '',
        _raw(e.pValue),
        _raw(e.se)
      ],
    for (final s in r.statistics.entries) [tr('Statistique calculée', 'Computed statistic'), s.key, _raw(s.value), '', '', '', '', '', ''],
  ];
  final b = StringBuffer(toCsv(rows.first, rows.skip(1).toList()));
  for (final t in r.tables) {
    b
      ..writeln()
      ..writeln('# ${t.title}')
      ..write(toCsv(t.header, t.rows));
  }
  return b.toString();
}

String _raw(double? v) => v == null ? '' : (v.isFinite ? v.toString() : (v.isNaN ? 'NA' : (v > 0 ? 'Inf' : '-Inf')));

String _h(String s) => const HtmlEscape().convert(s);

String _table(ResultTable t) {
  final b = StringBuffer('<table><caption>${_h(t.title)}</caption><thead><tr>');
  for (final h in t.header) {
    b.write('<th>${_h(h)}</th>');
  }
  b.write('</tr></thead><tbody>');
  for (final r in t.rows) {
    b.write('<tr>');
    for (final c in r) {
      b.write('<td>${_h(c)}</td>');
    }
    b.write('</tr>');
  }
  b.write('</tbody></table>');
  return b.toString();
}

/// Points à vérifier par le chercheur, déduits des contrôles et alertes.
List<String> pointsToVerify(AnalysisResult r) => [
      if (r.status != MethodStatus.validated) tr('Méthode non validée : confirmer avec un logiciel de référence.', 'Method not validated: confirm with reference software.'),
      for (final c in r.checks)
        if (c.status != CheckStatus.ok) '${c.label} — ${checkStatusLabel(c.status)}${tr(' : ', ': ')}${c.detail}',
      for (final a in r.alerts)
        if (a.severity != Severity.info) '${a.message}${a.suggestion == null ? "" : " → ${a.suggestion}"}',
    ];

String _figures(AnalysisResult r) {
  final f = r.figures;
  final b = StringBuffer();
  if (f['forest'] is Map) b.writeln('<figure>${forestPlotSvg((f['forest'] as Map).cast())}<figcaption>Forest plot</figcaption></figure>');
  if (f['calibration'] is List) b.writeln('<figure>${calibrationSvg((f['calibration'] as List).cast(), smooth: (f['calibrationSmooth'] as List?)?.cast())}<figcaption>${tr('Courbe de calibration (déciles de risque prédit${f['calibrationSmooth'] is List ? ', lissage lowess' : ''})', 'Calibration curve (deciles of predicted risk${f['calibrationSmooth'] is List ? ', lowess smooth' : ''})')}</figcaption></figure>');
  if (f['doseResponse'] is List) {
    for (final c in (f['doseResponse'] as List).cast<Map>()) {
      b.writeln('<figure>${doseResponseSvg(c)}<figcaption>${tr('Courbe dose-effet (spline cubique restreinte) : ${c['variable']}, bande de confiance', 'Dose-response curve (restricted cubic spline): ${c['variable']}, confidence band')}</figcaption></figure>');
    }
  }
  if (f['bayes'] is Map) b.writeln('<figure>${bayesSvg(f['bayes'] as Map)}<figcaption>${tr('A priori, données et a posteriori ; bande : intervalle de crédibilité', 'Prior, data and posterior; band: credible interval')}</figcaption></figure>');
  if (f['its'] is Map) b.writeln('<figure>${itsSvg(f['its'] as Map)}<figcaption>${tr('Série interrompue : observé (gris avant, bleu après), droite segmentée ajustée, tendance antérieure prolongée (tirets rouges)', 'Interrupted series: observed (grey before, blue after), fitted segmented line, extended prior trend (red dashes)')}</figcaption></figure>');
  if (f['referenceInterval'] is Map) b.writeln('<figure>${referenceIntervalSvg(f['referenceInterval'] as Map)}<figcaption>${tr('Distribution des valeurs de référence, bornes (rouge) et IC des bornes (bandes)', 'Distribution of reference values, limits (red) and CIs of the limits (bands)')}</figcaption></figure>');
  if (f['methodComparison'] is Map) b.writeln('<figure>${methodComparisonSvg(f['methodComparison'] as Map)}<figcaption>${tr('Comparaison de méthodes : droite ajustée et identité', 'Method comparison: fitted line and identity')}</figcaption></figure>');
  if (f['lovePlot'] is Map) b.writeln('<figure>${lovePlotSvg(f['lovePlot'] as Map)}<figcaption>${tr('Équilibre des covariables avant et après ajustement (love plot)', 'Covariate balance before and after adjustment (love plot)')}</figcaption></figure>');
  if (f['psOverlap'] is Map) b.writeln('<figure>${psOverlapSvg(f['psOverlap'] as Map)}<figcaption>${tr('Distribution du score de propension par groupe (recouvrement)', 'Propensity score distribution by group (overlap)')}</figcaption></figure>');
  if (f['decisionCurve'] is List) b.writeln('<figure>${decisionCurveSvg((f['decisionCurve'] as List).cast())}<figcaption>${tr('Courbe de décision', 'Decision curve')}</figcaption></figure>');
  if (f['miChains'] is Map) b.writeln('<figure>${miChainsSvg(f['miChains'] as Map)}<figcaption>${tr('Convergence des chaînes d\'imputation', 'Convergence of the imputation chains')}</figcaption></figure>');
  if (f['sroc'] is Map) b.writeln('<figure>${srocSvg((f['sroc'] as Map).cast())}<figcaption>${tr('Espace ROC : études, point combiné, courbe SROC, régions de confiance et de prédiction', 'ROC space: studies, pooled point, SROC curve, confidence and prediction regions')}</figcaption></figure>');
  if (f['bubble'] is Map) b.writeln('<figure>${bubblePlotSvg(f['bubble'] as Map)}<figcaption>${tr('Méta-régression : effet selon le modérateur (aire ∝ poids)', 'Meta-regression: effect by moderator (area ∝ weight)')}</figcaption></figure>');
  if (f['trajectories'] is Map) b.writeln('<figure>${trajectoriesSvg(f['trajectories'] as Map)}<figcaption>${tr('Trajectoires individuelles (gris) et moyenne ajustée par groupe (modèle mixte)', 'Individual trajectories (grey) and fitted mean by group (mixed model)')}</figcaption></figure>');
  if (f['powerCurve'] is Map) b.writeln('<figure>${powerCurveSvg(f['powerCurve'] as Map)}<figcaption>${tr('Courbe de puissance : puissance selon l\'effectif (tirets rouges : puissance visée ; vert : effectif retenu)', 'Power curve: power by sample size (red dashes: target power; green: chosen sample size)')}</figcaption></figure>');
  if (f['cumulativeIncidence'] is Map) b.writeln('<figure>${cifSvg(f['cumulativeIncidence'] as Map)}<figcaption>${tr('Incidence cumulée (Aalen-Johansen, bande : IC 95 %), 1 − Kaplan-Meier naïf et incidence de l\'événement concurrent', 'Cumulative incidence (Aalen-Johansen, band: 95% CI), naive 1 − Kaplan-Meier and incidence of the competing event')}</figcaption></figure>');
  if (f['kaplanMeier'] is Map) b.writeln('<figure>${kmSvg((f['kaplanMeier'] as Map).cast())}<figcaption>${tr('Courbes de Kaplan-Meier', 'Kaplan-Meier curves')}</figcaption></figure>');
  if (f['blandAltman'] is Map) b.writeln('<figure>${blandAltmanSvg(f['blandAltman'] as Map)}<figcaption>${tr('Graphique de Bland-Altman', 'Bland-Altman plot')}</figcaption></figure>');
  if (f['volcano'] is Map) b.writeln('<figure>${volcanoSvg(f['volcano'] as Map)}<figcaption>${tr('Volcano plot (rouge : significatif au FDR choisi)', 'Volcano plot (red: significant at the chosen FDR)')}</figcaption></figure>');
  if (f['manhattan'] is Map) b.writeln('<figure>${manhattanSvg(f['manhattan'] as Map)}<figcaption>${tr('Manhattan plot (rouge : seuil pangénomique 5 × 10⁻⁸ ; pointillés : seuil suggestif 10⁻⁵)', 'Manhattan plot (red: genome-wide threshold 5 × 10⁻⁸; dashed: suggestive threshold 10⁻⁵)')}</figcaption></figure>');
  if (f['qq'] is Map) b.writeln('<figure>${qqSvg(f['qq'] as Map)}<figcaption>${tr('QQ plot des p (bande de confiance à 95 %)', 'QQ plot of p-values (95% confidence band)')}</figcaption></figure>');
  if (f['ldsc'] is Map) {
    final cap = (f['ldsc'] as Map)['cross'] == true
        ? tr('Régression LD score croisée : z₁·z₂ moyen par classe de score LD, droite ajustée (pointillé : 0)', 'Cross-trait LD score regression: mean z₁·z₂ by LD score class, fitted line (dashed: 0)')
        : tr('Régression LD score : χ² moyen par classe de score LD, droite ajustée (pointillé : χ² = 1)', 'LD score regression: mean χ² by LD score class, fitted line (dashed: χ² = 1)');
    b.writeln('<figure>${ldscSvg(f['ldsc'] as Map)}<figcaption>$cap</figcaption></figure>');
  }
  if (f['prs'] is Map) b.writeln('<figure>${prsSvg(f['prs'] as Map)}<figcaption>${tr('Score polygénique : R² de Nagelkerke en validation selon le seuil de p (rouge : seuil retenu ; pointillé : R² sur le test)', 'Polygenic score: Nagelkerke R² in validation by p threshold (red: chosen threshold; dashed: test R²)')}</figcaption></figure>');
  if (f['mr'] is Map) b.writeln('<figure>${mrSvg(f['mr'] as Map)}<figcaption>${tr('Randomisation mendélienne : βY selon βX par variant (barres : ES), droites IVW, MR-Egger et médiane pondérée', 'Mendelian randomization: βY by βX per variant (bars: SE), IVW, MR-Egger and weighted median lines')}</figcaption></figure>');
  if (f['king'] is Map) b.writeln('<figure>${kingSvg(f['king'] as Map)}<figcaption>${tr('Apparentement : φ (KING) selon IBS0, seuils de degré', 'Relatedness: φ (KING) by IBS0, degree thresholds')}</figcaption></figure>');
  if (f['pca'] is Map) b.writeln('<figure>${pcaSvg(f['pca'] as Map)}<figcaption>${tr('ACP des génotypes : sujets selon CP1 et CP2', 'Genotype PCA: subjects by PC1 and PC2')}</figcaption></figure>');
  if (f['standardCurve'] is Map) b.writeln('<figure>${standardCurveSvg(f['standardCurve'] as Map)}<figcaption>${tr('Courbe standard de qPCR', 'qPCR standard curve')}</figcaption></figure>');
  if (f['alignment'] is Map) b.writeln('<figure><pre>${_h('${(f['alignment'] as Map)['text']}')}</pre><figcaption>${tr('Alignement avec', 'Alignment with')} ${_h('${(f['alignment'] as Map)['subject']}')}</figcaption></figure>');
  return b.toString();
}

/// Rapport HTML autonome (s'imprime en PDF depuis n'importe quel navigateur).
String projectReportHtml(Project p, {AuditReport? audit, String generatedAt = ''}) {
  final results = [for (final e in p.journal) (e, analysisResultFromJson(e.result))];
  final q = p.question;
  final b = StringBuffer()
    ..writeln('<!doctype html><html lang="${currentLang.name}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln(tr('<title>${_h(p.title)} — rapport Statoméa</title><style>$_css</style></head><body>', '<title>${_h(p.title)} — Statoméa report</title><style>$_css</style></head><body>'))
    ..writeln(tr('<header><h1>${_h(p.title)}</h1><p class="meta">Rapport généré par Statoméa ($engineName $engineVersion)${generatedAt.isEmpty ? "" : " le ${_h(generatedAt)}"}. Identifiant du projet : ${_h(p.id)}.</p>',
        '<header><h1>${_h(p.title)}</h1><p class="meta">Report generated by Statoméa ($engineName $engineVersion)${generatedAt.isEmpty ? "" : " on ${_h(generatedAt)}"}. Project identifier: ${_h(p.id)}.</p>'))
    ..writeln(p.demoNotice.isEmpty ? '' : '<p class="demo">${_h(p.demoNotice)}</p>')
    ..writeln('<p class="legend"><span class="tag in">${tr('Données saisies', 'Entered data')}</span> <span class="tag calc">${tr('Résultat calculé', 'Computed result')}</span> '
        '<span class="tag interp">${tr('Interprétation proposée', 'Proposed interpretation')}</span> <span class="tag verify">${tr('À vérifier par le chercheur', 'To be checked by the researcher')}</span></p></header>');

  // 1. Données saisies
  b
    ..writeln('<section><h2><span class="tag in">${tr('Données saisies', 'Entered data')}</span> ${tr('Question, plan et données', 'Question, design and data')}</h2><dl>')
    ..writeln('<dt>Question</dt><dd>${_h(q.text.isEmpty ? "—" : q.text)}</dd>')
    ..writeln('<dt>Population</dt><dd>${_h(q.population.isEmpty ? "—" : q.population)}</dd>')
    ..writeln('<dt>${tr('Exposition / intervention', 'Exposure / intervention')}</dt><dd>${_h(q.exposure.isEmpty ? "—" : q.exposure)}</dd>')
    ..writeln('<dt>${tr('Comparateur', 'Comparator')}</dt><dd>${_h(q.comparator.isEmpty ? "—" : q.comparator)}</dd>')
    ..writeln('<dt>${tr('Critère de jugement', 'Outcome')}</dt><dd>${_h(q.outcome.isEmpty ? "—" : q.outcome)}</dd>')
    ..writeln('<dt>Horizon</dt><dd>${_h(q.horizon.isEmpty ? "—" : q.horizon)}</dd>')
    ..writeln('<dt>${tr("Plan d'étude", 'Study design')}</dt><dd>${_h(designLabel(q.design))}</dd>')
    ..writeln('<dt>${tr('Objectif', 'Aim')}</dt><dd>${_h(objectiveLabel(q.objective))}</dd>')
    ..writeln('<dt>${tr("Plan d'analyse", 'Analysis plan')}</dt><dd>${_h(p.analysisPlan.isEmpty ? "—" : p.analysisPlan)}</dd></dl>');
  final ds = p.dataset;
  if (ds != null) {
    b.writeln(tr('<p>Jeu de données : ${_h(ds.source)} — ${ds.rowCount} ligne(s), ${ds.names.length} variable(s), empreinte ${fingerprint(jsonEncode(ds.original))}.</p>',
        '<p>Dataset: ${_h(ds.source)} — ${ds.rowCount} row(s), ${ds.names.length} variable(s), fingerprint ${fingerprint(jsonEncode(ds.original))}.</p>'));
    if (ds.corrections.isNotEmpty) {
      b.writeln(tr("<h3>Corrections journalisées (données d'origine conservées)</h3><ol>", '<h3>Logged corrections (original data kept)</h3><ol>'));
      for (final c in ds.corrections) {
        b.writeln('<li>${_h(c.describe())}${c.author.isEmpty ? "" : " — ${_h(c.author)}"}${c.timestamp.isEmpty ? "" : ", ${_h(c.timestamp)}"}</li>');
      }
      b.writeln('</ol>');
    } else {
      b.writeln(tr('<p>Aucune correction appliquée aux données importées.</p>', '<p>No correction applied to the imported data.</p>'));
    }
  }
  if (p.studies.isNotEmpty) {
    b.writeln(tr("<h3>Tableau d'extraction (métaanalyse)</h3><table><thead><tr><th>Étude</th><th>Valeur</th><th>Donnée</th><th>Statut</th><th>Source</th></tr></thead><tbody>",
        '<h3>Extraction table (meta-analysis)</h3><table><thead><tr><th>Study</th><th>Value</th><th>Datum</th><th>Status</th><th>Source</th></tr></thead><tbody>'));
    for (final s in p.studies) {
      for (final e in s.values.entries) {
        b.writeln('<tr><td>${_h(s.label)}</td><td>${_h(e.key)}</td><td>${e.value.value ?? "—"}</td><td>${_h(_provLabel(e.value.provenance.name))}</td><td>${_h(e.value.source)}</td></tr>');
      }
    }
    b.writeln('</tbody></table>');
  }
  b.writeln('</section>');

  // 2–4. Analyses
  for (final (e, r) in results) {
    final info = methodInfo(r.methodId);
    b
      ..writeln('<section class="analysis"><h2>${_h(r.methodName)}</h2>')
      ..writeln('<p class="meta">${tr('Calcul', 'Computation')} ${_h(e.id)} — ${_h(e.timestamp)} — ${tr('moteur', 'engine')} ${_h(e.result['engineVersion']?.toString() ?? engineVersion)}'
          '${e.datasetFingerprint.isEmpty ? "" : " — ${tr('données', 'data')} ${_h(e.datasetFingerprint)}"}'
          '${e.correctionIds.isEmpty ? "" : " — corrections ${_h(e.correctionIds.join(', '))}"}'
          '${info == null ? "" : " — validation${tr(' : ', ': ')}${_h(info.reference)}"}</p>');
    if (r.status != MethodStatus.validated) {
      b.writeln(tr("<p class=\"danger\">MÉTHODE EN DÉVELOPPEMENT : ce résultat n'est pas présenté comme fiable.</p>", '<p class="danger">METHOD IN DEVELOPMENT: this result is not presented as reliable.</p>'));
    }
    if (r.status == MethodStatus.validated && !r.reliable) {
      b.writeln(tr('<p class="danger">RÉSULTAT NON RAPPORTABLE : alerte bloquante (voir « À vérifier »). Les estimations ci-dessous sont conservées pour la traçabilité et ne doivent pas être citées.</p>',
          '<p class="danger">RESULT NOT REPORTABLE: blocking alert (see "To be checked"). The estimates below are kept for traceability and must not be cited.</p>'));
    }
    b
      ..writeln('<h3><span class="tag calc">${tr('Résultat calculé', 'Computed result')}</span></h3>')
      ..writeln('<p class="formula">${_h(r.formula)}</p>');
    for (final t in r.tables) {
      b.writeln(_table(t));
    }
    if (r.estimates.isNotEmpty) {
      b.writeln(_table(ResultTable(tr('Estimations', 'Estimates'), [tr('Mesure', 'Measure'), tr('Estimation', 'Estimate'), tr('Intervalle', 'Interval'), 'p'], [
        for (final x in r.estimates)
          [
            x.label,
            fmt(x.value),
            x.hasInterval
                ? tr('${x.intervalKind} ${(x.level * 100).round()} % : ${fmt(x.lower)} à ${fmt(x.upper)}', '${(x.level * 100).round()}% ${intervalName(x.intervalKind)}: ${fmt(x.lower)} to ${fmt(x.upper)}')
                : '—',
            fmtP(x.pValue)
          ]
      ])));
    }
    b.writeln(_figures(r));
    if (r.checks.isNotEmpty) {
      b.writeln(_table(ResultTable(tr('Hypothèses et diagnostics', 'Assumptions and diagnostics'), ['Condition', tr('Statut', 'Status'), tr('Détail', 'Detail')],
          [for (final c in r.checks) [c.label, checkStatusLabel(c.status), c.detail]])));
    }
    b
      ..writeln('<h3><span class="tag interp">${tr('Interprétation proposée', 'Proposed interpretation')}</span></h3><dl>')
      ..writeln('<dt>${tr('Pourquoi cette méthode ?', 'Why this method?')}</dt><dd>${_h(r.interpretation.whyThisMethod)}</dd>')
      ..writeln('<dt>${tr('Que signifie le résultat ?', 'What does the result mean?')}</dt><dd>${_h(r.interpretation.whatItMeans)}</dd>')
      ..writeln('<dt>${tr('Quelles conclusions restent injustifiées ?', 'Which conclusions remain unjustified?')}</dt><dd>${_h(r.interpretation.notJustified)}</dd></dl>');
    final pts = pointsToVerify(r);
    b.writeln('<h3><span class="tag verify">${tr('À vérifier par le chercheur', 'To be checked by the researcher')}</span></h3><ul>');
    for (final x in pts.isEmpty
        ? [tr('Aucun point signalé par le moteur ; la pertinence clinique et le plan restent à juger.', 'No point flagged by the engine; clinical relevance and the design remain to be judged.')]
        : pts) {
      b.writeln('<li>${_h(x)}</li>');
    }
    b.writeln('</ul>');
    if (r.log.isNotEmpty) {
      b.writeln('<details><summary>${tr('Journal de calcul', 'Computation log')}</summary><pre>${_h(r.log.join("\n"))}</pre></details>');
    }
    if (e.userNote.isNotEmpty) b.writeln(tr('<p><em>Note du chercheur :</em> ${_h(e.userNote)}</p>', "<p><em>Researcher's note:</em> ${_h(e.userNote)}</p>"));
    b.writeln('</section>');
  }

  if (p.resultsText.trim().isNotEmpty) {
    b.writeln('<section><h2><span class="tag in">${tr('Données saisies', 'Entered data')}</span> ${tr('Texte de résultats rédigé par le chercheur', 'Results text written by the researcher')}</h2><blockquote>${_h(p.resultsText).replaceAll("\n", "<br>")}</blockquote></section>');
  }
  if (audit != null) {
    b.writeln('<section><h2><span class="tag verify">${tr('À vérifier par le chercheur', 'To be checked by the researcher')}</span> ${tr('Audit contradictoire', 'Adversarial audit')}</h2>'
        '<p class="meta">${tr('Les constats marqués « lexical » reposent sur un repérage de formulations et peuvent être des faux positifs.', 'Findings marked "lexical" rest on wording detection and may be false positives.')}</p>');
    b.writeln(_table(ResultTable(tr('Constats', 'Findings'),
        [tr('Contrôle', 'Check'), tr('Statut', 'Status'), tr('Gravité', 'Severity'), tr('Constat', 'Finding'), tr('Élément déclencheur', 'Trigger'), tr('Correction proposée', 'Proposed correction')], [
      for (final f in audit.findings)
        [
          auditFamilyLabel(f.family),
          auditStatusLabel(f.status),
          f.status == AuditStatus.alert ? severityLabel(f.severity) : '—',
          '${f.message}${f.lexical ? " (lexical)" : ""}',
          f.trigger ?? '—',
          f.correction ?? '—',
        ]
    ])));
    b.writeln('</section>');
  }
  b.writeln(tr("<footer><p>Statoméa sépare le moteur de calcul déterministe des interprétations, qui sont des propositions à relire. Aucun résultat n'a été produit par une IA générative.</p>",
      '<footer><p>Statoméa separates the deterministic computation engine from the interpretations, which are proposals to be reread. No result was produced by generative AI.</p>'));
  b.writeln('<p><b>&#9888; ${_h(disclaimerTitle)} — ${_h(disclaimerLead)}</b> ${_h(disclaimerText)}</p><p>${_h(designedBy)}</p></footer></body></html>');
  return b.toString();
}

String _provLabel(String p) => switch (p) {
      'reported' => tr('rapportée', 'reported'),
      'recalculated' => tr('recalculée', 'recalculated'),
      'assumed' => tr('hypothèse', 'assumption'),
      _ => p
    };

/// Statut d'un constat d'audit.
String auditStatusLabel(AuditStatus s) => switch (s) {
      AuditStatus.alert => tr('alerte', 'alert'),
      AuditStatus.ok => tr('conforme', 'compliant'),
      AuditStatus.insufficient => tr('information insuffisante', 'insufficient information'),
    };

/// Journal de calcul complet (reproductibilité).
String journalJson(Project p) => const JsonEncoder.withIndent('  ').convert({
      'format': 'statomea-journal',
      'engine': '$engineName $engineVersion',
      'project': p.id,
      'title': p.title,
      'question': p.question.toJson(),
      'dataset': p.dataset == null
          ? null
          : {
              'source': p.dataset!.source,
              'rows': p.dataset!.rowCount,
              'fingerprint': fingerprint(jsonEncode(p.dataset!.original)),
              'corrections': [for (final c in p.dataset!.corrections) c.toJson()],
            },
      'entries': [for (final e in p.journal) e.toJson()],
    });

const _css = '''
body{font-family:Helvetica,Arial,sans-serif;max-width:900px;margin:24px auto;padding:0 16px;color:#1a1a1a;line-height:1.45}
h1{font-size:1.6em;margin-bottom:4px}h2{font-size:1.25em;border-bottom:1px solid #ccc;padding-bottom:4px;margin-top:32px}
h3{font-size:1.05em;margin-top:18px}.meta{color:#555;font-size:.85em}.formula{font-family:Menlo,Consolas,monospace;font-size:.85em;background:#f5f5f5;padding:8px;border-radius:4px}
table{border-collapse:collapse;width:100%;margin:10px 0;font-size:.88em}caption{text-align:left;font-weight:bold;padding:4px 0}
th,td{border:1px solid #ccc;padding:4px 6px;text-align:left;vertical-align:top}th{background:#eef2f7}
.tag{display:inline-block;font-size:.72em;padding:2px 6px;border-radius:3px;color:#fff;vertical-align:middle}
.tag.in{background:#5a6b7d}.tag.calc{background:#1f4e79}.tag.interp{background:#7a5c00}.tag.verify{background:#a33}
.danger{background:#fde8e8;border:1px solid #a33;padding:8px;font-weight:bold}.demo{background:#fff5d6;border:1px solid #c9a227;padding:8px}
figure{margin:12px 0;overflow-x:auto}figcaption{font-size:.85em;color:#555}dt{font-weight:bold;margin-top:6px}dd{margin-left:0}
blockquote{border-left:3px solid #ccc;margin:8px 0;padding:4px 12px;color:#333}
@media print{details{display:block}section{page-break-inside:auto}h2{page-break-after:avoid}}
''';
