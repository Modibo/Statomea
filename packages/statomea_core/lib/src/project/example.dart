import '../i18n.dart';

/// Projet d'exemple : protocole fictif qui contient volontairement des erreurs de méthode, que la relecture doit
/// retrouver ([errors]), accompagné de données simulées ([dataAsset], générées par `validation/r`). Les lignes de
/// [headings] sont les titres de section (mis en forme comme titres dans le document Word).
class ExampleProject {
  final String id;
  final String dataAsset; // fichier de données simulées (dossier demos/)
  final List<String> errors; // constats de relecture attendus (identifiants)
  final String _labelFr, _labelEn, _summaryFr, _summaryEn, _fileFr, _fileEn, _dataFr, _dataEn, _fr, _en;
  final List<String> _headingsFr, _headingsEn;
  const ExampleProject(this.id, this.dataAsset, this.errors, this._labelFr, this._labelEn, this._summaryFr, this._summaryEn, this._fileFr, this._fileEn,
      this._dataFr, this._dataEn, this._headingsFr, this._headingsEn, this._fr, this._en);

  String get label => tr(_labelFr, _labelEn);
  String get summary => tr(_summaryFr, _summaryEn);
  String get protocolFileName => tr(_fileFr, _fileEn);
  String get dataFileName => tr(_dataFr, _dataEn);
  String get text => tr(_fr, _en);
  List<String> get headings => currentLang == Lang.fr ? _headingsFr : _headingsEn;
}

/// Les projets d'exemple, du plus simple au plus complet.
const exampleProjects = [
  ExampleProject('aghbs', 'aghbs_simule.csv', ['loss_adjustment', 'no_adjustment', 'causal_wording', 'cross_sectional_incidence', 'ks_normality', 'missing_data'],
      'Étude transversale : portage de l\'AgHBs chez les femmes enceintes', 'Cross-sectional study: HBsAg carriage in pregnant women',
      'Six erreurs cachées : effectif, formulation, plan, ajustement, normalité, données manquantes ; 640 femmes simulées.',
      'Six hidden errors: sample size, wording, design, adjustment, normality, missing data; 640 simulated women.',
      'protocole-exemple-aghbs.docx', 'example-protocol-hbsag.docx', 'exemple-donnees-aghbs.csv', 'example-data-hbsag.csv',
      _aghbsHeadingsFr, _aghbsHeadingsEn, _aghbsFr, _aghbsEn),
  ExampleProject('zinc', 'zinc_essai_simule.csv',
      ['rct_sample_size_short', 'trial_registration', 'rct_randomisation', 'rct_itt', 'interim_without_rule', 'interim_without_dsmb', 'subgroup_interaction'],
      'Essai randomisé : zinc dans la diarrhée aiguë de l\'enfant', 'Randomised trial: zinc for acute diarrhoea in children',
      'Sept erreurs cachées : effectif par bras, enregistrement, randomisation, intention de traiter, analyse intermédiaire, comité, sous-groupes ; 240 enfants simulés.',
      'Seven hidden errors: sample size per arm, registration, randomisation, intention to treat, interim analysis, committee, subgroups; 240 simulated children.',
      'protocole-exemple-zinc.docx', 'example-protocol-zinc.docx', 'exemple-donnees-zinc.csv', 'example-data-zinc.csv',
      _zincHeadingsFr, _zincHeadingsEn, _zincFr, _zincEn),
];

const _aghbsHeadingsFr = ['Titre du projet', 'Avertissement', 'Objectif principal', 'Objectifs spécifiques', 'Type d\'étude', 'Population d\'étude',
    'Nombre de sujets nécessaires', 'Variables étudiées', 'Analyse statistique', 'Considérations éthiques'];
const _aghbsHeadingsEn = ['Project title', 'Notice', 'Primary objective', 'Specific objectives', 'Study design', 'Study population', 'Sample size',
    'Variables', 'Statistical analysis', 'Ethical considerations'];

const _aghbsFr = '''Titre du projet
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

const _aghbsEn = '''Project title
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

const _zincHeadingsFr = ['Titre du projet', 'Avertissement', 'Objectif principal', 'Type d\'étude', 'Population d\'étude', 'Critère de jugement principal',
    'Nombre de sujets nécessaires', 'Variables étudiées', 'Analyse statistique', 'Considérations éthiques'];
const _zincHeadingsEn = ['Project title', 'Notice', 'Primary objective', 'Study design', 'Study population', 'Primary outcome', 'Sample size', 'Variables',
    'Statistical analysis', 'Ethical considerations'];

const _zincFr = '''Titre du projet
Zinc associé aux sels de réhydratation orale dans la diarrhée aiguë de l'enfant : essai randomisé
Avertissement
Protocole fictif rédigé pour la formation : il contient volontairement des erreurs de méthode. Importez-le dans Statoméa pour les retrouver et les corriger ; les données associées sont simulées.
Objectif principal
Comparer la proportion d'enfants guéris au cinquième jour entre le zinc associé aux sels de réhydratation orale et un placebo associé aux sels de réhydratation orale.
Type d'étude
Essai contrôlé randomisé en double aveugle, à deux bras parallèles, dans le service de pédiatrie de l'hôpital ; allocation par enveloppes opaques scellées.
Population d'étude
Enfants de 6 à 59 mois admis pour une diarrhée aiguë de moins de 72 heures ; non-inclusion : déshydratation sévère, malnutrition aiguë sévère, refus des parents.
Critère de jugement principal
Guérison au cinquième jour : moins de trois selles liquides par 24 heures.
Nombre de sujets nécessaires
Pour montrer une augmentation de la guérison de 60 % à 75 % (puissance 80 %, alpha 5 %), il faut 120 enfants par bras.
Variables étudiées
Les informations suivantes seront recueillies : le bras attribué, l'âge en mois, le sexe, la déshydratation à l'admission, l'observance du traitement, la guérison au cinquième jour et la durée de la diarrhée.
Analyse statistique
Seuls les enfants ayant pris la totalité du traitement seront analysés. Les proportions de guérison seront comparées par le test du khi-deux au seuil de 5 %. Une analyse intermédiaire sera réalisée après l'inclusion de la moitié des enfants. Des analyses en sous-groupes selon l'âge et le sexe seront réalisées.
Considérations éthiques
Le protocole sera soumis au comité d'éthique ; le consentement écrit des parents sera recueilli.
''';

const _zincEn = '''Project title
Zinc with oral rehydration salts for acute diarrhoea in children: a randomised trial
Notice
Fictitious protocol written for training: it deliberately contains methodological errors. Import it into Statoméa to find and correct them; the associated data are simulated.
Primary objective
To compare the proportion of children cured on day five between zinc with oral rehydration salts and placebo with oral rehydration salts.
Study design
Double-blind randomised controlled trial with two parallel arms, in the hospital's paediatric ward; allocation by sealed opaque envelopes.
Study population
Children aged 6 to 59 months admitted for acute diarrhoea of less than 72 hours; non-inclusion: severe dehydration, severe acute malnutrition, parental refusal.
Primary outcome
Cure on day five: fewer than three liquid stools per 24 hours.
Sample size
To show an increase in cure from 60% to 75% (power 80%, alpha 5%), 120 children per arm are needed.
Variables
The following information will be collected: allocated arm, age in months, sex, dehydration at admission, treatment adherence, cure on day five and duration of diarrhoea.
Statistical analysis
Only children who took the full treatment will be analysed. Cure proportions will be compared with the chi-square test at the 5% level. An interim analysis will be performed after half of the children have been included. Subgroup analyses by age and sex will be performed.
Ethical considerations
The protocol will be submitted to the ethics committee; written parental consent will be obtained.
''';
