import 'dart:convert';
import 'dart:io';

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Matcher _err(String code) => throwsA(isA<StatInputError>().having((e) => e.code, 'code', code));

void main() {
  final demo1 = buildDemoAghbs(File('test/reference/aghbs_simule.csv').readAsStringSync());
  final demo2 = buildDemoMeta(File('test/reference/bcg_colditz1994.csv').readAsStringSync());
  final demo3 = buildDemoPrediction(File('test/reference/cardiometabolique_simule.csv').readAsStringSync(), bootstrap: 10,
      externalCsv: File('test/reference/cardiometabolique_externe_simule.csv').readAsStringSync());

  Set<String> codes(ProjectImport i) => {for (final a in i.notes) a.code};

  test('aller-retour exact des trois démonstrations, empreinte reconnue', () {
    for (final p in [demo1, demo2, demo3]) {
      final text = p.encode();
      final imp = importProject(text);
      expect(codes(imp), isNot(contains('import_modified')));
      expect(codes(imp), isNot(contains('import_no_checksum')));
      expect(jsonEncode(imp.project.toJson()), jsonEncode(p.toJson()), reason: p.id);
      expect(imp.originalId, isNull);
    }
  });

  test('un fichier modifié après l\'export est signalé (grave)', () {
    final j = jsonDecode(demo2.encode()) as Map<String, Object?>;
    j['resultsText'] = 'Texte réécrit à la main.';
    final imp = importProject(jsonEncode(j));
    final a = imp.notes.firstWhere((a) => a.code == 'import_modified');
    expect(a.severity, Severity.serious);
    expect(imp.notes.first.code, 'import_modified'); // trié du plus grave au moins grave
  });

  test('ancien export sans empreinte : relu, avec une information', () {
    final j = jsonDecode(demo2.encode()) as Map<String, Object?>..remove('checksum');
    final imp = importProject(jsonEncode(j));
    expect(codes(imp), contains('import_no_checksum'));
    expect(imp.project.journal.length, demo2.journal.length);
  });

  test('identifiant déjà présent : copie à part, jamais d\'écrasement', () {
    final imp = importProject(demo1.encode(), existingIds: {demo1.id}, newId: () => 'p42');
    expect(imp.project.id, 'p42');
    expect(imp.originalId, demo1.id);
    expect(imp.project.title, endsWith('(import)'));
    expect(codes(imp), contains('import_id'));
    expect(imp.project.journal.length, demo1.journal.length);
  });

  test('calculs portant sur d\'autres données que le jeu enregistré : signalés', () {
    expect(codes(importProject(demo1.encode())), contains('import_other_data')); // sous-ensemble des enfants suivis
    expect(codes(importProject(demo3.encode())), contains('import_other_data')); // cohorte externe
    expect(codes(importProject(demo2.encode())), isNot(contains('import_other_data')));
  });

  test('autre version du moteur : information, résultats non recalculés', () {
    final j = jsonDecode(demo2.encode()) as Map<String, Object?>;
    j['engine'] = 'statomea_core 1.0.0';
    j['checksum'] = projectChecksum(j);
    final imp = importProject(jsonEncode(j));
    expect(codes(imp), contains('import_engine'));
    expect(codes(imp), isNot(contains('import_modified')));
  });

  test('fichiers refusés avec un message explicite', () {
    expect(() => importProject('pas du json'), _err('import_not_json'));
    expect(() => importProject('[1, 2]'), _err('import_not_project'));
    expect(() => importProject('{"format": "autre"}'), _err('import_not_project'));
    expect(() => importProject(journalJson(demo2)), _err('import_journal'));
    final future = jsonDecode(demo2.encode()) as Map<String, Object?>..['formatVersion'] = projectFormatVersion + 1;
    expect(() => importProject(jsonEncode(future)), _err('import_format_version'));
    final broken = jsonDecode(demo2.encode()) as Map<String, Object?>..remove('title');
    expect(() => importProject(jsonEncode(broken)), _err('import_invalid'));
  });

  test('messages en anglais', () {
    withLang(Lang.en, () {
      final imp = importProject(demo1.encode(), existingIds: {demo1.id}, newId: () => 'p1');
      expect(imp.project.title, endsWith('(imported)'));
      for (final a in imp.notes) {
        expect(a.message, isNot(matches(RegExp('[éèàç]| les | des '))), reason: a.message);
      }
      expect(() => importProject(journalJson(demo2)),
          throwsA(isA<StatInputError>().having((e) => e.message, 'message', contains('computation log'))));
    });
  });
}
