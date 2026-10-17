import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// GET texte relatif au site (sans cache) ; null en cas d'échec.
Future<String?> getText(String url) async {
  try {
    final res = await web.window.fetch(url.toJS, web.RequestInit(cache: 'no-store')).toDart;
    if (!res.ok) return null;
    return (await res.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// Désinscrit le service worker, vide les caches puis rouvre l'application à une adresse marquée de la nouvelle
/// [version] (« /app/?v=1.50.2 ») : Safari (Mac, iPhone) resservait l'ancien code sur un simple location.reload().
/// La page ainsi rechargée référence `main.dart.js?v=<version>` (deploy/publish-web.sh), adresse jamais mise en cache.
Future<void> reloadFresh(String version) async {
  try {
    final regs = (await web.window.navigator.serviceWorker.getRegistrations().toDart).toDart;
    for (final r in regs) {
      await r.unregister().toDart;
    }
    final keys = (await web.window.caches.keys().toDart).toDart;
    for (final k in keys) {
      await web.window.caches.delete(k.toDart).toDart;
    }
  } catch (_) {}
  final loc = web.window.location;
  loc.replace('${loc.pathname}?v=${Uri.encodeQueryComponent(version)}');
}

Future<void> openExternal(String url) async {
  web.window.open(url, '_blank');
}

String? androidAbi() => null;

Future<String> downloadAndInstall(String url, String version, void Function(double) onProgress) async => throw UnsupportedError('web');
