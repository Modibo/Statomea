import 'package:statomea_core/statomea_core.dart' hide Step;

/// Ce que montre chaque mode d'affichage (écran « Que changent les modes ? » et guide d'utilisation). Les calculs du
/// moteur sont les mêmes dans les deux modes : seuls le niveau de détail affiché et les réglages proposés changent.
List<String> get guidedModePoints => [
      tr('Résultat principal, alertes importantes, trois questions pour interpréter et conditions d\'application.',
          'Main result, important alerts, three questions to interpret and conditions of use.'),
      tr('Réglages courants choisis pour vous : niveau de confiance 95 %, test de Welch, Efron pour les ex aequo d\'un modèle de Cox…',
          'Usual settings chosen for you: 95% confidence level, Welch test, Efron for ties in a Cox model…'),
      tr('Un tableau de résultats, s\'il est fiable.', 'One results table, if reliable.'),
    ];

List<String> get expertModePoints => [
      tr('Toutes les estimations, tous les tableaux et toutes les alertes ; détail de chaque condition vérifiée.',
          'All estimates, tables and alerts; details of each condition checked.'),
      tr('Méthode, formule et journal de calcul ; valeur brute même pour un résultat non fiable.', 'Method, formula and computation log; raw value even for an unreliable result.'),
      tr('Réglages avancés : niveau de confiance, test de Student, transformations et interactions en régression, ex aequo de Cox, approximation des modèles mixtes, graine des tirages, seuils du contrôle de qualité des génotypes, bornes plausibles des variables.',
          'Advanced settings: confidence level, Student\'s test, transformations and interactions in regression, Cox ties, mixed-model approximation, random seed, genotype quality-control thresholds, plausible bounds of variables.'),
      tr('Complétude PICO de la question (étape 1).', 'PICO completeness of the question (step 1).'),
    ];

String get modesSameEngine => tr('Les calculs sont identiques dans les deux modes ; on peut changer à tout moment sans rien perdre.',
    'Computations are identical in both modes; you can switch at any time without losing anything.');
