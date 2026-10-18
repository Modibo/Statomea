import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Future<Project> panel(WidgetTester t, String method, VariableRoles roles) async {
  await t.binding.setSurfaceSize(const Size(1200, 3600));
  final state = AppState(MemoryStorage());
  await state.load();
  final p = state.createProject('Rôles');
  p.dataset = parseCsv(File('test/regression_data.csv').readAsStringSync()).dataset;
  p.roles = roles;
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: p, initialMethod: method)))),
  ));
  await t.pumpAndSettle();
  return p;
}

void main() {
  testWidgets('rôles déclarés : la comparaison de 2 groupes est préremplie et calculable sans rien choisir', (t) async {
    final p = await panel(t, 't_test_welch', const VariableRoles(outcome: 'pas', exposure: 'sexe'));
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(p.journal, hasLength(1));
    expect(p.journal.first.methodId, 't_test_welch');
    expect(t.takeException(), isNull);
  });

  testWidgets('rôles déclarés : régression logistique préremplie (issue, événement, exposition et ajustement)', (t) async {
    final p = await panel(t, 'logistic_regression', const VariableRoles(outcome: 'hta', eventLevel: '1', exposure: 'tabac', covariates: ['age', 'sexe']));
    expect(find.text('tabac'), findsWidgets);
    expect(find.text('age'), findsWidgets);
    await t.tap(find.text('Ajuster le modèle'));
    await t.pumpAndSettle();
    expect(p.journal, hasLength(1));
    final cols = ((p.journal.first.result['inputs'] as Map)['model'] as Map)['columns'] as List;
    expect(cols, containsAll(['age', 'sexe = H (vs F)']));
    expect(cols.any((c) => (c as String).startsWith('tabac')), isTrue);
    expect(t.takeException(), isNull);
  });
}
