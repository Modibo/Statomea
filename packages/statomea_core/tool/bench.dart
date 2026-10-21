// Banc de performance : temps des opérations lourdes sur 5 000 lignes (dart run tool/bench.dart).
import 'dart:io';
import 'dart:math';

import 'package:statomea_core/statomea_core.dart';

T time<T>(String label, T Function() f) {
  final sw = Stopwatch()..start();
  final r = f();
  stdout.writeln('${label.padRight(40)} ${sw.elapsedMilliseconds} ms');
  return r;
}

void main() {
  final rnd = Random(1);
  final b = StringBuffer('"id","age","residence","parite","aghbs","hb","poids","groupe"\n');
  for (var i = 0; i < 5000; i++) {
    b.writeln('"F$i",${18 + rnd.nextInt(28)},"${rnd.nextBool() ? 'rural' : 'urbain'}",${rnd.nextInt(7)},'
        '"${rnd.nextDouble() < .1 ? 'positif' : 'negatif'}",${(9 + rnd.nextDouble() * 5).toStringAsFixed(1)},'
        '${(45 + rnd.nextDouble() * 40).toStringAsFixed(1)},"${['A', 'B', 'C'][rnd.nextInt(3)]}"');
  }
  final csv = b.toString();
  final ds = time('import CSV (5 000 × 8)', () => parseCsv(csv).dataset);
  time('Tableau 1 (groupe)', () => table1Result(ds, group: 'groupe'));
  time('Tableau 2 logistique', () => associationTable(ds,
      const ModelFormula('aghbs', [TermSpec('age'), TermSpec('residence', categorical: true, reference: 'urbain'), TermSpec('parite'), TermSpec('hb')], eventLevel: 'positif'),
      model: 'logistic', design: StudyDesign.crossSectional));
  final p = time('projet démo AgHBs', () => buildDemoAghbs(File('../../app/statomea/assets/demos/aghbs_simule.csv').readAsStringSync()));
  time('relecture du projet', () => reviewProject(p));
  time('suivi du projet (JSON aller-retour)', () => Project.fromJson(p.toJson()));
  final big = StringBuffer(csv);
  for (var k = 0; k < 9; k++) {
    big.write(csv.substring(csv.indexOf('\n') + 1));
  }
  final ds50 = time('import CSV (50 000 × 8)', () => parseCsv(big.toString()).dataset);
  time('Tableau 1 (50 000 lignes)', () => table1Result(ds50, group: 'groupe'));
  time('contrôle de qualité (50 000 lignes)', () => checkQuality(ds50, outcome: 'aghbs', predictors: ['age', 'residence', 'parite', 'hb', 'poids', 'groupe']));
  time('contrôle de qualité (2e passage)', () => checkQuality(ds50, outcome: 'aghbs', predictors: ['age', 'residence', 'parite', 'hb', 'poids', 'groupe']));
  time('niveaux × 8 variables', () => [for (final n in ds50.names) ds50.levels(n)]);
  final proto = StringBuffer('Titre du projet\nÉtude transversale de l\'anémie\nObjectif principal\nRechercher les facteurs associés à l\'anémie.\n');
  for (var i = 0; i < 300; i++) {
    proto.writeln('Contexte $i. Les femmes enceintes de 18 ans ou plus seront incluses après consentement ; la prévalence attendue est de 40 % et le test du khi-deux sera utilisé au seuil de 5 %.');
  }
  final d = time('analyse d\'un protocole (~40 pages)', () => protocolFromText(proto.toString()));
  final q = Project(id: 'q', title: d.title, createdAt: '')
    ..question = d.toQuestion()
    ..protocol = Map.of(d.fullSections)
    ..analysisPlan = d.sections['analysis'] ?? '';
  time('relecture du protocole importé', () => reviewProject(q));
  time('fiche de recueil', () => crfWorkbookParts(crfFields(q)));
  time('article prérédigé', () => articleOutline(q));
}
