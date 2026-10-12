/// Langue des textes produits par le moteur (messages, interprétations,
/// leçons, exports). Chaque texte est écrit dans les deux langues au même
/// endroit avec [tr], si bien qu'aucun message ne peut exister dans une seule
/// langue. Le moteur étant synchrone, la langue est un réglage global que
/// l'application fixe avant un calcul ([withLang] le fait de façon sûre) ;
/// un isolat de calcul doit la refixer.
library;

enum Lang { fr, en }

Lang _lang = Lang.fr;

Lang get currentLang => _lang;
void setLang(Lang l) => _lang = l;

/// Texte dans la langue courante.
String tr(String fr, String en) => _lang == Lang.en ? en : fr;

/// Exécute [f] dans la langue [l], puis restaure la langue précédente.
T withLang<T>(Lang l, T Function() f) {
  final old = _lang;
  _lang = l;
  try {
    return f();
  } finally {
    _lang = old;
  }
}
