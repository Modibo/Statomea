/// Score de risque polygénique par « clumping + seuil de p » (C+T, comme PLINK --clump puis --score) :
///  - répartition fixe des sujets dans l'ordre du fichier (i à partir de 0) : i mod 6 ∈ {0, 1, 2, 3} → découverte (2/3),
///    4 → validation (choix du seuil), 5 → test (performance rapportée) ;
///  - découverte : régression logistique issue ~ dosage (allèle compté du fichier) par variant, β et p de Wald ;
///  - clumping sur les génotypes de découverte : variants par p croissant ; chaque variant restant devient index et
///    écarte ceux du même chromosome à ≤ [windowBp] avec r² > [r2Max] ;
///  - score = Σ β_j·dosage_ij sur les index de p ≤ T (manquant → 2·fréquence de découverte), pour chaque seuil T ;
///  - validation : score centré réduit, logistique, OR par ET, AUC, R² de Nagelkerke ; seuil = R² maximal ;
///  - test : performance du seuil retenu, IC de l'AUC par DeLong.
/// Validé contre R (`validation/r/34_prs.R`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../i18n.dart';
import '../math/distributions.dart';
import '../model/result.dart';
import '../prediction/performance.dart';
import '../regression/glm.dart';
import 'genotype_io.dart';
import 'genotype_lmm.dart' show LmmCovariate;

const prsThresholds = [5e-8, 1e-6, 1e-4, 1e-3, 0.01, 0.05, 0.1, 0.5, 1.0];

/// Partie d'un sujet selon son rang dans le fichier : 0 découverte, 1 validation, 2 test.
int prsPart(int i) => switch (i % 6) { 4 => 1, 5 => 2, _ => 0 };

class PrsMetrics {
  /// [r2] : R² de Nagelkerke incrémental (modèle complet − modèle des covariables ; sans covariable, R² du score).
  /// [auc] : AUC du score seul ; [aucBase], [aucFull] : AUC des prédicteurs linéaires des modèles de base et complet.
  final double beta, se, p, auc, r2, r2Base, aucBase, aucFull;
  final int n, cases;
  final List<double> lpBase, lpFull;
  const PrsMetrics(this.beta, this.se, this.p, this.auc, this.r2, this.n, this.cases,
      {this.r2Base = 0, this.aucBase = 0.5, required this.aucFull, this.lpBase = const [], this.lpFull = const []});
  double get orPerSd => math.exp(beta);
}

class PrsFit {
  final List<double?> beta, p;
  final List<int> index;
  final List<(double, int, PrsMetrics)> validation; // seuil, nombre de variants, mesures
  final double bestThreshold;
  final PrsMetrics test;
  final AucResult testAuc;

  /// Avec covariables : gain d'AUC du modèle complet sur le modèle de base (test, DeLong apparié).
  final ({double diff, double se, double lower, double upper, double z, double p})? deltaAuc;
  final AnalysisResult result;
  PrsFit(this.beta, this.p, this.index, this.validation, this.bestThreshold, this.test, this.testAuc, this.result, {this.deltaAuc});
}

double _r2(Int8List a, Int8List b) {
  var n = 0;
  var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] < 0 || b[i] < 0) continue;
    n++;
    sa += a[i];
    sb += b[i];
    saa += a[i] * a[i];
    sbb += b[i] * b[i];
    sab += a[i] * b[i];
  }
  if (n < 3) return 0;
  final va = saa - sa * sa / n, vb = sbb - sb * sb / n, cov = sab - sa * sb / n;
  if (va <= 1e-12 || vb <= 1e-12) return 0;
  return cov * cov / (va * vb);
}

/// Mesures d'un score sur un échantillon : logistique sur le score centré réduit (avec les covariables [cov] du sujet,
/// sans constante, si présentes), AUC, R² de Nagelkerke (incrémental par rapport au modèle des covariables).
PrsMetrics _metrics(List<double> score, List<double> y, [List<List<double>> cov = const []]) {
  final n = score.length;
  final m = score.fold(0.0, (s, x) => s + x) / n;
  var ss = 0.0;
  for (final x in score) {
    ss += (x - m) * (x - m);
  }
  final sd = math.sqrt(ss / (n - 1));
  final z = [for (final x in score) (x - m) / sd];
  final cases = y.where((v) => v == 1).length;
  final pHat = cases / n;
  final ll0 = cases * math.log(pHat) + (n - cases) * math.log(1 - pHat);
  if (cov.isEmpty || cov.first.isEmpty) {
    final fit = fitLogistic([for (final v in z) Float64List.fromList([1, v])], y, keepTrace: false);
    final b = fit.beta[1], se = math.sqrt(fit.cov.get(1, 1));
    final r2 = pseudoR2(fit.logLik, ll0, n).nagelkerke;
    final auc = aucFast(z, y);
    return PrsMetrics(b, se, normalTwoSidedP(b / se), auc, r2, n, cases, aucFull: auc);
  }
  final q = cov.first.length;
  final base = fitLogistic([for (var i = 0; i < n; i++) Float64List.fromList([1, ...cov[i]])], y, keepTrace: false);
  final xf = [for (var i = 0; i < n; i++) Float64List.fromList([1, ...cov[i], z[i]])];
  final full = fitLogistic(xf, y, keepTrace: false);
  final b = full.beta[q + 1], se = math.sqrt(full.cov.get(q + 1, q + 1));
  List<double> lp(List<double> beta, int cols) => [
        for (var i = 0; i < n; i++)
          () {
            var e = beta[0];
            for (var c = 0; c < q; c++) {
              e += beta[c + 1] * cov[i][c];
            }
            if (cols > q + 1) e += beta[q + 1] * z[i];
            return e;
          }()
      ];
  final lpBase = lp(base.beta, q + 1), lpFull = lp(full.beta, q + 2);
  final r2Base = pseudoR2(base.logLik, ll0, n).nagelkerke, r2Full = pseudoR2(full.logLik, ll0, n).nagelkerke;
  return PrsMetrics(b, se, normalTwoSidedP(b / se), aucFast(z, y), r2Full - r2Base, n, cases,
      r2Base: r2Base, aucBase: aucFast(lpBase, y), aucFull: aucFast(lpFull, y), lpBase: lpBase, lpFull: lpFull);
}

/// Covariables d'un sujet en colonnes (indicatrices des modalités autres que la référence, numériques telles quelles),
/// ou null si l'une manque.
List<double>? _covRow(List<LmmCovariate> covariates, List<List<String>> levels, int i) {
  final out = <double>[];
  for (var c = 0; c < covariates.length; c++) {
    final v = covariates[c].values[i];
    if (v == null) return null;
    if (covariates[c].categorical) {
      for (final l in levels[c]) {
        out.add(v == l ? 1 : 0);
      }
    } else {
      final x = double.tryParse(v.replaceAll(',', '.'));
      if (x == null) return null;
      out.add(x);
    }
  }
  return out;
}

/// [outcome] : issue binaire 0/1 alignée sur g.samples (null = manquante).
/// [covariates] : ajustement (découverte et évaluation) ; les sujets dont une covariable manque sont écartés.
PrsFit polygenicRiskScore(GenotypeData g, List<double?> outcome,
    {String outcomeName = '', List<LmmCovariate> covariates = const [], List<double> thresholds = prsThresholds, int windowBp = 250000, double r2Max = 0.1}) {
  // Modalités codées (toutes sauf la référence, ordre alphabétique) pour les covariables qualitatives.
  final levels = [
    for (final c in covariates)
      if (!c.categorical)
        <String>[]
      else
        () {
          final lv = c.values.whereType<String>().toSet().toList()..sort();
          final ref = c.reference != null && lv.contains(c.reference) ? c.reference! : (lv.isEmpty ? '' : lv.first);
          return [for (final l in lv) if (l != ref) l];
        }()
  ];
  final covX = [for (var i = 0; i < g.sampleCount; i++) _covRow(covariates, levels, i)];
  final parts = [<int>[], <int>[], <int>[]];
  for (var i = 0; i < g.sampleCount; i++) {
    final y = outcome[i];
    if (y == null || covX[i] == null) continue;
    if (y != 0 && y != 1) throw StatInputError('prs_binary', tr('Le score polygénique demande une issue binaire (0/1).', 'The polygenic score requires a binary outcome (0/1).'));
    parts[prsPart(i)].add(i);
  }
  for (final (k, name) in [(0, tr('découverte', 'discovery')), (1, tr('validation', 'validation')), (2, tr('test', 'test'))]) {
    final c = parts[k].where((i) => outcome[i] == 1).length;
    if (c < 10 || parts[k].length - c < 10) {
      throw StatInputError('prs_small', tr('Échantillon de $name trop petit : au moins 10 cas et 10 témoins sont requis.', '$name sample too small: at least 10 cases and 10 controls are required.'));
    }
  }
  final disc = g.subset(sampleIdx: parts[0]);
  final yd = [for (final i in parts[0]) outcome[i]!];
  final m = g.variantCount;
  final beta = List<double?>.filled(m, null), pv = List<double?>.filled(m, null);
  final freq = List<double>.filled(m, 0);
  for (var j = 0; j < m; j++) {
    final d = disc.dosage[j];
    final x = <Float64List>[], y = <double>[];
    var s = 0;
    for (var i = 0; i < d.length; i++) {
      if (d[i] < 0) continue;
      x.add(Float64List.fromList([1, d[i].toDouble(), ...covX[parts[0][i]]!]));
      y.add(yd[i]);
      s += d[i];
    }
    if (x.isEmpty) continue;
    freq[j] = s / (2 * x.length);
    if (x.every((r) => r[1] == x.first[1])) continue; // monomorphe en découverte
    final fit = fitLogistic(x, y, keepTrace: false);
    final b = fit.beta[1], se = math.sqrt(fit.cov.get(1, 1));
    beta[j] = b;
    pv[j] = normalTwoSidedP(b / se);
  }
  // Clumping.
  final order = [for (var j = 0; j < m; j++) if (pv[j] != null) j]..sort((a, b) {
      final c = pv[a]!.compareTo(pv[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  final removed = List<bool>.filled(m, false), isIndex = List<bool>.filled(m, false);
  for (final j in order) {
    if (removed[j]) continue;
    isIndex[j] = true;
    final vj = g.variants[j];
    for (final k in order) {
      if (removed[k] || isIndex[k]) continue;
      final vk = g.variants[k];
      if (vk.chrom != vj.chrom || (vk.pos - vj.pos).abs() > windowBp) continue;
      if (_r2(disc.dosage[j], disc.dosage[k]) > r2Max) removed[k] = true;
    }
  }
  final index = [for (var j = 0; j < m; j++) if (isIndex[j]) j];
  List<double> score(List<int> rows, double t) => [
        for (final i in rows)
          () {
            var s = 0.0;
            for (final j in index) {
              if (pv[j]! > t) continue;
              final d = g.dosage[j][i];
              s += beta[j]! * (d < 0 ? 2 * freq[j] : d.toDouble());
            }
            return s;
          }()
      ];
  final yv = [for (final i in parts[1]) outcome[i]!], yt = [for (final i in parts[2]) outcome[i]!];
  final validation = <(double, int, PrsMetrics)>[];
  for (final t in thresholds) {
    final k = index.where((j) => pv[j]! <= t).length;
    if (k == 0) continue;
    validation.add((t, k, _metrics(score(parts[1], t), yv, [for (final i in parts[1]) covX[i]!])));
  }
  if (validation.isEmpty) throw StatInputError('prs_empty', tr('Aucun variant sous les seuils : score impossible.', 'No variant below the thresholds: score impossible.'));
  var best = validation.first;
  for (final v in validation) {
    if (v.$3.r2 > best.$3.r2) best = v;
  }
  final tScore = score(parts[2], best.$1);
  final adjusted = covariates.isNotEmpty;
  final test = _metrics(tScore, yt, [for (final i in parts[2]) covX[i]!]);
  final tAuc = adjusted ? aucDeLong(test.lpFull, yt) : aucDeLong(tScore, yt);
  final delta = adjusted ? compareAucDeLong(test.lpFull, test.lpBase, yt) : null;
  const zq = 1.959963984540054;
  final on = outcomeName.isEmpty ? tr('issue', 'outcome') : outcomeName;
  String f3(double v) => fmt(v, digits: 3);
  String tl(double t) => t >= 0.001 ? fmt(t, digits: 3) : t.toStringAsExponential(0).replaceFirst('e', ' × 10^');
  final optimism = best.$3.r2 - test.r2;
  final covNames = [for (final c in covariates) c.name].join(', ');
  final adjText = adjusted ? tr(' ajusté sur $covNames', ' adjusted for $covNames') : '';
  final result = AnalysisResult(
    methodId: 'polygenic_score',
    methodName: tr('Score de risque polygénique (clumping + seuil de p)$adjText — $on', 'Polygenic risk score (clumping + p threshold)$adjText — $on'),
    inputs: {'samples': [for (final p in parts) p.length], 'variants': m, 'indexVariants': index.length, 'window': windowBp, 'r2': r2Max, 'outcome': on, 'covariates': [for (final c in covariates) c.name]},
    formula: tr(
        'Sujets répartis dans l\'ordre du fichier : découverte (i mod 6 ≤ 3), validation (4), test (5). Découverte : logistique par variant. Clumping : par p croissant, '
            'écarter les variants à ≤ ${windowBp ~/ 1000} kb avec r² > ${fmt(r2Max)}. Score = Σ β·dosage sur les index de p ≤ T. Seuil T choisi en validation (R² de Nagelkerke maximal), '
            'performance rapportée sur le test : OR par ET du score, AUC (IC de DeLong), R² de Nagelkerke.'
            '${adjusted ? ' Ajustement ($covNames) : covariables dans chaque régression de découverte ; évaluation par comparaison du modèle « covariables » au modèle « covariables + score » (R² de Nagelkerke incrémental, AUC des prédicteurs linéaires, différence appariée de DeLong).' : ''}',
        'Subjects split in file order: discovery (i mod 6 ≤ 3), validation (4), test (5). Discovery: logistic regression per variant. Clumping: by increasing p, '
            'remove variants within ${windowBp ~/ 1000} kb with r² > ${fmt(r2Max)}. Score = Σ β·dosage over index variants with p ≤ T. Threshold T chosen in validation (maximal Nagelkerke R²), '
            'performance reported on the test set: OR per SD of the score, AUC (DeLong CI), Nagelkerke R².'
            '${adjusted ? ' Adjustment ($covNames): covariates in each discovery regression; evaluation by comparing the "covariates" model with the "covariates + score" model (incremental Nagelkerke R², AUC of the linear predictors, paired DeLong difference).' : ''}'),
    estimates: [
      Estimate(adjusted ? tr('OR par ET du score, ajusté (test)', 'OR per SD of the score, adjusted (test)') : tr('OR par ET du score (test)', 'OR per SD of the score (test)'), test.orPerSd,
          lower: math.exp(test.beta - zq * test.se), upper: math.exp(test.beta + zq * test.se), pValue: test.p),
      if (!adjusted) Estimate(tr('AUC (test)', 'AUC (test)'), tAuc.auc, lower: tAuc.lower, upper: tAuc.upper, se: tAuc.se),
      if (adjusted) ...[
        Estimate(tr('AUC du modèle covariables + score (test)', 'AUC of the covariates + score model (test)'), tAuc.auc, lower: tAuc.lower, upper: tAuc.upper, se: tAuc.se),
        Estimate(tr('Gain d\'AUC apporté par le score (test)', 'AUC gain brought by the score (test)'), delta!.diff, lower: delta.lower, upper: delta.upper, se: delta.se, pValue: delta.p),
      ],
      Estimate(adjusted ? tr('R² de Nagelkerke incrémental (test)', 'Incremental Nagelkerke R² (test)') : tr('R² de Nagelkerke (test)', 'Nagelkerke R² (test)'), test.r2),
    ],
    statistics: {
      'best_threshold': best.$1,
      'variants_in_score': best.$2.toDouble(),
      'index_variants': index.length.toDouble(),
      'validation_r2': best.$3.r2,
      'validation_auc': best.$3.auc,
      'test_r2': test.r2,
      'test_auc': tAuc.auc,
      'test_auc_lower': tAuc.lower,
      'test_auc_upper': tAuc.upper,
      'test_or_per_sd': test.orPerSd,
      'test_p': test.p,
      if (adjusted) ...{
        'test_auc_base': test.aucBase,
        'test_auc_score': test.auc,
        'test_r2_base': test.r2Base,
        'delta_auc': delta!.diff,
        'delta_auc_lower': delta.lower,
        'delta_auc_upper': delta.upper,
        'delta_auc_p': delta.p,
      },
      'optimism_r2': optimism,
      'n_discovery': parts[0].length.toDouble(),
      'n_validation': parts[1].length.toDouble(),
      'n_test': parts[2].length.toDouble(),
    },
    checks: [
      Check('independent_test', tr('Performance rapportée sur un échantillon non utilisé', 'Performance reported on an unused sample'), CheckStatus.ok,
          tr('Effets estimés en découverte, seuil choisi en validation, performance mesurée sur le test.', 'Effects estimated in discovery, threshold chosen in validation, performance measured on the test set.')),
      Check('optimism', tr('Optimisme du choix du seuil limité (R² validation − test ≤ 0,05)', 'Limited optimism of threshold choice (R² validation − test ≤ 0.05)'),
          optimism <= 0.05 ? CheckStatus.ok : CheckStatus.warning,
          tr('R² ${f3(best.$3.r2)} en validation contre ${f3(test.r2)} en test : le seuil retenu sur la validation surestime la performance ; seule celle du test est à rapporter.',
              'R² ${f3(best.$3.r2)} in validation versus ${f3(test.r2)} in test: the threshold chosen on validation overstates performance; only the test performance should be reported.')),
      Check('ancestry', tr('Même ascendance en découverte et en application', 'Same ancestry in discovery and application'), CheckStatus.notAssessed,
          tr('Un score construit dans une population perd beaucoup de performance dans une autre (DL et fréquences différents).',
              'A score built in one population loses much of its performance in another (different LD and frequencies).')),
    ],
    tables: [
      ResultTable(tr('Choix du seuil (échantillon de validation)', 'Threshold choice (validation sample)'),
          [
            tr('Seuil p', 'p threshold'), tr('Variants', 'Variants'), tr('OR par ET', 'OR per SD'), 'p', adjusted ? tr('AUC du score', 'Score AUC') : 'AUC',
            if (adjusted) tr('AUC complet', 'Full AUC'),
            adjusted ? tr('R² incrémental', 'Incremental R²') : tr('R² de Nagelkerke', 'Nagelkerke R²'),
          ], [
        for (final (t, k, v) in validation)
          [
            '${tl(t)}${t == best.$1 ? ' *' : ''}', '$k', f3(v.orPerSd), v.p < 1e-3 ? v.p.toStringAsExponential(2) : f3(v.p), f3(v.auc),
            if (adjusted) f3(v.aucFull),
            f3(v.r2),
          ]
      ]),
      if (adjusted)
        ResultTable(tr('Apport du score aux covariables (test)', 'Contribution of the score beyond the covariates (test)'),
            [tr('Modèle', 'Model'), 'AUC', tr('R² de Nagelkerke', 'Nagelkerke R²')], [
          [tr('Covariables ($covNames)', 'Covariates ($covNames)'), f3(test.aucBase), f3(test.r2Base)],
          [tr('Covariables + score', 'Covariates + score'), f3(tAuc.auc), f3(test.r2Base + test.r2)],
          [tr('Différence', 'Difference'), tr('${f3(delta!.diff)} (${f3(delta.lower)} à ${f3(delta.upper)})', '${f3(delta.diff)} (${f3(delta.lower)} to ${f3(delta.upper)})'), f3(test.r2)],
        ]),
    ],
    figures: {
      'prs': {
        'thresholds': [for (final v in validation) v.$1],
        'r2': [for (final v in validation) v.$3.r2],
        'best': best.$1,
        'testR2': test.r2,
      },
    },
    log: [
      tr('${parts[0].length} sujets en découverte, ${parts[1].length} en validation, ${parts[2].length} en test ; ${index.length} variants index après clumping ; seuil retenu ${tl(best.$1)} (${best.$2} variants).',
          '${parts[0].length} subjects in discovery, ${parts[1].length} in validation, ${parts[2].length} in test; ${index.length} index variants after clumping; chosen threshold ${tl(best.$1)} (${best.$2} variants).'),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Chaque variant n\'a qu\'un effet minime ; un score qui les additionne, pondérés par leurs effets, résume la prédisposition génétique. Les effets, le seuil et la performance doivent venir d\'échantillons distincts, sans quoi la performance est surestimée.',
          'Each variant has only a tiny effect; a score that adds them up, weighted by their effects, summarizes the genetic predisposition. Effects, threshold and performance must come from distinct samples, otherwise performance is overstated.'),
      whatItMeans: tr(
          'Sur l\'échantillon de test, chaque ET du score multiplie l\'odds de $on par ${f3(test.orPerSd)} (IC 95 % ${f3(math.exp(test.beta - zq * test.se))} à ${f3(math.exp(test.beta + zq * test.se))}) ; AUC ${f3(tAuc.auc)} (${f3(tAuc.lower)} à ${f3(tAuc.upper)}).',
          'On the test sample, each SD of the score multiplies the odds of $on by ${f3(test.orPerSd)} (95% CI ${f3(math.exp(test.beta - zq * test.se))} to ${f3(math.exp(test.beta + zq * test.se))}); AUC ${f3(tAuc.auc)} (${f3(tAuc.lower)} to ${f3(tAuc.upper)}).')
          + (adjusted
              ? tr(' Au-delà des covariables ($covNames), le score fait passer l\'AUC de ${f3(test.aucBase)} à ${f3(tAuc.auc)} (gain ${f3(delta!.diff)}, ${fmtP(delta.p)}).',
                  ' Beyond the covariates ($covNames), the score raises the AUC from ${f3(test.aucBase)} to ${f3(tAuc.auc)} (gain ${f3(delta.diff)}, ${fmtP(delta.p)}).')
              : ''),
      notJustified: tr(
          'Rapporter la performance de la validation (seuil choisi dessus) ; utiliser le score comme test diagnostique individuel (AUC modeste) ; l\'appliquer à une autre ascendance sans revalidation.',
          'Reporting the validation performance (threshold chosen on it); using the score as an individual diagnostic test (modest AUC); applying it to another ancestry without revalidation.'),
    ),
  );
  return PrsFit(beta, pv, index, validation, best.$1, test, tAuc, result, deltaAuc: delta);
}
