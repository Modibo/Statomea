import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/screens/steps/data_step.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/services/xlsx_import.dart';
import 'package:statomea/state/app_state.dart';

void main() {
  test('classeur Excel : feuille de données choisie par défaut (pas le dictionnaire), dates et valeurs lues', () {
    final r = datasetFromFile('exemple_excel.xlsx', File('test/exemple_excel.xlsx').readAsBytesSync());
    expect(r.workbook!.sheetNames, ['patients', 'dictionnaire']);
    expect(dictionarySheet(r.workbook!), 'dictionnaire');
    expect(r.dataset.rowCount, 40);
    expect(r.dataset.cell(0, 'date_inclusion'), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(() => openXlsx([1, 2, 3]), throwsFormatException);
  });

  testWidgets('étape « données » : import Excel avec application automatique de la feuille dictionnaire', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Excel');
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: DataStep(p)))));
    await t.pumpAndSettle();
    final st = t.state<DataStepState>(find.byType(DataStep));
    await st.importFileBytes('exemple_excel.xlsx', File('test/exemple_excel.xlsx').readAsBytesSync());
    await t.pumpAndSettle();
    final d = p.dataset!;
    expect(d.dictionary['poids']!.unit, 'kg');
    expect(d.dictionary['score']!.order, ['faible', 'moyen', 'fort']);
    expect(d.corrections.where((c) => c.action == 'set_missing'), isNotEmpty);
    expect(find.textContaining('Dictionnaire « dictionnaire » appliqué'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
