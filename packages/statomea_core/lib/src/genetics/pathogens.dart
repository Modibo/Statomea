/// Génomique des pathogènes :
///  - concordance génotype ↔ phénotype : une mutation (ou un catalogue de mutations, règle « au moins une »)
///    prédit-elle la résistance mesurée à l'antibiogramme ? Se, Sp, VPP, VPN (IC de Wilson), kappa de Cohen ;
///  - diversité des types (lignées, ST, spoligotypes) : indice discriminant de Hunter-Gaston (IC de Grundmann
///    2001) et indice de Shannon.
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../inference/proportion.dart';
import '../math/distributions.dart';
import '../model/result.dart';

bool? _present(String? s) {
  if (s == null) return null;
  final t = s.trim().toLowerCase();
  if (t.isEmpty || isMissingToken(t)) return null;
  if (const {'1', 'oui', 'yes', 'present', 'présent', 'presente', 'présente', 'mut', 'mutant', '+', 'true', 'vrai'}.contains(t)) return true;
  if (const {'0', 'non', 'no', 'absent', 'absente', 'wt', 'sauvage', 'wild', '-', 'false', 'faux'}.contains(t)) return false;
  return null;
}

class _Conc {
  final int tp, fp, fn, tn;
  _Conc(this.tp, this.fp, this.fn, this.tn);
  int get n => tp + fp + fn + tn;
  double get po => (tp + tn) / n;
  double get pe => ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / (n * n);
  double get kappa => (po - pe) / (1 - pe);

  /// ES asymptotique du kappa (Fleiss, Cohen et Everitt 1969).
  double get kappaSe {
    final k = kappa, nn = n.toDouble();
    final p11 = tp / nn, p12 = fp / nn, p21 = fn / nn, p22 = tn / nn;
    final r1 = p11 + p12, r2 = p21 + p22, c1 = p11 + p21, c2 = p12 + p22;
    final a = p11 * math.pow(1 - (r1 + c1) * (1 - k), 2) + p22 * math.pow(1 - (r2 + c2) * (1 - k), 2);
    final b = math.pow(1 - k, 2) * (p12 * math.pow(c1 + r2, 2) + p21 * math.pow(c2 + r1, 2));
    final c = math.pow(k - pe * (1 - k), 2);
    return math.sqrt((a + b - c) / nn) / (1 - pe);
  }
}

/// Concordance de mutations avec un phénotype de résistance.
/// [mutations] : colonnes présence/absence (1/0, oui/non, mutant/sauvage…).
AnalysisResult mutationPhenotypeConcordance(Dataset ds, String phenotype, String resistantLevel, List<String> mutations, {double level = 0.95}) {
  if (mutations.isEmpty) throw StatInputError('no_mutation', tr('Choisir au moins une mutation.', 'Choose at least one mutation.'));
  final y = ds.text(phenotype);
  final excluded = ds.excludedRows;
  final cols = {for (final m in mutations) m: [for (final s in ds.text(m)) _present(s)]};
  bool? anyOf(int i) {
    final v = [for (final m in mutations) cols[m]![i]];
    if (v.contains(true)) return true;
    if (v.contains(null)) return null;
    return false;
  }

  _Conc conc(bool? Function(int) g) {
    var tp = 0, fp = 0, fn = 0, tn = 0;
    for (var i = 0; i < ds.rowCount; i++) {
      if (excluded.contains(i) || y[i] == null) continue;
      final m = g(i);
      if (m == null) continue;
      final r = y[i] == resistantLevel;
      if (m && r) {
        tp++;
      } else if (m) {
        fp++;
      } else if (r) {
        fn++;
      } else {
        tn++;
      }
    }
    return _Conc(tp, fp, fn, tn);
  }

  final rows = <(String, _Conc)>[
    for (final m in mutations) (m, conc((i) => cols[m]![i])),
    if (mutations.length > 1) (tr('Au moins une mutation listée', 'At least one listed mutation'), conc(anyOf)),
  ];
  final z = normalQuantile(1 - (1 - level) / 2);
  String ci(int x, int n) {
    if (n == 0) return '—';
    final w = wilsonCi(x, n, level: level);
    return '${fmtPct(x / n)} (${fmtPct(w.lower)} – ${fmtPct(w.upper)})';
  }

  final main = rows.last.$2;
  final se = wilsonCi(main.tp, main.tp + main.fn, level: level), sp = wilsonCi(main.tn, main.tn + main.fp, level: level);
  final kSe = main.kappaSe;
  final excludedMissing = [for (var i = 0; i < ds.rowCount; i++) if (!excluded.contains(i) && y[i] != null && anyOf(i) == null) i].length;
  return AnalysisResult(
    methodId: 'mutation_phenotype',
    methodName: tr('Concordance génotype – phénotype de résistance', 'Genotype – resistance phenotype concordance'),
    inputs: {'phenotype': phenotype, 'resistantLevel': resistantLevel, 'mutations': mutations, 'level': level},
    formula: tr(
        'Mutation présente = « test positif », phénotype « $resistantLevel » = référence. Se = VP/(VP+FN), Sp = VN/(VN+FP), VPP, VPN avec IC de Wilson. Kappa de Cohen = (po − pe)/(1 − pe), ES de Fleiss, Cohen et Everitt (1969). Règle combinée : résistant prédit si au moins une mutation listée est présente.',
        'Mutation present = "positive test", phenotype "$resistantLevel" = reference. Se = TP/(TP+FN), Sp = TN/(TN+FP), PPV, NPV with Wilson CI. Cohen\'s kappa = (po − pe)/(1 − pe), SE of Fleiss, Cohen and Everitt (1969). Combined rule: resistance predicted if at least one listed mutation is present.'),
    estimates: [
      Estimate(tr('Sensibilité — ${rows.last.$1}', 'Sensitivity — ${rows.last.$1}'), main.tp / (main.tp + main.fn), lower: se.lower, upper: se.upper, level: level),
      Estimate(tr('Spécificité — ${rows.last.$1}', 'Specificity — ${rows.last.$1}'), main.tn / (main.tn + main.fp), lower: sp.lower, upper: sp.upper, level: level),
      Estimate(tr('Kappa de Cohen — ${rows.last.$1}', "Cohen's kappa — ${rows.last.$1}"), main.kappa, lower: main.kappa - z * kSe, upper: main.kappa + z * kSe, level: level, se: kSe),
    ],
    statistics: {
      for (final (name, c) in rows) ...{
        'tp_$name': c.tp.toDouble(),
        'fp_$name': c.fp.toDouble(),
        'fn_$name': c.fn.toDouble(),
        'tn_$name': c.tn.toDouble(),
        'kappa_$name': c.kappa,
        'kappa_se_$name': c.kappaSe,
      }
    },
    checks: [
      Check('reference_phenotype', tr('Phénotype de référence fiable (méthode et seuils documentés)', 'Reliable reference phenotype (method and breakpoints documented)'), CheckStatus.notAssessed,
          tr("Une erreur d'antibiogramme apparaît comme une discordance génotype-phénotype.", 'An antibiogram error shows up as a genotype-phenotype discordance.')),
      Check('heteroresistance', tr('Hétérorésistance et mutations hors catalogue considérées', 'Heteroresistance and off-catalogue mutations considered'), CheckStatus.notAssessed,
          tr('Les faux négatifs génotypiques relèvent souvent de mutations non listées ou de populations mixtes.', 'Genotypic false negatives often come from unlisted mutations or mixed populations.')),
    ],
    alerts: [
      if (excludedMissing > 0)
        Alert('missing_genotypes', Severity.caution,
            tr('$excludedMissing isolat(s) au génotype indéterminé exclu(s) de la règle combinée.', '$excludedMissing isolate(s) with an undetermined genotype excluded from the combined rule.')),
      Alert('prevalence', Severity.info,
          tr('VPP et VPN dépendent de la prévalence de la résistance dans cette collection : elles ne se transposent pas telles quelles.',
              'PPV and NPV depend on the prevalence of resistance in this collection: they do not transfer as is.')),
    ],
    tables: [
      ResultTable(tr('Concordance par mutation', 'Concordance by mutation'), [
        tr('Mutation', 'Mutation'),
        tr('VP / FP / FN / VN', 'TP / FP / FN / TN'),
        tr('Sensibilité (IC)', 'Sensitivity (CI)'),
        tr('Spécificité (IC)', 'Specificity (CI)'),
        tr('VPP (IC)', 'PPV (CI)'),
        tr('VPN (IC)', 'NPV (CI)'),
        'Kappa (IC)',
      ], [
        for (final (name, c) in rows)
          [
            name,
            '${c.tp} / ${c.fp} / ${c.fn} / ${c.tn}',
            ci(c.tp, c.tp + c.fn),
            ci(c.tn, c.tn + c.fp),
            ci(c.tp, c.tp + c.fp),
            ci(c.tn, c.tn + c.fn),
            c.n == 0 ? '—' : '${fmt(c.kappa)} (${fmt(c.kappa - z * c.kappaSe)} – ${fmt(c.kappa + z * c.kappaSe)})',
          ]
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          "Évaluer une prédiction génotypique de la résistance : la mutation joue le rôle d'un test diagnostique dont l'antibiogramme est la référence.",
          'Evaluating a genotypic prediction of resistance: the mutation acts as a diagnostic test with the antibiogram as reference.'),
      whatItMeans: tr(
          '${rows.last.$1} : sensibilité ${fmtPct(main.tp / (main.tp + main.fn))}, spécificité ${fmtPct(main.tn / (main.tn + main.fp))}, kappa ${fmt(main.kappa)}. Les résistances sans mutation listée (${main.fn}) signalent des mécanismes non couverts par le catalogue.',
          '${rows.last.$1}: sensitivity ${fmtPct(main.tp / (main.tp + main.fn))}, specificity ${fmtPct(main.tn / (main.tn + main.fp))}, kappa ${fmt(main.kappa)}. Resistances without a listed mutation (${main.fn}) point to mechanisms not covered by the catalogue.'),
      notJustified: tr(
          "Remplacer l'antibiogramme par le génotype quand la sensibilité est imparfaite ; transposer VPP et VPN à une autre prévalence ; conclure qu'une mutation est causale à partir de la seule association.",
          'Replacing the antibiogram with the genotype when sensitivity is imperfect; transferring PPV and NPV to another prevalence; concluding a mutation is causal from association alone.'),
    ),
  );
}

/// Diversité des types d'une collection d'isolats.
AnalysisResult typeDiversity(Dataset ds, String typeColumn) {
  final counts = <String, int>{};
  for (var i = 0; i < ds.rowCount; i++) {
    final v = ds.cell(i, typeColumn);
    if (ds.excludedRows.contains(i) || v == null || isMissingToken(v.trim())) continue;
    counts[v.trim()] = (counts[v.trim()] ?? 0) + 1;
  }
  final n = counts.values.fold(0, (a, b) => a + b);
  if (n < 2) throw StatInputError('n_too_small', tr('Au moins 2 isolats typés sont requis.', 'At least 2 typed isolates are required.'));
  final pi = [for (final c in counts.values) c / n];
  final d = 1 - counts.values.fold(0.0, (a, c) => a + c * (c - 1)) / (n * (n - 1));
  final s2 = pi.fold(0.0, (a, p) => a + p * p), s3 = pi.fold(0.0, (a, p) => a + p * p * p);
  final v = 4 / n * (s3 - s2 * s2);
  final lo = d - 2 * math.sqrt(v), hi = d + 2 * math.sqrt(v);
  final h = -pi.fold(0.0, (a, p) => a + p * math.log(p));
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return AnalysisResult(
    methodId: 'type_diversity',
    methodName: tr('Diversité des types (Hunter-Gaston, Shannon)', 'Type diversity (Hunter-Gaston, Shannon)'),
    inputs: {'column': typeColumn},
    formula: tr(
        'Indice discriminant de Hunter-Gaston D = 1 − Σ nⱼ(nⱼ − 1) / [N(N − 1)] (probabilité que deux isolats tirés au hasard soient de types différents) ; IC ≈ D ± 2√{(4/N)[Σπⱼ³ − (Σπⱼ²)²]} (Grundmann 2001). Shannon H = −Σ πⱼ ln πⱼ.',
        'Hunter-Gaston discriminatory index D = 1 − Σ nⱼ(nⱼ − 1) / [N(N − 1)] (probability that two random isolates are of different types); CI ≈ D ± 2√{(4/N)[Σπⱼ³ − (Σπⱼ²)²]} (Grundmann 2001). Shannon H = −Σ πⱼ ln πⱼ.'),
    estimates: [
      Estimate(tr('Indice discriminant de Hunter-Gaston', 'Hunter-Gaston discriminatory index'), d, lower: math.max(0, lo), upper: math.min(1, hi)),
      Estimate(tr('Indice de Shannon (nats)', 'Shannon index (nats)'), h),
    ],
    statistics: {'n': n.toDouble(), 'types': counts.length.toDouble(), 'hunter_gaston': d, 'hg_lower': lo, 'hg_upper': hi, 'shannon': h},
    checks: [
      Check('sampling', tr('Collection représentative (pas de surreprésentation d\'une épidémie)', 'Representative collection (no over-representation of an outbreak)'), CheckStatus.notAssessed,
          tr('Des isolats liés (même patient, même épidémie) réduisent artificiellement la diversité.', 'Related isolates (same patient, same outbreak) artificially reduce diversity.')),
    ],
    alerts: [
      if (d < 0.95)
        Alert('discrimination', Severity.info,
            tr('D < 0,95 : pouvoir discriminant insuffisant pour une méthode de typage destinée à distinguer des souches (repère de Hunter et Gaston).',
                'D < 0.95: insufficient discriminatory power for a typing method meant to distinguish strains (Hunter and Gaston benchmark).')),
    ],
    tables: [
      ResultTable(tr('Types', 'Types'), ['Type', 'n', '%'], [
        for (final e in sorted) [e.key, '${e.value}', fmtPct(e.value / n)]
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr('Décrire la diversité d\'une collection et le pouvoir discriminant d\'une méthode de typage.', 'Describe the diversity of a collection and the discriminatory power of a typing method.'),
      whatItMeans: tr('${counts.length} types parmi $n isolats ; D = ${fmt(d)} (IC ${fmt(lo)} à ${fmt(hi)}) : probabilité que deux isolats pris au hasard diffèrent. Shannon H = ${fmt(h)}.',
          '${counts.length} types among $n isolates; D = ${fmt(d)} (CI ${fmt(lo)} to ${fmt(hi)}): probability that two random isolates differ. Shannon H = ${fmt(h)}.'),
      notJustified: tr('Interpréter un type commun comme une transmission récente sans données épidémiologiques ni génomiques fines (SNP).', 'Interpreting a shared type as recent transmission without epidemiological or fine genomic (SNP) data.'),
    ),
  );
}
