import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Project _imported(String text) {
  final d = protocolFromText(text);
  return Project(id: 'c', title: d.title, createdAt: '')
    ..question = d.toQuestion()
    ..protocol = Map.of(d.fullSections);
}

const _protocol = """
Titre du projet
Facteurs associés à l'anémie chez les femmes enceintes
Objectif principal
Rechercher les facteurs associés à l'anémie chez les femmes enceintes.
Critère de jugement principal
Anémie (hémoglobine < 11 g/dL), oui ou non.
Type d'étude
Étude transversale.
Variables étudiées
Les informations suivantes seront recueillies : le sexe du nouveau-né, l'âge, le poids, la taille, la pression artérielle, le niveau d'instruction et le tabagisme.
Les examens comprendront la glycémie, l'INR (temps de prothrombine) et la créatinine.
""";

void main() {
  test('champs de la fiche : identifiant, date, variables du protocole avec unités, bornes et modalités ; critère principal', () {
    final f = crfFields(_imported(_protocol));
    expect(f.take(2).map((x) => x.type), [CrfType.identifier, CrfType.date]);
    CrfField by(String c) => f.firstWhere((x) => x.code == c);
    expect(f.map((x) => x.code), containsAllInOrder(['id', 'date_inclusion', 'sexe_nouveau', 'age', 'poids', 'taille', 'pas', 'pad', 'niveau_instruction', 'tabagisme', 'glycemie', 'inr', 'creatinine']));
    expect(by('sexe_nouveau').levels, ['F', 'M']);
    expect((by('age').unit, by('age').min, by('age').max), ('ans', 0.0, 120.0));
    expect((by('poids').unit, by('taille').unit), ('kg', 'cm'));
    expect((by('pas').label, by('pas').unit, by('pad').max), ('Pression artérielle systolique', 'mmHg', 200.0));
    expect(by('tabagisme').type, CrfType.binary);
    expect(by('tabagisme').levels, ['oui', 'non']);
    expect(by('niveau_instruction').levels, hasLength(4));
    expect((by('glycemie').unit, by('creatinine').unit, by('inr').max), ('mmol/L', 'µmol/L', 15.0));
    final outcome = by('critere_principal');
    expect(outcome.type, CrfType.binary, reason: 'issue binaire : oui / non');
    expect(outcome.label, startsWith('Critère principal : Anémie'));
    expect(crfFields(Project(id: 'v', title: 'V', createdAt: '')), isEmpty, reason: 'aucune variable décrite : pas de fiche');
  });

  test('dictionnaire et masque Excel : relus par le lecteur Excel et l\'import de l\'étape 4', () {
    final fields = crfFields(_imported(_protocol));
    final csv = crfDictionaryCsv(fields).split('\r\n');
    expect(csv.first, 'variable;type;libelle;unite;min;max;modalites');
    expect(csv, contains('sexe_nouveau;catégorielle;Sexe du nouveau-né;;;;"F;M"'));
    expect(csv, contains('age;numérique;Âge;ans;0;120;'));
    final parts = crfWorkbookParts(fields);
    final sheet1 = parts['xl/worksheets/sheet1.xml']!;
    expect(RegExp(r'<dataValidation ').allMatches(sheet1).length, fields.where((f) => f.levels.isNotEmpty || f.type == CrfType.date || (f.min != null && f.max != null)).length);
    expect(sheet1, contains('<formula1>"F,M"</formula1>'));
    expect(sheet1, contains('<formula1>40</formula1><formula2>300</formula2>'), reason: 'pression systolique 40–300 mmHg');
    expect(sheet1, contains('state="frozen"'));
    final wb = readXlsxParts(parts);
    expect(wb.sheetNames, ['Données', 'Dictionnaire']);
    final header = wb.sheet(name: 'Données');
    expect(header.names, [for (final f in fields) f.code]);
    final dict = wb.sheet(name: 'Dictionnaire');
    expect(dict.rowCount, fields.length);
    // Données saisies dans le masque puis dictionnaire appliqué (étape 4).
    final data = Dataset(header.names, [
      [for (final f in fields) switch (f.code) { 'id' => 'P001', 'sexe_nouveau' => 'F', 'age' => '27', 'tabagisme' => 'non', _ => null }],
      [for (final f in fields) switch (f.code) { 'id' => 'P002', 'sexe_nouveau' => 'M', 'age' => '31', 'tabagisme' => 'oui', _ => null }],
    ]);
    final rep = applyDataDictionary(data, dict);
    expect(rep.notInData, isEmpty);
    expect(rep.dataset.dictionary['age']!.unit, 'ans');
    expect(rep.dataset.dictionary['age']!.max, 120);
    expect(rep.dataset.dictionary['sexe_nouveau']!.order, ['F', 'M']);
    expect(rep.dataset.dictionary['tabagisme']!.type, VarType.binary);
  });

  test('examens des rubriques de dosage : analytes, méthodes, ajoutés à la fiche et au budget', () {
    final p = _imported("""
Titre du projet
Suivi du diabète de type 2 : étude transversale
Variables étudiées
Les informations suivantes seront recueillies : le sexe, l'âge et le poids.
Examens de laboratoire
Prélèvement sur tube fluoré et tube sec. Les dosages porteront sur la glycémie, l'HbA1c, le cholestérol total, les triglycérides et la créatinine.
C.1. Principe du dosage du glucose
Méthode enzymatique de référence avec hexokinase.
C.2. Principe du dosage du cholestérol total
Méthode colorimétrique enzymatique.
C.3. Principe du dosage de la créatinine
La méthode a été normalisée par rapport à la méthode de référence. Test cinétique colorimétrique (Jaffé).
Gestion et analyse des données
Les données seront analysées avec R.
""");
    final labs = protocolLabTests(p);
    expect(labs.map((l) => l.code), ['glycemie', 'hba1c', 'cholesterol_total', 'triglycerides', 'creatinine']);
    String? method(String c) => labs.firstWhere((l) => l.code == c).method;
    expect(method('glycemie'), 'methode enzymatique de reference avec hexokinase');
    expect(method('cholesterol_total'), 'methode colorimetrique enzymatique');
    expect(method('creatinine'), contains('colorimetrique'), reason: '« la méthode a été normalisée » n\'est pas une technique');
    expect(method('triglycerides'), isNull);
    final f = crfFields(p);
    expect(f.map((x) => x.code), containsAllInOrder(['sexe', 'age', 'poids', 'glycemie', 'hba1c', 'cholesterol_total', 'triglycerides', 'creatinine']));
    expect(f.firstWhere((x) => x.code == 'hba1c').unit, '%');
    p.inferred['plannedSampleSize'] = '100';
    final lab = studyPlanning(p).lines.firstWhere((l) => l.key == 'lab');
    expect(lab.label, 'Examens biologiques (5 par participant)');
    expect(lab.quantity, 500);
    expect(p.protocol['analysis'], contains('analysées avec R'), reason: 'la rubrique d\'examens se ferme à la rubrique suivante');
  });
}
