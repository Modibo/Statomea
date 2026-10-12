/// Imputation multiple par équations chaînées (MICE ; van Buuren 2018),
/// méthodes par défaut de `mice` :
///  - variable quantitative : appariement sur la moyenne prédite (PMM,
///    appariement de type 1, 5 donneurs ; tirage bayésien des coefficients) ;
///  - variable binaire : régression logistique bayésienne (« logreg ») ;
///  - qualitative à plus de 2 modalités : non imputée en V1 (erreur
///    explicite) — elle peut servir de prédicteur si elle est complète.
/// Les données importées ne sont jamais modifiées : chaque jeu complété est
/// un nouveau [Dataset] dont la source mentionne l'imputation.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/matrix.dart';
import '../math/random.dart';
import '../model/result.dart';
import '../regression/glm.dart';
import 'dataset.dart';

class MiceOptions {
  final int m;
  final int maxit;
  final int seed;
  final int donors;

  /// Variables exclues du modèle d'imputation (identifiants, texte libre).
  final Set<String> exclude;
  const MiceOptions({this.m = 20, this.maxit = 10, this.seed = 20261012, this.donors = 5, this.exclude = const {}});
  Map<String, Object?> toJson() => {'m': m, 'maxit': maxit, 'seed': seed, 'donors': donors, 'exclude': exclude.toList()};
}

/// Générateur de lois pour l'imputation (normale, χ²) à partir de SeededRandom.
class _Rng {
  final SeededRandom r;
  double? _spare;
  _Rng(int seed) : r = SeededRandom(seed);
  double unif() => (r.nextUint32() + 0.5) / 4294967296.0;
  double normal() {
    if (_spare != null) {
      final s = _spare!;
      _spare = null;
      return s;
    }
    final u1 = unif(), u2 = unif();
    final rad = math.sqrt(-2 * math.log(u1));
    _spare = rad * math.sin(2 * math.pi * u2);
    return rad * math.cos(2 * math.pi * u2);
  }

  /// Gamma(shape, 1) (Marsaglia & Tsang 2000).
  double gamma(double shape) {
    if (shape < 1) return gamma(shape + 1) * math.pow(unif(), 1 / shape);
    final d = shape - 1 / 3, c = 1 / math.sqrt(9 * d);
    while (true) {
      double x, v;
      do {
        x = normal();
        v = 1 + c * x;
      } while (v <= 0);
      v = v * v * v;
      final u = unif();
      if (u < 1 - 0.0331 * x * x * x * x || math.log(u) < 0.5 * x * x + d * (1 - v + math.log(v))) return d * v;
    }
  }

  double chiSquare(double df) => 2 * gamma(df / 2);
  int index(int n) => r.nextInt(n);
}

class ImputationDiagnostic {
  final String variable;
  final String method;
  final int missing;
  final double observedMean;
  final List<double> imputedMeans; // une moyenne par imputation
  final List<List<double>> chainMeans; // [imputation][itération]
  ImputationDiagnostic(this.variable, this.method, this.missing, this.observedMean, this.imputedMeans, this.chainMeans);
}

class ImputationResult {
  final List<Dataset> completed;
  final List<ImputationDiagnostic> diagnostics;
  final MiceOptions options;
  final List<String> predictors;
  ImputationResult(this.completed, this.diagnostics, this.options, this.predictors);
}

/// Colonnes numériques codant une variable comme prédicteur d'imputation.
List<List<double>> _encode(String name, VarType type, List<String?> cur, List<String> levels) {
  if (type == VarType.numeric) return [[for (final v in cur) parseNumber(v)!]];
  // Qualitative : indicatrices (première modalité = référence).
  return [for (final l in levels.skip(1)) [for (final v in cur) v == l ? 1.0 : 0.0]];
}

/// Imputation multiple d'un jeu de données.
ImputationResult multipleImputation(Dataset ds, MiceOptions o) {
  final vars = [
    for (final n in ds.names)
      if (!o.exclude.contains(n) && ds.dictionary[n]!.type != VarType.identifier && ds.dictionary[n]!.type != VarType.text && ds.dictionary[n]!.type != VarType.date) n
  ];
  final rows = [for (var i = 0; i < ds.rowCount; i++) if (!ds.excludedRows.contains(i)) i];
  final n = rows.length;
  final types = {for (final v in vars) v: ds.dictionary[v]!.type};
  final levels = {for (final v in vars) v: ds.levels(v)};
  final orig = {for (final v in vars) v: [for (final i in rows) types[v] == VarType.numeric ? (parseNumber(ds.cell(i, v)) == null ? null : ds.cell(i, v)!.trim()) : ds.text(v)[i]]};
  final incomplete = [for (final v in vars) if (orig[v]!.contains(null)) v];
  for (final v in incomplete) {
    final t = types[v]!;
    if (t != VarType.numeric && levels[v]!.length != 2) {
      throw StatInputError('mi_unsupported',
          tr("« $v » (qualitative à ${levels[v]!.length} modalités) a des valeurs manquantes : son imputation (régression polytomique) n'est pas disponible en V1. Regrouper les modalités sur des bases cliniques ou l'exclure.",
              '"$v" (categorical with ${levels[v]!.length} levels) has missing values: its imputation (polytomous regression) is not available in V1. Merge levels on clinical grounds or exclude it.'));
    }
    if (orig[v]!.where((x) => x != null).length < 10) {
      throw StatInputError('mi_too_few', tr('« $v » a moins de 10 valeurs observées : imputation impossible.', '"$v" has fewer than 10 observed values: imputation impossible.'));
    }
  }
  if (incomplete.isEmpty) throw StatInputError('mi_nothing', tr("Aucune valeur manquante dans les variables retenues : l'imputation est inutile.", 'No missing value in the selected variables: imputation is unnecessary.'));
  final rng = _Rng(o.seed);
  final completed = <Dataset>[];
  final chains = {for (final v in incomplete) v: <List<double>>[]};
  final impMeans = {for (final v in incomplete) v: <double>[]};
  String fmtNum(double x) => x == x.roundToDouble() && x.abs() < 1e15 ? x.toInt().toString() : x.toString();
  for (var imp = 0; imp < o.m; imp++) {
    final cur = {for (final v in vars) v: List<String?>.of(orig[v]!)};
    // Initialisation : tirage aléatoire parmi les valeurs observées (comme mice).
    for (final v in incomplete) {
      final obs = [for (final x in orig[v]!) ?x];
      for (var i = 0; i < n; i++) {
        if (cur[v]![i] == null) cur[v]![i] = obs[rng.index(obs.length)];
      }
    }
    final chain = {for (final v in incomplete) v: <double>[]};
    for (var it = 0; it < o.maxit; it++) {
      for (final v in incomplete) {
        final ry = [for (final x in orig[v]!) x != null];
        // Prédicteurs : toutes les autres variables (valeurs courantes).
        final cols = <List<double>>[];
        for (final w in vars) {
          if (w == v) continue;
          cols.addAll(_encode(w, types[w]!, cur[w]!, levels[w]!));
        }
        final x = [for (var i = 0; i < n; i++) [1.0, for (final c in cols) c[i]]];
        final obsIdx = [for (var i = 0; i < n; i++) if (ry[i]) i];
        final misIdx = [for (var i = 0; i < n; i++) if (!ry[i]) i];
        if (types[v] == VarType.numeric) {
          final y = [for (final i in obsIdx) parseNumber(orig[v]![i])!];
          final imputed = _pmm([for (final i in obsIdx) x[i]], y, [for (final i in misIdx) x[i]], o.donors, rng);
          for (var k = 0; k < misIdx.length; k++) {
            cur[v]![misIdx[k]] = fmtNum(imputed[k]);
          }
        } else {
          final ev = levels[v]!.last;
          final y = [for (final i in obsIdx) orig[v]![i] == ev ? 1.0 : 0.0];
          final draws = _logreg([for (final i in obsIdx) x[i]], y, [for (final i in misIdx) x[i]], rng);
          for (var k = 0; k < misIdx.length; k++) {
            cur[v]![misIdx[k]] = draws[k] ? ev : levels[v]!.first;
          }
        }
        chain[v]!.add(_meanImputed(cur[v]!, ry, types[v]!, levels[v]!));
      }
    }
    for (final v in incomplete) {
      chains[v]!.add(chain[v]!);
      impMeans[v]!.add(chain[v]!.last);
    }
    // Jeu complété : cellules d'origine + valeurs imputées pour les variables imputées.
    final data = <List<String?>>[];
    for (var k = 0; k < n; k++) {
      final i = rows[k];
      data.add([for (final name in ds.names) incomplete.contains(name) ? cur[name]![k] : ds.cell(i, name)]);
    }
    final dict = {for (final e in ds.dictionary.entries) e.key: Variable.fromJson(e.value.toJson())};
    completed.add(Dataset(ds.names, data, source: tr('${ds.source} — imputation ${imp + 1}/${o.m} (MICE, graine ${o.seed})', '${ds.source} — imputation ${imp + 1}/${o.m} (MICE, seed ${o.seed})'), dictionary: dict));
  }
  final diags = [
    for (final v in incomplete)
      ImputationDiagnostic(
        v,
        types[v] == VarType.numeric ? tr('PMM (5 donneurs)', 'PMM (5 donors)') : tr('régression logistique bayésienne', 'Bayesian logistic regression'),
        orig[v]!.where((x) => x == null).length,
        _meanObserved(orig[v]!, types[v]!, levels[v]!),
        impMeans[v]!,
        chains[v]!,
      )
  ];
  return ImputationResult(completed, diags, o, vars);
}

double _meanObserved(List<String?> col, VarType t, List<String> lv) {
  final xs = [for (final c in col) if (c != null) (t == VarType.numeric ? parseNumber(c)! : (c == lv.last ? 1.0 : 0.0))];
  return xs.fold(0.0, (a, b) => a + b) / xs.length;
}

double _meanImputed(List<String?> col, List<bool> ry, VarType t, List<String> lv) {
  final xs = <double>[];
  for (var i = 0; i < col.length; i++) {
    if (!ry[i]) xs.add(t == VarType.numeric ? parseNumber(col[i])! : (col[i] == lv.last ? 1.0 : 0.0));
  }
  return xs.fold(0.0, (a, b) => a + b) / xs.length;
}

/// PMM de type 1 (comme mice.impute.pmm) : β̂ pour les observés, β* tiré pour les manquants.
List<double> _pmm(List<List<double>> xObs, List<double> yObs, List<List<double>> xMis, int donors, _Rng rng) {
  final p = xObs.first.length;
  final xtx = crossprodWeighted(xObs, List<double>.filled(xObs.length, 1));
  var v = invertSpd(xtx);
  if (v == null) {
    // Quasi-colinéarité : pénalité ridge (comme mice).
    for (var j = 0; j < p; j++) {
      xtx.set(j, j, xtx.get(j, j) * (1 + 1e-5));
    }
    v = invertSpd(xtx)!;
  }
  final xty = List<double>.filled(p, 0);
  for (var i = 0; i < xObs.length; i++) {
    for (var j = 0; j < p; j++) {
      xty[j] += xObs[i][j] * yObs[i];
    }
  }
  final coef = v.multiplyVector(xty);
  var rss = 0.0;
  final yhatObs = <double>[];
  for (var i = 0; i < xObs.length; i++) {
    var f = 0.0;
    for (var j = 0; j < p; j++) {
      f += xObs[i][j] * coef[j];
    }
    yhatObs.add(f);
    rss += (yObs[i] - f) * (yObs[i] - f);
  }
  final df = math.max(xObs.length - p, 1).toDouble();
  final sigmaStar = math.sqrt(rss / rng.chiSquare(df));
  final l = cholesky(v)!;
  final z = [for (var j = 0; j < p; j++) rng.normal()];
  final betaStar = [
    for (var a = 0; a < p; a++)
      () {
        var s = 0.0;
        for (var b = 0; b <= a; b++) {
          s += l.get(a, b) * z[b];
        }
        return coef[a] + s * sigmaStar;
      }()
  ];
  // Observés triés une fois par valeur prédite ; pour chaque manquant, les k
  // plus proches sont trouvés par recherche dichotomique puis fenêtre.
  final order = List<int>.generate(yhatObs.length, (i) => i)..sort((a, b) => yhatObs[a].compareTo(yhatObs[b]));
  final sorted = [for (final i in order) yhatObs[i]];
  final out = <double>[];
  for (final row in xMis) {
    var t = 0.0;
    for (var j = 0; j < p; j++) {
      t += row[j] * betaStar[j];
    }
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final k = math.min(donors, sorted.length);
    var left = lo - 1, right = lo;
    final picked = <int>[];
    while (picked.length < k) {
      final dl = left >= 0 ? (t - sorted[left]).abs() : double.infinity;
      final dr = right < sorted.length ? (sorted[right] - t).abs() : double.infinity;
      // Ex aequo de distance départagés au hasard.
      if (dl < dr || (dl == dr && rng.unif() < 0.5)) {
        picked.add(order[left--]);
      } else {
        picked.add(order[right++]);
      }
    }
    out.add(yObs[picked[rng.index(k)]]);
  }
  return out;
}

/// Régression logistique bayésienne (comme mice.impute.logreg) : β* ~ N(β̂, V̂).
List<bool> _logreg(List<List<double>> xObs, List<double> yObs, List<List<double>> xMis, _Rng rng) {
  var fit = fitLogistic(xObs, yObs);
  if (!fit.converged || fit.beta.skip(1).any((b) => b.abs() > 15)) {
    fit = fitFirth(xObs, yObs); // séparation : estimations pénalisées finies
  }
  final p = fit.beta.length;
  final l = cholesky(fit.cov);
  final z = [for (var j = 0; j < p; j++) rng.normal()];
  final beta = [
    for (var a = 0; a < p; a++)
      () {
        var s = 0.0;
        if (l != null) {
          for (var b = 0; b <= a; b++) {
            s += l.get(a, b) * z[b];
          }
        }
        return fit.beta[a] + s;
      }()
  ];
  return [
    for (final row in xMis)
      () {
        var e = 0.0;
        for (var j = 0; j < p; j++) {
          e += row[j] * beta[j];
        }
        return rng.unif() <= 1 / (1 + math.exp(-e));
      }()
  ];
}
