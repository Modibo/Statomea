import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/meta_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  testWidgets('atelier de métaanalyse : méta-régression sur la latitude (BCG)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = buildDemoMeta(File('assets/demos/bcg_colditz1994.csv').readAsStringSync());
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MetaWorkshop(project: p, onResult: (r, {options = const {}}) => got = r)))),
    ));
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'annee'), findsOneWidget);
    await t.tap(find.widgetWithText(FilterChip, 'latitude'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lancer la méta-régression'));
    await t.pumpAndSettle();
    expect(got?.methodId, 'meta_regression');
    expect(got!.statistics['R2'], closeTo(0.7563, 1e-4)); // metafor : 75,63 %
    expect(got!.figures['bubble'], isNotNull);
  });
}
