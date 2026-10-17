import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:statomea/app_version.dart';
import 'package:statomea/main.dart';
import 'package:statomea/services/storage.dart';
import 'package:statomea/services/update/update_check.dart';
import 'package:statomea/state/app_state.dart';

void main() {
  test('la version de l\'application est celle de pubspec.yaml', () {
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, v);
  });

  test('comparaison de versions (suffixe de build ignoré)', () {
    expect(compareVersions('1.36.10', '1.36.9'), greaterThan(0));
    expect(compareVersions('1.37.0', '1.36.99'), greaterThan(0));
    expect(compareVersions('1.36.5+41', '1.36.5'), 0);
    expect(compareVersions('1.36.4', '1.36.5'), lessThan(0));
  });

  test('android.json : APK de l\'architecture du téléphone, sinon lien générique ; page HTML ignorée', () {
    const j = '{"version":"9.9.9","url":"telecharger/statomea.apk","urls":{"arm64-v8a":"telecharger/statomea-arm64-v8a.apk","armeabi-v7a":"telecharger/statomea-armeabi-v7a.apk"}}';
    expect(parseUpdate(j, current: '1.0.0', abi: 'arm64-v8a')!.url, '$statomeaSite/telecharger/statomea-arm64-v8a.apk');
    expect(parseUpdate(j, current: '1.0.0', abi: 'armeabi-v7a')!.url, '$statomeaSite/telecharger/statomea-armeabi-v7a.apk');
    expect(parseUpdate(j, current: '1.0.0', abi: 'x86_64')!.url, '$statomeaSite/telecharger/statomea.apk');
    expect(parseUpdate(j, current: '9.9.9'), isNull);
    // Ancien format (sans « urls ») et version web (sans lien).
    expect(parseUpdate('{"version":"9.9.9","url":"telecharger/statomea.apk"}', current: '1.0.0', abi: 'arm64-v8a')!.url, '$statomeaSite/telecharger/statomea.apk');
    expect(parseUpdate('{"app_name":"statomea","version":"9.9.9"}', current: '1.0.0')!.url, isNull);
    // Repli monopage du serveur (android.json absent → index.html).
    expect(parseUpdate('<!DOCTYPE html><html></html>', current: '1.0.0'), isNull);
  });

  Future<AppState> mount(WidgetTester t, {String? published, bool enabled = true, String? url}) async {
    var calls = 0;
    final state = AppState(MemoryStorage(), updateFetcher: () async {
      calls++;
      return published == null || compareVersions(published, appVersion) <= 0 ? null : UpdateInfo(published, url: url);
    });
    await state.load();
    if (!enabled) state.setCheckUpdates(false);
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const StatomeaApp()));
    await t.pumpAndSettle();
    addTearDown(() => expect(calls, enabled ? greaterThan(0) : 0));
    return state;
  }

  testWidgets('nouvelle version publiée : bandeau au démarrage ; « Plus tard » l\'écarte et s\'en souvient', (t) async {
    final state = await mount(t, published: '9.9.9');
    expect(find.textContaining('Nouvelle version 9.9.9 disponible'), findsOneWidget);
    expect(find.text('Recharger'), findsOneWidget); // version web : pas d'URL d'APK
    await t.tap(find.text('Plus tard'));
    await t.pumpAndSettle();
    expect(find.textContaining('Nouvelle version 9.9.9'), findsNothing);
    expect(state.dismissedUpdate, '9.9.9');
  });

  testWidgets('APK publié (Android) : le bandeau propose de télécharger', (t) async {
    await mount(t, published: '9.9.9', url: 'https://statomea.komodi-labo.org/telecharger/statomea.apk');
    expect(find.text('Télécharger et installer'), findsOneWidget);
    expect(find.text('Recharger'), findsNothing);
  });

  testWidgets('version à jour : pas de bandeau', (t) async {
    await mount(t, published: appVersion);
    expect(find.textContaining('Nouvelle version'), findsNothing);
  });

  testWidgets('vérification désactivée : aucune requête au démarrage, réglage visible dans Validation', (t) async {
    await mount(t, published: '9.9.9', enabled: false);
    expect(find.textContaining('Nouvelle version'), findsNothing);
    await t.tap(find.text('Validation').last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Vérifier les nouvelles versions'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Version installée : $appVersion'), findsOneWidget);
    expect(tester(t).widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Vérifier les nouvelles versions')).value, isFalse);
  });
}

WidgetTester tester(WidgetTester t) => t;
