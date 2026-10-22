import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import 'calculators.dart';
import 'common.dart';
import 'regression_workshop.dart';

/// Atelier de modèles de prédiction : spécification (TRIPOD+AI), prédicteurs
/// pré-spécifiés, modèle de référence, validation interne par bootstrap.
class PredictionWorkshop extends StatefulWidget {
  final Project? project;
  final OnResult onResult;
  const PredictionWorkshop({super.key, required this.project, required this.onResult});
  @override
  State<PredictionWorkshop> createState() => _PredictionWorkshopState();
}

class _PredictionWorkshopState extends State<PredictionWorkshop> {
  late final PredictionSpec? s0 = widget.project?.predictionSpec;
  late final pop = TextEditingController(text: s0?.targetPopulation ?? widget.project?.question.population ?? '');
  late final horizon = TextEditingController(text: s0?.horizon ?? widget.project?.question.horizon ?? '');
  late final use = TextEditingController(text: s0?.intendedUse ?? '');
  late final setting = TextEditingController(text: s0?.setting ?? '');
  late final refName = TextEditingController(text: s0?.referenceName ?? tr('Modèle de référence', 'Reference model'));
  final boot = TextEditingController(text: '200'), seed = TextEditingController(text: '20261010');
  bool mi = false;
  final miM = TextEditingController(text: '10');
  late String? outcome = s0?.outcome;
  late String? event = s0?.eventLevel;
  late List<TermSpec> terms = [...?s0?.predictors];
  late List<TermSpec> refTerms = [...?s0?.referencePredictors];
  bool busy = false;
  // Issue délai jusqu'à événement (modèle pronostique de Cox).
  bool survival = false;
  String? timeVar, statusVar, statusEvent;
  final horizonNum = TextEditingController();
  String? modelKey; // « idProjet/idEntrée »
  final extPop = TextEditingController();
  final eqJson = TextEditingController();

  /// Modèles développés dans les projets de l'appareil : équation logistique ([ModelEquation])
  /// ou pronostique de Cox ([CoxEquation]).
  List<(String, String, Object)> _models(AppState s) => [
        for (final pr in s.projects)
          for (final e in pr.journal)
            if (e.methodId.startsWith('prediction_logistic_internal'))
              ('${pr.id}/${e.id}', '${pr.title} — ${e.id}', ModelEquation.fromDevelopment(analysisResultFromJson(e.result), name: '${pr.title} (${e.id})'))
            else if (e.methodId == 'prediction_cox_internal')
              ('${pr.id}/${e.id}', '${pr.title} — ${e.id} (Cox)', CoxEquation.fromDevelopment(analysisResultFromJson(e.result), name: '${pr.title} (${e.id})')),
      ];

  static Map<String, Object?> _equationJson(Object eq) => eq is CoxEquation ? eq.toJson() : (eq as ModelEquation).toJson();

  PredictionSpec _spec() => PredictionSpec(
        targetPopulation: pop.text,
        outcome: outcome ?? '',
        eventLevel: event ?? '1',
        horizon: horizon.text,
        intendedUse: use.text,
        setting: setting.text,
        predictors: terms,
        referencePredictors: refTerms,
        referenceName: refName.text,
      );

  /// Sections 1 bis à 3 pour une issue « délai jusqu'à événement » (Cox).
  List<Widget> _survivalSection(BuildContext context, Dataset ds, bool expert) {
    final unit = timeVar == null ? '' : ds.dictionary[timeVar!]!.unit;
    return [
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(tr('Durée de suivi', 'Follow-up time'), timeVar, [for (final n in ds.names) if (ds.dictionary[n]!.type == VarType.numeric) (n, n)],
            (v) => setState(() => timeVar = v)),
        Pick<String>(tr('Statut (événement / censure)', 'Status (event / censoring)'), statusVar,
            [for (final n in ds.names) if (ds.dictionary[n]!.type == VarType.binary || ds.dictionary[n]!.type == VarType.categorical) (n, n)],
            (v) => setState(() {
                  statusVar = v;
                  statusEvent = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
                })),
        if (statusVar != null)
          Pick<String>(tr('Modalité « événement »', 'Event level'), statusEvent, [for (final l in ds.levels(statusVar!)) (l, l)], (v) => setState(() => statusEvent = v)),
        NumField(tr('Horizon (en unités de la durée${unit.isEmpty ? "" : " : $unit"})', 'Horizon (in time units${unit.isEmpty ? "" : ": $unit"})'), horizonNum, width: 220,
            helper: tr('risque prédit à ce temps, dans la plage du suivi', 'risk predicted at this time, within the follow-up range')),
      ]),
      const SizedBox(height: 10),
      Text(tr('2. Développement — prédicteurs pré-spécifiés', '2. Development — pre-specified predictors'), style: Theme.of(context).textTheme.titleSmall),
      PredictorEditor(ds, terms, (l) => setState(() => terms = l), exclude: {?timeVar, ?statusVar}),
      const SizedBox(height: 10),
      Text(tr('3. Validation interne', '3. Internal validation'), style: Theme.of(context).textTheme.titleSmall),
      Text(tr('Analyse en cas complets (imputation multiple non proposée pour le modèle de Cox en V1).', 'Complete-case analysis (multiple imputation not offered for the Cox model in V1).'),
          style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 12, runSpacing: 12, children: [
        NumField(tr('Répliques bootstrap', 'Bootstrap replicates'), boot, width: 160),
        if (expert) NumField(tr('Graine', 'Seed'), seed, width: 160, helper: tr('reproductibilité', 'reproducibility')),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
        label: Text(busy ? tr('Calcul en cours…', 'Computing…') : tr('Développer et valider (bootstrap)', 'Develop and validate (bootstrap)')),
        onPressed: busy
            ? null
            : () async {
                final h = readNum(horizonNum);
                if (timeVar == null || statusVar == null || statusEvent == null || terms.isEmpty || h == null) {
                  showError(context, tr("Choisir la durée, le statut et sa modalité « événement », l'horizon et au moins un prédicteur.",
                      'Choose the time, the status and its event level, the horizon and at least one predictor.'));
                  return;
                }
                setState(() => busy = true);
                final b = (readInt(boot) ?? 200).clamp(20, 2000), sd = readInt(seed) ?? 20261011;
                try {
                  final json = await compute(_developCox, (
                    ds.toJson(),
                    (timeVar!, statusVar!, statusEvent!, unit, pop.text, use.text),
                    [for (final t in terms) t.toJson()],
                    h,
                    b,
                    sd,
                    currentLang,
                  ));
                  if (!context.mounted) return;
                  widget.onResult(analysisResultFromJson(json), options: {'bootstrap': b, 'seed': sd, 'horizon': h});
                } on StatInputError catch (e) {
                  if (context.mounted) showError(context, e);
                } catch (e) {
                  if (context.mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final ds = p?.dataset;
    final expert = context.watch<AppState>().expertMode;
    if (ds == null) {
      return Text(tr('L\'atelier de prédiction travaille sur des données individuelles : importez-les à l\'étape 4 d\'un projet.', 'The prediction workshop works on individual data: import them in step 4 of a project.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Atelier de modèles de prédiction', 'Prediction model workshop'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(tr('Issue binaire (logistique)', 'Binary outcome (logistic)'))),
          ButtonSegment(value: true, label: Text(tr('Délai avec censure (Cox)', 'Censored time (Cox)'))),
        ],
        selected: {survival},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => survival = v.first),
      ),
      const SizedBox(height: 4),
      Text(tr('Étapes séparées : (1) spécification, (2) développement, (3) validation interne par bootstrap. La validation externe se fait plus bas, sur d\'autres données : aucun modèle n\'est déclaré « validé ».', 'Separate steps: (1) specification, (2) development, (3) internal validation by bootstrap. External validation is done below, on other data: no model is declared "validated".')),
      const SizedBox(height: 10),
      Text(tr('1. Spécification', '1. Specification'), style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      TextField(controller: pop, decoration: InputDecoration(labelText: tr('Population cible', 'Target population'))),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 200, child: TextField(controller: horizon, decoration: InputDecoration(labelText: tr('Horizon de prédiction', 'Prediction horizon')))),
        SizedBox(width: 380, child: TextField(controller: use, decoration: InputDecoration(labelText: tr('Usage prévu (décision éclairée par le modèle)', 'Intended use (decision informed by the model)')))),
        SizedBox(width: 220, child: TextField(controller: setting, decoration: InputDecoration(labelText: tr('Contexte de soins', 'Care setting')))),
      ]),
      const SizedBox(height: 10),
      if (survival) ..._survivalSection(context, ds, expert) else ...[
      Wrap(spacing: 12, runSpacing: 12, children: [
        Pick<String>(tr('Issue (binaire)', 'Outcome (binary)'), outcome, [for (final n in ds.names) if (ds.dictionary[n]!.type == VarType.binary) (n, n)], (v) => setState(() {
              outcome = v;
              event = v == null ? null : (ds.levels(v).contains('1') ? '1' : null);
            })),
        if (outcome != null) Pick<String>(tr('Modalité « événement »', 'Event level'), event, [for (final l in ds.levels(outcome!)) (l, l)], (v) => setState(() => event = v)),
      ]),
      const SizedBox(height: 10),
      Text(tr('2. Développement — prédicteurs pré-spécifiés', '2. Development — pre-specified predictors'), style: Theme.of(context).textTheme.titleSmall),
      Text(tr('Choisissez les prédicteurs AVANT l\'analyse, sur des bases cliniques, parmi ceux disponibles au moment de la prédiction. Aucune sélection automatique n\'est proposée (source de surajustement et de fuite d\'information).', 'Choose the predictors BEFORE the analysis, on clinical grounds, among those available at the time of prediction. No automatic selection is offered (a source of overfitting and information leakage).')),
      PredictorEditor(ds, terms, (l) => setState(() => terms = l), exclude: {?outcome}),
      const SizedBox(height: 8),
      PredictorEditor(ds, refTerms, (l) => setState(() => refTerms = l), exclude: {?outcome}, title: tr('Modèle de référence (comparaison, facultatif)', 'Reference model (comparison, optional)')),
      if (refTerms.isNotEmpty) SizedBox(width: 280, child: TextField(controller: refName, decoration: InputDecoration(labelText: tr('Nom du modèle de référence', 'Name of the reference model')))),
      const SizedBox(height: 10),
      Text(tr('3. Validation interne', '3. Internal validation'), style: Theme.of(context).textTheme.titleSmall),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Imputer les prédicteurs manquants (imputation multiple, refaite dans chaque réplique bootstrap)', 'Impute missing predictors (multiple imputation, redone in each bootstrap replicate)')),
        subtitle: Text(tr('Sinon : analyse en cas complets. L\'issue n\'est jamais imputée. Calcul plus long.', 'Otherwise: complete-case analysis. The outcome is never imputed. Longer computation.')),
        value: mi,
        onChanged: (v) => setState(() {
          mi = v;
          if (v && (readInt(boot) ?? 200) > 100) boot.text = '100';
        }),
      ),
      Wrap(spacing: 12, runSpacing: 12, children: [
        NumField(tr('Répliques bootstrap', 'Bootstrap replicates'), boot, width: 160),
        if (mi) NumField(tr('Imputations m', 'Imputations m'), miM, width: 140),
        if (expert) NumField(tr('Graine', 'Seed'), seed, width: 160, helper: tr('reproductibilité', 'reproducibility')),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
        label: Text(busy ? tr('Calcul en cours…', 'Computing…') : tr('Développer et valider (bootstrap)', 'Develop and validate (bootstrap)')),
        onPressed: busy
            ? null
            : () async {
                final spec = _spec();
                p!.predictionSpec = spec;
                context.read<AppState>().saveSoon(p);
                if (outcome == null || terms.isEmpty) {
                  showError(context, tr('Choisir l\'issue et au moins un prédicteur.', 'Choose the outcome and at least one predictor.'));
                  return;
                }
                setState(() => busy = true);
                final b = (readInt(boot) ?? 200).clamp(20, 2000), sd = readInt(seed) ?? 20261010;
                try {
                  final json = mi
                      ? await compute(_developMI, (p.dataset!.toJson(), spec.toJson(), b, sd, (readInt(miM) ?? 10).clamp(2, 100), currentLang))
                      : await compute(_develop, (p.dataset!.toJson(), spec.toJson(), b, sd, currentLang));
                  if (!context.mounted) return;
                  widget.onResult(analysisResultFromJson(json), options: {'bootstrap': b, 'seed': sd});
                } on StatInputError catch (e) {
                  if (context.mounted) showError(context, e);
                } catch (e) {
                  if (context.mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
      ),
      ],
      const SizedBox(height: 8),
      Text(tr('Grilles TRIPOD+AI (rédaction) et PROBAST+AI (risque de biais) : étape 8 « Interprétation ».', 'TRIPOD+AI (reporting) and PROBAST+AI (risk of bias) grids: step 8 "Interpretation".'), style: Theme.of(context).textTheme.bodySmall),
      const Divider(height: 32),
      Text(tr('Validation externe d\'un modèle existant', 'External validation of an existing model'), style: Theme.of(context).textTheme.titleSmall),
      Text(tr('Les données de CE projet servent de population de validation. L\'équation choisie est appliquée telle quelle (coefficients non réestimés) ; les prédicteurs doivent porter les mêmes noms, modalités et références.', 'The data of THIS project serve as the validation population. The chosen equation is applied as is (coefficients not re-estimated); the predictors must have the same names, levels and references.')),
      const SizedBox(height: 8),
      Builder(builder: (context) {
        final models = _models(context.watch<AppState>());
        return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Pick<String>(tr('Modèle développé dans Statoméa', 'Model developed in Statoméa'), modelKey, [for (final m in models) (m.$1, m.$2)], (v) => setState(() => modelKey = v), width: 380),
          if (modelKey != null && expert)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(tr('Copier l\'équation (JSON)', 'Copy the equation (JSON)')),
              onPressed: () {
                final m = models.firstWhere((m) => m.$1 == modelKey);
                Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_equationJson(m.$3))));
              },
            ),
        ]);
      }),
      ExpertHint(tr('graine des tirages, équation du modèle', 'random seed, model equation')),
      if (expert) ...[
        const SizedBox(height: 8),
        TextField(
          controller: eqJson,
          minLines: 2,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(labelText: tr('ou équation publiée au format JSON (prioritaire si renseignée)', 'or published equation in JSON format (takes priority if filled in)'), alignLabelWithHint: true),
        ),
      ],
      const SizedBox(height: 8),
      TextField(controller: extPop, decoration: InputDecoration(labelText: tr('Population de validation (lieu, période, critères)', 'Validation population (place, period, criteria)'))),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(tr('Valider le modèle sur les données de ce projet', 'Validate the model on the data of this project')),
        onPressed: () => run(context, () {
          Object eq;
          if (eqJson.text.trim().isNotEmpty) {
            try {
              final j = (jsonDecode(eqJson.text) as Map).cast<String, Object?>();
              eq = j['kind'] == 'cox' ? CoxEquation.fromJson(j) : ModelEquation.fromJson(j);
            } catch (e) {
              throw StatInputError('equation_json', tr('Équation JSON illisible : $e', 'Unreadable JSON equation: $e'));
            }
          } else {
            final models = _models(context.read<AppState>());
            if (modelKey == null) throw StatInputError('missing', tr('Choisir un modèle ou coller une équation.', 'Choose a model or paste an equation.'));
            eq = models.firstWhere((m) => m.$1 == modelKey).$3;
          }
          return eq is CoxEquation ? externalValidationCox(ds, eq, population: extPop.text) : externalValidation(ds, eq as ModelEquation, population: extPop.text);
        }, widget.onResult, options: {'model': modelKey ?? 'json'}),
      ),
    ]);
  }
}

// Les isolats ne partagent pas la langue courante : elle est transmise avec les données.
Map<String, Object?> _develop((Map<String, Object?>, Map<String, Object?>, int, int, Lang) a) {
  setLang(a.$5);
  final r = developPredictionModel(Dataset.fromJson(a.$1), PredictionSpec.fromJson(a.$2), bootstrap: a.$3, seed: a.$4);
  return sanitizeJson(r.toJson()) as Map<String, Object?>;
}

Map<String, Object?> _developMI((Map<String, Object?>, Map<String, Object?>, int, int, int, Lang) a) {
  setLang(a.$6);
  final r = developPredictionModelMI(Dataset.fromJson(a.$1), PredictionSpec.fromJson(a.$2), bootstrap: a.$3, seed: a.$4, m: a.$5);
  return sanitizeJson(r.toJson()) as Map<String, Object?>;
}

// Calcul en isolat : la langue courante est transmise avec les données.
Map<String, Object?> _developCox(
    (Map<String, Object?>, (String, String, String, String, String, String), List<Map<String, Object?>>, double, int, int, Lang) a) {
  setLang(a.$7);
  final (time, status, event, unit, pop, use) = a.$2;
  final s = buildSurvivalDesign(Dataset.fromJson(a.$1), time, status, event, [for (final t in a.$3) TermSpec.fromJson(t)]);
  final r = developCoxPredictionModel(s, horizon: a.$4, bootstrap: a.$5, seed: a.$6, targetPopulation: pop, intendedUse: use, timeUnit: unit);
  return sanitizeJson(r.toJson()) as Map<String, Object?>;
}
