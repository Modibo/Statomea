/// Briques partagées par les analyses fondamentales : interprétation de
/// l'intervalle de confiance (absence de preuve ≠ preuve d'absence).
library;

import '../i18n.dart';
import '../model/result.dart';

/// Lecture d'un intervalle de confiance par rapport à la valeur nulle et,
/// si l'utilisateur l'a fixée, à une marge cliniquement pertinente.
///
/// [margin] est exprimée sur la même échelle que l'estimation : écart absolu
/// pour une différence, rapport (> 1) pour un ratio (la zone d'équivalence est
/// alors [1/margin, margin]).
String readInterval(Estimate e, {required double nullValue, bool ratio = false, double? margin, String unit = ''}) {
  if (!e.hasInterval) return tr('Intervalle non disponible : aucune conclusion inférentielle.', 'Interval not available: no inferential conclusion.');
  final lo = e.lower!, hi = e.upper!;
  final pct = (e.level * 100).round();
  final excludesNull = lo > nullValue || hi < nullValue;
  final buf = StringBuffer();
  if (excludesNull) {
    buf.write(tr(
        "L'IC à $pct % exclut la valeur nulle (${fmt(nullValue)}) : les données sont peu compatibles avec une absence de différence, sous les hypothèses du modèle. ",
        'The $pct% CI excludes the null value (${fmt(nullValue)}): the data are hardly compatible with no difference, under the model assumptions. '));
  } else {
    buf.write(tr(
        "L'IC à $pct % contient la valeur nulle (${fmt(nullValue)}) : les données ne permettent pas d'exclure une absence de différence. "
            "Ce n'est PAS une preuve d'absence d'effet (absence de preuve). ",
        'The $pct% CI contains the null value (${fmt(nullValue)}): the data cannot rule out no difference. '
            'This is NOT evidence of no effect (absence of evidence). '));
  }
  if (margin == null) {
    if (!excludesNull) {
      buf.write(tr(
          "Sans marge cliniquement pertinente fixée, l'application ne peut pas conclure à l'équivalence ; l'intervalle va de ${fmt(lo)}$unit à ${fmt(hi)}$unit, "
              'et toutes ces valeurs restent compatibles avec les données.',
          'Without a pre-specified clinically relevant margin, equivalence cannot be concluded; the interval runs from ${fmt(lo)}$unit to ${fmt(hi)}$unit, '
              'and all these values remain compatible with the data.'));
    }
    return buf.toString();
  }
  final mLo = ratio ? 1 / margin : nullValue - margin;
  final mHi = ratio ? margin : nullValue + margin;
  if (lo >= mLo && hi <= mHi) {
    buf.write(tr(
        "L'IC entier est compris dans la zone d'équivalence [${fmt(mLo)} ; ${fmt(mHi)}] : les données soutiennent une absence de différence "
            "cliniquement pertinente (preuve d'absence, au sens de la marge choisie).",
        'The whole CI lies within the equivalence zone [${fmt(mLo)}; ${fmt(mHi)}]: the data support the absence of a clinically relevant '
            'difference (evidence of absence, for the chosen margin).'));
  } else if (hi < mLo || lo > mHi) {
    buf.write(tr("L'IC est entièrement au-delà de la marge cliniquement pertinente : la différence est vraisemblablement d'ampleur clinique.",
        'The CI lies entirely beyond the clinically relevant margin: the difference is likely of clinical magnitude.'));
  } else {
    buf.write(tr(
        "L'IC chevauche la limite de la marge cliniquement pertinente (${fmt(mLo)} ; ${fmt(mHi)}) : la précision est insuffisante pour conclure sur la pertinence clinique.",
        'The CI overlaps the clinically relevant margin (${fmt(mLo)}; ${fmt(mHi)}): precision is insufficient to conclude on clinical relevance.'));
  }
  return buf.toString();
}

/// Phrase standard rappelant ce que n'est pas une valeur de p.
String get pValueCaveat => tr(
    "La valeur de p est la probabilité d'observer des données au moins aussi extrêmes si l'hypothèse nulle et toutes les hypothèses du modèle "
        "étaient vraies ; ce n'est pas la probabilité que l'hypothèse nulle soit vraie, ni une mesure de l'importance de l'effet.",
    'The p-value is the probability of observing data at least as extreme if the null hypothesis and all model assumptions were true; '
        'it is not the probability that the null hypothesis is true, nor a measure of the size of the effect.');

List<double> finiteValues(List<double?> xs) => [for (final x in xs) if (x != null && x.isFinite) x];
