import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app_version.dart';
import 'update_platform_io.dart' if (dart.library.js_interop) 'update_platform_web.dart' as platform;

/// Adresse publique de Statoméa : version web et téléchargement de l'APK.
const statomeaSite = 'https://statomea.komodi-labo.org';

/// Version publiée disponible ([url] : lien de téléchargement de l'APK ; null pour la version web, qui se recharge).
class UpdateInfo {
  final String version;
  final String? url;
  const UpdateInfo(this.version, {this.url});
}

/// Compare deux versions « a.b.c » (suffixe « +n » ignoré) : < 0, 0 ou > 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.trim().split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Lit la version publiée : `version.json` du site pour la version web, `android.json` (publié avec chaque APK) sur
/// Android. Aucune donnée de l'utilisateur n'est envoyée. Null si rien de plus récent, hors ligne, ou plateforme non
/// concernée.
Future<UpdateInfo?> fetchUpdate({String current = appVersion}) async {
  final String? body;
  if (kIsWeb) {
    body = await platform.getText('version.json?t=${DateTime.now().millisecondsSinceEpoch}');
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    body = await platform.getText('$statomeaSite/android.json');
  } else {
    return null;
  }
  if (body == null) return null;
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final v = j['version'] as String?;
    if (v == null || compareVersions(v, current) <= 0) return null;
    final url = j['url'] as String?;
    return UpdateInfo(v, url: url == null ? null : (url.startsWith('http') ? url : '$statomeaSite/$url'));
  } catch (_) {
    return null;
  }
}

/// Applique la mise à jour : la version web vide ses caches et se recharge ; Android ouvre le lien de l'APK.
Future<void> applyUpdate(UpdateInfo u) => kIsWeb ? platform.reloadFresh() : platform.openExternal(u.url ?? '$statomeaSite/telecharger/statomea.apk');
