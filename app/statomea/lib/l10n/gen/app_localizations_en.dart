// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Statoméa';

  @override
  String get navProjects => 'Projects';

  @override
  String get navCalculators => 'Calculators';

  @override
  String get navLearn => 'Learn';

  @override
  String get navValidation => 'Validation';

  @override
  String get modeGuided => 'Guided';

  @override
  String get modeExpert => 'Expert';

  @override
  String get newProject => 'New project';

  @override
  String get demos => 'Demonstrations';

  @override
  String get deleteProject => 'Delete project';

  @override
  String deleteConfirm(String title) {
    return 'Permanently delete “$title” and all its data from this device?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get compute => 'Compute';

  @override
  String get offlineNote =>
      'All calculations and lessons work offline; no data leaves the device.';

  @override
  String get languageLabel => 'Language';
}
