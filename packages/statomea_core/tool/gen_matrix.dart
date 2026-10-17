// Génère docs/02-matrice-methodes.md depuis le registre des méthodes.
// Usage : dart run tool/gen_matrix.dart > ../../docs/02-matrice-methodes.md
import 'package:statomea_core/statomea_core.dart';

void main() {
  print('# 02 — Matrice « question → données requises → méthode → conditions → diagnostics → résultat »\n');
  print('Générée automatiquement depuis le registre du moteur (`lib/src/advisor/registry.dart`, $engineName $engineVersion) : '
      'elle ne peut pas diverger du code. L\'assistant de choix (`advisor.dart`) n\'utilise que les caractéristiques déclarées '
      'de la question ; il demande les informations manquantes au lieu de supposer.\n');
  print(methodMatrixMarkdown());
  print('\n## Règles de l\'assistant (résumé)\n');
  print('''- Objectif, niveau des données et type d'issue inconnus → questions, aucune recommandation.
- Données agrégées d'études → métaanalyse (binaire : OR/RR/DR ; continue : DM/DMS).
- Accord entre deux méthodes → Bland-Altman (jamais une corrélation) ; Passing-Bablok et Deming en complément (biais constant et proportionnel, biais aux niveaux de décision).
- Descriptif binaire → proportion avec IC de Wilson/exact ; règle de trois si zéro événement.
- Diagnostique → performance contre une référence (demande si la référence est appliquée à tous).
- Prédictif binaire → atelier de prédiction (exige population, horizon, usage) ; risques prédits déjà disponibles → calibration (Hosmer-Lemeshow, courbe lissée).
- Explicatif : plan, type d'exposition, appariement et besoin d'ajustement demandés ;
  - binaire apparié → McNemar ; binaire brut → 2 × 2 ; ajusté en cohorte/essai/transversal → Poisson robuste (RR/RP) recommandé, logistique en alternative ; cas-témoins → logistique seule ; peu d'événements → Firth proposé ;
  - continu apparié → t apparié / Wilcoxon ; deux groupes → Welch / Mann-Whitney (question sur la normalité si inconnue) ; k groupes → ANOVA / Kruskal-Wallis ; ajusté → régression linéaire ;
  - traitement binaire en cohorte ou transversal, ajustement → score de propension (appariement, IPTW) proposé en alternative ; exposition continue → rappel des splines cubiques restreintes plutôt que des classes ;
  - délai avec censure → Kaplan-Meier et log-rank (brut), Cox (ajusté) ; l'assistant demande s'il existe un événement concurrent (→ incidence cumulée, test de Gray, Fine-Gray) et si l'exposition change pendant le suivi (→ covariable dépendant du temps, contre le biais du temps immortel) ;
  - mesures répétées → modèle linéaire mixte (quantitative) ou GEE (binaire, comptage) ; comptage → Poisson / binomiale négative (offset) ; issue ordinale ajustée → cotes proportionnelles ; issue nominale ajustée → multinomiale.''');
}
