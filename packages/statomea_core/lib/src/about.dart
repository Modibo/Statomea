/// Avertissement d'usage et mention de conception, partagés par l'application et les rapports exportés.
library;

import 'i18n.dart';

/// Titre de l'avertissement.
String get disclaimerTitle => tr('Avertissement', 'Disclaimer');

/// Phrase principale de l'avertissement.
String get disclaimerLead => tr('Outil d\'aide et de formation — pas un dispositif médical.', 'Support and training tool — not a medical device.');

/// Texte de l'avertissement.
String get disclaimerText => tr(
    'Statoméa aide à formuler la question de recherche, à choisir, vérifier et interpréter une analyse statistique. '
        'Il ne remplace ni le jugement du chercheur, ni la relecture par un méthodologiste ou un statisticien, ni la validation clinique. '
        'Les démonstrations reposent sur des données simulées ou publiées et ne décrivent aucune population réelle. '
        'Vérifiez tout résultat avant une publication ou une décision.',
    'Statoméa helps to formulate the research question and to choose, check and interpret a statistical analysis. '
        'It replaces neither the researcher\'s judgement, nor review by a methodologist or a statistician, nor clinical validation. '
        'The demonstrations rely on simulated or published data and describe no real population. '
        'Check every result before a publication or a decision.');

/// Mention de conception.
String get designedBy => tr(
    'Conçu par le Dr. Modibo Mouctar COULIBALY — PharmD, CLMS, PhD · Maître de Recherche, Hôpital Sominé DOLO de Mopti (Mali)',
    'Designed by Dr. Modibo Mouctar COULIBALY — PharmD, CLMS, PhD · Senior Researcher, Sominé DOLO Hospital, Mopti (Mali)');
