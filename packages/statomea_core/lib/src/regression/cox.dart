/// Régression de Cox à risques proportionnels (vraisemblance partielle,
/// ex aequo d'Efron ou de Breslow), comme `survival::coxph`, avec :
///  - tests du rapport de vraisemblance, de Wald et du score ;
///  - indice de concordance de Harrell (convention de `survival`) ;
///  - test des risques proportionnels de `cox.zph` (survival ≥ 3) : test du
///    score de l'ajout de termes x·g(t), g = 1 − S_KM(t⁻) centré sur les
///    temps d'événement, évalué en (β̂, 0).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../data/dataset.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'design_matrix.dart';

/// Données de survie prêtes pour l'ajustement.
class SurvivalDesign {
  final DesignMatrix design; // y = temps
  final List<double> status; // 1 = événement, 0 = censure
  final String timeName, statusName, eventLevel;

  /// Termes du modèle (pour réappliquer l'équation à d'autres données).
  final List<TermSpec> terms;

  /// Début d'intervalle (processus de comptage (début, fin]) ; null = suivi depuis 0.
  final List<double>? start;
  final String? startName;
  SurvivalDesign(this.design, this.status, this.timeName, this.statusName, this.eventLevel, {this.terms = const [], this.start, this.startName});
  List<double> get time => design.y;
  int get events => status.where((s) => s == 1).length;
}

SurvivalDesign buildSurvivalDesign(Dataset ds, String time, String status, String eventLevel, List<TermSpec> terms) {
  final d0 = buildDesign(ds, ModelFormula(time, terms));
  final st = ds.text(status);
  final keep = <int>[];
  var missingStatus = 0;
  for (var k = 0; k < d0.n; k++) {
    if (st[d0.rows[k]] == null) {
      missingStatus++;
    } else {
      keep.add(k);
    }
  }
  if (!ds.levels(status).contains(eventLevel)) {
    throw StatInputError('event_level', tr('Modalité « $eventLevel » absente de « $status ».', 'Level "$eventLevel" not found in "$status".'));
  }
  final neg = [for (final k in keep) if (d0.y[k] < 0) k];
  if (neg.isNotEmpty) {
    throw StatInputError('negative_time', tr("${neg.length} durée(s) négative(s) dans « $time » : vérifier les dates d'origine et de fin.", '${neg.length} negative time(s) in "$time": check the start and end dates.'));
  }
  final alerts = [...d0.alerts];
  final excluded = Map<String, int>.of(d0.excludedBy);
  if (missingStatus > 0) {
    excluded[status] = missingStatus;
    alerts.add(Alert('missing_status', Severity.caution, tr('$missingStatus ligne(s) sans statut (événement/censure) exclue(s).', '$missingStatus row(s) without status (event/censoring) excluded.')));
  }
  final d = DesignMatrix(
    columns: d0.columns.sublist(1), // pas de constante dans un modèle de Cox
    termOfColumn: d0.termOfColumn.sublist(1),
    x: [for (final k in keep) d0.x[k].sublist(1)],
    y: [for (final k in keep) d0.y[k]],
    rows: [for (final k in keep) d0.rows[k]],
    excludedBy: excluded,
    excludedByCorrection: d0.excludedByCorrection,
    codingNotes: [...d0.codingNotes, tr('Événement : $status = « $eventLevel » ; autres modalités = censure.', 'Event: $status = "$eventLevel"; other levels = censoring.')],
    alerts: alerts,
    formula: 'Surv($time, $status) ~ ${d0.formula.split('~').last.trim()}',
  );
  if (d.x.isEmpty || d.p == 0) throw StatInputError('no_predictor', tr('Au moins un prédicteur est requis.', 'At least one predictor is required.'));
  return SurvivalDesign(d, [for (final k in keep) st[d0.rows[k]] == eventLevel ? 1.0 : 0.0], time, status, eventLevel, terms: terms);
}

/// Données en processus de comptage : une ligne par intervalle (début, fin], statut à la fin de l'intervalle.
SurvivalDesign buildCountingDesign(Dataset ds, String start, String stop, String status, String eventLevel, List<TermSpec> terms) {
  final s = buildSurvivalDesign(ds, stop, status, eventLevel, terms);
  final st = ds.numeric(start);
  final rows = s.design.rows;
  final bad = [for (var k = 0; k < rows.length; k++) if (st[rows[k]] == null || !(st[rows[k]]! < s.time[k])) rows[k] + 1];
  if (bad.isNotEmpty) {
    throw StatInputError('bad_interval', tr('${bad.length} intervalle(s) avec un début manquant ou ≥ à la fin (lignes ${bad.take(5).join(', ')}${bad.length > 5 ? '…' : ''}).',
        '${bad.length} interval(s) with a missing start or start ≥ stop (rows ${bad.take(5).join(', ')}${bad.length > 5 ? '…' : ''}).'));
  }
  final d = s.design;
  final dm = DesignMatrix(
    columns: d.columns,
    termOfColumn: d.termOfColumn,
    x: d.x,
    y: d.y,
    rows: d.rows,
    excludedBy: d.excludedBy,
    excludedByCorrection: d.excludedByCorrection,
    codingNotes: d.codingNotes,
    alerts: d.alerts,
    formula: 'Surv($start, $stop, $status) ~ ${d.formula.split('~').last.trim()}',
  );
  return SurvivalDesign(dm, s.status, stop, status, eventLevel, terms: terms, start: [for (final r in rows) st[r]!], startName: start);
}

/// Découpe le suivi de chaque sujet à la date de changement d'une covariable binaire (p. ex. une greffe) : intervalle
/// (0, changement] avec la covariable à « non », puis (changement, fin] avec « oui » ; le statut n'est porté que par le
/// dernier intervalle. Changement absent ou ≥ fin : une seule ligne à « non » ; changement ≤ 0 : une seule ligne à
/// « oui » (comme survival::tmerge avec tdc()). Les autres colonnes sont recopiées sur chaque intervalle.
Dataset splitAtSwitch(Dataset ds, {required String time, required String status, required String eventLevel, required String switchTime, required String covariate,
    String startName = 'debut', String stopName = 'fin', String yes = 'oui', String no = 'non'}) {
  final t = ds.numeric(time), sw = ds.numeric(switchTime), st = ds.text(status);
  final keep = [for (final n in ds.names) if (n != time && n != switchTime && n != status && n != covariate) n];
  // Statut des intervalles non terminaux : la modalité de non-événement la plus fréquente.
  final others = [for (final l in ds.levels(status)) if (l != eventLevel) l];
  if (others.isEmpty) throw StatInputError('no_censor_level', tr('« $status » n\'a pas de modalité autre que « $eventLevel ».', '"$status" has no level other than "$eventLevel".'));
  others.sort((a, b) => st.where((v) => v == b).length.compareTo(st.where((v) => v == a).length));
  final censorLevel = others.first;
  final names = [...keep, startName, stopName, status, covariate];
  final rows = <List<String?>>[];
  for (var i = 0; i < ds.rowCount; i++) {
    final ti = t[i];
    if (ti == null) continue;
    final base = [for (final n in keep) ds.cell(i, n)];
    final si = sw[i];
    if (si == null || si >= ti) {
      rows.add([...base, '0', _num(ti), st[i], no]);
    } else if (si <= 0) {
      rows.add([...base, '0', _num(ti), st[i], yes]);
    } else {
      rows.add([...base, '0', _num(si), censorLevel, no]);
      rows.add([...base, _num(si), _num(ti), st[i], yes]);
    }
  }
  return Dataset(names, rows, source: tr('${ds.source} découpé au changement de « $covariate » (« $switchTime »)', '${ds.source} split at the change of "$covariate" ("$switchTime")'));
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class CoxFit {
  final List<double> beta;
  final Matrix cov;
  final double logLik, logLikNull, scoreTest;
  final int iterations;
  final bool converged;
  final List<String> trace;
  CoxFit(this.beta, this.cov, this.logLik, this.logLikNull, this.scoreTest, this.iterations, this.converged, this.trace);
}

/// Groupes de temps d'événement (ordre décroissant) : indices du groupe.
List<List<int>> _timeGroups(List<double> t) {
  final idx = List<int>.generate(t.length, (i) => i)..sort((a, b) => t[b].compareTo(t[a]));
  final groups = <List<int>>[];
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && t[idx[j + 1]] == t[idx[i]]) {
      j++;
    }
    groups.add(idx.sublist(i, j + 1));
    i = j + 1;
  }
  return groups;
}

/// Log-vraisemblance partielle, score et information en β.
({double ll, List<double> u, Matrix info}) coxEval(List<List<double>> x, List<double> t, List<double> d, List<double> beta,
    {bool efron = true, List<double>? start}) {
  if (start != null) return _coxEvalCounting(x, start, t, d, beta, efron: efron);
  final p = beta.length;
  final eta = [
    for (final row in x)
      () {
        var s = 0.0;
        for (var j = 0; j < p; j++) {
          s += row[j] * beta[j];
        }
        return s;
      }()
  ];
  var s0 = 0.0;
  final s1 = List<double>.filled(p, 0);
  final s2 = Matrix(p, p);
  var ll = 0.0;
  final u = List<double>.filled(p, 0);
  final info = Matrix(p, p);
  for (final g in _timeGroups(t)) {
    var d0 = 0.0;
    final d1 = List<double>.filled(p, 0);
    final d2 = Matrix(p, p);
    var nd = 0;
    for (final i in g) {
      final r = math.exp(eta[i]);
      s0 += r;
      for (var a = 0; a < p; a++) {
        s1[a] += r * x[i][a];
        for (var b = 0; b <= a; b++) {
          s2.data[a * p + b] += r * x[i][a] * x[i][b];
        }
      }
      if (d[i] == 1) {
        nd++;
        d0 += r;
        ll += eta[i];
        for (var a = 0; a < p; a++) {
          u[a] += x[i][a];
          d1[a] += r * x[i][a];
          for (var b = 0; b <= a; b++) {
            d2.data[a * p + b] += r * x[i][a] * x[i][b];
          }
        }
      }
    }
    for (var l = 0; l < nd; l++) {
      final f = efron ? l / nd : 0.0;
      final z0 = s0 - f * d0;
      ll -= math.log(z0);
      for (var a = 0; a < p; a++) {
        final za = s1[a] - f * d1[a];
        u[a] -= za / z0;
        for (var b = 0; b <= a; b++) {
          final zb = s1[b] - f * d1[b];
          final v = (s2.data[a * p + b] - f * d2.data[a * p + b]) / z0 - za * zb / (z0 * z0);
          info.data[a * p + b] += v;
        }
      }
    }
  }
  for (var a = 0; a < p; a++) {
    for (var b = 0; b < a; b++) {
      info.data[b * p + a] = info.data[a * p + b];
    }
  }
  return (ll: ll, u: u, info: info);
}

/// Vraisemblance partielle en processus de comptage : à un temps d'événement t, l'ensemble à risque est formé des
/// intervalles (début, fin] avec début < t ≤ fin (comme coxph avec Surv(début, fin, statut)). Balayage par fin
/// décroissante : un intervalle entre quand t ≤ fin, sort quand t ≤ début.
({double ll, List<double> u, Matrix info}) _coxEvalCounting(List<List<double>> x, List<double> start, List<double> t, List<double> d, List<double> beta,
    {bool efron = true}) {
  final n = t.length, p = beta.length;
  final r = List<double>.filled(n, 0);
  final eta = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var e = 0.0;
    for (var j = 0; j < p; j++) {
      e += x[i][j] * beta[j];
    }
    eta[i] = e;
    r[i] = math.exp(e);
  }
  final byStop = List<int>.generate(n, (i) => i)..sort((a, b) => t[b].compareTo(t[a]));
  final byStart = List<int>.generate(n, (i) => i)..sort((a, b) => start[b].compareTo(start[a]));
  var s0 = 0.0;
  final s1 = List<double>.filled(p, 0);
  final s2 = Matrix(p, p);
  void acc(int i, double sign) {
    final w = sign * r[i];
    s0 += w;
    for (var a = 0; a < p; a++) {
      s1[a] += w * x[i][a];
      for (var b = 0; b <= a; b++) {
        s2.data[a * p + b] += w * x[i][a] * x[i][b];
      }
    }
  }

  var ll = 0.0;
  final u = List<double>.filled(p, 0);
  final info = Matrix(p, p);
  var q = 0, out = 0;
  while (q < n) {
    final tt = t[byStop[q]];
    var m = q;
    final ev = <int>[];
    while (m < n && t[byStop[m]] == tt) {
      final i = byStop[m];
      acc(i, 1);
      if (d[i] == 1) ev.add(i);
      m++;
    }
    q = m;
    if (ev.isEmpty) continue;
    // Retirer les intervalles qui commencent à t ou après (début ≥ t).
    while (out < n && start[byStart[out]] >= tt) {
      acc(byStart[out], -1);
      out++;
    }
    final nd = ev.length;
    var d0 = 0.0;
    final d1 = List<double>.filled(p, 0);
    final d2 = Matrix(p, p);
    for (final i in ev) {
      d0 += r[i];
      ll += eta[i];
      for (var a = 0; a < p; a++) {
        u[a] += x[i][a];
        d1[a] += r[i] * x[i][a];
        for (var b = 0; b <= a; b++) {
          d2.data[a * p + b] += r[i] * x[i][a] * x[i][b];
        }
      }
    }
    for (var l = 0; l < nd; l++) {
      final f = efron ? l / nd : 0.0;
      final z0 = s0 - f * d0;
      ll -= math.log(z0);
      for (var a = 0; a < p; a++) {
        final za = s1[a] - f * d1[a];
        u[a] -= za / z0;
        for (var b = 0; b <= a; b++) {
          final zb = s1[b] - f * d1[b];
          info.data[a * p + b] += (s2.data[a * p + b] - f * d2.data[a * p + b]) / z0 - za * zb / (z0 * z0);
        }
      }
    }
  }
  for (var a = 0; a < p; a++) {
    for (var b = 0; b < a; b++) {
      info.data[b * p + a] = info.data[a * p + b];
    }
  }
  return (ll: ll, u: u, info: info);
}

/// Ajustement par Newton-Raphson avec demi-pas (critère de coxph : variation
/// relative de la log-vraisemblance < 1e-9 ; ici 1e-12).
CoxFit fitCox(List<List<double>> x, List<double> t, List<double> d, {bool efron = true, int maxIter = 50, List<double>? start}) {
  final p = x.first.length;
  // Centrage des covariables (stabilité numérique ; β inchangés).
  final means = [for (var j = 0; j < p; j++) x.fold(0.0, (a, r) => a + r[j]) / x.length];
  final xc = [for (final r in x) [for (var j = 0; j < p; j++) r[j] - means[j]]];
  var beta = List<double>.filled(p, 0);
  var cur = coxEval(xc, t, d, beta, efron: efron, start: start);
  final ll0 = cur.ll;
  final cov0 = invertSpd(cur.info);
  var score = 0.0;
  if (cov0 != null) {
    final v = cov0.multiplyVector(cur.u);
    for (var j = 0; j < p; j++) {
      score += v[j] * cur.u[j];
    }
  }
  final trace = <String>[tr('Itération 0 : log-vraisemblance partielle = ${ll0.toStringAsFixed(8)}', 'Iteration 0: partial log-likelihood = ${ll0.toStringAsFixed(8)}')];
  var converged = false;
  var it = 0;
  for (it = 1; it <= maxIter; it++) {
    var step = solveSpd(cur.info, cur.u);
    if (step == null) break;
    var next = [for (var j = 0; j < p; j++) beta[j] + step[j]];
    var ev = coxEval(xc, t, d, next, efron: efron, start: start);
    var h = 0;
    while ((ev.ll.isNaN || ev.ll < cur.ll - 1e-12 * (1 + cur.ll.abs())) && h < 30) {
      step = [for (final s in step!) s / 2];
      next = [for (var j = 0; j < p; j++) beta[j] + step[j]];
      ev = coxEval(xc, t, d, next, efron: efron, start: start);
      h++;
    }
    final change = (ev.ll - cur.ll).abs();
    beta = next;
    cur = ev;
    trace.add(tr('Itération $it : log-vraisemblance partielle = ${cur.ll.toStringAsFixed(10)}${h > 0 ? " ($h demi-pas)" : ""}', 'Iteration $it: partial log-likelihood = ${cur.ll.toStringAsFixed(10)}${h > 0 ? " ($h step-halving(s))" : ""}'));
    if (change <= 1e-12 * (1 + cur.ll.abs())) {
      converged = true;
      break;
    }
  }
  final cov = invertSpd(cur.info) ?? Matrix(p, p);
  return CoxFit(beta, cov, cur.ll, ll0, score, math.min(it, maxIter), converged, trace);
}

/// Indice de concordance (convention de survival::concordance : paires
/// comparables quand le temps le plus court est un événement ; ex aequo de
/// temps entre deux événements exclus ; ex aequo du score comptés ½).
({double c, int concordant, int discordant, int tiedX, int comparable}) coxConcordance(List<double> t, List<double> d, List<double> eta) {
  var conc = 0, disc = 0, tie = 0;
  final n = t.length;
  for (var i = 0; i < n; i++) {
    if (d[i] != 1) continue;
    for (var j = 0; j < n; j++) {
      if (j == i) continue;
      // i a l'événement ; j est encore à risque après t_i (t_j > t_i), ou censuré à t_i.
      final comparable = t[j] > t[i] || (t[j] == t[i] && d[j] == 0);
      if (!comparable) continue;
      if (eta[i] > eta[j]) {
        conc++;
      } else if (eta[i] < eta[j]) {
        disc++;
      } else {
        tie++;
      }
    }
  }
  final tot = conc + disc + tie;
  return (c: (conc + 0.5 * tie) / tot, concordant: conc, discordant: disc, tiedX: tie, comparable: tot);
}

/// Test des risques proportionnels (cox.zph, transformation « km »).
({List<(String, double, int, double)> terms, double globalChi2, int globalDf, double globalP}) coxZph(
    SurvivalDesign s, CoxFit fit, {bool efron = true}) {
  final x = s.design.x, t = s.time, d = s.status;
  final n = x.length, p = fit.beta.length;
  // Kaplan-Meier sur tous les temps distincts.
  final times = {...t}.toList()..sort();
  final surv = <double, double>{};
  var sv = 1.0;
  for (final tt in times) {
    final atRisk = t.where((v) => v >= tt).length;
    var ev = 0;
    for (var i = 0; i < n; i++) {
      if (t[i] == tt && d[i] == 1) ev++;
    }
    sv *= 1 - ev / atRisk;
    surv[tt] = sv;
  }
  double sMinus(double tt) {
    var last = 1.0;
    for (final u in times) {
      if (u < tt) {
        last = surv[u]!;
      } else {
        break;
      }
    }
    return last;
  }

  final ttimes = [for (final v in t) 1 - sMinus(v)];
  final evIdx = [for (var i = 0; i < n; i++) if (d[i] == 1) i];
  final meanG = evIdx.fold(0.0, (a, i) => a + ttimes[i]) / evIdx.length;
  final g = [for (final v in ttimes) v - meanG];
  final eta = [
    for (final r in x)
      () {
        var s = 0.0;
        for (var j = 0; j < p; j++) {
          s += r[j] * fit.beta[j];
        }
        return s;
      }()
  ];
  final m = 2 * p;
  final imat = Matrix(m, m);
  final u2 = List<double>.filled(p, 0);
  var s0 = 0.0;
  final s1 = List<double>.filled(p, 0);
  final s2 = Matrix(p, p);
  for (final grp in _timeGroups(t)) {
    var d0 = 0.0;
    final d1 = List<double>.filled(p, 0);
    final d2 = Matrix(p, p);
    var nd = 0;
    final gt = g[grp.first];
    for (final i in grp) {
      final r = math.exp(eta[i]);
      s0 += r;
      for (var a = 0; a < p; a++) {
        s1[a] += r * x[i][a];
        for (var b = 0; b < p; b++) {
          s2.data[a * p + b] += r * x[i][a] * x[i][b];
        }
      }
      if (d[i] == 1) {
        nd++;
        d0 += r;
        for (var a = 0; a < p; a++) {
          u2[a] += gt * x[i][a];
          d1[a] += r * x[i][a];
          for (var b = 0; b < p; b++) {
            d2.data[a * p + b] += r * x[i][a] * x[i][b];
          }
        }
      }
    }
    for (var l = 0; l < nd; l++) {
      final f = efron ? l / nd : 0.0;
      final z0 = s0 - f * d0;
      for (var a = 0; a < p; a++) {
        final za = s1[a] - f * d1[a];
        u2[a] -= gt * za / z0;
        for (var b = 0; b < p; b++) {
          final zb = s1[b] - f * d1[b];
          final v = (s2.data[a * p + b] - f * d2.data[a * p + b]) / z0 - za * zb / (z0 * z0);
          imat.data[a * m + b] += v;
          imat.data[a * m + (b + p)] += gt * v;
          imat.data[(a + p) * m + b] += gt * v;
          imat.data[(a + p) * m + (b + p)] += gt * gt * v;
        }
      }
    }
  }
  double test(List<int> cols) {
    final kk = [for (var j = 0; j < p; j++) j, for (final c in cols) c + p];
    final sub = Matrix(kk.length, kk.length);
    for (var a = 0; a < kk.length; a++) {
      for (var b = 0; b < kk.length; b++) {
        sub.set(a, b, imat.get(kk[a], kk[b]));
      }
    }
    final u = [for (var j = 0; j < p; j++) 0.0, for (final c in cols) u2[c]];
    final sol = solveSpd(sub, u)!;
    var s = 0.0;
    for (var a = 0; a < u.length; a++) {
      s += sol[a] * u[a];
    }
    return s;
  }

  final termNames = <String>[];
  for (final tn in s.design.termOfColumn) {
    if (!termNames.contains(tn)) termNames.add(tn);
  }
  final terms = <(String, double, int, double)>[];
  for (final tn in termNames) {
    final cols = [for (var j = 0; j < p; j++) if (s.design.termOfColumn[j] == tn) j];
    final chi = test(cols);
    terms.add((tn, chi, cols.length, chiSquareUpper(chi, cols.length.toDouble())));
  }
  final glob = test([for (var j = 0; j < p; j++) j]);
  return (terms: terms, globalChi2: glob, globalDf: p, globalP: chiSquareUpper(glob, p.toDouble()));
}

/// Analyse complète de Cox.
AnalysisResult coxRegression(SurvivalDesign s, {bool efron = true, double level = 0.95}) {
  final d = s.design;
  final counting = s.start != null;
  final fit = fitCox(d.x, s.time, s.status, efron: efron, start: s.start);
  final p = d.p;
  final z = normalQuantile(1 - (1 - level) / 2);
  final coefs = [
    for (var j = 0; j < p; j++)
      () {
        final se = math.sqrt(fit.cov.get(j, j));
        final w = fit.beta[j] / se;
        return Coefficient(d.columns[j], fit.beta[j], se, w, normalTwoSidedP(w), fit.beta[j] - z * se, fit.beta[j] + z * se);
      }()
  ];
  final lr = 2 * (fit.logLik - fit.logLikNull);
  var wald = 0.0;
  final inv = invertSpd(fit.cov);
  if (inv != null) {
    final v = inv.multiplyVector(fit.beta);
    for (var j = 0; j < p; j++) {
      wald += v[j] * fit.beta[j];
    }
  }
  final eta = [
    for (final r in d.x)
      () {
        var t = 0.0;
        for (var j = 0; j < p; j++) {
          t += r[j] * fit.beta[j];
        }
        return t;
      }()
  ];
  final conc = counting ? null : coxConcordance(s.time, s.status, eta);
  final events = s.events;
  final alerts = <Alert>[...d.alerts];
  final checks = <Check>[];
  // Monotonie de la vraisemblance (équivalent de la séparation) : β divergent.
  final huge = [for (final c in coefs) if (c.estimate.abs() > 10 || c.se > 100 || c.se.isNaN) c.name];
  checks.add(Check('convergence', tr('Convergence et vraisemblance non monotone', 'Convergence and non-monotone likelihood'), (fit.converged && huge.isEmpty) ? CheckStatus.ok : CheckStatus.violated,
      tr('${fit.iterations} itération(s)${huge.isEmpty ? "." : " ; coefficient(s) divergent(s) : ${huge.join(", ")} (vraisemblance monotone, p. ex. aucun événement dans une modalité)."}',
          '${fit.iterations} iteration(s)${huge.isEmpty ? "." : "; diverging coefficient(s): ${huge.join(", ")} (monotone likelihood, e.g. no event in a level)."}')));
  if (!fit.converged || huge.isNotEmpty) {
    alerts.add(Alert('cox_monotone', Severity.critical,
        tr('Non-convergence ou vraisemblance monotone : les HR concernés sont infinis ou arbitraires et ne doivent pas être rapportés.', 'Non-convergence or monotone likelihood: the HRs involved are infinite or arbitrary and must not be reported.'),
        suggestion: tr('Regrouper des modalités justifiées a priori, retirer le terme, ou utiliser une pénalisation (hors V1).', 'Merge levels justified a priori, remove the term, or use penalization (outside V1).')));
  }
  final zph = (fit.converged && huge.isEmpty && !counting) ? coxZph(s, fit, efron: efron) : null;
  if (zph != null) {
    final bad = [for (final t in zph.terms) if (t.$4 < 0.05) t.$1];
    checks.add(Check('proportional_hazards', tr('Risques proportionnels (test de cox.zph, transformation KM)', 'Proportional hazards (cox.zph test, KM transform)'),
        zph.globalP < 0.05 || bad.isNotEmpty ? CheckStatus.warning : CheckStatus.ok,
        tr("Global : χ² = ${fmt(zph.globalChi2)} (ddl ${zph.globalDf}), ${fmtP(zph.globalP)}. ${bad.isEmpty ? "Aucun terme en écart significatif." : "Écart pour : ${bad.join(", ")} — le HR varie peut-être dans le temps ; examiner les résidus de Schoenfeld, stratifier ou modéliser une interaction avec le temps."} Un test non significatif ne prouve pas la proportionnalité (faible puissance avec peu d'événements).",
            'Global: χ² = ${fmt(zph.globalChi2)} (df ${zph.globalDf}), ${fmtP(zph.globalP)}. ${bad.isEmpty ? "No term with a significant departure." : "Departure for: ${bad.join(", ")} — the HR may vary over time; examine Schoenfeld residuals, stratify or model an interaction with time."} A non-significant test does not prove proportionality (low power with few events).')));
  }
  if (counting) {
    checks.add(Check('proportional_hazards', tr('Risques proportionnels', 'Proportional hazards'), CheckStatus.notAssessed,
        tr('Test de cox.zph non calculé en processus de comptage : examiner les résidus de Schoenfeld dans un logiciel dédié, ou ajouter une interaction avec le temps.',
            'cox.zph test not computed for counting-process data: examine Schoenfeld residuals in dedicated software, or add an interaction with time.')));
  }
  checks.add(collinearityCheck(gvif(d)));
  checks.add(Check('censoring', tr('Censure non informative', 'Non-informative censoring'), CheckStatus.notAssessed,
      tr('Hypothèse non vérifiable par le calcul : les perdus de vue doivent avoir le même pronostic que les sujets suivis.', 'Assumption not verifiable by computation: subjects lost to follow-up must have the same prognosis as those followed.')));
  final epv = events / p;
  if (epv < 5) {
    alerts.add(Alert('epv_very_low', Severity.serious, tr('$events événement(s) pour $p paramètre(s) (EPV = ${fmt(epv)}) : estimations instables et biaisées.', '$events event(s) for $p parameter(s) (EPV = ${fmt(epv)}): unstable and biased estimates.'),
        suggestion: tr('Réduire le nombre de paramètres, choisis a priori.', 'Reduce the number of parameters, chosen a priori.')));
  } else if (epv < 10) {
    alerts.add(Alert('epv_low', Severity.caution, tr('EPV = ${fmt(epv)} (< 10) : risque de surajustement.', 'EPV = ${fmt(epv)} (< 10): risk of overfitting.')));
  }
  final ties = <double>{};
  var hasTies = false;
  for (var i = 0; i < s.time.length; i++) {
    if (s.status[i] == 1 && !ties.add(s.time[i])) hasTies = true;
  }
  final main = coefs.first;
  final fu = [...s.time]..sort();
  return AnalysisResult(
    methodId: 'cox',
    methodName: counting
        ? tr('Régression de Cox avec covariable(s) dépendant du temps (processus de comptage)', 'Cox regression with time-dependent covariate(s) (counting process)')
        : tr('Régression de Cox (risques proportionnels)', 'Cox regression (proportional hazards)'),
    inputs: {'model': d.describe(), 'ties': efron ? 'efron' : 'breslow', 'level': level, 'events': events},
    formula: counting
        ? tr("h(t | x(t)) = h₀(t)·exp(x(t)ᵀβ) ; données en intervalles (début, fin] : à chaque temps d'événement, l'ensemble à risque contient les intervalles avec début < t ≤ fin, chaque sujet y figurant avec la valeur de ses covariables à ce moment ; vraisemblance partielle (ex aequo : ${efron ? "Efron" : "Breslow"}), Newton-Raphson ; HR = exp(β), IC de Wald ; tests RV, Wald, score.",
            "h(t | x(t)) = h₀(t)·exp(x(t)ᵀβ); data in (start, stop] intervals: at each event time, the risk set contains the intervals with start < t ≤ stop, each subject entering with its covariate values at that moment; partial likelihood (ties: ${efron ? "Efron" : "Breslow"}), Newton-Raphson; HR = exp(β), Wald CI; LR, Wald and score tests.")
        : tr("h(t | x) = h₀(t)·exp(xᵀβ) ; vraisemblance partielle (ex aequo : ${efron ? "Efron" : "Breslow"}), Newton-Raphson ; HR = exp(β), IC de Wald ; tests RV, Wald, score ; concordance de Harrell ; test de proportionnalité de cox.zph (score de l'ajout de x·g(t), g = 1 − S_KM(t⁻) centré).",
        "h(t | x) = h₀(t)·exp(xᵀβ); partial likelihood (ties: ${efron ? "Efron" : "Breslow"}), Newton-Raphson; HR = exp(β), Wald CI; LR, Wald and score tests; Harrell's concordance; cox.zph proportionality test (score for adding x·g(t), g = 1 − S_KM(t⁻) centred)."),
    estimates: [
      for (final c in coefs)
        Estimate('HR — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), level: level, pValue: c.p, se: c.se),
      if (conc != null) Estimate(tr('Concordance (C de Harrell)', "Concordance (Harrell's C)"), conc.c),
    ],
    statistics: {
      'n': d.n.toDouble(),
      'events': events.toDouble(),
      'loglik': fit.logLik,
      'loglik_null': fit.logLikNull,
      'lr': lr,
      'lr_p': chiSquareUpper(lr, p.toDouble()),
      'wald': wald,
      'wald_p': chiSquareUpper(wald, p.toDouble()),
      'score': fit.scoreTest,
      'score_p': chiSquareUpper(fit.scoreTest, p.toDouble()),
      'concordance': ?conc?.c,
      'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d.columns[j]}': coefs[j].se,
      if (zph != null) 'zph_global': zph.globalChi2,
      if (zph != null) 'zph_global_p': zph.globalP,
      if (zph != null)
        for (final t in zph.terms) 'zph_${t.$1}': t.$2,
    },
    checks: checks,
    alerts: alerts,
    tables: [
      coefficientTable(coefs, effectLabel: 'HR', exponentiate: true, level: level),
      ResultTable(tr('Tests globaux', 'Global tests'), ['Test', 'χ²', tr('ddl', 'df'), 'p'], [
        [tr('Rapport de vraisemblance', 'Likelihood ratio'), fmt(lr), '$p', fmtP(chiSquareUpper(lr, p.toDouble()))],
        ['Wald', fmt(wald), '$p', fmtP(chiSquareUpper(wald, p.toDouble()))],
        ['Score (log-rank)', fmt(fit.scoreTest), '$p', fmtP(chiSquareUpper(fit.scoreTest, p.toDouble()))],
      ]),
      if (zph != null)
        ResultTable(tr('Proportionnalité des risques (cox.zph)', 'Proportional hazards (cox.zph)'), [tr('Terme', 'Term'), 'χ²', tr('ddl', 'df'), 'p'], [
          for (final t in zph.terms) [t.$1, fmt(t.$2), '${t.$3}', fmtP(t.$4)],
          ['GLOBAL', fmt(zph.globalChi2), '${zph.globalDf}', fmtP(zph.globalP)],
        ]),
      ResultTable(tr('Codage et observations', 'Coding and observations'), [tr('Élément', 'Item'), tr('Détail', 'Detail')], [
        [tr('Modèle', 'Model'), d.formula],
        if (counting) [tr('Intervalles (début, fin] / événements', '(start, stop] intervals / events'), '${d.n} / $events'] else [tr('Observations / événements / censurés', 'Observations / events / censored'), '${d.n} / $events / ${d.n - events}'],
        [tr('Durée de suivi (min – médiane – max)', 'Follow-up time (min – median – max)'), '${fmt(fu.first)} – ${fmt(fu[fu.length ~/ 2])} – ${fmt(fu.last)}'],
        [tr("Ex aequo de temps d'événement", 'Tied event times'), hasTies ? tr('oui (méthode ${efron ? "d'Efron" : "de Breslow"})', 'yes (${efron ? "Efron" : "Breslow"} method)') : tr('non', 'no')],
        for (final c in d.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    log: fit.trace,
    interpretation: Interpretation(
      whyThisMethod: tr("Délai jusqu'à un événement avec censure : le modèle de Cox compare les taux instantanés d'événement (hazards) sans supposer de forme pour le risque de base, sous l'hypothèse que leur rapport est constant dans le temps.",
          'Time to an event with censoring: the Cox model compares instantaneous event rates (hazards) without assuming a form for the baseline hazard, under the assumption that their ratio is constant over time.'),
      whatItMeans: tr('« ${main.name} » : HR = ${fmt(math.exp(main.estimate))} (IC ${fmt(math.exp(main.lower))} à ${fmt(math.exp(main.upper))}), ${fmtP(main.p)}, à autres variables fixées.${conc == null ? '' : ' Concordance C = ${fmt(conc.c)} (0,5 = pas de discrimination).'}',
          '"${main.name}": HR = ${fmt(math.exp(main.estimate))} (CI ${fmt(math.exp(main.lower))} to ${fmt(math.exp(main.upper))}), ${fmtP(main.p)}, holding the other variables fixed.${conc == null ? '' : ' Concordance C = ${fmt(conc.c)} (0.5 = no discrimination).'}'),
      notJustified: tr("Lire un HR comme un risque relatif cumulé ou comme une différence de survie à une date donnée ; interpréter causalement un HR d'étude observationnelle ; ignorer un écart à la proportionnalité ; conclure à la proportionnalité parce que le test n'est pas significatif.",
          'Reading an HR as a cumulative risk ratio or as a survival difference at a given date; interpreting an HR from an observational study causally; ignoring a departure from proportionality; concluding proportionality because the test is not significant.'),
    ),
  );
}
