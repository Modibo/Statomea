import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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

const _channel = MethodChannel('statomea/update');

/// Télécharge l'APK [url] dans le cache de l'application (progression 0 → 1 via [onProgress]), puis ouvre
/// l'installateur Android. Renvoie « ok », « permission » (réglage « installer des applications » ouvert : appuyer de
/// nouveau ensuite) ou lève une exception (l'appelant se rabat sur le navigateur). Un APK complet déjà téléchargé
/// pour cette version est réutilisé.
Future<String> downloadAndInstall(String url, String version, void Function(double) onProgress) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/update');
  await dir.create(recursive: true);
  final file = File('${dir.path}/statomea-$version.apk');
  final done = File('${file.path}.ok');
  if (!(await done.exists() && await file.exists())) {
    // Anciennes versions téléchargées : inutiles.
    await for (final e in dir.list()) {
      if (e is File && !e.path.contains('statomea-$version.')) await e.delete();
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      if (total > 0 && await file.length() != total) throw const HttpException('téléchargement incomplet');
      await done.writeAsString('ok');
    } finally {
      client.close(force: true);
    }
  }
  onProgress(1);
  return await _channel.invokeMethod<String>('install', {'path': file.path}) ?? 'ok';
}
