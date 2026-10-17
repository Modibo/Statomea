# 05 — Jeux de tests et rapport de validation

**Moteur** : statomea_core 1.36.0 — **Date** : 12 octobre 2026 — **Résultat** : 449 tests du moteur (dont 12 en anglais) et
54 tests de l'application passent (dont 6 d'accessibilité, 1 test de captures ignoré par défaut) ; 16 captures de maquettes générées sans débordement.

## 1. Méthode de validation

1. Pour chaque méthode, un script R versionné (`validation/r/0*.R`, graines fixées) calcule les
   valeurs de référence avec des logiciels reconnus et les écrit en JSON dans
   `packages/statomea_core/test/reference/`.
2. Les tests Dart rejouent les mêmes entrées et comparent avec une **tolérance écrite** dans le test.
3. Pour le bootstrap, les indices de rééchantillonnage sont produits par R et rejoués à l'identique
   par le moteur : la comparaison est exacte (aux erreurs d'arrondi près), et non « à l'erreur de
   Monte-Carlo près ».
4. Les écarts sont examinés : erreur du moteur → corrigée ; imprécision du logiciel de référence →
   référence de haute précision ajoutée et écart documenté.

Environnement de référence : R 4.x (macOS), jsonlite, metafor 4.x, logistf 1.26.0, pROC, sandwich,
car, pmsampsize (versions inscrites dans le champ `_meta` de chaque fichier de référence).

Reproduire l'ensemble :

```bash
./validation/run_all.sh
```

## 2. Résultats par module

| Module | Fichier de test | Tests | Référence | Jeux de données | Tolérance (écart relatif max.) | Résultat |
|---|---|---|---|---|---|---|
| Lois de probabilité | `distributions_test.dart` | 124 | R `pnorm`, `qnorm`, `pt`, `qt`, `pchisq`, `qchisq`, `pf`, `pbeta`, `qbeta`, `binom.test`, `lgamma` | Grilles incluant queues extrêmes (z = −8, p = 1e-10) et ddl de 1 à 1000 | 1e-9 | ✅ |
| Proportions, 2 × 2, groupes, appariés, corrélation, accord, tailles d'échantillon | `fondamentaux_test.dart` | 33 | `prop.test`, `binom.test`, `fisher.test`, `chisq.test`, `t.test`, `wilcox.test`, `aov`, `oneway.test`, `kruskal.test`, `mcnemar.test`, `cor.test`, `power.t.test`, `power.prop.test`, `pt(ncp=)` | 5 proportions dont 0/250 et 60/60 ; 5 tableaux 2 × 2 dont cellules nulles ; échantillons avec et sans ex aequo | 1e-9 à 1e-8 (p) ; 1e-6 (n) | ✅ |
| Diagnostic, descriptif | `diagnostic_descriptif_test.dart` | 3 | `prop.test` (Wilson), formules de Simel recalculées dans R, `quantile(type=7)`, `t.test` | 2 tableaux diagnostiques ; série avec valeur manquante et valeur extrême | 1e-9 | ✅ |
| Régressions | `regression_test.dart` | 9 | `lm`, `car::vif`, `cooks.distance`, `glm(binomial)`, `glm(poisson)` + `sandwich::vcovHC(HC0)`, `logistf` | Cohorte simulée n = 300 (3 manquants), facteurs à 2 et 3 modalités ; jeu de séparation n = 40, 6 événements | β 1e-9 (MCO), 1e-7 (GLM) ; ES 1e-6 | ✅ |
| Métaanalyse | `meta_test.dart` | 17 | `metafor::escalc`, `rma` (FE, DL, REML, knha), `rma.mh`, `leave1out`, Egger par `lm` | BCG (13 essais, I² = 92 %), Normand 1999 (DM, DMS), 5 essais rares dont un double zéro | 1e-8 | ✅ |
| Méta-régression | `meta_regression_test.dart` | 7 | `metafor::rma(mods = )` (REML, DL, FE, knha) | BCG : latitude ; latitude + allocation (qualitatif) ; année ; cas inadaptés | 1e-7 | ✅ |
| Métaanalyse diagnostique bivariée | `meta_diagnostic_test.dart` | 3 | `mada::reitsma` 0.5.11 (REML via `mvmeta`, `reltol = 1e-14`) | AuditC (14 études, cellules nulles), Dementia ; < 3 études | 1e-6 (paramètres, IC, AUC), 1e-7 (log-vraisemblance) | ✅ |
| Prédiction | `prediction_test.dart` | 9 | `glm`, `pROC` (`ci.auc` DeLong, `roc.test`), `pmsampsize`, bénéfice net recalculé | Cohorte simulée n = 800 (23 manquants), 100 répliques bootstrap partagées | 1e-8 (apparent), 1e-6 (corrigé) ; Riley : entiers identiques | ✅ |
| Validation externe | `external_validation_test.dart` | 4 | `predict.glm`, `glm(y ~ offset(lp))`, `glm(y ~ lp)`, `pROC` (DeLong) | Modèle de la démo 3 appliqué à une cohorte externe simulée (594 sujets, 275 événements) ; codage incompatible ; audit | 1e-7 à 1e-10 | ✅ |
| Imputation multiple | `imputation_test.dart` | 6 | `mice` 3.16 : `pool` (identité exacte) ; `mice` PMM/logreg sur 12 graines | Démo 3 complétée par mice (5 jeux) ; simulation MAR n = 1000 | Rubin : 1e-8 à 1e-6 ; imputations : 3 erreurs de Monte-Carlo | ✅ |
| Prédiction avec imputation | `prediction_mi_test.dart` | 4 | Cohérence avec les cas complets, reproductibilité, contrôle de fuite | Démo 3 (23 sujets incomplets) | AUC corrigée à ± 0,02 des cas complets | ✅ |
| Qualité des données, assistant, audit | `quality_advisor_audit_test.dart` | 34 | Corpus annoté (13 phrases fautives, 4 correctes) et scénarios attendus | Fichiers CSV piégés | Détection 100 % du corpus ; 0 fausse alerte grave lexicale | ✅ |
| Firth — IC profilés, RV pénalisé | `firth_profile_test.dart` | 3 | `logistf(pl = TRUE)`, contrôles `xconv = lconv = 1e-12` | Séparation n = 40 ; 4 prédicteurs, 12 événements ; démo AgHBs (2 événements) | bornes 1e-6, p 1e-5 | ✅ |
| Kaplan-Meier, log-rank | `kaplan_meier_test.dart` | 5 | `survfit` (conf.type = "log"), `summary(survfit)$table`, `survdiff` | `lung` (tous, par sexe), `veteran` (4 types cellulaires), palier exactement à 0,5, absence d'événement | survie 1e-12, ES et IC 1e-10, médianes exactes, log-rank 1e-10 | ✅ |
| Régression de Cox | `cox_test.dart` | 5 | `survival::coxph` (Efron, Breslow), `cox.zph` (transformation KM), `concordance` | `lung` NCCTG (213 cas complets, 151 décès, ex aequo, manquants) ; `veteran` (facteur à 4 modalités, non-proportionnalité) ; vraisemblance monotone ; durées négatives | β 1e-8, ES 1e-7, tests 1e-7 à 1e-9, C 1e-12, zph 1e-6 | ✅ |
| Jeux inadaptés | `inadaptes_test.dart` | 8 | Codes d'erreur attendus | Issue à 3 modalités, colinéarité parfaite, log ≤ 0, n < p, séparation, séries inégales | Code exact | ✅ |
| Démonstrations, exports | `demos_test.dart` | 28 | `binom.test`, `logistf`, `fisher.test`, `metafor`, `chisq.test`, `MASS::dose.p`, `Biostrings` | Les 7 démonstrations | 1e-7 à 1e-9 (démo 6 : identité avec les calculs directs, 1e-12) | ✅ |
| Application | `app/statomea/test/*.dart` | 10 (+16 maquettes) | — | Accueil, PDF de la démo 2, suppression, journal, atelier de Cox, calculateur de survie, méta-régression, métaanalyse diagnostique, validation externe et imputation multiple pilotés de bout en bout | PDF valide (> 20 ko, en-tête %PDF) | ✅ |

## 3. Situations limites demandées par le cahier des charges

| Situation | Où elle est testée | Comportement vérifié |
|---|---|---|
| Cellules nulles | 2 × 2 (0/25 vs 6/19), métaanalyse (cellules nulles, double zéro), diagnostic (RV) | Correction 0,5 signalée ; Fisher exact ; double zéro exclu de l'OR/RR avec raison |
| Séparation logistique | `regression_test`, `inadaptes_test`, `firth_profile_test`, démo 1 | Contrôle « séparation » violé, alerte bloquante, résultat non fiable ; Firth fini, IC profilés conformes à logistf |
| Non-convergence | Séparation complète (y parfaitement prédit par x) | Pas d'exception ; résultat marqué non fiable ; modèle de prédiction refusé (`prediction_unstable`) |
| Événements rares | 0/250, 3/412, démo 1 (2/47) | IC exact, règle de trois, EPV, mode « petit nombre d'événements » |
| Données manquantes | Régression (3), prédiction (23), descriptif, apparié | Exclusions comptées par variable, alerte « cas complets », mentionnées dans l'audit si absentes du texte |
| Hétérogénéité élevée | BCG (I² = 92 %) | Alerte grave, intervalle de prédiction, généralisation signalée par l'audit |
| Firth — IC profilés, RV pénalisé | `firth_profile_test.dart` | 3 | `logistf(pl = TRUE)`, contrôles `xconv = lconv = 1e-12` | Séparation n = 40 ; 4 prédicteurs, 12 événements ; démo AgHBs (2 événements) | bornes 1e-6, p 1e-5 | ✅ |
| Kaplan-Meier, log-rank | `kaplan_meier_test.dart` | 5 | `survfit` (conf.type = "log"), `summary(survfit)$table`, `survdiff` | `lung` (tous, par sexe), `veteran` (4 types cellulaires), palier exactement à 0,5, absence d'événement | survie 1e-12, ES et IC 1e-10, médianes exactes, log-rank 1e-10 | ✅ |
| Régression de Cox | `cox_test.dart` | 5 | `survival::coxph` (Efron, Breslow), `cox.zph` (transformation KM), `concordance` | `lung` NCCTG (213 cas complets, 151 décès, ex aequo, manquants) ; `veteran` (facteur à 4 modalités, non-proportionnalité) ; vraisemblance monotone ; durées négatives | β 1e-8, ES 1e-7, tests 1e-7 à 1e-9, C 1e-12, zph 1e-6 | ✅ |
| Jeux inadaptés | `inadaptes_test.dart` | Messages d'erreur explicites (codes attendus) |

## 4. Écarts constatés pendant la validation et leur résolution

| Écart | Cause | Résolution |
|---|---|---|
| Statistique de Wald de Cox à 29,94 vs 29,9417 | `summary.coxph` arrondit les tests globaux à 2 décimales | Référence lue dans `m$wald.test` et `m$score` (non arrondis) |
| ES de x1 15,6 % plus grand que mice (une graine contre une graine) | Variabilité propre de mice d'une graine à l'autre : ES de 0,0397 à 0,0464 (17 %) | Comparaison refaite sur plusieurs graines de chaque côté, tolérance de Monte-Carlo ; aucune différence |
| Validation interne avec imputation : 9 répliques sur 30 exploitables | Filtre erroné écartant les modèles dont la constante dépasse 15 en valeur absolue | Filtre aligné sur le bootstrap sans imputation (convergence, valeurs finies) |
| Log-vraisemblance bivariée différente de mada (38,16 au lieu de 31,56) | Erreur de signe du moteur sur le terme −½·log|ΣXᵀV⁻¹X| de la vraisemblance REML | Corrigée ; vraisemblance, τ, ρ et μ identiques à mada |
| R² de méta-régression absent pour l'effet fixe | metafor rapporte alors un R² ajusté 1 − (QE/QE₀)(k − 1)/(k − p) | Implémenté, identique à metafor |
| Bornes de l'IC de la médiane de survie inversées (première version) | Erreur du moteur : la bande INFÉRIEURE passe sous 0,5 la première et donne la borne basse | Corrigé ; identique à `survfit` |
| Borne supérieure de l'IC exact de Fisher différente de `fisher.test` jusqu'à 1,5 % | `fisher.test` résout avec `uniroot` à tolérance ≈ 1e-4 : sa borne ne vérifie pas exactement l'équation (probabilité 0,0254 au lieu de 0,025) | Référence de haute précision ajoutée dans R (même équation, tol = 1e-14) : écart ≤ 1e-7. Écart à `fisher.test` toléré à 5 % et documenté |
| ES logistiques différents de `glm` de 1e-6 | `glm` calcule l'ES avec les poids de l'itération précédente | Convergence resserrée des deux côtés (1e-12 / 1e-14) : écart ≤ 1e-6 |
| ES de Firth différents de `logistf` de 5 % | logistf 1.26 utilise (Xᵀ diag(w(1+h)) X)⁻¹ (pseudo-observations), pas l'information de Fisher (XᵀWX)⁻¹ | Alignement sur logistf, documenté dans le code ; écart ≤ 1e-6 |
| β de Firth à 1,6e-7 de logistf | Demi-pas déclenchés par le bruit d'arrondi près de l'optimum | Tolérance relative ajoutée au critère de demi-pas ; le score pénalisé est nul (1e-13) au point de logistf |
| « Log-vraisemblance » Firth −10,09 vs −14,21 | Le script R lisait `loglik[2]` (modèle nul) | Script corrigé (`loglik["full"]`) |
| Colonne contenant « <0,5 » non reconnue comme quantitative | Seuil d'inférence de type à 95 % | Seuil à 80 % ; les valeurs non numériques sont signalées (`non_numeric`) et un type mixte est signalé (`mixed_type`) |

## 5. Ce qui n'est PAS validé

| Élément | Statut | Conséquence dans l'application |
|---|---|---|
| Imputation tirage pour tirage identique à mice | impossible par construction | Générateurs aléatoires différents : la validation des imputations est statistique (écrite et chiffrée ci-dessus) ; la combinaison des analyses est exacte |
| Audit lexical au-delà du corpus | heuristique | Constats marqués « repérage lexical » ; faux positifs et négatifs possibles |
| Applications Android et iOS | non construites sur ce poste | Code identique à la version web ; construction et tests sur appareil à faire |
| Ergonomie auprès des utilisateurs | non évaluée | Tests d'utilisabilité à organiser (étudiants, biologistes, enseignants) |

## 6. Critère de mise en service (proposé)

Une méthode passe au statut « validée » quand : (1) un script R de référence existe ; (2) au moins
un jeu nominal et un jeu limite sont testés ; (3) les tolérances ci-dessus sont respectées ; (4) les
messages d'erreur des cas inadaptés sont testés ; (5) le registre (`registry.dart`) indique le
logiciel de référence. Toute modification du moteur doit laisser `./validation/run_all.sh` vert.

## Version anglaise (1.8.0)

`packages/statomea_core/test/english_test.dart` passe le moteur en anglais et exécute toutes les familles
d'analyses (fondamentales, régressions, Cox, imputation, métaanalyses, prédiction, contrôle des données,
assistant, registre, audit, leçons, grilles, démonstrations, rapports HTML, CSV, figures, messages d'erreur).
Le test échoue au moindre fragment français (lettres accentuées, mots-outils) en dehors des valeurs issues
des données. Il vérifie aussi que :

- l'audit repère en anglais les erreurs volontaires des brouillons des sept démonstrations ;
- une équation de prédiction développée en français s'applique à des données en anglais, et inversement,
  avec les mêmes AUC et pente de calibration ;
- un résultat garde la langue dans laquelle il a été calculé (champ `lang` du JSON).

Les 285 tests existants passent toujours en français, langue par défaut. La traduction est l'œuvre du
développeur : une relecture par un anglophone du domaine reste à faire.

## Import d'un projet exporté (1.9.0)

L'export « Projet complet (JSON) » porte désormais une empreinte d'intégrité (FNV-1a du JSON sans ce champ).
`test/import_test.dart` vérifie : aller-retour exact des trois démonstrations ; fichier modifié après l'export
signalé comme grave ; ancien export sans empreinte relu avec une information ; collision d'identifiant →
copie à part, original intact ; calculs du journal portant sur un sous-ensemble ou une cohorte externe
signalés (non refaisables depuis le seul fichier) ; autre version du moteur signalée ; journal seul, JSON
étranger, format futur et fichier tronqué refusés avec un message explicite ; messages en anglais.
`app/statomea/test/import_project_test.dart` vérifie l'aperçu, l'annulation, la confirmation et l'enregistrement.
Limite : FNV n'est pas cryptographique ; l'empreinte détecte une modification, pas une falsification délibérée.

## Comparaisons post hoc (1.10.0)

Script `validation/r/14_posthoc.R` ; tests `test/posthoc_test.dart` (9 tests).

| Élément | Référence | Tolérance |
|---|---|---|
| Loi de l'étendue studentisée `ptukey` (96 valeurs : q, k = 2…10, ddl 5 à 30 000) | `stats::ptukey` | 1e-9 relatif |
| Quantile `qtukey` | uniroot serré sur `ptukey` (le `qtukey` de R s'arrête vers 1e-9) | 1e-10 |
| Tukey HSD : différences, p, IC simultanés (PlantGrowth ; jeu simulé à effectifs inégaux, Tukey-Kramer) | `stats::TukeyHSD` | p 1e-9 ; IC 1e-10 (référence précise), 1e-7 (TukeyHSD) |
| Games-Howell (variances inégales) | recalcul R exact ; `rstatix::games_howell_test` | 1e-9 ; à l'arrondi de rstatix près |
| Dunn + Holm (InsectSprays : 6 groupes, nombreux ex aequo ; jeu simulé) | `rstatix::dunn_test(p.adjust.method = "holm")` | 1e-9 |

Les comparaisons s'ajoutent automatiquement dès 3 groupes : Tukey après l'ANOVA classique, Games-Howell après
l'ANOVA de Welch, Dunn-Holm après Kruskal-Wallis. Une alerte rappelle qu'elles sont exploratoires si elles
n'étaient pas prévues au plan d'analyse.

**Correction du banc** : `validation/run_all.sh` ne relançait que les scripts `0*.R` ; les scripts 10 à 13
(méta-régression, métaanalyse diagnostique, validation externe, imputation) n'étaient donc pas régénérés par la
validation complète. Il relance désormais les 15 scripts ; toutes les références régénérées passent.

## Accessibilité (application)

`app/statomea/test/accessibility_test.dart` (6 tests, lancés avec la suite normale) :

- règles de Flutter `androidTapTargetGuideline` (48 dp), `iOSTapTargetGuideline` (44 pt) et `labeledTapTargetGuideline`
  sur 43 écrans (accueil, les 10 étapes d'un projet, ateliers de métaanalyse et de prédiction, 3 étapes de la démo 4,
  3 leçons, 13 calculateurs, 6 outils de l'atelier génomique et le plan d'expression d'un projet),
  en thème clair et sombre, à 844 px puis 3 000 px de haut pour évaluer aussi le contenu sous la ligne de flottaison ;
- contraste : rapport WCAG calculé exactement sur les paires de couleurs employées (texte 4,5:1, icônes de statut 3:1),
  dans les deux thèmes. La règle `textContrastGuideline`, qui échantillonne des pixels, a été écartée après vérification
  visuelle : faux positifs sur les cellules à moitié hors champ des tableaux défilants et les étiquettes sur deux lignes ;
- texte agrandi à 200 % : aucun débordement à 390 px sur les 43 écrans ;
- arbre sémantique : titres annoncés comme titres (étiquettes de section dans leur casse d'origine), forest plot décrit.

Défauts trouvés et corrigés : barre d'étapes trop basse (cibles de 36 px) ; bandeau « données simulées » illisible en
thème sombre (fond clair fixe) ; valeur corrigée signalée par la seule couleur orange (contraste 3:1) ; pied de page et
étiquettes de section qui débordaient à 200 % ; résultat principal sélectionnable de 32 px de haut. Le banc lui-même
avait un défaut : en réutilisant le même écran, Flutter gardait l'étape précédente, si bien que seule la première
étape était évaluée ; chaque écran est désormais reconstruit.

Limite : ces contrôles automatiques ne remplacent pas un essai avec VoiceOver et TalkBack sur appareil.

## Modèle pronostique de survie (Cox) — 1.11.0

Script `validation/r/15_cox_prediction.R` (jeu public `lung`, 227 sujets, 164 décès ; âge, sexe, ph.ecog) ;
tests `test/cox_prediction_test.dart` (5 tests) et `app/statomea/test/cox_prediction_workshop_test.dart`.

| Élément | Référence R | Tolérance |
|---|---|---|
| Coefficients (Efron, Breslow) | `coxph` | 1e-7 |
| Risque cumulé de base H₀(t) à 180, 365, 730 j : Efron (`ctype = 2`, défaut), Breslow (`ctype = 1`), modèle ajusté par Breslow | `survfit.coxph(newdata = x = 0)` | 1e-6 |
| Risque individuel à 365 j | `survfit(fit, newdata = d)` | 1e-6 |
| C de Harrell apparent | `concordance` | 1e-10 |
| Optimisme du C et de la pente (60 répliques, indices tirés par R et rejoués) ; C et pente corrigés | réajustements `coxph` dans R | 1e-5 (optimisme), 1e-7 / 1e-6 (corrigés) |
| Calibration à 365 j : quintiles de risque prédit, risque observé 1 − KM et IC | `survfit` par groupe | 1e-9 (KM) |

**Défaut corrigé au passage** : le tri des risques prédits n'était pas stable ; des sujets au risque identique
pouvaient changer de quintile de calibration par rapport à R (`order()` est stable). Le tri départage désormais par
ordre des lignes, ici et dans la calibration du modèle logistique.

Limites : pas encore d'imputation multiple pour le modèle de Cox ; le risque de base est
propre aux données de développement (recalibration nécessaire ailleurs), ce que le résultat rappelle.

## Validation externe d'un modèle de Cox — 1.12.0

Script `validation/r/16_cox_external.R` : équation développée sur `lung` (âge, sexe, ph.ecog ; horizon 365 j),
appliquée sans réestimation à une cohorte externe simulée (320 sujets, 274 décès ; risque de base plus élevé,
effets atténués). Tests `test/cox_external_test.dart` (4 tests) et un test d'application (modèle développé dans un
projet, validé depuis un autre).

| Élément | Référence R | Tolérance |
|---|---|---|
| C de Harrell | `concordance(reverse = TRUE)` | 1e-10 |
| Pente de calibration et son ES | `coxph(Surv ~ lp)` | 1e-6 ; 1e-5 |
| Risque moyen prédit à 365 j ; risque observé (KM) et IC ; rapport observé/prédit | calcul direct ; `survfit` | 1e-6 ; 1e-9 |
| H₀ recalibré (β fixés en décalage) ; H₀ recalibré après pente | `coxph(Surv ~ offset(lp))`, `survfit` | 1e-6 |
| Calibration par quintile à 365 j | `survfit` par groupe | 1e-6 / 1e-9 |

Résultat sur la cohorte simulée : C = 0,58, pente 0,57 (prédictions trop dispersées), observé/prédit 1,16 : le
moteur signale la mauvaise calibration et propose le risque de base et la pente recalibrés, à valider à leur tour.
L'équation s'échange en JSON (`"kind": "cox"`) et, développée en français, s'applique en anglais.

## Génomique — 1.13.0

Cinq familles, chacune avec son script R et ses tests ; l'atelier génomique de l'application est couvert par
`app/statomea/test/genomics_workshop_test.dart` (7 tests : saisie d'effectifs, jeux de données, exemples simulés,
calcul en arrière-plan, volcano plot et leçon dans le panneau de calcul) et par le banc d'accessibilité.

### Association génétique — `17_genetique.R`, `test/genetique_test.dart` (7 tests)

Jeu simulé de 400 sujets (6 variants : rs1 associé, rs2 avec génotypes manquants, rs4 hors Hardy-Weinberg).

| Élément | Référence R | Tolérance |
|---|---|---|
| Allèle mineur et fréquence (échantillon entier) | calcul direct | 1e-12 |
| χ² allélique, génotypique, tendance d'Armitage et leurs p | `chisq.test`, `prop.trend.test` | 1e-10 ; p 1e-9 |
| OR allélique, dominant, récessif (IC de Woolf) ; OR codominants | calcul direct ; `glm` | 1e-10 ; 1e-7 |
| Hardy-Weinberg : p exact, mid-p, χ², F | `HardyWeinberg::HWExact`, `HWChisq(cc = 0)` | 1e-9 / 1e-10 |
| Balayage ajusté (âge, sexe) : β, ES, p de Wald, p ajustés | `glm`, `p.adjust` | 1e-7 ; 1e-6 ; 1e-4 * |
| `p.adjust` (Bonferroni, Holm, BH, BY) | `p.adjust` | 1e-12 |

\* p de Wald très petits (< 10⁻¹⁰) : l'écart relatif résiduel vient de la convergence de `glm`, pas du moteur.

### Génomique des pathogènes — `18_pathogenes.R`, `test/pathogenes_test.dart` (2 tests)

| Élément | Référence | Tolérance |
|---|---|---|
| Concordance mutations rpoB ↔ rifampicine : effectifs, Se, Sp (Wilson), règle « au moins une mutation » | `binom` Wilson, calcul R | 1e-9 |
| Kappa de Cohen et son ES (Fleiss, Cohen, Everitt 1969) | calcul R | 1e-12 ; 1e-10 |
| Indice de Hunter-Gaston, IC de Grundmann, indice de Shannon | calcul R | 1e-12 |

### qPCR — `19_qpcr.R`, `test/qpcr_test.dart` (3 tests)

| Élément | Référence R | Tolérance |
|---|---|---|
| Courbe standard : pente, ordonnée, R², efficacité et IC, quantités inconnues | `lm`, `confint` | 1e-12 ; IC 1e-10 |
| ΔΔCt (Welch), ddl, p, rapport 2^−ΔΔCt et IC ; rapport de Pfaffl | `t.test` | 1e-12 ; IC 1e-10 ; p 1e-8 |
| Limite de détection probit : coefficients, log10 LOD95, ES (méthode delta), LOD et IC | `glm(binomial(probit), epsilon = 1e-14)`, `MASS::dose.p` | 1e-8 ; 1e-6 |

### Expression différentielle RNA-seq — `20_expression.R`, `test/expression_test.dart` (6 tests)

1 000 gènes × 8 échantillons simulés (binomiale négative, dispersion variable selon le gène, 80 gènes DE) ;
998 gènes retenus par le filtre CPM ≥ 1 dans ≥ 4 échantillons.

| Élément | Référence (edgeR 3.40, limma 3.54) | Tolérance |
|---|---|---|
| Gènes retenus, tailles de librairie | `cpm`, `DGEList(keep.lib.sizes = FALSE)` | identité ; 1e-14 |
| Facteurs de normalisation TMM | `calcNormFactors(method = "TMM")` | 1e-12 |
| voom : log-CPM et poids (5 premiers gènes × 8 échantillons) | `voom` | 1e-12 ; 1e-9 |
| `lowess` seul (ex æquo, valeurs aberrantes, f = 2/3 et 0,3, 0 et 3 itérations robustes) | `stats::lowess` | 1e-12 |
| Loi a priori d₀, s₀² | `eBayes` (`fitFDist`) | 1e-8 |
| log2 FC, expression moyenne, t modérés, p, p ajustés BH (998 gènes) | `topTable(sort.by = "none")` | 1e-9 ; 1e-12 ; 1e-8 ; 1e-7 |
| Nombre de gènes significatifs (FDR 5 %) | `topTable` | identité (51) |

Les fonctions digamma, trigamma et tétragamma ajoutées au socle concordent avec R (`digamma`, `trigamma`,
`psigamma(deriv = 2)`) à 1e-15 près sur 0,3 à 150.

### Alignement local hors ligne (type BLAST) — `21_alignement.R`, `test/alignement_test.dart` (8 tests)

Bibliothèque ADN simulée (8 séquences, 6 256 nt ; requête de 525 nt sur le brin inverse, apparentée à ref03 et,
de loin, à ref05) et bibliothèque protéique (6 séquences, 1 911 aa ; requête de 240 aa).

| Élément | Référence | Tolérance |
|---|---|---|
| Score Smith-Waterman optimal, ADN 2/−3, gaps 5/2, deux brins (8 × 2 paires) | `Biostrings::pairwiseAlignment(type = "local")` 2.66 | identité |
| Score Smith-Waterman, protéines BLOSUM62, gaps 11/1 (6 paires) | idem | identité |
| Espace de recherche effectif (ajustement de longueur de BLAST+) | blastn / blastp 2.17 (`Effective search space used`) | identité |
| Scores bruts, coordonnées, longueur, identités, gaps de chaque correspondance | blastn `-task blastn`, blastp `-comp_based_stats 0` | identité |
| Bit scores | idem | précision affichée par BLAST |
| E-values (ADN : Karlin-Altschul ; protéines : correction de taille finie de Spouge, comme blastp) | idem | précision affichée (2 ou 3 chiffres) |

BLAST étant heuristique, l'égalité des scores n'est garantie que lorsque BLAST trouve l'alignement optimal, ce qui
est le cas ici pour toutes les correspondances. Statoméa, lui, calcule toujours l'alignement optimal ; il ne
reproduit pas les statistiques de composition de blastp (option par défaut de BLAST, désactivée pour la comparaison)
ni la recherche de plusieurs HSP par séquence (une seule, la meilleure, est rapportée).

**Défauts corrigés au passage** : la vérification initiale des E-values utilisait une tolérance absolue de 1e-12 qui
laissait passer des écarts de 28 ordres de grandeur sur les très petites valeurs (protéines) ; elle compare désormais à
la précision affichée par BLAST, sans tolérance absolue, ce qui a révélé la correction de Spouge, depuis portée. Une
requête collée avec son en-tête FASTA voyait les lettres de l'en-tête lues comme des résidus ; l'en-tête est
désormais retiré (test dédié).

## Expression différentielle, plan à plusieurs facteurs — 1.14.0

Script `validation/r/22_expression_plan.R` : 1 500 gènes × 12 échantillons simulés, 3 groupes (A, B, C), 2 lots
croisés avec les groupes (effet lot sur 30 % des gènes), covariable quantitative RIN ; modèle
`~ groupe + lot + rin` (5 coefficients, 7 ddl résiduels). Tests `test/expression_plan_test.dart` (6 tests),
`test/log2_test.dart` (2 tests) et 2 tests d'application (plan à 3 groupes ajusté sur le lot ; plan incomplet refusé).

| Élément | Référence | Tolérance |
|---|---|---|
| Gènes retenus, facteurs TMM, poids voom (lowess sur le plan complet) | edgeR 3.40, `voom(design)` | identité ; 1e-12 ; 1e-9 |
| d₀, s₀², ddl totaux | `eBayes` | 1e-8 |
| Contrastes B − A et C − A (log2 FC, t, p, FDR) sur 1 498 gènes | `topTable(coef)` | 1e-8 ; 1e-7 ; 1e-6 ; 1e-6 |
| Contraste C − B | limma après changement de niveau de référence (paramétrisation exacte) | idem |
| F modéré global du groupe (2 ddl), p, FDR | calcul R gène par gène avec (XᵀW_gX)⁻¹ | 1e-7 ; 1e-6 |
| Nombre de gènes significatifs par contraste et pour F | idem | identité |
| Lot confondu avec le groupe ; trop de termes pour n | — | refus explicite (`confounded`, `no_df`) |

**Choix méthodologique : contrastes et F exacts.** Avec des poids voom et un plan non orthogonal, limma calcule
les contrastes (`contrasts.fit`) et le F (`topTable` à plusieurs coefficients) à partir de la corrélation des
coefficients du plan NON pondéré : c'est une approximation. Statoméa utilise la matrice (XᵀW_gX)⁻¹ propre à chaque
gène. Sur le jeu de validation, l'approximation de limma s'écarte du calcul exact de 1 % en médiane et jusqu'à 20 %
sur le t de C − B (8 gènes classés différemment au seuil de 5 %), de 0,8 % en médiane et jusqu'à 16 % sur le F. Les
contrastes contre la référence ne sont pas concernés (identiques à limma).

**Défaut corrigé : log2.** Sur ce jeu, les facteurs TMM s'écartaient de edgeR de 6e-5. Cause : Dart n'a pas de
`log2` ; `log(x)/ln 2` diffère d'une unité au dernier rang de la valeur de R pour 28 % des log-rapports, ce qui
déplace des blocs d'ex æquo (gènes aux comptages identiques) de part et d'autre des bornes de la troncature. Un `log2`
correctement arrondi (double-double) ramène l'écart à 17 valeurs sur 1 443, toutes à mi-chemin exact entre deux
flottants (la libm de R n'y est pas non plus correctement arrondie), sans effet sur la troncature ici. Limite : un
tel cas à mi-chemin situé exactement sur une borne de troncature pourrait encore donner un facteur TMM différent de
edgeR au-delà de 1e-12.

Effet de l'ajustement sur le lot (exemple simulé de l'application, 3 groupes × 3, 2 lots) : 45 gènes détectés par le
F global sans ajustement, 66 avec ; d₀ passe de 3,1 à 8,4 (la variance due au lot n'est plus prise pour du bruit).

## Expression différentielle, plans appariés et mesures répétées — 1.15.0

Script `validation/r/23_expression_apparie.R` (limma 3.54, statmod 1.5.0) ; tests `test/expression_apparie_test.dart`
(8 tests) et 2 tests d'application (exemple apparié analysé de trois façons ; interface à 390 px et texte à 200 %).

**(1) Avant/après chez 6 patients** (1 200 gènes simulés, forte variabilité entre patients) : sujet en effet fixe,
`~ patient + temps`.

| Élément | Référence | Tolérance |
|---|---|---|
| d₀, s₀² ; log2 FC, t, p, FDR de « après − avant » | `eBayes`, `topTable(coef)` | 1e-8 ; 1e-9 (t, p) |
| Gènes significatifs | idem | identité (62 ; 29 si l'on ignore l'appariement) |

**(2) 4 patients et 4 témoins, 2 sites par sujet** : le sujet est emboîté dans le statut (un effet fixe l'absorberait) ;
corrélation intra-sujet et moindres carrés généralisés, chaîne du guide de limma : voom → `duplicateCorrelation` →
voom(`block`, `correlation`) → `duplicateCorrelation` → `lmFit(block, correlation)` → `eBayes`.

| Élément | Référence | Écart mesuré (tolérance du test) |
|---|---|---|
| Corrélation consensuelle, passes 1 et 2 (ρ ≈ 0,63) | `duplicateCorrelation` | 1e-15 (1e-12) |
| atanh ρ par gène (REML à un effet aléatoire) | `statmod::mixedModel2Fit` | (1e-9) |
| Poids voom de la seconde passe (GLS) | `voom(block, correlation)` | (1e-9) |
| d₀, s₀² | `eBayes` | 4e-14 (1e-10) |
| log2 FC, t, p, FDR du statut sur 1 200 gènes | `lmFit(block, correlation)`, `topTable` | t 9e-12, p 3e-12 (1e-9) |

Portage ligne à ligne de `statmod::glmgam.fit` (MLE gamma amorti, arrêt à tolérance 1e-6 et 20 itérations), dont il
faut reproduire le chemin et pas seulement l'optimum ; poids appliqués à y et X mais pas à Z, comme statmod. Le
résultat ne dépend pas de la base choisie pour l'espace résiduel (les composantes de variance ne dépendent que de
sommes sur les espaces propres), ce qui permet une décomposition propre symétrique (Jacobi) au lieu de la SVD de
LAPACK. Le choix automatique « effet fixe / corrélation » repose sur le rang du modèle augmenté du sujet ; un sujet
déjà dans le modèle, ou des sujets à un seul échantillon, sont refusés explicitement.

## Démonstration 4 (tuberculose résistante) — 1.16.0

Script `validation/r/24_demo_tb.R` ; 5 tests dans `test/demos_test.dart` (concordance du panel à 3 et 4 mutations :
Se, Sp et IC de Wilson à 1e-9, kappa à 1e-12 ; Hunter-Gaston ; Fisher de la lignée L2 ; χ² des centres ; LOD95 à
1e-8 contre `MASS::dose.p` ; scores Smith-Waterman des 6 références identiques à Biostrings ; audit du brouillon ;
aller-retour JSON du projet), l'audit en anglais dans `test/english_test.dart`, le rapport PDF et HTML dans
`app/statomea/test/export_test.dart`, et 3 écrans de la démo dans le banc d'accessibilité. Détail des valeurs :
`docs/06-demonstrations.md`. Correction au passage : une E-value inférieure à 1e−180 s'écrivait « E = < 1e−180 » ;
elle s'écrit désormais « E < 1e−180 ».

## Essai Android de la 1.16.0

APK de version 1.16.0 (code 16), aucune permission Internet (`aapt2 dump permissions`), installé en mise à jour de la
1.10.0 sur l'émulateur API 37 : les projets existants sont conservés. Vérifiés à l'écran : démonstration 4 (ouverture,
étapes), alignement de l'atelier génomique calculé dans un isolat (mêmes scores que sur le web et dans les tests, résultat
ajouté au journal du projet), expression appariée avec corrélation intra-sujet.

**Défaut trouvé sur Android et corrigé** : l'outil d'expression ouvert dans un projet dont les données n'ont aucune colonne
numérique de comptages (tableau d'isolats de la démo 4) affichait un bloc gris (exception `Bad state: No element` :
niveaux d'un plan vide). Le plan vide est désormais traité, un message invite à choisir « Fichier ou exemple » ; deux tests
d'application ajoutés, dont un qui ouvre chacun des 10 outils de l'atelier génomique sur chaque jeu de données des
démonstrations (40 combinaisons, aucune erreur).

## Import de génotypes (VCF, PLINK) et contrôle de qualité — 1.17.0

Script `validation/r/25_genotypes.R` : 300 sujets simulés (150 cas, 150 témoins), 250 variants bialléliques et 2 sites
multialléliques, avec défauts volontaires (5 variants rares, 3 hors Hardy-Weinberg, 5 à fort taux de manquants ;
4 sujets à fort taux de manquants, 2 « contaminés » à hétérozygotie excessive). Mêmes génotypes écrits en VCF (génotypes
phasés et non phasés, manquants), PLINK texte et PLINK binaire (genio). Tests `test/genotypes_test.dart` (8 tests),
`app/statomea/test/genotype_import_test.dart` (4 tests : exemple binaire jusqu'au balayage, `.vcf.gz`, jeu incomplet,
écran étroit et texte à 200 %).

| Élément | Référence | Tolérance |
|---|---|---|
| Dosages lus dans le VCF | vcfR 1.15 (`extract.gt`), relecture identique | identité |
| Dosages du PLINK binaire = dosages du VCF ; sexe et phénotype du .fam | genio 1.1 (écriture) | identité |
| PLINK texte : même information (allèle compté = allèle mineur) | — | identité (orientation près) |
| Taux d'appel et MAF par variant ; taux d'appel et hétérozygotie par sujet (données brutes) | snpStats 1.48 `col.summary`, `row.summary` | 1e-12 |
| Sujets et variants écartés (6 et 13, exactement les défauts simulés) ; z d'hétérozygotie ; taux d'appel, MAF, HWE exact chez les témoins sur les sujets retenus | calcul R, `HardyWeinberg::HWExact` | identité ; 1e-12 ; HWE 1e-9 |
| Balayage ajusté (sexe, âge) des 237 variants retenus : p, \|β\|, p ajustés BH | `glm` | 1e-6 ; 1e-7 ; 1e-6 |

Ordre du contrôle : sujets (taux d'appel < 0,95, puis hétérozygotie à plus de 3 ET), puis variants sur les sujets
retenus (taux d'appel < 0,95, MAF < 0,01, HWE p < 1e-6 chez les témoins ; sur tous les sujets à défaut de phénotype,
ce qui est signalé). Non évalués et signalés comme tels : sexe génétique, apparentement, stratification.

**Défaut de performance corrigé** : le balayage de variants recopiait toute la table d'analyse pour chaque variant
(coût quadratique) ; 237 variants prenaient 14,2 s, 0,16 s désormais, à résultats identiques (tests contre `glm`
inchangés). Les `.vcf.gz` sont décompressés dans l'application par `archive` (Dart pur, déjà présent via la bibliothèque
PDF), y compris sur le web.

## Stratification de population : élagage LD, ACP, inflation génomique — 1.18.0

Script `validation/r/26_acp.R` : 400 sujets simulés de 2 sous-populations (Balding-Nichols, F_ST = 0,03) dont la
proportion de cas diffère (0,35 contre 0,65), sans variant causal ; 1 000 variants dont 60 paires fortement corrélées.
Tests `test/acp_test.dart` (5 tests) et un test d'application (exemple stratifié : balayage brut, ACP, balayage ajusté).

| Élément | Référence | Écart mesuré (tolérance du test) |
|---|---|---|
| Variants retenus par l'élagage LD (60 écartés : exactement les paires simulées) | règle réimplémentée dans R | identité |
| 10 premières valeurs propres, trace de G | `eigen(G, symmetric = TRUE)` | 4e-15 (1e-12) |
| 10 composantes × 400 sujets (signe normalisé) | idem | 6e-14 (1e-11) |
| λ de contrôle génomique et p des 1 000 balayages, sans ajustement puis ajustés sur CP1–CP2 | `glm`, médiane de χ²₁ | 1e-6 |

Résultat pédagogique : λ = 2,39 sans ajustement (fausses associations massives dues à l'ascendance), 1,13 après
ajustement sur 2 CP ; la 1re valeur propre (13,7) se détache nettement des suivantes (≈ 2,6).

La règle d'élagage (fenêtres de 50 variants, pas de 5, r² > 0,2 : variant de plus faible MAF écarté) est documentée et
réimplémentée à l'identique en R ; elle s'inspire de `plink --indep-pairwise` sans prétendre en reproduire chaque
détail. Décomposition propre : tridiagonalisation de Householder et QL implicite (EISPACK/JAMA), contrôlée aussi par
résidu (‖Av − λv‖ < 2e-14) et orthogonalité (< 4e-15). **Optimisation au passage** : les rotations QL travaillent sur la
transposée des vecteurs propres (accès mémoire séquentiel) — 6 s au lieu de 30 s pour 1 000 sujets, résultats
identiques. Limite fixée à 1 500 sujets sur l'appareil ; au-delà, l'application oriente vers `plink --pca`.

Le balayage de variants calcule désormais λ (à partir de 50 variants) et l'interprète : avertissement au-delà de 1,10,
avec un message différent selon que le modèle est déjà ajusté sur des composantes principales ou non.

## Apparentement (KING-robust) — 1.19.0

Script `validation/r/27_parente.R` : 200 fondateurs simulés et 20 000 variants indépendants ; apparentés générés par
transmission mendélienne (4 doublons à 0,5 % d'erreurs, enfants avec leurs deux parents, fratries avec leurs parents,
demi-frères, cousins germains via des parents non échantillonnés) ; 230 sujets, 0,5 % de manquants. Tests
`test/parente_test.dart` (4 tests) et un test d'application (détection, exclusion appliquée à l'ACP et au balayage,
annulable).

| Élément | Référence | Tolérance |
|---|---|---|
| φ KING-robust et IBS0 des 26 335 paires | formule de Manichaikul et al. (R) et SNPRelate 1.32 `snpgdsIBDKING(type = "KING-robust")` (écart R–SNPRelate 1e-16) | 1e-12 |
| Paires apparentées et degrés : 4 doublons, 25 au 1er degré, 1 au 2e (demi-frères), 1 au 3e (cousins) — exactement les liens simulés | idem | identité |
| Parent–enfant (IBS0 ≈ 0) distingué des frères/sœurs (IBS0 > 0) | — | — |
| Ensemble non apparenté : 15 sujets écartés, même règle gloutonne qu'en R ; aucun lien > 2e degré ensuite | règle réimplémentée | identité |

**Densité de variants** : à 3 000 variants, l'estimateur a un écart type ≈ 0,018 chez les non-apparentés, et 32 paires
sur 19 900 franchissaient au hasard le seuil du 3e degré (0,0442). À 20 000 variants (ET ≈ 0,007), plus aucun faux
positif. Le résultat le signale sous 10 000 variants. Calcul par masques de bits sur mots de 32 bits (comptes par
`popcount` sans multiplication, exacts aussi en JavaScript) : 26 335 paires × 20 000 variants en moins d'une seconde.
Dans l'application, l'exclusion des apparentés (activée par défaut, annulable) s'applique à l'ACP et au balayage ; les
données d'analyse sont mises en cache plutôt que recalculées à chaque affichage.

## Manhattan et QQ plots du balayage de variants — 1.20.0

Script `validation/r/28_qq.R` ; tests `test/qq_test.dart` (2 tests) et assertions ajoutées au test d'application de
stratification.

| Élément | Référence | Tolérance |
|---|---|---|
| Quantiles attendus du QQ plot (n = 1 000 et n = 7, règle a = 3/8 si n ≤ 10, sinon 1/2) | `ppoints` | 1e-14 |
| Bande de confiance ponctuelle à 95 % (k-ième plus petite p ~ Beta(k, n − k + 1)) | `qbeta` | 1e-8 |
| λ affiché sur le QQ plot = λ du balayage | — | identité |

Manhattan : −log10 p selon la position (chromosomes ordonnés 1–22, X, Y, MT, couleurs alternées), seuils pangénomique
5 × 10⁻⁸ et suggestif 10⁻⁵, cinq variants les plus significatifs nommés ; tracé seulement quand les positions sont
connues (import VCF/PLINK). Au-delà de 4 000 points, tous les p < 10⁻³ sont gardés et les autres sous-échantillonnés
régulièrement (lecture inchangée, fichiers d'export légers). Vérification visuelle sur l'exemple stratifié : QQ plot hors
de la bande dès le début (λ = 2,40), ramené dans la bande après ajustement sur CP1–CP2 (λ = 1,12).

## Démonstration 5 (étude pangénomique) — 1.21.0

Script `validation/r/29_demo_gwas.R` ; 4 tests dans `test/demos_test.dart` (QC, parenté, élagage et valeurs propres
identiques à R à 1e-10 ; λ brut et ajusté et p des 3 meilleurs variants contre `glm` à 1e-6/1e-5 ; audit ; projet
compact < 1 Mo relu à l'identique), audit anglais, rapport PDF/HTML et 2 écrans au banc d'accessibilité. Détail :
`docs/06-demonstrations.md`.

Cette démonstration, la première à manipuler 3 000 colonnes, a révélé et fait corriger plusieurs défauts généraux :

| Défaut | Effet | Correction |
|---|---|---|
| Recherche linéaire du nom de colonne à chaque cellule (`Dataset.col`) | Table de 3 000 colonnes : 8,9 s ; balayage : 9,9 s | Index nom → colonne : 0,34 s et 1,5 s, résultats identiques |
| Balayage étendu : statistiques, estimations, tableau et figures pour tous les variants, nombres à 17 chiffres | Projet de 7 Mo (stockage du navigateur ≈ 5 Mo) | Au-delà de 1 000 variants, détail des 500 plus petits p (estimations 50, tableau 200), figures sous-échantillonnées et arrondies ; λ sur tous les variants |
| Projets stockés en JSON indenté | Taille doublée | `encodeCompact()` pour le stockage (même empreinte) ; export lisible inchangé : 0,72 Mo |
| PDF : limite de 20 pages du moteur PDF | Export impossible des projets riches | Limite portée à 500 pages ; tableaux tronqués à 60 lignes dans le PDF (complets en HTML/CSV) |
| PDF : textes des figures en Helvetica (sans « − », grec, exposants) | Exception à la mise en page, pagination relancée sans fin | Police Noto Sans fournie au rendu SVG (`customFontLookup`) |
| PDF : tableaux enveloppés dans une colonne insécable | Tableau plus haut qu'une page → boucle de pagination | Titre et tableau émis comme éléments directs du document |
| Accessibilité : résultat principal très court (« 492 ») et réponses d'interprétation courtes | Cibles tactiles de 44 et 40 px | Minimum 48 × 48 |

## Leçon « Études d'association pangénomiques » — 1.22.0

Contenu : contrôle de qualité, parenté (φ, IBS0), stratification et composantes principales, λ et QQ plot, seuils
5 × 10⁻⁸ et 10⁻⁵, puissance et réplication ; 6 exercices, 5 erreurs fréquentes ; renvoi vers l'outil « Génotypes
VCF / PLINK » (import, QC, parenté, ACP et balayage étant rattachés à cette leçon dans le registre). Exemple calculé par
le moteur à chaque construction des leçons (≈ 70 ms) : 300 variants simulés, test de tendance d'Armitage ; λ ≈ 0,92
quand cas et témoins ont le même mélange d'ascendances, ≈ 2,80 quand les cas viennent surtout d'une population, sans
aucun variant causal. `test/lecon_gwas_test.dart` (3 tests) vérifie, en français et en anglais, que les réponses
attendues des exercices numériques concordent avec le moteur (−log10 du seuil, médiane de χ²₁, `ppoints`) et que
l'exemple montre bien l'inflation ; la leçon est contrôlée par le test « aucun fragment français » et par le banc
d'accessibilité.

## Modèle linéaire mixte (apparentés conservés) — 1.23.0

Script `validation/r/30_lmm.R` : 600 sujets simulés (150 fratries de 3 + 150 non apparentés), 1 500 variants complets,
trait quantitatif polygénique (h² ≈ 0,5) avec un variant causal. Méthode EMMAX/P3D (Kang et al. 2010) : REML sous le
modèle nul par décomposition spectrale de la GRM standardisée, puis moindres carrés généralisés par variant avec
H = K + λI fixé, test F(1, n − p) — exactement la logique de `rrBLUP::GWAS(P3D = TRUE)`. Tests `test/lmm_test.dart`
(3 tests) et un test d'application (exemple familial : trait quantitatif, apparentés gardés, variant causal retrouvé).

| Élément | Référence | Tolérance |
|---|---|---|
| λ = Ve/Vu, Vu, Ve (sexe en effet fixe) | recalcul R à tolérance serrée (`optimize`, tol 1e-12) ; rrBLUP 4.6 `mixed.solve` | 1e-6 ; 1e-5 (rrBLUP optimise à sa tolérance par défaut) |
| p des 1 500 variants (sexe) | recalcul serré ; rrBLUP `GWAS(P3D = TRUE)` | 1e-7 ; 1e-4 |
| p des 1 500 variants (sexe + âge, covariable numérique que `GWAS()` ne sait pas traiter) et λ_GC | recalcul serré | 1e-7 ; 1e-6 |

Le recalcul serré reproduit rrBLUP à 2e-6 près sur log10 p. À l'optimum REML, plat, deux optimiseurs différents
s'arrêtent à ~1e-8 près de λ, d'où la tolérance de 1e-6 sur les composantes de variance (sans effet visible sur les p).
Résultat pédagogique : régression ordinaire λ_GC = 1,47 (apparentés), modèle mixte 0,93 ; le léger excès de
conservatisme vient de la « contamination proximale » (variant testé inclus dans K), signalée dans le résultat — la
variante LOCO n'est pas implémentée. Écart assumé à rrBLUP : un génotype manquant est imputé par la moyenne (comme
EMMAX), alors que rrBLUP retire le sujet pour ce variant en réutilisant une sous-matrice de H⁻¹ ; la validation porte
donc sur des génotypes complets.

## Modèle mixte LOCO — 1.24.0

Script `validation/r/31_loco.R` (mêmes données que 30_lmm.R, covariables sexe + âge) : pour les variants du
chromosome c, K₋c = GRM calculée sans les variants de c ; composantes de variance réestimées par REML pour chaque
chromosome (comme GCTA `--mlma-loco`), puis test P3D. Dans Statoméa, K₋c = (m·K − m_c·K_c)/(m − m_c), sans recalculer
la GRM entière. Test `test/lmm_test.dart` (« LOCO ») et extension du test d'application (exemple familial).

| Élément | Référence | Tolérance |
|---|---|---|
| λ REML de chacun des 3 chromosomes | recalcul R serré | 1e-6 |
| p des 1 500 variants et λ_GC | idem | 1e-6 |

À noter : sur ces données, λ_GC passe de 0,93 (K complète) à 1,31 en LOCO. Ce n'est pas un défaut : le trait simulé
est très polygénique (300 variants causaux sur 1 500, sur 3 chromosomes) ; retirer le chromosome testé de K cesse
d'absorber son fond polygénique, et les vrais petits effets gonflent les statistiques. Le résultat le dit (contrôle
« contamination proximale évitée »). Avec 22 chromosomes et des variants causaux clairsemés, λ LOCO reste proche de 1 ;
distinguer polygénie et confusion relève de la régression LD score (1.25.0, ci-dessous). Coût : une décomposition propre
par chromosome (≈ 1,2 s pour 600 sujets sur ordinateur, soit ≈ 30 s pour 22 chromosomes).

## Régression LD score — 1.25.0

Script `validation/r/32_ldsc.R`. Aucun paquet R de référence ne calcule la LDSC sur des génotypes individuels (le
logiciel `ldsc` de Bulik-Sullivan est en Python 2 et attend des scores LD précalculés sur 1000 Genomes) : la
spécification de Statoméa est donc réécrite en R indépendamment (`crossprod` sur génotypes standardisés, `lm.wfit`) :

- scores LD dans l'échantillon : ℓ_j = Σ_k r²_adj(j, k), variants du même chromosome à moins de 1 Mb (k = j inclus),
  r²_adj = r² − (1 − r²)/(n − 2) ;
- χ² > max(80 ; 0,001·N) exclus ; régression pondérée de χ² sur (1, ℓ), deux itérations, poids
  1/(max(ℓ, 1)·(a + N·h²·ℓ/M)²), h² borné à [0 ; 1] dans les poids, départ a = 1 et h² = M(χ̄² − 1)/(N·ℓ̄) ;
- ES par jackknife sur B = min(50, ⌊J/10⌋) blocs contigus (poids de l'ajustement complet fixés) ; ratio = (a − 1)/(χ̄² − 1).

Données simulées avec un vrai DL (blocs de 1 à 20 variants, copule gaussienne AR(1) par haplotype, ρ de 0,3 à 0,97 ;
deux sous-populations de fréquences décalées). Test `test/ldsc_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| 4 000 scores LD (2 000 sujets) | R | 1e-10 |
| Scénario A (trait polygénique h² = 0,4, pas de confusion) : intercept 1,030 (ES 0,118), h² 0,39 | R | 1e-9 à 1e-10 |
| Scénario B (même trait + écart de moyenne entre sous-populations) : intercept 1,685 (ES 0,136), ratio 0,64 | R | 1e-9 |
| Exemple de l'application (1 000 sujets, 3 000 variants) : χ² de Wald des 3 000 régressions logistiques | glm (epsilon 1e-14) | 1e-6 (convergence IRLS) |
| Chaîne balayage → LDSC sur cet exemple : intercept 1,536 | R | 1e-6 |

Test d'application (`genotype_import_test.dart`) sur l'exemple en blocs de DL : balayage ajusté sur le sexe →
intercept 1,54 (ES 0,14 ; ratio 0,86 : l'inflation vient surtout de la confusion) ; après ACP et ajustement sur CP1–CP2,
intercept 1,01 (ES 0,12) et h² 0,29. Limites affichées dans le résultat : en deçà de 200 000 variants les ES restent
larges ; les scores LD de l'échantillon supposent une ascendance homogène ; ne pas appliquer après un contrôle génomique
ni après un modèle mixte LOCO ; h² d'une issue cas-témoins sur l'échelle observée. Après un balayage par modèle mixte, le
χ² utilisé est la statistique F(1, n − p).

## Corrélation génétique (régression LD score croisée) — 1.26.0

Script `validation/r/33_rg.R` (spécification réécrite en R, comme 32_ldsc.R) :

- z signés des deux balayages, mêmes sujets ; variants retenus si z₁² et z₂² ≤ max(80 ; 0,001·N) ;
- h²₁, h²₂ et intercepts a₁, a₂ par la régression LD score univariée (1.25.0) sur ces variants ;
- régression pondérée de z₁z₂ sur (1, ℓ), deux itérations, départ ρ = 0 et ρg = M·mean(z₁z₂)/(N·ℓ̄), poids
  1/(max(ℓ, 1)·[(a₁ + N·h̃²₁·ℓ/M)(a₂ + N·h̃²₂·ℓ/M) + (ρ + N·ρ̃g·ℓ/M)²]), h̃² bornés à [0 ; 1] et ρ̃g à [−1 ; 1] ;
- rg = ρg/√(h²₁·h²₂) (non défini si un h² ≤ 0) ; ES par jackknife sur blocs contigus (rg recalculé par bloc à partir
  des trois régressions, poids fixés ; ldsc utilise des pseudo-valeurs, écart documenté) ; p bilatéral par z = rg/ES.

Test `test/rg_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Validation (2 000 sujets, 4 000 variants ; rg simulée 0,6, corrélation environnementale −0,2) : rg 0,83 (ES 0,20), h², ρg, ρ et leurs ES | R | 1e-9 (ρ : 1e-7) |
| Exemple de l'application : |z| de Wald des 2 × 3 000 régressions logistiques (diabète, coronaropathie) | glm | 1e-6 |
| Produits z₁z₂ (le balayage compte l'allèle mineur, R l'allèle A1 : signe commun inversé, rg inchangé) | glm | 2e-6 |
| Chaîne balayages → rg (rg 1,01, ES 0,33) | R | 1e-5 |

Test d'application : balayages successifs du diabète puis de la coronaropathie (ajustés sur le sexe) → rg 0,95 (ES 0,30 ;
p = 0,001 ; rg simulée 0,7). L'avertissement « h² > 2 ES » se déclenche (h² 0,31 ± 0,17) : avec 3 000 variants, le
dénominateur de rg est imprécis, ce que le résultat signale ; un rg hors de [−1 ; 1] est possible (estimateur non borné).

## Démonstration 6 et performances — 1.27.0

La démonstration 6 (`docs/06-demonstrations.md`) enchaîne des méthodes déjà validées (1.17.0 à 1.26.0) ; ses tests
vérifient la chaîne et l'identité avec les calculs directs. Nouvelle famille d'audit « Inflation génomique : polygénie
ou confusion » : alerte grave si le texte attribue l'inflation à la polygénie alors qu'un intercept LDSC est nettement
> 1 ; prudence si cette attribution n'est étayée par aucune régression LD score (cas de la démo 5) ; « sans objet »
sans balayage. Le contrôle « analyse ajustée » reconnaît désormais les balayages avec covariables ; une même condition
non satisfaite dans plusieurs analyses ne donne plus qu'un constat.

Optimisations sans changement de résultat (arithmétique et ordre des sommes inchangés ; les 413 tests passent aux
mêmes tolérances) :

| Calcul | Avant | Après | Moyen |
|---|---|---|---|
| Décomposition propre 1 000 × 1 000 (JIT) | 20 s | 1,3 s | tred2 sur la transposée, lignes `Float64List`, boucles internes en petites fonctions |
| Élagage LD (AOT) | 5,2 s | 0,7 s | dosages typés `Int8List` |
| GRM 1 000 sujets × 2 212 variants (AOT) | 3,5 s | 0,7 s | produits scalaires de lignes, même ordre de sommation (bit à bit identique) |
| Balayage logistique, 3 000 variants | ≈ 3 s | ≈ 1,3 s | matrice des covariables construite une fois, IRLS sur `Float64List`, journal d'itérations facultatif |
| Démonstration 6 complète (AOT) | 24 s | 8,8 s | ci-dessus + génotypes lus une fois pour 4 balayages |

## Score de risque polygénique (C+T) — 1.28.0

Script `validation/r/34_prs.R` (spécification réécrite en R) : répartition fixe dans l'ordre du fichier (i mod 6 ≤ 3
découverte, 4 validation, 5 test) ; découverte : `glm` logistique par variant ; clumping par p croissant, ≤ 250 kb,
r² > 0,1 (règle de `plink --clump` avec p1 = p2 = 1) ; score = Σ β·dosage sur les index de p ≤ T, 9 seuils de 5 × 10⁻⁸ à
1 ; validation : `glm` sur le score centré réduit, AUC (`pROC`), R² de Nagelkerke ; seuil au R² maximal ; test : mêmes
mesures, IC de l'AUC par DeLong (`pROC::ci.auc`). Données simulées : 3 000 sujets, 3 000 variants en blocs de DL,
liability h² = 0,5 portée par 150 variants, maladie à 30 %. Test `test/prs_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| β et p des 3 000 régressions de découverte | glm (epsilon 1e-14) | 1e-6 et 1e-5 |
| 1 835 variants index après clumping | R | identité |
| Mesures des 9 seuils en validation, seuil retenu (10⁻³, 24 variants) | glm, pROC | β 1e-6, AUC 1e-12, R² 1e-6 |
| Test : OR par ET 1,97, AUC 0,674 (0,621 à 0,727), R² 0,113 | glm, pROC (DeLong) | 1e-6 ; AUC et IC 1e-12 et 1e-9 |

Point pédagogique : R² de Nagelkerke 0,25 en validation contre 0,11 en test. Choisir le seuil sur la validation
surestime la performance ; le contrôle « optimisme » le signale et seul le test est rapporté. Le score n'est pas
ajusté sur des covariables qu'à partir de la 1.31.0 (ci-dessous) et suppose des sujets non apparentés d'une même ascendance.

## Modèle mixte logistique (GMMAT) — 1.29.0

Script `validation/r/35_glmm.R` : données familiales de 30_lmm.R (600 sujets dont 450 en fratries, 1 500 variants) ;
maladie = 40 % des valeurs les plus élevées du trait simulé ; covariables sexe et âge ; K = GRM standardisée.
Modèle nul par PQL (τ par REML sur le modèle de travail, dispersion 1), test du score U = gᵀ(y − μ̂), V = gᵀPg.

| Élément | Référence | Tolérance |
|---|---|---|
| τ = 1,0785 et α (3 coefficients) | recalcul R serré du point fixe PQL-REML (optimize tol 1e-12, arrêt 1e-10) | 1e-6 |
| τ | GMMAT 1.4.2 `glmmkin` (AI-REML, tol 1e-5) | 1e-4 |
| U, V et p des 1 500 variants | recalcul serré | U 1e-6 (absolu), V 1e-6, p 1e-5 |
| p des 1 500 variants | GMMAT (U et V à partir de `obj$P` et `obj$scaled.residuals`, comme `glmm.score`) | 1e-3 (écart maximal observé 1,5 × 10⁻⁵ en log₁₀) |
| λ_GC | recalcul serré | 1e-5 |

Le point fixe est validé plutôt que la trajectoire d'AI-REML de GMMAT : à convergence, τ annule le score REML du modèle
de travail, comme dans Statoméa (décomposition spectrale de W^½KW^½ à chaque itération, section dorée sur log τ).
Résultat pédagogique : logistique ordinaire λ = 1,55 (apparentés), modèle mixte logistique λ = 1,00. Dans
l'application, une issue binaire analysée en mode « modèle mixte » utilise par défaut ce modèle (interrupteur vers le
modèle linéaire EMMAX, seul compatible avec LOCO). L'OR par allèle est l'approximation à un pas U/V de `glmm.score`.

## Leçon « Polygénie, régression LD score et scores polygéniques » — 1.30.0

Test `test/lecon_polygenie_test.dart` (français et anglais) : réponses des exercices numériques recalculées
(χ² moyen attendu 1 + N·h²·ℓ̄/M ; ratio), liens du registre (`ldsc`, `genetic_correlation`, `polygenic_score` → leçon
`polygenic`) et exemple calculé par le moteur : 20 000 statistiques simulées (N = 20 000, h² = 0,3) passées à
`ldscRegression` ; sans confusion, intercept 1,05 (ES 0,05) et h² 0,28 ; avec une confusion ajoutant 0,25 à chaque χ²
attendu, intercept 1,30 et h² 0,28 (ratio 0,19). L'intercept capte la confusion, la pente n'en dépend pas.

## Score polygénique ajusté — 1.31.0

Extension de `validation/r/34_prs.R` (graine 20261106, résultats non ajustés inchangés) : covariables sexe et âge
(l'âge est associé à la maladie indépendamment des génotypes) ; découverte `glm(y ~ dosage + sexe + âge)` ; évaluation
par comparaison des modèles `y ~ sexe + âge` (base) et `y ~ sexe + âge + z` (complet) : OR par ET ajusté, R² de
Nagelkerke incrémental (complet − base, chacun contre le modèle vide), AUC du score seul et des prédicteurs linéaires ;
seuil au R² incrémental maximal ; sur le test, IC de DeLong de l'AUC complète et différence appariée (`pROC::roc.test`,
DeLong). Sans covariable, les calculs sont exactement ceux de la 1.28.0 (tests inchangés).

| Élément | Référence | Tolérance |
|---|---|---|
| β et p de découverte ajustés ; variants index | glm | 1e-6 ; 1e-5 ; identité |
| Validation (9 seuils) : R² incrémental et de base, AUC du score, de base et complète ; seuil retenu (0,01, 58 variants) | glm, pROC | 1e-6 ; AUC 1e-9 à 1e-12 |
| Test : AUC base 0,695 → complète 0,775 ; gain 0,080 (IC et p = 8 × 10⁻⁵) ; R² incrémental 0,132 | pROC (DeLong apparié) | 1e-7 à 1e-5 |

Dans l'application, les covariables cochées sous « Ajustement » (dont CP1–CP2 après l'ACP) sont prises en compte ;
l'exemple pour score polygénique charge un fichier sexe/âge.

## Randomisation mendélienne — 1.32.0

Script `validation/r/36_mr.R` : MendelianRandomization 0.9.0, réglages par défaut (pondération simple, loi normale) sur
le jeu publié du paquet (28 variants : association avec le LDL-cholestérol et avec la maladie coronarienne en log-odds ;
Waterworth et al. 2010), copié dans `demos/mr_ldl_chd.csv`. Test `test/mr_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| IVW à effets aléatoires multiplicatifs (2,834 ; ES 0,530 ; OR 17,0 par mmol/L) et à effets fixes, Q, σ̂, F moyen (28,0) | `mr_ivw` | 1e-10 (p 1e-8) |
| MR-Egger : pente 3,253 (ES 0,770), intercept −0,011 (p = 0,45), Q de Rücker, I²_GX = 0,919 | `mr_egger` | 1e-10 à 1e-12 |
| Médiane pondérée : estimation 2,683 | `mr_median(weighting = "weighted")` | 1e-12 |
| ES du bootstrap sur 200 tirages R rejoués | `weighted.median` du paquet | 1e-12 |
| ES du bootstrap à 10 000 itérations avec le générateur de Statoméa (0,42) | `mr_median` (graine 314159265) | 4 % (erreur de Monte-Carlo ≈ 0,7 %) |

Avec moins de 4 variants, l'IVW passe en effets fixes comme le paquet. Les hypothèses d'indépendance des instruments
vis-à-vis des facteurs de confusion et d'absence de pléiotropie horizontale ne sont pas testables : le résultat le
rappelle ; l'intercept MR-Egger et la concordance des trois méthodes en donnent des indices.

## Randomisation mendélienne : sensibilité et multivariée — 1.33.0

Script `validation/r/37_mr_sensibilite.R` (MendelianRandomization 0.9.0 ; même jeu publié, complété des associations avec
le HDL-cholestérol et les triglycérides). Test `test/mr_sensibilite_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Mode pondéré : estimation 2,946 | `mr_mbe` (densité de R reproduite : discrétisation BinDist sur 2 × 512 cases, convolution, interpolation) | 1e-12 |
| 200 estimations bootstrap rejouées et leur MAD | `mbe_est` du paquet | 1e-12 |
| ES du mode à 10 000 tirages du générateur de Statoméa (1,00) | `mr_mbe` (graine 314159265) | 6 % (ES relative de la MAD ≈ 1 %) |
| Leave-one-out : 28 estimations IVW et IC (2,62 à 2,92) | `mr_loo` | 1e-10 |
| IVW multivariée LDL, HDL, TG : effets directs 1,93 / −0,59 / 0,72, ES, IC, p, Q | `mr_mvivw` | 1e-10 (p 1e-8) |

Piège relevé : la méthode `mr_mbe` utilise par défaut les ES de la méthode delta (√(se_Y²/βX² + βY²·se_X²/βX⁴)) alors que
la signature générique affiche « simple » ; avec les ES simples, l'estimation est la même mais l'ES bootstrap passe de
1,00 à 0,37. Statoméa suit le défaut effectif du paquet. La convolution de R (FFT) est calculée par somme directe sur les
cases non vides, ce qui ne change pas l'abscisse du maximum.

## Démonstration 7 et audit de la randomisation mendélienne — 1.34.0

`test/demos_test.dart` (groupe « Démo 7 ») vérifie que la chaîne reproduit les références de 36_mr.R et
37_mr_sensibilite.R (IVW, MR-Egger, mode, effets directs multivariés à 1e-10 à 1e-12), le contraste HDL (IVW univarié
p < 0,001, pléiotropie signalée, effet direct non significatif) et l'audit. Règles d'audit ajoutées : en présence d'une
randomisation mendélienne, (1) une conclusion causale n'est acceptée que si le texte discute instruments ou pléiotropie,
(2) une pléiotropie directionnelle détectée (intercept MR-Egger) et non discutée déclenche une alerte grave ; le
leave-one-out compte comme analyse de sensibilité réalisée.

## Leçon « Causalité et randomisation mendélienne » — 1.35.0

Test `test/lecon_causalite_test.dart` (français et anglais) : réponses des exercices numériques (OR de Wald exp(βY/βX),
F = (βX/ES)²), liens du registre (`mendelian_randomization`, `mendelian_randomization_mv` → `causal_mr`), identité des
données intégrées au moteur (`mrLipidExample`) avec le fichier publié (estimations IVW, MR-Egger et multivariée égales aux
références R à 1e-10 à 1e-12) et temps de construction des leçons (< 3 s).

## Sens causal : test de Steiger et MR bidirectionnelle — 1.36.0

Script `validation/r/38_mr_steiger.R` : formules de TwoSampleMR (paquet non distribué sur CRAN) réécrites en R —
r² = F/(N − 2 + F) avec F = (β/ES)² (`get_r_from_bsen`), test agrégé sur r = √Σr² (`directionality_test`) — et
comparaison des corrélations par `psych::r.test` ; IVW par `MendelianRandomization::mr_ivw`. Données simulées
(statistiques résumées, `demos/mr_bidirectionnel_simule.csv`) : X cause Y (θ = 0,4) ; 25 instruments de X dont 2 à effet
direct plus fort sur Y ; 20 instruments de Y sans effet sur X ; N_X = 60 000, N_Y = 90 000. Test `test/mr_steiger_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| r²_X = 3,6 %, r²_Y = 1,4 %, z = 13,5 | formules TwoSampleMR ; `psych::r.test` | 1e-12 ; 1e-10 |
| r² et p par variant ; 2 variants de sens inverse repérés | idem | r² 1e-12 ; p 1e-6 (R calcule 2·(1 − Φ(|z|)), imprécis pour les petites p) |
| IVW avec tous les variants (0,50) et sans les 2 inversés (0,38, proche de la vraie valeur 0,4) | `mr_ivw` | 1e-10 |
| MR inverse Y → X sur les instruments de Y : 0,003 (ES 0,028) | `mr_ivw` | 1e-10 |

Dans l'application, l'outil de randomisation mendélienne propose une sélection des variants (colonne, modalité), le
sens inverse (issue comme exposition) et le test de Steiger (effectifs des deux études). La leçon « causalité » a un
exercice sur r² de Steiger.

## Randomisation mendélienne à partir de deux GWAS complets — 1.38.0

Script `validation/r/39_gwas_mr.R` : règles de TwoSampleMR (`harmonise_data`, action 2 ; paquet non distribué sur CRAN)
réécrites en R, puis `MendelianRandomization::mr_ivw`, `mr_egger`, `mr_median`. Données simulées : deux fichiers de
statistiques résumées de 12 000 variants (4 chromosomes, 40 loci causaux, θ = 0,3), l'exposition au format GWAS-SSF
(`demos/gwas_exposition_simule.tsv`), l'issue au format TwoSampleMR avec OR, allèles en minuscules, un tiers d'allèles
inversés, un quart de brins complémentaires, 400 palindromiques, des allèles incompatibles et 500 variants absents
(`demos/gwas_issue_simule.tsv`). Test `test/gwas_mr_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Lecture : alias de colonnes GWAS-SSF / TwoSampleMR / PLINK, OR → log(OR), lignes illisibles écartées | — | exact |
| 62 variants à p < 5e-8, 29 instruments après clumping 10 000 kb (mêmes variants, même ordre) | spécification R | exact |
| Statut de chaque instrument : 8 alignés, 7 inversés, 3 brins corrigés, 4 brins corrigés et inversés, 1 palindromique aligné, 1 retourné, 2 écartés (EAF ∈ ]0,42 ; 0,58[), 2 incompatibles, 1 absent | spécification R | exact |
| β de l'issue réalignés (24 instruments utilisables) | spécification R | 1e-12 |
| IVW 0,265 (ES 0,018 ; θ simulé 0,3 dans l'IC), MR-Egger, intercept, médiane pondérée | `mr_ivw`, `mr_egger`, `mr_median` | 1e-10 |

Le clumping est fait par distance (pas de panel de référence de DL embarqué, l'application fonctionnant hors ligne) :
une fenêtre de 10 000 kb est conservatrice. Dans l'application, l'outil de randomisation mendélienne importe les deux
fichiers (.tsv, .csv ou .gz), règle seuil et fenêtre, affiche le bilan d'harmonisation et le joint au résultat.

## Risques concurrents : incidence cumulée et modèle de Fine-Gray — 1.39.0

Script `validation/r/40_risques_concurrents.R` : `cmprsk` 2.2-11 (`cuminc`, `crr` avec `gtol = 1e-12`) et `survival`
(`survfit`, `coxph`). Données simulées (`demos/risques_concurrents_simule.csv`) : 400 patients après traitement d'un
cancer, issue « rechute » (191), événement concurrent « décès » (141), 68 censures ; bras A/B, âge, sexe ; durées en
mois au dixième (ex aequo). Tests `test/risques_concurrents_test.dart` (moteur) et `app/statomea/test/risques_concurrents_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Incidence cumulée d'Aalen-Johansen à chaque temps d'événement, 2 groupes × 2 causes | `cuminc` | 1e-12 |
| Variance de Gray (avec correction des ex aequo) | `cuminc` | 1e-10 |
| IC ponctuel log(−log) F^exp(±z·√v/(F·log F)) | même formule en R | 1e-9 |
| Incidence de rechute à 24 mois : A 50,1 %, B 28,0 % (1 − KM naïf : 61,4 % et 34,3 %) | `cuminc`, `survfit` | 1e-12 |
| Fine-Gray (bras, âge, sexe) : coefficients, ES sandwich, log-pseudo-vraisemblance | `crr` | 1e-8, 1e-7, 1e-10 |
| Cox spécifique de cause en regard | `coxph` (Efron) | 1e-8 |
| Sans événement concurrent : Fine-Gray = Cox de Breslow ; incidence = 1 − KM | identités | 1e-9 |

Sur ces données, l'âge augmente le risque spécifique de rechute (HR > 1) mais diminue son incidence cumulée (sHR < 1) :
les patients âgés meurent plus souvent avant de rechuter. L'application le signale (alerte « sens opposés »).

Le test de Gray, d'abord approché à 0,1–0,2 %, est reproduit exactement en 1.40.0 (voir ci-dessous).

## Test de Gray, Cox avec covariable dépendant du temps et leçon — 1.40.0

**Test de Gray.** Traduction en Dart de la routine Fortran `crst` de cmprsk 2.2-11 (`src/crstm.f`, R. Gray, GPL),
lue dans le source CRAN : score par groupe Σ[d₁ⱼ − d₁·Rⱼ/ΣR], Rⱼ = nⱼ(1 − F̂ⱼ(t⁻))/Ŝⱼ(t⁻), et variance de Gray (1988)
avec correction des ex aequo ; une strate, rho au choix. Comparé à `cuminc$Tests` (script 40) : 2 groupes (bras),
3 groupes (tranches d'âge), rho = 0 et 1, pour chacune des deux causes — tolérance 1e-10.

**Cox avec covariable dépendant du temps.** Script `validation/r/41_cox_temps.R`, données réelles du programme de greffe
cardiaque de Stanford (`survival::jasa`, 103 patients, 69 greffés ; `demos/greffe_stanford.csv`), préparées comme la
vignette de survival. Test `test/cox_temps_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Découpage au changement (greffe) : 170 intervalles (début, fin], statut et covariable | `tmerge(tdc())` | exact |
| Cox en processus de comptage, Efron et Breslow : coefficients, ES | `coxph(Surv(début, fin, statut))` | 1e-8 |
| Log-vraisemblances, score, Wald | `coxph` | 1e-11, 1e-9, 1e-7 |
| Analyse naïve (greffe codée à l'inclusion) : HR 0,18 (biais du temps immortel) contre 1,01 (p = 0,96) | `coxph` | 1e-8 |

En processus de comptage, la concordance et le test de cox.zph ne sont pas calculés (signalé dans le résultat).
Leçon « Risques concurrents et temps immortel » (5 exercices), exemple calculé par le moteur sur les données de Stanford.

## Atelier de puissance et de taille d'échantillon — 1.41.0

Script `validation/r/42_puissance.R` : `pwr` 1.3, `powerSurvEpi` 0.1.3 et `stats`. Pour chaque plan, n pour une
puissance visée (résolution par Brent) ou puissance pour un n donné. Test `test/puissance_test.dart`.

| Plan | Référence | Tolérance |
|---|---|---|
| Deux moyennes, groupes inégaux (n2 = 2·n1, d = 0,5, 90 %) et égaux ; puissance pour 40 / 80 | `pwr.t2n.test` | n 1e-7, puissance 1e-9 |
| Apparié et un échantillon (t non centrale, deux queues) | `power.t.test(strict = TRUE)` | 1e-7, 1e-9 |
| Deux proportions : puissance pour n = 150 | `power.prop.test` | 1e-12 |
| Cas-témoins (OR 2, 20 % d'exposés, 2 témoins par cas) : 128 cas / 256 témoins ; puissance pour 120 / 240 | `pwr.2p2n.test` (arcsinus) | 1e-7, 1e-12 |
| Survie (HR 0,7, 45 % d'événements en contrôle) : 319 par bras, 247 événements (Freedman) ; puissance pour 300 / 300 | `powerSurvEpi::ssizeCT`, `powerCT` | exact, 1e-12 |
| Événements de Schoenfeld | formule | 1e-12 |
| GWAS, test allélique au seuil 5e-8 : non-centralité, puissance, effectif pour 80 % | `pchisq` non central | 1e-12, 1e-9, 1e-7 |

Atelier « Puissance et effectif » (calculs) avec courbe de puissance ; leçon « Puissance : survie, cas-témoins et GWAS ».

## Mesures répétées : modèle linéaire mixte — 1.42.0

Script `validation/r/43_lmm_longitudinal.R` : `lme4` 1.1 (`lmer`, REML, optimiseur bobyqa resserré) et `nlme` 3.1
(degrés de liberté). Deux jeux : `sleepstudy` (lme4 ; 18 sujets × 10 jours, `demos/sommeil_belenky.csv`) et un essai
simulé (120 patients, HbA1c à 0–12 mois, bras A/B, âge, 61 visites manquantes, `demos/hba1c_longitudinal_simule.csv`).
Test `test/lmm_longitudinal_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Déviance REML profilée au θ de lme4 (formule exacte, identité de Woodbury par sujet) | `REMLcrit` | 1e-10 |
| Optimum atteint par Nelder-Mead (même critère REML) | `lmer` | 1e-10 |
| Effets fixes, ES | `fixef`, `vcov` | 1e-6, 1e-5 |
| Degrés de liberté (constant dans le sujet : m − p_inter − 1 ; sinon N − m − p_intra) et p | `nlme::lme` | exact ; 1e-4 |
| Écarts-types des effets aléatoires, corrélation, σ | `VarCorr` | 1e-4, 1e-3, 1e-5 |

Modèles validés : intercept et pente aléatoires, intercept seul (sleepstudy) ; interaction temps × bras avec termes
inter-sujets (bras, âge). Leçon « Mesures répétées et modèles mixtes » (exemple sleepstudy : ES de la pente 1,55 contre
1,24 en régression ordinaire). L'atelier de régression choisit désormais le modèle dans une liste déroulante (lisible sur
téléphone).

## Mesures répétées : GEE — 1.43.0

Script `validation/r/44_gee.R` : `geepack` 1.3.9 (`geeglm`, ε = 1e-12) et `gee` 4.13 (tol 1e-12), sur l'essai simulé
HbA1c (539 mesures, 120 patients) : issue quantitative (HbA1c), binaire (contrôle : HbA1c < 7,8) et comptage
(épisodes d'hypoglycémie, colonne ajoutée au script 43 sans modifier ses autres tirages). Test `test/gee_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Gaussienne échangeable : β, ES robustes, α, φ — convention geepack (φ = Σr²/N) et gee (correction − p) | `geeglm`, `gee` | 1e-8, 1e-7 |
| Binomiale échangeable (deux conventions) et indépendance ; p de Wald | `geeglm`, `gee` | 1e-8, 1e-7, 1e-6 |
| Poisson échangeable (deux conventions) | `geeglm`, `gee` | 1e-8, 1e-7 |

Non fait : la corrélation de travail AR(1) — avec des visites manquantes, geepack et gee la définissent différemment
(rang ou temps) et aucune variante simple ne les reproduit ; elle n'est donc pas proposée.

## Comptages, issues ordinales et nominales — 1.44.0

Scripts `validation/r/45_comptages.R` (stats::glm, MASS 7.3 `glm.nb`, convergence 1e-14) et `46_ordinal.R`
(MASS `polr`, nnet `multinom`, reltol 1e-14). Données publiques du paquet MASS : `quine` (146 élèves, jours d'absence),
`Insurance` (64 cellules, sinistres avec offset log du nombre d'assurés), `housing` (1 681 locataires, satisfaction
faible < moyenne < élevée). Tests `test/comptages_test.dart`, `test/ordinal_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Poisson : β, ES, déviance, χ² de Pearson, log-vraisemblance (avec et sans offset) | `glm(poisson)` | 1e-9, 1e-8, 1e-10 |
| Quasi-Poisson : dispersion, ES | `glm(quasipoisson)` | 1e-10, 1e-8 |
| Binomiale négative : β, ES, θ, ES(θ), log-vraisemblance ; RV contre Poisson | `glm.nb` | 1e-6, 1e-5, 1e-10, 1e-7 |
| Absence de surdispersion (Insurance) : θ → ∞ signalé, β = Poisson | `glm.nb` (θ ≈ 2,6·10¹¹) | 1e-4 |
| Cotes proportionnelles : β, seuils, ES, log-vraisemblance | `polr` | 1e-7, 1e-5, 1e-11 |
| Multinomiale : coefficients, ES, log-vraisemblance | `multinom` | 1e-6, 1e-5, 1e-10 |

Le test des cotes proportionnelles est approché par le rapport de vraisemblance contre le modèle multinomial (signalé
comme approximation). Les IC sont de Wald (polr propose aussi des IC profilés, non repris).

## Démonstration 8 et audit des pièges de survie — 1.45.0

Démo 8 (survie avancée) construite par `buildDemoSurvivalAdvanced` : chaîne vérifiée contre les références des scripts
40 (`cuminc`, test de Gray, `crr`) et 41 (`coxph` en processus de comptage). Nouvelle famille d'audit « Survie :
risques concurrents et temps immortel » : (a) texte s'appuyant sur Kaplan-Meier alors qu'une analyse d'incidence
cumulée montre un événement concurrent (avec les deux valeurs en regard) ; (b) HR significatif d'une covariable codée
à l'inclusion que le modèle à covariable dépendant du temps ne confirme pas (temps immortel). Tests dans
`demos_test.dart` et `english_test.dart` (huit démonstrations, audit de chacune).

## Assistant de choix enrichi — 1.46.0

L'assistant propose désormais les méthodes ajoutées depuis la 1.39 : mesures répétées (modèle mixte pour une issue
quantitative, GEE pour une issue binaire ou de comptage), comptages (Poisson / binomiale négative), issues ordinales et
nominales ajustées. Deux caractéristiques déclarées s'ajoutent à la question de recherche pour une issue de survie :
« un autre événement peut-il empêcher l'événement étudié ? » (→ incidence cumulée, test de Gray, Fine-Gray ; Kaplan-Meier
assorti d'une mise en garde) et « l'exposition peut-elle changer pendant le suivi ? » (→ mise en garde sur le temps
immortel et covariable dépendant du temps). Si elles ne sont pas renseignées, l'assistant pose la question au lieu de
supposer. Scénarios dans `test/quality_advisor_audit_test.dart` ; textes anglais dans `english_test.dart`.

## Modèle mixte logistique et de Poisson (intercept aléatoire) — 1.48.0

Script `validation/r/47_glmm.R`. Trois niveaux de référence, parce que la déviance de `lme4::glmer` dépend de l'état
final de son algorithme PIRLS : aux mêmes paramètres, `logLik`, `devfun` et le Laplace théorique diffèrent d'environ
0,01 (constaté : 489,5435, 489,5365 et 489,5308 sur l'exemple binaire). Données : essai simulé HbA1c (contrôle
glycémique), `grouseticks` de lme4 (tiques de poussins de lagopède, effet de la couvée ; `demos/tiques_lagopede.csv`),
hypoglycémies (variance entre sujets nulle). Test `test/glmm_long_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Laplace exacte : log-vraisemblance | recalcul R (mode par optimize, maximum par optim BFGS, covariables centrées) | 2e-7 en absolu |
| Laplace exacte : β (crête plate constante–âge), σ, ES | idem, ES par optimHess ramenés à l'échelle d'origine | 1e-3 ES, 1e-4, 5e-3 |
| Quadrature de Gauss-Hermite adaptative à 25 points → maximum de vraisemblance exact | intégration numérique (integrate, rel.tol 1e-12) | β et σ 1e-3, log-vraisemblance 2e-5 |
| Même modèle que glmer (nAGQ = 1 et 10) | `glmer` | β 2 %, ES 5 % |
| Variance entre sujets nulle : σ négligeable, test de σ = 0 non significatif, β = glmer | `glmer` (frontière) | 1e-3 |

Deux corrections ont été nécessaires et sont documentées dans le code : le mode conditionnel converge sur la dérivée
(un critère sur la valeur de g bute sur l'arrondi et rend la vraisemblance bruitée à 5e-9), et la hessienne utilise un
pas de 1e-4 (comme `deriv12` de lme4), les covariables étant centrées pour l'optimisation.

## RMST et analyse landmark — 1.49.0

Script `validation/r/48_rmst_landmark.R` : `survRM2` 1.0.4 (`rmst2`) et `survival` 3.5. Données : essai `veteran`
(traitement standard contre test, `test/reference/cox_veteran.csv`), greffe de Stanford (`demos/greffe_stanford.csv`).
Test `test/rmst_landmark_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| RMST par bras à τ = 300 et 200 jours, ES (variance de survRM2) | `rmst2` | 1e-12, 1e-10 |
| Différence de RMST, rapport des RMST et des RMTL, IC, p | `rmst2` | 1e-11, 1e-10, 1e-9 |
| Landmark 30 et 60 jours : effectifs, exposés, événements, log-rank, Cox (exposition + âge) | `survfit`, `survdiff`, `coxph` | exact, 1e-10, 1e-8 |

Sur `veteran` (τ = 300 j) : RMST 103,5 j (test) contre 114,1 j (standard), différence −10,6 j (p = 0,54). Le τ ne peut
dépasser le dernier temps observé du groupe au suivi le plus court (refusé sinon). Calculateurs « RMST » et
« Analyse landmark » (rubrique Survie) ; la courbe de Kaplan-Meier trace τ.

## Import Excel et dictionnaire de variables — 1.50.0

Script `validation/r/49_excel.R` : classeur écrit par `openxlsx` 4.2 (`demos/exemple_excel.xlsx`, feuilles « patients »
et « dictionnaire »), relu par `readxl` 1.4. Lecteur .xlsx en pur Dart dans le moteur (XML des feuilles, chaînes
partagées et en ligne, booléens, erreurs de formule → manquant, dates par formats intégrés ou personnalisés, système
1900 ou 1904) ; le décompactage du zip est fait par l'application (paquet archive). Test `test/excel_dictionary_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Noms des feuilles et des colonnes | `excel_sheets`, `read_excel` | exact |
| Valeurs des 9 colonnes (dates AAAA-MM-JJ, décimaux, entiers, booléens, vides, « & < > », accents) | `read_excel` | exact |
| Dictionnaire : codes manquants (999) retirés par correction journalisée, codes 1/2 remplacés par leurs libellés, types, unités, libellés, références, ordre des modalités | effet attendu calculé en R | exact |

Le dictionnaire se lit en CSV ou en Excel (colonnes reconnues : variable, type, unité, min, max, référence, libellé,
manquants, modalités). Une feuille « dictionnaire » d'un classeur importé est appliquée automatiquement. Les cellules
d'origine restent intactes. La régression ordinale reprend l'ordre déclaré des modalités. Note : le R x86 de
validation exige `Sys.setlocale("LC_CTYPE", "en_US.UTF-8")` pour écrire des accents corrects.


## Splines cubiques restreintes — 1.51.0

Script `validation/r/50_splines.R` : `rms` 6.7 (`rcs`, `ols`, `lrm`, `cph`, `anova`, `Predict`) et `Hmisc`
(`rcspline.eval`). Données : `regression_data.csv` (pas selon l'âge, n = 300, et sous-échantillon de 60 sujets pour la
règle des petits effectifs), `cardiometabolique_simule.csv` (événement à 5 ans selon l'IMC), `cox_lung.csv`. Test
`test/splines_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Nœuds (quantiles, valeurs extrêmes très fréquentes, 5e plus petite et plus grande valeur sous 100 observations) | `rcspline.eval(knots.only = TRUE)`, `attr(rcs(), "parms")` | 1e-12 |
| Base (normalisation (t_k − t_1)^(2/3)) : coefficients et ES — linéaire, logistique, Cox (Efron) | `ols`, `lrm`, `cph` | 1e-9 à 1e-7 |
| Tests de Wald : association globale (k − 1 ddl) et non-linéarité (k − 2 ddl) ; F pour le modèle linéaire | `anova` | 1e-9 à 1e-7 |
| Courbe dose-effet : contraste f(x) − f(médiane) et IC (t pour ols, normal sinon) | `Predict(ref.zero = TRUE)` | 1e-7 |

`lrm` et `cph` s'arrêtent par défaut à un critère lâche (`cph` : eps = 1e-4, d'où 4e-3 d'écart relatif sur un
coefficient) : la référence les relance avec eps = 1e-12, valeurs alors identiques à `glm` et `coxph`. Une équation de
prédiction exportée garde les nœuds du développement (sinon recalculés sur les nouvelles données). Option « spline à
3, 4 ou 5 nœuds » de l'éditeur de prédicteurs (mode expert), pour les modèles linéaire, logistique, de Poisson, de
Firth et de Cox ; l'interaction avec une spline est refusée.

## Comparaison de méthodes : Passing-Bablok et Deming — 1.51.0

Script `validation/r/51_comparaison_methodes.R` : `mcr` 1.3.3 et l'algorithme publié de Passing-Bablok (1983)
recalculé en R. Données : créatinine sérique et plasmatique (`mcr::creatinine`, 108 patients complets,
`demos/creatinine_serum_plasma.csv`) et un petit jeu avec ex aequo et paire verticale. Test
`test/method_comparison_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Passing-Bablok : N pentes, K pentes < −1, pente, ordonnée et IC analytiques | algorithme publié recalculé | 1e-12 |
| Passing-Bablok : idem | `mcreg(method.reg = "PaBa", method.ci = "analytical")` | pente 1e-8, bornes 1e-4 |
| Deming λ = 1 et 2 : coefficients, ES et IC jackknife (t à n − 2 ddl) | `mcreg(method.reg = "Deming", method.ci = "jackknife")` | 1e-11 à 1e-9 |
| τ de Kendall (τ-b) et p avec correction des ex aequo | `cor.test(method = "kendall", exact = FALSE)` | 1e-12, 1e-6 |

`mcr` calcule Passing-Bablok sur les angles des pentes : la médiane d'un nombre pair d'angles diffère de la médiane des
pentes de 4e-9, et une borne d'IC de 6e-5 ; le moteur suit l'algorithme publié. Sur la créatinine : pente 1,088
(IC 1,000 à 1,173), ordonnée −0,117 (IC −0,200 à −0,020) mg/dL : biais constant négatif. Calculateur « Comparaison de
méthodes » (rubrique Accord), biais aux niveaux de décision ; démonstration 9.

## Calibration : Hosmer-Lemeshow, courbe lissée — 1.51.0

Script `validation/r/52_calibration.R` : `ResourceSelection` 0.3.6 (`hoslem.test`), `rms` 6.7 (`val.prob`),
`stats::lowess`. Modèle logistique développé sur `cardiometabolique_simule.csv`, évalué sur lui-même (calibration
apparente) et sur `cardiometabolique_externe_simule.csv`. Test `test/calibration_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Hosmer-Lemeshow : χ², ddl, p, événements observés et attendus par groupe (quantiles uniques, `cut(include.lowest = TRUE)`) | `hoslem.test(g = 10)` | 1e-10, exact, 1e-8 |
| Spiegelhalter z et p ; Brier ; intercept et pente de recalibration ; calibration dans l'ensemble | `val.prob`, `glm` avec offset | 1e-12 à 1e-7 |
| Courbe lowess (iter = 0) en chaque point | `lowess` (portage de clowess) | 1e-10 |
| Eavg, E90, Emax | `val.prob` | 1e-9 |

Validation externe : Hosmer-Lemeshow χ² = 22,7 (p = 0,004), pente 0,79, Eavg 0,045. Calculateur « Calibration d'un
modèle de risque » (rubrique Prédiction) ; la figure superpose les déciles et la courbe lissée.

## Score de propension : appariement et pondération — 1.51.0

Script `validation/r/53_propension.R` : `MatchIt` 4.5.5, `WeightIt` 0.14.2, `cobalt` 4.5.2, `sandwich`. Données :
étude observationnelle simulée (statines et événement cardiovasculaire, confusion par l'âge, le diabète et le LDL,
`demos/statines_observationnel_simule.csv`) avec caliper 0,2 ; `lalonde` (MatchIt) sans caliper. Test
`test/propensity_test.dart`.

| Élément | Référence | Tolérance |
|---|---|---|
| Score (régression logistique) | `glm` (epsilon 1e-14) | 1e-9 |
| Appariement 1:1 sans remise, ordre des traités par score décroissant, caliper en ÉT du score : paire de chaque traité | `matchit(method = "nearest")`, `match.matrix` | exact |
| Différences standardisées avant et après, rapports des variances (ATT : ÉT des traités ; ATE : ÉT poolé ; binaires standardisées) | `bal.tab(binary = "std")` | 1e-8 |
| IPTW ATE et ATT : tailles effectives, effet, ES robuste HC0 | `weightit(method = "glm")`, `vcovHC(type = "HC0")` | 1e-9, 1e-8 |
| Appariement : effet et ES robuste par paire | `lm(weights)`, `vcovCL(cluster = ~subclass, type = "HC1")` | 1e-9, 1e-8 |

Deux points ont été nécessaires : `glm` s'arrête par défaut à epsilon = 1e-8 (écart de 3e-9 sur les scores de
lalonde, où les revenus ont une grande échelle) ; la référence passe `control = list(epsilon = 1e-14)` à MatchIt et
WeightIt. Les ex aequo exacts de score (sujets aux covariables identiques) sont départagés comme MatchIt, qui parcourt
les témoins triés par score : le plus proche dans cet ordre. Calculateur « Score de propension » (rubrique Causalité) :
tableau et graphique d'équilibre (love plot), recouvrement des scores, alertes (équilibre insuffisant, poids extrêmes,
traités non appariés).
