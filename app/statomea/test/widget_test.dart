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
  });
}
