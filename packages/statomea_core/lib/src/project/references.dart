/// Bibliographie du projet : import RIS (Zotero, Mendeley, EndNote), BibTeX et MEDLINE (PubMed « .nbib »), saisie
/// manuelle ; style de Vancouver ; citations « [@clé] » dans les textes du chercheur, numérotées dans l'ordre de
/// première citation (les références non citées suivent) et remplacées par « [1] », « [1,2] » ou « [1–3] ».
library;

import '../audit/audit.dart' show foldAccents;
import '../i18n.dart';
import '../meta/meta.dart' show Study, SourcedValue;
import '../model/result.dart' show StatInputError;

class Reference {
  final String key;
  final List<String> authors; // forme de Vancouver : « Nom AB »
  final String title, journal, year, volume, issue, pages, doi, pmid, url;
  const Reference({
    required this.key,
    this.authors = const [],
    this.title = '',
    this.journal = '',
    this.year = '',
    this.volume = '',
    this.issue = '',
    this.pages = '',
    this.doi = '',
    this.pmid = '',
    this.url = '',
  });

  Reference withKey(String k) =>
      Reference(key: k, authors: authors, title: title, journal: journal, year: year, volume: volume, issue: issue, pages: pages, doi: doi, pmid: pmid, url: url);

  Map<String, Object?> toJson() => {
        'key': key,
        if (authors.isNotEmpty) 'authors': authors,
        for (final e in {'title': title, 'journal': journal, 'year': year, 'volume': volume, 'issue': issue, 'pages': pages, 'doi': doi, 'pmid': pmid, 'url': url}.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  factory Reference.fromJson(Map<String, Object?> j) => Reference(
        key: j['key'] as String,
        authors: [for (final a in (j['authors'] as List? ?? const [])) a as String],
        title: (j['title'] as String?) ?? '',
        journal: (j['journal'] as String?) ?? '',
        year: (j['year'] as String?) ?? '',
        volume: (j['volume'] as String?) ?? '',
        issue: (j['issue'] as String?) ?? '',
        pages: (j['pages'] as String?) ?? '',
        doi: (j['doi'] as String?) ?? '',
        pmid: (j['pmid'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
      );
}

/// « Smith, John Andrew » ou « John Andrew Smith » → « Smith JA » ; « Smith J » est gardé tel quel.
String vancouverName(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[{}]'), '');
  if (s.isEmpty) return s;
  String initials(String given) => [for (final part in given.split(RegExp(r'[\s.]+'))) if (part.isNotEmpty) for (final p2 in part.split('-')) if (p2.isNotEmpty) p2[0].toUpperCase()].join();
  if (s.contains(',')) {
    final i = s.indexOf(',');
    final last = s.substring(0, i).trim(), given = s.substring(i + 1).trim();
    return given.isEmpty ? last : '$last ${initials(given)}';
  }
  final parts = s.split(' ');
  if (parts.length >= 2 && RegExp(r'^[A-Z]{1,3}$').hasMatch(parts.last)) return s; // déjà « Smith JA »
  if (parts.length == 1) return s;
  // « John Andrew Smith » ; particules (« van », « de ») rattachées au nom.
  var k = parts.length - 1;
  while (k > 0 && RegExp(r'^(van|von|de|der|du|da|di|le|la|el|al|ben|ibn)$', caseSensitive: false).hasMatch(parts[k - 1])) {
    k--;
  }
  return '${parts.sublist(k).join(' ')} ${initials(parts.sublist(0, k).join(' '))}';
}

String _cleanTitle(String t) => t.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[{}]'), '');

String _keyFor(Reference r, Set<String> used) {
  final first = r.authors.isEmpty ? (r.title.isEmpty ? 'ref' : r.title.split(' ').first) : r.authors.first.split(' ').first;
  final base = '${foldAccents(first.toLowerCase()).replaceAll(RegExp(r'[^a-z0-9]'), '')}${r.year.isEmpty ? '' : r.year}';
  var k = base.isEmpty ? 'ref' : base;
  var n = 0;
  while (used.contains(k)) {
    k = '$base${String.fromCharCode(97 + n++)}';
  }
  used.add(k);
  return k;
}

/// RIS (lignes « TY  - JOUR » … « ER  - »).
List<Reference> parseRis(String text) {
  final out = <Reference>[];
  Map<String, List<String>> cur = {};
  void flush() {
    if (cur.isEmpty) return;
    String f(List<String> tags) {
      for (final t in tags) {
        final v = cur[t];
        if (v != null && v.isNotEmpty) return v.first.trim();
      }
      return '';
    }

    final sp = f(['SP']), ep = f(['EP']);
    final year = RegExp(r'(\d{4})').firstMatch(f(['PY', 'Y1', 'DA']))?.group(1) ?? '';
    out.add(Reference(
      key: '',
      authors: [for (final t in ['AU', 'A1']) ...?cur[t]?.map(vancouverName)],
      title: _cleanTitle(f(['TI', 'T1'])),
      journal: f(['JO', 'JA', 'J2', 'JF', 'T2']),
      year: year,
      volume: f(['VL']),
      issue: f(['IS']),
      pages: sp.isEmpty ? '' : (ep.isEmpty || ep == sp ? sp : '$sp-$ep'),
      doi: f(['DO']).replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), ''),
      pmid: RegExp(r'\d{6,9}').firstMatch(f(['AN', 'C1']).isEmpty ? '' : f(['AN', 'C1']))?.group(0) ?? '',
      url: f(['UR']),
    ));
    cur = {};
  }

  for (final line in text.replaceAll('\r', '').split('\n')) {
    final m = RegExp(r'^([A-Z][A-Z0-9])  - ?(.*)$').firstMatch(line);
    if (m == null) continue;
    final tag = m.group(1)!, val = m.group(2)!;
    if (tag == 'ER') {
      flush();
    } else {
      (cur[tag] ??= []).add(val);
    }
  }
  flush();
  return out;
}

/// MEDLINE de PubMed (« PMID- », « TI  - » avec lignes de continuation).
List<Reference> parseMedline(String text) {
  final out = <Reference>[];
  final records = text.replaceAll('\r', '').split(RegExp(r'\n\s*\n(?=PMID-)'));
  for (final rec in records) {
    final fields = <String, List<String>>{};
    String? last;
    for (final line in rec.split('\n')) {
      final m = RegExp(r'^([A-Z]{2,4})\s*- (.*)$').firstMatch(line);
      if (m != null) {
        last = m.group(1)!;
        (fields[last] ??= []).add(m.group(2)!.trim());
      } else if (last != null && line.startsWith('      ')) {
        final l = fields[last]!;
        l[l.length - 1] = '${l.last} ${line.trim()}';
      }
    }
    if (!fields.containsKey('PMID') && !fields.containsKey('TI')) continue;
    String f(String t) => fields[t]?.first ?? '';
    final doi = [...?fields['LID'], ...?fields['AID']].firstWhere((x) => x.endsWith('[doi]'), orElse: () => '').replaceFirst(' [doi]', '');
    out.add(Reference(
      key: '',
      authors: [...?fields['AU']],
      title: _cleanTitle(f('TI')),
      journal: f('TA').isNotEmpty ? f('TA') : f('JT'),
      year: RegExp(r'\d{4}').firstMatch(f('DP'))?.group(0) ?? '',
      volume: f('VI'),
      issue: f('IP'),
      pages: f('PG'),
      doi: doi,
      pmid: f('PMID'),
    ));
  }
  return out;
}

/// BibTeX (« @article{clé, author = {…}, … } »).
List<Reference> parseBibtex(String text) {
  final out = <Reference>[];
  var i = 0;
  while (true) {
    final at = text.indexOf('@', i);
    if (at < 0) break;
    final open = text.indexOf('{', at);
    if (open < 0) break;
    final type = text.substring(at + 1, open).trim().toLowerCase();
    // Fin de l'entrée : accolade fermante correspondante.
    var depth = 0, end = open;
    for (; end < text.length; end++) {
      if (text[end] == '{') depth++;
      if (text[end] == '}' && --depth == 0) break;
    }
    final body = text.substring(open + 1, end.clamp(open + 1, text.length));
    i = end + 1;
    if (type == 'comment' || type == 'string' || type == 'preamble') continue;
    final comma = body.indexOf(',');
    final key = comma < 0 ? '' : body.substring(0, comma).trim();
    final fields = <String, String>{};
    var k = comma + 1;
    while (k < body.length) {
      final m = RegExp(r'\s*([A-Za-z_\-]+)\s*=\s*').matchAsPrefix(body, k);
      if (m == null) break;
      k = m.end;
      String value;
      if (k < body.length && body[k] == '{') {
        var d = 0, e = k;
        for (; e < body.length; e++) {
          if (body[e] == '{') d++;
          if (body[e] == '}' && --d == 0) break;
        }
        value = body.substring(k + 1, e);
        k = e + 1;
      } else if (k < body.length && body[k] == '"') {
        final e = body.indexOf('"', k + 1);
        value = body.substring(k + 1, e < 0 ? body.length : e);
        k = (e < 0 ? body.length : e) + 1;
      } else {
        final e = body.indexOf(',', k);
        value = body.substring(k, e < 0 ? body.length : e).trim();
        k = e < 0 ? body.length : e;
      }
      fields[m.group(1)!.toLowerCase()] = value.trim();
      final c = body.indexOf(',', k);
      if (c < 0) break;
      k = c + 1;
    }
    out.add(Reference(
      key: key,
      authors: [for (final a in (fields['author'] ?? '').split(RegExp(r'\s+and\s+'))) if (a.trim().isNotEmpty) vancouverName(a)],
      title: _cleanTitle(fields['title'] ?? ''),
      journal: _cleanTitle(fields['journal'] ?? fields['booktitle'] ?? ''),
      year: fields['year'] ?? '',
      volume: fields['volume'] ?? '',
      issue: fields['number'] ?? '',
      pages: (fields['pages'] ?? '').replaceAll('--', '-'),
      doi: fields['doi'] ?? '',
      pmid: fields['pmid'] ?? '',
      url: fields['url'] ?? '',
    ));
  }
  return out;
}

/// Détecte le format et lit les références ; les clés manquantes ou en double sont (re)générées (« smith2020 »).
List<Reference> parseReferences(String text, {Iterable<String> existingKeys = const []}) {
  final t = text.trimLeft();
  final List<Reference> refs;
  if (t.startsWith('@') || RegExp(r'^\s*@\w+\s*\{', multiLine: true).hasMatch(text)) {
    refs = parseBibtex(text);
  } else if (RegExp(r'^PMID-', multiLine: true).hasMatch(text)) {
    refs = parseMedline(text);
  } else if (RegExp(r'^TY  - ', multiLine: true).hasMatch(text)) {
    refs = parseRis(text);
  } else {
    throw StatInputError('refs_format', tr('Format non reconnu : exporter les références en RIS, BibTeX ou MEDLINE (PubMed).', 'Unrecognised format: export the references as RIS, BibTeX or MEDLINE (PubMed).'));
  }
  final used = {...existingKeys};
  return [
    for (final r in refs)
      if (r.title.isNotEmpty || r.authors.isNotEmpty) r.key.isNotEmpty && !used.contains(r.key) && used.add(r.key) ? r : r.withKey(_keyFor(r, used)),
  ];
}

/// Référence au style de Vancouver (six auteurs au plus, puis « et al. »).
String vancouver(Reference r) {
  final authors = r.authors.isEmpty ? '' : '${r.authors.take(6).join(', ')}${r.authors.length > 6 ? ', et al' : ''}. ';
  final title = r.title.isEmpty ? '' : (RegExp(r'[.?!]$').hasMatch(r.title) ? '${r.title} ' : '${r.title}. ');
  final journal = r.journal.isEmpty ? '' : '${r.journal}. ';
  final vol = r.volume.isEmpty ? '' : r.volume;
  final iss = r.issue.isEmpty ? '' : '(${r.issue})';
  final pages = r.pages.isEmpty ? '' : ':${r.pages}';
  final source = r.year.isEmpty && vol.isEmpty ? '' : '${r.year}${vol.isEmpty && iss.isEmpty ? '' : ';$vol$iss'}$pages.';
  final ids = [if (r.doi.isNotEmpty) 'doi:${r.doi}', if (r.pmid.isNotEmpty) 'PMID: ${r.pmid}'].join('. ');
  return '$authors$title$journal$source${ids.isEmpty ? '' : ' $ids.'}'.trim();
}

final _cite = RegExp(r'\[(@[\w:\-]+(?:\s*[;,]\s*@[\w:\-]+)*)\]');

/// Numérotation des références : ordre de première citation dans [texts], puis références non citées.
Map<String, int> referenceNumbers(List<Reference> refs, Iterable<String> texts) {
  final known = {for (final r in refs) r.key};
  final order = <String>[];
  for (final t in texts) {
    for (final m in _cite.allMatches(t)) {
      for (final k in m.group(1)!.split(RegExp(r'\s*[;,]\s*'))) {
        final key = k.substring(1);
        if (known.contains(key) && !order.contains(key)) order.add(key);
      }
    }
  }
  for (final r in refs) {
    if (!order.contains(r.key)) order.add(r.key);
  }
  return {for (var i = 0; i < order.length; i++) order[i]: i + 1};
}

/// Remplace « [@a; @b] » par « [1,2] » (« [1–3] » pour une suite) ; une clé inconnue est laissée telle quelle.
String formatCitations(String text, Map<String, int> numbers) => text.replaceAllMapped(_cite, (m) {
      final keys = [for (final k in m.group(1)!.split(RegExp(r'\s*[;,]\s*'))) k.substring(1)];
      if (keys.any((k) => !numbers.containsKey(k))) return m.group(0)!;
      final ns = ({for (final k in keys) numbers[k]!}.toList())..sort();
      final parts = <String>[];
      var a = 0;
      while (a < ns.length) {
        var b = a;
        while (b + 1 < ns.length && ns[b + 1] == ns[b] + 1) {
          b++;
        }
        parts.add(b - a >= 2 ? '${ns[a]}–${ns[b]}' : [for (var k = a; k <= b; k++) '${ns[k]}'].join(','));
        a = b + 1;
      }
      return '[${parts.join(',')}]';
    });

/// Liste numérotée (« 1. Smith J, … »), dans l'ordre de [numbers].
List<String> referenceList(List<Reference> refs, Map<String, int> numbers) {
  final sorted = [...refs]..sort((a, b) => (numbers[a.key] ?? 1 << 30).compareTo(numbers[b.key] ?? 1 << 30));
  return [for (final r in sorted) '${numbers[r.key]}. ${vancouver(r)}'];
}

/// Libellé d'étude « Auteur année » (« Smith 2020 », « Smith 2020b » en cas de doublon).
List<String> studyLabels(List<Reference> refs) {
  final used = <String, int>{};
  return [
    for (final r in refs)
      () {
        final base = '${r.authors.isEmpty ? (r.title.split(' ').take(3).join(' ')) : r.authors.first.split(' ').first}${r.year.isEmpty ? '' : ' ${r.year}'}';
        final k = used[base] = (used[base] ?? 0) + 1;
        return k == 1 ? base : '$base${String.fromCharCode(96 + k)}';
      }(),
  ];
}

const _binKeys = ['e1', 'n1', 'e2', 'n2'], _contKeys = ['m1', 'sd1', 'n1', 'm2', 'sd2', 'n2'];

/// Études de méta-analyse préparées à partir des références : libellé « Auteur année », valeurs à extraire (vides,
/// source = clé de la référence), année gardée comme modérateur potentiel (méta-régression).
List<Study> metaStudiesFromReferences(List<Reference> refs, {bool continuous = false}) {
  final labels = studyLabels(refs);
  final keys = continuous ? _contKeys : _binKeys;
  return [
    for (var i = 0; i < refs.length; i++)
      Study(refs[i].key, labels[i], {
        for (final k in keys) k: SourcedValue(null, source: '[@${refs[i].key}]'),
        if (int.tryParse(refs[i].year) != null) 'annee': SourcedValue(double.parse(refs[i].year), source: '[@${refs[i].key}]'),
      }),
  ];
}

/// Grille d'extraction (CSV « ; ») : une ligne par référence ; colonnes lues par l'atelier de méta-analyse
/// (étude, e1, n1, e2, n2 — ou m1, sd1, n1, m2, sd2, n2 — et sous_groupe), plus l'année, la clé et le DOI pour
/// retrouver l'article.
String extractionGridCsv(List<Reference> refs, {bool continuous = false}) {
  final labels = studyLabels(refs);
  final keys = continuous ? _contKeys : _binKeys;
  String cell(String c) => c.contains(';') || c.contains('"') ? '"${c.replaceAll('"', '""')}"' : c;
  final rows = [
    ['etude', ...keys, 'sous_groupe', tr('annee', 'year'), tr('cle', 'key'), 'doi'],
    for (var i = 0; i < refs.length; i++) [labels[i], for (final _ in keys) '', '', refs[i].year, refs[i].key, refs[i].doi],
  ];
  return '${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
}
