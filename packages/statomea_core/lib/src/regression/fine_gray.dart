/// Risques concurrents : modèle de Fine et Gray (1999) sur la fonction de sous-répartition, comme `cmprsk::crr` :
///  - ensemble à risque pondéré : sujets encore suivis (poids 1) et sujets déjà sortis par un événement concurrent,
///    pondérés par Ĝ(t⁻)/Ĝ(X⁻), Ĝ = Kaplan-Meier de la censure ;
///  - vraisemblance partielle pondérée (ex aequo de Breslow), Newton-Raphson ;
///  - variance sandwich de Fine et Gray : Ω⁻¹ Σ(ηᵢ + ψᵢ)⊗² Ω⁻¹, ψᵢ = part due à l'estimation de Ĝ.
/// Codes de statut : 1 = événement d'intérêt, 2 = événement concurrent, 0 = censure.
/// Validé contre validation/r/40_risques_concurrents.R.
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';
import 'common.dart';
import 'cox.dart';
import 'design_matrix.dart';

class FineGrayFit {
  final List<double> beta;
  final Matrix cov, information;
  final double logLik, logLikNull;
  final int iterations;
  final bool converged;
  final List<String> trace;
  FineGrayFit(this.beta, this.cov, this.information, this.logLik, this.logLikNull, this.iterations, this.converged, this.trace);
}

/// Prépare un modèle de risques concurrents : statut codé 1 (cause d'intérêt), 0 (censure), 2 (toute autre modalité).
SurvivalDesign buildCompetingDesign(Dataset ds, String time, String status, String causeLevel, Set<String> censorLevels, List<TermSpec> terms) {
  if (censorLevels.contains(causeLevel)) {
    throw StatInputError('cause_is_censor', tr('La modalité « $causeLevel » ne peut pas être à la fois l\'événement d\'intérêt et une censure.', 'Level "$causeLevel" cannot be both the event of interest and censoring.'));
  }
  final s = buildSurvivalDesign(ds, time, status, causeLevel, terms);
  final st = ds.text(status);
  final codes = [for (final r in s.design.rows) st[r] == causeLevel ? 1.0 : (censorLevels.contains(st[r]) ? 0.0 : 2.0)];
  final others = {for (final r in s.design.rows) if (st[r] != causeLevel && !censorLevels.contains(st[r])) st[r]!}.toList()..sort();
  final d = s.design;
  final notes = [
    for (final c in d.codingNotes)
      if (!c.startsWith(tr('Événement :', 'Event:'))) c,
    tr('Événement d\'intérêt : $status = « $causeLevel » ; censure : ${censorLevels.map((c) => '« $c »').join(', ')} ; événement(s) concurrent(s) : ${others.isEmpty ? 'aucun' : others.map((c) => '« $c »').join(', ')}.',
        'Event of interest: $status = "$causeLevel"; censoring: ${censorLevels.map((c) => '"$c"').join(', ')}; competing event(s): ${others.isEmpty ? 'none' : others.map((c) => '"$c"').join(', ')}.'),
  ];
  final dm = DesignMatrix(
    columns: d.columns,
    termOfColumn: d.termOfColumn,
    x: d.x,
    y: d.y,
    rows: d.rows,
    excludedBy: d.excludedBy,
    excludedByCorrection: d.excludedByCorrection,
    codingNotes: notes,
    alerts: d.alerts,
    formula: 'Crr($time, $status) ~ ${d.formula.split('~').last.trim()}',
    splineKnots: d.splineKnots,
    splineColumns: d.splineColumns,
  );
  return SurvivalDesign(dm, codes, time, status, causeLevel, terms: terms);
}

/// Structures partagées par l'ajustement et la variance : ordre des temps, Ĝ(t⁻) de chaque sujet et de chaque temps
/// d'événement d'intérêt.
class _FgData {
  final List<List<double>> x;
  final List<double> t;
  final List<int> code;
  final int n, p;
  late final List<int> order; // indices triés par temps croissant
  late final List<double> ut; // temps distincts d'événement d'intérêt
  late final List<int> nd; // nombre d'événements d'intérêt à chaque ut
  late final List<double> gUt; // Ĝ(ut⁻)
  late final List<double> gX; // Ĝ(Xᵢ⁻)
  late final List<int> firstAtOrAfter; // pour chaque ut : position (dans order) du premier sujet avec X ≥ ut

  _FgData(this.x, this.t, this.code)
      : n = t.length,
        p = x.first.length {
    order = List<int>.generate(n, (i) => i)..sort((a, b) => t[a].compareTo(t[b]));
    // Ĝ(s⁻) = Π_{c < s} (1 − censures(c)/à risque(c)).
    final cTimes = <double>[], cFactor = <double>[];
    var k = 0;
    while (k < n) {
      final tv = t[order[k]];
      var c = 0, m = k;
      while (m < n && t[order[m]] == tv) {
        if (code[order[m]] == 0) c++;
        m++;
      }
      if (c > 0) {
        cTimes.add(tv);
        cFactor.add(1 - c / (n - k));
      }
      k = m;
    }
    double gMinus(double s) {
      var g = 1.0;
      for (var j = 0; j < cTimes.length && cTimes[j] < s; j++) {
        g *= cFactor[j];
      }
      return g;
    }

    // Évaluation en un passage (temps croissants).
    gX = List<double>.filled(n, 1);
    var g = 1.0, j = 0;
    for (final i in order) {
      while (j < cTimes.length && cTimes[j] < t[i]) {
        g *= cFactor[j];
        j++;
      }
      gX[i] = g;
    }
    final u = <double>[], c = <int>[], first = <int>[];
    for (var q = 0; q < n; q++) {
      final i = order[q];
      if (code[i] != 1) continue;
      if (u.isNotEmpty && u.last == t[i]) {
        c[c.length - 1]++;
      } else {
        u.add(t[i]);
        c.add(1);
        var f = q;
        while (f > 0 && t[order[f - 1]] == t[i]) {
          f--;
        }
        first.add(f);
      }
    }
    ut = u;
    nd = c;
    firstAtOrAfter = first;
    gUt = [for (final s in ut) gMinus(s)];
  }
}

/// Sommes pondérées S0, S1, S2 à chaque temps d'événement d'intérêt, en β.
({List<double> s0, List<List<double>> s1, List<Matrix> s2, List<double> r}) _fgSums(_FgData f, List<double> beta) {
  final n = f.n, p = f.p;
  final r = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var e = 0.0;
    for (var a = 0; a < p; a++) {
      e += f.x[i][a] * beta[a];
    }
    r[i] = math.exp(e);
  }
  // Sommes suffixes (X ≥ t) sur l'ordre croissant.
  final suf0 = List<double>.filled(n + 1, 0);
  final suf1 = List<List<double>>.generate(n + 1, (_) => List<double>.filled(p, 0));
  final suf2 = List<List<double>>.generate(n + 1, (_) => List<double>.filled(p * p, 0));
  for (var q = n - 1; q >= 0; q--) {
    final i = f.order[q], xi = f.x[i], ri = r[i];
    suf0[q] = suf0[q + 1] + ri;
    for (var a = 0; a < p; a++) {
      suf1[q][a] = suf1[q + 1][a] + ri * xi[a];
      for (var b = 0; b < p; b++) {
        suf2[q][a * p + b] = suf2[q + 1][a * p + b] + ri * xi[a] * xi[b];
      }
    }
  }
  // Événements concurrents déjà survenus (X < t), pondérés par rᵢ/Ĝ(Xᵢ⁻) ; le facteur Ĝ(t⁻) est appliqué ensuite.
  final s0 = <double>[], s1 = <List<double>>[], s2 = <Matrix>[];
  var c0 = 0.0;
  final c1 = List<double>.filled(p, 0), c2 = List<double>.filled(p * p, 0);
  var q = 0;
  for (var k = 0; k < f.ut.length; k++) {
    final fk = f.firstAtOrAfter[k];
    while (q < fk) {
      final i = f.order[q];
      if (f.code[i] == 2) {
        final w = r[i] / f.gX[i], xi = f.x[i];
        c0 += w;
        for (var a = 0; a < p; a++) {
          c1[a] += w * xi[a];
          for (var b = 0; b < p; b++) {
            c2[a * p + b] += w * xi[a] * xi[b];
          }
        }
      }
      q++;
    }
    final g = f.gUt[k];
    s0.add(suf0[fk] + g * c0);
    s1.add([for (var a = 0; a < p; a++) suf1[fk][a] + g * c1[a]]);
    final m = Matrix(p, p);
    for (var a = 0; a < p * p; a++) {
      m.data[a] = suf2[fk][a] + g * c2[a];
    }
    s2.add(m);
  }
  return (s0: s0, s1: s1, s2: s2, r: r);
}

({double ll, List<double> u, Matrix info}) _fgEval(_FgData f, List<double> beta) {
  final p = f.p;
  final s = _fgSums(f, beta);
  var ll = 0.0;
  final u = List<double>.filled(p, 0);
  final info = Matrix(p, p);
  for (var q = 0; q < f.n; q++) {
    final i = f.order[q];
    if (f.code[i] != 1) continue;
    for (var a = 0; a < p; a++) {
      ll += f.x[i][a] * beta[a];
      u[a] += f.x[i][a];
    }
  }
  for (var k = 0; k < f.ut.length; k++) {
    final nd = f.nd[k].toDouble(), s0 = s.s0[k], s1 = s.s1[k], s2 = s.s2[k];
    ll -= nd * math.log(s0);
    for (var a = 0; a < p; a++) {
      u[a] -= nd * s1[a] / s0;
      for (var b = 0; b < p; b++) {
        info.data[a * p + b] += nd * (s2.data[a * p + b] / s0 - s1[a] * s1[b] / (s0 * s0));
      }
    }
  }
  return (ll: ll, u: u, info: info);
}

/// Ajustement du modèle de Fine-Gray. [code] : 1 = événement d'intérêt, 2 = concurrent, 0 = censure.
FineGrayFit fitFineGray(List<List<double>> x, List<double> t, List<int> code, {int maxIter = 50}) {
  if (!code.contains(1)) throw StatInputError('no_event', tr('Aucun événement d\'intérêt.', 'No event of interest.'));
  final f = _FgData(x, t, code);
  final p = f.p;
  var beta = List<double>.filled(p, 0);
  var cur = _fgEval(f, beta);
  final ll0 = cur.ll;
  final trace = <String>[tr('Itération 0 : log-pseudo-vraisemblance = ${ll0.toStringAsFixed(8)}', 'Iteration 0: log pseudo-likelihood = ${ll0.toStringAsFixed(8)}')];
  var converged = false;
  var it = 0;
  for (it = 1; it <= maxIter; it++) {
    var step = solveSpd(cur.info, cur.u);
    if (step == null) break;
    var next = [for (var j = 0; j < p; j++) beta[j] + step[j]];
    var ev = _fgEval(f, next);
    var h = 0;
    while ((ev.ll.isNaN || ev.ll < cur.ll - 1e-12 * (1 + cur.ll.abs())) && h < 30) {
      step = [for (final s in step!) s / 2];
      next = [for (var j = 0; j < p; j++) beta[j] + step[j]];
      ev = _fgEval(f, next);
      h++;
    }
    final change = (ev.ll - cur.ll).abs();
    beta = next;
    cur = ev;
    trace.add(tr('Itération $it : log-pseudo-vraisemblance = ${cur.ll.toStringAsFixed(10)}${h > 0 ? " ($h demi-pas)" : ""}', 'Iteration $it: log pseudo-likelihood = ${cur.ll.toStringAsFixed(10)}${h > 0 ? " ($h step-halving(s))" : ""}'));
    if (change <= 1e-13 * (1 + cur.ll.abs()) && cur.u.every((g) => g.abs() < 1e-8)) {
      converged = true;
      break;
    }
  }
  final hInv = invertSpd(cur.info);
  final cov = hInv == null ? Matrix(p, p) : _sandwich(f, beta, hInv);
  return FineGrayFit(beta, cov, cur.info, cur.ll, ll0, math.min(it, maxIter), converged, trace);
}

/// Variance sandwich de Fine et Gray (1999), comme crr : Ω⁻¹ [Σᵢ (ηᵢ + ψᵢ)(ηᵢ + ψᵢ)ᵀ] Ω⁻¹.
Matrix _sandwich(_FgData f, List<double> beta, Matrix hInv) {
  final n = f.n, p = f.p, m = f.ut.length;
  final s = _fgSums(f, beta);
  final r = s.r;
  final dL = [for (var k = 0; k < m; k++) f.nd[k] / s.s0[k]];
  final eb = [for (var k = 0; k < m; k++) [for (var a = 0; a < p; a++) s.s1[k][a] / s.s0[k]]];
  // Cumuls préfixes (ut ≤ X) et suffixes pondérés par Ĝ (ut > X) de dΛ et de Ē·dΛ.
  final c0 = List<double>.filled(m + 1, 0), d0 = List<double>.filled(m + 1, 0);
  final c1 = List<List<double>>.generate(m + 1, (_) => List<double>.filled(p, 0));
  final d1 = List<List<double>>.generate(m + 1, (_) => List<double>.filled(p, 0));
  for (var k = 0; k < m; k++) {
    c0[k + 1] = c0[k] + dL[k];
    for (var a = 0; a < p; a++) {
      c1[k + 1][a] = c1[k][a] + eb[k][a] * dL[k];
    }
  }
  for (var k = m - 1; k >= 0; k--) {
    d0[k] = d0[k + 1] + f.gUt[k] * dL[k];
    for (var a = 0; a < p; a++) {
      d1[k][a] = d1[k + 1][a] + eb[k][a] * f.gUt[k] * dL[k];
    }
  }
  // Nombre de temps ut ≤ v (recherche binaire).
  int upTo(double v) {
    var lo = 0, hi = m;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (f.ut[mid] <= v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int idxOf(double v) => upTo(v) - 1;
  final eta = List<List<double>>.generate(n, (_) => List<double>.filled(p, 0));
  for (var i = 0; i < n; i++) {
    final xi = f.x[i], ki = upTo(f.t[i]);
    final e = eta[i];
    if (f.code[i] == 1) {
      final k = idxOf(f.t[i]);
      for (var a = 0; a < p; a++) {
        e[a] += xi[a] - eb[k][a];
      }
    }
    for (var a = 0; a < p; a++) {
      e[a] -= r[i] * (xi[a] * c0[ki] - c1[ki][a]);
    }
    if (f.code[i] == 2) {
      for (var a = 0; a < p; a++) {
        e[a] -= r[i] / f.gX[i] * (xi[a] * d0[ki] - d1[ki][a]);
      }
    }
  }
  // ψ : temps de censure distincts u, q(u) = Σ_{concurrents X_j < u} r_j/Ĝ(X_j⁻)·Σ_{ut ≥ u} (Z_j − Ē)·Ĝ(ut⁻)·dΛ.
  final psi = List<List<double>>.generate(n, (_) => List<double>.filled(p, 0));
  final cens = <double>[];
  for (final i in f.order) {
    if (f.code[i] == 0 && (cens.isEmpty || cens.last != f.t[i])) cens.add(f.t[i]);
  }
  if (cens.isNotEmpty) {
    final qs = <List<double>>[], dLc = <double>[], piU = <double>[];
    var q = 0;
    var w0 = 0.0;
    final w1 = List<double>.filled(p, 0);
    for (final u in cens) {
      while (q < n && f.t[f.order[q]] < u) {
        final j = f.order[q];
        if (f.code[j] == 2) {
          final w = r[j] / f.gX[j];
          w0 += w;
          for (var a = 0; a < p; a++) {
            w1[a] += w * f.x[j][a];
          }
        }
        q++;
      }
      // Premier ut ≥ u.
      var k0 = 0;
      while (k0 < m && f.ut[k0] < u) {
        k0++;
      }
      qs.add([for (var a = 0; a < p; a++) w1[a] * d0[k0] - w0 * d1[k0][a]]);
      final atRisk = (n - q).toDouble();
      var c = 0;
      for (var z = q; z < n && f.t[f.order[z]] == u; z++) {
        if (f.code[f.order[z]] == 0) c++;
      }
      piU.add(atRisk);
      dLc.add(c / atRisk);
    }
    // Cumul de q(u)/π(u)·dΛc(u) sur u ≤ Xᵢ.
    final cum = List<List<double>>.generate(cens.length + 1, (_) => List<double>.filled(p, 0));
    for (var l = 0; l < cens.length; l++) {
      for (var a = 0; a < p; a++) {
        cum[l + 1][a] = cum[l][a] + qs[l][a] / piU[l] * dLc[l];
      }
    }
    for (var i = 0; i < n; i++) {
      var lo = 0, hi = cens.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (cens[mid] <= f.t[i]) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      for (var a = 0; a < p; a++) {
        psi[i][a] -= cum[lo][a];
      }
      if (f.code[i] == 0) {
        final l = lo - 1;
        for (var a = 0; a < p; a++) {
          psi[i][a] += qs[l][a] / piU[l];
        }
      }
    }
  }
  final sig = Matrix(p, p);
  for (var i = 0; i < n; i++) {
    for (var a = 0; a < p; a++) {
      final va = eta[i][a] + psi[i][a];
      for (var b = 0; b < p; b++) {
        sig.data[a * p + b] += va * (eta[i][b] + psi[i][b]);
      }
    }
  }
  return hInv * sig * hInv;
}

/// Analyse complète : sHR de Fine-Gray (variance robuste), et HR spécifiques de cause (Cox, autres événements censurés)
/// pour comparaison.
AnalysisResult fineGrayRegression(SurvivalDesign s, {double level = 0.95}) {
  final d = s.design;
  final code = [for (final v in s.status) v.round()];
  final nCause = code.where((c) => c == 1).length, nComp = code.where((c) => c == 2).length, nCens = code.where((c) => c == 0).length;
  if (nCause == 0) throw StatInputError('no_event', tr('Aucun événement d\'intérêt « ${s.eventLevel} ».', 'No event of interest "${s.eventLevel}".'));
  final fit = fitFineGray(d.x, s.time, code);
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
  var wald = 0.0;
  final inv = invertSpd(fit.cov);
  if (inv != null) {
    final v = inv.multiplyVector(fit.beta);
    for (var j = 0; j < p; j++) {
      wald += v[j] * fit.beta[j];
    }
  }
  // Cox spécifique de cause : événements concurrents traités comme des censures.
  final cs = fitCox(d.x, s.time, [for (final c in code) c == 1 ? 1.0 : 0.0]);
  final csCoefs = [
    for (var j = 0; j < p; j++)
      () {
        final se = math.sqrt(cs.cov.get(j, j));
        final w = cs.beta[j] / se;
        return Coefficient(d.columns[j], cs.beta[j], se, w, normalTwoSidedP(w), cs.beta[j] - z * se, cs.beta[j] + z * se);
      }()
  ];
  final pct = (level * 100).round();
  final alerts = <Alert>[...d.alerts];
  final huge = [for (final c in coefs) if (c.estimate.abs() > 10 || c.se > 100 || c.se.isNaN) c.name];
  if (!fit.converged || huge.isNotEmpty) {
    alerts.add(Alert('fg_divergence', Severity.critical,
        tr('Non-convergence ou coefficient divergent (${huge.join(', ')}) : les sHR concernés ne doivent pas être rapportés.', 'Non-convergence or diverging coefficient (${huge.join(', ')}): the sHRs involved must not be reported.')));
  }
  final epv = nCause / p;
  if (epv < 10) {
    alerts.add(Alert(epv < 5 ? 'epv_very_low' : 'epv_low', epv < 5 ? Severity.serious : Severity.caution,
        tr('$nCause événement(s) d\'intérêt pour $p paramètre(s) (EPV = ${fmt(epv)}) : risque de surajustement.', '$nCause event(s) of interest for $p parameter(s) (EPV = ${fmt(epv)}): risk of overfitting.')));
  }
  if (nComp == 0) {
    alerts.add(Alert('no_competing', Severity.info,
        tr('Aucun événement concurrent : le modèle de Fine-Gray se ramène à un modèle de Cox (Breslow).', 'No competing event: the Fine-Gray model reduces to a Cox model (Breslow).')));
  }
  final divergent = [for (var j = 0; j < p; j++) if (coefs[j].p < 0.05 && csCoefs[j].p < 0.05 && coefs[j].estimate.sign != csCoefs[j].estimate.sign) d.columns[j]];
  final main = coefs.first, mainCs = csCoefs.first;
  String hr(Coefficient c) => '${fmt(math.exp(c.estimate))} (${fmt(math.exp(c.lower))} – ${fmt(math.exp(c.upper))})';
  return AnalysisResult(
    methodId: 'fine_gray',
    methodName: tr('Risques concurrents : modèle de Fine-Gray (« ${s.eventLevel} »)', 'Competing risks: Fine-Gray model ("${s.eventLevel}")'),
    inputs: {'model': d.describe(), 'level': level, 'events': nCause, 'competing': nComp, 'censored': nCens},
    formula: tr(
        'Risque de sous-répartition λ₁(t | x) = λ₁₀(t)·exp(xᵀβ), lié à l\'incidence cumulée : F₁(t | x) = 1 − exp(−∫λ₁). Ensemble à risque : sujets suivis (poids 1) et sujets sortis par un événement concurrent, pondérés par Ĝ(t⁻)/Ĝ(X⁻) (Ĝ = Kaplan-Meier de la censure). '
            'Vraisemblance partielle pondérée (ex aequo de Breslow), Newton-Raphson ; sHR = exp(β) ; variance sandwich de Fine et Gray (part de l\'estimation de Ĝ comprise) ; IC et Wald par la loi normale. '
            'En regard : modèle de Cox spécifique de cause (événements concurrents censurés, Efron).',
        'Subdistribution hazard λ₁(t | x) = λ₁₀(t)·exp(xᵀβ), tied to the cumulative incidence: F₁(t | x) = 1 − exp(−∫λ₁). Risk set: subjects still followed (weight 1) and subjects removed by a competing event, weighted by Ĝ(t⁻)/Ĝ(X⁻) (Ĝ = Kaplan-Meier of censoring). '
            'Weighted partial likelihood (Breslow ties), Newton-Raphson; sHR = exp(β); Fine and Gray sandwich variance (including the estimation of Ĝ); normal CIs and Wald tests. '
            'Alongside: cause-specific Cox model (competing events censored, Efron).'),
    estimates: [
      for (final c in coefs) Estimate('sHR — ${c.name}', math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), level: level, pValue: c.p, se: c.se),
      for (final c in csCoefs)
        Estimate(tr('HR spécifique de cause — ${c.name}', 'Cause-specific HR — ${c.name}'), math.exp(c.estimate), lower: math.exp(c.lower), upper: math.exp(c.upper), level: level, pValue: c.p, se: c.se),
    ],
    statistics: {
      'n': d.n.toDouble(),
      'events': nCause.toDouble(),
      'competing': nComp.toDouble(),
      'censored': nCens.toDouble(),
      'loglik': fit.logLik,
      'loglik_null': fit.logLikNull,
      'wald': wald,
      'wald_p': chiSquareUpper(wald, p.toDouble()),
      'iterations': fit.iterations.toDouble(),
      for (var j = 0; j < p; j++) 'beta_${d.columns[j]}': fit.beta[j],
      for (var j = 0; j < p; j++) 'se_${d.columns[j]}': coefs[j].se,
      for (var j = 0; j < p; j++) 'cs_beta_${d.columns[j]}': cs.beta[j],
      for (var j = 0; j < p; j++) 'cs_se_${d.columns[j]}': csCoefs[j].se,
    },
    checks: [
      Check('convergence', tr('Convergence', 'Convergence'), (fit.converged && huge.isEmpty) ? CheckStatus.ok : CheckStatus.violated,
          tr('${fit.iterations} itération(s).', '${fit.iterations} iteration(s).')),
      Check('competing_present', tr('Événements concurrents présents', 'Competing events present'), nComp > 0 ? CheckStatus.ok : CheckStatus.warning,
          tr('$nComp événement(s) concurrent(s), $nCause d\'intérêt, $nCens censure(s).', '$nComp competing event(s), $nCause of interest, $nCens censored.')),
      Check('censoring', tr('Censure non informative (indépendante des deux types d\'événement)', 'Non-informative censoring (independent of both event types)'), CheckStatus.notAssessed,
          tr('Les poids Ĝ supposent une censure indépendante des covariables ; à argumenter (fin d\'étude administrative = cas favorable).', 'The Ĝ weights assume censoring independent of the covariates; to be argued (administrative end of study = favourable case).')),
      Check('proportional_subdistribution', tr('Proportionnalité des risques de sous-répartition', 'Proportional subdistribution hazards'), CheckStatus.notAssessed,
          tr('Hypothèse forte : comparer les courbes d\'incidence cumulée par groupe ; si elles se croisent, un sHR unique résume mal l\'effet.', 'Strong assumption: compare the cumulative incidence curves by group; if they cross, a single sHR summarizes the effect poorly.')),
    ],
    alerts: [
      ...alerts,
      if (divergent.isNotEmpty)
        Alert('shr_vs_cshr', Severity.info,
            tr('Sens opposés pour ${divergent.join(', ')} : le facteur agit sur la vitesse de survenue de l\'événement (HR spécifique de cause) dans un sens, mais sur la proportion de sujets qui le connaissent (sHR) dans l\'autre, via l\'événement concurrent. Les deux résultats sont justes ; ils répondent à deux questions différentes.',
                'Opposite directions for ${divergent.join(', ')}: the factor acts on the rate of the event (cause-specific HR) in one direction, but on the proportion of subjects who experience it (sHR) in the other, through the competing event. Both results are correct; they answer two different questions.')),
    ],
    tables: [
      ResultTable(tr('Modèle de Fine-Gray et Cox spécifique de cause', 'Fine-Gray model and cause-specific Cox'), [
        tr('Terme', 'Term'), 'sHR', tr('IC $pct %', '$pct% CI'), 'p', tr('HR spécifique de cause', 'Cause-specific HR'), tr('IC $pct %', '$pct% CI'), 'p'
      ], [
        for (var j = 0; j < p; j++)
          [
            d.columns[j],
            fmt(math.exp(coefs[j].estimate)), '${fmt(math.exp(coefs[j].lower))} – ${fmt(math.exp(coefs[j].upper))}', fmtP(coefs[j].p),
            fmt(math.exp(csCoefs[j].estimate)), '${fmt(math.exp(csCoefs[j].lower))} – ${fmt(math.exp(csCoefs[j].upper))}', fmtP(csCoefs[j].p),
          ]
      ]),
      coefficientTable(coefs, effectLabel: 'sHR', exponentiate: true, level: level),
      ResultTable(tr('Test global', 'Global test'), ['Test', 'χ²', tr('ddl', 'df'), 'p'], [
        [tr('Wald (variance robuste)', 'Wald (robust variance)'), fmt(wald), '$p', fmtP(chiSquareUpper(wald, p.toDouble()))],
      ]),
      ResultTable(tr('Codage et observations', 'Coding and observations'), [tr('Élément', 'Item'), tr('Détail', 'Detail')], [
        [tr('Modèle', 'Model'), d.formula],
        [tr('Observations / événements d\'intérêt / concurrents / censurés', 'Observations / events of interest / competing / censored'), '${d.n} / $nCause / $nComp / $nCens'],
        for (final c in d.codingNotes) [tr('Codage', 'Coding'), c],
      ]),
    ],
    log: fit.trace,
    interpretation: Interpretation(
      whyThisMethod: tr(
          'Un événement concurrent (p. ex. un décès) empêche l\'événement d\'intérêt de survenir : le traiter comme une censure surestime l\'incidence. Le modèle de Fine-Gray modélise directement l\'incidence cumulée (la proportion de sujets qui connaissent l\'événement), utile pour le pronostic ; le Cox spécifique de cause décrit la vitesse de survenue chez les sujets encore exposés, utile pour l\'étiologie.',
          'A competing event (e.g. death) prevents the event of interest from occurring: treating it as censoring overestimates the incidence. The Fine-Gray model directly models the cumulative incidence (the proportion of subjects who experience the event), useful for prognosis; the cause-specific Cox model describes the rate of occurrence among subjects still exposed, useful for aetiology.'),
      whatItMeans: tr(
          '« ${main.name} » : sHR = ${hr(main)}, ${fmtP(main.p)} (incidence cumulée de « ${s.eventLevel} ») ; HR spécifique de cause = ${hr(mainCs)}, ${fmtP(mainCs.p)}. $nCause événement(s) d\'intérêt, $nComp concurrent(s).',
          '"${main.name}": sHR = ${hr(main)}, ${fmtP(main.p)} (cumulative incidence of "${s.eventLevel}"); cause-specific HR = ${hr(mainCs)}, ${fmtP(mainCs.p)}. $nCause event(s) of interest, $nComp competing.'),
      notJustified: tr(
          'Lire un sHR comme un rapport de taux instantanés chez les sujets à risque, ou comme un effet biologique sur l\'événement ; ignorer l\'événement concurrent (1 − Kaplan-Meier) ; ne rapporter qu\'un des deux modèles quand ils divergent.',
          'Reading an sHR as a ratio of instantaneous rates among subjects at risk, or as a biological effect on the event; ignoring the competing event (1 − Kaplan-Meier); reporting only one of the two models when they disagree.'),
    ),
  );
}
