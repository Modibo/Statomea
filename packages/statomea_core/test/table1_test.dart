import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

// Jeu de 30 sujets ; références calculées dans R 4.2.3 (t.test, wilcox.test, aov, kruskal.test, chisq.test(correct = FALSE),
// fisher.test, quantile type 7) — voir docs/05-validation.md.
const g = ['A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'A', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'B', 'C', 'C', 'C', 'C', 'C', 'C'];
const age = [34, 41, 29, 38, 45, 50, 36, 33, 40, 47, 39, 42, 52, 48, 55, 44, 58, 61, 49, 53, 47, 56, 50, 59, 40, 43, 38, 46, 41, 44];
const crp = [1.2, 0.8, 3.5, 2.1, 0.5, 15.2, 1.1, 0.9, 2.8, 0.7, 1.5, 30.1, 4.2, 6.8, 2.9, 12.5, 3.3, 45.0, 5.1, 2.2, 8.9, 3.8, 60.2, 4.4, 2.0, 1.1, 9.5, 0.6, 1.4, 3.0];
const sexe = ['F', 'M', 'F', 'F', 'M', 'F', 'M', 'F', 'F', 'M', 'F', 'F', 'M', 'M', 'F', 'M', 'M', 'F', 'M', 'M', 'F', 'M', 'M', 'F', 'F', 'M', 'F', 'F', 'M', 'F'];
const tabac = ['non', 'non', 'non', 'oui', 'non', 'non', 'non', 'non', 'non', 'non', 'non', 'non', 'oui', 'non', 'oui', 'oui', 'non', 'oui', 'non', 'non', 'oui', 'non', 'oui', 'non', 'non', 'non', 'oui', 'non', 'non', 'non'];

Dataset data({bool threeGroups = false}) {
  final rows = [
    for (var i = 0; i < g.length; i++)
      if (threeGroups || g[i] != 'C') [g[i], '${age[i]}', '${crp[i]}', sexe[i], tabac[i]]
  ];
  final ds = Dataset(['groupe', 'age', 'crp', 'sexe', 'tabac'], rows);
  ds.dictionary['age']!
    ..type = VarType.numeric
    ..label = 'Âge'
    ..unit = 'ans';
  ds.dictionary['crp']!
    ..type = VarType.numeric
    ..label = 'CRP'
    ..unit = 'mg/L';
  ds.dictionary['sexe']!.type = VarType.categorical;
  ds.dictionary['tabac']!.type = VarType.binary;
  return ds;
}

void main() {
  test('deux groupes : moyenne ± ET et Welch, médiane [Q1 – Q3] et Mann-Whitney, χ², Fisher (attendus < 5)', () {
    final t = table1(data(), group: 'groupe');
    expect(t.n, 24);
    expect(t.header, ['Caractéristique', 'Ensemble (N = 24)', 'A (n = 12)', 'B (n = 12)', 'p', 'Test']);
    Table1Row row(String v) => t.rows.firstWhere((r) => r.variable == v && !r.isLevel);
    final a = row('age');
    expect(a.label, 'Âge, ans, moyenne ± ET', reason: 'asymétrie 0,05 et 0,02 (R) : symétrique');
    expect(a.overall, '46,1 ± 8,7');
    expect(a.groups, ['39,5 ± 6,1', '52,7 ± 5,3']);
    expect((a.p, a.test), ('< 0,001', 'Welch'), reason: 'R : 1,09e-5');
    final c = row('crp');
    expect(c.label, 'CRP, mg/L, médiane [Q1 – Q3]', reason: 'asymétrie 2,22 (R)');
    expect(c.overall, '3,4 [1,4 – 7,3]');
    expect(c.groups, ['1,4 [0,9 – 3,0]', '4,8 [3,7 – 9,8]']);
    expect(c.test, 'Mann-Whitney');
    expect(c.p, anyOf('0,005', '0,006'), reason: 'R : 0,0045 (exact) ou 0,0061 (approximation normale)');
    final s = row('sexe');
    expect((s.p, s.test), ('0,10', 'χ²'), reason: 'R : chisq.test(correct = FALSE) 0,1025');
    final levels = t.rows.where((r) => r.variable == 'sexe' && r.isLevel).toList();
    expect([for (final l in levels) l.label], ['F', 'M']);
    expect(levels.first.groups, ['8 (66,7)', '4 (33,3)']);
    final tb = row('tabac');
    expect((tb.p, tb.test), ('0,07', 'Fisher'), reason: 'R : fisher.test 0,0686 ; effectif attendu 3,5 < 5');
  });

  test('trois groupes : ANOVA, Kruskal-Wallis, χ² RxC ; sans groupe ; résultat journalisable', () {
    final t = table1(data(threeGroups: true), group: 'groupe');
    Table1Row row(String v) => t.rows.firstWhere((r) => r.variable == v && !r.isLevel);
    expect((row('age').p, row('age').test), ('< 0,001', 'ANOVA'), reason: 'R : 4,38e-6');
    expect((row('crp').p, row('crp').test), ('0,008', 'Kruskal-Wallis'), reason: 'R : 0,00842');
    expect((row('sexe').p, row('sexe').test), ('0,20', 'χ²'), reason: 'R : 0,2005');
    final o = table1(data(threeGroups: true));
    expect(o.header, ['Caractéristique', 'Ensemble (N = 30)']);
    expect(o.rows.first.groups, isEmpty);
    final r = table1Result(data(), group: 'groupe');
    expect(r.tables.single.header.length, 6);
    expect(r.tables.single.rows.length, table1(data(), group: 'groupe').rows.length);
    expect(methodInfo(r.methodId), isNotNull);
    expect(() => table1(data(), group: 'age'), throwsA(isA<StatInputError>()), reason: 'plus de 6 modalités');
  });
}
