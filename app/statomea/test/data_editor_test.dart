import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statomea/screens/data_editor_screen.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  testWidgets('éditeur : corriger une cellule, ajouter une ligne, exclure une ligne ; le résultat revient journalisé', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    final ds = Dataset(['id', 'age', 'sexe'], [['1', '54', 'F'], ['2', '610', 'H'], ['3', '47', 'F']]);
    Dataset? result;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () async {
          result = await Navigator.push<Dataset>(c, MaterialPageRoute(builder: (_) => DataEditorScreen(ds)));
        }, child: const Text('ouvrir')))))));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    // Correction de la valeur aberrante 610 → 61.
    await t.tap(find.text('610'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Nouvelle valeur'), '61');
    await t.enterText(find.widgetWithText(TextField, 'Justification (obligatoire, journalisée)'), 'erreur de frappe (dossier)');
    await t.tap(find.text('Appliquer'));
    await t.pumpAndSettle();
    expect(find.text('61'), findsOneWidget);
    // Ajout d'une ligne.
    await t.tap(find.text('Ajouter une ligne'));
    await t.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await t.enterText(fields.at(0), '4');
    await t.enterText(fields.at(1), '70');
    await t.enterText(fields.at(2), 'H');
    await t.enterText(fields.at(3), 'sujet oublié à la saisie');
    await t.tap(find.widgetWithText(FilledButton, 'Ajouter'));
    await t.pumpAndSettle();
    expect(find.text('4 +'), findsOneWidget);
    // Exclusion de la ligne 1.
    await t.tap(find.text('1').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'hors critères d\'inclusion');
    await t.tap(find.text('Appliquer'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Terminer'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.corrections.map((c) => c.action), ['replace', 'add_row', 'exclude_row']);
    expect(result!.numeric('age'), [54, 61, 47, 70]);
    expect(result!.excludedRows, {0});
    expect(result!.original, ds.original);
    expect(t.takeException(), isNull);
  });
}
