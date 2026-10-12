import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/prediction_workshop.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

void main() {
  testWidgets('atelier de prédiction : validation externe d\'un modèle d\'un autre projet', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3200));
    final state = AppState(MemoryStorage());
    await state.load();
    final dev = buildDemoPrediction(File('assets/demos/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 10);
    state.projects.add(dev);
    final ext = state.createProject('Cohorte externe');
    ext.dataset = parseCsv(File('assets/demos/cardiometabolique_externe_simule.csv').readAsStringSync()).dataset;
    AnalysisResult? got;
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: PredictionWorkshop(project: ext, onResult: (r, {options = const {}}) => got = r)))),
    ));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Modèle développé dans Statoméa'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('demo-01').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Valider le modèle sur les données de ce projet'));
    await t.pumpAndSettle();
    expect(got?.methodId, 'external_validation');
    expect(got!.statistics['auc'], closeTo(0.8032, 1e-4)); // pROC : 0,8032
  });
}
