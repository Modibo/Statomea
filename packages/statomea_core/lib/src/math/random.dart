/// Générateur pseudo-aléatoire xorshift128 (Marsaglia 2003), sur 32 bits,
/// donnant la même suite sur toutes les plateformes (VM, web, mobile) pour
/// une graine donnée. Utilisé pour le bootstrap quand aucun jeu d'indices
/// n'est fourni.
library;

class SeededRandom {
  int _x, _y, _z, _w;
  final int seed;

  SeededRandom(this.seed)
      : _x = 123456789,
        _y = 362436069,
        _z = 521288629,
        _w = (88675123 ^ seed) & 0xFFFFFFFF {
    for (var i = 0; i < 16; i++) {
      nextUint32();
    }
  }

  int nextUint32() {
    final t = (_x ^ ((_x << 11) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >> 19) ^ (t ^ (t >> 8))) & 0xFFFFFFFF;
    return _w;
  }

  /// Uniforme sur [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Entier uniforme sur [0, n).
  int nextInt(int n) => (nextDouble() * n).floor();
}
