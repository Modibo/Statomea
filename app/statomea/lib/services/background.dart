import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:statomea_core/statomea_core.dart';

/// Au-delà de ce nombre de lignes, les calculs sur un jeu de données partent en arrière-plan : l'écran reste fluide et
/// affiche la progression. En deçà, ils restent immédiats (quelques dizaines de millisecondes).
const int backgroundRowThreshold = 10000;

/// Au-delà de cette taille (1 Mo), un fichier importé est lu en arrière-plan.
const int backgroundByteThreshold = 1 << 20;

/// Exécute [f] hors du fil de l'interface quand [heavy] : dans un isolat (avec la langue courante) ; sur le web, qui n'a
/// pas d'isolat, après une image pour laisser paraître l'indicateur de progression. [f] doit être une fonction de premier
/// niveau et [arg] des données simples (jeu de données, formules, textes).
Future<R> inBackground<A, R>(R Function(A) f, A arg, {bool heavy = true}) async {
  if (!heavy) return f(arg);
  if (kIsWeb) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return f(arg);
  }
  final lang = currentLang;
  return Isolate.run(() {
    setLang(lang);
    return f(arg);
  });
}
