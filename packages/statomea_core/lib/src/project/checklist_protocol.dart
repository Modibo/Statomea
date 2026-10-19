/// Conformité d'un protocole aux grilles internationales, choisie selon le plan : SPIRIT 2013 (essai), STROBE
/// (observationnel, éléments applicables au protocole), STARD 2015 (performance diagnostique), TRIPOD (modèle de
/// prédiction), PRISMA-P (revue systématique). Chaque item est recherché dans le texte du protocole par des règles
/// explicites ; « présent » cite le passage trouvé, « absent » signifie que Statoméa ne l'a pas reconnu (à vérifier).
/// Les libellés des items sont résumés, pas recopiés.
library;

import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import '../model/design.dart';
import 'project.dart';

class ProtocolChecklistItem {
  final String code;
  final String label;
  final bool present;
  final String? evidence;
  const ProtocolChecklistItem(this.code, this.label, this.present, this.evidence);
}

class ProtocolChecklist {
  final String name; // SPIRIT 2013…
  final String reference;
  final List<ProtocolChecklistItem> items;
  const ProtocolChecklist(this.name, this.reference, this.items);
  int get present => items.where((i) => i.present).length;
  List<ProtocolChecklistItem> get missing => [for (final i in items) if (!i.present) i];
}

String _n(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'");

typedef _Item = (String code, String fr, String en, String re);

const _common = <String, _Item>{
  'background': ('', 'Contexte et justification', 'Background and rationale', r"contexte et justification|justification|introduction|rationale|background|problematique|\ncontexte"),
  'objectives': ('', 'Objectifs (et hypothèse)', 'Objectives (and hypothesis)', r"\bobjectifs?\b|\bhypothese|\bobjectives?\b|\baims?\b"),
  'setting': ('', 'Lieu(x) et période de l\'étude', 'Setting(s) and study period', r"lieu d'etude|cadre de l'etude|se deroulera (a|au|dans|du)|centres? participants?|periode d'etude|study setting|study period"),
  'eligibility': ('', 'Critères d\'inclusion et de non-inclusion', 'Inclusion and exclusion criteria', r"criteres? d'(inclusion|eligibilite)|non[- ]?inclusion|criteres? d'exclusion|eligibility|inclusion criteria"),
  'outcome': ('', 'Critère de jugement principal défini (et horizon)', 'Primary outcome defined (with time point)', r"critere (de jugement )?principal|critere de jugement|variable principale|evenement principal|primary (outcome|endpoint)"),
  'sampleSize': ('', 'Justification du nombre de sujets', 'Sample size justification', r"nombre de sujets|taille (de l'|d')echantillon|calcul (de l'|d')effectif|sample size"),
  'recruitment': ('', 'Modalités de recrutement', 'Recruitment strategy', r"recrutement|recrute|recruit|inclusion consecutive|consecuti"),
  'dataCollection': ('', 'Recueil des données (fiche, mesures)', 'Data collection (form, measurements)', r"fiche (d'enquete|de recueil)|questionnaire|recueil des donnees|collecte des donnees|\bcrf\b|case report form|methode de (mesure|dosage)"),
  'dataManagement': ('', 'Gestion et qualité des données', 'Data management and quality', r"gestion des donnees|saisie|base de donnees|double (saisie|verification)|controle (de )?qualite|data management"),
  'statistics': ('', 'Méthodes statistiques', 'Statistical methods', r"analyse statistique|methodes? statistiques?|logiciel r\b|stata|spss|regression|statistical analysis"),
  'missing': ('', 'Traitement des données manquantes', 'Handling of missing data', r"donnees manquantes|valeurs manquantes|imputation|missing data"),
  'ethics': ('', 'Avis d\'un comité d\'éthique', 'Ethics committee approval', r"comite d'ethique|comite national d'ethique|avis (favorable|ethique)|ethics committee|institutional review board|\birb\b|validation du protocole par"),
  'consent': ('', 'Consentement éclairé', 'Informed consent', r"consentement|consent"),
  'confidentiality': ('', 'Confidentialité des données', 'Data confidentiality', r"confidential|anonymi|codage|code (unique|d'identification)|identifiant unique"),
  'funding': ('', 'Financement et rôle du financeur', 'Funding and funder\'s role', r"financement|finance par|budget|subvention|bailleur|funding|funded by|grant"),
  'dissemination': ('', 'Diffusion des résultats', 'Dissemination of results', r"publication|diffusion des resultats|valorisation|communication des resultats|dissemination|livrables"),
};

List<_Item> _grid(String name) => switch (name) {
      'SPIRIT' => [
          ('1', 'Titre précisant le plan (essai)', 'Title stating the design (trial)', r"^.{0,300}(essai|randomis|trial)"),
          ('2', 'Enregistrement dans un registre d\'essais', 'Trial registration', r"enregistr\w* (sur|dans|au)|registre d'essais|clinicaltrials|pactr|isrctn|ictrp|trial regist"),
          ('4', 'Financement', 'Funding', _common['funding']!.$4),
          ('5', 'Promoteur, investigateurs et responsabilités', 'Sponsor, investigators and roles', r"promoteur|investigateur (principal|coordonnateur)|sponsor|principal investigator|coordonnat"),
          ('6', 'Contexte, justification et choix du comparateur', 'Background, rationale and choice of comparator', _common['background']!.$4),
          ('7', 'Objectifs et hypothèses', 'Objectives and hypotheses', _common['objectives']!.$4),
          ('8', 'Schéma (supériorité, non-infériorité, bras, ratio)', 'Design (superiority, non-inferiority, arms, ratio)', r"superiorite|non[- ]inferiorite|equivalence|bras|1\s*:\s*1|groupes? paralleles?|parallel|cross-?over"),
          ('9', 'Lieux de l\'étude', 'Study settings', _common['setting']!.$4),
          ('10', 'Critères d\'éligibilité', 'Eligibility criteria', _common['eligibility']!.$4),
          ('11', 'Interventions décrites (dose, durée, administration)', 'Interventions described (dose, duration, route)', r"posologie|\bdose|\bmg\b|administr|duree du traitement|intervention (consiste|sera)|bras (experimental|controle)"),
          ('12', 'Critères de jugement et délais', 'Outcomes and time points', _common['outcome']!.$4),
          ('13', 'Calendrier des visites et des mesures', 'Schedule of visits and assessments', r"calendrier|chronogramme|visites?|\bj0\b|\bm\d+\b|schedule of"),
          ('14', 'Nombre de sujets', 'Sample size', _common['sampleSize']!.$4),
          ('15', 'Recrutement', 'Recruitment', _common['recruitment']!.$4),
          ('16a', 'Génération de la séquence de randomisation', 'Randomisation sequence generation', r"(randomis\w*|tirage au sort)[^.]{0,60}(blocs?|stratifi|informatis|ordinateur|logiciel|liste)|sequence (de randomisation|aleatoire)|liste de randomisation|computer-generated"),
          ('16b', 'Dissimulation de l\'allocation', 'Allocation concealment', r"enveloppes?[^.]{0,30}(opaques?|scellees?|numerotees?)|centralis|dissimul|concealment|iwrs"),
          ('17', 'Aveugle (qui, comment, levée)', 'Blinding (who, how, unblinding)', r"aveugle|insu|masqu|blind|ouvert|open[- ]label"),
          ('18', 'Recueil des données', 'Data collection', _common['dataCollection']!.$4),
          ('19', 'Gestion des données', 'Data management', _common['dataManagement']!.$4),
          ('20', 'Méthodes statistiques (intention de traiter, manquants)', 'Statistical methods (intention to treat, missing data)', r"intention de traiter|intention-to-treat|\bitt\b"),
          ('21', 'Comité de surveillance, analyse intermédiaire', 'Data monitoring committee, interim analysis', r"comite (de surveillance|independant|de suivi)|dsmb|analyse intermediaire|data monitoring|interim analys|monitoring"),
          ('22', 'Événements indésirables (recueil, déclaration)', 'Adverse events (collection, reporting)', r"evenements? indesirables?|effets? (indesirables?|secondaires?)|pharmacovigilance|adverse (events?|effects?)"),
          ('24', 'Avis du comité d\'éthique', 'Ethics approval', _common['ethics']!.$4),
          ('26', 'Consentement éclairé', 'Informed consent', _common['consent']!.$4),
          ('27', 'Confidentialité', 'Confidentiality', _common['confidentiality']!.$4),
          ('31', 'Diffusion des résultats', 'Dissemination', _common['dissemination']!.$4),
        ],
      'STROBE' => [
          ('1', 'Titre ou résumé précisant le plan', 'Title or abstract stating the design', r"^.{0,600}(cohorte|cas[- ]temoins?|transversal|cross[- ]sectional|case[- ]control|cohort|prospecti|retrospecti)"),
          ('2', 'Contexte et justification', 'Background and rationale', _common['background']!.$4),
          ('3', 'Objectifs et hypothèses', 'Objectives and hypotheses', _common['objectives']!.$4),
          ('4', 'Plan d\'étude présenté tôt', 'Study design presented early', r"etude (de cohorte|cas[- ]temoins?|transversale|prospective|retrospective)|type (et (design|duree) )?(de l'|d')etude|study design"),
          ('5', 'Lieux, période de recrutement et de suivi', 'Setting, recruitment and follow-up periods', _common['setting']!.$4),
          ('6', 'Participants : critères d\'éligibilité, sélection', 'Participants: eligibility, selection', _common['eligibility']!.$4),
          ('7', 'Variables définies (issue, expositions, facteurs de confusion)', 'Variables defined (outcome, exposures, confounders)', r"variables? (etudiees?|recueillies|d'interet|explicatives?)|parametres (de l'etude|etudies)|facteurs? de confusion|definition operationnelle|confounder"),
          ('8', 'Sources des données et méthodes de mesure', 'Data sources and measurement', r"methode de (mesure|dosage)|dosage|mesure(e|s)? (par|selon|a l'aide)|questionnaire|automate|dossiers? medicaux|registre|measured (by|with)"),
          ('9', 'Biais et moyens de les limiter', 'Bias and how it is addressed', r"\bbiais|\bbias"),
          ('10', 'Nombre de sujets', 'Study size', _common['sampleSize']!.$4),
          ('11', 'Variables quantitatives : continues ou en classes', 'Quantitative variables: continuous or grouped', r"variables? (quantitatives?|continues?)|en classes|categoris|splines?|forme continue|continuous"),
          ('12a', 'Méthodes statistiques, dont ajustement sur les facteurs de confusion', 'Statistical methods, including adjustment for confounders', r"ajust\w* sur (les )?(facteurs|variables|co-?variables|potentiels)|facteurs? de confusion|(analyse|modele|regression)[^.]{0,30}multivari|adjusted for|multivariable|confounders?"),
          ('12c', 'Données manquantes', 'Missing data', _common['missing']!.$4),
          ('12e', 'Analyses de sensibilité', 'Sensitivity analyses', r"analyses? de sensibilite|sensitivity analys"),
          ('E', 'Avis éthique et consentement', 'Ethics approval and consent', _common['ethics']!.$4),
          ('22', 'Financement', 'Funding', _common['funding']!.$4),
        ],
      'STARD' => [
          ('1', 'Titre identifiant une étude de performance diagnostique', 'Title identifying a diagnostic accuracy study', r"^.{0,400}(sensibilite|specificite|performance diagnostique|valeur diagnostique|precision diagnostique|diagnostic accuracy|test diagnostique)"),
          ('3', 'Contexte : usage prévu du test et rôle clinique', 'Background: intended use and clinical role of the test', _common['background']!.$4),
          ('4', 'Objectifs et hypothèses', 'Objectives and hypotheses', _common['objectives']!.$4),
          ('5', 'Recueil prospectif ou rétrospectif', 'Prospective or retrospective data collection', r"prospecti|retrospecti"),
          ('6', 'Critères d\'éligibilité', 'Eligibility criteria', _common['eligibility']!.$4),
          ('7', 'Mode de recrutement (consécutif, aléatoire)', 'Recruitment basis (consecutive, random)', r"consecuti|aleatoire|tirage au sort|convenance|consecutive|random sample"),
          ('8', 'Lieu et période', 'Setting and dates', _common['setting']!.$4),
          ('10a', 'Test évalué décrit', 'Index test described', r"test (evalue|etudie|index)|index test|technique (evaluee|etudiee)|automate|reactif|kit"),
          ('10b', 'Test de référence décrit', 'Reference standard described', r"test de reference|reference standard|etalon|gold standard|methode de reference"),
          ('12', 'Seuil de positivité prédéfini ou méthode de choix', 'Prespecified positivity threshold or how chosen', r"seuil|cut-?off|valeur seuil|threshold"),
          ('13', 'Lecture en aveugle de l\'autre test', 'Readers blinded to the other test', r"aveugle|insu|blind"),
          ('14', 'Mesures de performance avec IC', 'Accuracy measures with CI', r"(sensibilite|specificite|valeurs? predictives?|rapport de vraisemblance|auc)[^.]{0,120}(ic|intervalle de confiance|95 ?%)|confidence interval"),
          ('15', 'Résultats indéterminés ou manquants', 'Indeterminate or missing results', r"indetermin|non interpret|ininterpret|donnees manquantes|missing|invalid"),
          ('18', 'Nombre de sujets', 'Sample size', _common['sampleSize']!.$4),
          ('E', 'Avis éthique et consentement', 'Ethics approval and consent', _common['ethics']!.$4),
        ],
      'TRIPOD' => [
          ('1', 'Titre : développement ou validation, population, issue', 'Title: development or validation, population, outcome', r"^.{0,400}(score|modele (pronostique|predictif|de prediction)|prediction|pronosti|prognostic|risk model)"),
          ('3', 'Contexte et justification du modèle', 'Background and rationale for the model', _common['background']!.$4),
          ('4', 'Source des données (cohorte, essai, registre)', 'Source of data (cohort, trial, registry)', r"cohorte|registre|prospecti|retrospecti|cohort|registry"),
          ('5', 'Participants : éligibilité, lieux, dates', 'Participants: eligibility, settings, dates', _common['eligibility']!.$4),
          ('6', 'Issue prédite : définition et horizon', 'Outcome: definition and time horizon', r"(mortalite|deces|evenement|issue|survenue)[^.]{0,60}(a|au|dans les) \d+ ?(jours?|mois|ans?|heures?)|horizon|time horizon|j\d+"),
          ('7', 'Prédicteurs : définition et moment de mesure', 'Predictors: definition and timing of measurement', r"predicteurs?|variables? (candidates?|predictives?|explicatives?)|a l'admission|\bt0\b|predictors?"),
          ('8', 'Nombre de sujets (Riley, événements par paramètre)', 'Sample size (Riley, events per parameter)', r"riley|pmsampsize|evenements? par (parametre|predicteur|variable)|\bepv\b|\bepp\b|shrinkage"),
          ('9', 'Données manquantes', 'Missing data', _common['missing']!.$4),
          ('10a', 'Traitement des prédicteurs (continus, transformations)', 'Handling of predictors (continuous, transformations)', r"forme continue|variables? continues?|splines?|transformations?|non[- ]linea|continuous"),
          ('10b', 'Type de modèle et sélection des prédicteurs', 'Model type and predictor selection', r"regression (logistique|de cox)|lasso|ridge|penalis|selection (des|de) (variables|predicteurs)|logistic regression"),
          ('10d', 'Mesures de performance (discrimination et calibration)', 'Performance measures (discrimination and calibration)', r"(auc|aire sous la courbe|c-?statistique|discrimination)[^.]{0,200}calibration|calibration[^.]{0,200}(auc|aire sous la courbe|c-?statistique|discrimination)"),
          ('10e', 'Validation interne (bootstrap, validation croisée) ou externe', 'Internal (bootstrap, cross-validation) or external validation', r"bootstrap|validation (interne|croisee|externe)|cross-?validation|internal validation|external validation"),
          ('11', 'Groupes de risque ou utilité clinique', 'Risk groups or clinical utility', r"groupes? de risque|niveau de risque|courbe de decision|decision curve|benefice net|net benefit|seuils? de decision"),
          ('E', 'Avis éthique et consentement', 'Ethics approval and consent', _common['ethics']!.$4),
        ],
      _ => [
          ('1', 'Titre identifiant une revue systématique', 'Title identifying a systematic review', r"^.{0,300}(revue systematique|meta-?analyse|systematic review|meta-?analysis)"),
          ('2', 'Enregistrement (PROSPERO)', 'Registration (PROSPERO)', r"prospero|enregistr"),
          ('6', 'Justification', 'Rationale', _common['background']!.$4),
          ('7', 'Objectifs (PICO)', 'Objectives (PICO)', _common['objectives']!.$4),
          ('8', 'Critères d\'éligibilité des études', 'Study eligibility criteria', _common['eligibility']!.$4),
          ('9', 'Sources d\'information (bases, dates)', 'Information sources (databases, dates)', r"pubmed|medline|embase|cochrane|scopus|web of science|lilacs|base(s)? de donnees bibliographiques"),
          ('10', 'Équation de recherche', 'Search strategy', r"equation de recherche|strategie de recherche|mots[- ]cles|mesh|search strategy"),
          ('11', 'Sélection des études et extraction (deux lecteurs)', 'Study selection and data extraction (two reviewers)', r"deux (lecteurs|relecteurs|investigateurs)|independamment|double (lecture|selection)|two reviewers|independently"),
          ('14', 'Risque de biais des études', 'Risk of bias in studies', r"risque de biais|rob ?2|robins|newcastle|quadas|risk of bias"),
          ('15', 'Synthèse (modèle, hétérogénéité)', 'Synthesis (model, heterogeneity)', r"effets? aleatoires?|heterogeneite|\bi2\b|i²|random[- ]effects|heterogeneity"),
          ('16', 'Biais de publication', 'Publication bias', r"biais de publication|funnel|entonnoir|egger|publication bias"),
          ('17', 'Niveau de preuve (GRADE)', 'Certainty of evidence (GRADE)', r"\bgrade\b|niveau de preuve|certainty of evidence"),
        ],
    };

/// Grille adaptée au plan du projet et conformité du protocole (null si le plan n'est pas précisé).
ProtocolChecklist? protocolChecklist(Project p) {
  final q = p.question;
  final grid = switch ((q.design, q.objective)) {
    (StudyDesign.systematicReview, _) => 'PRISMA-P',
    (StudyDesign.rct, _) => 'SPIRIT',
    (_, StudyObjective.predictive) => 'TRIPOD',
    (StudyDesign.diagnosticAccuracy, _) || (_, StudyObjective.diagnostic) => 'STARD',
    (StudyDesign.cohort || StudyDesign.caseControl || StudyDesign.crossSectional, _) => 'STROBE',
    _ => null,
  };
  if (grid == null) return null;
  // Protocole importé : son texte et les corrections appliquées, pas la proposition rédigée par Statoméa à l'import.
  final marker = RegExp(r'(Correction Statoméa|Statoméa correction) — ').firstMatch(p.analysisPlan);
  final plan = p.protocol.isEmpty ? p.analysisPlan : (marker == null ? '' : p.analysisPlan.substring(marker.start));
  final raw = [p.title, p.protocol['_text'] ?? '', if (p.protocol['_text'] == null) ...p.protocol.values, q.text, q.population, q.outcome, plan].join('\n');
  final n = _n(raw);
  // Passage cité : la phrase (ou la ligne) qui contient la correspondance, coupée aux mots si elle est longue.
  String? quote(String re) {
    // Un intitulé de rubrique (« II. Objectifs ») est préféré à une mention en passant.
    final head = re.startsWith('^') ? null : RegExp(r"(?:^|\n)[ \t]*(?:(?:[ivx]+|\d+(?:\.\d+)*|[a-h])[.)][ \t]*)?(?:" + re + r")[^\n]{0,80}(?=\n|$)");
    final hm = head?.firstMatch(n);
    final m = hm ?? RegExp(re).firstMatch(n);
    if (m == null) return null;
    if (n.length != raw.length) return m.group(0)!.trim();
    var s = m.start, e = m.end;
    while (s < e && '\n \t'.contains(raw[s])) {
      s++;
    }
    while (s > 0 && !'.\n'.contains(raw[s - 1])) {
      s--;
    }
    while (e < raw.length && !'.\n'.contains(raw[e])) {
      e++;
    }
    var t = raw.substring(s, e).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 200) {
      final at = raw.substring(s, m.start).replaceAll(RegExp(r'\s+'), ' ').length;
      var a = (at - 60).clamp(0, t.length), b = (at + 140).clamp(0, t.length);
      while (a > 0 && t[a - 1] != ' ') {
        a--;
      }
      while (b < t.length && t[b] != ' ') {
        b++;
      }
      t = '${a > 0 ? '…' : ''}${t.substring(a, b).trim()}${b < t.length ? '…' : ''}';
    }
    return t;
  }

  final items = <ProtocolChecklistItem>[];
  for (final (code, fr, en, re) in _grid(grid)) {
    final ev = quote(re);
    items.add(ProtocolChecklistItem(code, tr(fr, en), ev != null, ev));
  }
  final (name, ref) = switch (grid) {
    'SPIRIT' => ('SPIRIT 2013', tr('Protocoles d\'essais cliniques (Chan et al., BMJ 2013)', 'Clinical trial protocols (Chan et al., BMJ 2013)')),
    'STROBE' => ('STROBE', tr('Études observationnelles (von Elm et al., 2007) — éléments applicables au protocole', 'Observational studies (von Elm et al., 2007) — items applicable to the protocol')),
    'STARD' => ('STARD 2015', tr('Études de performance diagnostique (Bossuyt et al., BMJ 2015)', 'Diagnostic accuracy studies (Bossuyt et al., BMJ 2015)')),
    'TRIPOD' => ('TRIPOD', tr('Modèles de prédiction (Collins et al., BMJ 2015 ; TRIPOD+AI 2024)', 'Prediction models (Collins et al., BMJ 2015; TRIPOD+AI 2024)')),
    _ => ('PRISMA-P 2015', tr('Protocoles de revue systématique (Moher et al., 2015)', 'Systematic review protocols (Moher et al., 2015)')),
  };
  return ProtocolChecklist(name, ref, items);
}
