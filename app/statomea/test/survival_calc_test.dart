import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';

void main() {
  testWidgets('calculateur de survie (saisie directe) : Kaplan-Meier, log-rank et figure', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(initialMethod: 'kaplan_meier')))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.text('Survie : Kaplan-Meier et log-rank'), findsWidgets);
    expect(find.text('Kaplan-Meier'), findsOneWidget); // titre de la figure
    // Mode guidé : le log-rank est donné dans l'interprétation (le tableau détaillé est en mode expert).
    expect(find.byWidgetPredicate((w) => w is SelectableText && (w.data ?? '').contains('Log-rank : χ²')), findsOneWidget);
  });
}
