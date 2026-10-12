import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/meta_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  testWidgets('atelier de métaanalyse : mode test diagnostique (AuditC)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Diag');
    final ds = parseCsv(File('test/diagmeta_auditc.csv').readAsStringSync()).dataset;
    p.studies = [
      for (var i = 0; i < ds.rowCount; i++)
        Study('s$i', 'Étude ${i + 1}', {for (final k in ['TP', 'FP', 'FN', 'TN']) k.toLowerCase(): SourcedValue(parseNumber(ds.cell(i, k)))})
    ];
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MetaWorkshop(project: p, onResult: (r, {options = const {}}) => got = r)))),
    ));
    await t.pumpAndSettle();
    expect(find.text('VP'), findsOneWidget);
    await t.tap(find.text('Lancer la métaanalyse diagnostique'));
    await t.pumpAndSettle();
    expect(got?.methodId, 'meta_diagnostic');
    expect(got!.estimates.first.value, closeTo(0.8909, 1e-4)); // mada : 0,891
    expect(got!.figures['sroc'], isNotNull);
  });
}
