/// Plan d'étude et objectif : conditionnent les mesures légitimes.
library;

import '../i18n.dart';

enum StudyDesign {
  rct,
  cohort,
  crossSectional,
  caseControl,
  diagnosticAccuracy,
  systematicReview,
  unknown,
}

enum StudyObjective { descriptive, explanatory, diagnostic, predictive, unknown }

String designLabel(StudyDesign d) => switch (d) {
      StudyDesign.rct => tr('essai contrôlé randomisé', 'randomized controlled trial'),
      StudyDesign.cohort => tr('étude de cohorte', 'cohort study'),
      StudyDesign.crossSectional => tr('étude transversale', 'cross-sectional study'),
      StudyDesign.caseControl => tr('étude cas-témoins', 'case-control study'),
      StudyDesign.diagnosticAccuracy => tr('étude de performance diagnostique', 'diagnostic accuracy study'),
      StudyDesign.systematicReview => tr('revue systématique / métaanalyse', 'systematic review / meta-analysis'),
      StudyDesign.unknown => tr('plan non précisé', 'design not specified'),
    };

String objectiveLabel(StudyObjective o) => switch (o) {
      StudyObjective.descriptive => tr('descriptif', 'descriptive'),
      StudyObjective.explanatory => tr('explicatif (étiologique)', 'explanatory (etiological)'),
      StudyObjective.diagnostic => tr('diagnostique', 'diagnostic'),
      StudyObjective.predictive => tr('prédictif (pronostique)', 'predictive (prognostic)'),
      StudyObjective.unknown => tr('non précisé', 'not specified'),
    };

/// Nom de la mesure de fréquence relative selon le plan.
String ratioMeasureName(StudyDesign d) => switch (d) {
      StudyDesign.crossSectional => tr('Rapport de prévalences', 'Prevalence ratio'),
      StudyDesign.caseControl => tr('(non estimable en cas-témoins)', '(not estimable in a case-control study)'),
      _ => tr('Risque relatif', 'Risk ratio'),
    };

/// Le plan permet-il d'estimer un risque (ou une prévalence) directement ?
bool designAllowsRisk(StudyDesign d) =>
    d == StudyDesign.rct || d == StudyDesign.cohort || d == StudyDesign.crossSectional;
