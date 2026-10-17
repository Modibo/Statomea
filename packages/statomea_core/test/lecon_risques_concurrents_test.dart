import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  for (final lang in [Lang.fr, Lang.en]) {
    test('leçon « risques concurrents et temps immortel » (${lang.name}) : exemple calculé, réponses cohérentes', () {
      withLang(lang, () {
        final l = buildLessons().firstWhere((l) => l.id == 'competing_risks');
        expect(l.exercises.length, 5);
        expect(l.example, contains(lang == Lang.fr ? 'temps immortel' : 'immortal time'));
        // Exercice 1 : 1 − KM naïf = 1 − (1 − 10/90).
        expect(l.exercises[0].answer, closeTo((1 - (1 - 10 / 90)) * 100, 0.006));
        expect(l.exercises[0].check('11,11'), isTrue);
        expect(l.exercises[1].check('10'), isTrue);
        expect(l.exercises[3].answer!, lessThan(0.25)); // greffe codée à l'inclusion (greffe + âge) : HR ≈ 0,17
        expect(methodInfo('cumulative_incidence')!.lessonId, 'competing_risks');
      });
    });
  }
}
