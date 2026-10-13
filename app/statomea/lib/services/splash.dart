import 'splash_io.dart' if (dart.library.js_interop) 'splash_web.dart' as impl;

/// Retire l'écran de démarrage de la page web (sans effet sur Android / iOS).
void hideSplash() => impl.hideSplash();
