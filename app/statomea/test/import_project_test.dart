import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/l10n/gen/app_localizations.dart';
import 'package:statomea/screens/projects_screen.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea_core/statomea_core.dart';

void main() {
  final bcg = File('../../packages/statomea_core/test/reference/bcg_colditz1994.csv').readAsStringSync();

  Future<(AppState, BuildContext)> pumpApp(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1000, 2400));
    final state = AppState(MemoryStorage());
    await state.load();
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const ProjectsScreen();
        })),
      ),
    ));
    await t.pumpAndSettle();
    return (state, ctx);
  }

  testWidgets('import d\'un projet exporté : aperçu, confirmation, copie à part si l\'identifiant existe', (t) async {
    final (state, ctx) = await pumpApp(t);
    expect(find.text('Importer un projet'), findsOneWidget);
    final p = buildDemoMeta(bcg);
    await state.addImported(p);
    final text = p.encode();

    // Premier essai : annulé, rien n'est enregistré.
    var fut = importProjectText(ctx, text);
    await t.pumpAndSettle();
    expect(find.textContaining('Importer « Démo 2'), findsOneWidget);
    expect(find.textContaining('même identifiant existe déjà'), findsOneWidget);
    expect(find.textContaining('13 étude(s) extraite(s)'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(await fut, isNull);
    expect(state.projects, hasLength(1));

    // Second essai : confirmé, la copie est enregistrée à part et l'original est intact.
    fut = importProjectText(ctx, text);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Importer'));
    await t.pumpAndSettle();
    expect(state.projects, hasLength(2));
    final copy = state.projects.first;
    expect(copy.id, isNot(p.id));
    expect(copy.title, endsWith('(import)'));
    expect(copy.journal.length, p.journal.length);
    expect(state.projects.last.title, p.title);
    expect(await state.storage.loadAll(), hasLength(2));
  });

  testWidgets('fichier modifié après l\'export : constat grave dans l\'aperçu', (t) async {
    final (state, ctx) = await pumpApp(t);
    final j = jsonDecode(buildDemoMeta(bcg).encode()) as Map<String, Object?>..['resultsText'] = 'réécrit';
    importProjectText(ctx, jsonEncode(j));
    await t.pumpAndSettle();
    expect(find.textContaining('modifié après l\'export'), findsOneWidget);
    expect(find.textContaining('Fichier intact'), findsNothing);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(state.projects, isEmpty);
  });

  testWidgets('journal de calcul refusé avec un message, sans aperçu', (t) async {
    final (state, ctx) = await pumpApp(t);
    final r = await importProjectText(ctx, journalJson(buildDemoMeta(bcg)));
    await t.pump();
    expect(r, isNull);
    expect(find.textContaining('journal de calcul'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.projects, isEmpty);
  });
}
