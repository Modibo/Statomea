import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:statomea_core/statomea_core.dart' hide Step;
import 'package:statomea_core/statomea_core.dart' as core show Step;

/// Guide d'utilisation (PDF A4) : présentation, installation, démarrage, parcours en 10 étapes, feuille de route et
/// outils, relecture, analyses, publication, formation, encadrants, sauvegarde, limites. [images] : captures d'écran
/// (nom de fichier des maquettes → PNG), insérées à côté du texte quand elles sont fournies.
Future<Uint8List> buildUserGuidePdf({Map<String, Uint8List> images = const {}}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final math = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansMath-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [math]);
  final blue = PdfColor.fromHex('#1F4E79');
  final doc = pw.Document(title: tr('Statoméa — guide d\'utilisation', 'Statoméa — user guide'), author: 'Statoméa', creator: '$engineName $engineVersion');

  pw.Widget h1(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: blue)));
  pw.Widget h2(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 8, bottom: 3), child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)));
  pw.Widget p(String t) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 5), child: pw.Text(t, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.5)));
  pw.Widget bullet(String t) => pw.Bullet(text: t, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4), bulletSize: 3);
  pw.Widget shot(String name, String caption) {
    final b = images[name];
    if (b == null) return pw.SizedBox();
    return pw.Container(
      width: 165,
      margin: const pw.EdgeInsets.only(left: 14),
      child: pw.Column(children: [
        pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.6)), child: pw.Image(pw.MemoryImage(b), width: 165)),
        pw.SizedBox(height: 3),
        pw.Text(caption, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ]),
    );
  }

  pw.Widget withShot(List<pw.Widget> text, String name, String caption) =>
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: text)), shot(name, caption)]);

  final steps = [for (final s in core.Step.values) (stepLabel(s), stepHint(s))];

  doc.addPage(pw.Page(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(48),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(height: 120),
      pw.Text('Statoméa', style: pw.TextStyle(fontSize: 44, fontWeight: pw.FontWeight.bold, color: blue)),
      pw.SizedBox(height: 8),
      pw.Text(tr('Guide d\'utilisation', 'User guide'), style: const pw.TextStyle(fontSize: 24)),
      pw.SizedBox(height: 16),
      pw.Text(tr('Statistique biomédicale et formation à la recherche : du protocole à la publication.', 'Biomedical statistics and research training: from protocol to publication.'), style: const pw.TextStyle(fontSize: 13)),
      pw.SizedBox(height: 40),
      pw.Text(tr('Version $engineVersion', 'Version $engineVersion'), style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.Text('https://statomea.komodi-labo.org', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.Spacer(),
      pw.Text(tr('Outil d\'aide et de formation — pas un dispositif médical. Il ne remplace ni le jugement du chercheur ni la relecture par un méthodologiste.', 'Support and training tool — not a medical device. It replaces neither the researcher\'s judgement nor review by a methodologist.'),
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ]),
  ));

  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 40),
    footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Statoméa — ${tr('guide d\'utilisation', 'user guide')} — ${c.pageNumber}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      h1(tr('1. Ce que fait Statoméa', '1. What Statoméa does')),
      withShot([
        p(tr('Statoméa accompagne chercheurs, biologistes et étudiants de la question de recherche à la publication : formuler la question, rédiger et faire relire le protocole, recueillir et contrôler les données, choisir la bonne méthode, calculer, interpréter, faire auditer le texte, puis préparer l\'article, la soutenance et la réponse aux relecteurs.',
            'Statoméa supports researchers, laboratory scientists and students from the research question to publication: framing the question, writing and reviewing the protocol, collecting and checking data, choosing the right method, computing, interpreting, auditing the text, then preparing the article, the defence and the response to reviewers.')),
        bullet(tr('Gratuit, en français et en anglais, utilisable hors connexion.', 'Free, in French and English, usable offline.')),
        bullet(tr('Aucune donnée ne quitte l\'appareil : tout est calculé et enregistré localement.', 'No data leaves the device: everything is computed and stored locally.')),
        bullet(tr('Chaque méthode statistique est validée contre R ; les tolérances sont écrites dans le rapport de validation.', 'Every statistical method is validated against R; tolerances are written in the validation report.')),
        bullet(tr('Les règles de relecture et de déduction sont explicites (aucun modèle de langage) : chaque proposition cite le passage qui la justifie.', 'Review and inference rules are explicit (no language model): every proposal quotes the passage that justifies it.')),
      ], 'mobile-01-accueil.png', tr('Écran Projets', 'Projects screen')),
      h1(tr('2. Installer et ouvrir', '2. Install and open')),
      bullet(tr('Navigateur (ordinateur, tablette, téléphone) : https://statomea.komodi-labo.org/app/ — sur iPhone, « Partager → Sur l\'écran d\'accueil ».', 'Browser (computer, tablet, phone): https://statomea.komodi-labo.org/app/ — on iPhone, "Share → Add to Home Screen".')),
      bullet(tr('Android : télécharger l\'APK depuis la page d\'accueil et autoriser l\'installation depuis cette source.', 'Android: download the APK from the home page and allow installation from this source.')),
      bullet(tr('L\'application signale les nouvelles versions ; « Recharger » installe la mise à jour.', 'The app reports new versions; "Reload" installs the update.')),
      h1(tr('3. Démarrer un projet', '3. Start a project')),
      h2(tr('Nouveau projet', 'New project')),
      p(guideNewProject),
      h2(tr('Projet importé', 'Imported project')),
      p(guideImportedProject),
      h1(tr('4. Le parcours en 10 étapes', '4. The 10-step pathway')),
      withShot([
        p(tr('Chaque étape conditionne la suivante : la méthode découle de la question et du plan, jamais du nom des variables. Marquez chaque étape « Terminée » ; on peut revenir à une étape à tout moment.',
            'Each step conditions the next: the method follows from the question and design, never from variable names. Mark each step "Done"; you can return to any step at any time.')),
        for (var k = 0; k < steps.length; k++) bullet('${k + 1}. ${steps[k].$1} — ${steps[k].$2}'),
      ], 'mobile-02-question.png', tr('Étape 1 : la question', 'Step 1: the question')),
      h1(tr('5. La feuille de route et ses outils', '5. The roadmap and its tools')),
      withShot([
        p(guideRoadmap),
        bullet(tr('Protocole : protocole prérédigé (Word, PDF), budget et chronogramme, bibliographie.', 'Protocol: pre-drafted protocol (Word, PDF), budget and timeline, bibliography.')),
        bullet(tr('Recueil des données : fiche de recueil (PDF), masque de saisie Excel avec listes et bornes, dictionnaire.', 'Data collection: case report form (PDF), Excel data-entry template with lists and bounds, dictionary.')),
        bullet(tr('Résultats et publication : diagramme de flux CONSORT/STROBE, article prérédigé avec Tableaux 1 et 2.', 'Results and publication: CONSORT/STROBE flow diagram, pre-drafted article with Tables 1 and 2.')),
        bullet(tr('Communication : présentation PowerPoint, poster A0, réponse aux relecteurs.', 'Communication: PowerPoint presentation, A0 poster, response to reviewers.')),
        bullet(tr('Formation : mode tuteur.', 'Training: tutor mode.')),
      ], 'mobile-14-feuille-de-route.png', tr('Feuille de route', 'Roadmap')),
      h1(tr('6. Relecture et corrections', '6. Review and corrections')),
      withShot([
        p(guideReview),
        p(tr('Les points sont classés en erreurs, à revoir et manquants ; chaque correction appliquée est datée et tracée. Le protocole Word d\'origine peut être renvoyé annoté de commentaires.', 'Points are classified as errors, to review and missing; each applied correction is dated and logged. The original Word protocol can be returned annotated with comments.')),
      ], 'mobile-15-relecture.png', tr('Relecture et corrections', 'Review and corrections')),
      h1(tr('7. Analyses', '7. Analyses')),
      withShot([
        p(tr('Les calculateurs couvrent proportions, comparaisons, corrélation, régressions (logistique, Poisson robuste, Cox…), survie et risques concurrents, méta-analyse, modèles de prédiction, laboratoire (Bland-Altman, Passing-Bablok), génomique, calculs d\'effectif et de puissance. Chaque résultat est ajouté au journal du projet avec ses options et l\'empreinte des données.',
            'Calculators cover proportions, comparisons, correlation, regressions (logistic, robust Poisson, Cox…), survival and competing risks, meta-analysis, prediction models, laboratory (Bland-Altman, Passing-Bablok), genomics, sample size and power. Each result is added to the project log with its options and the data fingerprint.')),
        bullet(tr('Tableau 1 : caractéristiques des participants, test adapté à chaque variable, export Word et Excel.', 'Table 1: participant characteristics, test suited to each variable, Word and Excel export.')),
        bullet(tr('Tableau 2 : associations brutes et ajustées, prérempli avec les rôles des variables.', 'Table 2: crude and adjusted associations, prefilled with the variable roles.')),
        bullet(tr('Audit contradictoire (étape 9) : OR lu comme un RR, langage causal, valeur de p mal interprétée, analyse annoncée mais non faite.', 'Adversarial audit (step 9): OR read as an RR, causal language, misread p-value, analysis announced but not performed.')),
      ], 'mobile-05-forest.png', tr('Méta-analyse : forest plot', 'Meta-analysis: forest plot')),
      h1(tr('8. Publication', '8. Publication')),
      bullet(tr('Article prérédigé (Word) : méthodes reprises du protocole corrigé, Tableaux 1 et 2, résultats du journal, limites selon le plan, grille de publication (CONSORT, STROBE, STARD, TRIPOD+AI, PRISMA).', 'Pre-drafted article (Word): methods taken from the corrected protocol, Tables 1 and 2, results from the log, limitations by design, reporting guideline (CONSORT, STROBE, STARD, TRIPOD+AI, PRISMA).')),
      bullet(tr('Bibliographie : import RIS (Zotero), BibTeX, MEDLINE (PubMed) ; citer avec [@clé] ; liste de Vancouver ; méta-analyse préparée depuis les références.', 'Bibliography: RIS (Zotero), BibTeX, MEDLINE (PubMed) import; cite with [@key]; Vancouver list; meta-analysis prepared from the references.')),
      bullet(tr('Présentation PowerPoint et poster A0 tirés du projet ; réponse aux relecteurs avec propositions et lettre Word.', 'PowerPoint presentation and A0 poster drawn from the project; response to reviewers with proposals and a Word letter.')),
      h1(tr('9. Formation', '9. Training')),
      withShot([
        bullet(tr('24 leçons avec exercices corrigés, ouvertes depuis chaque résultat.', '24 lessons with corrected exercises, opened from each result.')),
        bullet(tr('10 démonstrations complètes, avec un brouillon volontairement erroné que l\'audit doit corriger.', '10 complete demonstrations, with a deliberately flawed draft the audit must correct.')),
        bullet(tr('Mode tuteur : une question par étape, tirée du projet de l\'étudiant ; indice, explication, fiche de progression pour l\'encadrant.', 'Tutor mode: one question per step, drawn from the student\'s project; hint, explanation, progress sheet for the supervisor.')),
      ], 'mobile-08-lecon.png', tr('Une leçon', 'A lesson')),
      h1(tr('10. Pour les encadrants', '10. For supervisors')),
      bullet(tr('Tableau de bord encadrant (écran Projets) : importer les projets des étudiants (.json), voir étapes, relecture, mode tuteur, analyses, effectif et points d\'attention ; fiche PDF de la promotion.', 'Supervisor dashboard (Projects screen): import students\' projects (.json), see steps, review, tutor mode, analyses, sample size and attention points; cohort PDF sheet.')),
      bullet(tr('Les étudiants partagent leur projet à l\'étape 10, avec ou sans les données individuelles.', 'Students share their project at step 10, with or without individual data.')),
      h1(tr('11. Sauvegarder', '11. Back up')),
      p(tr('Les projets sont enregistrés dans l\'appareil (ou le navigateur). « Sauvegarder tous les projets » (écran Projets) produit un fichier à garder ailleurs (clé, nuage, courriel) ; « Restaurer une sauvegarde » le relit en vérifiant l\'intégrité de chaque projet. Un rappel s\'affiche si aucune sauvegarde n\'a été faite depuis 7 jours.',
          'Projects are stored on the device (or browser). "Back up all projects" (Projects screen) produces a file to keep elsewhere (USB key, cloud, email); "Restore a backup" reads it back, checking each project\'s integrity. A reminder appears if no backup has been made for 7 days.')),
      h1(tr('12. Limites', '12. Limitations')),
      bullet(tr('Statoméa est un outil d\'aide et de formation, pas un dispositif médical.', 'Statoméa is a support and training tool, not a medical device.')),
      bullet(tr('La relecture et les déductions reposent sur des règles : elles signalent ce qu\'elles savent reconnaître et ne remplacent pas un méthodologiste.', 'Review and inference rely on rules: they flag what they can recognise and do not replace a methodologist.')),
      bullet(tr('Les documents prérédigés (protocole, article, poster) sont des points de départ : les passages surlignés sont à rédiger par les auteurs.', 'Pre-drafted documents (protocol, article, poster) are starting points: highlighted passages are for the authors to write.')),
      bullet(tr('Code source et rapport de validation : https://github.com/Modibo/Statomea', 'Source code and validation report: https://github.com/Modibo/Statomea')),
    ],
  ));
  return doc.save();
}
