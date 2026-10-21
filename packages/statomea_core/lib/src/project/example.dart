import '../i18n.dart';

/// Protocole fictif du projet d'exemple : portage de l'AgHBs chez les femmes enceintes, cohérent avec les données
/// simulées `aghbs_simule.csv` (640 femmes, 54 porteuses). Il contient volontairement des erreurs de méthode, que la
/// relecture doit retrouver (voir [exampleProtocolErrors]) ; les titres de section sont les lignes de [exampleHeadings].
String get exampleProtocolText => tr(_fr, _en);

/// Titres de section du protocole d'exemple (mis en forme comme titres dans le document Word).
List<String> get exampleHeadings => tr(_headingsFr.join('\n'), _headingsEn.join('\n')).split('\n');

/// Constats de relecture attendus (identifiants) : les erreurs cachées du protocole d'exemple.
const exampleProtocolErrors = ['loss_adjustment', 'no_adjustment', 'causal_wording', 'cross_sectional_incidence', 'ks_normality', 'missing_data'];

const _headingsFr = ['Titre du projet', 'Avertissement', 'Objectif principal', 'Objectifs spécifiques', 'Type d\'étude', 'Population d\'étude',
    'Nombre de sujets nécessaires', 'Variables étudiées', 'Analyse statistique', 'Considérations éthiques'];
const _headingsEn = ['Project title', 'Notice', 'Primary objective', 'Specific objectives', 'Study design', 'Study population', 'Sample size',
    'Variables', 'Statistical analysis', 'Ethical considerations'];

const _fr = '''Titre du projet
Portage de l'antigène HBs chez les femmes enceintes et transmission mère-enfant de l'hépatite B : étude transversale
Avertissement
Protocole fictif rédigé pour la formation : il contient volontairement des erreurs de méthode. Importez-le dans Statoméa pour les retrouver et les corriger ; les données associées sont simulées.
Objectif principal
Évaluer l'effet de la résidence rurale sur le portage de l'antigène HBs chez les femmes enceintes.
Objectifs spécifiques
1. Estimer l'incidence du portage de l'AgHBs ;
2. Rechercher les facteurs associés au portage (âge, parité, résidence) ;
3. Estimer la fréquence de l'infection des enfants nés de mères porteuses, selon l'AgHBe.
Type d'étude
Étude transversale par recrutement consécutif dans les maternités de la ville, sur douze mois.
Population d'étude
Femmes enceintes de 15 ans ou plus venues en consultation prénatale ; non-inclusion : refus de participer.
Nombre de sujets nécessaires
Avec une prévalence attendue de 8 %, une marge d'erreur de 2,5 % et un niveau de confiance de 95 %, la formule N = Z² p q / i² donne 453 femmes. Pour couvrir les refus, nous ajouterons 10 %, ce qui nous ramènera à 498 femmes.
Variables étudiées
Les informations suivantes seront recueillies : l'âge, la résidence (urbaine ou rurale), la parité, l'AgHBs, l'AgHBe chez les porteuses, le suivi de l'enfant et l'infection de l'enfant.
Analyse statistique
Les données seront saisies dans Excel et analysées avec R. La normalité sera vérifiée par le test de Kolmogorov-Smirnov. Les proportions seront comparées par le test du khi-deux. Le seuil de signification sera fixé à 5 %.
Considérations éthiques
Le protocole sera soumis au comité d'éthique ; un consentement éclairé écrit sera recueilli.
''';

const _en = '''Project title
Hepatitis B surface antigen carriage in pregnant women and mother-to-child transmission of hepatitis B: a cross-sectional study
Notice
Fictitious protocol written for training: it deliberately contains methodological errors. Import it into Statoméa to find and correct them; the associated data are simulated.
Primary objective
To assess the effect of rural residence on hepatitis B surface antigen carriage in pregnant women.
Specific objectives
1. To estimate the incidence of HBsAg carriage;
2. To identify factors associated with carriage (age, parity, residence);
3. To estimate the frequency of infection in children born to carrier mothers, by HBeAg status.
Study design
Cross-sectional study with consecutive recruitment in the city's maternity units, over twelve months.
Study population
Pregnant women aged 15 years or older attending antenatal care; non-inclusion: refusal to participate.
Sample size
With an expected prevalence of 8%, a margin of error of 2.5% and a 95% confidence level, the formula N = Z² p q / i² gives 453 women. To cover refusals, we will add 10%, which brings us to 498 women.
Variables
The following information will be collected: age, residence (urban or rural), parity, HBsAg, HBeAg in carriers, child follow-up and child infection.
Statistical analysis
Data will be entered in Excel and analysed with R. Normality will be checked with the Kolmogorov-Smirnov test. Proportions will be compared with the chi-square test. The significance level will be set at 5%.
Ethical considerations
The protocol will be submitted to the ethics committee; written informed consent will be obtained.
''';
