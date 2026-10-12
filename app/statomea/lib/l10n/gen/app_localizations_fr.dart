// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Statoméa';

  @override
  String get navProjects => 'Projets';

  @override
  String get navCalculators => 'Calculs';

  @override
  String get navLearn => 'Formation';

  @override
  String get navValidation => 'Validation';

  @override
  String get modeGuided => 'Guidé';

  @override
  String get modeExpert => 'Expert';

  @override
  String get newProject => 'Nouveau projet';

  @override
  String get demos => 'Démonstrations';

  @override
  String get deleteProject => 'Supprimer le projet';

  @override
  String deleteConfirm(String title) {
    return 'Supprimer définitivement « $title » et toutes ses données de cet appareil ?';
  }

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get compute => 'Calculer';

  @override
  String get offlineNote =>
      'Tous les calculs et les leçons fonctionnent hors connexion ; aucune donnée ne quitte l\'appareil.';

  @override
  String get languageLabel => 'Langue';
}
