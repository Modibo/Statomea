/// « Tableau 2 » : associations brutes et ajustées. Chaque variable est d'abord estimée seule avec l'issue (modèle
/// univariable, sur ses observations complètes), puis toutes ensemble (modèle multivariable, observations complètes de
/// l'ensemble) : OR (logistique), RP/RR (Poisson robuste) ou différence de moyennes β (linéaire), avec IC et p. Les
/// estimations sont celles des régressions du moteur, validées contre R.
library;

import '../data/dataset.dart';
import '../i18n.dart';
import '../model/design.dart';
import '../model/result.dart';
import 'design_matrix.dart';
import 'glm.dart';
import 'linear.dart';

/// Modèle du tableau : 'logistic', 'poisson' ou 'linear'.
AnalysisResult associationTable(Dataset ds, ModelFormula f, {String model = 'logistic', StudyDesign design = StudyDesign.unknown}) {
  if (f.terms.isEmpty) throw StatInputError('missing', tr('Choisir au moins une variable explicative.', 'Choose at least one explanatory variable.'));
  final binary = model != 'linear';
  AnalysisResult fit(ModelFormula g) {
    final d = buildDesign(ds, g, binaryOutcome: binary);
    return switch (model) {
      'linear' => linearRegression(d, unit: ds.dictionary[g.outcome]?.unit ?? ''),
      'poisson' => poissonRobustRegression(d, design: design),
      _ => logisticRegression(d, design: design),
    };
  }

  List<Estimate> terms(AnalysisResult r) => model == 'linear' ? r.estimates.skip(1).toList() : r.estimates;
  final adjusted = fit(f);
  final crude = <String, Estimate>{};
  final crudeN = <String, int>{};
  for (final t in f.terms) {
    final r = fit(ModelFormula(f.outcome, [t], eventLevel: f.eventLevel));
    for (final e in terms(r)) {
      crude[e.label] = e;
      crudeN[e.label] = (r.statistics['n'] ?? 0).round();
    }
  }
  final measure = switch (model) {
    'linear' => tr('β (différence)', 'β (difference)'),
    'poisson' => design == StudyDesign.crossSectional ? tr('RP', 'PR') : 'RR',
    _ => 'OR',
  };
  String strip(String label) => label.replaceFirst(RegExp(r'^(OR|RP|RR|PR) — '), '');
  String ci(Estimate e) => e.lower == null || e.upper == null ? '—' : '${fmt(e.value)} (${fmt(e.lower!)} – ${fmt(e.upper!)})';
  String pv(double? p) => p == null ? '—' : (p < 0.001 ? tr('< 0,001', '< 0.001') : fmtFixed(p, p < 0.01 ? 3 : 2));
  final rows = <List<String>>[
    for (final e in terms(adjusted))
      [strip(e.label), crude[e.label] == null ? '—' : ci(crude[e.label]!), pv(crude[e.label]?.pValue), ci(e), pv(e.pValue)],
  ];
  final nAdj = (adjusted.statistics['n'] ?? 0).round();
  final level = adjusted.estimates.isEmpty ? 95 : (adjusted.estimates.first.level * 100).round();
  final header = [
    tr('Variable', 'Variable'),
    tr('$measure brut (IC $level %)', 'Crude $measure ($level% CI)'),
    'p',
    tr('$measure ajusté (IC $level %)', 'Adjusted $measure ($level% CI)'),
    'p',
  ];
  final nMin = crudeN.values.isEmpty ? nAdj : crudeN.values.reduce((a, b) => a < b ? a : b);
  final nMax = crudeN.values.isEmpty ? nAdj : crudeN.values.reduce((a, b) => a > b ? a : b);
  final notes = [
    tr('Brut : chaque variable seule avec « ${f.outcome} » (n = ${nMin == nMax ? '$nMin' : '$nMin à $nMax'}). Ajusté : toutes les variables du tableau ensemble (n = $nAdj, observations complètes).',
        'Crude: each variable alone with "${f.outcome}" (n = ${nMin == nMax ? '$nMin' : '$nMin to $nMax'}). Adjusted: all variables in the table together (n = $nAdj, complete cases).'),
    if (model == 'logistic' && design == StudyDesign.cohort)
      tr('Issue fréquente en cohorte : l\'OR surestime le RR ; préférer la régression de Poisson robuste.', 'Common outcome in a cohort: the OR overstates the RR; prefer robust Poisson regression.'),
  ];
  return AnalysisResult(
    methodId: 'association_table',
    methodName: tr('Tableau 2 : associations brutes et ajustées', 'Table 2: crude and adjusted associations'),
    inputs: {'model': model, 'formula': f.toJson(), 'design': design.name},
    formula: tr('Pour chaque variable : modèle univariable (brut), puis modèle multivariable avec toutes les variables (ajusté) ; ${adjusted.formula}', 'For each variable: univariable model (crude), then multivariable model with all variables (adjusted); ${adjusted.formula}'),
    estimates: terms(adjusted),
    statistics: {'n': nAdj.toDouble()},
    checks: adjusted.checks,
    alerts: [...adjusted.alerts, for (final n in notes) Alert('association_table_note', Severity.info, n)],
    tables: [ResultTable(tr('Tableau 2. Facteurs associés à « ${f.outcome} » : analyses brutes et ajustées', 'Table 2. Factors associated with "${f.outcome}": crude and adjusted analyses'), header, rows)],
    interpretation: Interpretation(
      whyThisMethod: tr('Montrer, pour chaque facteur, l\'association brute et l\'association ajustée sur les autres facteurs du tableau.', 'Show, for each factor, the crude association and the association adjusted for the other factors in the table.'),
      whatItMeans: tr('L\'écart entre brut et ajusté indique la part de l\'association expliquée par les autres variables (confusion).', 'The gap between crude and adjusted shows how much of the association is explained by the other variables (confounding).'),
      notJustified: tr('Interpréter chaque OR ajusté comme un effet causal (« sophisme du Tableau 2 ») : seul l\'effet de l\'exposition principale, ajusté sur ses facteurs de confusion, est interprétable.',
          'Interpreting every adjusted OR as a causal effect (the "Table 2 fallacy"): only the main exposure\'s effect, adjusted for its confounders, is interpretable.'),
    ),
  );
}
