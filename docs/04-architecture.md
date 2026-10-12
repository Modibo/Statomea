# 04 — Architecture technique et modèle de données

## Vue d'ensemble

```
Statomea/
  packages/statomea_core/        Moteur statistique DÉTERMINISTE — Dart pur, sans Flutter
    lib/src/math/                Fonctions spéciales, lois, algèbre linéaire (QR, Cholesky), RNG xorshift128
    lib/src/model/               AnalysisResult, Estimate, Check, Alert, Interpretation ; plan d'étude
    lib/src/descriptive/         Statistiques descriptives, rangs
    lib/src/inference/           Proportions, 2 × 2, Fisher, diagnostic, comparaisons, apparié, corrélation,
                                 Bland-Altman, tailles d'échantillon
    lib/src/regression/          Matrice de plan (codage, transformations, interactions), linéaire, GLM
                                 (logistique, Poisson robuste, Firth), Cox, GVIF, mode « petit nombre d'événements »
    lib/src/meta/                Effets individuels, IV/DL/REML/HK/MH, hétérogénéité, sensibilité, sous-groupes, Egger
    lib/src/prediction/          AUC/DeLong, calibration, Brier, courbe de décision, Riley, bootstrap d'optimisme (avec ou sans
                                 imputation multiple), validation externe et recalibration
    lib/src/data/                Dataset immuable + corrections journalisées, CSV, contrôle de qualité
    lib/src/advisor/             Registre des méthodes (statut, conditions, référence) et assistant de choix
    lib/src/audit/               Audit contradictoire (structuré + lexical)
    lib/src/pedagogy/            17 leçons, exercices, grilles TRIPOD+AI / PROBAST+AI / PRISMA (paraphrases)
    lib/src/project/             Projet en 10 étapes, journal de calcul, 5 démonstrations
    lib/src/report/              Figures SVG, rapport HTML, CSV, journal JSON
    test/ + test/reference/      Tests et valeurs de référence produites par R
    tool/gen_matrix.dart         Génère docs/02-matrice-methodes.md depuis le registre
  app/statomea/                  Application Flutter (Android, iOS, web)
    lib/state/                   AppState (projets, mode guidé/expert, langue)
    lib/services/                Stockage local, enregistrement de fichiers (web/natif), export PDF
    lib/screens/                 Accueil, projet (10 étapes), calculs, formation, validation
    lib/widgets/                 Calculateurs, ateliers (régression, métaanalyse, prédiction), ResultView
    lib/l10n/                    Chaînes d'interface FR (modèle) et EN
    assets/                      Polices Noto (OFL), CSV des démonstrations
  validation/r/                  Scripts R produisant les références (graines fixées)
  demos/                         Données des démonstrations (simulées ou publiques)
  docs/                          Livrables
```

## Séparation moteur / présentation / IA

1. **Moteur** : fonctions pures `entrées → AnalysisResult`. Aucune horloge, aucun réseau, aucun état
   global. L'aléa (bootstrap) vient d'une graine (`SeededRandom`, xorshift128 sur 32 bits, même suite sur
   VM, web et mobile) ou d'indices fournis (utilisés pour rejouer exactement le bootstrap de R).
2. **Interprétations** : produites par le moteur à partir de gabarits déterministes, donc testables.
3. **Assistant IA** : *absent de la V1*. Point d'extension prévu (non implémenté) : un service qui
   reçoit uniquement `AnalysisResult.toJson()` et le texte du chercheur, et renvoie une proposition de
   rédaction ; tout nombre de la proposition doit être retrouvé à l'identique dans le JSON, sinon la
   proposition est rejetée ; la proposition passe ensuite par l'audit. L'IA ne calcule rien.

## Modèle de données

```
Project
 ├─ id, title, createdAt, demoNotice, expertMode
 ├─ question : ResearchQuestion (PICO, horizon, plan, objectif, types, appariement, ajustement…)
 ├─ analysisPlan : texte
 ├─ dataset : Dataset ?
 │    ├─ names, original (cellules texte IMMUABLES), source
 │    ├─ dictionary : {variable → Variable(type, unité, min, max, référence, déclaré?)}
 │    └─ corrections : [Correction(id, variable, action, lignes, de, vers, justification, auteur, horodatage)]
 ├─ studies : [Study(id, label, sous-groupe, values{clé → SourcedValue(valeur, statut, source, note)},
 │                   compatibility(population, comparateur, critère, suivi, mesure), excluded, raison)]
 ├─ predictionSpec : PredictionSpec ?(population, issue, horizon, usage, prédicteurs, modèle de référence)
 ├─ journal : [JournalEntry(id, horodatage, méthode, empreinte FNV-1a des données, ids des corrections,
 │                          options, résultat complet, version du moteur, note)]
 ├─ resultsText : texte soumis à l'audit
 ├─ checklistAnswers : {"grille:item" → réponse}
 └─ completed : étapes terminées

AnalysisResult
 ├─ methodId, methodName, status (validée | en développement)
 ├─ inputs, formula
 ├─ estimates : [Estimate(label, valeur, borne inf, borne sup, niveau, p, ES, nature de l'intervalle : IC | IP …)]
 ├─ statistics : {nom → valeur}
 ├─ checks : [Check(id, libellé, statut ok | à surveiller | non satisfaite | non évaluable, détail)]
 ├─ alerts : [Alert(code, gravité info | prudence | grave | bloquant, message, suggestion, déclencheur)]
 ├─ tables, figures (données des graphiques), log
 └─ interpretation : (pourquoi cette méthode ? que signifie le résultat ? quelles conclusions restent injustifiées ?)
```

Un résultat est **fiable** (`reliable`) si la méthode est validée et qu'aucune alerte n'est
bloquante ; l'interface et l'audit s'appuient sur ce drapeau.

## Persistance et confidentialité

- Stockage local (`shared_preferences` : localStorage sur le web, préférences natives sur mobile),
  un document JSON par projet ; suppression = effacement du document et de ses clés.
- Aucun compte, aucun serveur, aucune télémétrie. Les exports sont des fichiers que l'utilisateur
  décide de partager.
- La version web est construite avec `--no-web-resources-cdn` : CanvasKit et polices servis par
  l'application (vérifié : aucune requête hors de l'hôte).

## Localisation

Chaînes d'interface dans `lib/l10n/app_fr.arb` (modèle) et `app_en.arb` (`flutter gen-l10n`).
Les textes produits par le moteur (messages, interprétations, leçons) sont en français ; leur
traduction exigera un catalogue de messages indexé par les codes déjà présents (`Alert.code`,
`Check.id`, identifiants de leçon) — non réalisé en V1.

## Choix techniques et raisons

| Choix | Raison |
|---|---|
| Flutter + moteur Dart pur | Une base de code pour Android, iOS, web ; même patron que BioSigma/BioChiméa ; calculs hors connexion sur l'appareil |
| Références R rejouées en tests | Validation chiffrée contre des logiciels reconnus, reproductible (`validation/run_all.sh`) |
| QR de Householder pour MCO | Stabilité numérique, détection des colonnes colinéaires |
| Figures SVG produites par le moteur | Mêmes figures dans l'application (`flutter_svg`), le PDF (`pdf`) et le HTML |
| PDF généré dans l'application | Hors connexion, polices Noto embarquées (couverture Unicode des symboles statistiques) |
