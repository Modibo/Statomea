// Calculs lourds en arrière-plan : au-delà de 10 000 lignes (ou d'un fichier de 1 Mo), import, contrôle de qualité et
// Tableaux 1 et 2 tournent dans un isolat ; l'écran affiche « … en cours » puis le résultat.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/screens/steps/data_step.dart';
import 'package:statomea/services/background.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/state/app_state.dart';
import 'package:statomea/widgets/calculators.dart';
import 'package:statomea/widgets/common.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

String _csv(int n) {
  final rnd = Random(3);
  final b = StringBuffer('id,age,residence,parite,aghbs,poids\n');
  for (var i = 0; i < n; i++) {
    // Une valeur aberrante pour que le contrôle de qualité ait quelque chose à signaler.
    final age = i == 7 ? 230 : 18 + rnd.nextInt(28);
    b.writeln('F$i,$age,${rnd.nextBool() ? 'rural' : 'urbain'},${rnd.nextInt(7)},${rnd.nextDouble() < .12 ? 'positif' : 'negatif'},${(45 + rnd.nextDouble() * 40).toStringAsFixed(1)}');
  }
  return b.toString();
}

/// Laisse l'isolat travailler (temps réel) puis reconstruit l'écran, jusqu'à disparition de l'indicateur.
Future<void> _waitBusy(WidgetTester t) async {
  for (var k = 0; k < 100 && find.byType(BusyLine).evaluate().isNotEmpty; k++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  expect(find.byType(BusyLine), findsNothing);
}

void main() {
  test('inBackground : même résultat qu\'en direct, langue transmise, erreur de saisie relayée', () async {
    final ds = parseCsv(_csv(500)).dataset;
    final direct = checkQuality(ds, outcome: 'aghbs');
    final remote = await inBackground(_quality, ds);
    expect(remote.issues.map((i) => i.code), direct.issues.map((i) => i.code));
    setLang(Lang.en);
    addTearDown(() => setLang(Lang.fr));
    expect(await inBackground(_hello, 0), 'Hello');
    await expectLater(inBackground(_fails, 0), throwsA(isA<StatInputError>()));
  });

  testWidgets('étape 4 : gros fichier lu puis contrôlé en arrière-plan', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final p = state.createProject('Gros fichier');
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: MaterialApp(home: Scaffold(body: DataStep(p)))));
    await t.pumpAndSettle();
    final bytes = utf8.encode(_csv(40000));
    expect(bytes.length, greaterThan(backgroundByteThreshold));
    final st = t.state<DataStepState>(find.byType(DataStep));
    st.importFileBytes('gros.csv', bytes);
    await t.pump();
    expect(find.textContaining('Lecture de « gros.csv » en cours'), findsOneWidget);
    for (var k = 0; k < 100 && p.dataset == null; k++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(p.dataset!.rowCount, 40000);
    expect(find.textContaining('Contrôle de qualité en cours (40000 lignes)'), findsOneWidget);
    await _waitBusy(t);
    expect(find.textContaining('plausible'), findsWidgets); // âge de 230 ans signalé
    // Une simple reconstruction ne relance pas le contrôle (résultat mémorisé).
    st.setState(() {});
    await t.pump();
    expect(find.byType(BusyLine), findsNothing);
  });

  testWidgets('Tableaux 1 et 2 sur 20 000 lignes : calcul en arrière-plan, résultat au journal', (t) async {
    await t.binding.setSurfaceSize(const Size(1100, 3000));
    final state = AppState(MemoryStorage());
    await state.load();
    final ds = parseCsv(_csv(20000)).dataset;
    final p = state.createProject('T')..dataset = ds;
    p.roles = const VariableRoles(outcome: 'aghbs', eventLevel: 'positif', exposure: 'residence', covariates: ['age', 'parite']);
    for (final m in ['table1', 'table2']) {
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: state, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CalculatorPanel(key: UniqueKey(), project: p, initialMethod: m))))));
      await t.pumpAndSettle();
      await t.tap(find.text('Calculer'));
      await t.pump();
      expect(find.textContaining('Calcul en cours sur 20000 lignes'), findsOneWidget, reason: m);
      await _waitBusy(t);
      expect(find.text(m == 'table1' ? 'Tableau 1 (Word)' : 'Tableau 2 (Word)'), findsOneWidget);
    }
    expect([for (final e in p.journal) e.methodId], containsAllInOrder(['describe_table1', 'association_table']));
    await t.pump(const Duration(seconds: 3));
  });
}

QualityReport _quality(Dataset ds) => checkQuality(ds, outcome: 'aghbs');
String _hello(int _) => tr('Bonjour', 'Hello');
String _fails(int _) => throw StatInputError('missing', 'manque');
