/// Figures vectorielles (SVG) produites par le moteur pour les exports :
/// forest plot, courbe de calibration, courbe de décision, Bland-Altman.
/// Rendu sobre, imprimable en noir et blanc, sans dépendance externe.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../model/result.dart';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _n(double v) => v.toStringAsFixed(2);

/// Famille de police des figures. Liste CSS par défaut (export HTML) ;
/// l'application passe « NotoSans » (police embarquée), car flutter_svg
/// n'interprète pas les listes de familles.
const String defaultSvgFont = 'NotoSans, Helvetica, Arial, sans-serif';
String _font(String family) => "font-family='$family'";

/// Forest plot à partir de `figures['forest']` d'une métaanalyse.
String forestPlotSvg(Map<String, Object?> forest, {String? measureLabel, String font = defaultSvgFont}) {
  measureLabel ??= switch (forest['measure']) {
    'or' => 'OR',
    'rr' => 'RR',
    'rd' => tr('DR', 'RD'),
    'md' => tr('DM', 'MD'),
    'smd' => tr('DMS', 'SMD'),
    _ => tr('Effet', 'Effect'),
  };
  final studies = (forest['studies'] as List).cast<Map>();
  final pooled = (forest['pooled'] as Map).cast<String, Object?>();
  final pred = (forest['prediction'] as Map?)?.cast<String, Object?>();
  final ratio = forest['ratio'] == true;
  final nullV = (forest['nullValue'] as num).toDouble();
  double sc(double v) => ratio ? math.log(v) : v;
  final all = <double>[
    for (final s in studies) ...[(s['lower'] as num).toDouble(), (s['upper'] as num).toDouble()],
    (pooled['lower'] as num).toDouble(),
    (pooled['upper'] as num).toDouble(),
    if (pred != null) ...[(pred['lower'] as num).toDouble(), (pred['upper'] as num).toDouble()],
    nullV,
  ].where((v) => v.isFinite && (!ratio || v > 0)).map(sc).toList();
  var lo = all.reduce(math.min), hi = all.reduce(math.max);
  final pad = (hi - lo) * 0.05 + 1e-9;
  lo -= pad;
  hi += pad;
  const left = 230.0, plotW = 300.0, right = 200.0, rowH = 22.0, top = 40.0;
  final rows = studies.length + 3;
  final h = top + rows * rowH + 50;
  const w = left + plotW + right;
  double x(double v) => left + (sc(v) - lo) / (hi - lo) * plotW;
  final b = StringBuffer()
    ..writeln("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${_n(w)} ${_n(h)}' width='${_n(w)}' height='${_n(h)}' ${_font(font)} font-size='12'>")
    ..writeln("<rect width='100%' height='100%' fill='white'/>")
    ..writeln("<text x='8' y='22' font-weight='bold'>${tr('Étude', 'Study')}</text>")
    ..writeln("<text x='${_n(left + plotW + 10)}' y='22' font-weight='bold'>${_esc(measureLabel)} [${tr('IC 95 %', '95% CI')}]</text>")
    ..writeln("<text x='${_n(left + plotW + 150)}' y='22' font-weight='bold'>${tr('Poids', 'Weight')}</text>");
  final maxW = studies.map((s) => (s['weight'] as num).toDouble()).fold(0.0, math.max);
  for (var i = 0; i < studies.length; i++) {
    final s = studies[i];
    final y = top + i * rowH + rowH / 2;
    final est = (s['est'] as num).toDouble(), l = (s['lower'] as num).toDouble(), u = (s['upper'] as num).toDouble();
    final wt = (s['weight'] as num).toDouble();
    final size = 3 + 7 * math.sqrt(wt / (maxW == 0 ? 1 : maxW));
    b
      ..writeln("<text x='8' y='${_n(y + 4)}'>${_esc(s['label'].toString())}</text>")
      ..writeln("<line x1='${_n(math.max(left, x(l)))}' x2='${_n(math.min(left + plotW, x(u)))}' y1='${_n(y)}' y2='${_n(y)}' stroke='black'/>")
      ..writeln("<rect x='${_n(x(est) - size / 2)}' y='${_n(y - size / 2)}' width='${_n(size)}' height='${_n(size)}' fill='#1f4e79'/>")
      ..writeln("<text x='${_n(left + plotW + 10)}' y='${_n(y + 4)}'>${fmt(est)} [${fmt(l)}${tr(' ; ', ', ')}${fmt(u)}]</text>")
      ..writeln("<text x='${_n(left + plotW + 150)}' y='${_n(y + 4)}'>${fmtFixed(wt, 1)} %</text>");
  }
  final yp = top + (studies.length + 1) * rowH;
  final pe = (pooled['est'] as num).toDouble(), pl = (pooled['lower'] as num).toDouble(), pu = (pooled['upper'] as num).toDouble();
  b
    ..writeln("<polygon points='${_n(x(pl))},${_n(yp)} ${_n(x(pe))},${_n(yp - 7)} ${_n(x(pu))},${_n(yp)} ${_n(x(pe))},${_n(yp + 7)}' fill='#c0504d'/>")
    ..writeln("<text x='8' y='${_n(yp + 4)}' font-weight='bold'>${tr('Combiné', 'Pooled')}</text>")
    ..writeln("<text x='${_n(left + plotW + 10)}' y='${_n(yp + 4)}' font-weight='bold'>${fmt(pe)} [${fmt(pl)}${tr(' ; ', ', ')}${fmt(pu)}]</text>")
    ..writeln("<text x='8' y='${_n(yp + 18)}' font-size='10' fill='#444'>${_esc(pooled['label'].toString())}</text>");
  if (pred != null) {
    final yq = yp + rowH * 1.4;
    final ql = (pred['lower'] as num).toDouble(), qu = (pred['upper'] as num).toDouble();
    b
      ..writeln("<line x1='${_n(math.max(left, x(ql)))}' x2='${_n(math.min(left + plotW, x(qu)))}' y1='${_n(yq)}' y2='${_n(yq)}' stroke='#c0504d' stroke-dasharray='4 3' stroke-width='2'/>")
      ..writeln("<text x='8' y='${_n(yq + 4)}' font-size='11'>${tr('Intervalle de prédiction', 'Prediction interval')}</text>")
      ..writeln("<text x='${_n(left + plotW + 10)}' y='${_n(yq + 4)}' font-size='11'>[${fmt(ql)}${tr(' ; ', ', ')}${fmt(qu)}]</text>");
  }
  final axisY = h - 30;
  b
    ..writeln("<line x1='${_n(x(nullV))}' x2='${_n(x(nullV))}' y1='${_n(top - 6)}' y2='${_n(axisY)}' stroke='#888' stroke-dasharray='3 3'/>")
    ..writeln("<line x1='$left' x2='${_n(left + plotW)}' y1='${_n(axisY)}' y2='${_n(axisY)}' stroke='black'/>");
  final ticks = ratio ? [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100] : _niceTicks(lo, hi);
  for (final t in ticks) {
    final tv = t.toDouble();
    if (ratio && (math.log(tv) < lo || math.log(tv) > hi)) continue;
    if (!ratio && (tv < lo || tv > hi)) continue;
    b
      ..writeln("<line x1='${_n(x(tv))}' x2='${_n(x(tv))}' y1='${_n(axisY)}' y2='${_n(axisY + 4)}' stroke='black'/>")
      ..writeln("<text x='${_n(x(tv))}' y='${_n(axisY + 16)}' text-anchor='middle' font-size='10'>${fmt(tv, digits: 2)}</text>");
  }
  b
    ..writeln("<text x='${_n(left)}' y='${_n(h - 2)}' font-size='10' fill='#444'>&lt; ${tr('plus faible dans le groupe 1', 'lower in group 1')}</text>")
    ..writeln("<text x='${_n(left + plotW)}' y='${_n(h - 2)}' font-size='10' fill='#444' text-anchor='end'>${tr('plus élevé dans le groupe 1', 'higher in group 1')} &gt;</text>")
    ..writeln('</svg>');
  return b.toString();
}

List<double> _niceTicks(double lo, double hi) {
  final span = hi - lo;
  final step0 = math.pow(10, (math.log(span / 5) / math.ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].map((m) => m * step0).firstWhere((s) => span / s <= 6, orElse: () => 10 * step0);
  final out = <double>[];
  for (var t = (lo / step).ceil() * step; t <= hi + 1e-12; t += step) {
    out.add(double.parse(t.toStringAsFixed(10)));
  }
  return out;
}

String _axes(StringBuffer b, double l, double t, double w, double h, String xl, String yl, List<double> xt, List<double> yt,
    double Function(double) x, double Function(double) y) {
  b
    ..writeln("<rect x='$l' y='$t' width='$w' height='$h' fill='none' stroke='black'/>")
    ..writeln("<text x='${_n(l + w / 2)}' y='${_n(t + h + 34)}' text-anchor='middle'>${_esc(xl)}</text>")
    ..writeln("<text x='14' y='${_n(t + h / 2)}' text-anchor='middle' transform='rotate(-90 14 ${_n(t + h / 2)})'>${_esc(yl)}</text>");
  for (final v in xt) {
    b.writeln("<text x='${_n(x(v))}' y='${_n(t + h + 16)}' text-anchor='middle' font-size='10'>${fmt(v, digits: 2)}</text>");
  }
  for (final v in yt) {
    b.writeln("<text x='${_n(l - 6)}' y='${_n(y(v) + 3)}' text-anchor='end' font-size='10'>${fmt(v, digits: 2)}</text>");
  }
  return '';
}

/// Courbe de calibration (groupes de risque, IC de Wilson), diagonale idéale.
String calibrationSvg(List<Map> groups, {String font = defaultSvgFont}) {
  const l = 60.0, t = 20.0, w = 320.0, h = 320.0;
  final maxV = math.max(0.1, groups.map((g) => math.max((g['predicted'] as num).toDouble(), (g['upper'] as num).toDouble())).fold(0.0, math.max));
  final top = (maxV * 10).ceil() / 10;
  double x(double v) => l + v / top * w;
  double y(double v) => t + h - v / top * h;
  final ticks = [for (var i = 0; i <= 5; i++) top * i / 5];
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 420 400' width='420' height='400' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Risque prédit', 'Predicted risk'), tr('Proportion observée', 'Observed proportion'), ticks, ticks, x, y);
  b.writeln("<line x1='${_n(x(0))}' y1='${_n(y(0))}' x2='${_n(x(top))}' y2='${_n(y(top))}' stroke='#888' stroke-dasharray='4 3'/>");
  final pts = <String>[];
  for (final g in groups) {
    final px = x((g['predicted'] as num).toDouble()), py = y((g['observed'] as num).toDouble());
    pts.add('${_n(px)},${_n(py)}');
    b
      ..writeln("<line x1='${_n(px)}' x2='${_n(px)}' y1='${_n(y((g['lower'] as num).toDouble()))}' y2='${_n(y((g['upper'] as num).toDouble()))}' stroke='#1f4e79'/>")
      ..writeln("<circle cx='${_n(px)}' cy='${_n(py)}' r='4' fill='#1f4e79'/>");
  }
  b
    ..writeln("<polyline points='${pts.join(' ')}' fill='none' stroke='#1f4e79'/>")
    ..writeln('</svg>');
  return b.toString();
}

/// Courbe de décision : bénéfice net du modèle, « traiter tous », « aucun ».
String decisionCurveSvg(List<Map> rows, {String font = defaultSvgFont}) {
  const l = 60.0, t = 20.0, w = 320.0, h = 260.0;
  final maxT = rows.map((r) => (r['threshold'] as num).toDouble()).fold(0.0, math.max);
  final maxNb = rows.map((r) => math.max((r['model'] as num).toDouble(), (r['treatAll'] as num).toDouble())).fold(0.01, math.max);
  final minNb = -0.05 * maxNb;
  double x(double v) => l + v / maxT * w;
  double y(double v) => t + h - (v.clamp(minNb, maxNb) - minNb) / (maxNb - minNb) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 420 340' width='420' height='340' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Seuil de probabilité', 'Probability threshold'), tr('Bénéfice net', 'Net benefit'), [for (var i = 0; i <= 5; i++) maxT * i / 5], [0, maxNb / 2, maxNb], x, y);
  String line(String key) => rows.map((r) => '${_n(x((r['threshold'] as num).toDouble()))},${_n(y((r[key] as num).toDouble()))}').join(' ');
  b
    ..writeln("<polyline points='${line('model')}' fill='none' stroke='#1f4e79' stroke-width='2'/>")
    ..writeln("<polyline points='${line('treatAll')}' fill='none' stroke='#c0504d' stroke-dasharray='5 3'/>")
    ..writeln("<line x1='${_n(x(0))}' x2='${_n(x(maxT))}' y1='${_n(y(0))}' y2='${_n(y(0))}' stroke='black'/>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + 14)}' text-anchor='end' fill='#1f4e79'>${tr('Modèle', 'Model')}</text>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + 28)}' text-anchor='end' fill='#c0504d'>${tr('Traiter tous', 'Treat all')}</text>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + 42)}' text-anchor='end'>${tr('Ne traiter personne', 'Treat none')}</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Graphique de Bland-Altman.
String blandAltmanSvg(Map ba, {String font = defaultSvgFont}) {
  final m = (ba['mean'] as List).map((e) => (e as num).toDouble()).toList();
  final d = (ba['diff'] as List).map((e) => (e as num).toDouble()).toList();
  final bias = (ba['bias'] as num).toDouble(), lo = (ba['loaLow'] as num).toDouble(), hi = (ba['loaHigh'] as num).toDouble();
  const l = 60.0, t = 20.0, w = 320.0, h = 240.0;
  final xmin = m.reduce(math.min), xmax = m.reduce(math.max);
  final ymin = math.min(d.reduce(math.min), lo) * 1.1, ymax = math.max(d.reduce(math.max), hi) * 1.1;
  double x(double v) => l + (v - xmin) / (xmax - xmin == 0 ? 1 : xmax - xmin) * w;
  double y(double v) => t + h - (v - ymin) / (ymax - ymin == 0 ? 1 : ymax - ymin) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 420 320' width='420' height='320' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Moyenne des deux méthodes', 'Mean of the two methods'), tr('Différence', 'Difference'), _niceTicks(xmin, xmax), [lo, bias, hi], x, y);
  for (var i = 0; i < m.length; i++) {
    b.writeln("<circle cx='${_n(x(m[i]))}' cy='${_n(y(d[i]))}' r='3' fill='#1f4e79'/>");
  }
  for (final (v, lab, dash) in [(bias, tr('Biais', 'Bias'), ''), (lo, tr('LdA inf.', 'Lower LoA'), '5 3'), (hi, tr('LdA sup.', 'Upper LoA'), '5 3')]) {
    b
      ..writeln("<line x1='$l' x2='${_n(l + w)}' y1='${_n(y(v))}' y2='${_n(y(v))}' stroke='#c0504d' ${dash.isEmpty ? '' : "stroke-dasharray='$dash'"}/>")
      ..writeln("<text x='${_n(l + w + 4)}' y='${_n(y(v) + 4)}' font-size='10'>$lab</text>");
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Courbes de Kaplan-Meier en escalier, marques de censure (+) et tableau
/// des sujets à risque.
String kmSvg(Map<String, Object?> km, {String font = defaultSvgFont}) {
  final curves = (km['curves'] as List).cast<Map>();
  final unit = (km['unit'] as String?) ?? '';
  const colors = ['#1f4e79', '#c0504d', '#5a8f29', '#7a5c00', '#6b4c9a', '#2a8c8c'];
  final tmax = curves.map((c) => ((c['time'] as List).last as num).toDouble()).fold(0.0, math.max);
  final ticks = _niceTicks(0, tmax);
  final top = ticks.last > tmax ? ticks.last : tmax;
  const l = 60.0, t = 20.0, w = 340.0, h = 220.0;
  final riskH = 18.0 * curves.length + 24;
  double x(double v) => l + v / top * w;
  double y(double v) => t + h - v * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 ${_n(300 + riskH)}' width='440' height='${_n(300 + riskH)}' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Temps${unit.isEmpty ? "" : " ($unit)"}', 'Time${unit.isEmpty ? "" : " ($unit)"}'), tr('Survie', 'Survival'), ticks, [0, 0.25, 0.5, 0.75, 1], x, y);
  for (var k = 0; k < curves.length; k++) {
    final c = curves[k];
    final col = colors[k % colors.length];
    final ts = [for (final v in c['time'] as List) (v as num).toDouble()];
    final ss = [for (final v in c['surv'] as List) (v as num).toDouble()];
    final cs = [for (final v in c['censored'] as List) (v as num).toInt()];
    final pts = <String>['${_n(x(0))},${_n(y(1))}'];
    var prev = 1.0;
    for (var i = 0; i < ts.length; i++) {
      pts.add('${_n(x(ts[i]))},${_n(y(prev))}');
      pts.add('${_n(x(ts[i]))},${_n(y(ss[i]))}');
      prev = ss[i];
      if (cs[i] > 0) {
        b.writeln("<line x1='${_n(x(ts[i]))}' x2='${_n(x(ts[i]))}' y1='${_n(y(ss[i]) - 4)}' y2='${_n(y(ss[i]) + 4)}' stroke='$col'/>");
      }
    }
    b
      ..writeln("<polyline points='${pts.join(' ')}' fill='none' stroke='$col' stroke-width='1.8'/>")
      ..writeln("<rect x='${_n(l + w - 120)}' y='${_n(t + 8 + 16.0 * k)}' width='10' height='3' fill='$col'/>")
      ..writeln("<text x='${_n(l + w - 105)}' y='${_n(t + 12 + 16.0 * k)}' font-size='11'>${_esc(c['group'].toString())}</text>");
  }
  // τ du RMST : trait vertical en tirets (aire sous la courbe jusqu'à τ).
  final tau = (km['tau'] as num?)?.toDouble();
  if (tau != null) {
    b
      ..writeln("<line x1='${_n(x(tau))}' x2='${_n(x(tau))}' y1='${_n(t)}' y2='${_n(t + h)}' stroke='#7a5c00' stroke-dasharray='5 3'/>")
      ..writeln("<text x='${_n(x(tau) + 4)}' y='${_n(t + 12)}' font-size='10' fill='#7a5c00'>τ = ${_n(tau).replaceAll('.00', '')}</text>");
  }
  // Sujets à risque aux graduations.
  final ry = t + h + 52;
  b.writeln("<text x='4' y='${_n(ry)}' font-size='10' font-weight='bold'>${tr('À risque', 'At risk')}</text>");
  for (var k = 0; k < curves.length; k++) {
    final c = curves[k];
    final ts = [for (final v in c['time'] as List) (v as num).toDouble()];
    final ar = [for (final v in c['atRisk'] as List) (v as num).toInt()];
    final n0 = ar.isEmpty ? 0 : ar.first;
    final yy = ry + 16.0 * (k + 1);
    b.writeln("<text x='4' y='${_n(yy)}' font-size='10' fill='${colors[k % colors.length]}'>${_esc(c['group'].toString())}</text>");
    for (final tk in ticks) {
      var nr = n0;
      for (var i = 0; i < ts.length; i++) {
        if (ts[i] >= tk) {
          nr = ar[i];
          break;
        }
        nr = 0;
      }
      if (tk == 0) nr = n0;
      b.writeln("<text x='${_n(x(tk))}' y='${_n(yy)}' font-size='10' text-anchor='middle'>$nr</text>");
    }
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Incidence cumulée en escalier par groupe (trait plein, bande d'IC claire), 1 − Kaplan-Meier naïf (tirets, même
/// couleur) et incidence de l'événement concurrent (pointillés).
String cifSvg(Map cif, {String font = defaultSvgFont}) {
  final curves = (cif['curves'] as List).cast<Map>();
  final unit = (cif['unit'] as String?) ?? '';
  const colors = ['#1f4e79', '#c0504d', '#5a8f29', '#7a5c00', '#6b4c9a', '#2a8c8c'];
  List<double> dl(Object? v) => [for (final x in v as List) (x as num).toDouble()];
  final tmax = curves.map((c) => (c['last'] as num).toDouble()).fold(0.0, math.max);
  var ymax = 0.0;
  for (final c in curves) {
    for (final k in ['upper', 'naive', 'compCif']) {
      for (final v in dl(c[k])) {
        if (v.isFinite) ymax = math.max(ymax, v);
      }
    }
  }
  final yt = _niceTicks(0, math.max(ymax, 0.05));
  final top = yt.last, xt = _niceTicks(0, tmax), right = xt.last > tmax ? xt.last : tmax;
  const l = 60.0, t = 20.0, w = 340.0, h = 220.0;
  double x(double v) => l + v / right * w;
  double y(double v) => t + h - v / top * h;
  final legendH = 16.0 * (curves.length + 2) + 10;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 ${_n(290 + legendH)}' width='440' height='${_n(290 + legendH)}' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Temps${unit.isEmpty ? "" : " ($unit)"}', 'Time${unit.isEmpty ? "" : " ($unit)"}'), tr('Incidence cumulée', 'Cumulative incidence'), xt, yt, x, y);
  String steps(List<double> ts, List<double> vs, double end) {
    final pts = <String>['${_n(x(0))},${_n(y(0))}'];
    var prev = 0.0;
    for (var i = 0; i < ts.length; i++) {
      pts.add('${_n(x(ts[i]))},${_n(y(prev))}');
      pts.add('${_n(x(ts[i]))},${_n(y(vs[i]))}');
      prev = vs[i];
    }
    pts.add('${_n(x(end))},${_n(y(prev))}');
    return pts.join(' ');
  }

  for (var k = 0; k < curves.length; k++) {
    final c = curves[k];
    final col = colors[k % colors.length];
    final ts = dl(c['time']), lo = dl(c['lower']), hi = dl(c['upper']), end = (c['last'] as num).toDouble();
    // Bande d'IC (marches hautes puis basses en sens inverse).
    final up = <String>[], dn = <String>[];
    for (var i = 0; i < ts.length; i++) {
      final t1 = i + 1 < ts.length ? ts[i + 1] : end;
      if (!lo[i].isFinite || !hi[i].isFinite) continue;
      up..add('${_n(x(ts[i]))},${_n(y(hi[i]))}')..add('${_n(x(t1))},${_n(y(hi[i]))}');
      dn..add('${_n(x(t1))},${_n(y(lo[i]))}')..add('${_n(x(ts[i]))},${_n(y(lo[i]))}');
    }
    if (up.isNotEmpty) b.writeln("<polygon points='${[...up, ...dn.reversed].join(' ')}' fill='$col' fill-opacity='0.12' stroke='none'/>");
    b
      ..writeln("<polyline points='${steps(dl(c['naiveTime']), dl(c['naive']), end)}' fill='none' stroke='$col' stroke-width='1.2' stroke-dasharray='6 4'/>")
      ..writeln("<polyline points='${steps(dl(c['compTime']), dl(c['compCif']), end)}' fill='none' stroke='$col' stroke-width='1.2' stroke-dasharray='1.5 3' stroke-opacity='0.8'/>")
      ..writeln("<polyline points='${steps(ts, dl(c['cif']), end)}' fill='none' stroke='$col' stroke-width='2'/>");
  }
  // Légende sous le graphique.
  var ly = t + h + 44;
  for (var k = 0; k < curves.length; k++) {
    final col = colors[k % colors.length];
    b
      ..writeln("<rect x='${_n(l)}' y='${_n(ly - 4)}' width='16' height='3' fill='$col'/>")
      ..writeln("<text x='${_n(l + 22)}' y='${_n(ly)}' font-size='11'>${_esc(curves[k]['group'].toString())} — ${_esc(cif['cause'].toString())}</text>");
    ly += 16;
  }
  b
    ..writeln("<line x1='${_n(l)}' x2='${_n(l + 16)}' y1='${_n(ly - 4)}' y2='${_n(ly - 4)}' stroke='#444' stroke-dasharray='6 4'/>")
    ..writeln("<text x='${_n(l + 22)}' y='${_n(ly)}' font-size='11'>${tr('1 − Kaplan-Meier naïf (surestime)', 'Naive 1 − Kaplan-Meier (overestimates)')}</text>");
  ly += 16;
  b
    ..writeln("<line x1='${_n(l)}' x2='${_n(l + 16)}' y1='${_n(ly - 4)}' y2='${_n(ly - 4)}' stroke='#444' stroke-dasharray='1.5 3'/>")
    ..writeln("<text x='${_n(l + 22)}' y='${_n(ly)}' font-size='11'>${_esc(cif['competing'].toString())} (${tr('événement concurrent', 'competing event')})</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Courbe de puissance : puissance selon l'effectif, ligne de la puissance visée et repère de l'effectif retenu.
String powerCurveSvg(Map pc, {String font = defaultSvgFont}) {
  final xs = [for (final v in pc['n'] as List) (v as num).toDouble()];
  final ys = [for (final v in pc['power'] as List) (v as num).toDouble()];
  final target = (pc['target'] as num).toDouble(), nStar = (pc['nStar'] as num).toDouble();
  final xt = _niceTicks(xs.first, xs.last);
  final lo = xt.first < xs.first ? xt.first : xs.first, hi = xt.last > xs.last ? xt.last : xs.last;
  const l = 60.0, t = 20.0, w = 340.0, h = 220.0;
  double x(double v) => l + (v - lo) / (hi - lo) * w;
  double y(double v) => t + h - v * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 300' width='440' height='300' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, _esc(pc['xLabel'].toString()), tr('Puissance', 'Power'), xt, [0, 0.2, 0.4, 0.6, 0.8, 1], x, y);
  b
    ..writeln("<line x1='${_n(l)}' x2='${_n(l + w)}' y1='${_n(y(target))}' y2='${_n(y(target))}' stroke='#c0504d' stroke-dasharray='5 3'/>")
    ..writeln("<text x='${_n(l + 4)}' y='${_n(y(target) - 4)}' font-size='10' fill='#c0504d'>${tr('puissance visée', 'target power')} ${(target * 100).round()} %</text>")
    ..writeln("<polyline points='${[for (var i = 0; i < xs.length; i++) '${_n(x(xs[i]))},${_n(y(ys[i]))}'].join(' ')}' fill='none' stroke='#1f4e79' stroke-width='2'/>")
    ..writeln("<line x1='${_n(x(nStar))}' x2='${_n(x(nStar))}' y1='${_n(t)}' y2='${_n(t + h)}' stroke='#5a8f29' stroke-dasharray='3 3'/>")
    ..writeln("<text x='${_n(x(nStar) + 4)}' y='${_n(t + h - 6)}' font-size='10' fill='#5a8f29'>n = ${nStar.ceil()}</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Trajectoires individuelles (gris) et moyenne ajustée par groupe (partie fixe du modèle mixte).
String trajectoriesSvg(Map tr0, {String font = defaultSvgFont}) {
  final subjects = (tr0['subjects'] as List).cast<Map>(), means = (tr0['mean'] as List).cast<Map>();
  List<double> dl(Object? v) => [for (final x in v as List) (x as num).toDouble()];
  var xmin = double.infinity, xmax = -double.infinity, ymin = double.infinity, ymax = -double.infinity;
  for (final s in [...subjects, ...means]) {
    for (final v in dl(s['x'])) {
      xmin = math.min(xmin, v);
      xmax = math.max(xmax, v);
    }
    for (final v in dl(s['y'])) {
      ymin = math.min(ymin, v);
      ymax = math.max(ymax, v);
    }
  }
  final xt = _niceTicks(xmin, xmax), yt = _niceTicks(ymin, ymax);
  final x0 = math.min(xt.first, xmin), x1 = math.max(xt.last, xmax), y0 = math.min(yt.first, ymin), y1 = math.max(yt.last, ymax);
  const l = 60.0, t = 20.0, w = 340.0, h = 220.0;
  double x(double v) => l + (v - x0) / (x1 - x0 + 1e-12) * w;
  double y(double v) => t + h - (v - y0) / (y1 - y0 + 1e-12) * h;
  const colors = ['#1f4e79', '#c0504d', '#5a8f29', '#7a5c00', '#6b4c9a', '#2a8c8c'];
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 ${_n(290 + 16.0 * means.length)}' width='440' height='${_n(290 + 16.0 * means.length)}' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, _esc(tr0['xLabel'].toString()), _esc(tr0['yLabel'].toString()), xt, yt, x, y);
  for (final s in subjects) {
    final xs = dl(s['x']), ys = dl(s['y']);
    b.writeln("<polyline points='${[for (var i = 0; i < xs.length; i++) '${_n(x(xs[i]))},${_n(y(ys[i]))}'].join(' ')}' fill='none' stroke='#9aa5b1' stroke-opacity='0.55' stroke-width='0.8'/>");
  }
  for (var k = 0; k < means.length; k++) {
    final xs = dl(means[k]['x']), ys = dl(means[k]['y']), col = colors[k % colors.length];
    b
      ..writeln("<polyline points='${[for (var i = 0; i < xs.length; i++) '${_n(x(xs[i]))},${_n(y(ys[i]))}'].join(' ')}' fill='none' stroke='$col' stroke-width='2.6'/>")
      ..writeln("<rect x='${_n(l)}' y='${_n(t + h + 40 + 16.0 * k)}' width='16' height='3' fill='$col'/>")
      ..writeln("<text x='${_n(l + 22)}' y='${_n(t + h + 44 + 16.0 * k)}' font-size='11'>${tr('Moyenne ajustée', 'Fitted mean')} — ${_esc(means[k]['group'].toString())}</text>");
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Graphique à bulles de méta-régression : effet de chaque étude en fonction
/// du modérateur (aire ∝ poids), droite de régression (échelle log si ratio).
String bubblePlotSvg(Map bubble, {String font = defaultSvgFont}) {
  final xs = [for (final v in bubble['x'] as List) (v as num).toDouble()];
  final ys = [for (final v in bubble['y'] as List) (v as num).toDouble()];
  final ws = [for (final v in bubble['w'] as List) (v as num).toDouble()];
  final ratio = bubble['ratio'] == true;
  final b0 = (bubble['b0'] as num).toDouble(), b1 = (bubble['b1'] as num).toDouble();
  double ty(double v) => ratio ? math.log(v) : v;
  final xmin = xs.reduce(math.min), xmax = xs.reduce(math.max);
  final lys = [for (final v in ys) ty(v)];
  var ymin = lys.reduce(math.min), ymax = lys.reduce(math.max);
  for (final xv in [xmin, xmax]) {
    ymin = math.min(ymin, b0 + b1 * xv);
    ymax = math.max(ymax, b0 + b1 * xv);
  }
  if (ratio) {
    ymin = math.min(ymin, 0);
    ymax = math.max(ymax, 0);
  }
  final pad = (ymax - ymin) * 0.08 + 1e-9;
  ymin -= pad;
  ymax += pad;
  const l = 60.0, t = 20.0, w = 340.0, h = 240.0;
  final xpad = (xmax - xmin) * 0.05 + 1e-9;
  double x(double v) => l + (v - xmin + xpad) / (xmax - xmin + 2 * xpad) * w;
  double y(double v) => t + h - (v - ymin) / (ymax - ymin) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 420 320' width='420' height='320' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  final yt = ratio
      ? [for (final r in [0.1, 0.2, 0.5, 1.0, 2.0, 5.0]) if (math.log(r) >= ymin && math.log(r) <= ymax) r]
      : _niceTicks(ymin, ymax);
  b.writeln("<rect x='$l' y='$t' width='$w' height='$h' fill='none' stroke='black'/>");
  for (final v in _niceTicks(xmin, xmax)) {
    b.writeln("<text x='${_n(x(v))}' y='${_n(t + h + 16)}' text-anchor='middle' font-size='10'>${fmt(v, digits: 2)}</text>");
  }
  for (final v in yt) {
    b.writeln("<text x='${_n(l - 6)}' y='${_n(y(ty(v)) + 3)}' text-anchor='end' font-size='10'>${fmt(v, digits: 2)}</text>");
  }
  b
    ..writeln("<text x='${_n(l + w / 2)}' y='${_n(t + h + 34)}' text-anchor='middle'>${_esc(bubble['xName'].toString())}</text>")
    ..writeln("<text x='14' y='${_n(t + h / 2)}' text-anchor='middle' transform='rotate(-90 14 ${_n(t + h / 2)})'>${_esc(bubble['yName'].toString())}${ratio ? tr(" (échelle log)", " (log scale)") : ""}</text>");
  if (ymin < 0 && ymax > 0) {
    b.writeln("<line x1='$l' x2='${_n(l + w)}' y1='${_n(y(0))}' y2='${_n(y(0))}' stroke='#888' stroke-dasharray='3 3'/>");
  }
  final wmax = ws.reduce(math.max);
  for (var i = 0; i < xs.length; i++) {
    final r = 3 + 10 * math.sqrt(ws[i] / wmax);
    b.writeln("<circle cx='${_n(x(xs[i]))}' cy='${_n(y(lys[i]))}' r='${_n(r)}' fill='#1f4e79' fill-opacity='0.35' stroke='#1f4e79'/>");
  }
  b
    ..writeln("<line x1='${_n(x(xmin))}' y1='${_n(y(b0 + b1 * xmin))}' x2='${_n(x(xmax))}' y2='${_n(y(b0 + b1 * xmax))}' stroke='#c0504d' stroke-width='2'/>")
    ..writeln('</svg>');
  return b.toString();
}

/// Espace ROC de la métaanalyse diagnostique : études (aire ∝ effectif),
/// point combiné, courbe SROC, région de confiance et de prédiction.
String srocSvg(Map<String, Object?> sroc, {String font = defaultSvgFont}) {
  const l = 60.0, t = 20.0, w = 320.0, h = 320.0;
  double x(double v) => l + v * w;
  double y(double v) => t + h - v * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 420' width='440' height='420' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  const ticks = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  _axes(b, l, t, w, h, tr('1 − spécificité (taux de faux positifs)', '1 − specificity (false positive rate)'), tr('Sensibilité', 'Sensitivity'), ticks, ticks, x, y);
  String path(List pts) => [for (final p in pts) '${_n(x(((p as List)[0] as num).toDouble()))},${_n(y((p[1] as num).toDouble()))}'].join(' ');
  if (sroc['prediction'] is List) {
    b.writeln("<polygon points='${path(sroc['prediction'] as List)}' fill='none' stroke='#c0504d' stroke-dasharray='4 3'/>");
  }
  if (sroc['confidence'] is List) {
    b.writeln("<polygon points='${path(sroc['confidence'] as List)}' fill='#c0504d' fill-opacity='0.12' stroke='#c0504d'/>");
  }
  if (sroc['curve'] is List) {
    b.writeln("<polyline points='${path(sroc['curve'] as List)}' fill='none' stroke='#1f4e79' stroke-width='2'/>");
  }
  final st = (sroc['studies'] as List).cast<Map>();
  final nmax = st.map((s) => (s['n'] as num).toDouble()).fold(1.0, math.max);
  for (final s in st) {
    final r = 2.5 + 7 * math.sqrt((s['n'] as num).toDouble() / nmax);
    b.writeln("<circle cx='${_n(x((s['fpr'] as num).toDouble()))}' cy='${_n(y((s['sens'] as num).toDouble()))}' r='${_n(r)}' fill='none' stroke='#555'/>");
  }
  final sm = (sroc['summary'] as Map);
  b
    ..writeln("<circle cx='${_n(x((sm['fpr'] as num).toDouble()))}' cy='${_n(y((sm['sens'] as num).toDouble()))}' r='5' fill='#c0504d'/>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + h - 46)}' text-anchor='end' font-size='10' fill='#1f4e79'>Courbe SROC</text>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + h - 32)}' text-anchor='end' font-size='10' fill='#c0504d'>${tr('Point combiné, région de confiance', 'Pooled point, confidence region')}</text>")
    ..writeln("<text x='${_n(l + w - 4)}' y='${_n(t + h - 18)}' text-anchor='end' font-size='10' fill='#c0504d'>- - ${tr('région de prédiction', 'prediction region')}</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Convergence des chaînes d'imputation : moyenne des valeurs imputées par
/// itération, une ligne par imputation (les lignes doivent se mêler).
String miChainsSvg(Map chains, {String font = defaultSvgFont}) {
  final vars = chains.keys.map((k) => k.toString()).toList();
  const pw = 200.0, ph = 120.0, gap = 30.0;
  final h = 40 + (ph + gap + 20) * ((vars.length + 1) ~/ 2);
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 480 ${_n(h)}' width='480' height='${_n(h)}' ${_font(font)} font-size='11'>\n<rect width='100%' height='100%' fill='white'/>\n");
  const colors = ['#1f4e79', '#c0504d', '#5a8f29', '#7a5c00', '#6b4c9a'];
  for (var v = 0; v < vars.length; v++) {
    final lines = [for (final c in chains[vars[v]] as List) [for (final x in c as List) (x as num).toDouble()]];
    final l = 40.0 + (v % 2) * (pw + gap), t = 30.0 + (v ~/ 2) * (ph + gap + 20);
    final all = lines.expand((x) => x).toList();
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if (hi == lo) hi = lo + 1;
    final iters = lines.first.length;
    double x(int i) => l + (iters == 1 ? 0 : i / (iters - 1) * pw);
    double y(double val) => t + ph - (val - lo) / (hi - lo) * ph;
    b
      ..writeln("<text x='${_n(l)}' y='${_n(t - 8)}' font-weight='bold'>${_esc(vars[v])}</text>")
      ..writeln("<rect x='$l' y='$t' width='$pw' height='$ph' fill='none' stroke='black'/>")
      ..writeln("<text x='${_n(l - 4)}' y='${_n(t + 4)}' text-anchor='end' font-size='9'>${fmt(hi)}</text>")
      ..writeln("<text x='${_n(l - 4)}' y='${_n(t + ph)}' text-anchor='end' font-size='9'>${fmt(lo)}</text>")
      ..writeln("<text x='${_n(l + pw / 2)}' y='${_n(t + ph + 14)}' text-anchor='middle' font-size='9'>${tr('itération', 'iteration')}</text>");
    for (var k = 0; k < lines.length && k < 10; k++) {
      final pts = [for (var i = 0; i < lines[k].length; i++) '${_n(x(i))},${_n(y(lines[k][i]))}'].join(' ');
      b.writeln("<polyline points='$pts' fill='none' stroke='${colors[k % colors.length]}' stroke-opacity='0.8'/>");
    }
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Volcano plot : log2 FC en abscisse, −log10 p en ordonnée ; gènes significatifs (FDR) en rouge,
/// seuils |log2 FC| en pointillés ; les 8 gènes les plus significatifs sont nommés.
String volcanoSvg(Map v, {String font = defaultSvgFont}) {
  final fc = [for (final e in v['logFC'] as List) (e as num).toDouble()];
  final lp = [for (final e in v['negLog10P'] as List) (e as num).toDouble()];
  final sig = [for (final e in v['significant'] as List) e == true];
  final genes = [for (final e in (v['genes'] as List? ?? const [])) '$e'];
  final minFc = ((v['minLogFC'] as num?) ?? 1).toDouble();
  const l = 60.0, t = 20.0, w = 360.0, h = 280.0;
  final xm = math.max(minFc * 1.5, fc.map((e) => e.abs()).fold(0.0, math.max)) * 1.05;
  final ym = math.max(1.0, lp.where((e) => e.isFinite).fold(0.0, math.max)) * 1.05;
  double x(double e) => l + (e + xm) / (2 * xm) * w;
  double y(double e) => t + h - (e.isFinite ? e : ym) / ym * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 460 360' width='460' height='360' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('log2 du rapport d\'expression', 'log2 fold change'), '−log10 p', _niceTicks(-xm, xm), _niceTicks(0, ym), x, y);
  for (final e in [-minFc, minFc]) {
    b.writeln("<line x1='${_n(x(e))}' x2='${_n(x(e))}' y1='$t' y2='${_n(t + h)}' stroke='#888' stroke-dasharray='4 3'/>");
  }
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < fc.length; i++) {
      if (sig[i] != (pass == 1)) continue;
      b.writeln("<circle cx='${_n(x(fc[i]))}' cy='${_n(y(lp[i]))}' r='${sig[i] ? 2.6 : 2}' fill='${sig[i] ? '#c0504d' : '#9aa7b4'}' fill-opacity='${sig[i] ? 0.9 : 0.6}'/>");
    }
  }
  if (genes.length == fc.length) {
    // Étiquettes des gènes les plus significatifs, sans chevauchement (une étiquette est omise si elle en recouvre une autre).
    final top = [for (var i = 0; i < fc.length; i++) if (sig[i]) i]..sort((a, c) => lp[c].compareTo(lp[a]));
    final placed = <(double, double, double)>[]; // x gauche, x droite, y
    var shown = 0;
    for (final i in top) {
      if (shown == 8) break;
      final right = fc[i] >= 0;
      final w = 5.2 * genes[i].length;
      final x0 = right ? x(fc[i]) + 4 : x(fc[i]) - 4 - w, yy = y(lp[i]) - 3;
      if (x0 < 2 || x0 + w > 458) continue;
      if (placed.any((p) => x0 < p.$2 + 2 && x0 + w > p.$1 - 2 && (yy - p.$3).abs() < 11)) continue;
      placed.add((x0, x0 + w, yy));
      shown++;
      b.writeln("<text x='${_n(x0)}' y='${_n(yy)}' font-size='9'>${_esc(genes[i])}</text>");
    }
  }
  final nSig = sig.where((e) => e).length;
  b
    ..writeln("<text x='${_n(l + 6)}' y='${_n(t + 14)}' font-size='11' fill='#c0504d'>${tr('$nSig significatif(s) (FDR)', '$nSig significant (FDR)')}</text>")
    ..writeln(v['contrast'] == null ? '' : "<text x='${_n(l + w / 2)}' y='${_n(t - 6)}' font-size='11' text-anchor='middle'>${_esc('${v['contrast']}')}</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Courbe standard de qPCR : Ct selon log10(quantité), droite ajustée.
String standardCurveSvg(Map s, {String font = defaultSvgFont}) {
  final xs = [for (final e in s['x'] as List) (e as num).toDouble()];
  final ys = [for (final e in s['y'] as List) (e as num).toDouble()];
  final a = (s['intercept'] as num).toDouble(), sl = (s['slope'] as num).toDouble();
  const l = 60.0, t = 20.0, w = 320.0, h = 240.0;
  final x0 = xs.reduce(math.min) - 0.3, x1 = xs.reduce(math.max) + 0.3;
  final y0 = ys.reduce(math.min) - 1, y1 = ys.reduce(math.max) + 1;
  double x(double e) => l + (e - x0) / (x1 - x0) * w;
  double y(double e) => t + h - (e - y0) / (y1 - y0) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 420 320' width='420' height='320' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('log10 quantité', 'log10 quantity'), 'Ct', _niceTicks(x0, x1), _niceTicks(y0, y1), x, y);
  b.writeln("<line x1='${_n(x(x0))}' y1='${_n(y(a + sl * x0))}' x2='${_n(x(x1))}' y2='${_n(y(a + sl * x1))}' stroke='#c0504d'/>");
  for (var i = 0; i < xs.length; i++) {
    b.writeln("<circle cx='${_n(x(xs[i]))}' cy='${_n(y(ys[i]))}' r='3.5' fill='#1f4e79'/>");
  }
  b
    ..writeln("<text x='${_n(l + w - 6)}' y='${_n(t + 16)}' text-anchor='end' font-size='11'>Ct = ${fmt(a)} ${sl < 0 ? '−' : '+'} ${fmt(sl.abs())} × log10 q</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// ACP des génotypes : sujets dans le plan CP1 × CP2, couleur selon le groupe (cas, témoins…).
String pcaSvg(Map f, {String font = defaultSvgFont}) {
  final x = [for (final e in f['pc1'] as List) (e as num).toDouble()];
  final y = [for (final e in f['pc2'] as List) (e as num).toDouble()];
  final groups = [for (final e in f['groups'] as List) '$e'];
  final levels = groups.toSet().toList()..sort();
  const colors = ['#1f4e79', '#c0504d', '#5a8f29', '#7a5c00', '#6b4c9a'];
  const l = 60.0, t = 20.0, w = 320.0, h = 280.0;
  double pad(double a, double b) => (b - a) * 0.05 + 1e-12;
  final x0 = x.reduce(math.min), x1 = x.reduce(math.max), y0 = y.reduce(math.min), y1 = y.reduce(math.max);
  final xa = x0 - pad(x0, x1), xb = x1 + pad(x0, x1), ya = y0 - pad(y0, y1), yb = y1 + pad(y0, y1);
  double px(double v) => l + (v - xa) / (xb - xa) * w;
  double py(double v) => t + h - (v - ya) / (yb - ya) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 440 360' width='440' height='360' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, 'PC1 (${fmtPct((f['var1'] as num).toDouble())})', 'PC2 (${fmtPct((f['var2'] as num).toDouble())})', _niceTicks(xa, xb), _niceTicks(ya, yb), px, py);
  for (var i = 0; i < x.length; i++) {
    b.writeln("<circle cx='${_n(px(x[i]))}' cy='${_n(py(y[i]))}' r='2.4' fill='${colors[levels.indexOf(groups[i]) % colors.length]}' fill-opacity='0.75'/>");
  }
  for (var k = 0; k < levels.length; k++) {
    b
      ..writeln("<circle cx='${_n(l + w + 14)}' cy='${_n(t + 10 + 16.0 * k)}' r='4' fill='${colors[k % colors.length]}'/>")
      ..writeln("<text x='${_n(l + w + 22)}' y='${_n(t + 14 + 16.0 * k)}' font-size='11'>${_esc(levels[k])}</text>");
  }
  b.writeln('</svg>');
  return b.toString();
}

/// Graphique de KING : φ selon IBS0 pour les paires (échantillon des paires non apparentées en gris), seuils de degré.
String kingSvg(Map f, {String font = defaultSvgFont}) {
  List<double> d(String k) => [for (final e in (f[k] as List? ?? const [])) (e as num).toDouble()];
  final phi = d('phi'), ibs = d('ibs0'), bphi = d('background_phi'), bibs = d('background_ibs0');
  const l = 60.0, t = 20.0, w = 320.0, h = 280.0;
  final allIbs = [...ibs, ...bibs].where((v) => v.isFinite), allPhi = [...phi, ...bphi].where((v) => v.isFinite);
  final xb = math.max(0.05, allIbs.fold(0.0, math.max)) * 1.05;
  final ya = math.min(-0.05, allPhi.fold(0.0, math.min)), yb = math.max(0.55, allPhi.fold(0.0, math.max) + 0.02);
  double px(double v) => l + v / xb * w;
  double py(double v) => t + h - (v - ya) / (yb - ya) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 460 360' width='460' height='360' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, 'IBS0', tr('Parenté φ (KING)', 'Kinship φ (KING)'), _niceTicks(0, xb), _niceTicks(ya, yb), px, py);
  for (final (v, lab) in [(0.354, tr('doublon/MZ', 'dup./MZ')), (0.177, tr('1er degré', '1st deg.')), (0.0884, tr('2e', '2nd')), (0.0442, tr('3e', '3rd'))]) {
    b
      ..writeln("<line x1='$l' x2='${_n(l + w)}' y1='${_n(py(v))}' y2='${_n(py(v))}' stroke='#888' stroke-dasharray='4 3'/>")
      ..writeln("<text x='${_n(l + w + 4)}' y='${_n(py(v) + 4)}' font-size='10'>${_esc(lab)}</text>");
  }
  for (var i = 0; i < bphi.length; i++) {
    if (bphi[i].isFinite && bibs[i].isFinite) b.writeln("<circle cx='${_n(px(bibs[i]))}' cy='${_n(py(bphi[i]))}' r='1.6' fill='#9aa7b4' fill-opacity='0.5'/>");
  }
  for (var i = 0; i < phi.length; i++) {
    b.writeln("<circle cx='${_n(px(ibs[i]))}' cy='${_n(py(phi[i]))}' r='3' fill='#c0504d'/>");
  }
  b.writeln('</svg>');
  return b.toString();
}

int _chromKey(String c) {
  final s = c.toUpperCase().replaceFirst(RegExp('^CHR'), '');
  final n = int.tryParse(s);
  if (n != null) return n;
  return switch (s) { 'X' => 23, 'Y' => 24, 'XY' => 25, 'MT' || 'M' => 26, _ => 100 + s.codeUnits.fold(0, (a, b) => a + b) };
}

/// Manhattan plot : −log10 p selon la position, chromosomes alternés ; seuils pangénomique (5×10⁻⁸) et suggestif (10⁻⁵).
String manhattanSvg(Map f, {String font = defaultSvgFont}) {
  final chrom = [for (final e in f['chrom'] as List) '$e'];
  final pos = [for (final e in f['pos'] as List) (e as num).toDouble()];
  final lp = [for (final e in f['logp'] as List) (e as num).toDouble()];
  final names = [for (final e in (f['names'] as List? ?? const [])) '$e'];
  final gw = -math.log((f['genomeWide'] as num).toDouble()) / math.ln10, sug = -math.log((f['suggestive'] as num).toDouble()) / math.ln10;
  final chroms = chrom.toSet().toList()..sort((a, b) => _chromKey(a).compareTo(_chromKey(b)));
  // Abscisse cumulée : chaque chromosome occupe l'étendue de ses positions (+ 3 % d'écart).
  final start = <String, double>{}, span = <String, double>{}, minPos = <String, double>{};
  var cum = 0.0;
  for (final c in chroms) {
    final ps = [for (var i = 0; i < pos.length; i++) if (chrom[i] == c) pos[i]];
    final lo = ps.reduce(math.min), hi = ps.reduce(math.max);
    minPos[c] = lo;
    span[c] = math.max(hi - lo, 1);
    start[c] = cum;
    cum += span[c]! * 1.03;
  }
  const l = 60.0, t = 20.0, w = 520.0, h = 260.0;
  final ymax = math.max(gw + 1, lp.fold(0.0, math.max) * 1.05);
  double px(int i) => l + (start[chrom[i]]! + pos[i] - minPos[chrom[i]]!) / cum * w;
  double py(double v) => t + h - v / ymax * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 600 340' width='600' height='340' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  b
    ..writeln("<rect x='$l' y='$t' width='$w' height='$h' fill='none' stroke='black'/>")
    ..writeln("<text x='${_n(l + w / 2)}' y='${_n(t + h + 34)}' text-anchor='middle'>${tr('Chromosome', 'Chromosome')}</text>")
    ..writeln("<text x='14' y='${_n(t + h / 2)}' text-anchor='middle' transform='rotate(-90 14 ${_n(t + h / 2)})'>−log10 p</text>");
  for (final v in _niceTicks(0, ymax)) {
    b.writeln("<text x='${_n(l - 6)}' y='${_n(py(v) + 3)}' text-anchor='end' font-size='10'>${fmt(v, digits: 2)}</text>");
  }
  for (final c in chroms) {
    b.writeln("<text x='${_n(l + (start[c]! + span[c]! / 2) / cum * w)}' y='${_n(t + h + 16)}' text-anchor='middle' font-size='10'>${_esc(c)}</text>");
  }
  for (final (v, col, dash) in [(gw, '#c0504d', ''), (sug, '#888', "stroke-dasharray='4 3'")]) {
    if (v <= ymax) b.writeln("<line x1='$l' x2='${_n(l + w)}' y1='${_n(py(v))}' y2='${_n(py(v))}' stroke='$col' $dash/>");
  }
  for (var i = 0; i < lp.length; i++) {
    final col = chroms.indexOf(chrom[i]).isEven ? '#1f4e79' : '#7fa6c9';
    b.writeln("<circle cx='${_n(px(i))}' cy='${_n(py(lp[i]))}' r='2' fill='${lp[i] >= gw ? '#c0504d' : col}'/>");
  }
  if (names.length == lp.length) {
    final top = [for (var i = 0; i < lp.length; i++) if (lp[i] >= sug && names[i].isNotEmpty) i]..sort((a, c) => lp[c].compareTo(lp[a]));
    for (final i in top.take(5)) {
      b.writeln("<text x='${_n(px(i) + 4)}' y='${_n(py(lp[i]) - 3)}' font-size='9'>${_esc(names[i])}</text>");
    }
  }
  b.writeln('</svg>');
  return b.toString();
}

/// QQ plot des p : −log10 observés selon −log10 attendus, bande de confiance à 95 %, diagonale, λ.
String qqSvg(Map f, {String font = defaultSvgFont}) {
  List<double> d(String k) => [for (final e in f[k] as List) (e as num).toDouble()];
  final obs = d('observed'), exp = d('expected'), hiB = d('bandHigh'), loB = d('bandLow');
  final lambda = (f['lambda'] as num?)?.toDouble();
  const l = 60.0, t = 20.0, w = 300.0, h = 300.0;
  final xm = exp.fold(0.0, math.max) * 1.05, ym = math.max(xm, [...obs, ...hiB].fold(0.0, math.max) * 1.05);
  double px(double v) => l + v / xm * w;
  double py(double v) => t + h - v / ym * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 380' width='400' height='380' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('−log10 p attendu', 'Expected −log10 p'), tr('−log10 p observé', 'Observed −log10 p'), _niceTicks(0, xm), _niceTicks(0, ym), px, py);
  final order = [for (var i = 0; i < exp.length; i++) i]..sort((a, c) => exp[a].compareTo(exp[c]));
  final upper = [for (final i in order) '${_n(px(exp[i]))},${_n(py(hiB[i]))}'];
  final lower = [for (final i in order.reversed) '${_n(px(exp[i]))},${_n(py(loB[i]))}'];
  b
    ..writeln("<polygon points='${[...upper, ...lower].join(' ')}' fill='#d9e2ec' stroke='none'/>")
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(0))}' x2='${_n(px(math.min(xm, ym)))}' y2='${_n(py(math.min(xm, ym)))}' stroke='#c0504d'/>");
  for (var i = 0; i < obs.length; i++) {
    b.writeln("<circle cx='${_n(px(exp[i]))}' cy='${_n(py(obs[i]))}' r='2' fill='#1f4e79'/>");
  }
  if (lambda != null) b.writeln("<text x='${_n(l + 8)}' y='${_n(t + 16)}' font-size='12'>λ = ${fmt(lambda, digits: 3)}</text>");
  b.writeln('</svg>');
  return b.toString();
}

/// Régression LD score : χ² moyen par classe de score LD (points) et droite ajustée ; pointillé : χ² = 1 (aucune inflation).
/// Variante croisée (`cross`) : produit z₁·z₂ moyen, pointillé à 0.
String ldscSvg(Map f, {String font = defaultSvgFont}) {
  final bins = [for (final e in f['bins'] as List) [for (final x in e as List) (x as num).toDouble()]];
  final a = (f['intercept'] as num).toDouble(), s = (f['slope'] as num).toDouble();
  final cross = f['cross'] == true;
  final ref = cross ? 0.0 : 1.0;
  const l = 60.0, t = 20.0, w = 300.0, h = 280.0;
  final xs = [for (final e in bins) e[0]], ys = [for (final e in bins) e[1]];
  final xm = xs.fold(0.0, math.max) * 1.05;
  final lineEnd = a + s * xm;
  final lo0 = [...ys, a, lineEnd, ref].fold(double.infinity, math.min), hi0 = [...ys, a, lineEnd, ref + 0.2].fold(-double.infinity, math.max);
  final pad = (hi0 - lo0) * 0.06;
  final ylo = cross ? lo0 - pad : math.min(0.8, lo0 * 0.95);
  final yhi = cross ? hi0 + pad : hi0 * 1.05;
  double px(double v) => l + v / xm * w;
  double py(double v) => t + h - (v - ylo) / (yhi - ylo) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 360' width='400' height='360' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, tr('Score LD (ℓ)', 'LD score (ℓ)'), cross ? tr('z₁·z₂ moyen', 'Mean z₁·z₂') : tr('χ² moyen', 'Mean χ²'), _niceTicks(0, xm), _niceTicks(ylo, yhi), px, py);
  b
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(ref))}' x2='${_n(px(xm))}' y2='${_n(py(ref))}' stroke='#888' stroke-dasharray='4 3'/>")
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(a))}' x2='${_n(px(xm))}' y2='${_n(py(lineEnd))}' stroke='#c0504d' stroke-width='1.5'/>");
  for (final e in bins) {
    b.writeln("<circle cx='${_n(px(e[0]))}' cy='${_n(py(e[1]))}' r='3' fill='#1f4e79'/>");
  }
  b.writeln("<text x='${_n(l + 8)}' y='${_n(t + 16)}' font-size='12'>${tr('intercept', 'intercept')} = ${fmt(a, digits: 3)}</text>");
  b.writeln('</svg>');
  return b.toString();
}

/// Score polygénique : R² de Nagelkerke en validation selon le seuil de p (barres ; seuil retenu en rouge) et R² sur le
/// test (pointillé) — l'écart montre l'optimisme du choix du seuil.
String prsSvg(Map f, {String font = defaultSvgFont}) {
  final th = [for (final x in f['thresholds'] as List) (x as num).toDouble()];
  final r2 = [for (final x in f['r2'] as List) (x as num).toDouble()];
  final best = (f['best'] as num).toDouble(), test = (f['testR2'] as num).toDouble();
  const l = 60.0, t = 20.0, w = 320.0, h = 240.0;
  final ym = [...r2, test, 0.01].fold(0.0, math.max) * 1.15;
  double py(double v) => t + h - v / ym * h;
  final bw = w / th.length;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 330' width='400' height='330' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  b.writeln("<line x1='$l' y1='${t + h}' x2='${l + w}' y2='${t + h}' stroke='black'/><line x1='$l' y1='$t' x2='$l' y2='${t + h}' stroke='black'/>");
  for (final v in _niceTicks(0, ym)) {
    if (v > ym) continue;
    b.writeln("<line x1='${l - 4}' y1='${_n(py(v))}' x2='$l' y2='${_n(py(v))}' stroke='black'/><text x='${l - 6}' y='${_n(py(v) + 4)}' text-anchor='end'>${fmt(v, digits: 2)}</text>");
  }
  for (var k = 0; k < th.length; k++) {
    final x = l + k * bw + bw * 0.15;
    b.writeln("<rect x='${_n(x)}' y='${_n(py(r2[k]))}' width='${_n(bw * 0.7)}' height='${_n(t + h - py(r2[k]))}' fill='${th[k] == best ? '#c0504d' : '#1f4e79'}'/>");
    final lab = th[k] >= 0.001 ? fmt(th[k], digits: 3) : th[k].toStringAsExponential(0).replaceFirst('e-', 'e−');
    b.writeln("<text x='${_n(x + bw * 0.35)}' y='${t + h + 14}' font-size='9' text-anchor='end' transform='rotate(-45 ${_n(x + bw * 0.35)} ${t + h + 14})'>$lab</text>");
  }
  b
    ..writeln("<line x1='$l' y1='${_n(py(test))}' x2='${l + w}' y2='${_n(py(test))}' stroke='#c0504d' stroke-dasharray='5 3'/>")
    ..writeln("<text x='${l + w}' y='${_n(py(test) - 4)}' text-anchor='end' fill='#c0504d'>${tr('test', 'test')} ${fmt(test, digits: 2)}</text>")
    ..writeln("<text x='${l + w / 2}' y='${t + h + 52}' text-anchor='middle'>${tr('Seuil de p', 'p threshold')}</text>")
    ..writeln("<text x='16' y='${t + h / 2}' text-anchor='middle' transform='rotate(-90 16 ${t + h / 2})'>${tr('R² de Nagelkerke (validation)', 'Nagelkerke R² (validation)')}</text>")
    ..writeln('</svg>');
  return b.toString();
}

/// Randomisation mendélienne : associations variant–issue (βY) selon variant–exposition (βX), barres d'ES, droites IVW
/// (bleu), MR-Egger (rouge, avec intercept) et médiane pondérée (vert, pointillé).
String mrSvg(Map f, {String font = defaultSvgFont}) {
  List<double> d(String k) => [for (final x in f[k] as List) (x as num).toDouble()];
  final bx = d('bx'), by = d('by'), sx = d('bxse'), sy = d('byse');
  final ivw = (f['ivw'] as num).toDouble(), eg = (f['egger'] as num).toDouble(), ei = (f['eggerIntercept'] as num).toDouble(), md = (f['median'] as num).toDouble();
  final mo = (f['mode'] as num?)?.toDouble();
  const l = 64.0, t = 20.0, w = 300.0, h = 260.0;
  final xm = [for (var j = 0; j < bx.length; j++) bx[j] + sx[j]].fold(0.0, math.max) * 1.05;
  final ylo = math.min(0.0, [for (var j = 0; j < by.length; j++) by[j] - sy[j]].fold(0.0, math.min) * 1.05);
  final yhi = [...[for (var j = 0; j < by.length; j++) by[j] + sy[j]], ivw * xm, eg * xm + ei, md * xm, ?(mo == null ? null : mo * xm)].fold(0.0, math.max) * 1.05;
  double px(double v) => l + v / xm * w;
  double py(double v) => t + h - (v - ylo) / (yhi - ylo) * h;
  final b = StringBuffer("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 340' width='400' height='340' ${_font(font)} font-size='12'>\n<rect width='100%' height='100%' fill='white'/>\n");
  _axes(b, l, t, w, h, '${tr('Association avec', 'Association with')} ${f['exposure']} (βX)', '${tr('Association avec', 'Association with')} ${f['outcome']} (βY)',
      _niceTicks(0, xm), _niceTicks(ylo, yhi), px, py);
  if (ylo < 0) b.writeln("<line x1='${_n(px(0))}' y1='${_n(py(0))}' x2='${_n(px(xm))}' y2='${_n(py(0))}' stroke='#bbb'/>");
  for (var j = 0; j < bx.length; j++) {
    b
      ..writeln("<line x1='${_n(px(math.max(0, bx[j] - sx[j])))}' y1='${_n(py(by[j]))}' x2='${_n(px(bx[j] + sx[j]))}' y2='${_n(py(by[j]))}' stroke='#9aa'/>")
      ..writeln("<line x1='${_n(px(bx[j]))}' y1='${_n(py(by[j] - sy[j]))}' x2='${_n(px(bx[j]))}' y2='${_n(py(by[j] + sy[j]))}' stroke='#9aa'/>")
      ..writeln("<circle cx='${_n(px(bx[j]))}' cy='${_n(py(by[j]))}' r='2.5' fill='#333'/>");
  }
  b
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(0))}' x2='${_n(px(xm))}' y2='${_n(py(ivw * xm))}' stroke='#1f4e79' stroke-width='1.6'/>")
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(ei))}' x2='${_n(px(xm))}' y2='${_n(py(ei + eg * xm))}' stroke='#c0504d' stroke-width='1.6'/>")
    ..writeln("<line x1='${_n(px(0))}' y1='${_n(py(0))}' x2='${_n(px(xm))}' y2='${_n(py(md * xm))}' stroke='#4f8a3c' stroke-width='1.6' stroke-dasharray='5 3'/>")
    ..writeln(mo == null ? '' : "<line x1='${_n(px(0))}' y1='${_n(py(0))}' x2='${_n(px(xm))}' y2='${_n(py(mo * xm))}' stroke='#7b4f9e' stroke-width='1.4' stroke-dasharray='2 3'/>")
    ..writeln("<text x='${l + 8}' y='${t + 14}' fill='#1f4e79'>IVW</text><text x='${l + 48}' y='${t + 14}' fill='#c0504d'>MR-Egger</text>"
        "<text x='${l + 120}' y='${t + 14}' fill='#4f8a3c'>${tr('médiane pondérée', 'weighted median')}</text>"
        "${mo == null ? '' : "<text x='${l + 8}' y='${t + 30}' fill='#7b4f9e'>${tr('mode pondéré', 'weighted mode')}</text>"}")
    ..writeln('</svg>');
  return b.toString();
}
