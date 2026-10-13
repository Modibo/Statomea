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

/// Désinscrit le service worker, vide les caches puis recharge : la nouvelle version est servie d'emblée.
Future<void> reloadFresh() async {
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
  web.window.location.reload();
}

Future<void> openExternal(String url) async {
  web.window.open(url, '_blank');
}

String? androidAbi() => null;
