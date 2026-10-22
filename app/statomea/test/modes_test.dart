// Modes Guidé et Expert expliqués : bulles d'aide, fenêtre « Que changent les modes ? », ligne « Réglages avancés en
// mode Expert » là où des réglages sont masqués, qui bascule en mode Expert.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/l10n/gen/app_localizations.dart';
import 'package:statomea/screens/home_screen.dart';
import 'package:statomea/services/modes.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/common.dart';

Widget _app(AppState s, Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: home));

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('sélecteur des modes (${width.toInt()} px) : bulles d\'aide et fenêtre d\'explication', (t) async {
      await t.binding.setSurfaceSize(Size(width, 900));
      final state = AppState(MemoryStorage());
      await state.load();
      await t.pumpWidget(_app(state, const HomeScreen()));
      await t.pumpAndSettle();
      expect(find.byTooltip('Résultats essentiels, réglages courants choisis pour vous'), findsOneWidget);
      expect(find.byTooltip('Tous les résultats, formules et réglages avancés'), findsOneWidget);
      await t.tap(find.byTooltip('Que changent les modes ?'));
      await t.pumpAndSettle();
      expect(find.text('Que changent les modes ?'), findsOneWidget);
      expect(find.text('• ${guidedModePoints.first}'), findsOneWidget);
      expect(find.text('• ${expertModePoints.first}'), findsOneWidget);
      expect(find.text(modesSameEngine), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(find.text('Que changent les modes ?'), findsNothing);
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('ligne « Réglages avancés » : visible en Guidé seulement, et bascule en mode Expert', (t) async {
    final state = AppState(MemoryStorage());
    await state.load();
    await t.pumpWidget(_app(state, const Scaffold(body: ExpertHint('seuils'))));
    expect(find.text('Réglages avancés (seuils) en mode Expert.'), findsOneWidget);
    await t.tap(find.text('Passer en mode Expert'));
    await t.pump();
    expect(state.expertMode, isTrue);
    expect(find.textContaining('Réglages avancés'), findsNothing);
  });
}
