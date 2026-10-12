/// Contrôle des données avant analyse. Le module DÉTECTE et PROPOSE ; il ne
/// modifie jamais les données. Chaque correction acceptée par l'utilisateur
/// devient une [Correction] journalisée (cf. dataset.dart).
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../model/result.dart';
import 'dataset.dart';

class QualityIssue {
  final String code;
  final Severity severity;
  final String? variable;
  final List<int> rows; // 0-based
  final String message;
  final String? suggestion;

  /// Correction proposée (à confirmer par l'utilisateur), le cas échéant.
  final Correction? proposed;
  const QualityIssue(this.code, this.severity, this.message,
      {this.variable, this.rows = const [], this.suggestion, this.proposed});

  Map<String, Object?> toJson() => {
        'code': code,
        'severity': severity.name,
        'variable': variable,
        'rows': rows,
        'message': message,
        'suggestion': suggestion,
      };
}

class VariableSummary {
  final String name;
  final VarType type;
  final int missing;
  final int distinct;
  final String preview;
  VariableSummary(this.name, this.type, this.missing, this.distinct, this.preview);
}

class QualityReport {
  final int rows;
  final List<VariableSummary> variables;
  final List<QualityIssue> issues;
  QualityReport(this.rows, this.variables, this.issues);

  int count(Severity s) => issues.where((i) => i.severity == s).length;
  bool get blocking => issues.any((i) => i.severity == Severity.critical);
}

/// Bornes physiologiques plausibles de variables courantes, repérées par leur
/// nom. Elles servent à SIGNALER (jamais à corriger) ; le dictionnaire de
/// l'utilisateur est prioritaire.
const Map<String, (double, double, String)> plausibleRanges = {
  'age': (0, 120, 'ans'),
  'poids': (0.3, 350, 'kg'),
  'taille': (30, 250, 'cm'),
  'imc': (10, 80, 'kg/m²'),
  'pas': (50, 300, 'mmHg'),
  'pad': (20, 200, 'mmHg'),
  'fc': (20, 250, '/min'),
  'temperature': (30, 45, '°C'),
  'hb': (2, 25, 'g/dL'),
  'tour_taille': (40, 200, 'cm'),
};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[éèê]'), 'e').replaceAll(RegExp(r'[^a-z0-9_]'), '_');

/// Rapport de qualité complet.
QualityReport checkQuality(Dataset ds, {String? outcome, String? idVariable, List<String> predictors = const []}) {
  final issues = <QualityIssue>[];
  final summaries = <VariableSummary>[];
  final excluded = ds.excludedRows;
  final rowsIdx = [for (var i = 0; i < ds.rowCount; i++) if (!excluded.contains(i)) i];

  // Doublons de lignes complètes.
  final seen = <String, int>{};
  final dupRows = <int>[];
  for (final i in rowsIdx) {
    final key = [for (final n in ds.names) if (ds.dictionary[n]?.type != VarType.identifier) ds.cell(i, n) ?? ''].join('\u0001');
    if (seen.containsKey(key)) {
      dupRows.add(i);
    } else {
      seen[key] = i;
    }
  }
  if (dupRows.isNotEmpty) {
    issues.add(QualityIssue('duplicate_rows', Severity.serious,
        tr('${dupRows.length} ligne(s) identique(s) à une ligne précédente (hors identifiant) : ${_rowsText(dupRows)}.', '${dupRows.length} row(s) identical to a previous row (excluding identifier): ${_rowsText(dupRows)}.'),
        rows: dupRows,
        suggestion: tr("Vérifier s'il s'agit d'une double saisie ; ne les exclure qu'après vérification à la source.", 'Check whether this is double entry; exclude them only after checking the source.')));
  }

  final idVar = idVariable ?? [for (final n in ds.names) if (ds.dictionary[n]?.type == VarType.identifier) n].firstOrNull ??
      [for (final n in ds.names) if (_norm(n) == 'id' || _norm(n).startsWith('id_') || _norm(n).endsWith('_id')) n].firstOrNull;
  if (idVar != null) {
    final counts = <String, List<int>>{};
    for (final i in rowsIdx) {
      final v = ds.cell(i, idVar);
      if (v != null && !isMissingToken(v)) counts.putIfAbsent(v.trim(), () => []).add(i);
    }
    final rep = counts.entries.where((e) => e.value.length > 1).toList();
    if (rep.isNotEmpty) {
      final rows = rep.expand((e) => e.value).toList();
      issues.add(QualityIssue('repeated_id', Severity.serious,
          tr('${rep.length} identifiant(s) « $idVar » présent(s) sur plusieurs lignes (p. ex. ${rep.take(3).map((e) => e.key).join(", ")}) : soit des doublons, soit des mesures répétées (format long, suivi). Les tests pour observations indépendantes seraient alors invalides.',
              '${rep.length} "$idVar" identifier(s) present on several rows (e.g. ${rep.take(3).map((e) => e.key).join(", ")}): either duplicates or repeated measures (long format, follow-up). Tests for independent observations would then be invalid.'),
          variable: idVar,
          rows: rows,
          suggestion: tr('Préciser la structure : un individu par ligne (doublons à résoudre) ou mesures répétées (analyse appariée ou modèle pour données corrélées).',
              'Specify the structure: one individual per row (duplicates to resolve) or repeated measures (paired analysis or a model for correlated data).')));
    }
  }

  for (final name in ds.names) {
    final v = ds.dictionary[name]!;
    final txt = [for (final i in rowsIdx) ds.cell(i, name)];
    final miss = [for (var k = 0; k < txt.length; k++) if (isMissingToken(txt[k])) rowsIdx[k]];
    final present = [for (final t in txt) if (!isMissingToken(t)) t!.trim()];
    summaries.add(VariableSummary(name, v.type, miss.length, present.toSet().length,
        present.take(4).join(' · ')));
    if (miss.isNotEmpty) {
      final share = miss.length / rowsIdx.length;
      issues.add(QualityIssue('missing', share > 0.2 ? Severity.serious : (share > 0.05 ? Severity.caution : Severity.info),
          tr('« $name » : ${miss.length} valeur(s) manquante(s) (${fmtPct(share)}).', '"$name": ${miss.length} missing value(s) (${fmtPct(share)}).'),
          variable: name,
          rows: miss,
          suggestion: share > 0.05
              ? tr("Décrire le mécanisme probable (MCAR, MAR, MNAR) ; comparer les sujets avec et sans valeur ; sous MAR, envisager l'imputation multiple (ateliers de régression et de prédiction).",
                  'Describe the likely mechanism (MCAR, MAR, MNAR); compare subjects with and without a value; under MAR, consider multiple imputation (regression and prediction workshops).')
              : null));
    }
    if (present.isEmpty) continue;

    if (v.type == VarType.numeric) {
      // Valeurs non numériques dans une colonne quantitative.
      final bad = <int>[];
      final badVals = <String>{};
      for (var k = 0; k < txt.length; k++) {
        final t = txt[k];
        if (!isMissingToken(t) && parseNumber(t) == null) {
          bad.add(rowsIdx[k]);
          badVals.add(t!.trim());
        }
      }
      if (bad.isNotEmpty) {
        final censored = badVals.any((s) => s.startsWith('<') || s.startsWith('>'));
        issues.add(QualityIssue('non_numeric', Severity.serious,
            tr("« $name » (quantitative) contient ${bad.length} valeur(s) non numérique(s) : ${badVals.take(5).map((s) => "« $s »").join(", ")}. Elles seront traitées comme manquantes si rien n'est fait.",
                '"$name" (quantitative) contains ${bad.length} non-numeric value(s): ${badVals.take(5).map((s) => '"$s"').join(", ")}. They will be treated as missing if nothing is done.'),
            variable: name,
            rows: bad,
            suggestion: censored
                ? tr("Valeurs censurées (« < seuil ») : décider explicitement d'une règle (seuil, seuil/2, analyse adaptée) et la documenter.", 'Censored values ("< threshold"): decide an explicit rule (threshold, threshold/2, suitable analysis) and document it.')
                : tr('Corriger à la source ou mettre en manquant de façon journalisée.', 'Correct at the source or set to missing with a logged entry.')));
      }
      final nums = [for (var k = 0; k < txt.length; k++) (row: rowsIdx[k], x: parseNumber(txt[k]))]
          .where((e) => e.x != null)
          .toList();
      // Bornes plausibles : dictionnaire, sinon connaissances par défaut.
      final key = _norm(name);
      final known = plausibleRanges[key];
      final lo = v.min ?? known?.$1, hi = v.max ?? known?.$2;
      if (lo != null || hi != null) {
        final out = [for (final e in nums) if ((lo != null && e.x! < lo) || (hi != null && e.x! > hi)) e];
        if (out.isNotEmpty) {
          issues.add(QualityIssue('out_of_range', Severity.serious,
              tr("« $name » : ${out.length} valeur(s) hors de l'intervalle plausible [${fmt(lo)} ; ${fmt(hi)}]${v.min == null && known != null ? " (borne par défaut, ${known.$3})" : ""} : ${out.take(5).map((e) => "${fmt(e.x)} (ligne ${e.row + 2})").join(", ")}.",
                  '"$name": ${out.length} value(s) outside the plausible range [${fmt(lo)}; ${fmt(hi)}]${v.min == null && known != null ? " (default bound, ${known.$3 == 'ans' ? 'years' : known.$3})" : ""}: ${out.take(5).map((e) => "${fmt(e.x)} (row ${e.row + 2})").join(", ")}.'),
              variable: name,
              rows: [for (final e in out) e.row],
              suggestion: tr("Vérifier l'unité et la saisie à la source ; corriger ou mettre en manquant avec justification.", 'Check the unit and entry at the source; correct or set to missing with a justification.')));
        }
      }
      // Mélange d'unités suspect : deux groupes séparés de plus d'un facteur 8.
      final pos = [for (final e in nums) if (e.x! > 0) e.x!]..sort();
      if (pos.length >= 20) {
        final logs = [for (final x in pos) math.log(x) / math.ln10];
        var bestGap = 0.0, at = -1;
        for (var k = 1; k < logs.length; k++) {
          final g = logs[k] - logs[k - 1];
          if (g > bestGap) {
            bestGap = g;
            at = k;
          }
        }
        final share = math.min(at, logs.length - at) / logs.length;
        if (bestGap > 0.9 && share >= 0.03) {
          issues.add(QualityIssue('unit_mix_suspected', Severity.serious,
              tr("« $name » : deux groupes de valeurs séparés d'un facteur ≈ ${fmt(math.pow(10, bestGap).toDouble(), digits: 2)} ($at valeur(s) ≤ ${fmt(pos[at - 1])}, ${pos.length - at} ≥ ${fmt(pos[at])}). Suspicion de mélange d'unités (p. ex. mmol/L et mg/dL, g/L et g/dL).",
                  '"$name": two groups of values separated by a factor ≈ ${fmt(math.pow(10, bestGap).toDouble(), digits: 2)} ($at value(s) ≤ ${fmt(pos[at - 1])}, ${pos.length - at} ≥ ${fmt(pos[at])}). Suspected mixture of units (e.g. mmol/L and mg/dL, g/L and g/dL).'),
              variable: name,
              suggestion: tr("Vérifier l'unité de chaque source ; convertir seulement avec une règle explicite et journalisée.", 'Check the unit of each source; convert only with an explicit, logged rule.')));
        }
      }
      // Valeurs négatives pour une grandeur généralement positive.
      final negatives = [for (final e in nums) if (e.x! < 0) e.row];
      if (negatives.isNotEmpty && lo == null && !key.contains('diff') && !key.contains('delta')) {
        issues.add(QualityIssue('negative_values', Severity.caution,
            tr('« $name » : ${negatives.length} valeur(s) négative(s). Plausible ?', '"$name": ${negatives.length} negative value(s). Plausible?'),
            variable: name, rows: negatives));
      }
    }

    if (v.type != VarType.numeric && v.type != VarType.identifier) {
      final numShare = present.where((t) => parseNumber(t) != null).length / present.length;
      if (numShare >= 0.5 && numShare < 1 && present.toSet().length > 5) {
        issues.add(QualityIssue('mixed_type', Severity.caution,
            tr('« $name » mêle ${fmtPct(numShare)} de valeurs numériques et des valeurs textuelles (${present.where((t) => parseNumber(t) == null).toSet().take(4).map((s) => "« $s »").join(", ")}).',
                '"$name" mixes ${fmtPct(numShare)} numeric values and text values (${present.where((t) => parseNumber(t) == null).toSet().take(4).map((s) => '"$s"').join(", ")}).'),
            variable: name,
            suggestion: tr('Déclarer le type de la variable dans le dictionnaire et traiter les valeurs non numériques explicitement.', 'Declare the variable type in the dictionary and handle non-numeric values explicitly.')));
      }
    }

    if (v.type == VarType.categorical || v.type == VarType.binary || v.type == VarType.ordinal) {
      // Modalités qui ne diffèrent que par la casse ou les espaces.
      final groups = <String, Set<String>>{};
      for (final s in present) {
        groups.putIfAbsent(s.toLowerCase().replaceAll(RegExp(r'\s+'), ' '), () => {}).add(s);
      }
      for (final g in groups.values.where((g) => g.length > 1)) {
        issues.add(QualityIssue('inconsistent_labels', Severity.serious,
            tr('« $name » : modalités qui ne diffèrent que par la casse ou les espaces : ${g.map((s) => "« $s »").join(", ")}. Elles seraient analysées comme des catégories distinctes.',
                '"$name": levels that differ only by case or spaces: ${g.map((s) => '"$s"').join(", ")}. They would be analysed as distinct categories.'),
            variable: name,
            suggestion: tr('Recoder en une modalité unique (correction journalisée).', 'Recode into a single level (logged correction).')));
      }
      final counts = <String, int>{};
      for (final s in present) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
      final rare = counts.entries.where((e) => e.value < 5).toList();
      if (rare.isNotEmpty && counts.length > 1) {
        issues.add(QualityIssue('sparse_category', Severity.caution,
            tr('« $name » : modalité(s) à effectif < 5 : ${rare.map((e) => "${e.key} (${e.value})").join(", ")}.', '"$name": level(s) with count < 5: ${rare.map((e) => "${e.key} (${e.value})").join(", ")}.'),
            variable: name,
            suggestion: tr("Risque de cellules nulles et d'estimations instables ; regrouper sur des bases cliniques, fixées avant l'analyse.", 'Risk of zero cells and unstable estimates; merge on clinical grounds, set before the analysis.')));
      }
      if (predictors.contains(name) && v.reference == null && counts.length > 1) {
        issues.add(QualityIssue('reference_undefined', Severity.caution,
            tr('« $name » : catégorie de référence non définie.', '"$name": reference category not defined.'),
            variable: name,
            suggestion: tr('Choisir une référence cliniquement interprétable et suffisamment fréquente.', 'Choose a clinically interpretable and sufficiently frequent reference.')));
      }
    }
  }

  // Issue binaire : événements rares, cellules nulles avec les prédicteurs qualitatifs.
  if (outcome != null && ds.names.contains(outcome)) {
    final y = ds.text(outcome);
    final lv = ds.levels(outcome);
    if (lv.length == 2) {
      final ev = lv.contains('1') ? '1' : lv.last;
      final nEv = [for (final i in rowsIdx) if (y[i] == ev) i].length;
      final nNon = [for (final i in rowsIdx) if (y[i] != null && y[i] != ev) i].length;
      final minority = math.min(nEv, nNon);
      if (minority < 10) {
        issues.add(QualityIssue('rare_events', Severity.serious,
            tr('Issue « $outcome » : seulement $minority observation(s) dans la classe la plus rare.', 'Outcome "$outcome": only $minority observation(s) in the rarer class.'),
            variable: outcome,
            suggestion: tr("Méthodes exactes, Firth, nombre de covariables très limité ; voir le mode « petit nombre d'événements ».", 'Exact methods, Firth, very limited number of covariates; see the "few events" mode.')));
      }
      for (final p in predictors) {
        final pv = ds.dictionary[p];
        if (pv == null || !(pv.type == VarType.categorical || pv.type == VarType.binary)) continue;
        final x = ds.text(p);
        final cells = <String, (int, int)>{};
        for (final i in rowsIdx) {
          if (x[i] == null || y[i] == null) continue;
          final c = cells[x[i]!] ?? (0, 0);
          cells[x[i]!] = y[i] == ev ? (c.$1 + 1, c.$2) : (c.$1, c.$2 + 1);
        }
        final zero = [for (final e in cells.entries) if (e.value.$1 == 0 || e.value.$2 == 0) e.key];
        if (zero.isNotEmpty) {
          issues.add(QualityIssue('zero_cell', Severity.serious,
              tr('Croisement « $p » × « $outcome » : cellule nulle pour ${zero.map((z) => "« $z »").join(", ")} (aucun ${cells[zero.first]!.$1 == 0 ? "événement" : "non-événement"}). Séparation probable en régression logistique.',
                  'Cross-tabulation "$p" × "$outcome": zero cell for ${zero.map((z) => '"$z"').join(", ")} (no ${cells[zero.first]!.$1 == 0 ? "event" : "non-event"}). Separation likely in logistic regression.'),
              variable: p,
              suggestion: tr('Firth, regroupement justifié a priori, ou présentation descriptive.', 'Firth, merging justified a priori, or descriptive presentation.')));
        }
      }
    }
  }

  // Structure appariée en format large (colonnes avant/après).
  final pairs = <String>[];
  final suffixes = [('_avant', '_apres'), ('_j0', '_j30'), ('_t0', '_t1'), ('_pre', '_post'), ('_1', '_2')];
  for (final n in ds.names) {
    for (final (a, b) in suffixes) {
      if (_norm(n).endsWith(a)) {
        final base = n.substring(0, n.length - a.length);
        final other = ds.names.where((m) => _norm(m) == _norm(base + b)).firstOrNull;
        if (other != null) pairs.add('$n / $other');
      }
    }
  }
  if (pairs.isNotEmpty) {
    issues.add(QualityIssue('paired_wide', Severity.info,
        tr('Colonnes vraisemblablement appariées (mêmes sujets) : ${pairs.join(" ; ")}. Utiliser des méthodes appariées pour les comparer.',
            'Columns likely paired (same subjects): ${pairs.join("; ")}. Use paired methods to compare them.'),
        suggestion: tr('Ne pas comparer ces colonnes comme deux groupes indépendants.', 'Do not compare these columns as two independent groups.')));
  }
  // Dates de suivi incohérentes.
  final dates = [for (final n in ds.names) if (ds.dictionary[n]!.type == VarType.date) n];
  if (dates.length >= 2) {
    final start = dates.first, end = dates.last;
    final bad = <int>[];
    for (final i in rowsIdx) {
      final a = _parseDate(ds.cell(i, start)), b = _parseDate(ds.cell(i, end));
      if (a != null && b != null && b.isBefore(a)) bad.add(i);
    }
    if (bad.isNotEmpty) {
      issues.add(QualityIssue('follow_up_order', Severity.serious,
          tr('${bad.length} ligne(s) où « $end » précède « $start » : durée de suivi négative.', '${bad.length} row(s) where "$end" precedes "$start": negative follow-up time.'),
          rows: bad, suggestion: tr("Vérifier l'ordre et le format des dates.", 'Check the order and format of the dates.')));
    }
  }
  issues.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return QualityReport(rowsIdx.length, summaries, issues);
}

/// Contrôle numérateur ≤ dénominateur (tableaux d'effectifs agrégés).
List<QualityIssue> checkDenominators(Dataset ds, String numerator, String denominator) {
  final a = ds.numeric(numerator), b = ds.numeric(denominator);
  final bad = [for (var i = 0; i < ds.rowCount; i++) if (a[i] != null && b[i] != null && (a[i]! > b[i]! || a[i]! < 0)) i];
  return [
    if (bad.isNotEmpty)
      QualityIssue('denominator', Severity.critical,
          tr('« $numerator » dépasse « $denominator » (ou est négatif) sur ${bad.length} ligne(s) : ${_rowsText(bad)}.', '"$numerator" exceeds "$denominator" (or is negative) on ${bad.length} row(s): ${_rowsText(bad)}.'),
          rows: bad, suggestion: tr("Effectifs discordants : vérifier l'extraction avant toute analyse.", 'Discordant counts: check the extraction before any analysis.'))
  ];
}

DateTime? _parseDate(String? s) {
  if (s == null) return null;
  final t = s.trim();
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
  if (m != null) return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  return null;
}

String _rowsText(List<int> rows) =>
    tr('ligne(s) ${rows.take(8).map((r) => r + 2).join(", ")}${rows.length > 8 ? "…" : ""} (numérotation du fichier, en-tête = ligne 1)',
        'row(s) ${rows.take(8).map((r) => r + 2).join(", ")}${rows.length > 8 ? "…" : ""} (file numbering, header = row 1)');
