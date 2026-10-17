/// Formation intégrée : leçons courtes associées aux méthodes. Les exemples
/// chiffrés et les corrigés d'exercices sont CALCULÉS par le moteur au moment
/// de la construction de la leçon, pour garantir leur cohérence avec les
/// calculateurs.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../genetics/genotype_ldsc.dart';
import '../genetics/examples.dart';
import '../genetics/mendelian.dart';
import '../inference/compare.dart';
import '../inference/power.dart';
import '../inference/competing_risks.dart';
import '../inference/survival.dart';
import '../inference/diagnostic.dart';
import '../inference/proportion.dart';
import '../inference/sample_size.dart';
import '../inference/two_by_two.dart';
import '../meta/meta.dart';
import '../model/design.dart';
import '../model/result.dart';
import '../data/dataset.dart';
import '../genetics/association.dart';
import '../genetics/qpcr.dart';
import '../math/random.dart';
import '../regression/cox.dart';
import '../regression/design_matrix.dart';

enum Level { beginner, intermediate, advanced }

String levelLabel(Level l) => switch (l) {
      Level.beginner => tr('débutant', 'beginner'),
      Level.intermediate => tr('intermédiaire', 'intermediate'),
      Level.advanced => tr('avancé', 'advanced'),
    };

class Exercise {
  final String prompt;
  final List<String> choices; // vide = réponse numérique
  final int correctChoice;
  final double? answer;
  final double tolerance; // absolue
  final String correction;
  const Exercise.choice(this.prompt, this.choices, this.correctChoice, this.correction)
      : answer = null,
        tolerance = 0;
  const Exercise.numeric(this.prompt, this.answer, this.tolerance, this.correction)
      : choices = const [],
        correctChoice = -1;

  bool get isNumeric => choices.isEmpty;

  /// Vérifie une réponse (texte saisi, virgule décimale acceptée, « % » ignoré).
  bool check(String input) {
    if (!isNumeric) return int.tryParse(input) == correctChoice;
    final v = double.tryParse(input.replaceAll(',', '.').replaceAll('%', '').trim());
    return v != null && (v - answer!).abs() <= tolerance;
  }
}

class Lesson {
  final String id;
  final String title;
  final Level level;
  final List<String> body;
  final String exampleTitle;
  final String example;
  final List<Exercise> exercises;
  final List<String> commonErrors;
  final String calculatorId;
  const Lesson(
      {required this.id,
      required this.title,
      required this.level,
      required this.body,
      required this.exampleTitle,
      required this.example,
      required this.exercises,
      required this.commonErrors,
      required this.calculatorId});
}

String _p1(double v) => fmtFixed(v * 100, 1);


/// Exemple de la leçon GWAS, calculé par le moteur : 300 variants simulés dans deux populations aux fréquences
/// alléliques différentes ; λ du test de tendance d'Armitage quand cas et témoins ont le même mélange d'ascendances,
/// puis quand les cas viennent surtout de la population 2.
({double balanced, double confounded}) _gwasLambdaExample() {
  final r = SeededRandom(20261030);
  double lambda(double casesPop2, double controlsPop2) {
    final rr = SeededRandom(7 + (casesPop2 * 100).round());
    final chi = <double>[];
    for (var j = 0; j < 300; j++) {
      final p1 = 0.1 + 0.8 * r.nextDouble(), p2 = (p1 + (r.nextDouble() - 0.5) * 0.3).clamp(0.02, 0.98);
      List<int> draw(int n, double fracPop2) {
        final c = [0, 0, 0];
        for (var i = 0; i < n; i++) {
          final p = rr.nextDouble() < fracPop2 ? p2 : p1;
          c[(rr.nextDouble() < p ? 1 : 0) + (rr.nextDouble() < p ? 1 : 0)]++;
        }
        return c;
      }
      chi.add(geneticAssociation(draw(200, casesPop2), draw(200, controlsPop2)).statistics['trend_chi2']!);
    }
    chi.sort();
    return (chi[149] + chi[150]) / 2 / 0.45493642311957283;
  }
  return (balanced: lambda(0.5, 0.5), confounded: lambda(0.7, 0.3));
}

/// Exemple de la leçon « polygénie » : statistiques simulées pour 20 000 variants (N = 20 000, h² = 0,3), sans confusion
/// puis avec une confusion qui ajoute N·a = 0,25 à tous les χ² attendus ; régression LD score par le moteur.
({LdscFit clean, LdscFit confounded}) _polygenicExample() {
  final r = SeededRandom(20261105);
  const n = 20000, m = 20000, h2 = 0.3;
  final ell = [for (var j = 0; j < m; j++) 1 + 7 * r.nextDouble()];
  final gauss = [
    for (var j = 0; j < m; j++)
      () {
        final u1 = 1 - r.nextDouble(), u2 = r.nextDouble();
        return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
      }()
  ];
  List<double?> chi2(double na) => [for (var j = 0; j < m; j++) (1 + na + n * h2 * ell[j] / m) * gauss[j] * gauss[j]];
  return (clean: ldscRegression(chi2(0), ell, n: n, m: m), confounded: ldscRegression(chi2(0.25), ell, n: n, m: m));
}

/// Exemple de la leçon « risques concurrents et temps immortel » : (1) 20 patients fictifs, rechute ou décès sans
/// rechute ; (2) greffe cardiaque de Stanford, greffe codée à l'inclusion (biais du temps immortel) puis en covariable
/// dépendant du temps.
({double cif, double naive, double hrNaive, double hrTd, double pTd}) _competingExample() {
  const times = <double>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 24];
  const codes = [1, 2, 1, 2, 1, 0, 2, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 0, 0, 0];
  final cif = cumulativeIncidence(times, codes, 1).steps.last.cif;
  final km = kaplanMeier(times, [for (final c in codes) c == 1 ? 1.0 : 0.0]);
  final naive = 1 - km.steps.where((s) => s.events > 0).last.surv;
  final h = stanfordHeartExample;
  final yes = tr('oui', 'yes'), no = tr('non', 'no');
  final ds = Dataset.fromColumns({
    'jours': h.days,
    'deces': [for (final d in h.died) d == 1 ? yes : no],
    'attente': h.wait,
    'greffe': [for (final w in h.wait) w == null ? no : yes],
    'age': h.age,
  });
  final terms = [TermSpec('greffe', categorical: true, reference: no), TermSpec('age')];
  final naiveCox = coxRegression(buildSurvivalDesign(ds, 'jours', 'deces', yes, terms));
  final long = splitAtSwitch(ds, time: 'jours', status: 'deces', eventLevel: yes, switchTime: 'attente', covariate: 'greffe', yes: yes, no: no);
  final td = coxRegression(buildCountingDesign(long, 'debut', 'fin', 'deces', yes, terms));
  return (cif: cif, naive: naive, hrNaive: naiveCox.estimates.first.value, hrTd: td.estimates.first.value, pTd: td.estimates.first.pValue!);
}

/// Exemple de la leçon « causalité » : données publiées LDL / HDL → maladie coronarienne (estimations ponctuelles ; les
/// ES bootstrap ne sont pas affichées, d'où peu d'itérations).
({MrFit ldl, MrFit hdl, MvMrFit mv}) _mrExample() {
  final d = mrLipidExample;
  return (
    ldl: mendelianRandomization(d.bldl, d.sldl, d.bchd, d.schd, iterations: 100),
    hdl: mendelianRandomization(d.bhdl, d.shdl, d.bchd, d.schd, iterations: 100),
    mv: multivariableMendelianRandomization([d.bldl, d.bhdl, d.btg], [d.sldl, d.shdl, d.stg], d.bchd, d.schd, exposures: const ['LDL', 'HDL', 'TG']),
  );
}

List<Lesson> buildLessons() {
  // --- Exemples calculés par le moteur
  final prev = proportionCi(12, 400, label: tr("Prévalence de l'AgHBs", 'HBsAg prevalence'));
  final w = prev.estimates.first;
  final prev0 = proportionCi(0, 150);
  final t2 = twoByTwo(120, 380, 80, 420, design: StudyDesign.cohort);
  final rr = t2.estimate(tr('Risque relatif', 'Risk ratio'))!, or = t2.estimate('Odds ratio (Woolf)')!;
  final diag = diagnosticAccuracy(90, 30, 10, 870, targetPrevalence: 0.01);
  final ppv1 = diag.statistics['ppv_target']!;
  final tt = tTestIndependent([5.1, 5.8, 6.2, 4.9, 5.5, 6.0, 5.3, 5.7], [5.9, 6.4, 6.8, 6.1, 7.0, 6.3, 6.6, 5.8]);
  final dm = tt.estimates.first;
  final ssm = sampleSizeTwoMeans(delta: 5, sd: 12, power: 0.8);
  final ssp = sampleSizeProportion(expected: 0.08, precision: 0.02);
  // Paradoxe de Simpson (calculs rénaux, Charig et al. 1986) : succès par traitement A/B selon la taille.
  final crude = twoByTwo(273, 77, 289, 61, design: StudyDesign.cohort);
  final small = twoByTwo(81, 6, 234, 36, design: StudyDesign.cohort);
  final large = twoByTwo(192, 71, 55, 25, design: StudyDesign.cohort);
  final meta = metaAnalysis([
    Study.binary(tr('Essai A', 'Trial A'), 12, 100, 20, 100),
    Study.binary(tr('Essai B', 'Trial B'), 30, 250, 32, 248),
    Study.binary(tr('Essai C', 'Trial C'), 5, 60, 15, 62),
    Study.binary(tr('Essai D', 'Trial D'), 40, 300, 41, 295),
  ], const MetaOptions(measure: EffectMeasure.rr, method: TauMethod.reml));
  final mp = meta.estimates.first;
  // Survie : 24 patients fictifs, deux traitements, censure administrative à 36 mois.
  final months = tr('mois', 'months'), death = tr('deces', 'death'), arm = tr('bras', 'arm'), yes = tr('oui', 'yes'), no = tr('non', 'no');
  const died = [1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0];
  final surv = Dataset.fromColumns({
    months: [3, 5, 6, 8, 9, 12, 14, 15, 20, 24, 36, 36, 4, 7, 10, 13, 18, 22, 26, 30, 36, 36, 36, 36],
    death: [for (final d in died) d == 1 ? yes : no],
    arm: [for (var i = 0; i < 24; i++) i < 12 ? 'A' : 'B'],
  });
  final cox = coxRegression(buildSurvivalDesign(surv, months, death, yes, [TermSpec(arm, categorical: true, reference: 'A')]));
  final hr = cox.estimates.first;
  // Génétique : variant fictif, 300 cas et 300 témoins (effectifs AA, AB, BB).
  final gen = geneticAssociation(const [96, 144, 60], const [135, 132, 33], major: 'C', minor: 'T', variant: 'rs0001');
  final orAllelic = gen.estimates.first;
  final hweBad = hardyWeinberg(159, 119, 72, major: 'C', minor: 'T');
  final gw = _gwasLambdaExample();
  final pg = _polygenicExample();
  final mx = _mrExample();
  final cr = _competingExample();
  // Puissance : survie (Freedman), cas-témoins 1:1 et 1:4, GWAS.
  final pwSurv = powerSurvival(hr: 0.7, pC: 0.45);
  final pwCc1 = powerCaseControl(or: 2, p0: 0.2), pwCc4 = powerCaseControl(or: 2, p0: 0.2, ratio: 4);
  final pwGw = powerGwas(maf: 0.25, or: 1.15);
  final pwPilot = powerMeans(delta: 5, sd: 10, n: 20);
  final ddct = qpcrRelativeQuantification(const [24.9, 25.3, 25.1], const [18.0, 18.2, 17.9], const [22.8, 23.1, 22.7], const [18.1, 17.9, 17.8]);

  if (currentLang == Lang.en) {
    return [
      Lesson(
        id: 'ic',
        title: 'Confidence interval of a proportion',
        level: Level.beginner,
        body: [
          'A proportion observed in a sample (p̂ = x/n) estimates an unknown proportion in the population. The 95% confidence interval (CI) gathers the population values compatible with the data, under the assumptions of the calculation.',
          '"95%" describes the method: repeated over many samples, it would produce intervals containing the true value 95% of the time. For ONE given interval, we do not say it has a 95% chance of containing the true value.',
          "The Wald CI (p̂ ± 1.96√(p̂(1−p̂)/n)) performs poorly when p̂ is close to 0 or 1 or when n is small. Prefer the Wilson CI or the exact Clopper-Pearson CI.",
          'With zero events, the true proportion is not zero: the "rule of three" gives a one-sided 95% upper bound ≈ 3/n.',
        ],
        exampleTitle: 'HBsAg prevalence in 400 pregnant women (fictitious data)',
        example: '12 carriers out of 400: prevalence ${_p1(w.value)}%, Wilson CI ${_p1(w.lower!)}% to ${_p1(w.upper!)}%. '
            'With 0 cases out of 150, the exact upper bound is ${_p1(prev0.estimates[1].upper!)}% and the rule of three gives ${_p1(3 / 150)}%.',
        exercises: [
          Exercise.numeric('In a sample of 400 donors, 12 carry HBsAg. What is the UPPER bound of the 95% Wilson CI, in % (one decimal)?', w.upper! * 100, 0.06,
              'Wilson: ${_p1(w.lower!)}% to ${_p1(w.upper!)}%. The Wald CI would give a lower bound that is too low.'),
          const Exercise.choice('No infection among 150 newborns. Which statement is correct?', [
            'The risk of infection is zero.',
            'The risk is compatible with values up to about 2%.',
            'The 95% CI is 0% to 0%.',
          ], 1, 'Zero observed is not zero true: 3/150 = 2% (rule of three).'),
        ],
        commonErrors: [
          'Reporting "0%" without an upper bound when no case is observed.',
          'Using the Wald CI for a rare proportion.',
          'Generalizing a prevalence from a convenience sample (volunteer donors) to the general population.',
        ],
        calculatorId: 'proportion_ci',
      ),
      Lesson(
        id: 'p_value',
        title: 'p-value: absence of evidence is not evidence of absence',
        level: Level.beginner,
        body: [
          'The p-value measures the compatibility of the data with the null hypothesis AND all model assumptions: it is the probability of observing data at least as extreme if these assumptions were true.',
          'It is not the probability that the null hypothesis is true, nor the probability that the result is "due to chance", nor a measure of clinical importance.',
          'p > 0.05 does not prove the absence of an effect: look at the CI. If the CI contains both 0 and clinically important effects, the study simply did not reach a conclusion.',
          'Concluding that there is no relevant difference requires a margin set a priori and a CI lying entirely within that margin (equivalence logic).',
        ],
        exampleTitle: 'Blood glucose in two groups of 8 patients (fictitious data)',
        example: 'Difference in means = ${fmt(dm.value)} mmol/L, CI ${fmt(dm.lower)} to ${fmt(dm.upper)}, ${fmtP(dm.pValue)}. '
            'The CI shows the plausible size of the difference, which the p-value alone does not.',
        exercises: [
          const Exercise.choice('A trial finds p = 0.30 and an RR CI from 0.6 to 1.9. What is the conclusion?', [
            'The treatment has no effect.',
            'The data do not allow a conclusion: both a beneficial and a harmful effect remain compatible.',
            'There is a 30% chance that the treatment is ineffective.',
          ], 1, 'Wide CI including important effects in both directions: absence of evidence.'),
          const Exercise.choice('p = 0.03 means that…', [
            'the probability that H0 is true is 3%.',
            'if H0 and the model were true, data at least as extreme would be observed 3% of the time.',
            'there is a 97% chance that the effect is real.',
          ], 1, 'Frequentist definition; the other two answers are classic errors.'),
        ],
        commonErrors: [
          'Writing "no difference (p = 0.12)".',
          '"Trend towards significance" for p = 0.07.',
          'Comparing two subgroups by noting that one is significant and the other is not (test the interaction).',
        ],
        calculatorId: 't_test_welch',
      ),
      Lesson(
        id: 'or_rr',
        title: 'Odds ratio and risk ratio',
        level: Level.beginner,
        body: [
          'The risk ratio (RR) compares two risks: a/(a+b) divided by c/(c+d). It requires the group proportions to estimate risks: cohort, trial, or cross-sectional study (prevalence ratio).',
          'The odds ratio (OR) compares two odds (odds = p/(1−p)). It is the only measure estimable in a case-control study and the natural measure of logistic regression.',
          'When the outcome is rare (< 10%), OR ≈ RR. When it is common, the OR is further from 1 than the RR: writing it as "risk multiplied by" exaggerates the effect.',
          'For an adjusted RR of a common outcome, Poisson regression with robust variance is an option; in a case-control study, only logistic regression (OR) is appropriate.',
        ],
        exampleTitle: 'Hypertension in exposed (120/500) and unexposed (80/500) subjects, fictitious cohort',
        example: 'RR = ${fmt(rr.value)} (CI ${fmt(rr.lower)} to ${fmt(rr.upper)}) but OR = ${fmt(or.value)} (CI ${fmt(or.lower)} to ${fmt(or.upper)}): '
            'the outcome affects 20% of subjects, so the OR overstates the relative size.',
        exercises: [
          Exercise.numeric('Cohort: 120 hypertension cases among 500 exposed, 80 among 500 unexposed. Compute the RR (two decimals).', rr.value, 0.006,
              'RR = (120/500)/(80/500) = ${fmt(rr.value)}. The OR is ${fmt(or.value)}.'),
          const Exercise.choice('In a case-control study, which measure is estimable?', ['The RR', 'The risk difference', 'The OR'], 2,
              'Cases and controls are sampled on the outcome: risks are not estimable.'),
        ],
        commonErrors: [
          '"Exposed subjects have 1.7 times the risk" from an OR with a common outcome.',
          'Computing the prevalence of the disease in a case-control sample.',
          'Forgetting the absolute measure (risk difference), needed to judge impact.',
        ],
        calculatorId: 'two_by_two',
      ),
      Lesson(
        id: 'diagnostic',
        title: 'Sensitivity, specificity and predictive values',
        level: Level.beginner,
        body: [
          'Se = proportion of positive tests among the diseased; Sp = proportion of negative tests among the non-diseased. They describe the test (in a given patient spectrum).',
          'PPV and NPV depend on prevalence: the same test has a low PPV when the disease is rare.',
          'Likelihood ratios (LR+ = Se/(1−Sp), LR− = (1−Se)/Sp) convert a pre-test probability into a post-test probability.',
          'Case-control recruitment (severe patients versus healthy volunteers) overestimates Se and Sp (spectrum bias) and makes PPV/NPV non-transferable.',
          'To combine several studies, the bivariate model analyses Se and Sp together: they are correlated across studies (different thresholds, threshold effect). The SROC curve and the prediction region show the variability expected from one setting to another.',
        ],
        exampleTitle: 'Rapid test against the reference (fictitious data)',
        example: 'Se = ${_p1(diag.estimates[0].value)}%, Sp = ${_p1(diag.estimates[1].value)}%. PPV = ${_p1(diag.estimates[2].value)}% '
            'at the sample prevalence (${_p1(diag.statistics['prevalence_sample']!)}%), but only ${_p1(ppv1)}% if the prevalence is 1%.',
        exercises: [
          Exercise.numeric('With Se = 90% and Sp = ${_p1(diag.estimates[1].value)}%, what is the PPV (in %, one decimal) for a prevalence of 1%?', ppv1 * 100, 0.15,
              'PPV = Se·p / [Se·p + (1−Sp)(1−p)] = ${_p1(ppv1)}%.'),
        ],
        commonErrors: ['Transferring the PPV of a hospital study to population screening.', 'Ignoring the imprecision (CI) of Se and Sp.'],
        calculatorId: 'diagnostic_accuracy',
      ),
      Lesson(
        id: 'compare_means',
        title: 'Comparing two or more groups',
        level: Level.beginner,
        body: [
          "Quantitative outcome, two independent groups: t-test. Welch's test does not assume equal variances and loses very little when they are equal: a good default choice.",
          'Small, highly skewed samples or ordinal outcome: Mann-Whitney, which compares distributions (not specifically medians).',
          'More than two groups: ANOVA (or Welch); Kruskal-Wallis for an ordinal outcome. The global test does not say which groups differ: pairwise comparisons (Tukey, Games-Howell if variances differ, Dunn after Kruskal-Wallis) do so while controlling the family-wise error rate; if not planned, they remain exploratory.',
          'Always report the effect size (difference in means, CI) and not only p.',
        ],
        exampleTitle: 'See the example in the p-value lesson',
        example: "Welch: t = ${fmt(tt.statistics["t"])}, df = ${fmt(tt.statistics["df"])}, ${fmtP(tt.statistics["p"])}; Hedges' g = ${fmt(tt.estimates[1].value)}.",
        exercises: [
          const Exercise.choice('Blood glucose measured in the same patients before and after treatment. Which test?', ["Welch's t", 'Paired t', 'χ²'], 1,
              'Same subjects: paired data.'),
        ],
        commonErrors: ['Running a normality test and then choosing the test according to p (unreliable two-step strategy).', 'Multiplying pairwise tests without correction.'],
        calculatorId: 't_test_welch',
      ),
      const Lesson(
        id: 'paired',
        title: 'Paired data',
        level: Level.intermediate,
        body: [
          'Two measurements on the same subjects (before/after, two eyes, two tests on the same sample) are not independent: the analysis is about the within-subject differences.',
          'Quantitative: paired t (differences ~ normal) or Wilcoxon signed-rank. Binary: McNemar, which uses only the discordant pairs.',
          'Without a control group, a before/after change is not a treatment effect (regression to the mean, natural course).',
        ],
        exampleTitle: 'Two tests on 100 samples',
        example: '40 positive with both, 41 negative with both, 14 positive only with test A, 5 only with test B: only the 19 discordant pairs inform the comparison.',
        exercises: [
          Exercise.choice("How many pairs are used by McNemar's test in the example?", ['100', '19', '81'], 1, '14 + 5 = 19 discordant pairs.'),
        ],
        commonErrors: ['Analysing two measurement times as two independent groups.', 'Silently excluding incomplete pairs.'],
        calculatorId: 'mcnemar',
      ),
      const Lesson(
        id: 'correlation',
        title: 'Correlation: what it says and does not say',
        level: Level.beginner,
        body: [
          "Pearson's r measures the strength of a LINEAR relationship; Spearman's ρ that of a monotonic relationship.",
          'A strong correlation proves neither causality nor agreement between two methods (two methods can be perfectly correlated and differ by 20%).',
          'Always look at the scatter plot: an extreme value can create or hide a correlation.',
        ],
        exampleTitle: 'Creatinine on two analysers',
        example: 'If analyser B always gives 1.2 × the value of A, r = 1 although the results are not interchangeable.',
        exercises: [
          Exercise.choice('To judge whether two devices are interchangeable, one uses…', ["Pearson's r", 'Bland-Altman', "Welch's t"], 1,
              'Agreement is studied on the differences (Bland-Altman).'),
        ],
        commonErrors: ['Concluding agreement from r.', 'Interpreting r = 0 as the absence of any relationship (a non-linear relationship is possible).'],
        calculatorId: 'pearson',
      ),
      const Lesson(
        id: 'agreement',
        title: 'Agreement between methods: Bland-Altman',
        level: Level.intermediate,
        body: [
          'For each subject, the difference between methods is computed. The bias is the mean of the differences; the limits of agreement (bias ± 1.96 SD) contain about 95% of individual differences.',
          'The limits of agreement are NOT a confidence interval: they describe the spread of individuals. The CI of the bias describes the precision of the mean; each limit also has its own CI.',
          'Acceptability is judged against a clinically tolerable difference set BEFORE the analysis.',
          'If the difference increases with the measured level (proportional bias), analyse the ratio or the logarithm.',
        ],
        exampleTitle: 'Capillary vs venous blood glucose',
        example: 'Bias = +0.2 mmol/L (CI 0.05 to 0.35); limits of agreement −0.9 to +1.3 mmol/L: a patient may show a difference of 1.3 mmol/L, which a narrow CI of the bias does not show.',
        exercises: [
          Exercise.choice('"95% limits of agreement: −0.9 to 1.3" means…', [
            'that the true bias lies between −0.9 and 1.3 with 95% confidence.',
            'that about 95% of individual differences are expected between −0.9 and 1.3.',
          ], 1, 'The limits of agreement describe individuals; the CI of the bias describes the mean.'),
        ],
        commonErrors: ['Calling the limits of agreement a "confidence interval".', 'Judging agreement without an a priori clinical criterion.'],
        calculatorId: 'bland_altman',
      ),
      Lesson(
        id: 'sample_size',
        title: 'Sample size',
        level: Level.intermediate,
        body: [
          'To compare: set the minimal clinically important difference (not the hoped-for effect), the variability, α and power.',
          'To estimate a prevalence: set the desired precision (half-width of the CI); for a rare proportion, reason in relative precision.',
          'Add losses to follow-up and, for a cluster survey, the design effect.',
          'A "post hoc power" computed with the observed effect adds no information: look at the CI.',
        ],
        exampleTitle: 'Two calculations',
        example: 'Detecting a 5 mmHg difference in SBP (SD 12) with 80% power: ${fmt(ssm.statistics["n_per_group"])} subjects per group. '
            'Estimating a prevalence of 8% to ± 2%: ${fmt(ssp.statistics["n"])} subjects.',
        exercises: [
          Exercise.numeric('How many subjects PER GROUP to detect a 5 mmHg difference (SD 12, α = 0.05, power 80%)?', ssm.statistics['n_per_group']!, 0.5,
              'Non-central t distribution (as in power.t.test): ${fmt(ssm.statistics["n_exact"])} → ${fmt(ssm.statistics["n_per_group"])}.'),
        ],
        commonErrors: ['Choosing the expected effect to obtain a feasible sample size.', 'Forgetting losses to follow-up.'],
        calculatorId: 'sample_size',
      ),
      Lesson(
        id: 'power_planning',
        title: 'Power: survival, case-control and GWAS',
        level: Level.advanced,
        body: [
          'Power is the probability of detecting the effect if it truly exists. It depends on four quantities: the effect to detect, the variability (or the event frequency), α, and the sample size. Fixing three gives the fourth.',
          'Survival: power comes from the number of EVENTS, not of patients. Freedman or Schoenfeld give the number of deaths or relapses required; the number of patients follows from the probability of an event during the study (accrual, follow-up). A longer follow-up can replace patients.',
          'Case-control: the effect is an OR; power depends on the frequency of exposure in controls. Adding controls per case helps, but beyond about 4 controls per case the gain becomes small.',
          'GWAS: about one million independent tests are performed, hence the genome-wide threshold α = 5·10⁻⁸. True effects of common variants are small (OR 1.05 to 1.2): thousands to tens of thousands of cases are needed.',
          'Post hoc power, computed from the observed effect, adds nothing to the p-value: to interpret a non-significant result, look at the confidence interval.',
        ],
        exampleTitle: 'Three studies planned with 80% power',
        example: 'Trial, HR 0.7 with 45% events in the control arm: ${fmt(pwSurv.statistics['n_1'], digits: 0)} patients per arm, about ${fmt(pwSurv.statistics['events_freedman'], digits: 0)} events (Freedman; Schoenfeld ${fmt(pwSurv.statistics['events_schoenfeld'], digits: 0)}). '
            'Case-control, OR 2 with 20% exposed controls: ${fmt(pwCc1.statistics['n_0'], digits: 0)} cases with 1 control each, ${fmt(pwCc4.statistics['n_0'], digits: 0)} cases with 4 controls each. '
            'GWAS, allele at 25%, OR 1.15, α = 5·10⁻⁸: ${fmt(pwGw.statistics['n_0'], digits: 0)} cases and as many controls. '
            'A pilot study of 20 subjects per group has only ${fmtPct(pwPilot.statistics['power'])} power to detect d = 0.5.',
        exercises: [
          const Exercise.numeric('Schoenfeld: number of events to detect HR = 0.5 with 80% power, α = 0.05, 1:1 allocation (nearest integer)?', 65, 1,
              'd = (1.96 + 0.84)² × 4 / (log 0.5)² = 7.85 × 4 / 0.480 ≈ 65 events.'),
          const Exercise.choice('A survival trial records fewer deaths than planned. Its power…', [
            'is unchanged, since the number of patients is reached',
            'decreases: power depends on the number of events',
            'increases',
          ], 1, 'In survival analysis, the information comes from the events.'),
          Exercise.numeric('In the example, how many cases are needed for OR 2 with 1 control per case?', pwCc1.statistics['n_0']!, 0.5,
              '${fmt(pwCc1.statistics['n_0'], digits: 0)} cases; with 4 controls per case, ${fmt(pwCc4.statistics['n_0'], digits: 0)} cases suffice.'),
          const Exercise.choice('A first GWAS reports OR = 1.6 for a variant. To plan the replication, we should…', [
            'use OR = 1.6',
            'assume a smaller OR: the effects reported at discovery are overestimated (winner\'s curse)',
            'use α = 0.05 for the replication of all variants',
          ], 1, 'Discovery selects the estimates that happen to be largest; the true effect is generally smaller.'),
          const Exercise.choice('Non-significant result; a reviewer asks for the "observed power". Best answer?', [
            'Compute it from the observed effect',
            'Report the confidence interval of the effect, which shows which effects remain compatible with the data',
            'Increase α',
          ], 1, 'Observed power is a function of the p-value and brings no new information.'),
        ],
        commonErrors: [
          'Basing the effect to detect on the hoped-for effect or on a small pilot study.',
          'In survival, counting patients rather than events.',
          'Forgetting losses to follow-up, missing data and multiple testing.',
          'Planning a GWAS with an OR taken from a discovery study.',
          'Computing post hoc power to "explain" a non-significant result.',
        ],
        calculatorId: 'power',
      ),
      Lesson(
        id: 'confounding',
        title: 'Confounding and causality',
        level: Level.intermediate,
        body: [
          'A confounder is related to the exposure and to the outcome without lying on the causal path. It can create, hide or reverse an association.',
          "Simpson's paradox is its extreme form: the direction of the crude association reverses in every stratum.",
          'Adjustment corrects only factors that are measured, well measured and correctly modelled: residual confounding remains possible. Only randomization also balances unknown factors.',
          'Wording: "was associated with", not "causes", in an observational study.',
        ],
        exampleTitle: 'Kidney stones: treatment A vs B (Charig et al., 1986)',
        example: 'Crude: success ${_p1(crude.statistics["risk_exposed"]!)}% (A) vs ${_p1(crude.statistics["risk_unexposed"]!)}% (B), A seems worse. '
            'Small stones: ${_p1(small.statistics["risk_exposed"]!)}% vs ${_p1(small.statistics["risk_unexposed"]!)}%; large stones: '
            '${_p1(large.statistics["risk_exposed"]!)}% vs ${_p1(large.statistics["risk_unexposed"]!)}%. A is better in each stratum: '
            'stone size influences both the choice of treatment and success.',
        exercises: [
          const Exercise.choice('Should a variable on the causal path between exposure and outcome (mediator) be adjusted for to estimate the total effect?', [
            'Yes, always.',
            'No: adjusting for a mediator removes part of the effect one wants to estimate.',
          ], 1, 'Adjust for confounders, not for mediators or colliders.'),
        ],
        commonErrors: ['"Factor X increases the risk" from a cross-sectional study.', 'Adjusting for everything available (mediators, colliders).'],
        calculatorId: 'two_by_two',
      ),
      const Lesson(
        id: 'covariates',
        title: 'Choosing the covariates of a model',
        level: Level.advanced,
        body: [
          'Explanatory model: covariates are chosen a priori from a causal diagram (DAG): confounders yes, mediators and colliders no.',
          'Stepwise selection on p-values produces biased coefficients, CIs that are too narrow and non-reproducible results.',
          'The number of parameters must remain compatible with the sample size (events per parameter in logistic regression).',
          'Only the coefficient of the exposure of interest is interpreted; the coefficients of adjustment covariates have no causal interpretation ("Table 2 fallacy").',
        ],
        exampleTitle: 'Smoking and hypertension',
        example: 'For the effect of smoking on hypertension: adjust for age and sex (confounding), not for the SBP at the previous visit (close to the outcome).',
        exercises: [
          Exercise.choice('A stepwise regression kept 4 variables out of 15. The reported CIs are…', [
            'correct.',
            'too narrow, because they ignore the selection step.',
          ], 1, 'The uncertainty of the selection is not accounted for.'),
        ],
        commonErrors: ['Selection on p < 0.20 in univariable analysis.', 'Interpreting all ORs in the table as effects.'],
        calculatorId: 'linear_regression',
      ),
      const Lesson(
        id: 'small_events',
        title: "Few events, separation and Firth's regression",
        level: Level.advanced,
        body: [
          'With few events, maximum likelihood overestimates coefficients and Wald CIs have poor coverage.',
          'Separation: a variable perfectly predicts the outcome in a subgroup (e.g. no case in a category). The estimate tends to infinity; software may display an absurd number without an error.',
          "Firth's penalization gives finite and less biased estimates, but does not create information: uncertainty remains large. Its CIs and tests are read by penalized profile likelihood, not by the Wald method.",
          'Options: fewer covariates (chosen a priori), justified merging, exact methods, descriptive analysis, exploratory presentation.',
        ],
        exampleTitle: 'Mother-to-child transmission of HBsAg (fictitious data)',
        example: "2 infected children out of 48: the exact CI of the proportion runs from about 0.5% to 14%. Crossing with maternal HBeAg status (0 cases among HBeAg− mothers) produces separation: only a Firth analysis gives a finite OR. Its asymmetric penalized profile likelihood CI is to be preferred to the Wald CI, which is symmetric on the log scale and misleading with so few events.",
        exercises: [
          Exercise.choice('An OR of 3.2 × 10⁸ with an SE of 4,000 in a logistic output suggests…', ['a very strong effect', 'separation', 'moderate collinearity'], 1,
              'Excessive coefficient and SE: separation.'),
        ],
        commonErrors: ['Reporting an "infinite" or excessive OR.', 'Adding 10 covariates for 12 events.'],
        calculatorId: 'firth_logistic',
      ),
      const Lesson(
        id: 'missing',
        title: 'Missing data',
        level: Level.intermediate,
        body: [
          'MCAR: missingness unrelated to the data; MAR: related to observed variables; MNAR: related to the missing value itself.',
          'Complete-case analysis is unbiased under MCAR (and in some MAR cases) but loses power; otherwise it may be biased.',
          'Always report the number of missing values per variable and compare included and excluded subjects.',
          "Multiple imputation is the reference under MAR: m completed datasets, one analysis per dataset, pooling by Rubin's rules (the between-imputation variance reflects the uncertainty due to missing values). Include the outcome in the imputation model. Single mean imputation underestimates the variance.",
          'For a prediction model, imputation must be redone in each bootstrap replicate; otherwise internal validation reuses information from the whole dataset.',
        ],
        exampleTitle: 'Missing blood glucose',
        example: 'If blood glucose is missing mostly in patients seen in the emergency department, the MCAR assumption is implausible.',
        exercises: [
          Exercise.choice('Replacing missing values with the mean…', ['has no consequence.', 'artificially reduces the variance and can bias associations.'], 1,
              'Single imputation: illusory precision.'),
        ],
        commonErrors: ['Not mentioning exclusions.', 'Imputing the outcome in prediction without declaring it.'],
        calculatorId: 'describe_numeric',
      ),
      Lesson(
        id: 'heterogeneity',
        title: 'Heterogeneity in meta-analysis',
        level: Level.intermediate,
        body: [
          'Q tests for heterogeneity (low power with few studies). I² estimates the share of variability due to true differences between studies; τ² gives its variance on the effect scale.',
          'With random effects, the CI concerns the MEAN effect. The prediction interval shows where the effect would lie in a new comparable study.',
          'High I²: look for explanations planned a priori (population, dose, risk of bias); sometimes, do not pool.',
          'Before any pooling, check that the studies answer the same question (PICO, follow-up, measure).',
          'Meta-regression relates the effect to a study characteristic (latitude, dose, year): it explores heterogeneity but remains observational and aggregated (ecological bias); its moderators must be planned a priori.',
        ],
        exampleTitle: 'Four fictitious trials',
        example: 'Pooled RR ${fmtCi(mp)}; I² = ${fmtPct(meta.statistics["I2"])}, τ² = ${fmt(meta.statistics["tau2"])}.',
        exercises: [
          const Exercise.choice('The CI of a pooled RR (random effects) runs from 0.70 to 0.95; the prediction interval from 0.45 to 1.45. Conclusion?', [
            'The treatment is beneficial in all situations.',
            'Beneficial on average, but in a new setting the effect could be null or harmful.',
          ], 1, 'The prediction interval describes the spread of true effects.'),
        ],
        commonErrors: ['Choosing fixed/random effects according to the p-value of Q.', 'Confusing the CI and the prediction interval.', 'Believing that PRISMA guarantees the quality of studies.'],
        calculatorId: 'meta_binary',
      ),
      const Lesson(
        id: 'calibration',
        title: 'Discrimination and calibration',
        level: Level.advanced,
        body: [
          'Discrimination (AUC, C-statistic): ability to rank higher the subjects who will have the event. Calibration: agreement between predicted risks and observed frequencies.',
          'A model can discriminate well and be poorly calibrated (predicting 30% when 10% is observed): threshold-based decisions are then wrong.',
          'Calibration slope < 1: predictions too extreme, a sign of overfitting. Internal validation by bootstrap estimates this optimism.',
          'Internal validation ≠ external validation ≠ clinical usefulness. No model is "clinically validated" on its AUC alone.',
          'In external validation, the coefficients are applied WITHOUT re-estimation. A calibration intercept ≠ 0 (O/E ≠ 1) calls for an intercept update; a slope < 1, for logistic recalibration; the recalibrated version must in turn be evaluated.',
        ],
        exampleTitle: 'Cardiometabolic model (demonstration 3)',
        example: 'See the demonstration: apparent AUC, optimism-corrected AUC, corrected slope and decision curve.',
        exercises: [
          Exercise.choice('Corrected AUC 0.84, corrected slope 0.78. What should be done before use?', [
            'Use the model as is.',
            'Reduce overfitting (fewer parameters, shrinkage) and then validate externally.',
          ], 1, 'Slope 0.78: predictions too extreme; external validation is still needed.'),
        ],
        commonErrors: ['Reporting only the AUC.', 'Randomly splitting the sample and calling it "external validation".', 'Choosing the threshold on the same data without saying so.'],
        calculatorId: 'prediction_logistic_internal',
      ),
      Lesson(
        id: 'survival',
        title: 'Survival, censoring and the Cox model',
        level: Level.advanced,
        body: [
          'When the outcome is a time (to death, to relapse) and some subjects are lost to follow-up or still event-free at the end of follow-up, their time is CENSORED: we only know it exceeds the last known date.',
          'Analysing the event as a binary variable without a common horizon of complete follow-up, or excluding censored subjects, biases the results.',
          'The Cox model estimates ratios of instantaneous rates (hazard ratios, HR) without assuming the form of the baseline hazard, provided this ratio is constant over time (proportional hazards) and censoring is not informative.',
          'An HR is neither a cumulative risk ratio nor a survival difference at a date: to communicate impact, add survival curves or proportions at a given horizon.',
          'The proportionality test (cox.zph) has little power with few events: a non-significant result does not prove proportionality.',
        ],
        exampleTitle: 'Two treatments, 24 fictitious patients followed for 36 months',
        example: 'Arm B vs arm A: HR = ${fmtCi(hr)}, ${fmtP(hr.pValue)}. '
            '${cox.statistics["events"]!.toInt()} deaths, ${(24 - cox.statistics["events"]!).toInt()} censored. '
            'Concordance C = ${fmt(cox.statistics["concordance"])}. Proportionality test: ${fmtP(cox.statistics["zph_global_p"])}. '
            'With so few events, the CI is wide: neither benefit nor absence of effect is demonstrated.',
        exercises: [
          const Exercise.choice('A patient lost to follow-up at month 14, alive at the last visit, should be…', [
            'excluded from the analysis.',
            'counted as dead at month 14.',
            'included as censored at month 14.',
          ], 2, 'Censoring keeps the information "alive for at least 14 months".'),
          Exercise.numeric('In the example, what is the HR of arm B relative to arm A (two decimals)?', double.parse(hr.value.toStringAsFixed(2)), 0.006,
              'HR = ${fmt(hr.value)}; CI ${fmt(hr.lower)} to ${fmt(hr.upper)}.'),
          const Exercise.choice('HR = 0.70 (CI 0.55 to 0.89). Which sentence is correct?', [
            'Five-year survival is 30% higher with treatment.',
            'The instantaneous death rate is reduced by about 30% with treatment, other factors held fixed, if the ratio is constant over time.',
            'The treatment cures 30% of patients.',
          ], 1, 'The HR concerns the instantaneous rate, not cumulative survival.'),
        ],
        commonErrors: [
          'Excluding censored subjects or treating them as event-free.',
          'Presenting an HR as a survival difference or a 5-year risk ratio.',
          'Ignoring a departure from proportionality (HR reversing over time).',
          'Adjusting for a variable measured after the start of follow-up (immortal time bias).',
        ],
        calculatorId: 'kaplan_meier',
      ),
      Lesson(
        id: 'competing_risks',
        title: 'Competing risks and immortal time',
        level: Level.advanced,
        body: [
          'A competing event prevents the event of interest from ever happening: a patient who dies cannot relapse afterwards. Treating death as censoring (1 − Kaplan-Meier) assumes the patient could still relapse later, and overestimates the incidence.',
          'The Aalen-Johansen cumulative incidence gives the proportion of subjects who actually experience the event over time, given the competing event. The Gray test compares these incidences between groups.',
          'Two models, two questions. The cause-specific Cox model (competing events censored) describes the rate of the event among subjects still exposed — the aetiological question. The Fine-Gray model describes the cumulative incidence (sHR) — the prognostic question, how many patients will have the event. A factor can increase the cause-specific rate yet decrease the incidence, if it also hastens the competing event.',
          'Immortal time: a characteristic acquired during follow-up (transplant, treatment started later) cannot be coded at inclusion. The patient must survive until the transplant to be "transplanted": this waiting time, free of deaths by construction, is wrongly credited to the transplant.',
          'The fix: a time-dependent covariate. Follow-up is split into (start, stop] intervals: "not transplanted" up to the transplant, "transplanted" after. At each death, each patient is compared with his status at that moment.',
        ],
        exampleTitle: 'Relapse with death as competing event; heart transplant at Stanford',
        example: '20 fictitious patients: cumulative incidence of relapse at 24 months ${fmt(cr.cif * 100)}%, against ${fmt(cr.naive * 100)}% with the naive 1 − Kaplan-Meier. '
            'Stanford heart transplant programme (103 patients): coded at inclusion, transplant seems protective, HR = ${fmt(cr.hrNaive)}; as a time-dependent covariate, HR = ${fmt(cr.hrTd)} (${fmtP(cr.pTd)}). The apparent benefit came from immortal time.',
        exercises: [
          const Exercise.numeric('100 patients, no censoring. Month 1: 10 die without relapse. Month 2: 10 relapse. Naive 1 − Kaplan-Meier for relapse at month 2, in % (two decimals)?', 11.11, 0.006,
              'Deaths treated as censoring: 1 − (1 − 10/90) = 11.11%. The cumulative incidence is 10/100 = 10%: the naive estimate overestimates it.'),
          const Exercise.numeric('Same example: cumulative incidence of relapse at month 2, in %?', 10, 0.01, 'Aalen-Johansen: S(1) × 10/90 = 0.90 × 0.111 = 10%.'),
          const Exercise.choice('Age: cause-specific HR of relapse 1.03 per year, sHR 0.99. Interpretation?', [
            'One of the two models is wrong',
            'Age speeds up relapse among those still alive, but older patients die before relapsing, so the share who relapse does not increase',
            'Age has no effect',
          ], 1, 'Both are correct: they answer two different questions.'),
          Exercise.numeric('In the Stanford example, HR of transplant coded at inclusion (two decimals)?', double.parse(cr.hrNaive.toStringAsFixed(2)), 0.006,
              'HR = ${fmt(cr.hrNaive)}: spectacular but biased, since transplanted patients had by definition survived until their transplant.'),
          const Exercise.choice('To estimate the effect of a treatment started during follow-up, we should…', [
            'compare patients who ever received it with the others',
            'exclude patients who died before being able to receive it',
            'code it as a time-dependent covariate (or use a landmark analysis)',
          ], 2, 'The first two options create or worsen immortal time bias.'),
        ],
        commonErrors: [
          'Reporting 1 − Kaplan-Meier as a probability of the event when deaths are frequent.',
          'Interpreting an sHR as an effect on the rate of the event, or a cause-specific HR as an effect on the proportion of patients.',
          'Coding at inclusion a characteristic acquired during follow-up (immortal time bias).',
          'Excluding patients who died early "because they could not be treated".',
        ],
        calculatorId: 'cumulative_incidence',
      ),
      Lesson(
        id: 'genetics',
        title: 'Genetics and genomics: association, multiplicity, expression',
        level: Level.advanced,
        body: [
          'A biallelic variant gives three genotypes. In controls, Hardy-Weinberg equilibrium serves as a GENOTYPING QUALITY check: a marked departure (p < 10⁻³) suggests a technical error before any biological explanation.',
          'The genetic model (additive, dominant, recessive) is fixed before seeing the data. Testing the three and keeping the best inflates the false-positive rate; the Armitage trend test (additive model) is the usual default.',
          'With many variants or genes, multiplicity dominates: 20 independent tests at 5% give on average one false positive under the null. Bonferroni controls the risk of at least one error (FWER); Benjamini-Hochberg controls the proportion of false discoveries (FDR). The genome-wide threshold is 5 × 10⁻⁸.',
          'Population stratification (cases and controls of different ancestry) confounds associations: adjust or match, and replicate in an independent cohort.',
          'RNA-seq: raw counts depend on sequencing depth and library composition; TMM normalization corrects them, voom models the mean–variance relationship and limma stabilizes gene variances (empirical Bayes). A log2 fold change of 1 is a doubling.',
          'qPCR: ΔΔCt assumes 100% efficiency for both genes (a doubling per cycle); otherwise use the Pfaffl ratio with the measured efficiencies. Technical replicates are averaged; only biological replicates count as n.',
          'Alignment: the E-value is the number of matches this good expected by chance in THIS library; it depends on its size. Identity and coverage judge the identification (16S: ≥ 99% for species, ≥ 97% for genus, as benchmarks).',
        ],
        exampleTitle: 'One variant, 300 cases and 300 controls',
        example: 'Allele T: OR per allele = ${fmtCi(orAllelic)}, trend test ${fmtP(gen.statistics['trend_p'])}. Hardy-Weinberg in controls: ${fmtP(gen.statistics['hwe_controls_p'])}. '
            'In another variant (159/119/72 controls), HWE ${fmtP(hweBad.statistics['p_exact'])}: check the genotyping before interpreting it. '
            'qPCR: ΔΔCt = ${fmt(ddct.statistics['ddct'])}, i.e. expression × ${fmt(ddct.statistics['fold'])} in treated samples.',
        exercises: [
          const Exercise.numeric('20 independent variants with no real effect are each tested at 5%. How many false positives are expected on average?', 1, 0.01,
              '20 × 0.05 = 1. Hence the need for a multiple-testing correction.'),
          Exercise.numeric('In the example, what is the OR per allele T (two decimals)?', double.parse(orAllelic.value.toStringAsFixed(2)), 0.006,
              'OR = ${fmt(orAllelic.value)}; CI ${fmt(orAllelic.lower)} to ${fmt(orAllelic.upper)}.'),
          const Exercise.choice('In controls, a variant departs strongly from Hardy-Weinberg (p = 10⁻⁷). First reaction?', [
            'Conclude that the variant is under natural selection.',
            'Check the genotyping (calling errors, contamination) before any analysis.',
            'Remove the controls in disequilibrium.',
          ], 1, 'In controls, a marked HWE departure is primarily a quality signal.'),
          const Exercise.numeric('ΔΔCt = 2 (treated − control). What is the expression ratio treated/control (2^−ΔΔCt)?', 0.25, 0.001,
              '2^−2 = 0.25: expression is divided by 4 in treated samples.'),
          const Exercise.choice('Two searches give E = 10⁻⁵ against a library of 50 sequences and E = 10⁻⁵ against a library of 5 million. Which statement is correct?', [
            'The raw similarity is the same in both cases.',
            'The second match has a much higher score, since the same E is reached in a much larger search space.',
            'E-values from different libraries are directly comparable for identification.',
          ], 1, 'E = K·m·n·e^(−λS): for the same E, a larger n requires a higher score.'),
        ],
        commonErrors: [
          'Testing dominant, recessive and additive models and reporting only the best.',
          'Reporting uncorrected p-values for hundreds of variants or thousands of genes.',
          'Analysing normalized values (FPKM, TPM) with tools designed for raw counts.',
          'Counting technical replicates as independent samples.',
          'Concluding a species from the best BLAST match without looking at identity, coverage and the next match.',
        ],
        calculatorId: 'genomics',
      ),
      Lesson(
        id: 'gwas',
        title: 'Genome-wide association studies: quality, relatedness, stratification',
        level: Level.advanced,
        body: [
          'A genome-wide association study (GWAS) tests hundreds of thousands of variants. Quality control comes first, with thresholds fixed in advance: call rate of subjects and variants, heterozygosity (contamination), minor allele frequency, Hardy-Weinberg in controls.',
          'Subjects must be independent: duplicates and relatives (kinship φ: about 0.5 for duplicates, 0.25 for 1st degree, IBS0 ≈ 0 for parent–offspring) are detected and one subject per pair is kept, or a mixed model is used.',
          'Population stratification: if cases and controls differ in ancestry, every variant whose frequency differs between populations appears associated. Principal components summarize ancestry and are added as covariates.',
          'The genomic inflation λ (median of the χ² statistics divided by 0.455) should be close to 1; the QQ plot shows whether p-values depart from the diagonal from the start (stratification) or only at the tail (true signals).',
          'LD score regression separates the two sources of inflation: variants in strong linkage disequilibrium tag more polygenic signal, but not more confounding. Regressing χ² on the LD score gives a slope (heritability h²_SNP) and an intercept: about 1 without confounding, > 1 with stratification or cryptic relatedness. Ratio = (intercept − 1)/(mean χ² − 1) = share of inflation due to confounding. It needs many variants (≥ 200,000) and is not applied after genomic control or a LOCO mixed model. Crossing two scans (product of signed z) gives the genetic correlation rg = ρg/√(h²₁·h²₂) between two diseases.',
          'Genome-wide significance threshold: 5 × 10⁻⁸ (about 0.05 / 1,000,000 independent tests); 10⁻⁵ is only "suggestive". A non-significant variant may simply lack power. Any association requires independent replication.',
        ],
        exampleTitle: '300 simulated variants, 200 cases and 200 controls from two populations',
        example: 'Cases and controls with the same ancestry mix: λ = ${fmt(gw.balanced, digits: 3)}. Cases mostly from population 2 (70% vs 30%): λ = ${fmt(gw.confounded, digits: 3)} — with no causal variant, this inflation is entirely due to stratification. Demo 5 goes further: λ falls from 1.47 to 1.00 after adjusting for 2 principal components.',
        exercises: [
          const Exercise.numeric('Genome-wide threshold 5 × 10⁻⁸: what is its −log10 (two decimals)?', 7.30, 0.006, '−log10(5 × 10⁻⁸) = 7.30: the red line of a Manhattan plot.'),
          const Exercise.numeric('The median of the χ² statistics of a scan is 0.682. What is λ (two decimals)?', 1.50, 0.006, 'λ = 0.682 / 0.455 = 1.50: strong inflation, look for stratification or relatedness.'),
          const Exercise.choice('A pair of subjects has φ = 0.25 and IBS0 ≈ 0. Most likely relationship?', [
            'Duplicate sample',
            'Parent–offspring',
            'Full siblings',
            'First cousins',
          ], 1, 'φ ≈ 0.25 is 1st degree; IBS0 ≈ 0 (never opposite homozygotes) characterizes parent–offspring.'),
          const Exercise.numeric('Under the null hypothesis, with 1,000 tests, what is the expected −log10 of the smallest p (ppoints: (1 − 0.5)/1000; two decimals)?', 3.30, 0.006,
              '−log10(0.5 / 1000) = 3.30: a p of 10⁻³ among 1,000 tests is not remarkable.'),
          const Exercise.choice('On the QQ plot, the points leave the diagonal from the smallest values of −log10 p. Interpretation?', [
            'Many true associations',
            'Systematic inflation: stratification, relatedness or genotyping problem',
            'Insufficient power',
          ], 1, 'A departure from the start of the plot reflects inflation of all statistics, not isolated signals.'),
          const Exercise.numeric('LD score regression: intercept 1.10, mean χ² 1.50. What share of the inflation is due to confounding (ratio, two decimals)?', 0.20, 0.006,
              'Ratio = (1.10 − 1)/(1.50 − 1) = 0.20: most of the inflation (80%) reflects polygenicity; adjustment is still worth checking.'),
          const Exercise.numeric('Genetic covariance ρg = 0.12, h²₁ = 0.40, h²₂ = 0.25. What is the genetic correlation rg (two decimals)?', 0.38, 0.006,
              'rg = 0.12 / √(0.40 × 0.25) = 0.12 / 0.316 = 0.38: the two traits share part of their genetic factors.'),
          const Exercise.choice('A variant has p = 5.8 × 10⁻⁵ after adjustment. Which conclusion?', [
            'It has no effect',
            'It is associated with the disease',
            'Suggestive signal: neither excluded nor demonstrated; to be replicated in an independent cohort',
          ], 2, 'Below 5 × 10⁻⁸ is not reached: absence of evidence, not evidence of absence (in demo 5 it is a true causal variant lacking power).'),
        ],
        commonErrors: [
          'Interpreting a high λ as a polygenic signal without adjusting for principal components (or checking the LD score regression intercept).',
          'Keeping duplicates or relatives as independent subjects.',
          'Using the 5% threshold (or a non-corrected p) for thousands of variants.',
          'Testing Hardy-Weinberg in cases (a true association departs from equilibrium in cases).',
          'Presenting the OR per allele as a risk ratio in a case-control study.',
        ],
        calculatorId: 'genotype_qc',
      ),
      Lesson(
        id: 'polygenic',
        title: 'Polygenicity, LD score regression, polygenic scores and Mendelian randomization',
        level: Level.advanced,
        body: [
          'Most common diseases are polygenic: thousands of variants each with a tiny effect. In a large GWAS, the χ² statistics are then inflated even WITHOUT confounding: λ grows with sample size and heritability. A λ > 1 alone does not distinguish polygenicity from stratification.',
          'LD score regression: E[χ²] = 1 + N·a + N·h²·ℓ/M, where ℓ is the LD score of the variant (sum of its r² with its neighbours). A variant in strong LD tags more polygenic signal, but not more confounding: the slope estimates h²_SNP, the intercept (1 + N·a) the confounding. Ratio = (intercept − 1)/(mean χ² − 1) = share of the inflation due to confounding.',
          'Conditions: many variants (≥ 200,000), LD scores from the same ancestry, and no prior genomic control (which forces the intercept towards 1). After a LOCO mixed model, the intercept may fall below 1.',
          'Genetic correlation rg: crossing two scans (product of signed z) gives the genetic covariance; rg = ρg/√(h²₁·h²₂). The cross intercept absorbs the overlap of samples. A genetic correlation reflects shared factors (pleiotropy, common pathway), not causality, and is unstable if one h² is close to 0.',
          'Polygenic risk score: sum of the alleles weighted by their effects, after clumping and a p threshold. Effects, threshold and performance must come from three distinct samples: the performance measured where the threshold was chosen is optimistic. The AUC of a score is modest; it stratifies a population but is not a diagnostic test, and it loses much of its performance in another ancestry.',
          'Mendelian randomization: variants associated with an exposure act as instruments randomly allocated at conception. The Wald ratio βY/βX of each variant estimates the causal effect; IVW combines them, MR-Egger (intercept = directional pleiotropy) and the weighted median are robust to some invalid instruments. Conditions: strong instruments (F ≥ 10), no effect of the variants on the outcome other than through the exposure.',
          'Relatives: rather than excluding them, a mixed model (linear for a quantitative trait, logistic for a case-control status) includes the genomic relationship matrix and restores a λ close to 1.',
        ],
        exampleTitle: '20,000 simulated variants (N = 20,000, h² = 0.3)',
        example: 'Without confounding: mean χ² ${fmt(pg.clean.meanChi2, digits: 3)}, intercept ${fmt(pg.clean.intercept, digits: 3)} (SE ${fmt(pg.clean.seIntercept, digits: 2)}), h² ${fmt(pg.clean.h2, digits: 2)} — the inflation is purely polygenic. With confounding adding 0.25 to every expected χ²: mean χ² ${fmt(pg.confounded.meanChi2, digits: 3)}, intercept ${fmt(pg.confounded.intercept, digits: 3)}, h² ${fmt(pg.confounded.h2, digits: 2)}, ratio ${fmt(pg.confounded.ratio, digits: 2)}: the intercept captures the confounding, the slope (h²) hardly changes. Demo 6 shows the same contrast on genotypes.',
        exercises: [
          const Exercise.numeric('N = 20,000, h² = 0.25, mean LD score 80, M = 1,000,000 variants, no confounding. Expected mean χ² (two decimals)?', 1.40, 0.006,
              '1 + N·h²·ℓ̄/M = 1 + 20,000 × 0.25 × 80 / 1,000,000 = 1.40: a λ well above 1 without any confounding.'),
          const Exercise.numeric('Intercept 1.06, mean χ² 1.30. Ratio (share of the inflation due to confounding, two decimals)?', 0.20, 0.006,
              'Ratio = 0.06 / 0.30 = 0.20: 80% of the inflation is polygenic.'),
          const Exercise.numeric('A variant raises LDL cholesterol by 0.10 mmol/L per allele (βX) and the log-odds of coronary disease by 0.03 (βY). Wald ratio estimate of the causal effect, per mmol/L, on the log-odds scale (two decimals)?', 0.30, 0.006,
              'βY/βX = 0.03/0.10 = 0.30 log-odds per mmol/L, i.e. an OR of e^0.30 ≈ 1.35 per mmol/L.'),
          const Exercise.choice('λ = 1.35 and LD score regression intercept 1.01 (SE 0.01). Interpretation?', [
            'Strong stratification: adjust for principal components',
            'Inflation explained by polygenicity; no detectable confounding',
            'Genotyping error',
          ], 1, 'An intercept compatible with 1 means the inflation follows the LD score: polygenic signal.'),
          const Exercise.choice('A polygenic score has a Nagelkerke R² of 0.25 in the sample where the threshold was chosen and 0.11 in an independent test sample. Which value to report?', [
            '0.25: it is the best',
            'The mean of the two',
            '0.11: only the independent sample gives an unbiased performance',
          ], 2, 'Choosing the threshold on a sample overstates performance there (optimism).'),
          const Exercise.choice('rg = 0.6 between type 2 diabetes and coronary disease. Conclusion?', [
            'Diabetes causes coronary disease',
            'The two diseases share part of their genetic factors',
            'The same patients have both diseases',
          ], 1, 'rg measures shared genetic effects (pleiotropy or common pathway), not causality; Mendelian randomization addresses causality.'),
        ],
        commonErrors: [
          'Concluding to stratification from λ > 1 alone in a large GWAS (polygenicity also inflates λ).',
          'Applying LD score regression after genomic control, or with LD scores from another ancestry.',
          'Reading a genetic correlation as a causal effect.',
          'Reporting the performance of a polygenic score on the sample used to choose its threshold.',
          'Using a polygenic score as an individual diagnostic test, or in another ancestry without revalidation.',
        ],
        calculatorId: 'ldsc',
      ),
      Lesson(
        id: 'causal_mr',
        title: 'Causality and Mendelian randomization',
        level: Level.advanced,
        body: [
          'An observational association between an exposure and a disease may reflect confounding or reverse causation. Alleles are allocated at random at conception (Mendel\'s laws): variants that raise an exposure act as a natural randomization, like a lifelong trial.',
          'Three assumptions make a variant a valid instrument: (1) relevance — it is associated with the exposure (mean F statistic ≥ 10); (2) independence — it is not associated with confounders (same ancestry, no stratification); (3) exclusion restriction — it acts on the outcome only through the exposure (no horizontal pleiotropy). Only the first can be tested directly.',
          'Estimation: the Wald ratio βY/βX of each variant estimates the causal effect per unit of exposure; IVW combines them (weights 1/se_Y²). For a binary outcome, βY is in log-odds: exp(θ) is an OR per unit of exposure.',
          'Robust methods relax the exclusion assumption: MR-Egger (valid if pleiotropic effects are independent of the instrument strengths; its intercept detects directional pleiotropy), weighted median (valid if at least half of the weight comes from valid instruments), weighted mode (valid if the largest group of similar estimates is valid), leave-one-out (no single variant drives the result). Agreement between methods strengthens the conclusion.',
          'Multivariable MR: when variants act on several related exposures (LDL, HDL, triglycerides), it estimates the direct effect of each, holding the others fixed.',
          'Direction: a variant chosen for the exposure may in fact act first on the outcome. The Steiger test checks that the variants explain more variance of the exposure than of the outcome; reverse MR (outcome → exposure) explores the opposite direction.',
          'Interpretation: MR estimates the effect of a small lifelong difference in exposure, not that of a short intervention in adulthood; the size of the effect is not directly transposable to a drug.',
        ],
        exampleTitle: 'Published data: 28 variants, lipids and coronary heart disease',
        example: 'LDL cholesterol: IVW ${fmt(mx.ldl.ivw.estimate, digits: 3)} log-odds per mmol/L (OR ${fmt(math.exp(mx.ldl.ivw.estimate), digits: 3)}), MR-Egger ${fmt(mx.ldl.egger.estimate, digits: 3)}, weighted median ${fmt(mx.ldl.median.estimate, digits: 3)}, Egger intercept p = ${fmt(mx.ldl.eggerIntercept.p, digits: 2)}: concordant methods. HDL cholesterol: IVW ${fmt(mx.hdl.ivw.estimate, digits: 3)} (apparently protective), but Egger intercept p = ${fmt(mx.hdl.eggerIntercept.p, digits: 2)} and MR-Egger ${fmt(mx.hdl.egger.estimate, digits: 2)}; in multivariable MR the direct HDL effect is ${fmt(mx.mv.estimates[1].estimate, digits: 2)} (95% CI ${fmt(mx.mv.estimates[1].lower, digits: 2)} to ${fmt(mx.mv.estimates[1].upper, digits: 2)}). Demo 7 develops this example.',
        exercises: [
          const Exercise.numeric('A variant raises an exposure by βX = 0.20 units and the log-odds of the disease by βY = 0.10. Causal OR per unit of exposure (Wald ratio, two decimals)?', 1.65, 0.006,
              'θ = βY/βX = 0.50 log-odds per unit; OR = e^0.50 = 1.65.'),
          const Exercise.numeric('βX = 0.05 with a standard error of 0.01. F statistic of this instrument?', 25, 0.5,
              'F ≈ (βX/se)² = 5² = 25 ≥ 10: instrument strong enough.'),
          const Exercise.numeric('Steiger test: a variant has β/SE = 10 in an exposure study of N = 10,000. Share of variance of the exposure it explains, r² in % (two decimals)?', 0.99, 0.006,
              'F = 100; r² = F/(N − 2 + F) = 100/10,098 = 0.0099, i.e. 0.99%. It is compared with the r² of the outcome to check the direction.'),
          const Exercise.choice('A variant used as an instrument for LDL also raises blood pressure, which affects the disease. Which assumption is violated?', [
            'Relevance',
            'Independence from confounders',
            'Exclusion restriction (horizontal pleiotropy)',
          ], 2, 'The variant reaches the outcome through another pathway than the exposure: horizontal pleiotropy.'),
          const Exercise.choice('IVW significant, MR-Egger intercept p = 0.01, MR-Egger slope not significant. Interpretation?', [
            'Robust causal effect',
            'Directional pleiotropy likely: IVW is biased, do not conclude on it alone',
            'Weak instruments',
          ], 1, 'A non-zero intercept signals directional pleiotropy; the robust methods must be examined.'),
          const Exercise.choice('The weighted median remains valid if…', [
            'all instruments are valid',
            'at least half of the weight comes from valid instruments',
            'the MR-Egger intercept is zero',
          ], 1, 'The median tolerates up to 50% of the weight from invalid instruments.'),
        ],
        commonErrors: [
          'Concluding causality without discussing the instrument assumptions (especially pleiotropy).',
          'Relying on IVW alone when MR-Egger, median and mode disagree.',
          'Using weak instruments (F < 10) or exposure and outcome samples of different ancestries.',
          'Transposing the effect of a lifelong genetic exposure to a drug given in adulthood.',
          'Interpreting the univariable effect of an exposure correlated with others (HDL) as its own effect.',
        ],
        calculatorId: 'mendelian_randomization',
      ),
      const Lesson(
        id: 'explanatory_vs_predictive',
        title: 'Explanatory or predictive model?',
        level: Level.advanced,
        body: [
          'Explanatory: estimate the effect of ONE exposure, controlling confounding. Covariates come from causal reasoning; one coefficient is interpreted.',
          'Predictive: estimate an individual risk as well as possible. Predictors must be available at the time of prediction; discrimination, calibration and usefulness are judged, not the coefficients.',
          'A good predictor is not a cause (a symptom predicts the disease); a cause may predict poorly.',
          'Mixing the two aims leads to inconsistent choices (stepwise selection to "explain", causal interpretation of a score).',
        ],
        exampleTitle: 'Waist circumference',
        example: 'In a risk score, waist circumference improves prediction; this does not mean that reducing waist circumference would reduce the risk by as much.',
        exercises: [
          Exercise.choice('Aim: to find out whether smoking increases the risk of hypertension. The main evaluation criterion is…', [
            'the AUC of the model',
            'the adjusted estimate of the effect of smoking and its CI',
          ], 1, 'Explanatory question.'),
        ],
        commonErrors: ['Interpreting the ORs of a score as causal effects.', 'Judging an explanatory model on its AUC.'],
        calculatorId: 'logistic_regression',
      ),
    ];
  }

  return [
    Lesson(
      id: 'ic',
      title: 'Intervalle de confiance d\'une proportion',
      level: Level.beginner,
      body: [
        'Une proportion observée dans un échantillon (p̂ = x/n) estime une proportion inconnue de la population. L\'intervalle de confiance (IC) à 95 % rassemble les valeurs de la population compatibles avec les données, sous les hypothèses du calcul.',
        '« 95 % » qualifie la méthode : répétée sur de nombreux échantillons, elle produirait des intervalles contenant la vraie valeur dans 95 % des cas. Pour UN intervalle donné, on ne dit pas qu\'il a 95 % de chances de contenir la vraie valeur.',
        'L\'IC de Wald (p̂ ± 1,96√(p̂(1−p̂)/n)) est mauvais quand p̂ est proche de 0 ou 1 ou quand n est petit. Préférer Wilson ou l\'IC exact de Clopper-Pearson.',
        'Avec zéro événement, la proportion vraie n\'est pas nulle : la « règle de trois » donne une borne supérieure unilatérale à 95 % ≈ 3/n.',
      ],
      exampleTitle: 'Prévalence de l\'AgHBs chez 400 femmes enceintes (données fictives)',
      example: '12 porteuses sur 400 : prévalence ${_p1(w.value)} %, IC de Wilson ${_p1(w.lower!)} % à ${_p1(w.upper!)} %. '
          'Avec 0 cas sur 150, la borne supérieure exacte est ${_p1(prev0.estimates[1].upper!)} % et la règle de trois donne ${_p1(3 / 150)} %.',
      exercises: [
        Exercise.numeric('Dans un échantillon de 400 donneurs, 12 sont porteurs de l\'AgHBs. Quelle est la borne SUPÉRIEURE de l\'IC de Wilson à 95 %, en % (une décimale) ?',
            w.upper! * 100, 0.06, 'Wilson : ${_p1(w.lower!)} % à ${_p1(w.upper!)} %. L\'IC de Wald donnerait une borne inférieure trop basse.'),
        const Exercise.choice('Aucun cas d\'infection sur 150 nouveau-nés. Quelle formulation est correcte ?', [
          'Le risque d\'infection est nul.',
          'Le risque est compatible avec des valeurs allant jusqu\'à environ 2 %.',
          'L\'IC à 95 % est de 0 % à 0 %.',
        ], 1, 'Zéro observé n\'est pas zéro vrai : 3/150 = 2 % (règle de trois).'),
      ],
      commonErrors: [
        'Rapporter « 0 % » sans borne supérieure quand aucun cas n\'est observé.',
        'Utiliser l\'IC de Wald pour une proportion rare.',
        'Généraliser une prévalence d\'un échantillon de convenance (donneurs volontaires) à la population générale.',
      ],
      calculatorId: 'proportion_ci',
    ),
    Lesson(
      id: 'p_value',
      title: 'Valeur de p : absence de preuve n\'est pas preuve d\'absence',
      level: Level.beginner,
      body: [
        'La valeur de p mesure la compatibilité des données avec l\'hypothèse nulle ET toutes les hypothèses du modèle : c\'est la probabilité d\'observer des données au moins aussi extrêmes si ces hypothèses étaient vraies.',
        'Ce n\'est pas la probabilité que l\'hypothèse nulle soit vraie, ni la probabilité que le résultat soit « dû au hasard », ni une mesure de l\'importance clinique.',
        'p > 0,05 ne prouve pas l\'absence d\'effet : il faut regarder l\'IC. Si l\'IC contient à la fois 0 et des effets cliniquement importants, l\'étude n\'a simplement pas conclu.',
        'Conclure à l\'absence de différence pertinente exige une marge fixée a priori et un IC entièrement contenu dans cette marge (logique d\'équivalence).',
      ],
      exampleTitle: 'Glycémie dans deux groupes de 8 patients (données fictives)',
      example: 'Différence de moyennes = ${fmt(dm.value)} mmol/L, IC ${fmt(dm.lower)} à ${fmt(dm.upper)}, ${fmtP(dm.pValue)}. '
          'L\'IC indique l\'ampleur plausible de la différence, ce que la valeur de p seule ne dit pas.',
      exercises: [
        const Exercise.choice('Un essai trouve p = 0,30 et un IC du RR de 0,6 à 1,9. Quelle conclusion ?', [
          'Le traitement n\'a pas d\'effet.',
          'Les données ne permettent pas de conclure : un effet bénéfique comme délétère reste compatible.',
          'Il y a 30 % de chances que le traitement soit inefficace.',
        ], 1, 'IC large incluant des effets importants dans les deux sens : absence de preuve.'),
        const Exercise.choice('p = 0,03 signifie que…', [
          'la probabilité que H0 soit vraie est de 3 %.',
          'si H0 et le modèle étaient vrais, des données au moins aussi extrêmes seraient observées dans 3 % des cas.',
          'il y a 97 % de chances que l\'effet soit réel.',
        ], 1, 'Définition fréquentiste ; les deux autres réponses sont des erreurs classiques.'),
      ],
      commonErrors: [
        'Écrire « pas de différence (p = 0,12) ».',
        '« Tendance à la significativité » pour p = 0,07.',
        'Comparer deux sous-groupes en notant que l\'un est significatif et l\'autre non (tester l\'interaction).',
      ],
      calculatorId: 't_test_welch',
    ),
    Lesson(
      id: 'or_rr',
      title: 'Odds ratio et risque relatif',
      level: Level.beginner,
      body: [
        'Le risque relatif (RR) rapporte deux risques : a/(a+b) divisé par c/(c+d). Il exige que les proportions par groupe estiment des risques : cohorte, essai, ou transversal (rapport de prévalences).',
        'L\'odds ratio (OR) rapporte deux cotes (odds = p/(1−p)). Il est la seule mesure estimable en cas-témoins et la mesure naturelle de la régression logistique.',
        'Quand l\'issue est rare (< 10 %), OR ≈ RR. Quand elle est fréquente, l\'OR est plus éloigné de 1 que le RR : le rédiger comme « risque multiplié par » exagère l\'effet.',
        'Pour un RR ajusté d\'une issue fréquente, la régression de Poisson à variance robuste est une option ; en cas-témoins, seule la logistique (OR) convient.',
      ],
      exampleTitle: 'HTA chez exposés (120/500) et non exposés (80/500), cohorte fictive',
      example: 'RR = ${fmt(rr.value)} (IC ${fmt(rr.lower)} à ${fmt(rr.upper)}) mais OR = ${fmt(or.value)} (IC ${fmt(or.lower)} à ${fmt(or.upper)}) : '
          'l\'issue touche 20 % des sujets, l\'OR surestime l\'ampleur relative.',
      exercises: [
        Exercise.numeric('Cohorte : 120 HTA parmi 500 exposés, 80 parmi 500 non exposés. Calculez le RR (deux décimales).', rr.value, 0.006,
            'RR = (120/500)/(80/500) = ${fmt(rr.value)}. L\'OR vaut ${fmt(or.value)}.'),
        const Exercise.choice('Dans une étude cas-témoins, quelle mesure est estimable ?', ['Le RR', 'La différence de risques', 'L\'OR'], 2,
            'Les cas et témoins sont échantillonnés sur l\'issue : les risques ne sont pas estimables.'),
      ],
      commonErrors: [
        '« Les exposés ont 1,7 fois plus de risque » à partir d\'un OR avec une issue fréquente.',
        'Calculer une prévalence de la maladie dans un échantillon cas-témoins.',
        'Oublier la mesure absolue (différence de risques), nécessaire pour juger l\'impact.',
      ],
      calculatorId: 'two_by_two',
    ),
    Lesson(
      id: 'diagnostic',
      title: 'Sensibilité, spécificité et valeurs prédictives',
      level: Level.beginner,
      body: [
        'Se = proportion de tests positifs chez les malades ; Sp = proportion de tests négatifs chez les non-malades. Elles décrivent le test (dans un spectre de patients donné).',
        'VPP et VPN dépendent de la prévalence : un même test a une VPP faible quand la maladie est rare.',
        'Les rapports de vraisemblance (RV+ = Se/(1−Sp), RV− = (1−Se)/Sp) transforment une probabilité pré-test en probabilité post-test.',
        'Un recrutement cas-témoins (malades sévères contre volontaires sains) surestime Se et Sp (biais de spectre) et rend VPP/VPN non transposables.',
        'Pour combiner plusieurs études, le modèle bivarié analyse Se et Sp ensemble : elles sont corrélées entre études (seuils différents, effet de seuil). La courbe SROC et la région de prédiction montrent la variabilité attendue d\'un contexte à l\'autre.',
      ],
      exampleTitle: 'Test rapide contre la référence (données fictives)',
      example: 'Se = ${_p1(diag.estimates[0].value)} %, Sp = ${_p1(diag.estimates[1].value)} %. VPP = ${_p1(diag.estimates[2].value)} % '
          'à la prévalence de l\'échantillon (${_p1(diag.statistics['prevalence_sample']!)} %), mais seulement ${_p1(ppv1)} % si la prévalence est de 1 %.',
      exercises: [
        Exercise.numeric('Avec Se = 90 % et Sp = ${_p1(diag.estimates[1].value)} %, quelle est la VPP (en %, une décimale) pour une prévalence de 1 % ?', ppv1 * 100, 0.15,
            'VPP = Se·p / [Se·p + (1−Sp)(1−p)] = ${_p1(ppv1)} %.'),
      ],
      commonErrors: ['Transposer la VPP d\'une étude hospitalière au dépistage en population.', 'Ignorer l\'imprécision (IC) de Se et Sp.'],
      calculatorId: 'diagnostic_accuracy',
    ),
    Lesson(
      id: 'compare_means',
      title: 'Comparer deux groupes ou plus',
      level: Level.beginner,
      body: [
        'Issue quantitative, deux groupes indépendants : test t. Le test de Welch ne suppose pas l\'égalité des variances et perd très peu quand elles sont égales : c\'est un bon choix par défaut.',
        'Petits effectifs très asymétriques ou issue ordinale : Mann-Whitney, qui compare des distributions (pas spécifiquement des médianes).',
        'Plus de deux groupes : ANOVA (ou Welch) ; Kruskal-Wallis pour une issue ordinale. Le test global ne dit pas quels groupes diffèrent : les comparaisons deux à deux (Tukey, Games-Howell si les variances diffèrent, Dunn après Kruskal-Wallis) le font en contrôlant le risque d\'erreur global ; non prévues au plan, elles restent exploratoires.',
        'Rapporter toujours la taille d\'effet (différence de moyennes, IC) et pas seulement p.',
      ],
      exampleTitle: 'Voir l\'exemple de la leçon sur la valeur de p',
      example: 'Welch : t = ${fmt(tt.statistics["t"])}, ddl = ${fmt(tt.statistics["df"])}, ${fmtP(tt.statistics["p"])} ; g de Hedges = ${fmt(tt.estimates[1].value)}.',
      exercises: [
        const Exercise.choice('Glycémie mesurée chez les mêmes patients avant et après traitement. Quel test ?', ['t de Welch', 't apparié', 'χ²'], 1,
            'Mêmes sujets : données appariées.'),
      ],
      commonErrors: ['Faire un test de normalité puis choisir le test selon p (stratégie en deux temps peu fiable).', 'Multiplier les tests deux à deux sans correction.'],
      calculatorId: 't_test_welch',
    ),
    const Lesson(
      id: 'paired',
      title: 'Données appariées',
      level: Level.intermediate,
      body: [
        'Deux mesures sur les mêmes sujets (avant/après, deux yeux, deux tests sur le même prélèvement) ne sont pas indépendantes : l\'analyse porte sur les différences intra-sujet.',
        'Quantitatif : t apparié (différences ~ normales) ou Wilcoxon signé. Binaire : McNemar, qui n\'utilise que les paires discordantes.',
        'Sans groupe témoin, un changement avant/après n\'est pas un effet du traitement (régression vers la moyenne, évolution naturelle).',
      ],
      exampleTitle: 'Deux tests sur 100 prélèvements',
      example: '40 positifs aux deux, 41 négatifs aux deux, 14 positifs seulement au test A, 5 seulement au test B : seules les 19 paires discordantes informent la comparaison.',
      exercises: [
        Exercise.choice('Combien de paires sont utilisées par le test de McNemar dans l\'exemple ?', ['100', '19', '81'], 1, '14 + 5 = 19 paires discordantes.'),
      ],
      commonErrors: ['Analyser deux temps de mesure comme deux groupes indépendants.', 'Exclure silencieusement les paires incomplètes.'],
      calculatorId: 'mcnemar',
    ),
    const Lesson(
      id: 'correlation',
      title: 'Corrélation : ce qu\'elle dit et ne dit pas',
      level: Level.beginner,
      body: [
        'Le r de Pearson mesure l\'intensité d\'une relation LINÉAIRE ; le ρ de Spearman celle d\'une relation monotone.',
        'Une corrélation forte ne prouve ni la causalité, ni l\'accord entre deux méthodes (deux méthodes peuvent être parfaitement corrélées et différer de 20 %).',
        'Toujours regarder le nuage de points : une valeur extrême peut créer ou masquer une corrélation.',
      ],
      exampleTitle: 'Créatinine par deux automates',
      example: 'Si l\'automate B donne toujours 1,2 × la valeur de A, r = 1 alors que les résultats ne sont pas interchangeables.',
      exercises: [
        Exercise.choice('Pour juger si deux appareils sont interchangeables, on utilise…', ['r de Pearson', 'Bland-Altman', 't de Welch'], 1,
            'L\'accord s\'étudie sur les différences (Bland-Altman).'),
      ],
      commonErrors: ['Conclure à l\'accord à partir de r.', 'Interpréter r = 0 comme absence de toute relation (relation non linéaire possible).'],
      calculatorId: 'pearson',
    ),
    const Lesson(
      id: 'agreement',
      title: 'Accord entre méthodes : Bland-Altman',
      level: Level.intermediate,
      body: [
        'On calcule pour chaque sujet la différence entre méthodes. Le biais est la moyenne des différences ; les limites d\'accord (biais ± 1,96 ÉT) contiennent environ 95 % des différences individuelles.',
        'Les limites d\'accord ne sont PAS un intervalle de confiance : elles décrivent la dispersion des individus. L\'IC du biais décrit la précision de la moyenne ; chaque limite a aussi son propre IC.',
        'L\'acceptabilité se juge contre un écart cliniquement tolérable fixé AVANT l\'analyse.',
        'Si la différence augmente avec le niveau mesuré (biais proportionnel), analyser le rapport ou le logarithme.',
      ],
      exampleTitle: 'Glycémie capillaire vs veineuse',
      example: 'Biais = +0,2 mmol/L (IC 0,05 à 0,35) ; limites d\'accord −0,9 à +1,3 mmol/L : un patient peut présenter un écart de 1,3 mmol/L, ce qu\'un IC du biais étroit ne montre pas.',
      exercises: [
        Exercise.choice('« Limites d\'accord à 95 % : −0,9 à 1,3 » signifie…', [
          'que le biais vrai est entre −0,9 et 1,3 avec 95 % de confiance.',
          'qu\'environ 95 % des différences individuelles sont attendues entre −0,9 et 1,3.',
        ], 1, 'Les limites d\'accord décrivent les individus ; l\'IC du biais décrit la moyenne.'),
      ],
      commonErrors: ['Appeler les limites d\'accord « intervalle de confiance ».', 'Juger l\'accord sans critère clinique a priori.'],
      calculatorId: 'bland_altman',
    ),
    Lesson(
      id: 'sample_size',
      title: 'Taille d\'échantillon',
      level: Level.intermediate,
      body: [
        'Pour comparer : fixer la différence minimale cliniquement pertinente (pas l\'effet espéré), la variabilité, α et la puissance.',
        'Pour estimer une prévalence : fixer la précision voulue (demi-largeur de l\'IC) ; pour une proportion rare, raisonner en précision relative.',
        'Ajouter les perdus de vue et, pour un sondage en grappes, l\'effet de plan.',
        'Une « puissance a posteriori » calculée avec l\'effet observé n\'apporte aucune information : regarder l\'IC.',
      ],
      exampleTitle: 'Deux calculs',
      example: 'Détecter 5 mmHg de différence de PAS (ÉT 12) avec 80 % de puissance : ${fmt(ssm.statistics["n_per_group"])} sujets par groupe. '
          'Estimer une prévalence de 8 % à ± 2 % : ${fmt(ssp.statistics["n"])} sujets.',
      exercises: [
        Exercise.numeric('Combien de sujets PAR GROUPE pour détecter 5 mmHg de différence (ÉT 12, α = 0,05, puissance 80 %) ?', ssm.statistics['n_per_group']!, 0.5,
            'Loi de Student non centrale (comme power.t.test) : ${fmt(ssm.statistics["n_exact"])} → ${fmt(ssm.statistics["n_per_group"])}.'),
      ],
      commonErrors: ['Choisir l\'effet attendu pour obtenir un effectif faisable.', 'Oublier les perdus de vue.'],
      calculatorId: 'sample_size',
    ),
    Lesson(
      id: 'power_planning',
      title: 'Puissance : survie, cas-témoins et GWAS',
      level: Level.advanced,
      body: [
        'La puissance est la probabilité de détecter l\'effet s\'il existe vraiment. Elle dépend de quatre quantités : l\'effet à détecter, la variabilité (ou la fréquence de l\'événement), α et l\'effectif. En fixer trois donne la quatrième.',
        'Survie : la puissance vient du nombre d\'ÉVÉNEMENTS, non de patients. Freedman ou Schoenfeld donnent le nombre de décès ou de rechutes nécessaires ; le nombre de patients s\'en déduit par la probabilité d\'un événement pendant l\'étude (recrutement, suivi). Un suivi plus long peut remplacer des patients.',
        'Cas-témoins : l\'effet est un OR ; la puissance dépend de la fréquence de l\'exposition chez les témoins. Ajouter des témoins par cas aide, mais au-delà d\'environ 4 témoins par cas le gain devient faible.',
        'GWAS : environ un million de tests indépendants sont réalisés, d\'où le seuil pangénomique α = 5·10⁻⁸. Les vrais effets des variants fréquents sont petits (OR 1,05 à 1,2) : il faut des milliers à des dizaines de milliers de cas.',
        'La puissance a posteriori, calculée à partir de l\'effet observé, n\'apporte rien de plus que la p : pour interpréter un résultat non significatif, regarder l\'intervalle de confiance.',
      ],
      exampleTitle: 'Trois études planifiées à 80 % de puissance',
      example: 'Essai, HR 0,7 avec 45 % d\'événements dans le bras contrôle : ${fmt(pwSurv.statistics['n_1'], digits: 0)} patients par bras, environ ${fmt(pwSurv.statistics['events_freedman'], digits: 0)} événements (Freedman ; Schoenfeld ${fmt(pwSurv.statistics['events_schoenfeld'], digits: 0)}). '
          'Cas-témoins, OR 2 avec 20 % de témoins exposés : ${fmt(pwCc1.statistics['n_0'], digits: 0)} cas avec 1 témoin chacun, ${fmt(pwCc4.statistics['n_0'], digits: 0)} cas avec 4 témoins chacun. '
          'GWAS, allèle à 25 %, OR 1,15, α = 5·10⁻⁸ : ${fmt(pwGw.statistics['n_0'], digits: 0)} cas et autant de témoins. '
          'Une étude pilote de 20 sujets par groupe n\'a que ${fmtPct(pwPilot.statistics['power'])} de puissance pour détecter d = 0,5.',
      exercises: [
        const Exercise.numeric('Schoenfeld : nombre d\'événements pour détecter HR = 0,5 avec 80 % de puissance, α = 0,05, allocation 1:1 (entier le plus proche) ?', 65, 1,
            'd = (1,96 + 0,84)² × 4 / (log 0,5)² = 7,85 × 4 / 0,480 ≈ 65 événements.'),
        const Exercise.choice('Un essai de survie enregistre moins de décès que prévu. Sa puissance…', [
          'est inchangée, puisque le nombre de patients est atteint',
          'diminue : la puissance dépend du nombre d\'événements',
          'augmente',
        ], 1, 'En analyse de survie, l\'information vient des événements.'),
        Exercise.numeric('Dans l\'exemple, combien de cas faut-il pour un OR de 2 avec 1 témoin par cas ?', pwCc1.statistics['n_0']!, 0.5,
            '${fmt(pwCc1.statistics['n_0'], digits: 0)} cas ; avec 4 témoins par cas, ${fmt(pwCc4.statistics['n_0'], digits: 0)} cas suffisent.'),
        const Exercise.choice('Un premier GWAS rapporte un OR de 1,6 pour un variant. Pour planifier la réplication, il faut…', [
          'utiliser OR = 1,6',
          'supposer un OR plus petit : les effets publiés à la découverte sont surestimés (malédiction du vainqueur)',
          'utiliser α = 0,05 pour la réplication de tous les variants',
        ], 1, 'La découverte sélectionne les estimations qui se trouvent être les plus grandes ; le vrai effet est en général plus petit.'),
        const Exercise.choice('Résultat non significatif ; un relecteur demande la « puissance observée ». Meilleure réponse ?', [
          'La calculer à partir de l\'effet observé',
          'Donner l\'intervalle de confiance de l\'effet, qui montre quels effets restent compatibles avec les données',
          'Augmenter α',
        ], 1, 'La puissance observée est une fonction de la p et n\'apporte aucune information nouvelle.'),
      ],
      commonErrors: [
        'Fonder l\'effet à détecter sur l\'effet espéré ou sur une petite étude pilote.',
        'En survie, compter les patients plutôt que les événements.',
        'Oublier les perdus de vue, les données manquantes et la multiplicité des tests.',
        'Planifier un GWAS avec un OR tiré d\'une étude de découverte.',
        'Calculer une puissance a posteriori pour « expliquer » un résultat non significatif.',
      ],
      calculatorId: 'power',
    ),
    Lesson(
      id: 'confounding',
      title: 'Confusion et causalité',
      level: Level.intermediate,
      body: [
        'Un facteur de confusion est lié à l\'exposition et à l\'issue sans être sur le chemin causal. Il peut créer, masquer ou inverser une association.',
        'Le paradoxe de Simpson en est la forme extrême : le sens de l\'association brute s\'inverse dans chaque strate.',
        'L\'ajustement ne corrige que les facteurs mesurés, bien mesurés et correctement modélisés : une confusion résiduelle reste possible. Seule la randomisation équilibre aussi les facteurs inconnus.',
        'Formulation : « était associé à », pas « entraîne », dans une étude observationnelle.',
      ],
      exampleTitle: 'Calculs rénaux : traitement A vs B (Charig et al., 1986)',
      example: 'Brut : succès ${_p1(crude.statistics["risk_exposed"]!)} % (A) vs ${_p1(crude.statistics["risk_unexposed"]!)} % (B), A semble moins bon. '
          'Petits calculs : ${_p1(small.statistics["risk_exposed"]!)} % vs ${_p1(small.statistics["risk_unexposed"]!)} % ; gros calculs : '
          '${_p1(large.statistics["risk_exposed"]!)} % vs ${_p1(large.statistics["risk_unexposed"]!)} %. A est meilleur dans chaque strate : '
          'la taille du calcul influence à la fois le choix du traitement et le succès.',
      exercises: [
        const Exercise.choice('Une variable située sur le chemin causal entre exposition et issue (médiateur) doit-elle être ajustée pour estimer l\'effet total ?', [
          'Oui, toujours.',
          'Non : ajuster sur un médiateur retire une partie de l\'effet qu\'on veut estimer.',
        ], 1, 'On ajuste sur les facteurs de confusion, pas sur les médiateurs ni les colliders.'),
      ],
      commonErrors: ['« Le facteur X augmente le risque » à partir d\'une étude transversale.', 'Ajuster sur tout ce qui est disponible (médiateurs, colliders).'],
      calculatorId: 'two_by_two',
    ),
    const Lesson(
      id: 'covariates',
      title: 'Choisir les covariables d\'un modèle',
      level: Level.advanced,
      body: [
        'Modèle explicatif : les covariables se choisissent a priori à partir d\'un schéma causal (DAG) : facteurs de confusion oui, médiateurs et colliders non.',
        'La sélection pas à pas sur les valeurs de p produit des coefficients biaisés, des IC trop étroits et des résultats non reproductibles.',
        'Le nombre de paramètres doit rester compatible avec l\'effectif (événements par paramètre en logistique).',
        'Seul le coefficient de l\'exposition d\'intérêt s\'interprète ; les coefficients des covariables d\'ajustement n\'ont pas d\'interprétation causale (sophisme de la « table 2 »).',
      ],
      exampleTitle: 'Tabac et HTA',
      example: 'Pour l\'effet du tabac sur l\'HTA : ajuster sur l\'âge et le sexe (confusion), pas sur la PAS de la visite précédente (proche de l\'issue).',
      exercises: [
        Exercise.choice('Une régression pas à pas a retenu 4 variables sur 15. Les IC rapportés sont…', [
          'corrects.',
          'trop étroits, car ils ignorent l\'étape de sélection.',
        ], 1, 'L\'incertitude de la sélection n\'est pas prise en compte.'),
      ],
      commonErrors: ['Sélection sur p < 0,20 en analyse univariée.', 'Interpréter tous les OR du tableau comme des effets.'],
      calculatorId: 'linear_regression',
    ),
    const Lesson(
      id: 'small_events',
      title: 'Peu d\'événements, séparation et régression de Firth',
      level: Level.advanced,
      body: [
        'Avec peu d\'événements, le maximum de vraisemblance surestime les coefficients et les IC de Wald couvrent mal.',
        'Séparation : une variable prédit parfaitement l\'issue dans un sous-groupe (p. ex. aucun cas dans une catégorie). L\'estimation tend vers l\'infini ; un logiciel peut afficher un nombre absurde sans erreur.',
        'La pénalisation de Firth donne des estimations finies et moins biaisées, mais ne crée pas d\'information : l\'incertitude reste grande. Ses IC et tests se lisent par vraisemblance profilée pénalisée, pas par la méthode de Wald.',
        'Options : moins de covariables (choisies a priori), regroupement justifié, méthodes exactes, analyse descriptive, présentation exploratoire.',
      ],
      exampleTitle: 'Transmission mère-enfant de l\'AgHBs (données fictives)',
      example: '2 enfants infectés sur 48 : l\'IC exact de la proportion va d\'environ 0,5 % à 14 %. Croiser avec le statut AgHBe maternel (0 cas chez les mères AgHBe−) produit une séparation : seule une analyse de Firth donne un OR fini. Son IC par vraisemblance profilée pénalisée, asymétrique, est à préférer à l\'IC de Wald, symétrique sur l\'échelle log et trompeur avec si peu d\'événements.',
      exercises: [
        Exercise.choice('Un OR de 3,2 × 10⁸ avec un ES de 4 000 en sortie de logistique évoque…', ['un effet très fort', 'une séparation', 'une colinéarité modérée'], 1,
            'Coefficient et ES démesurés : séparation.'),
      ],
      commonErrors: ['Rapporter un OR « infini » ou démesuré.', 'Ajouter 10 covariables pour 12 événements.'],
      calculatorId: 'firth_logistic',
    ),
    const Lesson(
      id: 'missing',
      title: 'Données manquantes',
      level: Level.intermediate,
      body: [
        'MCAR : manque sans lien avec les données ; MAR : lié aux variables observées ; MNAR : lié à la valeur manquante elle-même.',
        'L\'analyse en cas complets est sans biais sous MCAR (et dans certains cas MAR) mais perd de la puissance ; elle peut être biaisée sinon.',
        'Toujours rapporter le nombre de manquants par variable et comparer inclus et exclus.',
        'L\'imputation multiple est la référence sous MAR : m jeux complétés, une analyse par jeu, combinaison par les règles de Rubin (la variance entre imputations traduit l\'incertitude due aux manquants). Inclure l\'issue dans le modèle d\'imputation. Une imputation simple par la moyenne sous-estime la variance.',
        'Pour un modèle de prédiction, l\'imputation doit être refaite dans chaque réplique bootstrap ; sinon la validation interne réutilise une information issue de l\'ensemble des données.',
      ],
      exampleTitle: 'Glycémie manquante',
      example: 'Si la glycémie manque surtout chez les patients vus en urgence, l\'hypothèse MCAR est peu plausible.',
      exercises: [
        Exercise.choice('Remplacer les valeurs manquantes par la moyenne…', ['est sans conséquence.', 'réduit artificiellement la variance et peut biaiser les associations.'], 1,
            'Imputation simple : précision illusoire.'),
      ],
      commonErrors: ['Ne pas mentionner les exclusions.', 'Imputer l\'issue en prédiction sans le déclarer.'],
      calculatorId: 'describe_numeric',
    ),
    Lesson(
      id: 'heterogeneity',
      title: 'Hétérogénéité en métaanalyse',
      level: Level.intermediate,
      body: [
        'Q teste l\'existence d\'une hétérogénéité (faible puissance avec peu d\'études). I² estime la part de variabilité due à de vraies différences entre études ; τ² en donne la variance sur l\'échelle de l\'effet.',
        'En effets aléatoires, l\'IC concerne l\'effet MOYEN. L\'intervalle de prédiction indique où se situerait l\'effet dans une nouvelle étude comparable.',
        'I² élevé : chercher des explications prévues a priori (population, dose, risque de biais) ; parfois, ne pas combiner.',
        'Avant toute combinaison, vérifier que les études répondent à la même question (PICO, suivi, mesure).',
        'La méta-régression relie l\'effet à une caractéristique des études (latitude, dose, année) : elle explore l\'hétérogénéité mais reste observationnelle et agrégée (biais écologique) ; ses modérateurs doivent être prévus a priori.',
      ],
      exampleTitle: 'Quatre essais fictifs',
      example: 'RR combiné ${fmtCi(mp)} ; I² = ${fmtPct(meta.statistics["I2"])}, τ² = ${fmt(meta.statistics["tau2"])}.',
      exercises: [
        const Exercise.choice('L\'IC d\'un RR combiné (effets aléatoires) va de 0,70 à 0,95 ; l\'intervalle de prédiction de 0,45 à 1,45. Conclusion ?', [
          'Le traitement est bénéfique dans toutes les situations.',
          'En moyenne bénéfique, mais dans un nouveau contexte l\'effet pourrait être nul ou délétère.',
        ], 1, 'L\'intervalle de prédiction décrit la dispersion des effets vrais.'),
      ],
      commonErrors: ['Choisir effet fixe/aléatoire selon la valeur de p de Q.', 'Confondre IC et intervalle de prédiction.', 'Croire que PRISMA garantit la qualité des études.'],
      calculatorId: 'meta_binary',
    ),
    const Lesson(
      id: 'calibration',
      title: 'Discrimination et calibration',
      level: Level.advanced,
      body: [
        'Discrimination (AUC, C-statistique) : capacité à classer plus haut les sujets qui auront l\'événement. Calibration : accord entre risques prédits et fréquences observées.',
        'Un modèle peut bien discriminer et être mal calibré (prédire 30 % quand on observe 10 %) : décisions fondées sur des seuils fausses.',
        'Pente de calibration < 1 : prédictions trop extrêmes, signe de surajustement. La validation interne par bootstrap estime cet optimisme.',
        'Validation interne ≠ validation externe ≠ utilité clinique. Aucun modèle n\'est « validé cliniquement » sur sa seule AUC.',
        'En validation externe, les coefficients sont appliqués SANS réestimation. Un intercept de calibration ≠ 0 (O/E ≠ 1) appelle une mise à jour de l\'intercept ; une pente < 1, une recalibration logistique ; la version recalibrée doit à son tour être évaluée.',
      ],
      exampleTitle: 'Modèle cardiométabolique (démonstration 3)',
      example: 'Voir la démonstration : AUC apparente, AUC corrigée de l\'optimisme, pente corrigée et courbe de décision.',
      exercises: [
        Exercise.choice('AUC corrigée 0,84, pente corrigée 0,78. Que faire avant usage ?', [
          'Utiliser le modèle tel quel.',
          'Réduire le surajustement (moins de paramètres, rétrécissement) puis valider en externe.',
        ], 1, 'Pente 0,78 : prédictions trop extrêmes ; la validation externe reste nécessaire.'),
      ],
      commonErrors: ['Rapporter seulement l\'AUC.', 'Partager aléatoirement l\'échantillon et appeler cela « validation externe ».', 'Choisir le seuil sur les mêmes données sans le dire.'],
      calculatorId: 'prediction_logistic_internal',
    ),
    Lesson(
      id: 'survival',
      title: 'Survie, censure et modèle de Cox',
      level: Level.advanced,
      body: [
        'Quand l\'issue est un délai (jusqu\'au décès, à la rechute) et que certains sujets sont perdus de vue ou encore indemnes à la fin du suivi, leur durée est CENSURÉE : on sait seulement qu\'elle dépasse la dernière date connue.',
        'Analyser l\'événement comme une variable binaire sans horizon commun de suivi complet, ou exclure les censurés, biaise les résultats.',
        'Le modèle de Cox estime des rapports de taux instantanés (hazard ratios, HR) sans supposer la forme du risque de base, à condition que ce rapport soit constant dans le temps (risques proportionnels) et que la censure ne soit pas informative.',
        'Un HR n\'est ni un risque relatif cumulé ni une différence de survie à une date : pour communiquer un impact, compléter par des courbes de survie ou des proportions à un horizon donné.',
        'Le test de proportionnalité (cox.zph) a peu de puissance avec peu d\'événements : un résultat non significatif ne prouve pas la proportionnalité.',
      ],
      exampleTitle: 'Deux traitements, 24 patients fictifs suivis 36 mois',
      example: 'Bras B vs bras A : HR = ${fmtCi(hr)}, ${fmtP(hr.pValue)}. '
          '${cox.statistics["events"]!.toInt()} décès, ${(24 - cox.statistics["events"]!).toInt()} censures. '
          'Concordance C = ${fmt(cox.statistics["concordance"])}. Test de proportionnalité : ${fmtP(cox.statistics["zph_global_p"])}. '
          'Avec si peu d\'événements, l\'IC est large : ni bénéfice ni absence d\'effet ne sont démontrés.',
      exercises: [
        const Exercise.choice('Un patient perdu de vue au 14e mois, vivant à sa dernière visite, doit être…', [
          'exclu de l\'analyse.',
          'compté comme décédé au 14e mois.',
          'inclus comme censuré au 14e mois.',
        ], 2, 'La censure conserve l\'information « vivant au moins 14 mois ».'),
        Exercise.numeric('Dans l\'exemple, quel est le HR du bras B par rapport au bras A (deux décimales) ?', double.parse(hr.value.toStringAsFixed(2)), 0.006,
            'HR = ${fmt(hr.value)} ; IC ${fmt(hr.lower)} à ${fmt(hr.upper)}.'),
        const Exercise.choice('HR = 0,70 (IC 0,55 à 0,89). Quelle phrase est correcte ?', [
          'La survie à 5 ans est 30 % plus élevée sous traitement.',
          'Le taux instantané de décès est réduit d\'environ 30 % sous traitement, à autres facteurs fixés, si le rapport est constant dans le temps.',
          'Le traitement guérit 30 % des patients.',
        ], 1, 'Le HR porte sur le taux instantané, pas sur la survie cumulée.'),
      ],
      commonErrors: [
        'Exclure les sujets censurés ou les traiter comme sans événement.',
        'Présenter un HR comme une différence de survie ou un risque relatif à 5 ans.',
        'Ignorer un écart à la proportionnalité (HR qui s\'inverse dans le temps).',
        'Ajuster sur une variable mesurée après le début du suivi (biais du temps immortel).',
      ],
      calculatorId: 'kaplan_meier',
    ),
    Lesson(
      id: 'competing_risks',
      title: 'Risques concurrents et temps immortel',
      level: Level.advanced,
      body: [
        'Un événement concurrent empêche définitivement l\'événement d\'intérêt : un patient décédé ne peut plus rechuter. Traiter le décès comme une censure (1 − Kaplan-Meier) suppose que le patient pourrait encore rechuter plus tard, et surestime l\'incidence.',
        'L\'incidence cumulée d\'Aalen-Johansen donne la proportion de sujets qui connaissent réellement l\'événement au cours du temps, compte tenu de l\'événement concurrent. Le test de Gray compare ces incidences entre groupes.',
        'Deux modèles, deux questions. Le Cox spécifique de cause (événements concurrents censurés) décrit la vitesse de survenue chez les sujets encore exposés — question étiologique. Le modèle de Fine-Gray décrit l\'incidence cumulée (sHR) — question pronostique : combien de patients auront l\'événement. Un facteur peut augmenter la vitesse de survenue et diminuer l\'incidence s\'il précipite aussi l\'événement concurrent.',
        'Temps immortel : une caractéristique acquise en cours de suivi (greffe, traitement commencé plus tard) ne peut pas être codée à l\'inclusion. Le patient doit survivre jusqu\'à la greffe pour être « greffé » : ce temps d\'attente, sans décès par construction, est attribué à tort à la greffe.',
        'La correction : une covariable dépendant du temps. Le suivi est découpé en intervalles (début, fin] : « non greffé » jusqu\'à la greffe, « greffé » ensuite. À chaque décès, chaque patient est comparé avec son statut à ce moment.',
      ],
      exampleTitle: 'Rechute avec décès concurrent ; greffe cardiaque à Stanford',
      example: '20 patients fictifs : incidence cumulée de rechute à 24 mois ${fmt(cr.cif * 100)} %, contre ${fmt(cr.naive * 100)} % avec le 1 − Kaplan-Meier naïf. '
          'Programme de greffe cardiaque de Stanford (103 patients) : codée à l\'inclusion, la greffe paraît protectrice, HR = ${fmt(cr.hrNaive)} ; en covariable dépendant du temps, HR = ${fmt(cr.hrTd)} (${fmtP(cr.pTd)}). Le bénéfice apparent venait du temps immortel.',
      exercises: [
        const Exercise.numeric('100 patients, aucune censure. Mois 1 : 10 décès sans rechute. Mois 2 : 10 rechutes. 1 − Kaplan-Meier naïf de la rechute au mois 2, en % (deux décimales) ?', 11.11, 0.006,
            'Décès traités comme censures : 1 − (1 − 10/90) = 11,11 %. L\'incidence cumulée vaut 10/100 = 10 % : l\'estimation naïve la surestime.'),
        const Exercise.numeric('Même exemple : incidence cumulée de la rechute au mois 2, en % ?', 10, 0.01, 'Aalen-Johansen : S(1) × 10/90 = 0,90 × 0,111 = 10 %.'),
        const Exercise.choice('Âge : HR spécifique de cause de la rechute 1,03 par an, sHR 0,99. Interprétation ?', [
          'Un des deux modèles est faux',
          'L\'âge accélère la rechute chez les patients encore vivants, mais les patients âgés meurent avant de rechuter : la proportion de rechutes n\'augmente pas',
          'L\'âge n\'a aucun effet',
        ], 1, 'Les deux sont justes : ils répondent à deux questions différentes.'),
        Exercise.numeric('Dans l\'exemple de Stanford, HR de la greffe codée à l\'inclusion (deux décimales) ?', double.parse(cr.hrNaive.toStringAsFixed(2)), 0.006,
            'HR = ${fmt(cr.hrNaive)} : spectaculaire mais biaisé, car les greffés avaient par définition survécu jusqu\'à leur greffe.'),
        const Exercise.choice('Pour estimer l\'effet d\'un traitement commencé en cours de suivi, il faut…', [
          'comparer les patients qui l\'ont reçu un jour aux autres',
          'exclure les patients décédés avant d\'avoir pu le recevoir',
          'le coder en covariable dépendant du temps (ou faire une analyse « landmark »)',
        ], 2, 'Les deux premières options créent ou aggravent le biais du temps immortel.'),
      ],
      commonErrors: [
        'Rapporter 1 − Kaplan-Meier comme une probabilité d\'événement quand les décès sont fréquents.',
        'Lire un sHR comme un effet sur la vitesse de survenue, ou un HR spécifique de cause comme un effet sur la proportion de patients.',
        'Coder à l\'inclusion une caractéristique acquise en cours de suivi (biais du temps immortel).',
        'Exclure les patients décédés tôt « parce qu\'ils n\'ont pas pu être traités ».',
      ],
      calculatorId: 'cumulative_incidence',
    ),
    Lesson(
      id: 'genetics',
      title: 'Génétique et génomique : association, multiplicité, expression',
      level: Level.advanced,
      body: [
        'Un variant biallélique donne trois génotypes. Chez les témoins, l\'équilibre de Hardy-Weinberg sert de CONTRÔLE DE QUALITÉ du génotypage : un écart marqué (p < 10⁻³) évoque une erreur technique avant toute explication biologique.',
        'Le modèle génétique (additif, dominant, récessif) se fixe avant de voir les données. Tester les trois et garder le meilleur gonfle le risque de faux positif ; le test de tendance d\'Armitage (modèle additif) est le choix usuel par défaut.',
        'Avec de nombreux variants ou gènes, la multiplicité domine : 20 tests indépendants à 5 % donnent en moyenne un faux positif sous l\'hypothèse nulle. Bonferroni contrôle le risque d\'au moins une erreur (FWER) ; Benjamini-Hochberg contrôle la proportion de fausses découvertes (FDR). Le seuil pangénomique est 5 × 10⁻⁸.',
        'La stratification de population (cas et témoins d\'ascendances différentes) confond les associations : ajuster ou apparier, et répliquer dans une cohorte indépendante.',
        'RNA-seq : les comptages bruts dépendent de la profondeur de séquençage et de la composition des librairies ; la normalisation TMM les corrige, voom modélise la relation moyenne–variance et limma stabilise les variances des gènes (Bayes empirique). Un log2 FC de 1 est un doublement.',
        'qPCR : ΔΔCt suppose une efficacité de 100 % pour les deux gènes (doublement à chaque cycle) ; sinon, utiliser le rapport de Pfaffl avec les efficacités mesurées. Les réplicats techniques se moyennent ; seuls les réplicats biologiques comptent comme n.',
        'Alignement : l\'E-value est le nombre de correspondances aussi bonnes attendues par hasard dans CETTE bibliothèque ; elle dépend de sa taille. L\'identité et la couverture jugent l\'identification (16S : ≥ 99 % pour l\'espèce, ≥ 97 % pour le genre, à titre de repères).',
      ],
      exampleTitle: 'Un variant, 300 cas et 300 témoins',
      example: 'Allèle T : OR par allèle = ${fmtCi(orAllelic)}, test de tendance ${fmtP(gen.statistics['trend_p'])}. Hardy-Weinberg chez les témoins : ${fmtP(gen.statistics['hwe_controls_p'])}. '
          'Pour un autre variant (témoins 159/119/72), HWE ${fmtP(hweBad.statistics['p_exact'])} : vérifier le génotypage avant de l\'interpréter. '
          'qPCR : ΔΔCt = ${fmt(ddct.statistics['ddct'])}, soit une expression × ${fmt(ddct.statistics['fold'])} chez les traités.',
      exercises: [
        const Exercise.numeric('On teste 20 variants indépendants sans effet réel, chacun à 5 %. Combien de faux positifs en moyenne ?', 1, 0.01,
            '20 × 0,05 = 1. D\'où la nécessité d\'une correction des tests multiples.'),
        Exercise.numeric('Dans l\'exemple, quel est l\'OR par allèle T (deux décimales) ?', double.parse(orAllelic.value.toStringAsFixed(2)), 0.006,
            'OR = ${fmt(orAllelic.value)} ; IC ${fmt(orAllelic.lower)} à ${fmt(orAllelic.upper)}.'),
        const Exercise.choice('Chez les témoins, un variant s\'écarte fortement de Hardy-Weinberg (p = 10⁻⁷). Première réaction ?', [
          'Conclure que le variant est soumis à sélection naturelle.',
          'Vérifier le génotypage (erreurs d\'appel, contamination) avant toute analyse.',
          'Retirer les témoins en déséquilibre.',
        ], 1, 'Chez les témoins, un écart marqué à HWE est d\'abord un signal de qualité.'),
        const Exercise.numeric('ΔΔCt = 2 (traités − témoins). Quel est le rapport d\'expression traités/témoins (2^−ΔΔCt) ?', 0.25, 0.001,
            '2^−2 = 0,25 : l\'expression est divisée par 4 chez les traités.'),
        const Exercise.choice('Deux recherches donnent E = 10⁻⁵, l\'une contre une bibliothèque de 50 séquences, l\'autre contre 5 millions. Quelle affirmation est correcte ?', [
          'La similarité brute est la même dans les deux cas.',
          'La seconde correspondance a un score nettement plus élevé, puisque la même E est atteinte dans un espace de recherche bien plus grand.',
          'Les E-values de bibliothèques différentes sont directement comparables pour l\'identification.',
        ], 1, 'E = K·m·n·e^(−λS) : à E égale, un n plus grand exige un score plus élevé.'),
      ],
      commonErrors: [
        'Tester les modèles dominant, récessif et additif et ne rapporter que le meilleur.',
        'Rapporter des p non corrigés pour des centaines de variants ou des milliers de gènes.',
        'Analyser des valeurs normalisées (FPKM, TPM) avec des outils conçus pour des comptages bruts.',
        'Compter les réplicats techniques comme des échantillons indépendants.',
        'Conclure à une espèce sur la meilleure correspondance BLAST sans regarder l\'identité, la couverture et la correspondance suivante.',
      ],
      calculatorId: 'genomics',
    ),
    Lesson(
      id: 'gwas',
      title: 'Études d\'association pangénomiques : qualité, parenté, stratification',
      level: Level.advanced,
      body: [
        'Une étude d\'association pangénomique (GWAS) teste des centaines de milliers de variants. Le contrôle de qualité vient d\'abord, avec des seuils fixés à l\'avance : taux d\'appel des sujets et des variants, hétérozygotie (contamination), fréquence de l\'allèle mineur, Hardy-Weinberg chez les témoins.',
        'Les sujets doivent être indépendants : doublons et apparentés (parenté φ : environ 0,5 pour un doublon, 0,25 au 1er degré, IBS0 ≈ 0 pour parent–enfant) sont repérés et l\'on garde un sujet par paire, ou l\'on utilise un modèle mixte.',
        'Stratification de population : si cas et témoins diffèrent par l\'ascendance, tout variant dont la fréquence diffère entre populations paraît associé. Les composantes principales résument l\'ascendance et s\'ajoutent en covariables.',
        'L\'inflation génomique λ (médiane des χ² divisée par 0,455) doit être proche de 1 ; le QQ plot montre si les p s\'écartent de la diagonale dès le début (stratification) ou seulement en queue (vrais signaux).',
        'La régression LD score sépare les deux sources d\'inflation : un variant en fort déséquilibre de liaison capte davantage de signal polygénique, mais pas davantage de confusion. Régresser les χ² sur le score LD donne une pente (héritabilité h²_SNP) et un intercept : environ 1 sans confusion, > 1 en cas de stratification ou d\'apparentement cryptique. Ratio = (intercept − 1)/(χ² moyen − 1) = part de l\'inflation due à la confusion. Elle demande de nombreux variants (≥ 200 000) et ne s\'applique pas après un contrôle génomique ou un modèle mixte LOCO. Croiser deux balayages (produit des z signés) donne la corrélation génétique rg = ρg/√(h²₁·h²₂) entre deux maladies.',
        'Seuil pangénomique : 5 × 10⁻⁸ (environ 0,05 / 1 000 000 de tests indépendants) ; 10⁻⁵ n\'est que « suggestif ». Un variant non significatif peut simplement manquer de puissance. Toute association demande une réplication indépendante.',
      ],
      exampleTitle: '300 variants simulés, 200 cas et 200 témoins issus de deux populations',
      example: 'Cas et témoins de même mélange d\'ascendances : λ = ${fmt(gw.balanced, digits: 3)}. Cas surtout issus de la population 2 (70 % contre 30 %) : λ = ${fmt(gw.confounded, digits: 3)} — sans aucun variant causal, cette inflation est due entièrement à la stratification. La démonstration 5 va plus loin : λ passe de 1,47 à 1,00 après ajustement sur 2 composantes principales.',
      exercises: [
        const Exercise.numeric('Seuil pangénomique 5 × 10⁻⁸ : combien vaut son −log10 (deux décimales) ?', 7.30, 0.006, '−log10(5 × 10⁻⁸) = 7,30 : la ligne rouge d\'un Manhattan plot.'),
        const Exercise.numeric('La médiane des χ² d\'un balayage vaut 0,682. Combien vaut λ (deux décimales) ?', 1.50, 0.006, 'λ = 0,682 / 0,455 = 1,50 : forte inflation, rechercher une stratification ou une parenté.'),
        const Exercise.choice('Une paire de sujets a φ = 0,25 et IBS0 ≈ 0. Relation la plus probable ?', [
          'Doublon d\'échantillon',
          'Parent–enfant',
          'Frères/sœurs',
          'Cousins germains',
        ], 1, 'φ ≈ 0,25 est le 1er degré ; IBS0 ≈ 0 (jamais d\'homozygotes opposés) caractérise le lien parent–enfant.'),
        const Exercise.numeric('Sous l\'hypothèse nulle, avec 1 000 tests, quel est le −log10 attendu du plus petit p (ppoints : (1 − 0,5)/1000 ; deux décimales) ?', 3.30, 0.006,
            '−log10(0,5 / 1000) = 3,30 : un p de 10⁻³ parmi 1 000 tests n\'a rien de remarquable.'),
        const Exercise.choice('Sur le QQ plot, les points quittent la diagonale dès les plus petites valeurs de −log10 p. Interprétation ?', [
          'De nombreuses vraies associations',
          'Inflation systématique : stratification, parenté ou problème de génotypage',
          'Puissance insuffisante',
        ], 1, 'Un écart dès le début du graphique traduit une inflation de toutes les statistiques, pas des signaux isolés.'),
        const Exercise.numeric('Régression LD score : intercept 1,10, χ² moyen 1,50. Quelle part de l\'inflation est due à la confusion (ratio, deux décimales) ?', 0.20, 0.006,
            'Ratio = (1,10 − 1)/(1,50 − 1) = 0,20 : l\'essentiel de l\'inflation (80 %) traduit la polygénie ; l\'ajustement reste à vérifier.'),
        const Exercise.numeric('Covariance génétique ρg = 0,12, h²₁ = 0,40, h²₂ = 0,25. Combien vaut la corrélation génétique rg (deux décimales) ?', 0.38, 0.006,
            'rg = 0,12 / √(0,40 × 0,25) = 0,12 / 0,316 = 0,38 : les deux traits partagent une partie de leurs facteurs génétiques.'),
        const Exercise.choice('Un variant a p = 5,8 × 10⁻⁵ après ajustement. Quelle conclusion ?', [
          'Il n\'a aucun effet',
          'Il est associé à la maladie',
          'Signal suggestif : ni exclu ni démontré ; à répliquer dans une cohorte indépendante',
        ], 2, 'Le seuil de 5 × 10⁻⁸ n\'est pas atteint : absence de preuve, pas preuve d\'absence (dans la démonstration 5, c\'est un vrai variant causal qui manque de puissance).'),
      ],
      commonErrors: [
        'Interpréter un λ élevé comme un signal polygénique sans ajuster sur les composantes principales (ou vérifier l\'intercept de la régression LD score).',
        'Garder doublons et apparentés comme des sujets indépendants.',
        'Utiliser le seuil de 5 % (ou des p non corrigés) pour des milliers de variants.',
        'Tester Hardy-Weinberg chez les cas (une vraie association écarte les cas de l\'équilibre).',
        'Présenter l\'OR par allèle comme un risque relatif dans une étude cas-témoins.',
      ],
      calculatorId: 'genotype_qc',
    ),
    Lesson(
      id: 'polygenic',
      title: 'Polygénie, régression LD score, scores polygéniques et randomisation mendélienne',
      level: Level.advanced,
      body: [
        'La plupart des maladies fréquentes sont polygéniques : des milliers de variants à effet minime. Dans une grande GWAS, les χ² sont alors gonflés même SANS confusion : λ augmente avec l\'effectif et l\'héritabilité. Un λ > 1 ne distingue donc pas à lui seul polygénie et stratification.',
        'Régression LD score : E[χ²] = 1 + N·a + N·h²·ℓ/M, où ℓ est le score LD du variant (somme de ses r² avec ses voisins). Un variant en fort DL capte davantage de signal polygénique, mais pas davantage de confusion : la pente estime h²_SNP, l\'intercept (1 + N·a) la confusion. Ratio = (intercept − 1)/(χ² moyen − 1) = part de l\'inflation due à la confusion.',
        'Conditions : de nombreux variants (≥ 200 000), des scores LD de même ascendance, et pas de contrôle génomique préalable (qui ramène l\'intercept vers 1). Après un modèle mixte LOCO, l\'intercept peut passer sous 1.',
        'Corrélation génétique rg : croiser deux balayages (produit des z signés) donne la covariance génétique ; rg = ρg/√(h²₁·h²₂). L\'intercept croisé absorbe le recouvrement des échantillons. Une corrélation génétique traduit des facteurs partagés (pléiotropie, voie commune), pas une causalité, et elle est instable si l\'un des h² est proche de 0.',
        'Score de risque polygénique : somme des allèles pondérés par leurs effets, après clumping et seuil de p. Effets, seuil et performance doivent venir de trois échantillons distincts : la performance mesurée là où le seuil a été choisi est optimiste. L\'AUC d\'un score est modeste ; il stratifie une population mais n\'est pas un test diagnostique, et il perd beaucoup de performance dans une autre ascendance.',
        'Randomisation mendélienne : des variants associés à une exposition servent d\'instruments répartis au hasard à la conception. Le rapport de Wald βY/βX de chaque variant estime l\'effet causal ; l\'IVW les combine, MR-Egger (intercept = pléiotropie directionnelle) et la médiane pondérée résistent à une part d\'instruments invalides. Conditions : instruments forts (F ≥ 10), aucun effet des variants sur l\'issue autrement que par l\'exposition.',
        'Apparentés : plutôt que de les exclure, un modèle mixte (linéaire pour un trait quantitatif, logistique pour un statut cas-témoins) intègre la matrice de parenté génomique et ramène λ près de 1.',
      ],
      exampleTitle: '20 000 variants simulés (N = 20 000, h² = 0,3)',
      example: 'Sans confusion : χ² moyen ${fmt(pg.clean.meanChi2, digits: 3)}, intercept ${fmt(pg.clean.intercept, digits: 3)} (ES ${fmt(pg.clean.seIntercept, digits: 2)}), h² ${fmt(pg.clean.h2, digits: 2)} — l\'inflation est purement polygénique. Avec une confusion qui ajoute 0,25 à chaque χ² attendu : χ² moyen ${fmt(pg.confounded.meanChi2, digits: 3)}, intercept ${fmt(pg.confounded.intercept, digits: 3)}, h² ${fmt(pg.confounded.h2, digits: 2)}, ratio ${fmt(pg.confounded.ratio, digits: 2)} : l\'intercept capte la confusion, la pente (h²) change à peine. La démonstration 6 montre le même contraste sur des génotypes.',
      exercises: [
        const Exercise.numeric('N = 20 000, h² = 0,25, score LD moyen 80, M = 1 000 000 de variants, sans confusion. χ² moyen attendu (deux décimales) ?', 1.40, 0.006,
            '1 + N·h²·ℓ̄/M = 1 + 20 000 × 0,25 × 80 / 1 000 000 = 1,40 : un λ nettement supérieur à 1 sans aucune confusion.'),
        const Exercise.numeric('Intercept 1,06, χ² moyen 1,30. Ratio (part de l\'inflation due à la confusion, deux décimales) ?', 0.20, 0.006,
            'Ratio = 0,06 / 0,30 = 0,20 : 80 % de l\'inflation est polygénique.'),
        const Exercise.numeric('Un variant augmente le LDL-cholestérol de 0,10 mmol/L par allèle (βX) et le log-odds de maladie coronarienne de 0,03 (βY). Estimation de Wald de l\'effet causal par mmol/L, en log-odds (deux décimales) ?', 0.30, 0.006,
            'βY/βX = 0,03/0,10 = 0,30 log-odds par mmol/L, soit un OR de e^0,30 ≈ 1,35 par mmol/L.'),
        const Exercise.choice('λ = 1,35 et intercept de la régression LD score 1,01 (ES 0,01). Interprétation ?', [
          'Forte stratification : ajuster sur les composantes principales',
          'Inflation expliquée par la polygénie ; pas de confusion détectable',
          'Erreur de génotypage',
        ], 1, 'Un intercept compatible avec 1 signifie que l\'inflation suit le score LD : signal polygénique.'),
        const Exercise.choice('Un score polygénique a un R² de Nagelkerke de 0,25 dans l\'échantillon où le seuil a été choisi et de 0,11 sur un échantillon de test indépendant. Quelle valeur rapporter ?', [
          '0,25 : c\'est la meilleure',
          'La moyenne des deux',
          '0,11 : seul l\'échantillon indépendant donne une performance non biaisée',
        ], 2, 'Choisir le seuil sur un échantillon y surestime la performance (optimisme).'),
        const Exercise.choice('rg = 0,6 entre diabète de type 2 et coronaropathie. Conclusion ?', [
          'Le diabète cause la coronaropathie',
          'Les deux maladies partagent une partie de leurs facteurs génétiques',
          'Ce sont les mêmes patients qui ont les deux maladies',
        ], 1, 'rg mesure des effets génétiques partagés (pléiotropie ou voie commune), pas une causalité ; la randomisation mendélienne traite la causalité.'),
      ],
      commonErrors: [
        'Conclure à une stratification à partir d\'un λ > 1 seul dans une grande GWAS (la polygénie gonfle aussi λ).',
        'Appliquer la régression LD score après un contrôle génomique, ou avec des scores LD d\'une autre ascendance.',
        'Lire une corrélation génétique comme un effet causal.',
        'Rapporter la performance d\'un score polygénique sur l\'échantillon qui a servi à choisir son seuil.',
        'Utiliser un score polygénique comme test diagnostique individuel, ou dans une autre ascendance sans revalidation.',
      ],
      calculatorId: 'ldsc',
    ),
    Lesson(
      id: 'causal_mr',
      title: 'Causalité et randomisation mendélienne',
      level: Level.advanced,
      body: [
        'Une association observationnelle entre une exposition et une maladie peut traduire une confusion ou une causalité inverse. Les allèles sont répartis au hasard à la conception (lois de Mendel) : des variants qui augmentent une exposition jouent le rôle d\'une randomisation naturelle, comme un essai sur la vie entière.',
        'Trois hypothèses font d\'un variant un instrument valide : (1) pertinence — il est associé à l\'exposition (F moyen ≥ 10) ; (2) indépendance — il n\'est pas lié aux facteurs de confusion (même ascendance, pas de stratification) ; (3) restriction d\'exclusion — il n\'agit sur l\'issue que par l\'exposition (pas de pléiotropie horizontale). Seule la première se teste directement.',
        'Estimation : le rapport de Wald βY/βX de chaque variant estime l\'effet causal par unité d\'exposition ; l\'IVW les combine (poids 1/se_Y²). Pour une issue binaire, βY est en log-odds : exp(θ) est un OR par unité d\'exposition.',
        'Les méthodes robustes assouplissent l\'hypothèse d\'exclusion : MR-Egger (valide si les effets pléiotropes sont indépendants de la force des instruments ; son intercept détecte la pléiotropie directionnelle), médiane pondérée (valide si au moins la moitié du poids vient d\'instruments valides), mode pondéré (valide si le plus grand groupe d\'estimations semblables est valide), leave-one-out (aucun variant ne porte seul le résultat). La concordance des méthodes renforce la conclusion.',
        'MR multivariée : quand des variants agissent sur plusieurs expositions liées (LDL, HDL, triglycérides), elle estime l\'effet direct de chacune à niveau égal des autres.',
        'Sens causal : un variant choisi pour l\'exposition peut en réalité agir d\'abord sur l\'issue. Le test de Steiger vérifie que les variants expliquent davantage la variance de l\'exposition que celle de l\'issue ; la MR inverse (issue → exposition) explore le sens opposé.',
        'Interprétation : la MR estime l\'effet d\'une petite différence d\'exposition sur toute la vie, pas celui d\'une intervention brève à l\'âge adulte ; l\'ampleur de l\'effet n\'est pas directement transposable à un médicament.',
      ],
      exampleTitle: 'Données publiées : 28 variants, lipides et maladie coronarienne',
      example: 'LDL-cholestérol : IVW ${fmt(mx.ldl.ivw.estimate, digits: 3)} log-odds par mmol/L (OR ${fmt(math.exp(mx.ldl.ivw.estimate), digits: 3)}), MR-Egger ${fmt(mx.ldl.egger.estimate, digits: 3)}, médiane pondérée ${fmt(mx.ldl.median.estimate, digits: 3)}, intercept d\'Egger p = ${fmt(mx.ldl.eggerIntercept.p, digits: 2)} : méthodes concordantes. HDL-cholestérol : IVW ${fmt(mx.hdl.ivw.estimate, digits: 3)} (apparemment protecteur), mais intercept d\'Egger p = ${fmt(mx.hdl.eggerIntercept.p, digits: 2)} et MR-Egger ${fmt(mx.hdl.egger.estimate, digits: 2)} ; en MR multivariée, l\'effet direct du HDL vaut ${fmt(mx.mv.estimates[1].estimate, digits: 2)} (IC 95 % ${fmt(mx.mv.estimates[1].lower, digits: 2)} à ${fmt(mx.mv.estimates[1].upper, digits: 2)}). La démonstration 7 développe cet exemple.',
      exercises: [
        const Exercise.numeric('Un variant augmente une exposition de βX = 0,20 unité et le log-odds de la maladie de βY = 0,10. OR causal par unité d\'exposition (rapport de Wald, deux décimales) ?', 1.65, 0.006,
            'θ = βY/βX = 0,50 log-odds par unité ; OR = e^0,50 = 1,65.'),
        const Exercise.numeric('βX = 0,05 avec une erreur type de 0,01. Statistique F de cet instrument ?', 25, 0.5,
            'F ≈ (βX/ES)² = 5² = 25 ≥ 10 : instrument assez fort.'),
        const Exercise.numeric('Test de Steiger : un variant a β/ES = 10 dans une étude de l\'exposition de N = 10 000. Part de variance de l\'exposition qu\'il explique, r² en % (deux décimales) ?', 0.99, 0.006,
            'F = 100 ; r² = F/(N − 2 + F) = 100/10 098 = 0,0099, soit 0,99 %. On la compare au r² de l\'issue pour vérifier le sens.'),
        const Exercise.choice('Un variant utilisé comme instrument du LDL augmente aussi la pression artérielle, qui agit sur la maladie. Quelle hypothèse est violée ?', [
          'La pertinence',
          'L\'indépendance vis-à-vis des facteurs de confusion',
          'La restriction d\'exclusion (pléiotropie horizontale)',
        ], 2, 'Le variant atteint l\'issue par une autre voie que l\'exposition : pléiotropie horizontale.'),
        const Exercise.choice('IVW significatif, intercept MR-Egger p = 0,01, pente MR-Egger non significative. Interprétation ?', [
          'Effet causal robuste',
          'Pléiotropie directionnelle probable : l\'IVW est biaisé, ne pas conclure sur lui seul',
          'Instruments faibles',
        ], 1, 'Un intercept non nul signale une pléiotropie directionnelle ; il faut examiner les méthodes robustes.'),
        const Exercise.choice('La médiane pondérée reste valide si…', [
          'tous les instruments sont valides',
          'au moins la moitié du poids vient d\'instruments valides',
          'l\'intercept MR-Egger est nul',
        ], 1, 'La médiane tolère jusqu\'à 50 % du poids venant d\'instruments invalides.'),
      ],
      commonErrors: [
        'Conclure à une causalité sans discuter les hypothèses des instruments (surtout la pléiotropie).',
        'Se fier à l\'IVW seul quand MR-Egger, médiane et mode divergent.',
        'Utiliser des instruments faibles (F < 10) ou des échantillons d\'exposition et d\'issue d\'ascendances différentes.',
        'Transposer l\'effet d\'une exposition génétique à vie à un médicament donné à l\'âge adulte.',
        'Lire l\'effet univarié d\'une exposition corrélée à d\'autres (HDL) comme son effet propre.',
      ],
      calculatorId: 'mendelian_randomization',
    ),
    const Lesson(
      id: 'explanatory_vs_predictive',
      title: 'Modèle explicatif ou modèle prédictif ?',
      level: Level.advanced,
      body: [
        'Explicatif : estimer l\'effet d\'UNE exposition, en contrôlant la confusion. Les covariables viennent d\'un raisonnement causal ; on interprète un coefficient.',
        'Prédictif : estimer au mieux un risque individuel. Les prédicteurs doivent être disponibles au moment de la prédiction ; on juge la discrimination, la calibration et l\'utilité, pas les coefficients.',
        'Un bon prédicteur n\'est pas une cause (un symptôme prédit la maladie) ; une cause peut mal prédire.',
        'Mélanger les deux objectifs conduit à des choix incohérents (sélection pas à pas pour « expliquer », interprétation causale d\'un score).',
      ],
      exampleTitle: 'Tour de taille',
      example: 'Dans un score de risque, le tour de taille améliore la prédiction ; cela ne dit pas qu\'une réduction du tour de taille réduirait le risque d\'autant.',
      exercises: [
        Exercise.choice('Objectif : savoir si le tabagisme augmente le risque d\'HTA. Le critère principal d\'évaluation est…', [
          'l\'AUC du modèle',
          'l\'estimation ajustée de l\'effet du tabac et son IC',
        ], 1, 'Question explicative.'),
      ],
      commonErrors: ['Interpréter les OR d\'un score comme des effets causaux.', 'Juger un modèle explicatif sur son AUC.'],
      calculatorId: 'logistic_regression',
    ),
  ];
}

Lesson? lessonById(List<Lesson> all, String id) {
  for (final l in all) {
    if (l.id == id) return l;
  }
  return null;
}
