<p align="center"><img src="docs/logo/statomea_logo.png" alt="Logo Statoméa" width="260"></p>

# Statoméa

Application de calcul statistique et de formation à la recherche biomédicale, en français, pour
téléphone et ordinateur. Elle conduit l'utilisateur **d'une question de recherche à une analyse
justifiée, vérifiable et correctement interprétée** : question → plan d'étude → plan d'analyse →
contrôle des données → choix de la méthode → calcul → diagnostics → interprétation → audit → export.

> **Outil d'aide à l'analyse et à la formation.** Les calculs sont validés contre R ; les
> interprétations sont des propositions à relire. Validation logicielle n'est pas validation
> clinique : aucun modèle n'est déclaré « validé cliniquement ».

## Documentation (livrables)

| # | Livrable | Document |
|---|---|---|
| 0 | Analyse critique de la demande, périmètre V1 | [docs/00-analyse-cahier-des-charges.md](docs/00-analyse-cahier-des-charges.md) |
| 1 | Cahier des charges, parcours, critères d'acceptation, messages d'erreur | [docs/01-cahier-des-charges.md](docs/01-cahier-des-charges.md) |
| 2 | Matrice question → données → méthode → conditions → diagnostics → résultat | [docs/02-matrice-methodes.md](docs/02-matrice-methodes.md) (générée depuis le code) |
| 3 | Maquettes téléphone et ordinateur | [docs/03-maquettes.md](docs/03-maquettes.md) |
| 4 | Architecture technique et modèle de données | [docs/04-architecture.md](docs/04-architecture.md) |
| 5 | Code exécutable et installation | ce fichier |
| 6 | Jeux de tests et rapport de validation | [docs/05-validation.md](docs/05-validation.md) |
| 7 | Dix démonstrations complètes | [docs/06-demonstrations.md](docs/06-demonstrations.md) |
| — | Protocole de tests d'utilisabilité | [docs/08-tests-utilisabilite.md](docs/08-tests-utilisabilite.md) |
| — | État du projet et feuille de route | [docs/07-etat-et-feuille-de-route.md](docs/07-etat-et-feuille-de-route.md) |

## Architecture en bref

```
packages/statomea_core/   Moteur statistique déterministe, Dart pur (aucune dépendance Flutter)
app/statomea/             Application Flutter (Android, iOS, web)
validation/r/             Scripts R produisant les valeurs de référence
demos/                    Données des démonstrations (simulées ou publiques)
docs/                     Livrables
```

Le moteur ne fait appel à aucune IA : il produit pour chaque analyse les estimations, les
hypothèses vérifiées, les alertes, un journal et une interprétation par gabarits déterministes.

## Prérequis

- Flutter ≥ 3.47 (Dart ≥ 3.13). Sur ce poste : `~/development/flutter/bin`.
- Pour revalider : R ≥ 4.2 avec `jsonlite`, `metafor`, `logistf`, `pROC`, `sandwich`, `car`, `pmsampsize`, `survival`, `mada`, `mice`, `rstatix`, `HardyWeinberg`, `MASS` ; `statmod`, `vcfR`, `genio`, `rrBLUP`, `GMMAT`, `MendelianRandomization`, `psych` ; Bioconductor `snpStats`, `SNPRelate` ; Bioconductor `edgeR`, `limma`, `Biostrings` ; BLAST+ 2.17 (variable `BLAST_BIN`, par défaut `~/development/ncbi-blast-2.17.0+/bin`). Sur ce poste, R 4.2.3 est une version x86_64 : installer les paquets avec `type = "binary"`.
- Pour Android : SDK Android (installé sur ce poste, API 36). Pour iOS : Xcode complet et CocoaPods (Xcode incomplet sur ce poste : `flutter doctor` le signale).

## Installer et lancer

```bash
cd packages/statomea_core && dart pub get && dart test
```

```bash
cd app/statomea && flutter pub get && flutter test
```

Version web (fonctionne hors connexion : CanvasKit et polices servis localement) :

```bash
cd app/statomea && flutter build web --release --no-web-resources-cdn
```

```bash
python3 -m http.server 8792 --directory app/statomea/build/web
```

Android. Gradle n'arrive pas à écrire ses caches dans un dossier synchronisé par OneDrive : construire depuis une
copie locale (le moteur doit être copié à côté, l'application l'importe par `../../packages/statomea_core`).

```bash
rsync -a --exclude build --exclude .dart_tool --exclude android/.gradle app packages /tmp/statomea_build/
```

```bash
cd /tmp/statomea_build/app/statomea && flutter build apk --release
```

L'APK obtenu (`build/app/outputs/flutter-apk/app-release.apk`) est signé avec la clé de débogage : il s'installe sur un
appareil ou un émulateur (`adb install`) mais ne peut pas être publié sur Google Play sans une clé de publication.
Depuis la 1.36.5, l'APK a la seule permission Internet, pour lire le numéro de version publié (`android.json`) et signaler une mise à jour ; désactivable dans l'écran Validation, aucune donnée de l'utilisateur n'est envoyée. APK par architecture (depuis 1.36.10, ~30 Mo au lieu de 75) : https://statomea.komodi-labo.org/telecharger/statomea-arm64-v8a.apk (presque tous les téléphones) et statomea-armeabi-v7a.apk (anciens 32 bits) ; statomea.apk renvoie à la version arm64. L'application lit android.json et télécharge l'APK de son architecture. Copies dans `dist/` (hors dépôt). L'APK est signé avec la clé de débogage du poste de construction : les mises à jour doivent être construites sur ce même poste.

iOS (poste avec Xcode complet) :

```bash
cd app/statomea && flutter build ipa --release
```

## Valider

```bash
./validation/run_all.sh
```

Régénère toutes les références avec R, puis exécute les 400 tests du moteur et les tests de
l'application. Maquettes (captures de l'application réelle) :

```bash
cd app/statomea && flutter test test/maquettes_test.dart --tags maquettes --run-skipped --update-goldens
```

## Ce qui est opérationnel, testé, en développement

| Module | Opérationnel | Testé contre | Statut |
|---|---|---|---|
| Projets en 10 étapes, stockage local, suppression complète ; projet créé depuis un protocole Word (.docx) ou PDF (texte extrait hors connexion, sections reconnues) ; caractéristiques déduites de la question pendant la saisie (plan, objectif, issue, exposition, PICO, horizon), sans écraser les choix du chercheur ; feuille de route des 10 étapes imprimable en PDF, avec le calcul d'effectif adapté à la question ; relecture méthodologique avec corrections applicables d'un appui (effectif recalculé, majoration pour les pertes, ajustement, validation d'un modèle prédictif, tests appariés au nombre de groupes, multiplicité, effet centre, randomisation et aveugle d'un essai, critères d'inclusion, faisabilité du recrutement…), conformité SPIRIT / STROBE / STARD / TRIPOD, calculateur d'effectif prérempli (dont corrélation et Riley), dictionnaire de données tiré du protocole et protocole Word d'origine annoté de commentaires ; fiche de recueil imprimable et masque de saisie Excel (listes déroulantes, bornes) ; résultats confrontés au protocole ; chronogramme (Gantt) et budget prévisionnel ; examens de laboratoire lus dans les rubriques de dosage (avec la méthode) ; Tableau 1 automatique (Word, Excel) ; article prérédigé IMRaD en Word ; diagramme de flux CONSORT/STROBE ; Tableau 2 des associations brutes et ajustées ; bibliographie (RIS, BibTeX, PubMed) au style de Vancouver ; protocole prérédigé exportable en Word (.docx) et PDF (rubriques d'un comité d'éthique, éléments à compléter surlignés) ; rôles des variables (issue, exposition, ajustement) qui préremplissent les calculateurs | ✅ | tests app | validé |
| Import CSV et Excel (.xlsx), saisie, éditeur de données (corriger une cellule, ajouter ou exclure une ligne, toujours journalisé), dictionnaire de variables (types, unités, bornes, codes manquants, modalités), contrôle des données, corrections journalisées | ✅ | tests de détection, readxl | validé |
| Imputation multiple (MICE) et règles de Rubin, y compris dans la validation interne | ✅ | mice | validé |
| Assistant de choix de méthode | ✅ | scénarios | validé |
| Descriptif, proportions, 2 × 2, Fisher, diagnostic, comparaisons, apparié, corrélation, Bland-Altman, tailles d'échantillon, survie (Kaplan-Meier, log-rank) | ✅ | R, survival | validé |
| Comparaison de méthodes de laboratoire : Passing-Bablok (IC analytique) et Deming (IC jackknife), biais aux niveaux de décision | ✅ | mcr | validé |
| Bayésien d'introduction : proportion bêta-binomiale (a priori uniforme, Jeffreys, informatif), réinterprétation d'un effet publié (a priori sceptique, enthousiaste, vague) | ✅ | qbeta, pbeta, qnorm | validé |
| Équivalence et non-infériorité (TOST : moyennes, appariées, proportions) ; valeur E de la confusion non mesurée | ✅ | TOSTER, EValue | validé |
| Séries chronologiques interrompues : régression segmentée, ES de Newey-West, quasi-Poisson avec population | ✅ | lm, glm, sandwich | validé |
| Laboratoire : intervalles de référence (CLSI EP28 : non paramétrique avec IC, paramétrique, robuste ; valeurs aberrantes de Horn ; partition de Harris et Boyd) et fidélité (EP05, EP15 : composantes de la variance, IC, vérification d'une fidélité annoncée) | ✅ | referenceIntervals, MASS, VCA | validé |
| Régressions linéaire, logistique, Poisson robuste, Firth (IC profilés pénalisés), Cox | ✅ | lm, glm, sandwich, car, logistf, survival | validé |
| Splines cubiques restreintes : test de non-linéarité, courbe dose-effet relative à la médiane | ✅ | rms, Hmisc | validé |
| Score de propension : appariement 1:1 (caliper), IPTW ATE et ATT, équilibre (différences standardisées, love plot), effet avec ES robuste | ✅ | MatchIt, WeightIt, cobalt, sandwich | validé |
| Risques concurrents : incidence cumulée d'Aalen-Johansen (variance de Gray), test de Gray, modèle de Fine-Gray et Cox spécifique de cause | ✅ | cmprsk, survival | validé |
| Comptages (Poisson avec offset, quasi-Poisson, binomiale négative) ; issues ordinales (cotes proportionnelles) et nominales (multinomiale) | ✅ | glm, MASS, nnet | validé |
| Mesures répétées : modèle linéaire mixte (intercept et pente aléatoires, REML, ddl de nlme), trajectoires ; GEE (gaussienne, binomiale, Poisson ; indépendance ou échangeable ; variance robuste) ; modèle mixte logistique ou de Poisson (Laplace, Gauss-Hermite adaptative) | ✅ | lme4, nlme, geepack, gee, vraisemblance exacte (integrate) | validé |
| Puissance et effectif : moyennes (groupes inégaux, apparié), proportions, cas-témoins, survie (Freedman, Schoenfeld), GWAS ; courbe de puissance | ✅ | pwr, powerSurvEpi, stats | validé |
| Survie : temps moyen de survie restreint (RMST, RMTL, différence et rapports) et analyse landmark | ✅ | survRM2, survival | validé |
| Cox avec covariables dépendant du temps (processus de comptage, découpage à une date de changement) | ✅ | survival (coxph, tmerge) | validé |
| Métaanalyse binaire et continue, forest plot, sensibilité, sous-groupes, méta-régression, métaanalyse diagnostique bivariée | ✅ | metafor, mada | validé |
| Prédiction : développement, validation interne bootstrap, validation externe et recalibration | ✅ | glm, pROC, pmsampsize | validé |
| Calibration de risques prédits : Hosmer-Lemeshow, Spiegelhalter, courbe lissée (lowess), Eavg/E90/Emax | ✅ | ResourceSelection, rms | validé |
| Génomique : import de génotypes VCF/PLINK, contrôle de qualité, apparentement (KING), ACP de stratification, modèle mixte linéaire (option LOCO) et logistique, régression LD score, corrélation génétique, score de risque polygénique et randomisation mendélienne (y compris à partir de deux GWAS complets, allèles harmonisés), association génétique, pathogènes (mutations–résistance, typage), qPCR, RNA-seq (TMM + voom + limma, plans à plusieurs facteurs, appariés ou à mesures répétées), alignement local hors ligne type BLAST | ✅ | HardyWeinberg, glm, MASS, vcfR, snpStats, rrBLUP, GMMAT, MendelianRandomization, pROC, edgeR, limma, Biostrings, BLAST+ 2.17 | validé |
| Formation (24 leçons), grilles TRIPOD+AI / PROBAST+AI / PRISMA | ✅ | — | contenu à relire par des enseignants |
| Audit contradictoire | ✅ | corpus annoté | heuristique pour la partie lexicale |
| Exports PDF, HTML, CSV, JSON | ✅ | tests app | validé |
| Android | ✅ APK par architecture, mise à jour intégrée à l'application, essayé sur émulateur (API 37) | démos 1, 3 et 4, atelier génomique | signé avec la clé de publication (`~/.statomea`, mot de passe dans le trousseau macOS ; même certificat que les versions précédentes, vérifié à chaque publication) ; essai sur appareil réel à faire |
| iOS | ✅ construit (Xcode 27, Swift Package Manager) et installé sur iPhone 15 Pro Max (iOS 26.6) | simulateur iPhone 16e, appareil réel | compte Apple gratuit : installation depuis Xcode, valable 7 jours ; TestFlight/App Store avec le programme développeur |
| Version anglaise | ✅ complète | test « aucun fragment français » | relecture par un anglophone à prévoir |

## Données des démonstrations

- Démo 1 (AgHBs) et démo 3 (cardiométabolique) : **données simulées**, scripts et graines dans
  `validation/r/`. Elles ne décrivent aucune population réelle.
- Démo 2 : 13 essais publiés du BCG (Colditz et al., JAMA 1994 ; jeu public `dat.bcg` de metafor).
- Randomisation mendélienne : 28 variants publiés LDL-cholestérol / maladie coronarienne (Waterworth et al. 2010), jeu d'exemple du paquet R MendelianRandomization (`demos/mr_ldl_chd.csv`).
- Comptages et issues ordinales (paquet MASS) : absences scolaires `quine` (`demos/absences_quine.csv`), sinistres `Insurance` avec offset (`demos/sinistres_assurance.csv`), satisfaction du logement `housing` (`demos/satisfaction_logement.csv`).
- Mesures répétées : étude de privation de sommeil (18 sujets, 10 jours, jeu `sleepstudy` de lme4, `demos/sommeil_belenky.csv`) et essai simulé de suivi de l'HbA1c avec sorties d'étude (`demos/hba1c_longitudinal_simule.csv`).
- Démo 8 (survie avancée) : rechute avec décès concurrent et greffe de Stanford, de la question au rapport, avec un brouillon à auditer.
- Démo 9 (laboratoire) : créatinine sur sérum et sur plasma chez 108 patients, jeu `creatinine` du paquet R mcr (`demos/creatinine_serum_plasma.csv`).
- Intervalles de référence et fidélité : créatinine **simulée** par sexe (`demos/creatinine_reference_simule.csv`) et plan EP15 simulé (`demos/fidelite_ep15_simule.csv`) ; plan EP05 d'exemple du paquet R VCA.
- Démo 10 (santé publique) : série interrompue **simulée** de 48 mois (politique au mois 25), du piège avant/après au modèle quasi-Poisson.
- Équivalence : essai **simulé** de deux formulations (`demos/equivalence_formulations_simule.csv`) ; série interrompue **simulée** de 48 mois (`demos/serie_interrompue_simule.csv`).
- Score de propension : étude observationnelle **simulée** des statines (`demos/statines_observationnel_simule.csv`, `validation/r/53_propension.R`).
- Biais du temps immortel : programme de greffe cardiaque de Stanford (103 patients, jeu `jasa` du paquet R survival, `demos/greffe_stanford.csv`).
- Risques concurrents : 400 patients simulés, rechute après traitement d'un cancer avec le décès comme événement concurrent (`demos/risques_concurrents_simule.csv`).
- Randomisation mendélienne à partir de deux GWAS complets (simulés, 12 000 variants) : exposition au format GWAS-SSF, issue au format TwoSampleMR à harmoniser (`demos/gwas_exposition_simule.tsv`, `demos/gwas_issue_simule.tsv`).
- Démos 4, 5 et 6 (tuberculose, GWAS, polygénie) : **données simulées** (`validation/r/24_demo_tb.R`, `29_demo_gwas.R`, `32_ldsc.R`, `33_rg.R`).

## Licences des ressources

Polices Noto Sans et Noto Sans Math : SIL Open Font License 1.1 (`app/statomea/assets/fonts/OFL.txt`).
Les grilles TRIPOD+AI, PROBAST+AI et PRISMA 2020 sont des paraphrases pédagogiques ; se référer aux
publications originales citées dans l'application.

## Déploiement web

Site https://statomea.komodi-labo.org (VPS partagé, façade Caddy de NexoLab) : page d'accueil à la racine (`deploy/landing/`, HTML et CSS seuls, captures de `docs/maquettes/`), application web sous `/app/`, APK sous `/telecharger/`.
Depuis le Mac : `bash deploy/publish-web.sh` (construit l'application et met à jour la branche `web` : site + fichiers
de déploiement). Sur le VPS, première installation :
`git clone --branch web --single-branch https://github.com/Modibo/Statomea.git /opt/statomea && bash /opt/statomea/install.sh` ;
mises à jour : `cd /opt/statomea && git fetch -q && git reset -q --hard origin/web && bash install.sh` (la branche `web` est un instantané republié à chaque version, avec l'APK si `BUILD_APK=1`).

## Avertissement

**Outil d'aide et de formation — pas un dispositif médical.** Statoméa aide à formuler la question de recherche, à
choisir, vérifier et interpréter une analyse statistique. Il ne remplace ni le jugement du chercheur, ni la relecture par
un méthodologiste ou un statisticien, ni la validation clinique. Les démonstrations reposent sur des données simulées ou
publiées et ne décrivent aucune population réelle. Vérifiez tout résultat avant une publication ou une décision.

## Conception

Conçu par le **Dr. Modibo Mouctar COULIBALY** — PharmD, CLMS, PhD · Maître de Recherche, Hôpital Sominé DOLO de Mopti
(Mali).
