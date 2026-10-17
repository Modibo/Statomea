/// Données d'exemple SIMULÉES pour l'atelier génomique (reproductibles, graine fixe).
/// Aucune séquence ni aucun comptage ne provient d'un organisme ou d'un patient réel.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/random.dart';
import 'alignment.dart';

double _normal(SeededRandom r) {
  final u1 = math.max(r.nextDouble(), 1e-300), u2 = r.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

/// Loi gamma (Marsaglia-Tsang), forme k, échelle 1.
double _gamma(SeededRandom r, double k) {
  if (k < 1) return _gamma(r, k + 1) * math.pow(math.max(r.nextDouble(), 1e-300), 1 / k);
  final d = k - 1 / 3, c = 1 / math.sqrt(9 * d);
  for (;;) {
    final x = _normal(r), v0 = 1 + c * x;
    if (v0 <= 0) continue;
    final v = v0 * v0 * v0, u = r.nextDouble();
    if (math.log(math.max(u, 1e-300)) < 0.5 * x * x + d - d * v + d * math.log(v)) return d * v;
  }
}

int _poisson(SeededRandom r, double mu) {
  if (mu > 50) return math.max(0, (mu + math.sqrt(mu) * _normal(r)).round());
  final l = math.exp(-mu);
  var k = 0;
  var p = 1.0;
  do {
    k++;
    p *= r.nextDouble();
  } while (p > l);
  return k - 1;
}

/// Matrice de comptages RNA-seq simulée (binomiale négative = Poisson-gamma) : [genes] gènes, 3 témoins puis
/// 3 traités, environ 10 % de gènes différentiellement exprimés (log2 FC de ±1 à ±3).
({List<String> genes, List<List<double>> counts, List<bool> treated, List<String> samples}) exampleRnaSeq({int genes = 400, int seed = 20261019}) {
  final r = SeededRandom(seed);
  const libf = [1.0, 1.25, 0.85, 1.1, 0.9, 1.2];
  final treated = [false, false, false, true, true, true];
  final names = <String>[], counts = <List<double>>[];
  for (var g = 0; g < genes; g++) {
    final base = 5 + 400 * _gamma(r, 0.7);
    final de = r.nextDouble() < 0.1;
    final lfc = de ? (r.nextDouble() < 0.5 ? -1 : 1) * (1 + 2 * r.nextDouble()) : 0.0;
    final disp = 0.05 * math.exp(0.6 * _normal(r));
    names.add('GENE${(g + 1).toString().padLeft(4, '0')}');
    counts.add([
      for (var j = 0; j < 6; j++)
        _poisson(r, base * libf[j] * math.pow(2, treated[j] ? lfc : 0) * _gamma(r, 1 / disp) * disp).toDouble()
    ]);
  }
  return (genes: names, counts: counts, treated: treated, samples: [tr('temoin1', 'control1'), tr('temoin2', 'control2'), tr('temoin3', 'control3'), tr('traite1', 'treated1'), tr('traite2', 'treated2'), tr('traite3', 'treated3')]);
}

/// Plan simulé à 3 groupes (A, B, C ; 3 échantillons chacun) séquencés en 2 lots croisés avec les groupes,
/// avec un effet lot marqué sur 30 % des gènes : illustre l'ajustement sur le lot.
({List<String> genes, List<List<double>> counts, List<String> samples, List<String> group, List<String> batch}) exampleRnaSeqDesign({int genes = 500, int seed = 20261022}) {
  final r = SeededRandom(seed);
  const group = ['A', 'A', 'A', 'B', 'B', 'B', 'C', 'C', 'C'];
  const batch = ['L1', 'L2', 'L1', 'L2', 'L1', 'L2', 'L1', 'L2', 'L1'];
  const libf = [1.0, 1.2, 0.9, 1.1, 0.85, 1.25, 0.95, 1.15, 1.05];
  final names = <String>[], counts = <List<double>>[];
  for (var g = 0; g < genes; g++) {
    final base = 5 + 400 * _gamma(r, 0.7);
    double effect() => r.nextDouble() < 0.08 ? (r.nextDouble() < 0.5 ? -1 : 1) * (1 + 2 * r.nextDouble()) : 0.0;
    final eb = effect(), ec = effect();
    final lot = r.nextDouble() < 0.3 ? 1.5 * _normal(r) : 0.0;
    final disp = 0.05 * math.exp(0.6 * _normal(r));
    names.add('GENE${(g + 1).toString().padLeft(4, '0')}');
    counts.add([
      for (var j = 0; j < 9; j++)
        _poisson(r, base * libf[j] * math.pow(2, (group[j] == 'B' ? eb : 0) + (group[j] == 'C' ? ec : 0) + (batch[j] == 'L2' ? lot : 0)) * _gamma(r, 1 / disp) * disp).toDouble()
    ]);
  }
  return (genes: names, counts: counts, samples: [for (var j = 0; j < 9; j++) '${group[j]}${j % 3 + 1}'], group: group.toList(), batch: batch.toList());
}

/// Plan apparié simulé : 5 patients prélevés avant et après traitement, avec une forte variabilité entre
/// patients (l'appariement la retire) ; ~8 % de gènes modifiés par le traitement.
({List<String> genes, List<List<double>> counts, List<String> samples, List<String> time, List<String> subject}) exampleRnaSeqPaired({int genes = 500, int seed = 20261024}) {
  final r = SeededRandom(seed);
  final before = tr('avant', 'before'), after = tr('apres', 'after');
  final subject = [for (var i = 1; i <= 5; i++) ...['P$i', 'P$i']];
  final time = [for (var i = 0; i < 5; i++) ...[before, after]];
  final libf = [for (var j = 0; j < 10; j++) 0.8 + 0.4 * r.nextDouble()];
  final names = <String>[], counts = <List<double>>[];
  for (var g = 0; g < genes; g++) {
    final base = 5 + 400 * _gamma(r, 0.7);
    final lfc = r.nextDouble() < 0.08 ? (r.nextDouble() < 0.5 ? -1 : 1) * (0.7 + 1.5 * r.nextDouble()) : 0.0;
    final subj = [for (var i = 0; i < 5; i++) 0.8 * _normal(r)];
    final disp = 0.03 * math.exp(0.5 * _normal(r));
    names.add('GENE${(g + 1).toString().padLeft(4, '0')}');
    counts.add([
      for (var j = 0; j < 10; j++)
        _poisson(r, base * libf[j] * math.pow(2, subj[j ~/ 2] + (j.isOdd ? lfc : 0)) * _gamma(r, 1 / disp) * disp).toDouble()
    ]);
  }
  return (genes: names, counts: counts, samples: [for (var j = 0; j < 10; j++) '${subject[j]}_${time[j]}'], time: time, subject: subject);
}

String _mutate(SeededRandom r, String s, String alphabet, double pSub, double pIndel) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final u = r.nextDouble();
    if (u < pIndel / 2) continue;
    if (u < pIndel) b.write(alphabet[r.nextInt(alphabet.length)]);
    if (r.nextDouble() < pSub) {
      var c = s[i];
      while (c == s[i]) {
        c = alphabet[r.nextInt(alphabet.length)];
      }
      b.write(c);
    } else {
      b.write(s[i]);
    }
  }
  return b.toString();
}

/// Bibliothèque FASTA d'ADN simulée (6 « références » apparentées à des degrés divers) et une requête
/// dérivée de la référence 2 (1,5 % de substitutions), comme un séquençage d'isolat à identifier.
({String library, String query}) exampleFasta({int seed = 20261020}) {
  final r = SeededRandom(seed);
  String rand(int n) => [for (var i = 0; i < n; i++) 'ACGT'[r.nextInt(4)]].join();
  final ancestor = rand(900);
  final refs = <(String, String, String)>[
    ('ref1', tr('Référence simulée 1 (proche)', 'Simulated reference 1 (close)'), _mutate(r, ancestor, 'ACGT', 0.04, 0.004)),
    ('ref2', tr('Référence simulée 2', 'Simulated reference 2'), _mutate(r, ancestor, 'ACGT', 0.02, 0.002)),
    ('ref3', tr('Référence simulée 3 (même genre)', 'Simulated reference 3 (same genus)'), _mutate(r, ancestor, 'ACGT', 0.06, 0.006)),
    ('ref4', tr('Référence simulée 4 (éloignée)', 'Simulated reference 4 (distant)'), _mutate(r, ancestor, 'ACGT', 0.25, 0.02)),
    ('ref5', tr('Référence simulée 5 (sans rapport)', 'Simulated reference 5 (unrelated)'), rand(880)),
    ('ref6', tr('Référence simulée 6 (sans rapport)', 'Simulated reference 6 (unrelated)'), rand(940)),
  ];
  String wrap(String s) => [for (var i = 0; i < s.length; i += 70) s.substring(i, math.min(s.length, i + 70))].join('\n');
  final lib = [for (final (id, d, s) in refs) '>$id $d\n${wrap(s)}'].join('\n');
  final q = _mutate(r, refs[1].$3.substring(40, 840), 'ACGT', 0.015, 0);
  return (library: lib, query: '>isolat_X ${tr("séquence simulée", "simulated sequence")}\n${wrap(q)}');
}

/// Nombre de séquences et longueur totale d'une bibliothèque FASTA (contrôle avant calcul).
({int sequences, int letters}) fastaSummary(String text) {
  final recs = parseFasta(text);
  return (sequences: recs.length, letters: recs.fold<int>(0, (a, r) => a + r.sequence.length));
}


/// Statistiques publiées de randomisation mendélienne (28 variants associés aux lipides ; Waterworth et al. 2010 ; jeu
/// d'exemple ldlc/hdlc/trig/chdlodds du paquet R MendelianRandomization) : associations par allèle avec le LDL, le HDL et
/// les triglycérides (mmol/L) et avec la maladie coronarienne (log-odds), avec leurs erreurs types.
const mrLipidExample = (
  bldl: <double>[0.026, -0.044, -0.038, -0.023, -0.017, -0.031, -0.018, 0.046, 0.059, 0.004, 0.011, -0.005, 0.004, 0.022, -0.005, -0.002, -0.002, 0.004, 0.011, 0.009, -0.011, -0.003, -0.012, 3e-04, -0.015, -0.008, 0.009, -0.036],
  sldl: <double>[0.004, 0.004, 0.004, 0.003, 0.003, 0.006, 0.004, 0.007, 0.004, 0.003, 0.004, 0.005, 0.005, 0.005, 0.004, 0.004, 0.003, 0.004, 0.004, 0.003, 0.004, 0.003, 0.004, 0.003, 0.003, 0.004, 0.003, 0.007],
  bhdl: <double>[0.002, 0.005, 0.003, 0.001, 0.011, 0.031, -0.003, -0.007, -0.021, 0.018, -0.017, -0.047, 0.022, -0.029, 0.016, 0.034, 0.035, 0.019, 0.028, 1e-04, 0.016, 0.005, -0.01, -0.023, 0.012, 0.018, -0.006, 0.004],
  shdl: <double>[0.004, 0.004, 0.004, 0.003, 0.003, 0.006, 0.004, 0.006, 0.004, 0.003, 0.003, 0.005, 0.004, 0.004, 0.003, 0.004, 0.003, 0.004, 0.004, 0.003, 0.003, 0.003, 0.004, 0.003, 0.003, 0.003, 0.003, 0.006],
  btg: <double>[0.016, -0.004, -0.009, 0.003, -0.039, -0.142, 0.007, 0.095, 0.042, -0.023, 0.036, 0.097, 0.013, 0.142, -0.005, 0.019, 0.003, -0.018, -0.02, 0.035, -0.036, -0.054, 0.054, 0.067, -0.04, -0.067, 0.028, -0.07],
  stg: <double>[0.008, 0.008, 0.008, 0.006, 0.006, 0.012, 0.007, 0.013, 0.008, 0.006, 0.007, 0.01, 0.009, 0.009, 0.007, 0.007, 0.006, 0.008, 0.008, 0.007, 0.007, 0.006, 0.008, 0.006, 0.006, 0.007, 0.006, 0.013],
  bchd: <double>[0.0677, -0.1625, -0.1054, -0.0619, -0.0834, -0.1278, -0.0408, 0.077, 0.157, -0.0305, 0.01, 0.1823, -0.0408, 0.1989, 0.01, 0.0488, 0.01, -0.0408, -0.0305, -0.0408, -0.0202, -0.0619, 0.0296, 0.0677, -0.0726, -0.0726, 0, 0.0198],
  schd: <double>[0.0286, 0.03, 0.031, 0.0243, 0.0222, 0.0667, 0.0373, 0.0543, 0.0306, 0.0236, 0.0277, 0.0403, 0.0344, 0.0335, 0.0378, 0.0292, 0.0253, 0.0319, 0.0316, 0.0241, 0.0285, 0.0217, 0.0298, 0.0239, 0.022, 0.0246, 0.0255, 0.0647],
);

/// Programme de greffe cardiaque de Stanford (Crowley et Hu 1977 ; jeu « jasa » du paquet R survival) : 103 patients
/// inscrits sur liste d'attente. Durée de suivi en jours (≥ 0,5), décès, délai d'attente avant greffe (null = non
/// greffé ; avancé de 0,5 jour si greffe le jour du décès, comme la vignette de survival), âge − 48 ans, pontage antérieur.
/// Exemple classique du biais du temps immortel (demos/greffe_stanford.csv, validation/r/41_cox_temps.R).
const stanfordHeartExample = (
  days: <double>[49, 5, 15, 38, 17, 2, 674, 39, 84, 57, 152, 7, 80, 1386, 0.5, 307, 35, 42, 36, 27, 1031, 50, 732, 218, 1799, 1400, 262, 71, 34, 851, 15, 76, 1586, 1571, 11, 99, 65, 4, 52, 1407, 1321, 2, 1, 39, 44, 995, 71, 8, 1141, 979, 284, 101, 187, 2, 60, 941, 148, 342, 915, 67, 1, 68, 841, 583, 77, 31, 284, 67, 669, 29, 619, 595, 89, 16, 1, 544, 20, 514, 95, 481, 444, 427, 79, 333, 4, 396, 109, 369, 206, 185, 339, 339, 264, 164, 15, 179, 130, 108, 20, 38, 30, 10, 5],
  died: <int>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1],
  wait: <double?>[null, null, 0, 35, null, null, 50, null, null, 11, 25, null, 16, 36, null, 27, null, 19, null, 17, 7, 11, 2, 82, 24, null, null, 70, null, 15, null, 16, 50, 22, null, 45, 18, 3.5, 1, 40, 57, null, null, null, 0, 1, 20, null, 35, 82, 31, null, 40, null, 9, 66, null, 20, 77, 2, null, null, 26, 32, 11, null, 56, 2, 9, 4, 30, 3, 26, 4, null, 45, null, 209, 66, 25, 5, null, 31, 36, null, 7, 59, 30, 138, 159, null, 309, 27, 3, 1, 12, 20, 95, null, 37, null, null, null],
  age: <double>[-17.16, 3.84, 6.3, -7.74, -27.21, 6.6, 2.87, -2.65, -0.84, -5.5, -0.02, 5.19, 6.57, 6.01, 5.82, 1.45, -27.67, 8.85, 11.12, 7.28, -4.66, -5.22, 10.36, 3.8, -14.78, -17.46, -39.21, 6.02, 2.43, -3.09, 6.89, 16.41, 0.9, -7.45, -4.53, 0.93, 13.5, -6.53, 2.52, 0.48, -2.7, -11.56, -4.61, -5.42, -11.82, 0.61, -0.9, 8.04, -11.35, -2.11, 0.73, -6.75, -0.66, -0.21, 4.45, -9.26, -6.74, 0.02, -6.62, 1.05, 4.56, -8.65, -15.34, 0.82, 3.29, 5.21, -28.45, -2.76, -0.01, 5, -0.59, -21.27, 8.33, -18.83, 4.18, 4.08, -6.89, 0.7, 5.78, -1.56, 4.89, -18.8, 5.31, -5.28, -0.02, 0.92, -1.75, 6.36, 3.05, 4.03, -0.41, -3.02, -0.25, -4.16, -7.72, -21.35, -24.38, -19.37, 1.83, -12.94, 1.52, -7.61, -8.68],
  surgery: <int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0],
);

/// Étude de privation de sommeil (Belenky et al. 2003 ; jeu « sleepstudy » du paquet R lme4) : temps de réaction moyen
/// (ms) de 18 sujets, jours 0 à 9 (demos/sommeil_belenky.csv, validation/r/43_lmm_longitudinal.R).
const sleepStudyExample = (
  subject: <String>['S308', 'S308', 'S308', 'S308', 'S308', 'S308', 'S308', 'S308', 'S308', 'S308', 'S309', 'S309', 'S309', 'S309', 'S309', 'S309', 'S309', 'S309', 'S309', 'S309', 'S310', 'S310', 'S310', 'S310', 'S310', 'S310', 'S310', 'S310', 'S310', 'S310', 'S330', 'S330', 'S330', 'S330', 'S330', 'S330', 'S330', 'S330', 'S330', 'S330', 'S331', 'S331', 'S331', 'S331', 'S331', 'S331', 'S331', 'S331', 'S331', 'S331', 'S332', 'S332', 'S332', 'S332', 'S332', 'S332', 'S332', 'S332', 'S332', 'S332', 'S333', 'S333', 'S333', 'S333', 'S333', 'S333', 'S333', 'S333', 'S333', 'S333', 'S334', 'S334', 'S334', 'S334', 'S334', 'S334', 'S334', 'S334', 'S334', 'S334', 'S335', 'S335', 'S335', 'S335', 'S335', 'S335', 'S335', 'S335', 'S335', 'S335', 'S337', 'S337', 'S337', 'S337', 'S337', 'S337', 'S337', 'S337', 'S337', 'S337', 'S349', 'S349', 'S349', 'S349', 'S349', 'S349', 'S349', 'S349', 'S349', 'S349', 'S350', 'S350', 'S350', 'S350', 'S350', 'S350', 'S350', 'S350', 'S350', 'S350', 'S351', 'S351', 'S351', 'S351', 'S351', 'S351', 'S351', 'S351', 'S351', 'S351', 'S352', 'S352', 'S352', 'S352', 'S352', 'S352', 'S352', 'S352', 'S352', 'S352', 'S369', 'S369', 'S369', 'S369', 'S369', 'S369', 'S369', 'S369', 'S369', 'S369', 'S370', 'S370', 'S370', 'S370', 'S370', 'S370', 'S370', 'S370', 'S370', 'S370', 'S371', 'S371', 'S371', 'S371', 'S371', 'S371', 'S371', 'S371', 'S371', 'S371', 'S372', 'S372', 'S372', 'S372', 'S372', 'S372', 'S372', 'S372', 'S372', 'S372'],
  days: <double>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  reaction: <double>[249.56, 258.7047, 250.8006, 321.4398, 356.8519, 414.6901, 382.2038, 290.1486, 430.5853, 466.3535, 222.7339, 205.2658, 202.9778, 204.707, 207.7161, 215.9618, 213.6303, 217.7272, 224.2957, 237.3142, 199.0539, 194.3322, 234.32, 232.8416, 229.3074, 220.4579, 235.4208, 255.7511, 261.0125, 247.5153, 321.5426, 300.4002, 283.8565, 285.133, 285.7973, 297.5855, 280.2396, 318.2613, 305.3495, 354.0487, 287.6079, 285, 301.8206, 320.1153, 316.2773, 293.3187, 290.075, 334.8177, 293.7469, 371.5811, 234.8606, 242.8118, 272.9613, 309.7688, 317.4629, 309.9976, 454.1619, 346.8311, 330.3003, 253.8644, 283.8424, 289.555, 276.7693, 299.8097, 297.171, 338.1665, 332.0265, 348.8399, 333.36, 362.0428, 265.4731, 276.2012, 243.3647, 254.6723, 279.0244, 284.1912, 305.5248, 331.5229, 335.7469, 377.299, 241.6083, 273.9472, 254.4907, 270.8021, 251.4519, 254.6362, 245.4523, 235.311, 235.7541, 237.2466, 312.3666, 313.8058, 291.6112, 346.1222, 365.7324, 391.8385, 404.2601, 416.6923, 455.8643, 458.9167, 236.1032, 230.3167, 238.9256, 254.922, 250.7103, 269.7744, 281.5648, 308.102, 336.2806, 351.6451, 256.2968, 243.4543, 256.2046, 255.5271, 268.9165, 329.7247, 379.4445, 362.9184, 394.4872, 389.0527, 250.5265, 300.0576, 269.8939, 280.5891, 271.8274, 304.6336, 287.7466, 266.5955, 321.5418, 347.5655, 221.6771, 298.1939, 326.8785, 346.8555, 348.7402, 352.8287, 354.4266, 360.4326, 375.6406, 388.5417, 271.9235, 268.4369, 257.2424, 277.6566, 314.8222, 317.2135, 298.1353, 348.1229, 340.28, 366.5131, 225.264, 234.5235, 238.9008, 240.473, 267.5373, 344.1937, 281.1481, 347.5855, 365.163, 372.2288, 269.8804, 272.4428, 277.8989, 281.7895, 279.1705, 284.512, 259.2658, 304.6306, 350.7807, 369.4692, 269.4117, 273.474, 297.5968, 310.6316, 287.1726, 329.6076, 334.4818, 343.2199, 369.1417, 364.1236],
);
