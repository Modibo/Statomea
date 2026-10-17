{{flutter_js}}
{{flutter_build_config}}

// Amorçage sans service worker : celui de Flutter est obsolète et faisait servir l'ancienne version après une mise à
// jour (Safari). Les anciens enregistrements se désinscrivent d'eux-mêmes (flutter_service_worker.js de nettoyage).
_flutter.loader.load();
