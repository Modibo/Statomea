import 'dart:math' as math;

import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

void main() {
  for (final lang in Lang.values) {
    test('leçon GWAS (${lang.name}) : réponses des exercices numériques cohérentes avec le moteur', () {
      withLang(lang, () {
        final l = lessonById(buildLessons(), 'gwas')!;
        final num = l.exercises.where((e) => e.isNumeric).toList();
        expect(num, hasLength(5));
        // −log10(5e-8)
        expect(num[0].check(fmtFixed(-math.log(5e-8) / math.ln10, 2)), isTrue);
        // λ = 0,682 / médiane de χ²₁ (moteur)
        expect(num[1].check(fmtFixed(0.682 / chiSquareQuantile(0.5, 1), 2)), isTrue);
        // −log10 du plus petit quantile attendu pour 1 000 tests (ppoints, moteur)
        final q = qqPoints(List.filled(1000, 0.5));
        expect(num[2].check(fmtFixed(-math.log(q.expected.first) / math.ln10, 2)), isTrue);
        // ratio LDSC = (intercept − 1)/(χ̄² − 1)
        expect(num[3].check(fmtFixed((1.10 - 1) / (1.50 - 1), 2)), isTrue);
        expect(methodInfo('ldsc')!.lessonId, 'polygenic');
        // rg = ρg/√(h²₁·h²₂)
        expect(num[4].check(fmtFixed(0.12 / math.sqrt(0.40 * 0.25), 2)), isTrue);
        expect(methodInfo('genetic_correlation')!.lessonId, 'polygenic');
        expect(l.calculatorId, 'genotype_qc');
        expect(methodInfo('genotype_pca')!.lessonId, 'gwas');
      });
    });
  }

  test('exemple calculé : λ proche de 1 si cas et témoins ont la même ascendance, gonflé sinon', () {
    final l = lessonById(buildLessons(), 'gwas')!;
    final lambdas = RegExp(r'λ = (\d+[.,]\d+)').allMatches(l.example).map((m) => double.parse(m.group(1)!.replaceAll(',', '.'))).toList();
    expect(lambdas[0], inInclusiveRange(0.8, 1.2));
    expect(lambdas[1], greaterThan(2));
  });
}
