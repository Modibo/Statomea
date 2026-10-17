import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  for (final lang in [Lang.fr, Lang.en]) {
    test('leçon « puissance : survie, cas-témoins et GWAS » (${lang.name}) : exemple calculé, réponses cohérentes', () {
      withLang(lang, () {
        final l = buildLessons().firstWhere((l) => l.id == 'power_planning');
        expect(l.exercises.length, 5);
        expect(l.example, contains('319'));
        expect(l.exercises[0].answer, closeTo(schoenfeldEvents(0.5, 1), 1));
        expect(l.exercises[2].answer, powerCaseControl(or: 2, p0: 0.2).statistics['n_0']);
        expect(methodInfo('power_survival')!.lessonId, 'power_planning');
      });
    });
  }
}
