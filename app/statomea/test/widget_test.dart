import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/main.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';

void main() {
  testWidgets('l\'accueil affiche les projets et les démonstrations', (tester) async {
    final state = AppState(MemoryStorage());
    await state.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const StatomeaApp()));
    await tester.pumpAndSettle();
    expect(find.text('Projets'), findsWidgets);
    expect(find.text('Démonstrations'), findsOneWidget);
    expect(find.textContaining('Métaanalyse avec forest plot'), findsOneWidget);
    expect(find.text('Polygénie ou confusion ?'), findsOneWidget);
    expect(find.text('Causalité : LDL, HDL et cœur'), findsOneWidget);
    // Avertissement et mention de conception en bas de l'accueil.
    await tester.scrollUntilVisible(find.textContaining('Conçu par le Dr. Modibo Mouctar COULIBALY'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('pas un dispositif médical', findRichText: true), findsOneWidget);
    expect(find.textContaining('Conçu par le Dr. Modibo Mouctar COULIBALY'), findsOneWidget);
  });
}
