import 'package:statomea_core/statomea_core.dart';
import 'package:test/test.dart';

Matcher errCode(String code) => throwsA(isA<StatInputError>().having((e) => e.code, 'code', code));

void main() {
  group('Jeux de données inadaptés : erreurs explicites attendues', () {
    final ds = Dataset.fromColumns({
      'y3': ['a', 'b', 'c', 'a', 'b', 'c', 'a', 'b'],
      'x': [1, 2, 3, 4, 5, 6, 7, 8],
      'x2': [2, 4, 6, 8, 10, 12, 14, 16],
      'neg': [-1, 2, 3, 4, 5, 6, 7, 8],
      'yb': [0, 1, 0, 1, 0, 1, 0, 1],
      'yc': [1.2, 2.3, 2.9, 4.1, 5.2, 5.8, 7.1, 8.3],
    });
    test('issue à 3 modalités en logistique', () {
      expect(() => buildDesign(ds, const ModelFormula('y3', [TermSpec('x')]), binaryOutcome: true), errCode('outcome_not_binary'));
    });
    test('colonnes parfaitement colinéaires', () {
      final d = buildDesign(ds, const ModelFormula('yc', [TermSpec('x'), TermSpec('x2')]));
      expect(() => linearRegression(d), errCode('aliased'));
    });
    test('logarithme de valeurs ≤ 0', () {
      expect(() => buildDesign(ds, const ModelFormula('yc', [TermSpec('neg', transform: TermTransform.log)])), errCode('log_nonpositive'));
    });
    test('plus de paramètres que d\'observations', () {
      final small = Dataset.fromColumns({'y': [1.0, 2.0], 'a': [1, 2], 'b': [3, 1]});
      expect(() => buildDesign(small, const ModelFormula('y', [TermSpec('a'), TermSpec('b')])), errCode('too_few_rows'));
    });
    test('modèle de prédiction séparé : aucune performance rapportée', () {
      final sep = Dataset.fromColumns({
        'y': [for (var i = 0; i < 40; i++) i < 20 ? 0 : 1],
        'x': [for (var i = 0; i < 40; i++) i.toDouble()],
      });
      const spec = PredictionSpec(targetPopulation: 'p', outcome: 'y', eventLevel: '1', horizon: '1 an', intendedUse: 'u', predictors: [TermSpec('x')]);
      expect(() => developPredictionModel(sep, spec, bootstrap: 10), errCode('prediction_unstable'));
    });
    test('séries appariées de longueurs différentes ; McNemar sans paire discordante', () {
      expect(() => pairedTTest([1, 2, 3], [1, 2]), errCode('unpaired_lengths'));
      expect(() => mcNemar(10, 0, 0, 12), errCode('no_discordant'));
    });
    test('non-convergence ou séparation en logistique : résultat marqué non fiable, pas d\'exception', () {
      final d = buildDesign(
          Dataset.fromColumns({'y': [0, 0, 0, 0, 1, 1, 1, 1], 'x': [1, 2, 3, 4, 5, 6, 7, 8]}), const ModelFormula('y', [TermSpec('x')], eventLevel: '1'),
          binaryOutcome: true);
      final r = logisticRegression(d);
      expect(r.reliable, isFalse);
      expect(r.checks.firstWhere((c) => c.id == 'separation').status, CheckStatus.violated);
      final f = firthRegression(d);
      expect(f.estimates.single.value.isFinite, isTrue);
    });
    test('2 × 2 sans aucun événement ; proportion avec x > n', () {
      expect(() => twoByTwo(0, 10, 0, 12), errCode('empty_column'));
      expect(() => proportionCi(5, 3), errCode('events_out_of_range'));
    });
  });
}
