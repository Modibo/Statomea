import 'package:web/web.dart' as web;

/// Fondu puis suppression de l'écran de démarrage défini dans web/index.html.
void hideSplash() {
  final s = web.document.getElementById('splash') as web.HTMLElement?;
  if (s == null) return;
  s.style.opacity = '0';
  Future<void>.delayed(const Duration(milliseconds: 300), () => s.remove());
}
