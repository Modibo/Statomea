# 08 — Protocole de tests d'utilisabilité

Objectif : observer de vrais utilisateurs réaliser des tâches typiques avec Statoméa, mesurer ce qui réussit, ce qui
bloque et le temps nécessaire, avant d'ajouter de nouvelles fonctions. Cinq participants révèlent déjà la plupart des
problèmes majeurs ; huit permettent de couvrir les trois profils.

## 1. Participants

| Profil | Nombre | Recrutement |
|---|---|---|
| Étudiants (médecine, pharmacie, master de santé publique) ayant suivi un cours de statistique | 2 à 3 | Promotion en cours, volontaires |
| Biologistes ou cliniciens qui analysent leurs propres données | 2 à 3 | Laboratoire, service hospitalier |
| Enseignants de biostatistique ou de méthodologie | 1 à 2 | Collègues |

Critères : jamais utilisé Statoméa ; aucun lien hiérarchique avec l'observateur pendant la séance. Consentement oral
enregistré en début de séance (participation volontaire, possibilité d'arrêter à tout moment, données anonymisées,
aucun jugement des compétences : c'est l'application qui est évaluée).

## 2. Déroulement (60 minutes par participant)

1. **Accueil (5 min)** : présentation, consentement, questions de profil (formation, logiciels utilisés, aisance en
   statistique de 1 à 5).
2. **Consigne « penser à voix haute » (2 min)** : « Dites ce que vous cherchez, ce que vous pensez, ce qui vous
   surprend. Je ne peux pas vous aider pendant les tâches ; si vous êtes bloqué plus de 3 minutes, dites-le. »
3. **Tâches (40 min)** : dans l'ordre ci-dessous, sur l'appareil habituel du participant (téléphone ou ordinateur).
4. **Questionnaire SUS (5 min)** et **entretien (8 min)**.

L'observateur note sans intervenir. Si le participant est bloqué plus de 3 minutes, l'observateur donne l'indice
prévu et note « aidé ». Enregistrer l'écran si le participant l'accepte.

## 3. Tâches

Partir à chaque fois de l'écran d'accueil (Projets). Temps cible = temps d'un utilisateur averti × 3.

| N° | Tâche (lue au participant) | Réussite si | Temps cible | Indice si bloqué |
|---|---|---|---|---|
| T1 | « Vous voulez comparer la pression artérielle de deux groupes de patients. Trouvez la méthode qui convient et calculez-la avec les valeurs proposées. » | Résultat d'un test de comparaison de 2 groupes affiché | 3 min | « Il y a une rubrique Calculs. » |
| T2 | « Ouvrez la démonstration sur la créatinine (plasma ou sérum) et dites-moi si les deux dosages peuvent être utilisés indifféremment. » | Cite le biais constant ou les limites d'accord, pas la corrélation | 6 min | « Regardez l'étape Interprétation. » |
| T3 | « Le texte de résultats de cette démonstration contient des erreurs. Trouvez-en au moins deux avec l'application. » | Lance l'audit et explique 2 alertes | 6 min | « Une étape s'appelle Audit. » |
| T4 | « Créez un projet, importez ce fichier de données (CSV fourni) et vérifiez s'il contient des valeurs anormales. » | Projet créé, données importées, contrôle consulté | 8 min | « Les données s'importent à l'étape 4. » |
| T5 | « Dans ce projet, une issue binaire dépend de l'âge et du sexe : obtenez un odds ratio ajusté. » | Régression logistique avec les deux covariables | 8 min | « Il y a un atelier de régression. » |
| T6 | « Exportez le rapport de ce projet pour l'envoyer à un collègue. » | Fichier PDF ou HTML produit | 4 min | « Dernière étape du projet. » |
| T7 (facultative, enseignants) | « Trouvez une leçon qui explique la différence entre OR et RR et faites l'exercice. » | Leçon ouverte, exercice répondu | 4 min | « Rubrique Formation. » |

Fichiers à préparer : un CSV de 200 lignes contenant 3 anomalies volontaires (une valeur impossible, un doublon, une
modalité mal orthographiée) et une issue binaire avec âge et sexe.

## 4. Grille d'observation (une ligne par tâche)

| Tâche | Réussie seul / aidée / échec | Temps (min:s) | Erreurs (chemins sans issue, retours) | Hésitations et citations | Gravité du problème (1–4) |
|---|---|---|---|---|---|
| T1 | | | | | |
| T2 | | | | | |
| T3 | | | | | |
| T4 | | | | | |
| T5 | | | | | |
| T6 | | | | | |
| T7 | | | | | |

Gravité : 1 = cosmétique ; 2 = gêne mineure ; 3 = gêne majeure (réussite ralentie ou aidée) ; 4 = bloquant (échec).

## 5. Questionnaire SUS (System Usability Scale, version française)

Réponse de 1 (pas du tout d'accord) à 5 (tout à fait d'accord).

1. Je pense que j'aimerais utiliser cette application fréquemment.
2. J'ai trouvé l'application inutilement complexe.
3. J'ai trouvé l'application facile à utiliser.
4. Je pense que j'aurais besoin de l'aide d'une personne compétente pour pouvoir l'utiliser.
5. J'ai trouvé que les différentes fonctions de l'application étaient bien intégrées.
6. J'ai trouvé qu'il y avait trop d'incohérences dans l'application.
7. J'imagine que la plupart des gens apprendraient très vite à utiliser cette application.
8. J'ai trouvé l'application très contraignante à utiliser.
9. Je me suis senti(e) très en confiance en utilisant l'application.
10. J'ai dû apprendre beaucoup de choses avant de pouvoir utiliser l'application.

Score : pour les items impairs, score − 1 ; pour les items pairs, 5 − score ; somme × 2,5 (de 0 à 100). Repères :
68 = moyenne des applications évaluées ; ≥ 80 = très bonne utilisabilité ; < 50 = problèmes sérieux.

## 6. Entretien final

1. Qu'avez-vous trouvé le plus utile ? Le plus difficile ?
2. À quel moment vous êtes-vous senti(e) perdu(e) ?
3. Les messages d'alerte et les interprétations étaient-ils compréhensibles ? Exemple ?
4. Utiliseriez-vous Statoméa pour vos propres analyses ou pour enseigner ? Pourquoi ?
5. Que manque-t-il pour que vous l'utilisiez ?

## 7. Analyse

- Par tâche : taux de réussite sans aide, temps médian, nombre d'erreurs.
- SUS : moyenne et étendue, par profil.
- Problèmes : regrouper les observations identiques, compter les participants touchés, retenir la gravité maximale.
  Priorité = gravité × nombre de participants touchés.
- Livrable : tableau des problèmes classés, avec la capture ou la citation, la correction proposée et la version qui
  la corrige ; refaire les tâches concernées après correction (2 ou 3 participants suffisent).

## 8. Matériel

Téléphone ou ordinateur du participant (version web à jour, ou application Android/iOS), fichiers d'exercice, grille
imprimée ou tableur, chronomètre, formulaire SUS, enregistreur d'écran si accepté.
