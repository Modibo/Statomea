/// Modèle de résultat commun à toutes les analyses.
///
/// Un [AnalysisResult] contient tout ce qu'il faut pour reproduire et auditer
/// un calcul : données d'entrée (ou leur résumé), méthode et version, formule,
/// estimations, contrôles d'hypothèses, alertes, journal et interprétation.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../version.dart';

/// Statut de validation d'une méthode (cf. docs/06-validation.md).
enum MethodStatus {
  /// Comparée à un logiciel de référence avec des critères chiffrés satisfaits.
  validated,

  /// Implémentée mais non (ou incomplètement) validée : aucun résultat ne doit
  /// être présenté comme fiable.
  inDevelopment,
}

enum CheckStatus { ok, warning, violated, notAssessed }

enum Severity { info, caution, serious, critical }

String severityLabel(Severity s) => switch (s) {
      Severity.info => tr('Information', 'Information'),
      Severity.caution => tr('Prudence', 'Caution'),
      Severity.serious => tr('Grave', 'Serious'),
      Severity.critical => tr('Bloquant', 'Blocking'),
    };

String checkStatusLabel(CheckStatus s) => switch (s) {
      CheckStatus.ok => tr('satisfaite', 'met'),
      CheckStatus.warning => tr('à surveiller', 'to monitor'),
      CheckStatus.violated => tr('non satisfaite', 'not met'),
      CheckStatus.notAssessed => tr('non évaluable', 'not assessable'),
    };

/// Une estimation ponctuelle avec son intervalle de confiance.
class Estimate {
  final String label;
  final double value;
  final double? lower;
  final double? upper;
  final double level;
  final double? pValue;
  final double? se;

  /// Nature de l'intervalle : « IC » par défaut. Les limites d'accord de
  /// Bland-Altman ou un intervalle de prédiction ne sont PAS des IC, et cette
  /// étiquette est relue par l'audit.
  final String intervalKind;

  const Estimate(this.label, this.value,
      {this.lower,
      this.upper,
      this.level = 0.95,
      this.pValue,
      this.se,
      this.intervalKind = 'IC'});

  bool get hasInterval => lower != null && upper != null;

  factory Estimate.fromJson(Map<String, Object?> j) => Estimate(j['label'] as String, _den(j['value'])!,
      lower: _den(j['lower']),
      upper: _den(j['upper']),
      level: (j['level'] as num?)?.toDouble() ?? 0.95,
      pValue: _den(j['p']),
      se: _den(j['se']),
      intervalKind: (j['interval'] as String?) ?? 'IC');

  Map<String, Object?> toJson() => {
        'label': label,
        'value': _num(value),
        'lower': _num(lower),
        'upper': _num(upper),
        'level': level,
        'interval': intervalKind,
        if (pValue != null) 'p': _num(pValue),
        if (se != null) 'se': _num(se),
      };
}

/// Contrôle d'une hypothèse ou diagnostic.
class Check {
  final String id;
  final String label;
  final CheckStatus status;
  final String detail;
  const Check(this.id, this.label, this.status, this.detail);

  Map<String, Object?> toJson() =>
      {'id': id, 'label': label, 'status': status.name, 'detail': detail};

  factory Check.fromJson(Map<String, Object?> j) =>
      Check(j['id'] as String, j['label'] as String, CheckStatus.values.byName(j['status'] as String), (j['detail'] as String?) ?? '');
}

/// Alerte émise par le moteur, les contrôles de données ou l'audit.
class Alert {
  final String code;
  final Severity severity;
  final String message;
  final String? suggestion;

  /// Élément déclencheur (valeur, cellule, passage de texte…).
  final String? trigger;
  const Alert(this.code, this.severity, this.message, {this.suggestion, this.trigger});

  Map<String, Object?> toJson() => {
        'code': code,
        'severity': severity.name,
        'message': message,
        if (suggestion != null) 'suggestion': suggestion,
        if (trigger != null) 'trigger': trigger,
      };

  factory Alert.fromJson(Map<String, Object?> j) => Alert(j['code'] as String, Severity.values.byName(j['severity'] as String),
      j['message'] as String,
      suggestion: j['suggestion'] as String?, trigger: j['trigger'] as String?);
}

/// Tableau de résultats (affichable et exportable en CSV).
class ResultTable {
  final String title;
  final List<String> header;
  final List<List<String>> rows;
  const ResultTable(this.title, this.header, this.rows);

  Map<String, Object?> toJson() => {'title': title, 'header': header, 'rows': rows};

  factory ResultTable.fromJson(Map<String, Object?> j) => ResultTable(j['title'] as String,
      [for (final h in j['header'] as List) h as String], [for (final r in j['rows'] as List) [for (final c in r as List) c as String]]);
}

/// Les trois questions posées après chaque calcul (§8 du cahier des charges).
class Interpretation {
  final String whyThisMethod;
  final String whatItMeans;
  final String notJustified;
  const Interpretation(
      {required this.whyThisMethod, required this.whatItMeans, required this.notJustified});

  Map<String, Object?> toJson() =>
      {'why': whyThisMethod, 'meaning': whatItMeans, 'notJustified': notJustified};

  factory Interpretation.fromJson(Map<String, Object?> j) => Interpretation(
      whyThisMethod: (j['why'] as String?) ?? '', whatItMeans: (j['meaning'] as String?) ?? '', notJustified: (j['notJustified'] as String?) ?? '');
}

class AnalysisResult {
  final String methodId;
  final String methodName;
  final MethodStatus status;
  final Map<String, Object?> inputs;
  final String formula;
  final List<Estimate> estimates;
  final Map<String, double> statistics;
  final List<Check> checks;
  final List<Alert> alerts;
  final List<ResultTable> tables;
  final List<String> log;
  final Interpretation interpretation;

  /// Données graphiques éventuelles (forest plot, calibration…), sérialisables.
  final Map<String, Object?> figures;

  /// Langue dans laquelle les textes du résultat ont été rédigés (fixée au calcul).
  final Lang lang;

  AnalysisResult({
    required this.methodId,
    required this.methodName,
    this.status = MethodStatus.validated,
    required this.inputs,
    required this.formula,
    this.estimates = const [],
    this.statistics = const {},
    this.checks = const [],
    this.alerts = const [],
    this.tables = const [],
    this.log = const [],
    required this.interpretation,
    this.figures = const {},
    Lang? lang,
  }) : lang = lang ?? currentLang;

  Estimate? estimate(String label) {
    for (final e in estimates) {
      if (e.label == label) return e;
    }
    return null;
  }

  bool get reliable =>
      status == MethodStatus.validated &&
      !alerts.any((a) => a.severity == Severity.critical);

  Map<String, Object?> toJson() => {
        'method': methodId,
        'methodName': methodName,
        'status': status.name,
        'engine': engineName,
        'engineVersion': engineVersion,
        'lang': lang.name,
        'inputs': sanitizeJson(inputs),
        'formula': formula,
        'estimates': [for (final e in estimates) e.toJson()],
        'statistics': {for (final e in statistics.entries) e.key: _num(e.value)},
        'checks': [for (final c in checks) c.toJson()],
        'alerts': [for (final a in alerts) a.toJson()],
        'tables': [for (final t in tables) t.toJson()],
        'log': log,
        'interpretation': interpretation.toJson(),
        'figures': sanitizeJson(figures),
      };
}

/// Reconstruit un résultat depuis le journal (le moteur ne recalcule rien).
AnalysisResult analysisResultFromJson(Map<String, Object?> j) => AnalysisResult(
      methodId: j['method'] as String,
      methodName: j['methodName'] as String,
      status: MethodStatus.values.byName((j['status'] as String?) ?? 'validated'),
      inputs: ((j['inputs'] as Map?) ?? {}).cast<String, Object?>(),
      formula: (j['formula'] as String?) ?? '',
      estimates: [for (final e in (j['estimates'] as List? ?? [])) Estimate.fromJson((e as Map).cast())],
      statistics: {
        for (final e in ((j['statistics'] as Map?) ?? {}).entries)
          if (_den(e.value) != null) e.key as String: _den(e.value)!
      },
      checks: [for (final c in (j['checks'] as List? ?? [])) Check.fromJson((c as Map).cast())],
      alerts: [for (final a in (j['alerts'] as List? ?? [])) Alert.fromJson((a as Map).cast())],
      tables: [for (final t in (j['tables'] as List? ?? [])) ResultTable.fromJson((t as Map).cast())],
      log: [for (final l in (j['log'] as List? ?? [])) l as String],
      interpretation: Interpretation.fromJson(((j['interpretation'] as Map?) ?? {}).cast()),
      figures: ((j['figures'] as Map?) ?? {}).cast<String, Object?>(),
      lang: Lang.values.asNameMap()[j['lang']] ?? Lang.fr,
    );

/// Remplace récursivement les doubles non finis (non représentables en JSON).
Object? sanitizeJson(Object? v) => switch (v) {
      double d when !d.isFinite => _num(d),
      Map m => {for (final e in m.entries) e.key.toString(): sanitizeJson(e.value)},
      Iterable l => [for (final x in l) sanitizeJson(x)],
      _ => v,
    };

double? _den(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      'NaN' => double.nan,
      'Inf' => double.infinity,
      '-Inf' => double.negativeInfinity,
      _ => null,
    };

Object? _num(double? v) {
  if (v == null) return null;
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Inf' : '-Inf';
  return v;
}

/// Erreur levée quand les données ne permettent pas la méthode demandée.
/// Le message est destiné à l'utilisateur (français, explicite).
class StatInputError implements Exception {
  final String code;
  final String message;
  StatInputError(this.code, this.message);
  @override
  String toString() => 'StatInputError($code) : $message';
}

// ---------------------------------------------------------- Mise en forme

/// Formate un nombre à [digits] chiffres significatifs, en notation
/// française (virgule décimale).
String _dec(String s) => currentLang == Lang.en ? s.replaceFirst('-', '−') : s.replaceAll('.', ',').replaceFirst('-', '−');

String fmt(double? v, {int digits = 3}) {
  if (v == null) return '—';
  if (v.isNaN) return 'NA';
  if (v.isInfinite) return v > 0 ? '+∞' : '−∞';
  // Valeurs numériquement nulles (résidus d'arrondi, p. ex. −8e-16) : « 0 ».
  if (v == 0 || v.abs() < 1e-12) return '0';
  final mag = (math.log(v.abs()) / math.ln10).floor();
  final decimals = math.max(0, digits - 1 - mag).clamp(0, 12);
  return _dec(v.toStringAsFixed(decimals));
}

/// Formate un nombre avec un nombre fixe de décimales.
String fmtFixed(double? v, int decimals) {
  if (v == null) return '—';
  if (v.isNaN) return 'NA';
  if (v.isInfinite) return v > 0 ? '+∞' : '−∞';
  return _dec(v.toStringAsFixed(decimals));
}

/// Pourcentage à une décimale (« 12,3 % » ; « 12.3% » en anglais).
String fmtPct(double? v, {int decimals = 1}) =>
    v == null ? '—' : '${fmtFixed(v * 100, decimals)}${tr(' %', '%')}';

/// Valeur de p selon les recommandations usuelles (p < 0,001 sous le seuil).
String fmtP(double? p) {
  if (p == null || p.isNaN) return '—';
  if (p < 0.001) return tr('p < 0,001', 'p < 0.001');
  if (p < 0.01) return 'p = ${fmtFixed(p, 3)}';
  return 'p = ${fmtFixed(p, 2)}';
}

/// Nom de l'intervalle (codes internes « IC », « IP »).
String intervalName(String kind) => switch (kind) { 'IC' => tr('IC', 'CI'), 'IP' => tr('IP', 'PI'), _ => kind };

String fmtCi(Estimate e, {int digits = 3}) {
  final pct = (e.level * 100).round();
  if (!e.hasInterval) return fmt(e.value, digits: digits);
  return tr(
      '${fmt(e.value, digits: digits)} (${intervalName(e.intervalKind)} $pct % : ${fmt(e.lower, digits: digits)} à ${fmt(e.upper, digits: digits)})',
      '${fmt(e.value, digits: digits)} ($pct% ${intervalName(e.intervalKind)}: ${fmt(e.lower, digits: digits)} to ${fmt(e.upper, digits: digits)})');
}
