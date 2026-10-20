import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

const ris = '''TY  - JOUR
TI  - Hepatitis B virus infection in pregnant women in Mali
AU  - Coulibaly, Modibo Mouctar
AU  - Traoré, Aminata
AU  - van der Berg, Johannes P.
T2  - BMC Infectious Diseases
PY  - 2021///
VL  - 21
IS  - 3
SP  - 101
EP  - 109
DO  - https://doi.org/10.1186/s12879-021-0001
ER  - 

TY  - JOUR
TI  - Global prevalence of diabetes
AU  - Smith, John
PY  - 2019
JO  - Lancet
VL  - 393
SP  - 1234
ER  - 
''';

const bib = r'''
@article{riley2020,
  author = {Riley, Richard D. and Ensor, Joie and Snell, Kym I. E.},
  title = {Calculating the sample size required for developing a clinical prediction model},
  journal = {BMJ},
  year = {2020},
  volume = 368,
  pages = {m441--m441},
  doi = {10.1136/bmj.m441}
}
@comment{ignoré}
@book{altman1991, author = "Douglas G. Altman", title = "Practical Statistics for Medical Research", year = 1991}
''';

const medline = '''PMID- 31234567
TI  - Tranexamic acid in trauma patients: a randomised trial with a very long title that
      continues on the next line.
AU  - Roberts I
AU  - Shakur H
AU  - Coats T
AU  - Hunt B
AU  - Balogun E
AU  - Barnetson L
AU  - Cook L
TA  - Lancet
DP  - 2019 Oct
VI  - 394
IP  - 10210
PG  - 1713-23
LID - 10.1016/S0140-6736(19)32233-0 [doi]
''';

void main() {
  test('import RIS (Zotero), BibTeX, MEDLINE ; noms et clés ; style de Vancouver', () {
    final r = parseReferences(ris);
    expect(r.length, 2);
    expect(r[0].authors, ['Coulibaly MM', 'Traoré A', 'van der Berg JP']);
    expect(r[0].key, 'coulibaly2021');
    expect((r[0].pages, r[0].doi, r[0].journal), ('101-109', '10.1186/s12879-021-0001', 'BMC Infectious Diseases'));
    expect(vancouver(r[0]), 'Coulibaly MM, Traoré A, van der Berg JP. Hepatitis B virus infection in pregnant women in Mali. BMC Infectious Diseases. 2021;21(3):101-109. doi:10.1186/s12879-021-0001.');
    expect(vancouver(r[1]), 'Smith J. Global prevalence of diabetes. Lancet. 2019;393:1234.');
    final b = parseReferences(bib);
    expect(b.map((x) => x.key), ['riley2020', 'altman1991']);
    expect(b[0].authors, ['Riley RD', 'Ensor J', 'Snell KIE']);
    expect(b[0].pages, 'm441-m441');
    expect(b[1].authors, ['Altman DG']);
    expect(vancouver(b[1]), 'Altman DG. Practical Statistics for Medical Research. 1991.');
    final m = parseReferences(medline);
    expect(m.single.title, 'Tranexamic acid in trauma patients: a randomised trial with a very long title that continues on the next line.');
    expect((m.single.pmid, m.single.doi, m.single.year), ('31234567', '10.1016/S0140-6736(19)32233-0', '2019'));
    expect(vancouver(m.single), startsWith('Roberts I, Shakur H, Coats T, Hunt B, Balogun E, Barnetson L, et al. Tranexamic acid'));
    expect(vancouver(m.single), endsWith('Lancet. 2019;394(10210):1713-23. doi:10.1016/S0140-6736(19)32233-0. PMID: 31234567.'));
    expect(parseReferences(ris, existingKeys: ['coulibaly2021']).first.key, 'coulibaly2021a', reason: 'clé déjà prise');
    expect(() => parseReferences('du texte libre'), throwsA(isA<StatInputError>()));
  });

  test('citations numérotées dans l\'ordre, suites « 1–3 », non citées à la fin ; article et protocole ; enregistrement', () {
    final refs = [...parseReferences(ris), ...parseReferences(bib)];
    final n = referenceNumbers(refs, ['Le VHB est fréquent [@coulibaly2021].', 'Effectif selon Riley [@riley2020; @smith2019; @coulibaly2021].', 'Inconnu [@xyz].']);
    expect(n, {'coulibaly2021': 1, 'riley2020': 2, 'smith2019': 3, 'altman1991': 4});
    expect(formatCitations('voir [@riley2020; @smith2019; @coulibaly2021]', n), 'voir [1–3]');
    expect(formatCitations('voir [@altman1991, @coulibaly2021]', n), 'voir [1,4]');
    expect(formatCitations('voir [@xyz]', n), 'voir [@xyz]');
    expect(referenceList(refs, n).first, startsWith('1. Coulibaly MM'));

    final p = Project(id: 'b', title: 'VHB', createdAt: '')
      ..question = const ResearchQuestion(text: 'Quelle est la prévalence de l\'AgHBs ?', design: StudyDesign.crossSectional)
      ..analysisPlan = 'Effectif calculé selon [@riley2020]. Prévalence avec IC de Wilson [@altman1991].';
    p.references.addAll(refs);
    final art = articleOutline(p);
    final plan = art.firstWhere((s) => s.title == 'Analyse statistique').paragraphs.join(' ');
    expect(plan, contains('selon [1]'));
    expect(plan, contains('Wilson [2]'));
    final list = art.firstWhere((s) => s.title == 'Références').paragraphs;
    expect(list.length, 4);
    expect(list.first, startsWith('1. Riley RD, Ensor J, Snell KIE. Calculating the sample size'));
    final prot = protocolOutline(p);
    expect(prot.last.title, 'Références');
    expect(prot.last.paragraphs.length, 4);
    final back = Project.decode(p.encode());
    expect(back.references.map((r) => vancouver(r)), refs.map((r) => vancouver(r)));
  });

  test('méta-analyse depuis la bibliographie : libellés, études à extraire, année, grille réimportable, calcul', () {
    final refs = [
      ...parseReferences(ris),
      ...parseReferences('TY  - JOUR\nTI  - Another HBV study\nAU  - Coulibaly, Fatoumata\nPY  - 2021\nER  - \n', existingKeys: ['coulibaly2021']),
    ];
    expect(studyLabels(refs), ['Coulibaly 2021', 'Smith 2019', 'Coulibaly 2021b']);
    final st = metaStudiesFromReferences(refs);
    expect(st.map((s) => s.label), ['Coulibaly 2021', 'Smith 2019', 'Coulibaly 2021b']);
    expect(st.first.values.keys, containsAll(['e1', 'n1', 'e2', 'n2', 'annee']));
    expect(st.first.v('e1'), isNull);
    expect(st.first.v('annee'), 2021);
    expect(st.first.values['e1']!.source, '[@coulibaly2021]');
    expect(metaStudiesFromReferences(refs, continuous: true).first.values.keys, containsAll(['m1', 'sd1', 'n1', 'm2', 'sd2', 'n2']));
    final csv = extractionGridCsv(refs);
    final grid = parseCsv(csv).dataset;
    expect(grid.names, ['etude', 'e1', 'n1', 'e2', 'n2', 'sous_groupe', 'annee', 'cle', 'doi']);
    expect(grid.rowCount, 3);
    expect(grid.cell(0, 'doi'), '10.1186/s12879-021-0001');
    // Valeurs extraites puis méta-analyse (OR, effets aléatoires).
    final filled = [Study.binary(st[0].label, 12, 100, 20, 100), Study.binary(st[1].label, 8, 80, 15, 82), Study.binary(st[2].label, 30, 250, 41, 248)];
    final r = metaAnalysis(filled, const MetaOptions(measure: EffectMeasure.or));
    expect(r.estimates.first.value, lessThan(1));
  });
}
