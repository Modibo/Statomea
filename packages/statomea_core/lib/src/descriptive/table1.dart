/// « Tableau 1 » : caractéristiques des participants, globalement et par groupe, avec le test de comparaison adapté.
///  - Variable quantitative : moyenne ± écart-type si la distribution est à peu près symétrique dans chaque groupe
///    (|asymétrie| ≤ 1), sinon médiane [Q1 – Q3] (quantiles de type 7, comme R) ; test de Welch ou ANOVA, sinon
///    Mann-Whitney ou Kruskal-Wallis.
///  - Variable qualitative : n (%) par modalité, pourcentages des valeurs renseignées ; test du χ² (sans correction
///    de continuité), ou test exact de Fisher pour un tableau 2 × 2 dont un effectif attendu est < 5.
/// Les valeurs manquantes sont comptées et signalées. Les tests sont ceux du moteur, chacun validé contre R.
library;

import 'dart:math' as math;

import '../data/dataset.dart';
import '../i18n.dart';
import '../inference/compare.dart';
import '../inference/two_by_two.dart' show fisherExact;
import '../model/result.dart';
import 'descriptive.dart';

class Table1Row {
  final String variable;
  final String label; // libellé de la variable ou de la modalité
  final bool isLevel; // ligne de modalité (indentée)
  final String overall;
  final List<String> groups;
  final String p;
  final String test;
  const Table1Row(this.variable, this.label, this.isLevel, this.overall, this.groups, this.p, this.test);
}

class Table1 {
  final String? groupVariable;
  final List<String> groupNames;
  final List<int> groupN;
  final int n;
  final List<Table1Row> rows;
  final List<String> notes;
  const Table1(this.groupVariable, this.groupNames, this.groupN, this.n, this.rows, this.notes);

  /// En-tête : Caractéristique, Ensemble (N = …), groupes (n = …), p, test.
  List<String> get header => [
        tr('Caractéristique', 'Characteristic'),
        '${tr('Ensemble', 'Overall')} (N = $n)',
        for (var g = 0; g < groupNames.length; g++) '${groupNames[g]} (n = ${groupN[g]})',
        if (groupNames.isNotEmpty) ...['p', tr('Test', 'Test')],
      ];

  List<List<String>> get cells => [
        for (final r in rows) [r.isLevel ? '   ${r.label}' : r.label, r.overall, ...r.groups, if (groupNames.isNotEmpty) ...[r.p, r.test]],
      ];
}

double _skew(List<double> x) {
  if (x.length < 3) return 0;
  final m = x.reduce((a, b) => a + b) / x.length;
  var m2 = 0.0, m3 = 0.0;
  for (final v in x) {
    m2 += (v - m) * (v - m);
    m3 += (v - m) * (v - m) * (v - m);
  }
  m2 /= x.length;
  m3 /= x.length;
  return m2 == 0 ? 0 : m3 / math.pow(m2, 1.5);
}

String _p(double? p) {
  if (p == null || p.isNaN) return '—';
  if (p < 0.001) return tr('< 0,001', '< 0.001');
  return fmtFixed(p, p < 0.01 ? 3 : 2);
}

/// Tableau 1 de [ds], par [group] si donné. [variables] : par défaut toutes, sauf le groupe, les identifiants, les
/// dates et les textes libres. [labels] : libellés lisibles (sinon le libellé du dictionnaire, sinon le nom).
Table1 table1(Dataset ds, {String? group, List<String>? variables, int decimals = 1}) {
  final notes = <String>[];
  final groupRows = <String, List<int>>{};
  // Les lignes exclues au contrôle des données (étape 4) ne sont pas décrites.
  final excluded = ds.excludedRows;
  final all = [for (var i = 0; i < ds.rowCount; i++) if (!excluded.contains(i)) i];
  var rowsUsed = all;
  if (group != null) {
    final g = ds.text(group);
    for (final l in ds.levels(group)) {
      groupRows[l] = [for (final i in all) if (g[i] == l) i];
    }
    rowsUsed = [for (final i in all) if (g[i] != null) i];
    final miss = all.length - rowsUsed.length;
    if (miss > 0) notes.add(tr('$miss sujet(s) sans valeur de « $group » exclu(s).', '$miss subject(s) without a value of "$group" excluded.'));
    if (groupRows.length < 2) throw StatInputError('table1_groups', tr('« $group » doit avoir au moins deux modalités.', '"$group" must have at least two levels.'));
    if (groupRows.length > 6) throw StatInputError('table1_groups', tr('« $group » a ${groupRows.length} modalités : choisir une variable de groupe à 6 modalités au plus.', '"$group" has ${groupRows.length} levels: choose a grouping variable with at most 6 levels.'));
  }
  final vars = variables ??
      [
        for (final name in ds.names)
          if (name != group && !const [VarType.identifier, VarType.date, VarType.text].contains(ds.dictionary[name]?.type)) name
      ];
  String fmtN(double v) => fmtFixed(v, decimals);
  final out = <Table1Row>[];
  for (final name in vars) {
    final v = ds.dictionary[name];
    final label = (v == null || v.label.isEmpty) ? name : v.label;
    final unit = v == null || v.unit.isEmpty ? '' : ', ${v.unit}';
    final numeric = v?.type == VarType.numeric;
    if (numeric) {
      final x = ds.numeric(name);
      List<double> vals(List<int> idx) => [for (final i in idx) if (x[i] != null && x[i]!.isFinite) x[i]!];
      final overall = vals(rowsUsed);
      if (overall.isEmpty) continue;
      final groupsVals = [for (final e in groupRows.entries) vals(e.value)];
      final symmetric = [overall, ...groupsVals].every((g) => _skew(g).abs() <= 1);
      String desc(List<double> g) {
        if (g.isEmpty) return '—';
        if (symmetric) return '${fmtN(g.reduce((a, b) => a + b) / g.length)} ± ${g.length > 1 ? fmtN(sd(g)) : '—'}';
        final s = [...g]..sort();
        return '${fmtN(quantile(s, 0.5))} [${fmtN(quantile(s, 0.25))} – ${fmtN(quantile(s, 0.75))}]';
      }

      String p = '', test = '';
      if (groupRows.isNotEmpty && groupsVals.every((g) => g.length >= 2)) {
        final named = {for (final e in groupRows.entries) e.key: [for (final i in e.value) x[i]]};
        final AnalysisResult r;
        if (groupRows.length == 2) {
          final ks = named.keys.toList();
          r = symmetric ? tTestIndependent(named[ks[0]]!, named[ks[1]]!) : mannWhitney(named[ks[0]]!, named[ks[1]]!);
          test = symmetric ? tr('Welch', 'Welch') : 'Mann-Whitney';
        } else {
          r = symmetric ? anovaOneWay(named) : kruskalWallis(named);
          test = symmetric ? 'ANOVA' : 'Kruskal-Wallis';
        }
        p = _p(r.statistics['p']);
      }
      final missing = rowsUsed.length - overall.length;
      out.add(Table1Row(name, '$label$unit, ${symmetric ? tr('moyenne ± ET', 'mean ± SD') : tr('médiane [Q1 – Q3]', 'median [Q1 – Q3]')}', false, desc(overall), [for (final g in groupsVals) desc(g)], p, test));
      if (missing > 0) notes.add(tr('« $label » : $missing valeur(s) manquante(s).', '"$label": $missing missing value(s).'));
    } else {
      final t = ds.text(name);
      final levels = v?.order ?? ds.levels(name);
      if (levels.isEmpty || levels.length > 12) continue;
      List<int> counts(List<int> idx) => [for (final l in levels) idx.where((i) => t[i] == l).length];
      final overall = counts(rowsUsed);
      final totalO = overall.fold(0, (a, b) => a + b);
      if (totalO == 0) continue;
      final groupCounts = [for (final e in groupRows.entries) counts(e.value)];
      String p = '', test = '';
      if (groupRows.isNotEmpty) {
        final table = [for (var li = 0; li < levels.length; li++) [for (final gc in groupCounts) gc[li]]];
        final nonEmpty = [for (final r in table) if (r.any((c) => c > 0)) r];
        if (nonEmpty.length >= 2) {
          final rowT = [for (final r in nonEmpty) r.fold(0, (a, b) => a + b)];
          final colT = [for (var c = 0; c < groupCounts.length; c++) nonEmpty.fold(0, (a, r) => a + r[c])];
          final tot = rowT.fold(0, (a, b) => a + b);
          final minExpected = [for (final rt in rowT) for (final ct in colT) rt * ct / tot].reduce(math.min);
          if (nonEmpty.length == 2 && colT.length == 2 && minExpected < 5) {
            p = _p(fisherExact(nonEmpty[0][0], nonEmpty[0][1], nonEmpty[1][0], nonEmpty[1][1]).pValue);
            test = 'Fisher';
          } else {
            p = _p(chiSquareRxC(nonEmpty).statistics['p']);
            test = tr('χ²', 'χ²');
            if (minExpected < 5) notes.add(tr('« $label » : effectifs attendus < 5, test du χ² approximatif.', '"$label": expected counts < 5, approximate χ² test.'));
          }
        }
      }
      out.add(Table1Row(name, '$label, n (%)', false, '', [for (final _ in groupCounts) ''], p, test));
      final gTotals = [for (final gc in groupCounts) gc.fold(0, (a, b) => a + b)];
      String cell(int c, int tot) => tot == 0 ? '—' : '$c (${fmtFixed(100 * c / tot, decimals)})';
      for (var li = 0; li < levels.length; li++) {
        out.add(Table1Row(name, levels[li], true, cell(overall[li], totalO), [for (var g = 0; g < groupCounts.length; g++) cell(groupCounts[g][li], gTotals[g])], '', ''));
      }
      final missing = rowsUsed.length - totalO;
      if (missing > 0) notes.add(tr('« $label » : $missing valeur(s) manquante(s).', '"$label": $missing missing value(s).'));
    }
  }
  return Table1(group, groupRows.keys.toList(), [for (final r in groupRows.values) r.length], rowsUsed.length, out, notes);
}

/// Résultat journalisable du Tableau 1 (étape 6), avec le tableau prêt à exporter.
AnalysisResult table1Result(Dataset ds, {String? group, List<String>? variables}) {
  final t = table1(ds, group: group, variables: variables);
  return AnalysisResult(
    methodId: 'describe_table1',
    methodName: tr('Tableau 1 : caractéristiques des participants', 'Table 1: participant characteristics'),
    inputs: {'group': group, 'variables': variables ?? [for (final r in t.rows) if (!r.isLevel) r.variable]},
    formula: tr('Moyenne ± ET si |asymétrie| ≤ 1 dans chaque groupe, sinon médiane [Q1 – Q3] ; n (%) ; Welch/ANOVA ou Mann-Whitney/Kruskal-Wallis ; χ² ou Fisher (2 × 2, effectif attendu < 5).',
        'Mean ± SD if |skewness| ≤ 1 in each group, otherwise median [Q1 – Q3]; n (%); Welch/ANOVA or Mann-Whitney/Kruskal-Wallis; χ² or Fisher (2 × 2, expected count < 5).'),
    statistics: {'n': t.n.toDouble()},
    tables: [ResultTable(tr('Tableau 1', 'Table 1'), t.header, t.cells)],
    alerts: [for (final n in t.notes) Alert('table1_note', Severity.info, n)],
    interpretation: Interpretation(
      whyThisMethod: tr('Décrire les participants inclus${group == null ? '' : ' selon « $group »'} avant toute analyse d\'effet.', 'Describe the included participants${group == null ? '' : ' by "$group"'} before any effect analysis.'),
      whatItMeans: tr('${t.n} participants décrits ; chaque variable est résumée selon sa distribution.', '${t.n} participants described; each variable is summarised according to its distribution.'),
      notJustified: tr('Dans un essai randomisé, tester la comparabilité des groupes par des valeurs de p (CONSORT le déconseille) ; conclure à un effet à partir du Tableau 1.',
          'In a randomised trial, testing group comparability with p-values (CONSORT advises against it); concluding on an effect from Table 1.'),
    ),
  );
}
