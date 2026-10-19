import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/services/table_export.dart';
import 'package:statomea/services/xlsx_import.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

Dataset _data() {
  final ds = Dataset(['groupe', 'age', 'sexe'], [
    for (var i = 0; i < 20; i++) [i < 10 ? 'Témoin' : 'Traité', '${30 + i * 2 + (i % 3)}', i % 3 == 0 ? 'M' : 'F'],
  ]);
  ds.dictionary['age']!
    ..type = VarType.numeric
    ..label = 'Âge'
    ..unit = 'ans';
  ds.dictionary['sexe']!.type = VarType.categorical;
  ds.dictionary['groupe']!.type = VarType.categorical;
  return ds;
}

void main() {
  testWidgets('calculateur Tableau 1 : groupe choisi, tableau affiché, journal, exports Word et Excel', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 2600));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('T1')..dataset = _data();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(project: p, initialMethod: 'table1'))))));
    await t.pumpAndSettle();
    await t.tap(find.text('— aucun groupe —'));
    await t.pumpAndSettle();
    await t.tap(find.text('groupe').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Calculer'));
    await t.pumpAndSettle();
    expect(find.textContaining('Témoin (n = 10)', skipOffstage: false), findsWidgets);
    expect(find.text('Tableau 1 (Word)'), findsOneWidget);
    expect(p.journal.last.methodId, 'describe_table1');
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);
  });

  test('exports : Word relu à l\'identique, Excel relu par le lecteur de l\'application, XML valide', () async {
    final tb = table1(_data(), group: 'groupe');
    final docx = tableDocx('Tableau 1', tb.header, tb.cells, notes: tb.notes);
    final text = docxText(docx);
    expect(text, contains('Ensemble (N = 20)'));
    expect(text, contains('Âge, ans, moyenne ± ET'));
    final xlsx = tableXlsx('Tableau 1', tb.header, tb.cells);
    final sheet = openXlsx(xlsx).sheet();
    expect(sheet.names, tb.header);
    expect(sheet.rowCount, tb.cells.length);
    final dir = await Directory.systemTemp.createTemp('statomea_t1');
    for (final (name, bytes) in [('t.docx', docx), ('t.xlsx', xlsx)]) {
      final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      final check = await Process.run('python3', ['-c', 'import sys,zipfile,xml.dom.minidom as m\nz=zipfile.ZipFile(sys.argv[1])\n[m.parseString(z.read(n)) for n in z.namelist()]\nprint("ok")', f.path]);
      expect('${check.stdout}'.trim(), 'ok', reason: '${check.stderr}');
    }
    await dir.delete(recursive: true);
  });
}
