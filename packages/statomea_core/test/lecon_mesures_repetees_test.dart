import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  for (final lang in [Lang.fr, Lang.en]) {
    test('leçon « mesures répétées » (${lang.name}) : exemple sleepstudy calculé (pente 10,47 ms/jour), ES naïf plus petit', () {
      withLang(lang, () {
        final l = buildLessons().firstWhere((l) => l.id == 'repeated_measures');
        expect(l.exercises[1].answer, closeTo(10.5, 0.06));
        expect(l.example, contains(lang == Lang.fr ? '10,47' : '10.47'));
        expect(l.example, isNot(contains('NaN')));
        expect(methodInfo('lmm_longitudinal')!.lessonId, 'repeated_measures');
      });
    });
  }
}
