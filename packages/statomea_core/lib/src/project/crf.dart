/// Fiche de recueil et masque de saisie tirés du protocole : une variable par champ, avec type, unité, bornes plausibles
/// et modalités. Les variables viennent de la rubrique « variables » du protocole importé (sinon du dictionnaire des
/// données déjà importées) ; un identifiant, la date d'inclusion et le critère de jugement principal sont toujours
/// présents. Unités et bornes sont des valeurs usuelles à vérifier (elles servent à refuser les saisies aberrantes,
/// pas de valeurs normales).
library;

import '../audit/audit.dart' show foldAccents;
import '../advisor/advisor.dart';
import '../data/dataset.dart';
import '../i18n.dart';
import 'project.dart';
import 'review.dart' show protocolVariables;

enum CrfType { identifier, date, numeric, binary, categorical, text }

String crfTypeWord(CrfType t) => switch (t) {
      CrfType.identifier => tr('identifiant', 'identifier'),
      CrfType.date => 'date',
      CrfType.numeric => tr('numérique', 'numeric'),
      CrfType.binary => tr('binaire', 'binary'),
      CrfType.categorical => tr('catégorielle', 'categorical'),
      CrfType.text => tr('texte', 'text'),
    };

class CrfField {
  final String code;
  final String label;
  final CrfType type;
  final String unit;
  final double? min, max;
  final List<String> levels;
  const CrfField(this.code, this.label, this.type, {this.unit = '', this.min, this.max, this.levels = const []});
}

String _n(String s) => foldAccents(s.toLowerCase()).replaceAll('’', "'");

typedef _Known = (String re, CrfType type, String unit, double? min, double? max, List<String> Function() levels);

List<String> _none() => const [];
List<String> _yesNo() => [tr('oui', 'yes'), tr('non', 'no')];

/// Unités et bornes usuelles (ordre : le plus spécifique d'abord).
final List<_Known> _known = [
  (r"tour de taille|perimetre abdominal|waist", CrfType.numeric, 'cm', 40, 200, _none),
  (r"\bage\b|\bâge\b", CrfType.numeric, tr('ans', 'years'), 0, 120, _none),
  (r"\bpoids\b|weight", CrfType.numeric, 'kg', 0.5, 300, _none),
  (r"\btaille\b|height", CrfType.numeric, 'cm', 30, 250, _none),
  (r"\bimc\b|\bbmi\b|masse corporelle", CrfType.numeric, 'kg/m²', 10, 80, _none),
  (r"temperature", CrfType.numeric, '°C', 30, 45, _none),
  (r"frequence cardiaque|\bpouls\b|heart rate", CrfType.numeric, tr('bpm', 'bpm'), 20, 250, _none),
  (r"hba1c|hemoglobine glyquee|glycated", CrfType.numeric, '%', 3, 20, _none),
  (r"glycemie|glucose", CrfType.numeric, 'mmol/L', 0.5, 50, _none),
  (r"hemoglobine|\bhb\b|haemoglobin|hemoglobin", CrfType.numeric, 'g/dL', 2, 25, _none),
  (r"creatinine", CrfType.numeric, 'µmol/L', 10, 2000, _none),
  (r"\buree\b|\burea\b", CrfType.numeric, 'mmol/L', 0.5, 100, _none),
  (r"\bsodium\b|^na$", CrfType.numeric, 'mmol/L', 100, 180, _none),
  (r"potassium|^k$", CrfType.numeric, 'mmol/L', 1.5, 9, _none),
  (r"chlore|chlorure|chloride|^cl$", CrfType.numeric, 'mmol/L', 60, 150, _none),
  (r"calcium ionise|ionized calcium|^ica", CrfType.numeric, 'mmol/L', 0.3, 2.5, _none),
  (r"bicarbonate|hco3", CrfType.numeric, 'mmol/L', 2, 60, _none),
  (r"\bhdl\b", CrfType.numeric, 'mmol/L', 0.1, 5, _none),
  (r"\bldl\b", CrfType.numeric, 'mmol/L', 0.1, 15, _none),
  (r"cholesterol", CrfType.numeric, 'mmol/L', 0.1, 20, _none),
  (r"\bcrp\b|proteine c reactive|c-reactive", CrfType.numeric, 'mg/L', 0, 500, _none),
  (r"\basat\b|\bast\b|\bsgot\b|aspartate", CrfType.numeric, 'UI/L', 0, 5000, _none),
  (r"\balat\b|\balt\b|\bsgpt\b|alanine", CrfType.numeric, 'UI/L', 0, 5000, _none),
  (r"acide urique|uric acid", CrfType.numeric, 'µmol/L', 50, 1500, _none),
  (r"albumin", CrfType.numeric, 'g/L', 5, 60, _none),
  (r"ferritin", CrfType.numeric, 'µg/L', 1, 5000, _none),
  (r"\btsh\b", CrfType.numeric, 'mUI/L', 0.001, 100, _none),
  (r"bilirubin", CrfType.numeric, 'µmol/L', 1, 800, _none),
  (r"microalbumin|proteinurie|proteinuria", CrfType.numeric, 'mg/L', 0, 5000, _none),
  (r"triglycerid", CrfType.numeric, 'mmol/L', 0.1, 50, _none),
  (r"\binr\b|prothrombin", CrfType.numeric, '', 0.5, 15, _none),
  (r"cephaline|\btca\b|aptt|\bptt\b", CrfType.numeric, 's', 15, 200, _none),
  (r"fibrinogen", CrfType.numeric, 'g/L', 0, 10, _none),
  (r"plaquett|platelet", CrfType.numeric, 'G/L', 0, 2000, _none),
  (r"leucocyt|globules blancs|white (blood )?cells", CrfType.numeric, 'G/L', 0, 300, _none),
  (r"lactate", CrfType.numeric, 'mmol/L', 0, 30, _none),
  (r"\bph\b", CrfType.numeric, '', 6.5, 8, _none),
  (r"sao2|saturation", CrfType.numeric, '%', 0, 100, _none),
  (r"pco2|dioxyde de carbone|carbon dioxide", CrfType.numeric, 'mmHg', 5, 150, _none),
  (r"\bpo2\b|pression partielle en oxygene|oxygen tension", CrfType.numeric, 'mmHg', 10, 700, _none),
  (r"glasgow", CrfType.numeric, '', 3, 15, _none),
  (r"\biss\b|injury severity", CrfType.numeric, '', 0, 75, _none),
  (r"indice de choc|shock index", CrfType.numeric, '', 0, 5, _none),
  (r"\bsexe\b|\bgenre\b|\bsex\b|gender", CrfType.categorical, '', null, null, () => const ['F', 'M']),
  (r"niveau d'instruction|scolarisation|education", CrfType.categorical, '', null, null,
      () => [tr('aucun', 'none'), tr('primaire', 'primary'), tr('secondaire', 'secondary'), tr('supérieur', 'higher')]),
  (r"tabagisme|tabac|smok|alcool|alcohol|antecedent|diabete|hypertension|vaccin|deces|transfusion|grossesse|pregnan|history of", CrfType.binary, '', null, null, _yesNo),
  (r"\bdate\b", CrfType.date, '', null, null, _none),
  (r"profession|occupation|mecanisme|mechanism|traitement|treatment|commentaire|comment", CrfType.text, '', null, null, _none),
];

CrfField _field(String code, String label) {
  final n = _n('$label $code');
  for (final (re, type, unit, min, max, levels) in _known) {
    if (RegExp(re).hasMatch(n)) return CrfField(code, label, type, unit: unit, min: min, max: max, levels: levels());
  }
  return CrfField(code, label, CrfType.numeric);
}

String _slug(String s) => _n(s).replaceAll(RegExp(r"[^a-z0-9]+"), '_').replaceAll(RegExp(r"^_+|_+$"), '');

/// Analyte reconnu dans les rubriques d'examens (« Examens de laboratoire », « Dosage des paramètres… »).
class LabTest {
  final String code, label;
  final String? method; // méthode de dosage citée à proximité
  final String pattern; // motif de reconnaissance (texte normalisé)
  const LabTest(this.code, this.label, this.method, [this.pattern = '']);
}

/// Analytes usuels : nom de colonne, libellé, motif de reconnaissance (texte normalisé).
final List<(String, String Function(), String)> _analytes = [
  ('hba1c', () => tr('Hémoglobine glyquée (HbA1c)', 'Glycated haemoglobin (HbA1c)'), r"hba1c|hemoglobine glyquee|glycated h"),
  ('glycemie', () => tr('Glycémie à jeun', 'Fasting glucose'), r"glycemie|glucose"),
  ('cholesterol_total', () => tr('Cholestérol total', 'Total cholesterol'), r"cholesterol total|total cholesterol"),
  ('hdl', () => tr('Cholestérol HDL', 'HDL cholesterol'), r"\bhdl\b"),
  ('ldl', () => tr('Cholestérol LDL', 'LDL cholesterol'), r"\bldl\b"),
  ('triglycerides', () => tr('Triglycérides', 'Triglycerides'), r"triglycerid"),
  ('creatinine', () => tr('Créatinine', 'Creatinine'), r"creatinin"),
  ('uree', () => tr('Urée', 'Urea'), r"\buree\b|\burea\b"),
  ('acide_urique', () => tr('Acide urique', 'Uric acid'), r"acide urique|uric acid"),
  ('sodium', () => tr('Sodium (Na⁺)', 'Sodium (Na⁺)'), r"\bsodium\b|\bna\+"),
  ('potassium', () => tr('Potassium (K⁺)', 'Potassium (K⁺)'), r"potassium|\bk\+"),
  ('chlore', () => tr('Chlore (Cl⁻)', 'Chloride (Cl⁻)'), r"\bchlore\b|chlorure|chloride|\bcl-"),
  ('hemoglobine', () => tr('Hémoglobine', 'Haemoglobin'), r"hemoglobine(?! glyquee)|\bhb\b(?!a1c)|haemoglobin(?! a1c)"),
  ('leucocytes', () => tr('Leucocytes', 'White blood cells'), r"leucocyt|globules blancs|\bgb\b|white blood"),
  ('plaquettes', () => tr('Plaquettes', 'Platelets'), r"plaquett|platelet|\bplt\b"),
  ('crp', () => tr('Protéine C réactive (CRP)', 'C-reactive protein (CRP)'), r"\bcrp\b|proteine c reactive"),
  ('asat', () => tr('ASAT', 'AST'), r"\basat\b|\bsgot\b"),
  ('alat', () => tr('ALAT', 'ALT'), r"\balat\b|\bsgpt\b"),
  ('albumine', () => tr('Albumine', 'Albumin'), r"albumin(?!urie)"),
  ('microalbuminurie', () => tr('Microalbuminurie', 'Microalbuminuria'), r"microalbumin"),
  ('ferritine', () => tr('Ferritine', 'Ferritin'), r"ferritin"),
  ('tsh', () => 'TSH', r"\btsh\b"),
  ('bilirubine', () => tr('Bilirubine totale', 'Total bilirubin'), r"bilirubin"),
];

/// Analytes cités dans les rubriques d'examens du protocole, dans l'ordre d'apparition, avec la méthode de dosage
/// citée dans les 250 caractères qui suivent (« méthode colorimétrique enzymatique », « électrode ion-sélective »…).
List<LabTest> protocolLabTests(Project p) {
  final raw = p.protocol['labtests'] ?? '';
  if (raw.isEmpty) return const [];
  final t = _n(raw);
  final found = <(int, LabTest)>[];
  for (final (code, label, re) in _analytes) {
    final ms = RegExp(re).allMatches(t).toList();
    if (ms.isEmpty) continue;
    final methodRe = RegExp(r"(methode [a-z\- ]{4,50}?|test [a-z\- ]*(enzymatique|colorimetrique|immuno)[a-z\- ]*|electrode[a-z\- ]{0,30}|impedance[a-z\- ]{0,20}|cytometrie[a-z\- ]{0,20}|chromatographie[a-z\- ]{0,30}|turbidimetri[a-z\- ]{0,20}|immunoturbidimetri[a-z\- ]{0,20})(?=[.,;:(]|\s{2}|$)");
    // Première mention suivie d'une méthode de dosage (la première mention est souvent une simple liste).
    String? method;
    for (final m in ms) {
      var after = t.substring(m.end, (m.end + 250).clamp(0, t.length));
      // La fenêtre s'arrête au bloc suivant (« Principe du dosage du … »).
      final next = RegExp(r"principe d|dosage (du|de la|de l'|des|d')").firstMatch(after);
      if (next != null) after = after.substring(0, next.start);
      final tech = RegExp(r"enzymat|colorim|immuno|electrode|chromatograph|turbidim|impedance|cytometr|hexokinase|oxydase|jaffe|potentiometr|spectrophotom|hplc|ion[- ]selecti|photometr|nephelometr|clauss|coagulom");
      for (final mm in methodRe.allMatches(after)) {
        if (tech.hasMatch(mm.group(1)!)) {
          method = mm.group(1)!.trim();
          break;
        }
      }
      if (method != null) break;
    }
    final m = ms.first;
    found.add((m.start, LabTest(code, label(), method, re)));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// Champs de la fiche : identifiant, date d'inclusion, variables du protocole (la pression artérielle donne deux
/// champs, systolique et diastolique), critère de jugement principal s'il n'est pas déjà couvert. Liste vide si le
/// projet ne décrit aucune variable.
List<CrfField> crfFields(Project p) {
  final out = <CrfField>[];
  final seen = <String>{};
  void add(CrfField f) {
    if (seen.add(f.code)) out.add(f);
  }

  final vars = protocolVariables(p);
  final labs = protocolLabTests(p);
  final fromData = vars.isEmpty && labs.isEmpty && p.dataset != null;
  if (vars.isEmpty && labs.isEmpty && !fromData) return const [];
  add(CrfField('id', tr('Identifiant anonyme du participant', 'Anonymous participant identifier'), CrfType.identifier));
  add(CrfField('date_inclusion', tr('Date d\'inclusion', 'Date of enrolment'), CrfType.date));
  if (fromData) {
    final ds = p.dataset!;
    for (final name in ds.names) {
      final v = ds.dictionary[name];
      final code = _slug(name);
      if (code == 'id' || v == null) continue;
      final guess = _field(code, v.label.isEmpty ? name : v.label);
      final type = switch (v.type) {
        VarType.numeric => CrfType.numeric,
        VarType.binary => CrfType.binary,
        VarType.categorical || VarType.ordinal => CrfType.categorical,
        VarType.date => CrfType.date,
        VarType.identifier => CrfType.identifier,
        _ => guess.type,
      };
      add(CrfField(code, v.label.isEmpty ? name : v.label, type,
          unit: v.unit.isNotEmpty ? v.unit : guess.unit, min: v.min ?? guess.min, max: v.max ?? guess.max, levels: guess.levels));
    }
  } else {
    for (final v in vars) {
      if (RegExp(r"pression arterielle|blood pressure").hasMatch(_n(v.label)) && !RegExp(r"systol|diastol|moyenne|mean").hasMatch(_n(v.label))) {
        add(CrfField(tr('pas', 'sbp'), tr('Pression artérielle systolique', 'Systolic blood pressure'), CrfType.numeric, unit: 'mmHg', min: 40, max: 300));
        add(CrfField(tr('pad', 'dbp'), tr('Pression artérielle diastolique', 'Diastolic blood pressure'), CrfType.numeric, unit: 'mmHg', min: 20, max: 200));
        continue;
      }
      add(_field(v.code, v.label[0].toUpperCase() + v.label.substring(1)));
    }
    // Examens décrits dans les rubriques de dosage, s'ils ne sont pas déjà dans la liste des variables.
    for (final l in labs) {
      // Doublon : même nom de colonne, ou même premier mot (« glycemie » ↔ « glycemie_jeun ») ; l'hémoglobine (Hb) reste
      // distincte de l'hémoglobine glyquée (HbA1c).
      final stem = l.code.split('_').first;
      // … ou variable déjà décrite qui désigne le même analyte (« numération plaquettaire » ↔ « plaquettes »).
      if (out.any((f) => f.code == l.code || f.code.split('_').first == stem || (l.pattern.isNotEmpty && RegExp(l.pattern).hasMatch(_n('${f.code} ${f.label}'))))) continue;
      add(_field(l.code, l.label));
    }
  }
  // Critère de jugement principal, s'il n'est pas déjà dans la liste.
  final q = p.question;
  final outcome = q.outcome.trim();
  if (outcome.isNotEmpty) {
    final key = _slug(outcome).split('_').where((w) => w.length > 3).take(2).join('_');
    final covered = key.isEmpty || out.any((f) => f.code.contains(key.split('_').first) || _slug(f.label).contains(key.split('_').first));
    if (!covered) {
      final label = '${tr('Critère principal : ', 'Primary outcome: ')}$outcome';
      switch (q.outcomeType) {
        case OutcomeType.binary:
          add(CrfField('critere_principal', label, CrfType.binary, levels: _yesNo()));
        case OutcomeType.timeToEvent:
          add(CrfField('evenement', label, CrfType.binary, levels: _yesNo()));
          add(CrfField('date_evenement', tr('Date de l\'événement ou des dernières nouvelles', 'Date of event or last contact'), CrfType.date));
        case OutcomeType.continuous || OutcomeType.count:
          add(CrfField('critere_principal', label, CrfType.numeric));
        default:
          add(CrfField('critere_principal', label, CrfType.text));
      }
    }
  }
  return out;
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Dictionnaire de données complet (CSV « ; ») : variable, type, libellé, unité, min, max, modalités.
String crfDictionaryCsv(List<CrfField> fields) {
  String cell(String c) => c.contains(';') || c.contains('"') ? '"${c.replaceAll('"', '""')}"' : c;
  final rows = [
    ['variable', 'type', tr('libelle', 'label'), tr('unite', 'unit'), 'min', 'max', tr('modalites', 'levels')],
    for (final f in fields) [f.code, crfTypeWord(f.type), f.label, f.unit, f.min == null ? '' : _num(f.min!), f.max == null ? '' : _num(f.max!), f.levels.join(';')],
  ];
  return '${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
}

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _col(int i) {
  var s = '';
  var k = i + 1;
  while (k > 0) {
    final r = (k - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    k = (k - 1) ~/ 26;
  }
  return s;
}

/// Masque de saisie Excel (.xlsx) : parties XML du classeur (à zipper par l'application). Feuille « Données » (une
/// colonne par variable, en-tête figé, listes déroulantes pour les variables qualitatives, bornes pour les
/// quantitatives, dates contrôlées, [rows] lignes préparées) et feuille « Dictionnaire » (relue à l'import, étape 4).
Map<String, String> crfWorkbookParts(List<CrfField> fields, {String title = '', int rows = 500}) {
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  String cell(String ref, String v, {int style = 0}) => '<c r="$ref" t="inlineStr"${style > 0 ? ' s="$style"' : ''}><is><t xml:space="preserve">${_x(v)}</t></is></c>';
  final last = rows + 1;
  final data = StringBuffer('<row r="1">');
  for (var i = 0; i < fields.length; i++) {
    data.write(cell('${_col(i)}1', fields[i].code, style: 1));
  }
  data.write('</row>');
  final dv = StringBuffer();
  var nDv = 0;
  for (var i = 0; i < fields.length; i++) {
    final f = fields[i];
    final range = '${_col(i)}2:${_col(i)}$last';
    final unit = f.unit.isEmpty ? '' : ' ${f.unit}';
    if (f.levels.isNotEmpty) {
      nDv++;
      dv.write('<dataValidation type="list" allowBlank="1" showInputMessage="1" showErrorMessage="1" errorTitle="${_x(f.code)}" error="${_x(tr('Choisir dans la liste : ${f.levels.join(', ')}', 'Choose from the list: ${f.levels.join(', ')}'))}" promptTitle="${_x(f.code)}" prompt="${_x(f.label)}" sqref="$range"><formula1>"${_x(f.levels.join(','))}"</formula1></dataValidation>');
    } else if (f.type == CrfType.numeric && f.min != null && f.max != null) {
      nDv++;
      dv.write('<dataValidation type="decimal" operator="between" allowBlank="1" showInputMessage="1" showErrorMessage="1" errorTitle="${_x(f.code)}" error="${_x(tr('Valeur attendue entre ${_num(f.min!)} et ${_num(f.max!)}$unit', 'Value expected between ${_num(f.min!)} and ${_num(f.max!)}$unit'))}" promptTitle="${_x(f.code)}" prompt="${_x('${f.label}$unit')}" sqref="$range"><formula1>${_num(f.min!)}</formula1><formula2>${_num(f.max!)}</formula2></dataValidation>');
    } else if (f.type == CrfType.date) {
      nDv++;
      dv.write('<dataValidation type="date" operator="between" allowBlank="1" showInputMessage="1" showErrorMessage="1" errorTitle="${_x(f.code)}" error="${_x(tr('Date attendue (JJ/MM/AAAA)', 'Date expected (DD/MM/YYYY)'))}" promptTitle="${_x(f.code)}" prompt="${_x(f.label)}" sqref="$range"><formula1>36526</formula1><formula2>73051</formula2></dataValidation>');
    }
  }
  final sheet1 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$ns" xmlns:r="$r">'
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
      '<cols><col min="1" max="${fields.length}" width="18" customWidth="1"/></cols>'
      '<sheetData>$data</sheetData>'
      '${nDv == 0 ? '' : '<dataValidations count="$nDv">$dv</dataValidations>'}'
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>';
  final header = ['variable', 'type', tr('libelle', 'label'), tr('unite', 'unit'), 'min', 'max', tr('modalites', 'levels')];
  final dict = StringBuffer('<row r="1">');
  for (var i = 0; i < header.length; i++) {
    dict.write(cell('${_col(i)}1', header[i], style: 1));
  }
  dict.write('</row>');
  for (var k = 0; k < fields.length; k++) {
    final f = fields[k];
    final vals = [f.code, crfTypeWord(f.type), f.label, f.unit, f.min == null ? '' : _num(f.min!), f.max == null ? '' : _num(f.max!), f.levels.join(';')];
    dict.write('<row r="${k + 2}">');
    for (var i = 0; i < vals.length; i++) {
      final ref = '${_col(i)}${k + 2}';
      if ((i == 4 || i == 5) && vals[i].isNotEmpty) {
        dict.write('<c r="$ref"><v>${vals[i]}</v></c>');
      } else if (vals[i].isNotEmpty) {
        dict.write(cell(ref, vals[i]));
      }
    }
    dict.write('</row>');
  }
  final sheet2 = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$ns" xmlns:r="$r">'
      '<cols><col min="1" max="2" width="20" customWidth="1"/><col min="3" max="3" width="45" customWidth="1"/><col min="4" max="7" width="14" customWidth="1"/></cols>'
      '<sheetData>$dict</sheetData><pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>';
  final dataName = tr('Données', 'Data'), dictName = tr('Dictionnaire', 'Dictionary');
  return {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="$ns" xmlns:r="$r"><sheets>'
        '<sheet name="${_x(dataName)}" sheetId="1" r:id="rId1"/><sheet name="${_x(dictName)}" sheetId="2" r:id="rId2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="$ns">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    'xl/worksheets/sheet1.xml': sheet1,
    'xl/worksheets/sheet2.xml': sheet2,
  };
}
