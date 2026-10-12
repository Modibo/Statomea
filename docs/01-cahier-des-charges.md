# 01 — Cahier des charges de la V1 : parcours et critères d'acceptation

Ce cahier des charges remplace la demande initiale par une version **vérifiable** (voir
[00-analyse-cahier-des-charges.md](00-analyse-cahier-des-charges.md) pour les écarts et leur
justification). Chaque exigence porte un identifiant, un critère d'acceptation chiffré ou
observable, le jeu de test qui le vérifie et son statut.

Légende du statut : **✅ vérifié** (test automatique qui passe), **👁 vérifié manuellement**
(navigateur ou rendu), **🚧 en développement**, **⛔ hors V1**.

## 1. Publics, plateformes, modes

| Id | Exigence | Critère d'acceptation | Vérification | Statut |
|---|---|---|---|---|
| G1 | Fonctionnement hors connexion | Aucun appel réseau à l'exécution : polices, données de démonstration et leçons embarquées ; aucun code d'accès réseau dans `lib/` | Revue du code (aucun client HTTP dans les dépendances de l'app) ; rendu des glyphes ≤ ≥ √ → vérifié sur la version web | 👁 |
| G2 | Téléphone et ordinateur | Mise en page sans débordement à 390 × 844 et 1366 × 860 px | `app/statomea/test/maquettes_test.dart` (16 captures, échec si débordement) | ✅ |
| G3 | Android, iOS, web | Code unique Flutter ; version web construite | `flutter build web` ; Android/iOS : non construits sur ce poste (pas de SDK Android ni de Xcode complet) | 👁 web / 🚧 mobiles |
| G4 | Mode guidé / expert | Le mode expert affiche toutes les estimations, statistiques, formule, journal et JSON ; le mode guidé, le résultat principal, les alertes importantes, les trois questions et les conditions | `ResultView` ; captures | 👁 |
| G6 | Accessibilité | Cibles tactiles ≥ 48 dp (Android) et 44 pt (iOS), toutes étiquetées ; contraste WCAG AA (texte 4,5:1, icônes de statut 3:1) en thème clair et sombre ; texte agrandi à 200 % sans débordement à 390 px ; titres d'écran et de section annoncés comme titres ; graphiques décrits (forest plot : k, effet combiné, IC) ; valeur corrigée signalée autrement que par la couleur | `test/accessibility_test.dart` : règles Flutter sur 29 écrans × 2 thèmes × 2 hauteurs, contraste calculé, arbre sémantique | ✅ (essai sur appareil avec VoiceOver/TalkBack à faire) |
| G5 | Français d'abord, anglais prévu | Version anglaise complète : interface, interprétations, alertes, audit (détection bilingue), leçons, grilles, démonstrations, rapports. Chaque texte est écrit dans les deux langues au même endroit (`tr(fr, en)`) ; un résultat garde la langue de son calcul ; une équation enregistrée dans une langue s'applique dans l'autre | `test/english_test.dart` : toutes les analyses calculées en anglais, échec au moindre fragment français ; sélecteur de langue vérifié au navigateur | ✅ (relecture par un anglophone du domaine à prévoir) |

## 2. Parcours central (10 étapes)

Question → plan d'étude → plan d'analyse → contrôle des données → choix de la méthode → calcul →
diagnostics → interprétation → audit → export. Chaque étape peut être marquée terminée ; l'état est
enregistré localement.

| Id | Exigence | Critère d'acceptation | Vérification | Statut |
|---|---|---|---|---|
| P1 | Saisie PICO + horizon + objectif | Les 6 champs et l'objectif sont persistés dans le projet | `Project.toJson/fromJson` (aller-retour identique, `demos_test.dart`) | ✅ |
| P2 | Plan d'étude déclaré | Plan, niveau des données, types, appariement, ajustement, normalité, événements attendus | `ResearchQuestion.toJson` | ✅ |
| P3 | Pas de choix sur le nom des variables | L'assistant n'utilise que des champs déclarés ; avec une question vide il ne recommande rien et pose ≥ 3 questions | `quality_advisor_audit_test.dart` « information insuffisante » | ✅ |
| P4 | Options multiples avec conditions | Cas « deux groupes, normalité inconnue » : Welch ET Mann-Whitney proposés, plus une question sur la normalité | idem | ✅ |
| P5 | Méthode non validée non utilisable | Une option au statut « en développement » dans le registre a son bouton désactivé (aucune en 1.10.0) | `MethodStep` ; statut lu dans le registre | ✅ |

## 3. Contrôle des données

| Id | Exigence | Critère d'acceptation | Jeu de test | Statut |
|---|---|---|---|---|
| D1 | Import CSV et saisie manuelle | Séparateurs `,` `;` tabulation détectés ; virgule décimale ; BOM retiré ; lignes de longueur incorrecte signalées | `regression_test.dart`, `quality_advisor_audit_test.dart` | ✅ |
| D2 | Aperçu avant analyse | 30 premières lignes, type inféré ou déclaré par colonne | Captures `*-03-donnees.png` | 👁 |
| D3 | Types incohérents | Colonne quantitative contenant « <0,5 » → alerte `non_numeric` avec suggestion sur les valeurs censurées | CSV de test intégré | ✅ |
| D4 | Doublons, identifiants répétés | Lignes identiques → `duplicate_rows` ; identifiant sur plusieurs lignes → `repeated_id` (doublon ou format long) | idem | ✅ |
| D5 | Valeurs manquantes et impossibles | Manquants par variable (gravité selon la proportion) ; âge 250 → `out_of_range` | idem | ✅ |
| D6 | Unités incohérentes (suspicion) | Mélange mmol/L–mg/dL (facteur ≈ 18) → `unit_mix_suspected` | idem | ✅ |
| D7 | Dénominateurs discordants | Numérateur > dénominateur → alerte bloquante | `checkDenominators` | ✅ |
| D8 | Référence non définie, libellés incohérents | « Oui » / « oui » → `inconsistent_labels` ; prédicteur qualitatif sans référence → `reference_undefined` | idem | ✅ |
| D9 | Cellules nulles, événements rares | Issue avec 3 événements → `rare_events` ; croisement sans événement → `zero_cell` | idem | ✅ |
| D10 | Données appariées / de suivi | Colonnes `_avant/_apres` → `paired_wide` ; date de fin < début → `follow_up_order` | idem | ✅ |
| D11 | Aucune modification silencieuse | Les cellules d'origine sont inchangées après contrôle et après correction ; chaque correction a un identifiant, une justification obligatoire, un horodatage, et est réversible | test « correction journalisée appliquée sur une copie » | ✅ |
| D13 | Imputation multiple (MICE : PMM pour les quantitatives, régression logistique bayésienne pour les binaires) et règles de Rubin | Combinaison identique à `mice::pool` (Q̄ ≤ 1e-8 ; ES ≤ 1e-7 ; B, riv, ddl de Barnard-Rubin, fmi ≤ 1e-6) sur les jeux complétés par mice ; imputations : sur une simulation MAR (n = 1000, 37 % et 17 % de manquants), moyennes des estimations et des ES sur plusieurs graines compatibles avec mice à 3 erreurs de Monte-Carlo près ; biais réduit par rapport aux cas complets ; valeurs observées inchangées ; reproductible à graine égale ; variable qualitative > 2 modalités incomplète refusée | ✅ |
| D12 | Suppression complète d'un projet | Après suppression, aucune clé du projet ne subsiste dans le stockage | `export_test.dart` | ✅ |

## 4. Analyses fondamentales

Pour chaque méthode : données utilisées, formule, hypothèses (contrôles), taille d'effet, IC, p si
pertinente, trois questions d'interprétation. La lecture « absence de preuve ≠ preuve d'absence » est
générée à partir de l'IC et, si elle est fixée, d'une marge cliniquement pertinente.

| Id | Méthode | Critère d'acceptation (écart maximal à R) | Statut |
|---|---|---|---|
| F1 | Lois de probabilité (normale, t, χ², F, bêta, binomiale) | 124 points ; écart relatif ≤ 1e-9 | ✅ |
| F2 | IC d'une proportion (Wilson, Clopper-Pearson), règle de trois | ≤ 1e-9 (Wilson), ≤ 1e-8 (exact) ; 0 événement → alerte + borne 3/n | ✅ |
| F3 | Tableau 2 × 2 : RR, OR, DR (Newcombe), χ² (± Yates), Fisher | ≤ 1e-9 ; OR conditionnel de Fisher ≤ 1e-3 (tolérance de `uniroot` dans R), IC exact ≤ 1e-7 contre une résolution R de haute précision | ✅ |
| F4 | Plan cas-témoins | RR et DR non produits, alerte `cc_no_risk` | ✅ |
| F5 | Performance diagnostique | Se, Sp, VPP, VPN (IC de Wilson), RV± (IC log) ≤ 1e-9 ; VPP à prévalence cible exacte | ✅ |
| F6 | t de Student et de Welch, Mann-Whitney (exact, ex aequo, grand n), ANOVA, ANOVA de Welch, Kruskal-Wallis, χ² r × c | statistiques ≤ 1e-10, p ≤ 1e-8 | ✅ |
| F7 | t apparié, Wilcoxon signé (exact et approché), McNemar (asymptotique et exact) | ≤ 1e-8 | ✅ |
| F8 | Pearson (IC de Fisher), Spearman | ≤ 1e-9 | ✅ |
| F9 | Bland-Altman : biais, limites d'accord, IC du biais et des limites | ≤ 1e-9 ; les limites sont étiquetées « limites d'accord », jamais « IC » | ✅ |
| F10 | Tailles d'échantillon (proportion, 2 proportions, 2 moyennes) | n non arrondi ≤ 1e-6 relatif à `power.prop.test` / `power.t.test` ; loi t non centrale ≤ 1e-9 | ✅ |
| F12 | Survie : Kaplan-Meier, médianes, survie à un horizon, log-rank (k groupes) | survie, ES de Greenwood, IC log ≤ 1e-10 ; sujets à risque, médianes et leurs IC identiques à `survfit` (y compris palier à 0,5) ; log-rank ≤ 1e-10 contre `survdiff` (2 et 4 groupes) | ✅ |
| F11 | Statistiques descriptives | moyenne, ÉT, quantiles de type 7, IC t, asymétrie ≤ 1e-10 | ✅ |

## 5. Atelier de régression

| Id | Exigence | Critère d'acceptation | Statut |
|---|---|---|---|
| R1 | Linéaire simple et multiple | β, ES, p, IC ≤ 1e-9 ; R², σ, F ≤ 1e-9 ; Breusch-Pagan ≤ 1e-8 ; Cook max ≤ 1e-8 ; GVIF ≤ 1e-8 (contre `lm`, `car::vif`) | ✅ |
| R2 | Logistique binaire | β ≤ 1e-7, ES ≤ 1e-6, déviance et AIC ≤ 1e-9 (contre `glm`, convergence resserrée) | ✅ |
| R3 | Poisson à variance robuste | β ≤ 1e-7, ES sandwich HC0 ≤ 1e-6 (contre `sandwich::vcovHC`) ; refusée en cas-témoins | ✅ |
| R4 | Firth | β ≤ 1e-7, ES ≤ 1e-6, IC de Wald, log-vraisemblance pénalisée ≤ 1e-8 (contre `logistf` 1.26, `pl = FALSE`) | ✅ |
| R5 | Firth — IC par vraisemblance profilée pénalisée et p du RV pénalisé | bornes ≤ 1e-6, p ≤ 1e-5 (contre `logistf`, `pl = TRUE`) sur 3 jeux : séparation, 4 prédicteurs dont un facteur à 3 modalités (12 événements), démo AgHBs ; borne non atteinte signalée | ✅ |
| R6 | Codage explicite | Catégories de référence, transformations (log, log2, centrage, par k unités), interactions et lignes exclues affichées ; référence par défaut signalée | ✅ |
| R7 | Diagnostics | Linéarité (terme quadratique), colinéarité (GVIF), influence (Cook, levier), convergence, séparation | ✅ |
| R8 | Séparation | Jeu avec une modalité sans événement : contrôle « séparation » violé, alerte bloquante, `reliable = false` | ✅ |
| R9 | Mode « petit nombre d'événements » | EPV < 10 → alerte, < 5 → alerte grave, avec leçon et options ; panneau EPV en direct dans l'atelier | ✅ |
| R10 | Pas d'interprétation causale automatique | Chaque modèle comporte une mise en garde causale dans « conclusions injustifiées » | ✅ |
| R11 | Cox (Efron, Breslow) | β ≤ 1e-8, ES ≤ 1e-7, log-vraisemblances ≤ 1e-10, tests RV/Wald ≤ 1e-7, score ≤ 1e-9, concordance ≤ 1e-12, test de proportionnalité `cox.zph` par terme et global ≤ 1e-6 (contre survival 3.5 sur `lung` et `veteran`) ; vraisemblance monotone → non rapportable ; durée négative refusée | ✅ |

## 6. Atelier de métaanalyse

| Id | Exigence | Critère d'acceptation | Statut |
|---|---|---|---|
| M1 | Traçabilité des valeurs | Chaque valeur a un statut (rapportée / recalculée / hypothèse) et une source ; les hypothèses déclenchent une alerte et une suggestion de sensibilité | ✅ |
| M2 | Effets individuels OR, RR, DR, DM, DMS | `escalc` ≤ 1e-12 ; double zéro exclu (OR/RR), correction 0,5 sinon, signalée | ✅ |
| M3 | Modèles FE, DL, REML, Hartung-Knapp, Mantel-Haenszel | μ, ES, IC, τ², Q, I², H² ≤ 1e-8 (contre `metafor` 4.x, BCG et Normand 1999) | ✅ |
| M4 | Intervalle de prédiction | t(k−2) de Higgins 2009 ≤ 1e-8 | ✅ |
| M5 | Sensibilité et sous-groupes | Leave-one-out ≤ 1e-8 ; Q entre sous-groupes ≤ 1e-9 (= QM de metafor) | ✅ |
| M6 | Forest plot | SVG identique dans l'application, le PDF et le HTML | 👁 |
| M7 | Compatibilité | Grille 5 critères par étude ; « non » → alerte grave ; « incertain » → information insuffisante | ✅ |
| M8 | PRISMA 2020 | Grille paraphrasée avec rappel « rapport ≠ qualité » | ✅ |
| M9 | Méta-régression (modérateurs quantitatifs et sous-groupe ; REML, DL, effet fixe ; Hartung-Knapp) | β, ES, IC, p ≤ 1e-7 ; τ², QE, QM, I², H², R² ≤ 1e-7 (contre `metafor::rma(mods = )`, BCG : latitude, latitude + allocation, année) ; graphique à bulles ; alerte < 10 études par modérateur | ✅ |
| M10 | Métaanalyse diagnostique bivariée (Reitsma, REML) | μ, Var(μ), Ψ (τ², ρ) ≤ 1e-6 ; log-vraisemblance ≤ 1e-7 ; IC de Se et Sp, AUC de la SROC ≤ 1e-6 (contre `mada::reitsma` 0.5.11, jeux AuditC avec cellules nulles et Dementia) ; correction 0,5 signalée ; < 3 études refusé ; courbe SROC, régions de confiance et de prédiction | ✅ |

## 7. Atelier de modèles de prédiction

| Id | Exigence | Critère d'acceptation | Statut |
|---|---|---|---|
| Q1 | Spécification | Population, issue, horizon, usage ; champ manquant → alerte grave | ✅ |
| Q2 | Développement / validation interne / externe séparés | Validation interne par bootstrap ; validation externe = étape distincte, sur d'autres données, coefficients non réestimés | ✅ |
| Q11 | Validation interne avec imputation multiple | Imputation refaite dans chaque réplique bootstrap (contrôle « fuite ») ; issue jamais imputée ; coefficients combinés (Rubin) ; reproductible ; données peu manquantes : résultats proches des cas complets | ✅ |
| Q10 | Validation externe | Logit prédit identique à `predict.glm` (1e-8) ; AUC et IC DeLong (1e-8), intercept et pente de calibration et leurs ES (1e-7), O/E et Brier (1e-10) contre glm et pROC ; codage incompatible refusé (`equation_mismatch`) ; recalibrations proposées (intercept ; intercept et pente) ; alerte < 100 événements | ✅ |
| Q3 | Pas de fuite d'information | Prédicteurs pré-spécifiés ; ajustement refait dans chaque réplique ; pas de sélection automatique | ✅ |
| Q4 | Discrimination | AUC et IC DeLong ≤ 1e-8 ; différence d'AUC appariée (z) ≤ 1e-7 (contre `pROC`) | ✅ |
| Q5 | Calibration, Brier, optimisme | Apparent ≤ 1e-8 ; corrigé ≤ 1e-6 avec les mêmes indices bootstrap que R | ✅ |
| Q6 | Utilité clinique | Bénéfice net ≤ 1e-10 aux seuils 5–30 % | ✅ |
| Q7 | Taille d'échantillon | Critères de Riley i–iii identiques (entiers) à `pmsampsize` | ✅ |
| Q8 | Jamais « validé cliniquement » | Aucun texte généré ne contient « validé cliniquement » ; l'audit signale « validé », « utilisable en pratique clinique » | ✅ |
| Q9 | TRIPOD+AI, PROBAST+AI | Grilles paraphrasées ; items reliés aux contrôles automatiques quand c'est possible | ✅ |

## 8. Formation

| Id | Exigence | Critère d'acceptation | Statut |
|---|---|---|---|
| L1 | Leçon par méthode | 17 leçons (débutant 6, intermédiaire 5, avancé 6) ; chacune : notions, exemple chiffré, ≥ 1 exercice corrigé, erreurs fréquentes, lien vers le calcul | ✅ |
| L2 | Exemples cohérents avec les calculs | Exemples et corrigés numériques calculés par le moteur à la construction de la leçon | ✅ |
| L3 | Thèmes transversaux | OR/RR, IC, covariables, confusion et causalité, données manquantes, hétérogénéité, calibration/discrimination, explicatif vs prédictif, valeur de p, petits effectifs | ✅ |
| L4 | Trois questions après chaque calcul | Champ `Interpretation` obligatoire dans tout `AnalysisResult` | ✅ |

## 9. Audit contradictoire

Constat par famille : alerte (gravité, élément déclencheur, correction), conforme, ou **information
insuffisante**. Les contrôles lexicaux sont signalés comme tels.

| Id | Famille | Critère d'acceptation (corpus annoté) | Statut |
|---|---|---|---|
| A1 | Méthode incompatible avec le plan | RR en cas-témoins ; test indépendant sur données appariées ; effet fixe avec I² > 50 % ; méthode non validée ou résultat bloquant | ✅ |
| A2 | OR présenté comme RR | 2/2 phrases détectées ; 0 fausse alerte grave sur la formulation correcte « la cote … » | ✅ |
| A3 | Limite d'accord confondue avec un IC | 1/1 détectée | ✅ |
| A4 | p mal interprétée | 4/4 détectées (probabilité de H0, « 97 % de chances », p > 0,05 ⇒ pas de différence, « tendance ») | ✅ |
| A5 | Conclusion causale | 2/2 ; « était associé à » non signalé ; « information insuffisante » si plan inconnu | ✅ |
| A6 | Prédiction présentée comme validée | 1/1 ; démonstration 3 signalée | ✅ |
| A7 | Analyse annoncée non effectuée | sensibilité, imputation multiple, validation externe, ajustement, Egger, calibration | ✅ |
| A8 | Précision dépassée | absence d'effet avec IC large, « prouve/démontre », décimales excessives, généralisation malgré I² élevé, « biais de publication exclu » | ✅ |

Limite assumée : un repérage lexical ne couvre pas toutes les tournures ; le critère porte sur le
corpus de test, pas sur l'exhaustivité.

## 10. Reproductibilité et exports

| Id | Exigence | Critère d'acceptation | Statut |
|---|---|---|---|
| E1 | Moteur déterministe séparé | `statomea_core` sans Flutter, sans horloge, sans réseau ; aléa par graine (xorshift128, identique sur toutes les plateformes) ou indices fournis | ✅ |
| E2 | Pas d'IA générative dans les résultats | Aucune dépendance IA ; interprétations par gabarits testés | ✅ |
| E3 | Journal | Chaque calcul de projet : id, horodatage, méthode, version du moteur, empreinte des données, corrections, options, résultat complet | ✅ |
| E4 | Exports | PDF, HTML, CSV par résultat, journal JSON, projet JSON | ✅ (PDF et HTML générés en test) |
| E6 | Import d'un projet exporté | Aperçu avant import ; empreinte d'intégrité (fichier modifié après l'export signalé) ; version du moteur et langue des résultats indiquées ; calculs portant sur des données absentes du fichier signalés ; un identifiant existant n'est jamais écrasé ; journal seul refusé ; rien n'est recalculé | `test/import_test.dart` (8 tests), `test/import_project_test.dart` (3 tests d'interface) | ✅ |
| E5 | Séparation saisi / calculé / interprété / à vérifier | Les 4 étiquettes présentes dans le HTML et le PDF | ✅ |

## 11. Messages d'erreur attendus (extraits)

| Situation | Code | Message affiché |
|---|---|---|
| Dénominateur nul | `n_zero` | Le dénominateur doit être strictement positif. |
| Aucune issue dans une colonne du 2 × 2 | `empty_column` | Aucun événement observé : aucune mesure d'association n'est estimable. |
| Issue non binaire en logistique | `outcome_not_binary` | L'issue « … » a k modalité(s) observée(s) ; … en exige exactement 2. |
| Colonnes parfaitement colinéaires | `aliased` | Colonnes parfaitement colinéaires … un terme est une combinaison exacte des autres. |
| Logarithme d'une valeur ≤ 0 | `log_nonpositive` | n valeur(s) ≤ 0 dans « … » : transformation logarithmique impossible. |
| Poisson en cas-témoins | `poisson_case_control` | Plan cas-témoins : les risques ne sont pas estimables … Utiliser la régression logistique (OR). |
| Modèle de prédiction instable | `prediction_unstable` | Le modèle ne converge pas ou présente une séparation … aucune performance ne peut être rapportée. |
| McNemar sans paire discordante | `no_discordant` | Aucune paire discordante : le test de McNemar n'est pas calculable. |
| Métaanalyse sans étude exploitable | `no_study` | Aucune étude ne fournit les données nécessaires à la mesure « … ». |
| Séries appariées de longueurs différentes | `unpaired_lengths` | Les deux séries n'ont pas la même longueur … pas appariées ligne à ligne. |
