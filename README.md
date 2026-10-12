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
| 7 | Sept démonstrations complètes | [docs/06-demonstrations.md](docs/06-demonstrations.md) |
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
Le paquet publié n'a aucune permission Internet. La version 1.16.0 (génomique et démonstration 4 comprises) est rangée dans `dist/` (hors dépôt), à côté de 1.10.0 ; empreinte SHA-256 de `statomea-1.16.0.apk` : `fe58141690b6da322ef72ed28f488c11f24f702ce970b65448bd6ac94290cd9d`.

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
| Projets en 10 étapes, stockage local, suppression complète | ✅ | tests app | validé |
| Import CSV, saisie, contrôle des données, corrections journalisées | ✅ | tests de détection | validé |
| Imputation multiple (MICE) et règles de Rubin, y compris dans la validation interne | ✅ | mice | validé |
| Assistant de choix de méthode | ✅ | scénarios | validé |
| Descriptif, proportions, 2 × 2, Fisher, diagnostic, comparaisons, apparié, corrélation, Bland-Altman, tailles d'échantillon, survie (Kaplan-Meier, log-rank) | ✅ | R, survival | validé |
| Régressions linéaire, logistique, Poisson robuste, Firth (IC profilés pénalisés), Cox | ✅ | lm, glm, sandwich, car, logistf, survival | validé |
| Métaanalyse binaire et continue, forest plot, sensibilité, sous-groupes, méta-régression, métaanalyse diagnostique bivariée | ✅ | metafor, mada | validé |
| Prédiction : développement, validation interne bootstrap, validation externe et recalibration | ✅ | glm, pROC, pmsampsize | validé |
| Génomique : import de génotypes VCF/PLINK, contrôle de qualité, apparentement (KING), ACP de stratification, modèle mixte linéaire (option LOCO) et logistique, régression LD score, corrélation génétique, score de risque polygénique et randomisation mendélienne, association génétique, pathogènes (mutations–résistance, typage), qPCR, RNA-seq (TMM + voom + limma, plans à plusieurs facteurs, appariés ou à mesures répétées), alignement local hors ligne type BLAST | ✅ | HardyWeinberg, glm, MASS, vcfR, snpStats, rrBLUP, GMMAT, MendelianRandomization, pROC, edgeR, limma, Biostrings, BLAST+ 2.17 | validé |
| Formation (19 leçons), grilles TRIPOD+AI / PROBAST+AI / PRISMA | ✅ | — | contenu à relire par des enseignants |
| Audit contradictoire | ✅ | corpus annoté | heuristique pour la partie lexicale |
| Exports PDF, HTML, CSV, JSON | ✅ | tests app | validé |
| Android | ✅ APK 1.16.0 construit, installé (mise à jour depuis 1.10.0, projets conservés) et utilisé sur émulateur (API 37) | démos 1, 3 et 4, atelier génomique (alignement et expression appariée calculés en isolat) | signé avec la clé de débogage ; essai sur appareil réel à faire |
| iOS | code prêt | — | non construit : Xcode incomplet sur ce poste |
| Version anglaise | ✅ complète | test « aucun fragment français » | relecture par un anglophone à prévoir |

## Données des démonstrations

- Démo 1 (AgHBs) et démo 3 (cardiométabolique) : **données simulées**, scripts et graines dans
  `validation/r/`. Elles ne décrivent aucune population réelle.
- Démo 2 : 13 essais publiés du BCG (Colditz et al., JAMA 1994 ; jeu public `dat.bcg` de metafor).
- Randomisation mendélienne : 28 variants publiés LDL-cholestérol / maladie coronarienne (Waterworth et al. 2010), jeu d'exemple du paquet R MendelianRandomization (`demos/mr_ldl_chd.csv`).
- Démos 4, 5 et 6 (tuberculose, GWAS, polygénie) : **données simulées** (`validation/r/24_demo_tb.R`, `29_demo_gwas.R`, `32_ldsc.R`, `33_rg.R`).

## Licences des ressources

Polices Noto Sans et Noto Sans Math : SIL Open Font License 1.1 (`app/statomea/assets/fonts/OFL.txt`).
Les grilles TRIPOD+AI, PROBAST+AI et PRISMA 2020 sont des paraphrases pédagogiques ; se référer aux
publications originales citées dans l'application.

## Déploiement web

Version web servie sur https://statomea.komodi-labo.org (VPS partagé, façade Caddy de NexoLab).
Depuis le Mac : `bash deploy/publish-web.sh` (construit l'application et met à jour la branche `web` : site + fichiers
de déploiement). Sur le VPS, première installation :
`git clone --branch web --single-branch https://github.com/Modibo/Statomea.git /opt/statomea && bash /opt/statomea/install.sh` ;
mises à jour : `cd /opt/statomea && git pull && bash install.sh`.
