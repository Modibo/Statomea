/// Équations d'estimation généralisées (GEE, Liang et Zeger 1986) pour mesures répétées ou données en grappes :
/// familles gaussienne (identité), binomiale (logit), Poisson (log) ; corrélation de travail indépendante ou
/// échangeable ; variance robuste (sandwich). Deux conventions d'estimation des paramètres de nuisance :
///  - geepack (défaut) : φ = Σr²/N, α = Σᵢ Σⱼ<ₖ rᵢⱼrᵢₖ / [φ·Σᵢ nᵢ(nᵢ − 1)/2] ;
///  - gee (Liang-Zeger, petits échantillons) : φ = Σr²/(N − p), α = … / [φ·(Σᵢ nᵢ(nᵢ − 1)/2 − p)].
/// Validé contre validation/r/44_gee.R (geepack 1.3.9, gee 4.13).
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

enum GeeFamily { gaussian, binomial, poisson }

enum GeeCorrelation { independence, exchangeable }

class GeeFit {
  final List<double> beta, se;
  final Matrix robustCov;
  final double alpha, phi;
  final int iterations;
  final bool converged;
  const GeeFit(this.beta, this.se, this.robustCov, this.alpha, this.phi, this.iterations, this.converged);
}

double _mu(GeeFamily f, double eta) => switch (f) {
      GeeFamily.gaussian => eta,
      GeeFamily.binomial => 1 / (1 + math.exp(-eta)),
      GeeFamily.poisson => math.exp(eta),
    };
double _var(GeeFamily f, double mu) => switch (f) {
      GeeFamily.gaussian => 1,
      GeeFamily.binomial => mu * (1 - mu),
      GeeFamily.poisson => mu,
    };
double _dmu(GeeFamily f, double mu) => switch (f) {
      GeeFamily.gaussian => 1,
      GeeFamily.binomial => mu * (1 - mu),
      GeeFamily.poisson => mu,
    };

/// Matrice de corrélation de travail échangeable (ou identité) de taille n, inversée.
Matrix _rInv(int n, double alpha) {
  // (1 − α)I + αJ : inverse = [I − α/(1 + (n − 1)α)·J]/(1 − α).
  final m = Matrix(n, n);
  final c = alpha / (1 + (n - 1) * alpha);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      m.set(i, j, ((i == j ? 1 : 0) - c) / (1 - alpha));
    }
  }
  return m;
}

/// Ajustement : [group] = sujet de chaque ligne (0 … m − 1).
GeeFit fitGee(List<List<double>> x, List<double> y, List<int> group, {GeeFamily family = GeeFamily.gaussian, GeeCorrelation corr = GeeCorrelation.exchangeable, bool smallSample = false, int maxIter = 100}) {
  final n = y.length, p = x.first.length;
  final m = group.reduce(math.max) + 1;
  final rowsOf = [for (var g = 0; g < m; g++) <int>[]];
  for (var i = 0; i < n; i++) {
    rowsOf[group[i]].add(i);
  }
  final ybar = y.reduce((a, b) => a + b) / n;
  var beta = List<double>.filled(p, 0);
  beta[0] = switch (family) {
    GeeFamily.gaussian => ybar,
    GeeFamily.binomial => math.log(ybar / (1 - ybar)),
    GeeFamily.poisson => math.log(ybar),
  };
  var alpha = 0.0, phi = 1.0;
  var converged = false, it = 0;
  List<double> etaOf(List<double> b) => [
        for (final r in x)
          () {
            var s = 0.0;
            for (var j = 0; j < p; j++) {
              s += r[j] * b[j];
            }
            return s;
          }()
      ];
  // Une itération : φ et α aux β courants, puis pas de scores de Fisher. Démarrage : β de l'indépendance (GLM).
  ({Matrix a, List<double> u, List<double> mu, List<double> eta}) scores(List<double> b, double al, double ph) {
    final eta = etaOf(b);
    final mu = [for (final e in eta) _mu(family, e)];
    final a = Matrix(p, p);
    final u = List<double>.filled(p, 0);
    for (final rows in rowsOf) {
      final k = rows.length;
      final ri = _rInv(k, al);
      final s = [for (final i in rows) math.sqrt(_var(family, mu[i]))];
      // D = diag(dμ/dη)·X ; V⁻¹ = A^{-½} R⁻¹ A^{-½} / φ.
      final w = [for (var r = 0; r < k; r++) _dmu(family, mu[rows[r]]) / s[r]]; // (A^{-½}D) ligne par ligne
      for (var r = 0; r < k; r++) {
        for (var c = 0; c < k; c++) {
          final v = ri.get(r, c) / ph;
          if (v == 0) continue;
          final er = (y[rows[c]] - mu[rows[c]]) / s[c];
          for (var j = 0; j < p; j++) {
            final dj = w[r] * x[rows[r]][j];
            u[j] += dj * v * er;
            for (var l = 0; l < p; l++) {
              a.data[j * p + l] += dj * v * w[c] * x[rows[c]][l];
            }
          }
        }
      }
    }
    return (a: a, u: u, mu: mu, eta: eta);
  }

  void nuisance(List<double> mu) {
    final r = [for (var i = 0; i < n; i++) (y[i] - mu[i]) / math.sqrt(_var(family, mu[i]))];
    phi = r.fold(0.0, (s, v) => s + v * v) / (n - (smallSample ? p : 0));
    if (corr == GeeCorrelation.independence) {
      alpha = 0;
      return;
    }
    var num = 0.0, pairs = 0.0;
    for (final rows in rowsOf) {
      var s = 0.0, s2 = 0.0;
      for (final i in rows) {
        s += r[i];
        s2 += r[i] * r[i];
      }
      num += (s * s - s2) / 2;
      pairs += rows.length * (rows.length - 1) / 2;
    }
    alpha = num / (phi * (pairs - (smallSample ? p : 0)));
  }

  // Départ : GLM (indépendance), puis GEE.
  for (var k = 0; k < 50; k++) {
    final sc = scores(beta, 0, 1);
    final step = solveSpd(sc.a, sc.u);
    if (step == null) break;
    beta = [for (var j = 0; j < p; j++) beta[j] + step[j]];
    if (step.every((v) => v.abs() < 1e-12)) break;
  }
  for (it = 1; it <= maxIter; it++) {
    final eta = etaOf(beta);
    nuisance([for (final e in eta) _mu(family, e)]);
    final sc = scores(beta, alpha, phi);
    final step = solveSpd(sc.a, sc.u);
    if (step == null) break;
    beta = [for (var j = 0; j < p; j++) beta[j] + step[j]];
    if (step.every((v) => v.abs() < 1e-12)) {
      converged = true;
      break;
    }
  }
  // Variance robuste A⁻¹BA⁻¹ aux estimations finales (φ, α recalculés aux β finaux comme les deux paquets).
  final eta = etaOf(beta);
  final mu = [for (final e in eta) _mu(family, e)];
  final sc = scores(beta, alpha, phi);
  final b = Matrix(p, p);
  for (final rows in rowsOf) {
    final k = rows.length;
    final ri = _rInv(k, alpha);
    final s = [for (final i in rows) math.sqrt(_var(family, mu[i]))];
    final w = [for (var r = 0; r < k; r++) _dmu(family, mu[rows[r]]) / s[r]];
    final ui = List<double>.filled(p, 0);
    for (var r = 0; r < k; r++) {
      for (var c = 0; c < k; c++) {
        final v = ri.get(r, c) / phi;
        final er = (y[rows[c]] - mu[rows[c]]) / s[c];
        for (var j = 0; j < p; j++) {
          ui[j] += w[r] * x[rows[r]][j] * v * er;
        }
      }
    }
    for (var j = 0; j < p; j++) {
      for (var l = 0; l < p; l++) {
        b.data[j * p + l] += ui[j] * ui[l];
      }
    }
  }
  final aInv = invertSpd(sc.a) ?? Matrix(p, p);
  final cov = aInv * b * aInv;
  return GeeFit(beta, [for (var j = 0; j < p; j++) math.sqrt(cov.get(j, j))], cov, alpha, phi, it, converged);
}

/// Analyse GEE d'un jeu de données en format long ; [subject] identifie la grappe (sujet).
AnalysisResult geeRegression(Dataset ds, ModelFormula f, {required String subject, GeeFamily family = GeeFamily.gaussian, GeeCorrelation corr = GeeCorrelation.exchangeable, bool smallSample = false, double level = 0.95}) {
  final d0 = buildDesign(ds, f, binaryOutcome: family == GeeFamily.binomial);
  final subj = ds.text(subject);
  final keep = [for (var k = 0; k < d0.n; k++) if (subj[d0.rows[k]] != null) k];
  final ids = <String, int>{};
  final group = [for (final k in keep) ids.putIfAbsent(subj[d0.rows[k]]!, () => ids.length)];
  if (ids.length < 3) throw StatInputError('few_subjects', tr('Au moins 3 sujets (grappes) sont nécessaires.', 'At least 3 subjects (clusters) are required.'));
  final y = [for (final k in keep) d0.y[k]];
  if (family == GeeFamily.poisson && y.any((v) => v < 0 || v != v.roundToDouble())) {
    throw StatInputError('not_counts', tr('L\'issue de Poisson doit être un comptage (entier ≥ 0).', 'The Poisson outcome must be a count (integer ≥ 0).'));
  }
  final x = [for (final k in keep) d0.x[k]];
  final fit = fitGee(x, y, group, family: family, corr: corr, smallSample: smallSample);
  final p = x.first.length, m = ids.length, n = y.length;
  final z = normalQuantile(1 - (1 - level) / 2);
  final coefs = [
    for (var j = 0; j < p; j++) Coefficient(d0.columns[j], fit.beta[j], fit.se[j], fit.beta[j] / fit.se[j], normalTwoSidedP(fit.beta[j] / fit.se[j]), fit.beta[j] - z * fit.se[j], fit.beta[j] + z * fit.se[j])
  ];
  final expo = family != GeeFamily.gaussian;
  final effect = switch (family) { GeeFamily.binomial => 'OR', GeeFamily.poisson => tr('RR (rapport de taux)', 'RR (rate ratio)'), _ => tr('Différence', 'Difference') };
  final famName = switch (family) {
    GeeFamily.gaussian => tr('gaussienne (identité)', 'Gaussian (identity)'),
    GeeFamily.binomial => tr('binomiale (logit)', 'binomial (logit)'),
    GeeFamily.poisson => tr('Poisson (log)', 'Poisson (log)'),
  };
  final corrName = corr == GeeCorrelation.exchangeable ? tr('échangeable', 'exchangeable') : tr('indépendance', 'independence');
  final pct = (level * 100).round();
  final sizes = [for (var g = 0; g < m; g++) group.where((v) => v == g).length]..sort();
  final main = coefs.length > 1 ? coefs[1] : coefs.first;
  String eff(Coefficient c) => expo ? '${fmt(math.exp(c.estimate))} (${fmt(math.exp(c.lower))} – ${fmt(math.exp(c.upper))})' : '${fmt(c.estimate)} (${fmt(c.lower)} – ${fmt(c.upper)})';
  return AnalysisResult(
    methodId: 'gee',
    methodName: tr('GEE pour mesures répétées : famille $famName, corrélation $corrName', 'GEE for repeated measures: $famName family, $corrName correlation'),
    inputs: {'model': d0.describe(), 'subject': subject, 'family': family.name, 'correlation': corr.name, 'smallSample': smallSample, 'level': level},
    formula: tr(
        'g(E[yᵢⱼ]) = xᵢⱼᵀβ ; Σᵢ DᵢᵀVᵢ⁻¹(yᵢ − μᵢ) = 0, Vᵢ = φ·A½R(α)A½, corrélation de travail $corrName ; résidus de Pearson ; ${smallSample ? 'φ = Σr²/(N − p), α avec correction − p (gee, Liang-Zeger)' : 'φ = Σr²/N, α sans correction (geepack)'} ; variance robuste (sandwich) A⁻¹BA⁻¹ ; IC et Wald par la loi normale.',
        'g(E[yᵢⱼ]) = xᵢⱼᵀβ; Σᵢ DᵢᵀVᵢ⁻¹(yᵢ − μᵢ) = 0, Vᵢ = φ·A½R(α)A½, $corrName working correlation; Pearson residuals; ${smallSample ? 'φ = Σr²/(N − p), α with − p correction (gee, Liang-Zeger)' : 'φ = Σr²/N, α without correction (geepack)'}; robust (sandwich) variance A⁻¹BA⁻¹; normal CIs and Wald tests.'),
    estimates: [
      for (final c in coefs.skip(1))
        expo
            ? Estimate('$effect — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), pValue: c.p, se: c.se, level: level)
            : Estimate(c.name, c.estimate, lower: c.lower, upper: c.upper, pValue: c.p, se: c.se, level: level),
      if (corr == GeeCorrelation.exchangeable) Estimate(tr('Corrélation de travail α', 'Working correlation α'), fit.alpha),
    ],
    statistics: {
      'n': n.toDouble(), 'subjects': m.toDouble(), 'alpha': fit.alpha, 'phi': fit.phi, 'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < p; j++) 'beta_${d0.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d0.columns[j]}': fit.se[j],
      for (var j = 0; j < p; j++) 'p_${d0.columns[j]}': coefs[j].p,
    },
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), fit.converged ? CheckStatus.ok : CheckStatus.violated, tr('${fit.iterations} itération(s).', '${fit.iterations} iteration(s).')),
      Check('clusters', tr('Assez de sujets pour la variance robuste (≥ 40 conseillé)', 'Enough subjects for the robust variance (≥ 40 advised)'), m >= 40 ? CheckStatus.ok : CheckStatus.warning,
          tr('$m sujets, $n mesures (${sizes.first} à ${sizes.last} par sujet).${m < 40 ? ' Avec peu de grappes, la variance robuste sous-estime l\'incertitude ; préférer la convention « petits échantillons » ou un modèle mixte.' : ''}',
              '$m subjects, $n measurements (${sizes.first} to ${sizes.last} per subject).${m < 40 ? ' With few clusters, the robust variance underestimates uncertainty; prefer the small-sample convention or a mixed model.' : ''}')),
      Check('missing_mcar', tr('Données manquantes complètement aléatoires (MCAR)', 'Missing completely at random (MCAR)'), CheckStatus.notAssessed,
          tr('Les GEE ne restent sans biais que si les sorties d\'étude ne dépendent pas des valeurs observées (MCAR) ; sous MAR, préférer le modèle mixte ou des GEE pondérées.',
              'GEE remain unbiased only if dropout does not depend on observed values (MCAR); under MAR, prefer the mixed model or weighted GEE.')),
    ],
    alerts: [...d0.alerts],
    tables: [
      ResultTable(tr('Coefficients (variance robuste)', 'Coefficients (robust variance)'), [tr('Terme', 'Term'), tr('Estimation', 'Estimate'), tr('ES robuste', 'Robust SE'), 'z', 'p', expo ? '$effect (IC $pct %)' : tr('IC $pct %', '$pct% CI')], [
        for (final c in coefs) [c.name, fmt(c.estimate), fmt(c.se), fmt(c.statistic), fmtP(c.p), expo ? eff(c) : '${fmt(c.lower)} – ${fmt(c.upper)}']
      ]),
      ResultTable(tr('Paramètres de nuisance', 'Nuisance parameters'), [tr('Paramètre', 'Parameter'), tr('Valeur', 'Value')], [
        [tr('Corrélation de travail', 'Working correlation'), '$corrName${corr == GeeCorrelation.exchangeable ? ', α = ${fmt(fit.alpha, digits: 3)}' : ''}'],
        [tr('Échelle φ', 'Scale φ'), fmt(fit.phi, digits: 4)],
        [tr('Mesures / sujets', 'Measurements / subjects'), '$n / $m'],
        for (final c in d0.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Mesures répétées ou en grappes : les GEE estiment un effet moyen dans la population (marginal) et corrigent les erreurs types pour la corrélation intra-sujet par la variance robuste, qui reste valide même si la corrélation de travail est mal choisie.',
          'Repeated or clustered measurements: GEE estimate a population-average (marginal) effect and correct the standard errors for within-subject correlation through the robust variance, which remains valid even if the working correlation is misspecified.'),
      whatItMeans: tr('« ${main.name} » : ${expo ? '$effect = ' : ''}${eff(main)}, ${fmtP(main.p)} (effet moyen dans la population). ${corr == GeeCorrelation.exchangeable ? 'Corrélation intra-sujet de travail α = ${fmt(fit.alpha, digits: 2)}.' : ''}',
          '"${main.name}": ${expo ? '$effect = ' : ''}${eff(main)}, ${fmtP(main.p)} (population-average effect). ${corr == GeeCorrelation.exchangeable ? 'Working within-subject correlation α = ${fmt(fit.alpha, digits: 2)}.' : ''}'),
      notJustified: tr(
          'Lire un OR de GEE comme un effet propre à un individu (il est marginal, plus proche de 1 que l\'OR conditionnel d\'un modèle mixte logistique) ; utiliser les GEE avec peu de sujets ; ignorer des sorties d\'étude liées à l\'évolution (non MCAR).',
          'Reading a GEE OR as an individual-specific effect (it is marginal, closer to 1 than the conditional OR of a logistic mixed model); using GEE with few subjects; ignoring dropout related to the evolution (not MCAR).'),
    ),
  );
}
