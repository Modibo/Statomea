import 'dart:convert';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  final ds = Dataset(['id', 'age', 'sexe'], [['1', '54', 'F'], ['2', '61', 'H'], ['3', '47', 'F']]);

  test('cellule corrigée, ligne ajoutée puis corrigée, exclusion : valeurs courantes, import intact', () {
    var d = ds.applyCorrection(const Correction(id: 'c1', variable: 'age', action: 'replace', rows: [1], from: '61', to: '16', reason: 'erreur de saisie'));
    d = d.addRow(['4', '70', 'H'], id: 'c2', reason: 'sujet oublié');
    expect(d.rowCount, 4);
    expect(d.numeric('age'), [54, 16, 47, 70]);
    expect(d.originalCell(3, 'age'), isNull);
    d = d.applyCorrection(const Correction(id: 'c3', variable: 'age', action: 'set_missing', rows: [3], from: '70', reason: 'valeur douteuse'));
    d = d.applyCorrection(const Correction(id: 'c4', variable: '*', action: 'exclude_row', rows: [0], reason: 'hors critères'));
    expect(d.numeric('age'), [54, 16, 47, null]);
    expect(d.excludedRows, {0});
    expect(d.original, ds.original); // l'import n'est jamais modifié
    expect(d.corrections.map((c) => c.describe()).last, contains('exclue'));
    final back = Dataset.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>);
    expect(back.rowCount, 4);
    expect(back.text('sexe'), ['F', 'H', 'F', 'H']);
  });

  test('retirer une ligne ajoutée retire ses corrections et renumérote les suivantes', () {
    var d = ds.addRow(['4', '70', 'H'], id: 'a1', reason: 'ajout');
    d = d.addRow(['5', '33', 'F'], id: 'a2', reason: 'ajout');
    d = d.applyCorrection(const Correction(id: 'r1', variable: 'age', action: 'replace', rows: [3], from: '70', to: '71', reason: 'r'));
    d = d.applyCorrection(const Correction(id: 'r2', variable: 'age', action: 'replace', rows: [4], from: '33', to: '34', reason: 'r'));
    final e = d.withoutCorrection('a1');
    expect(e.rowCount, 4);
    expect(e.numeric('age'), [54, 61, 47, 34]);
    expect(e.corrections.map((c) => c.id), ['a2', 'r2']);
    expect(e.corrections.firstWhere((c) => c.id == 'a2').rows, [3]);
  });

  test('rôles des variables : limités aux variables présentes, sauvegardés avec le projet', () {
    const r = VariableRoles(outcome: 'age', exposure: 'sexe', covariates: ['id', 'disparue', 'sexe']);
    final v = r.validFor(ds);
    expect(v.covariates, ['id']);
    final p = Project(id: 'p1', title: 't', createdAt: '', dataset: ds, roles: r);
    final back = Project.decode(p.encode());
    expect(back.roles.outcome, 'age');
    expect(back.roles.covariates, ['id', 'disparue', 'sexe']);
    expect(Project(id: 'p2', title: 't', createdAt: '').toJson().containsKey('roles'), isFalse);
  });
}
