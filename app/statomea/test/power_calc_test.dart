import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  testWidgets('atelier de puissance : moyennes, puis survie (Freedman) et GWAS en mode « puissance pour un effectif »', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final got = <AnalysisResult>[];
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PowerCalc((r, {options = const {}}) => got.add(r))))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'power_means');
    expect(got.last.statistics['n_0'], 64); // d = 0,5, puissance 80 % : 64 par groupe
    expect(got.last.figures['powerCurve'], isNotNull);

    Future<void> pickItem(String label, String item) async {
      await t.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField && (w.decoration.labelText == label)));
      await t.pumpAndSettle();
      await t.tap(find.text(item).last);
      await t.pumpAndSettle();
    }

    await pickItem('Plan d\'étude', 'Survie : essai à deux bras (HR)');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'power_survival');
    expect(got.last.statistics['n_1'], 319); // powerSurvEpi::ssizeCT : 319 par bras

    await pickItem('Plan d\'étude', 'Étude pangénomique (GWAS)');
    await pickItem('Objectif', 'la puissance pour un effectif');
    await t.enterText(find.widgetWithText(TextField, 'Nombre de cas'), '5000');
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(got.last.methodId, 'power_gwas');
    expect(got.last.statistics['power'], closeTo(0.5992, 1e-3)); // MAF 0,25, OR 1,2, 5000 cas / 5000 témoins
    expect(t.takeException(), isNull);
  });
}
