# 00 — Analyse critique du cahier des charges et périmètre de la V1

Ce document précède toute ligne de code. Il relève ce qui, dans le cahier des charges initial,
est contradictoire, ambigu, invérifiable ou irréaliste, et fixe en conséquence un périmètre de
première version **dont chaque élément peut être testé**.

## 1. Incohérences internes

| # | Constat | Conséquence | Décision |
|---|---------|-------------|----------|
| I1 | §4 renvoie aux analyses « définies dans le cahier des charges », mais aucune liste n'y figure. | Le périmètre « fondamental » est indéterminé, donc invérifiable. | Liste fermée fixée au §5 ci-dessous ; tout ce qui n'y est pas est hors V1. |
| I2 | §5 place Firth dans l'atelier de régression ; §12 le range parmi les modules avancés. | Statut ambigu. | Firth est implémenté et validé contre `logistf` : estimations, IC par vraisemblance profilée pénalisée et p du rapport de vraisemblance pénalisé (ajoutés à l'étape 2 de réalisation), IC de Wald en comparaison. |
| I3 | §5 inclut la régression de Poisson à variance robuste ; §12 ne cite que « linéaire et logistique ». | Sans elle, aucun RR ajusté n'est estimable en cohorte ou transversal (risque d'OR présenté comme RR, précisément ce que l'audit §9 doit détecter). | Incluse en V1. |
| I4 | §9 veut détecter « une limite d'accord confondue avec un IC », mais §4 ne prévoit pas d'analyse d'accord. | L'audit testerait une notion absente du moteur. | Bland-Altman ajouté en V1 (limites d'accord **et** IC de ces limites). |
| I5 | §10 sépare moteur déterministe et assistant IA ; §1 exige que les leçons et calculs fonctionnent hors connexion. | Un assistant génératif exige une connexion, un fournisseur, un coût et fait sortir des données de l'appareil. | V1 sans IA générative : les interprétations sont produites par des gabarits déterministes, versionnés et testés. Un point d'extension documenté (§ architecture) n'accepte en entrée que le résultat JSON du moteur et ne peut modifier aucun nombre. |
| I6 | §7 demande de « séparer rigoureusement » développement / validation interne / validation externe, et §12 de livrer « développement et validation interne ». | Le partage aléatoire d'un même échantillon est souvent présenté comme une validation « externe » ; c'est une validation interne inefficace. | Validation interne par bootstrap (correction d'optimisme de Harrell) ; le partage aléatoire n'est pas proposé. Toute validation externe est hors V1 et l'application le dit. |
| I7 | §11 exige une validation chiffrée de **chaque** fonctionnalité, y compris l'audit textuel (§9). | Un détecteur de formulations en langue naturelle n'a pas de « valeur de référence » logicielle. | Pour l'audit, le critère d'acceptation porte sur un corpus de phrases annotées (vrais positifs, vrais négatifs attendus), pas sur une exhaustivité impossible. |

## 2. Fonctionnalités irréalistes ou invérifiables telles qu'écrites

1. **Audit sémantique exhaustif du texte libre** (§9). Repérer « une conclusion causale tirée d'une
   simple association » dans n'importe quelle rédaction française relève de la compréhension du
   langage, non d'un calcul. *Réaliste* : (a) contrôles **structurés** fiables, croisant le plan
   d'étude déclaré et le journal des analyses (OR calculé mais « risque » écrit, cas-témoins et
   prévalence annoncée…) ; (b) **lexique** de formulations à risque (« prouve », « entraîne »,
   « p = probabilité que… ») qui signale, montre le passage déclencheur et propose une correction,
   en acceptant des faux positifs. L'audit renvoie « information insuffisante » quand le plan ou
   l'analyse n'est pas renseigné.
2. **« Vérifier la compatibilité des populations, comparateurs, critères… » en métaanalyse** (§6).
   Aucun algorithme ne juge la comparabilité clinique de deux essais. *Réaliste* : une grille
   obligatoire que l'utilisateur remplit étude par étude ; le moteur bloque seulement ce qui est
   vérifiable (mesures d'effet hétérogènes, sens de l'effet incohérent, unités différentes pour une
   DM, données insuffisantes).
3. **« Unités incohérentes » à l'import CSV** (§3). Un CSV ne porte pas d'unités. *Réaliste* : un
   dictionnaire de variables (unité, bornes plausibles, rôle) que l'utilisateur déclare ; le moteur
   signale les valeurs hors bornes et les distributions bimodales évocatrices d'un mélange d'unités
   (p. ex. glycémie en mmol/L et en mg/dL), en tant que **suspicions**, jamais en corrections.
4. **« Distinguer absence de preuve et preuve d'absence »** (§4) n'est possible que si l'utilisateur
   fixe une marge cliniquement pertinente. Sans marge, l'application dit qu'elle ne peut conclure
   à l'absence d'effet.
5. **Applications natives Android et iOS** (§1). Le poste de développement n'a pas de SDK Android
   ni de Xcode complet. *Réaliste* : base de code Flutter unique ; la version web est construite et
   testée ici ; les paquets Android/iOS sont décrits mais **non construits ni testés** sur ce poste.
6. **« Comparer chaque calcul à des logiciels reconnus »** (§11) pour le bootstrap : deux logiciels
   n'ont pas le même générateur aléatoire. *Réaliste* : les indices de rééchantillonnage sont
   produits par R et rejoués à l'identique par le moteur Dart ; l'égalité est alors exacte.
7. **TRIPOD+AI, PROBAST+AI, PRISMA** (§6–7). Les listes officielles sont des textes publiés ;
   l'application en propose une **paraphrase** structurée pour guider la rédaction et renvoie au
   texte original, sans prétendre s'y substituer. Les grilles ne mesurent pas la qualité
   méthodologique (PRISMA = qualité du rapport).
8. **Données des démonstrations** (§12.7). Aucune donnée réelle n'est fournie. La métaanalyse
   utilise un jeu publié et public (essais du BCG, Colditz 1994, `metafor::dat.bcg`). L'AgHBs et le
   modèle cardiométabolique reposent sur des **données simulées**, déclarées comme telles dans
   l'application et les exports, avec la graine et le script de simulation.

## 3. Ambiguïtés que l'application doit transformer en questions

- « Petit nombre d'événements » : seuil non défini. Retenu : événements par paramètre (EPV) < 10
  ⇒ alerte ; < 5 ⇒ alerte forte ; séparation détectée ⇒ estimation de maximum de vraisemblance
  refusée, Firth proposé. Ces seuils sont des repères, pas des règles (Riley 2019 propose un calcul
  de taille d'échantillon spécifique) ; l'application l'explique.
- Poisson robuste « lorsque son usage est approprié » : issue binaire, plan de cohorte, essai ou
  transversal, objectif = RR/RP. Refusé en cas-témoins.
- Données manquantes : la V1 fait de l'analyse en cas complets **documentée** (effectifs exclus par
  variable, comparaison inclus/exclus). L'imputation multiple (MICE, règles de Rubin), ajoutée en 1.7.0,
  est proposée en option sous l'hypothèse MAR ; elle est refaite dans chaque réplique bootstrap pour
  la validation interne d'un modèle de prédiction.

## 4. Principes de vérifiabilité retenus

1. **Registre des méthodes** : chaque méthode a un statut (`validée`, `en développement`). Une
   méthode non validée ne produit pas de résultat présenté comme fiable : bandeau rouge, export
   marqué, audit en alerte.
2. **Moteur pur** (`statomea_core`, Dart sans Flutter) : entrées → résultat + hypothèses +
   diagnostics + avertissements + journal. Aucun état caché, aucune horloge, aléa uniquement par
   graine ou indices fournis.
3. **Valeurs de référence produites par R** (scripts versionnés dans `validation/r/`), comparées
   par tests automatiques avec des tolérances écrites.
4. **Données importées immuables** : toute correction est une opération journalisée appliquée à une
   copie (qui, quoi, pourquoi, nombre de valeurs touchées).

## 5. Périmètre de la V1 (liste fermée)

**Projets** : création, parcours en 10 étapes, stockage local, suppression complète.

**Données** : saisie manuelle, import CSV (séparateur `,` ou `;`, décimale `.` ou `,`), aperçu,
dictionnaire de variables, contrôles (types, doublons, manquants, hors bornes, mélange d'unités
suspect, catégories de référence, cellules nulles / effectifs faibles, données appariées ou de
suivi mal structurées), journal des corrections.

**Assistant de choix** : questions PICO/plan → options avec conditions, ou demande de précision.

**Analyses fondamentales** :
- descriptives (moyenne, ÉT, médiane, quartiles, min–max, effectifs) ;
- IC d'une proportion (Wilson, Clopper-Pearson exact, règle de trois pour 0 événement) ;
- IC d'une moyenne (t), d'une différence de proportions (Newcombe) ;
- 2 × 2 : RR, OR, DR (IC), χ² de Pearson, test exact de Fisher, correction de Haldane si cellule nulle ;
- performance diagnostique : Se, Sp, VPP, VPN (IC de Wilson), RV+, RV−, prévalence ;
- comparaisons de groupes : t de Student et de Welch, Mann-Whitney, ANOVA à un facteur, Kruskal-Wallis, χ² r × c ;
- appariées : t apparié, Wilcoxon signé, McNemar (exact et asymptotique) ;
- corrélations : Pearson (IC par transformation de Fisher), Spearman ;
- accord : Bland-Altman (biais, limites d'accord, IC des limites) ;
- tailles d'échantillon : estimation d'une proportion, comparaison de deux proportions, de deux moyennes.

**Régressions** : linéaire (MCO, VIF, levier, distance de Cook, résidus), logistique binaire (IRLS,
convergence, détection de séparation, EPV), Poisson à variance robuste (sandwich HC0), Firth
(estimations, IC profilés pénalisés, test du RV pénalisé).

**Métaanalyse** : issues binaires (log OR, log RR, DR ; inverse-variance et Mantel-Haenszel pour
OR/RR), continues (DM, DMS de Hedges) ; effets fixes et aléatoires (DerSimonian-Laird, REML),
Q, I², τ², intervalle de prédiction, forest plot, sensibilité « leave-one-out », sous-groupes ;
traçabilité de chaque valeur (rapportée / recalculée / hypothèse).

**Modèle de prédiction binaire** : spécification (population, issue, horizon, usage), prédicteurs
pré-spécifiés (pas de sélection automatique en V1), AUC (IC DeLong), comparaison d'AUC appariées
(DeLong), Brier, pente et intercept de calibration, courbe de calibration par déciles, validation
interne par bootstrap avec correction d'optimisme, courbe de décision (bénéfice net), grilles
TRIPOD+AI et PROBAST+AI (paraphrasées).

**Formation** : une leçon par méthode (niveau, exemple chiffré, exercice corrigé, erreurs
fréquentes, lien vers le calcul), plus les leçons transversales demandées ; trois questions après
chaque calcul.

**Audit contradictoire** : 8 familles de contrôles, gravité, déclencheur, correction, « information
insuffisante ».

**Exports** : CSV des tableaux, journal de calcul JSON, rapport imprimable/PDF où sont séparés
données saisies, résultats calculés, interprétations proposées et points à vérifier.

**Hors V1** : assistant IA, version anglaise
complète (l'architecture de traduction est en place, les chaînes ne sont pas traduites).
