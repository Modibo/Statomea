/// Séries chronologiques interrompues : régression segmentée (Bernal, Cummins et Gasparrini 2017).
///  - y_t = β₀ + β₁·t + β₂·après_t + β₃·(t − T₀)·après_t, après_t = 1 si t ≥ T₀ : β₂ = changement de niveau à T₀,
///    β₃ = changement de pente ;
///  - issue continue : moindres carrés, ES robustes à l'autocorrélation de Newey-West (noyau de Bartlett, retard L) ;
///    Durbin-Watson et autocorrélation des résidus au retard 1 ;
///  - comptages : Poisson avec offset log(population), dispersion quasi-Poisson ; rapports de taux ;
///  - effet à h périodes après T₀ : β₂ + β₃·h (IC de Wald) ; contrefactuel = tendance antérieure prolongée.
/// Validé contre validation/r/56_series_interrompues.R (stats::lm, glm quasipoisson, sandwich::NeweyWest).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../math/distributions.dart';
import '../math/matrix.dart';
import '../model/result.dart';

enum SeriesFamily { gaussian, poisson }

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// (XᵀWX)⁻¹ pour 4 colonnes.
Matrix _bread(List<List<double>> x, List<double> w) {
  final p = x.first.length;
  final m = Matrix(p, p);
  for (var i = 0; i < x.length; i++) {
    for (var a = 0; a < p; a++) {
      for (var b = 0; b < p; b++) {
        m.set(a, b, m.get(a, b) + w[i] * x[i][a] * x[i][b]);
      }
    }
  }
  final inv = invertSpd(m);
  if (inv == null) throw StatInputError('its_singular', tr('Série dégénérée (périodes avant ou après l\'intervention en nombre insuffisant).', 'Degenerate series (too few periods before or after the intervention).'));
  return inv;
}

AnalysisResult interruptedTimeSeries(List<double?> timeRaw, List<double?> yRaw, double interruption,
    {SeriesFamily family = SeriesFamily.gaussian, List<double?>? population, int? lag, double? horizon, double level = 0.95, String outcome = 'y', String timeName = 't', String unit = ''}) {
  final t = <double>[], y = <double>[], off = <double>[];
  for (var i = 0; i < math.min(timeRaw.length, yRaw.length); i++) {
    final ti = timeRaw[i], yi = yRaw[i], pi = population?[i];
    if (ti == null || yi == null || !ti.isFinite || !yi.isFinite) continue;
    if (population != null && (pi == null || pi <= 0)) continue;
    if (family == SeriesFamily.poisson && (yi < 0 || yi != yi.roundToDouble())) {
      throw StatInputError('its_counts', tr('L\'issue d\'un modèle de Poisson doit être un comptage entier ≥ 0.', 'The outcome of a Poisson model must be an integer count ≥ 0.'));
    }
    t.add(ti);
    y.add(yi);
    off.add(population == null ? 0 : math.log(pi!));
  }
  // Ordre chronologique (indispensable pour l'autocorrélation).
  final ord = List<int>.generate(t.length, (i) => i)..sort((a, b) => t[a].compareTo(t[b]));
  final tt = [for (final i in ord) t[i]], yy = [for (final i in ord) y[i]], oo = [for (final i in ord) off[i]];
  final n = tt.length;
  final before = tt.where((v) => v < interruption).length, after = n - before;
  if (before < 3 || after < 3) {
    throw StatInputError('its_periods', tr('Au moins 3 périodes avant et 3 après l\'intervention sont requises (8 à 12 de chaque côté recommandées).', 'At least 3 periods before and 3 after the intervention are required (8 to 12 on each side recommended).'));
  }
  final x = [for (final v in tt) [1.0, v, v >= interruption ? 1.0 : 0.0, v >= interruption ? v - interruption : 0.0]];
  const p = 4;
  final names = [tr('Constante', 'Intercept'), tr('Tendance avant ($timeName)', 'Pre-intervention trend ($timeName)'), tr('Changement de niveau', 'Level change'), tr('Changement de pente', 'Slope change')];
  late List<double> beta;
  late Matrix v;
  final stats = <String, double>{'n': n.toDouble(), 'before': before.toDouble(), 'after': after.toDouble()};
  final l = lag ?? (math.pow(n, 0.25).floor());
  if (family == SeriesFamily.gaussian) {
    final ones = List<double>.filled(n, 1);
    final b = _bread(x, ones);
    beta = b.multiplyVector([for (var a = 0; a < p; a++) _dot([for (final r in x) r[a]], yy)]);
    final e = [for (var i = 0; i < n; i++) yy[i] - _dot(x[i], beta)];
    // Newey-West : Γ₀ + Σₗ (1 − l/(L+1))(Γₗ + Γₗᵀ), Γₗ = Σₜ uₜ uₜ₋ₗᵀ, uₜ = xₜ eₜ.
    final u = [for (var i = 0; i < n; i++) [for (final c in x[i]) c * e[i]]];
    final meat = Matrix(p, p);
    for (var k = 0; k <= l; k++) {
      final w = k == 0 ? 1.0 : 1 - k / (l + 1);
      for (var i = k; i < n; i++) {
        for (var a = 0; a < p; a++) {
          for (var c = 0; c < p; c++) {
            final g = u[i][a] * u[i - k][c];
            meat.set(a, c, meat.get(a, c) + w * g);
            if (k > 0) meat.set(c, a, meat.get(c, a) + w * g); // Γₗ + Γₗᵀ
          }
        }
      }
    }
    v = b * meat * b;
    final rss = e.fold(0.0, (s, r) => s + r * r);
    var dw = 0.0;
    for (var i = 1; i < n; i++) {
      dw += (e[i] - e[i - 1]) * (e[i] - e[i - 1]);
    }
    final em = e.fold(0.0, (s, r) => s + r) / n;
    var num = 0.0;
    for (var i = 0; i < n - 1; i++) {
      num += (e[i] - em) * (e[i + 1] - em);
    }
    final ac1 = num / e.fold(0.0, (s, r) => s + (r - em) * (r - em));
    stats.addAll({'dw': dw / rss, 'ac1': ac1, 'sigma': math.sqrt(rss / (n - p)), 'lag': l.toDouble()});
    for (var a = 0; a < p; a++) {
      stats['se_ols_$a'] = math.sqrt(rss / (n - p) * b.get(a, a));
    }
  } else {
    // IRLS de Poisson avec offset, puis dispersion de Pearson (quasi-Poisson).
    beta = [math.log(math.max(1e-8, yy.fold(0.0, (s, r) => s + r) / oo.fold(0.0, (s, r) => s + math.exp(r)))), 0, 0, 0];
    for (var it = 0; it < 100; it++) {
      final eta = [for (var i = 0; i < n; i++) _dot(x[i], beta) + oo[i]];
      final mu = [for (final e in eta) math.exp(e)];
      final z = [for (var i = 0; i < n; i++) eta[i] - oo[i] + (yy[i] - mu[i]) / mu[i]];
      final b = _bread(x, mu);
      final next = b.multiplyVector([for (var a = 0; a < p; a++) _dot([for (var i = 0; i < n; i++) x[i][a] * mu[i]], z)]);
      final delta = [for (var a = 0; a < p; a++) (next[a] - beta[a]).abs()].reduce(math.max);
      beta = next;
      if (delta < 1e-12) break;
    }
    final mu = [for (var i = 0; i < n; i++) math.exp(_dot(x[i], beta) + oo[i])];
    final phi = [for (var i = 0; i < n; i++) (yy[i] - mu[i]) * (yy[i] - mu[i]) / mu[i]].fold(0.0, (s, r) => s + r) / (n - p);
    final b = _bread(x, mu);
    v = Matrix(p, p);
    for (var a = 0; a < p; a++) {
      for (var c = 0; c < p; c++) {
        v.set(a, c, phi * b.get(a, c));
      }
    }
    stats['dispersion'] = phi;
  }
  final tq = tQuantile(1 - (1 - level) / 2, n - p.toDouble());
  final pct = (level * 100).round();
  final exp = family == SeriesFamily.poisson;
  final rows = <List<String>>[];
  final estimates = <Estimate>[];
  for (var a = 0; a < p; a++) {
    final se = math.sqrt(v.get(a, a)), tv = beta[a] / se, pv = tTwoSidedP(tv, n - p.toDouble());
    stats['beta_$a'] = beta[a];
    stats['se_$a'] = se;
    stats['p_$a'] = pv;
    final lo = beta[a] - tq * se, hi = beta[a] + tq * se;
    rows.add([names[a], fmt(beta[a], digits: 4), fmt(se, digits: 3), if (exp) a == 0 ? '—' : fmt(math.exp(beta[a])), exp ? (a == 0 ? '—' : '${fmt(math.exp(lo))} – ${fmt(math.exp(hi))}') : '${fmt(lo)} – ${fmt(hi)}', fmtP(pv)]);
    if (a >= 2) estimates.add(Estimate(exp ? '${names[a]} (${tr('rapport de taux', 'rate ratio')})' : names[a], exp ? math.exp(beta[a]) : beta[a], lower: exp ? math.exp(lo) : lo, upper: exp ? math.exp(hi) : hi, se: se, pValue: pv, level: level));
  }
  // Effet à l'horizon h (par défaut : dernière période observée).
  final h = horizon ?? (tt.last - interruption);
  final g = [0.0, 0.0, 1.0, h];
  final eff = _dot(g, beta);
  final effSe = math.sqrt(_dot(g, v.multiplyVector(g)));
  final effLo = eff - tq * effSe, effHi = eff + tq * effSe;
  stats.addAll({'effect': eff, 'effect_se': effSe, 'horizon': h});
  estimates.add(Estimate(tr('Effet à ${fmt(h)} période(s) après l\'intervention', 'Effect ${fmt(h)} period(s) after the intervention') + (exp ? tr(' (rapport de taux)', ' (rate ratio)') : ''),
      exp ? math.exp(eff) : eff, lower: exp ? math.exp(effLo) : effLo, upper: exp ? math.exp(effHi) : effHi, se: effSe, level: level, pValue: tTwoSidedP(eff / effSe, n - p.toDouble())));
  // Figure : observé, ajusté, contrefactuel (tendance antérieure prolongée), sur l'échelle de l'issue (taux si offset).
  final scale = population == null ? 1.0 : 1e5;
  double fit(List<double> r, int i, {bool counter = false}) {
    final lin = counter ? beta[0] + beta[1] * r[1] : _dot(r, beta);
    return exp ? math.exp(lin) * (population == null ? math.exp(oo[i]) : scale) : lin;
  }

  final obs = [for (var i = 0; i < n; i++) exp && population != null ? yy[i] / math.exp(oo[i]) * scale : yy[i]];
  final alerts = <Alert>[];
  if (family == SeriesFamily.gaussian && (stats['ac1']!.abs() > 0.3)) {
    alerts.add(Alert('its_autocorrelation', Severity.caution,
        tr('Autocorrélation des résidus au retard 1 = ${fmt(stats['ac1']!)} (Durbin-Watson ${fmt(stats['dw']!)}) : les ES de Newey-West en tiennent compte ; vérifier la saisonnalité.', 'Lag-1 residual autocorrelation = ${fmt(stats['ac1']!)} (Durbin-Watson ${fmt(stats['dw']!)}): Newey-West SEs account for it; check for seasonality.')));
  }
  if (exp && stats['dispersion']! > 1.5) {
    alerts.add(Alert('its_overdispersion', Severity.info, tr('Surdispersion (φ = ${fmt(stats['dispersion']!)}) : prise en compte par le modèle quasi-Poisson.', 'Overdispersion (φ = ${fmt(stats['dispersion']!)}): accounted for by the quasi-Poisson model.')));
  }
  if (before < 8 || after < 8) {
    alerts.add(Alert('its_short', Severity.caution, tr('$before période(s) avant et $after après : une série courte estime mal la tendance et l\'autocorrélation (8 à 12 de chaque côté recommandées).', '$before period(s) before and $after after: a short series estimates the trend and autocorrelation poorly (8 to 12 on each side recommended).')));
  }
  final u = unit.isEmpty ? '' : ' $unit';
  return AnalysisResult(
    methodId: 'interrupted_time_series',
    methodName: tr('Série chronologique interrompue (régression segmentée, ${exp ? 'quasi-Poisson' : 'Newey-West'})', 'Interrupted time series (segmented regression, ${exp ? 'quasi-Poisson' : 'Newey-West'})'),
    inputs: {'n': n, 'interruption': interruption, 'family': family.name, 'lag': l, 'horizon': h, 'offset': population != null, 'level': level, 'outcome': outcome},
    formula: exp
        ? tr('log E[y_t] = log(population_t) + β₀ + β₁·t + β₂·après_t + β₃·(t − T₀)·après_t ; IRLS de Poisson, ES multipliés par √φ (dispersion de Pearson, quasi-Poisson) ; rapports de taux exp(β).',
            'log E[y_t] = log(population_t) + β₀ + β₁·t + β₂·after_t + β₃·(t − T₀)·after_t; Poisson IRLS, SEs multiplied by √φ (Pearson dispersion, quasi-Poisson); rate ratios exp(β).')
        : tr('y_t = β₀ + β₁·t + β₂·après_t + β₃·(t − T₀)·après_t + ε_t ; moindres carrés ; ES de Newey-West (Bartlett, retard L = $l) : (XᵀX)⁻¹[Γ₀ + Σₗ (1 − l/(L+1))(Γₗ + Γₗᵀ)](XᵀX)⁻¹ ; effet à h : β₂ + β₃·h.',
            'y_t = β₀ + β₁·t + β₂·after_t + β₃·(t − T₀)·after_t + ε_t; least squares; Newey-West SEs (Bartlett, lag L = $l): (XᵀX)⁻¹[Γ₀ + Σₗ (1 − l/(L+1))(Γₗ + Γₗᵀ)](XᵀX)⁻¹; effect at h: β₂ + β₃·h.'),
    estimates: estimates,
    statistics: stats,
    checks: [
      Check('its_periods', tr('Assez de périodes de chaque côté (≥ 8)', 'Enough periods on each side (≥ 8)'), before >= 8 && after >= 8 ? CheckStatus.ok : CheckStatus.warning, tr('$before avant, $after après.', '$before before, $after after.')),
      if (!exp) Check('its_autocorrelation', tr('Autocorrélation des résidus prise en compte', 'Residual autocorrelation accounted for'), CheckStatus.ok, 'DW = ${fmt(stats['dw']!)}, r₁ = ${fmt(stats['ac1']!)}.'),
      Check('its_cointervention', tr('Pas d\'autre changement simultané (co-intervention, codage, population)', 'No other simultaneous change (co-intervention, coding, population)'), CheckStatus.notAssessed,
          tr('La conception ne contrôle pas un autre événement survenu à T₀ ; envisager une série témoin.', 'The design does not control for another event occurring at T₀; consider a control series.')),
      Check('its_seasonality', tr('Saisonnalité examinée', 'Seasonality examined'), CheckStatus.notAssessed, tr('Avec des données mensuelles, ajouter des termes saisonniers si un cycle est visible.', 'With monthly data, add seasonal terms if a cycle is visible.')),
    ],
    alerts: alerts,
    tables: [
      ResultTable(tr('Régression segmentée (T₀ = ${fmt(interruption)})', 'Segmented regression (T₀ = ${fmt(interruption)})'),
          [tr('Terme', 'Term'), 'β', exp ? tr('ES (quasi-Poisson)', 'SE (quasi-Poisson)') : tr('ES (Newey-West)', 'SE (Newey-West)'), if (exp) tr('Rapport de taux', 'Rate ratio'), tr('IC $pct %', '$pct% CI'), 'p'], rows),
    ],
    figures: {
      'its': {
        'time': tt,
        'observed': obs,
        'fitted': [for (var i = 0; i < n; i++) fit(x[i], i)],
        'counterfactual': [for (var i = 0; i < n; i++) fit(x[i], i, counter: true)],
        'interruption': interruption,
        'yLabel': population != null && exp ? tr('$outcome pour 100 000', '$outcome per 100,000') : outcome,
        'xLabel': timeName,
      }
    },
    interpretation: Interpretation(
      whyThisMethod: tr('Une série chronologique interrompue compare l\'évolution observée après une intervention à la tendance antérieure prolongée, en tenant compte de la tendance et de l\'autocorrélation ; c\'est l\'un des plans quasi expérimentaux les plus solides sans groupe témoin.',
          'An interrupted time series compares the trajectory observed after an intervention with the extended prior trend, accounting for trend and autocorrelation; it is one of the strongest quasi-experimental designs without a control group.'),
      whatItMeans: exp
          ? tr('Changement de niveau : taux × ${fmt(math.exp(beta[2]))} à T₀ ; changement de pente : × ${fmt(math.exp(beta[3]))} par période. À ${fmt(h)} période(s), taux × ${fmt(math.exp(eff))} (IC ${fmt(math.exp(effLo))} à ${fmt(math.exp(effHi))}) par rapport à la tendance prolongée.',
              'Level change: rate × ${fmt(math.exp(beta[2]))} at T₀; slope change: × ${fmt(math.exp(beta[3]))} per period. At ${fmt(h)} period(s), rate × ${fmt(math.exp(eff))} (CI ${fmt(math.exp(effLo))} to ${fmt(math.exp(effHi))}) compared with the extended trend.')
          : tr('Changement de niveau ${fmt(beta[2])}$u à T₀, changement de pente ${fmt(beta[3])}$u par période. À ${fmt(h)} période(s), écart de ${fmt(eff)}$u (IC ${fmt(effLo)} à ${fmt(effHi)}) par rapport à la tendance prolongée.',
              'Level change ${fmt(beta[2])}$u at T₀, slope change ${fmt(beta[3])}$u per period. At ${fmt(h)} period(s), difference of ${fmt(eff)}$u (CI ${fmt(effLo)} to ${fmt(effHi)}) compared with the extended trend.'),
      notJustified: tr('Attribuer le changement à l\'intervention sans exclure une co-intervention ou un changement de mesure ; extrapoler la tendance contrefactuelle loin après T₀ ; comparer seulement les moyennes avant et après.',
          'Attributing the change to the intervention without ruling out a co-intervention or a change in measurement; extrapolating the counterfactual trend far beyond T₀; comparing only the before and after means.'),
    ),
  );
}
