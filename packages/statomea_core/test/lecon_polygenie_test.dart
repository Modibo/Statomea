import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  for (final lang in Lang.values) {
    test('leçon polygénie (${lang.name}) : réponses cohérentes avec le moteur, liens du registre', () {
      withLang(lang, () {
        final l = lessonById(buildLessons(), 'polygenic')!;
        final num = l.exercises.where((e) => e.isNumeric).toList();
        expect(num, hasLength(3));
        // χ² moyen attendu = 1 + N·h²·ℓ̄/M
        expect(num[0].check(fmtFixed(1 + 20000 * 0.25 * 80 / 1000000, 2)), isTrue);
        // ratio = (intercept − 1)/(χ̄² − 1)
        expect(num[1].check(fmtFixed((1.06 - 1) / (1.30 - 1), 2)), isTrue);
        // rapport de Wald βY/βX (moteur : un seul variant → IVW = βY/βX)
        expect(num[2].check(fmtFixed(0.03 / 0.10, 2)), isTrue);
        expect(l.calculatorId, 'ldsc');
        for (final m in ['ldsc', 'genetic_correlation', 'polygenic_score']) {
          expect(methodInfo(m)!.lessonId, 'polygenic', reason: m);
        }
      });
    });
  }

  test('exemple calculé : intercept ≈ 1 sans confusion, ≈ 1,25 avec ; la pente (h²) change peu', () {
    final l = withLang(Lang.fr, () => lessonById(buildLessons(), 'polygenic')!);
    double val(String key) => double.parse(RegExp('$key (\\d+,\\d+)').allMatches(l.example).map((m) => m.group(1)!).first.replaceAll(',', '.'));
    final nums = RegExp(r'intercept (\d+,\d+)').allMatches(l.example).map((m) => double.parse(m.group(1)!.replaceAll(',', '.'))).toList();
    expect(nums[0], closeTo(1, 0.15));
    expect(nums[1], closeTo(1.25, 0.1));
    final h2 = RegExp(r'h² (\d+,\d+)').allMatches(l.example).map((m) => double.parse(m.group(1)!.replaceAll(',', '.'))).toList();
    expect((h2[0] - h2[1]).abs(), lessThan(0.1));
    expect(val('ratio'), inInclusiveRange(0.1, 0.3)); // 0,25 / (χ̄² − 1) : la confusion n'est qu'une part de l'inflation
  });
}
