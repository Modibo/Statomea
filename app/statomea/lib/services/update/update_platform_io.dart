import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// GET texte (délai court ; null en cas d'échec : hors ligne, serveur indisponible).
Future<String?> getText(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return await res.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> reloadFresh() async {}

/// Architecture Android de l'appareil, d'après la version de la VM Dart (« … on "android_arm64" »).
String? androidAbi() {
  final v = Platform.version;
  if (v.contains('android_arm64')) return 'arm64-v8a';
  if (v.contains('android_arm')) return 'armeabi-v7a';
  if (v.contains('android_x64')) return 'x86_64';
  return null;
}

Future<void> openExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
