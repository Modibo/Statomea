import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:statomea/services/document_text.dart';
import 'package:statomea/services/user_guide.dart';

/// Construit le guide d'utilisation avec les captures des maquettes ; GUIDE_OUT=chemin écrit le PDF (publication).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('guide d\'utilisation : douze chapitres, captures, PDF relu', () async {
    final images = <String, Uint8List>{
      for (final n in ['mobile-01-accueil.png', 'mobile-02-question.png', 'mobile-14-feuille-de-route.png', 'mobile-15-relecture.png', 'mobile-05-forest.png', 'mobile-08-lecon.png'])
        if (File('test/goldens/$n').existsSync()) n: File('test/goldens/$n').readAsBytesSync(),
    };
    final bytes = await buildUserGuidePdf(images: images);
    final text = pdfText(bytes).replaceAll(RegExp(r'\s+'), ' ');
    for (final h in ['1. Ce que fait Statoméa', '4. Le parcours en 10 étapes', '6. Relecture et corrections', '10. Pour les encadrants', '12. Limites']) {
      expect(text, contains(h));
    }
    final out = Platform.environment['GUIDE_OUT'];
    if (out != null) {
      for (final path in out.split(':')) {
        File(path).writeAsBytesSync(bytes);
      }
    }
  });
}
