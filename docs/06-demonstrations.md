# 06 — Les cinq démonstrations complètes

Chaque démonstration est un projet entièrement calculé par le moteur, ouvert depuis l'accueil de
l'application. Elle parcourt les 10 étapes et contient un **brouillon de texte volontairement
fautif** que l'audit (étape 9) doit corriger. Les valeurs ci-dessous sont celles produites par le
moteur (démos 1 à 3 : 1.6.0 ; démo 4 : 1.16.0 ; démo 5 : 1.21.0) ; elles sont vérifiées contre R dans `test/demos_test.dart`.

## Démo 1 — Prévalence de l'AgHBs et événements rares

**Données SIMULÉES** (`demos/aghbs_simule.csv`, script `validation/r/05_demo_aghbs.R`, graine 2026) :
640 femmes enceintes dépistées en consultation prénatale ; suivi des enfants nés de mères porteuses.
Elles ne décrivent aucune population réelle.

| Analyse | Résultat | Point pédagogique |
|---|---|---|
| Prévalence de l'AgHBs | 54/640 = 8,44 % ; Wilson 6,52–10,8 % ; exact 6,40–10,9 % | IC adaptés aux proportions modestes |
| Rural − urbain | +3,5 points (IC Newcombe −0,9 à +8,0) | L'IC inclut 0 : absence de preuve, pas preuve d'absence |
| Rapport de prévalences ajusté sur l'âge (Poisson robuste) | RP rural = 1,51 (0,90–2,53) | Transversal ⇒ RP et non RR ; l'OR serait trompeur |
| Transmission mère-enfant | 2/47 = 4,3 % ; exact 0,5–14,5 % | Événements rares : IC exact large |
| AgHBe maternel × transmission (2 × 2) | Fisher p = 0,084 ; OR conditionnel infini (IC 0,46 à ∞) | Cellule nulle (aucun cas chez les mères AgHBe−) |
| Logistique (maximum de vraisemblance) | **Non rapportable** : séparation détectée, alerte bloquante | Un logiciel afficherait un OR de l'ordre de 10¹² |
| Logistique de Firth | OR = 13,4 ; IC profilé pénalisé 1,0004–1 900, p (RV pénalisé) = 0,050 ; IC de Wald 0,60–299, p = 0,10 | Estimation finie mais très imprécise ; l'IC de Wald, symétrique sur l'échelle log, donne ici une image fausse de l'incertitude |

Erreurs volontaires du brouillon et constats de l'audit : précision excessive (« 8,4375 % »),
« la résidence rurale **entraîne** » (langage causal, transversal), « p > 0,05 … l'âge n'a donc pas
d'effet » (absence de preuve), « **prouve** l'efficacité » (sans groupe témoin), « une analyse de
sensibilité a confirmé » (non réalisée), résultat bloquant présent dans le journal.

## Démo 2 — Métaanalyse avec forest plot

**Données PUBLIÉES et publiques** : 13 essais du vaccin BCG (Colditz et al., JAMA 1994 ; jeu `dat.bcg`
du paquet R metafor), `demos/bcg_colditz1994.csv`. La grille de compatibilité a été remplie à titre
d'exemple (suivi « incertain » pour toutes les études : durées non homogènes).

| Analyse | Résultat |
|---|---|
| RR combiné, effets aléatoires (REML) | 0,489 (IC 0,344–0,696), p < 0,001 |
| Hétérogénéité | I² = 92,2 %, τ² = 0,313, Q = 152 (12 ddl) |
| Intervalle de prédiction (t, k − 2) | 0,134 à 1,78 : dans un nouveau contexte, l'effet pourrait être nul ou défavorable |
| Sensibilité Hartung-Knapp | 0,489 (0,330–0,726) |
| Sensibilité effet fixe Mantel-Haenszel | 0,635 (0,588–0,686) — signalé comme inadapté vu l'hétérogénéité |
| Retrait d'une étude à la fois | RR entre 0,452 et 0,533 |
| Sous-groupes (allocation aléatoire / non) | 0,379 vs 0,618 ; p (différence) = 0,16 |
| Test d'Egger (k = 13) | p = 0,19 |
| Méta-régression sur la latitude (REML, prévue a priori) | RR × 0,971 par degré (IC 0,958–0,985), p < 0,001 ; R² = 75,6 % ; I² résiduel = 68,4 % ; graphique à bulles |

Erreurs du brouillon et constats : « démontre que le vaccin est efficace **partout** » (généralisation
malgré I² = 92 % et un intervalle de prédiction incluant 1), « hautement significatif »,
« biais de publication **exclu** par le test d'Egger », effet fixe à côté de l'analyse principale
(prudence : acceptable comme sensibilité seulement).

## Démo 3 — Modèle de risque cardiométabolique avec validation interne

**Données SIMULÉES** (`demos/cardiometabolique_simule.csv`, script `validation/r/04_prediction.R`,
graine 20261010) : 800 adultes, issue à 5 ans, 23 observations incomplètes.

| Élément | Résultat |
|---|---|
| Spécification | Population, horizon (5 ans), usage (orientation vers un bilan), 8 prédicteurs pré-spécifiés |
| Taille d'échantillon (Riley, a posteriori) | minimum indicatif 334 ; n = 777, 248 événements |
| AUC apparente | 0,868 (IC DeLong 0,840–0,896) |
| AUC corrigée de l'optimisme (200 répliques) | 0,862 |
| Pente / intercept de calibration corrigés | 0,964 / −0,001 |
| Brier corrigé | 0,135 |
| Modèle de référence âge + sexe | ΔAUC apparente = +0,225 ; corrigée = +0,224 |
| Courbe de décision | Bénéfice net supérieur à « traiter tous » sur 1–50 % |
| Validation externe (cohorte simulée indépendante, 594 sujets, 275 événements) | AUC 0,803 ; pente de calibration 0,716 (prédictions trop extrêmes) ; intercept −0,16 ; recalibrations proposées |

Erreurs du brouillon et constats : « le modèle **est validé** », « **utilisable en pratique
clinique** » (seule une validation interne a été faite), « le tour de taille **augmente le risque** »
(interprétation causale d'un prédicteur).

## Démo 4 — Tuberculose résistante à la rifampicine : que vaut le génotypage ?

**Données SIMULÉES** (`demos/tb_rifampicine_simule.csv`, `tb_references_simule.fasta`, `tb_isolat_simule.fasta` ;
script `validation/r/24_demo_tb.R`, graine 20261025) : 220 isolats de 3 centres, antibiogramme phénotypique MGIT
(référence), 4 mutations rpoB détectées par le test moléculaire (dont L430P, mutation « limite »), lignée ; 3 échecs
d'amplification ; série de dilutions du test ; 6 séquences de référence et un isolat **fictifs**. Aucun isolat,
patient ni séquence réels. Valeurs vérifiées contre R (Wilson, kappa, Fisher, χ², `MASS::dose.p`,
`Biostrings::pairwiseAlignment`) dans `test/demos_test.dart`.

| Analyse | Résultat | Point pédagogique |
|---|---|---|
| Panel S450L + H445Y + D435V contre MGIT (217 isolats ; 3 échecs exclus, décomptés) | Se 74,0 % (63,3–82,5), Sp 96,4 % (91,9–98,5), κ = 0,74 ; S450L seule : Se 66,2 % | 20 isolats résistants sans mutation détectée : VPN 87 %, l'absence de mutation **n'exclut pas** la résistance |
| Même panel + rpoB L430P | Se 76,6 %, Sp 88,6 % (16 faux positifs au lieu de 5), κ = 0,66 | Une mutation « limite » gagne peu en sensibilité et coûte beaucoup en spécificité |
| Diversité des lignées | D de Hunter-Gaston 0,752 (0,719–0,785) | < 0,95 : la lignée ne suffit pas pour une enquête de transmission |
| Lignée L2 × résistance | RP 1,47 (1,04–2,10), Fisher p = 0,043 | Association transversale : marqueur, pas cause ; issue fréquente, OR (1,88) ≠ RP |
| Résistance selon le centre | χ² = 1,23 (2 ddl), p = 0,54 | Absence de preuve d'une différence, pas preuve d'égalité |
| Limite de détection du test (probit, 20 réplicats/niveau) | LOD95 = 51,0 UFC/mL (30,6–84,8) | IC large malgré 120 réplicats ; ne pas rapporter la LOD sans son IC |
| Identification de l'isolat TB-X (alignement local, bibliothèque locale) | MTBC_sim : 530/530 (100,0 %) ; MBOV_sim : 526/530 (99,2 %) | Écart < 0,8 point : complexe identifié, **espèce non tranchée** par ce fragment |

Erreurs volontaires du brouillon : précision excessive (« 74,02597 % »), « la lignée L2 **entraîne** la
résistance » (causal), « p > 0,05 : il n'y a aucune différence entre centres » (absence de preuve), « une analyse
de sensibilité a confirmé » (non réalisée) — repérées par l'audit, en français comme en anglais. Deux erreurs de
fond échappent volontairement à l'audit lexical et relèvent de l'enseignant : « l'absence de mutation permet
d'exclure la résistance » (contredit par la sensibilité et la VPN) et « l'isolat TB-X est *M. tuberculosis* »
(contredit par le contrôle « écart avec la 2e correspondance »).

## Démo 5 — Étude d'association cas-témoins pangénomique

**Données SIMULÉES** (`demos/gwas_simule.bed/.bim/.fam`, `gwas_covariables_simule.csv` ; script
`validation/r/29_demo_gwas.R`, graine 20261029) : 495 sujets génotypés sur 3 000 variants, issus de deux
ascendances dont la proportion de cas diffère (confusion), avec 2 variants causaux (OR 2,6 et 1,6), un voisin en DL,
3 doublons, 5 paires de frères/sœurs, 3 sujets contaminés et 5 variants à manquants. Chaîne vérifiée de bout en bout
contre une réimplémentation en R des mêmes règles (`test/demos_test.dart`).

| Étape | Résultat | Point pédagogique |
|---|---|---|
| Contrôle de qualité | 3 sujets (hétérozygotie) et 5 variants (manquants) écartés | Seuils fixés avant l'analyse |
| Parenté KING-robust | 3 doublons, 5 paires au 1er degré ; 8 sujets écartés (484 restants) ; nombreux « 3e degré » signalés comme peu fiables (3 000 variants) | Un doublon compté deux fois fausse tout ; densité de variants et 3e degré |
| ACP (non-apparentés, élagage LD) | 1re valeur propre 15,6 contre ≈ 1,9 ensuite | Structure d'ascendance nette |
| Balayage brut | λ = 1,47 ; 5 variants « significatifs » après BH | Fausses associations dues à l'ascendance |
| Balayage ajusté (sexe, âge, CP1–CP2) | λ = 1,00 ; rs201500 p = 1,1 × 10⁻¹¹ (OR par allèle 2,97), seul au-delà de 5 × 10⁻⁸ ; second causal rs202200 seulement suggestif (p = 5,8 × 10⁻⁵) | Puissance limitée : non significatif ≠ sans effet ; réplication nécessaire |
| Détail génotypique de rs201500 | Modèles allélique, dominant, récessif ; HWE chez les témoins | — |

Erreurs volontaires du brouillon, toutes repérées par l'audit (français et anglais) : « **cause** la maladie »
(causal), « le **risque est multiplié** par 2,97064 » (OR présenté comme un risque, précision excessive), « non
significatif… il n'a donc **aucun effet** » (absence de preuve), « une analyse de sensibilité a **confirmé** »
(non réalisée, formulation catégorique). L'audit signale aussi les doublons non discutés. Erreur de fond laissée à
l'enseignant : « λ = 1,47 traduit un fort signal polygénique » (c'est la stratification, que l'ajustement fait
disparaître).

## Démo 6 — Polygénie ou confusion ? Régression LD score et corrélation génétique

**Données SIMULÉES** (`genotypes_dl_simule.bed/.bim/.fam` et `genotypes_dl_traits.csv`, copiés depuis
`test/reference/genotypes/ldsc_app.*` ; scripts `validation/r/32_ldsc.R` (graine 20261102) et `33_rg.R` (graine
20261103)) : 1 000 sujets, 3 000 variants en blocs de déséquilibre de liaison, deux ascendances. L'hypertension (statut
du .fam) a une prévalence qui diffère entre ascendances (confusion) ; diabète et coronaropathie partagent une base
génétique simulée (rg = 0,7) sans confusion. Chaque maillon est validé contre R (régression LD score, corrélation
génétique, balayage logistique) ; `test/demos_test.dart` vérifie la chaîne, dont l'identité de rg avec le calcul direct.

| Étape | Résultat | Point pédagogique |
|---|---|---|
| Contrôle de qualité | 997 sujets, 3 000 variants retenus | — |
| ACP | Structure d'ascendance nette (CP1) | — |
| Hypertension, ajustée sur le sexe | λ = 1,62 | Inflation : polygénie ou confusion ? |
| Régression LD score | intercept 1,54 (ES 0,14) ; ratio 0,86 | L'inflation vient surtout de la confusion |
| Hypertension, ajustée sur sexe, CP1, CP2 | λ = 1,11 | — |
| Régression LD score | intercept 1,01 (ES 0,12) ; h² 0,29 (ES 0,23) | L'ajustement a levé la confusion ; l'inflation restante est polygénique |
| Diabète, coronaropathie (sexe, CP1, CP2) | λ = 1,14 et 1,12 | — |
| Corrélation génétique | rg = 0,96 (ES 0,29 ; p = 0,001) ; h² 0,33 ± 0,18 et 0,35 ± 0,16 | Base génétique commune ; h² fragiles (avertissement) et 3 000 variants : estimation indicative |

Erreurs volontaires du brouillon repérées par l'audit (français et anglais) : « le λ de 1,62… traduit un fort signal
**polygénique** » (nouvelle famille d'audit : l'intercept de la régression LD score montre une confusion), « h² vaut
**0,28635** » (précision excessive), rg « **prouve** que le diabète **cause** la coronaropathie » (formulation
catégorique, langage causal ; une corrélation génétique peut venir de la pléiotropie), « une analyse de sensibilité a
**confirmé** » (non réalisée). L'audit signale aussi l'écart à Hardy-Weinberg chez les témoins, non discuté (mélange de
deux ascendances : effet Wahlund), en un seul constat pour les 4 balayages. Erreur laissée à l'enseignant : « les deux
héritabilités sont estimées avec précision » (ES ≈ 0,17 ; le contrôle « h² > 2 ES » est en avertissement).

Construction en 8,8 s sur ordinateur (exécutable compilé) et en quelques secondes dans le navigateur.

## Démo 7 — Causalité : LDL, HDL et maladie coronarienne (randomisation mendélienne)

**Statistiques PUBLIÉES** (`demos/mr_ldl_chd.csv` : 28 variants associés aux lipides, associations avec le
LDL-cholestérol, le HDL-cholestérol, les triglycérides et la maladie coronarienne ; Waterworth et al. 2010, jeu
d'exemple du paquet R MendelianRandomization). Chaque analyse est validée contre ce paquet (36_mr.R, 37_mr_sensibilite.R).

| Étape | Résultat | Point pédagogique |
|---|---|---|
| LDL-cholestérol | IVW 2,83 log-odds par mmol/L (OR 17, IC 6 à 48) ; MR-Egger 3,25, intercept −0,011 (p = 0,45) ; médiane 2,68 ; mode 2,95 ; leave-one-out de 2,62 à 2,92 ; F moyen 28 | Méthodes concordantes, pas de pléiotropie directionnelle, aucun variant influent : argument causal solide |
| HDL-cholestérol seul | IVW −2,38 (p < 0,001) mais intercept MR-Egger p = 0,026, MR-Egger −0,49 (IC −2,6 à 1,6), mode −1,07 (IC large), I²_GX < 0,9 | L'apparente protection vient de variants pléiotropes |
| Triglycérides seuls | IVW 1,22 (OR 3,4), méthodes concordantes | — |
| MR multivariée | Effets directs : LDL 1,93 (p = 1,2 × 10⁻⁵), HDL −0,59 (IC −1,68 à 0,50 ; p = 0,29), TG 0,72 (p = 0,002) | À LDL et TG égaux, pas d'effet propre démontré du HDL (cohérent avec l'échec des médicaments augmentant le HDL) |

Erreurs volontaires du brouillon repérées par l'audit : « le LDL **cause**… » sans discussion des hypothèses
(nouvelle règle : en randomisation mendélienne, la conclusion causale est acceptée si la validité des instruments et la
pléiotropie sont discutées), « **multiplie le risque** par 17,0170 » (OR présenté comme un risque, précision excessive),
« le HDL **protège**… » alors que la pléiotropie directionnelle détectée n'est pas discutée (nouvelle règle), « les
analyses de sensibilité ont **confirmé** » (formulation catégorique ; les analyses existent, la règle « annoncée non
faite » reconnaît désormais le leave-one-out). Erreur laissée à l'enseignant : « augmenter le HDL par un médicament
réduira les infarctus » (extrapolation d'une exposition génétique à vie à une intervention, et effet direct nul).

## Démo 8 — Survie avancée : risques concurrents et temps immortel

Données : `demos/risques_concurrents_simule.csv` (400 patients **simulés**, rechute / décès sans rechute / censure)
et données **réelles** publiées du programme de greffe cardiaque de Stanford (103 patients, jeu `jasa` du paquet R
survival, embarquées dans le moteur). Question : le bras B réduit-il la rechute, sachant que des patients meurent avant
de rechuter ?

Journal : (1) Kaplan-Meier « naïf » de la rechute (décès censurés) ; (2) incidence cumulée d'Aalen-Johansen par bras,
test de Gray, sHR du bras ; (3) Fine-Gray ajusté (bras, âge, sexe) avec Cox spécifique de cause en regard — l'âge en
sens opposés ; (4) Cox de Stanford avec la greffe codée à l'inclusion (HR 0,18, biais du temps immortel) ; (5) la greffe
en covariable dépendant du temps (HR ≈ 1).

Brouillon à auditer : proportion de rechutes tirée de Kaplan-Meier, « l'âge protège », « la greffe réduit la mortalité
de 82 % ». L'audit relève les deux pièges de survie (nouvelle famille « risques concurrents et temps immortel »), le
langage causal et la formulation catégorique. `test/demos_test.dart` (groupe « Démo 8 ») vérifie la chaîne contre
les références des scripts 40 et 41.

## Reproduire

Dans l'application : Projets → Démonstrations. En ligne de commande :

```bash
cd packages/statomea_core
dart test test/demos_test.dart
```
