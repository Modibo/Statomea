import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:statomea_core/statomea_core.dart' hide Step;

import '../state/app_state.dart';
import 'calculators.dart';
import 'common.dart';

/// Nombre maximal de variants soumis au balayage (temps de calcul sur téléphone).
const maxScanVariants = 50000;

typedef _QcArgs = (Map<String, Uint8List>, (double, double, double, double, double), Lang);
typedef _QcOut = (Map<String, Object?>, GenotypeData);

_QcOut _runQc(_QcArgs a) {
  setLang(a.$3);
  final o = a.$2;
  final data = readGenotypeFiles(a.$1);
  final qc = genotypeQc(data, options: GenotypeQcOptions(minSampleCallRate: o.$1, hetSd: o.$2, minVariantCallRate: o.$3, minMaf: o.$4, hweP: o.$5));
  return (sanitizeJson(qc.result.toJson()) as Map<String, Object?>, qc.cleaned);
}

typedef _PcaOut = (Map<String, Object?>, Map<String, Map<String, String>>);

_PcaOut _runPca((GenotypeData, Lang) a) {
  setLang(a.$2);
  final pca = genotypePca(a.$1);
  return (sanitizeJson(pca.result.toJson()) as Map<String, Object?>, pca.covariates(10));
}

typedef _KinOut = (Map<String, Object?>, List<int>);

_KinOut _runKinship((GenotypeData, Lang) a) {
  setLang(a.$2);
  final k = genotypeKinship(a.$1);
  return (sanitizeJson(k.result.toJson()) as Map<String, Object?>, k.removed);
}

typedef _LmmArgs = (GenotypeData, List<double?>, List<(String, List<String?>, bool, String?)>, String, Lang, bool);

/// Résultat d'un balayage et z signés par variant (alignés sur les variants ; null = non testé), pour la régression
/// LD score (χ² = z²) et la corrélation génétique, avec l'effectif analysé.
typedef _ScanOut = (Map<String, Object?>, List<double?>, int);

_ScanOut _runLmm(_LmmArgs a) {
  setLang(a.$5);
  final g = a.$1;
  final r = lmmScan(g, a.$2,
      covariates: [for (final (name, values, cat, ref) in a.$3) LmmCovariate(name, values, categorical: cat, reference: ref)],
      grmVariants: ldPrune(g), outcomeName: a.$4, positions: {for (final v in g.variants) v.label: (v.chrom, v.pos)}, loco: a.$6);
  // z signé = signe(β)·√F (F à 1 ddl au numérateur).
  final z = {for (var k = 0; k < r.variants.length; k++) r.variants[k]: (r.beta[k] < 0 ? -1 : 1) * math.sqrt(r.f[k])};
  return (sanitizeJson(r.result.toJson()) as Map<String, Object?>, [for (final v in g.variants) z[v.label]], (r.result.inputs['samples'] as num).toInt());
}

_ScanOut _runGlmm(_LmmArgs a) {
  setLang(a.$5);
  final g = a.$1;
  final r = glmmScan(g, a.$2,
      covariates: [for (final (name, values, cat, ref) in a.$3) LmmCovariate(name, values, categorical: cat, reference: ref)],
      grmVariants: ldPrune(g), outcomeName: a.$4, positions: {for (final v in g.variants) v.label: (v.chrom, v.pos)});
  // z signé = U/√V (test du score).
  final z = {for (var k = 0; k < r.variants.length; k++) r.variants[k]: r.score[k] / math.sqrt(r.variance[k])};
  return (sanitizeJson(r.result.toJson()) as Map<String, Object?>, [for (final v in g.variants) z[v.label]], (r.result.inputs['samples'] as num).toInt());
}

typedef _ScanArgs = (GenotypeData, Map<String, Map<String, String>>, String, String, List<(String, bool, String?)>, PAdjust, Lang);

_ScanOut _runScan(_ScanArgs a) {
  setLang(a.$7);
  final ds = genotypeDataset(a.$1, covariates: a.$2);
  // Les colonnes de variants sont les dernières de la table (noms rendus uniques par genotypeDataset).
  final names = ds.names.sublist(ds.names.length - a.$1.variantCount);
  final z = <double>[];
  final r = snpScan(ds, names, a.$3, a.$4,
      positions: {for (var j = 0; j < names.length; j++) names[j]: (a.$1.variants[j].chrom, a.$1.variants[j].pos)},
      covariates: [for (final (name, cat, ref) in a.$5) TermSpec(name, categorical: cat, reference: ref)], correction: a.$6, zOut: z);
  final n = ds.text(a.$3).where((v) => v != null).length;
  return (sanitizeJson(r.toJson()) as Map<String, Object?>, z, n);
}

typedef _LdscArgs = (GenotypeData, List<double?>, int, String, Lang);

Map<String, Object?> _runLdsc(_LdscArgs a) {
  setLang(a.$5);
  return sanitizeJson(ldscFromScan(a.$1, [for (final z in a.$2) z == null ? null : z * z], n: a.$3, scanName: a.$4).result.toJson()) as Map<String, Object?>;
}

typedef _PrsArgs = (GenotypeData, List<double?>, String, Lang, List<(String, List<String?>, bool, String?)>);

Map<String, Object?> _runPrs(_PrsArgs a) {
  setLang(a.$4);
  return sanitizeJson(polygenicRiskScore(a.$1, a.$2, outcomeName: a.$3,
          covariates: [for (final (name, values, cat, ref) in a.$5) LmmCovariate(name, values, categorical: cat, reference: ref)])
      .result
      .toJson()) as Map<String, Object?>;
}

typedef _RgArgs = (GenotypeData, List<double?>, List<double?>, int, String, String, Lang);

Map<String, Object?> _runRg(_RgArgs a) {
  setLang(a.$7);
  return sanitizeJson(geneticCorrelationFromScans(a.$1, a.$2, a.$3, n: a.$4, trait1: a.$5, trait2: a.$6).result.toJson()) as Map<String, Object?>;
}

/// Décompression des .gz (pur Dart, aussi sur le web) ; le nom perd son suffixe .gz.
MapEntry<String, Uint8List> decompressIfNeeded(String name, Uint8List bytes) =>
    name.toLowerCase().endsWith('.gz') ? MapEntry(name.substring(0, name.length - 3), const GZipDecoder().decodeBytes(bytes)) : MapEntry(name, bytes);

/// Import de génotypes (VCF, VCF.GZ, PLINK texte ou binaire), contrôle de qualité, puis balayage des variants retenus.
class GenotypeImportTool extends StatefulWidget {
  final OnResult onResult;
  const GenotypeImportTool(this.onResult, {super.key});
  @override
  State<GenotypeImportTool> createState() => GenotypeImportToolState();
}

class GenotypeImportToolState extends State<GenotypeImportTool> {
  final files = <String, Uint8List>{};
  Dataset? covariateTable;
  String covariateName = '';
  Map<String, Map<String, String>> pcCovs = const {};
  List<int>? relatedRemoved;
  bool excludeRelated = true;

  /// Modèle mixte : garde tous les sujets contrôlés (apparentés compris) et accepte une issue quantitative.
  bool mixed = false;
  bool loco = false;

  /// Modèle mixte et issue binaire : modèle logistique (GMMAT) plutôt que linéaire (EMMAX).
  bool logisticMixed = true;

  /// Dernier balayage (données, z signés par variant, effectif, libellé) : base de la régression LD score.
  (GenotypeData, List<double?>, int, String)? lastScan;

  /// z signés du dernier balayage de chaque issue (ordre d'exécution ; mêmes données) : base de la corrélation génétique.
  final scansByTrait = <String, (List<double?>, int)>{};

  void _recordScan(GenotypeData g, List<double?> z, int n, String label) {
    lastScan = (g, z, n, label);
    scansByTrait
      ..remove(outcome)
      ..[outcome!] = (z, n);
  }
  GenotypeData? get scanData => mixed ? cleaned : analysisData;

  /// Données d'analyse : génotypes contrôlés, sans les apparentés si l'utilisateur les écarte. Mises en cache
  /// (recalculées seulement après le contrôle de qualité, l'apparentement ou le choix d'exclusion).
  GenotypeData? analysisData;

  void _refreshAnalysis() {
    lastScan = null;
    scansByTrait.clear();
    final g = cleaned, r = relatedRemoved;
    final drop = r == null ? const <int>{} : r.toSet();
    analysisData = g == null || drop.isEmpty || !excludeRelated
        ? g
        : g.subset(sampleIdx: [for (var i = 0; i < g.sampleCount; i++) if (!drop.contains(i)) i],
            notes: [tr('${drop.length} sujet(s) apparenté(s) écarté(s).', '${drop.length} related subject(s) removed.')]);
  }
  GenotypeData? cleaned;
  bool busy = false;
  final minSampleCall = TextEditingController(text: '0,95'), hetSd = TextEditingController(text: '3'), minVarCall = TextEditingController(text: '0,95'),
      minMaf = TextEditingController(text: '0,01'), hweP = TextEditingController(text: '1e-6');
  String? outcome, caseLevel;
  final covs = <String>{};
  PAdjust correction = PAdjust.bh;

  /// Ajoute des fichiers (les .gz sont décompressés) ; utilisé par le sélecteur et par les tests.
  void loadFiles(Map<String, Uint8List> picked) {
    try {
      setState(() {
        for (final e in picked.entries) {
          final f = decompressIfNeeded(e.key, e.value);
          files[f.key] = f.value;
        }
        cleaned = null;
        relatedRemoved = null;
        _refreshAnalysis();
      });
    } catch (e) {
      showError(context, tr('Fichier compressé illisible : $e', 'Unreadable compressed file: $e'));
    }
  }

  /// Covariables : CSV dont la 1re colonne est l'identifiant du sujet.
  void loadCovariates(String csv, String name) {
    final ds = parseCsv(csv, source: name).dataset;
    if (ds.names.length < 2) {
      showError(context, tr('Le fichier de covariables doit contenir l\'identifiant puis au moins une colonne.', 'The covariate file must contain the identifier and at least one column.'));
      return;
    }
    setState(() {
      covariateTable = ds;
      covariateName = name;
    });
  }

  Map<String, Map<String, String>> get covariateMap {
    final ds = covariateTable;
    final id = ds?.names.first;
    return {
      if (ds != null)
        for (final c in ds.names.skip(1))
          c: {for (var i = 0; i < ds.rowCount; i++) if (ds.cell(i, id!) != null && ds.cell(i, c) != null) ds.cell(i, id)!: ds.cell(i, c)!},
      ...pcCovs,
    };
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['vcf', 'gz', 'ped', 'map', 'bed', 'bim', 'fam']);
    if (picked.isEmpty) return;
    loadFiles({for (final f in picked) f.name: await f.xFile.readAsBytes()});
  }

  Future<void> _pickCovariates() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt', 'tsv']);
    if (picked.isEmpty) return;
    loadCovariates(utf8.decode(await picked.single.xFile.readAsBytes(), allowMalformed: true), picked.single.name);
  }

  Future<void> loadFamilyExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_familles_simule.bed'), bim = await b('genotypes_familles_simule.bim'), fam = await b('genotypes_familles_simule.fam');
    final cov = await rootBundle.loadString('assets/demos/genotypes_familles_phenotypes.csv');
    setState(files.clear);
    loadFiles({'genotypes_familles_simule.bed': bed, 'genotypes_familles_simule.bim': bim, 'genotypes_familles_simule.fam': fam});
    loadCovariates(cov, 'genotypes_familles_phenotypes.csv');
    setState(() => mixed = true);
  }

  /// Exemple pour la régression LD score : variants en blocs de DL, deux sous-populations, statut cas/témoin confondu ;
  /// deux maladies génétiquement corrélées (diabète, coronaropathie) pour la corrélation génétique.
  Future<void> loadLdExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_dl_simule.bed'), bim = await b('genotypes_dl_simule.bim'), fam = await b('genotypes_dl_simule.fam');
    setState(() {
      files.clear();
      covariateTable = null;
      covariateName = '';
      mixed = false;
    });
    loadFiles({'genotypes_dl_simule.bed': bed, 'genotypes_dl_simule.bim': bim, 'genotypes_dl_simule.fam': fam});
    loadCovariates(await rootBundle.loadString('assets/demos/genotypes_dl_traits.csv'), 'genotypes_dl_traits.csv');
  }

  /// Exemple pour le score polygénique : 3 000 sujets, 3 000 variants en blocs de DL, une population, maladie à 30 %.
  Future<void> loadPrsExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_prs_simule.bed'), bim = await b('genotypes_prs_simule.bim'), fam = await b('genotypes_prs_simule.fam');
    setState(() {
      files.clear();
      covariateTable = null;
      covariateName = '';
      mixed = false;
    });
    loadFiles({'genotypes_prs_simule.bed': bed, 'genotypes_prs_simule.bim': bim, 'genotypes_prs_simule.fam': fam});
    loadCovariates(await rootBundle.loadString('assets/demos/genotypes_prs_covariables.csv'), 'genotypes_prs_covariables.csv');
  }

  Future<void> loadRelatedExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_parente_simule.bed'), bim = await b('genotypes_parente_simule.bim'), fam = await b('genotypes_parente_simule.fam');
    setState(() {
      files.clear();
      covariateTable = null;
      covariateName = '';
    });
    loadFiles({'genotypes_parente_simule.bed': bed, 'genotypes_parente_simule.bim': bim, 'genotypes_parente_simule.fam': fam});
  }

  Future<void> loadStratifiedExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_strat_simule.bed'), bim = await b('genotypes_strat_simule.bim'), fam = await b('genotypes_strat_simule.fam');
    setState(() {
      files.clear();
      covariateTable = null;
      covariateName = '';
    });
    loadFiles({'genotypes_strat_simule.bed': bed, 'genotypes_strat_simule.bim': bim, 'genotypes_strat_simule.fam': fam});
  }

  Future<void> loadExample() async {
    Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
    final bed = await b('genotypes_simule.bed'), bim = await b('genotypes_simule.bim'), fam = await b('genotypes_simule.fam');
    final cov = await rootBundle.loadString('assets/demos/genotypes_simule_covariables.csv');
    setState(files.clear);
    loadFiles({'genotypes_simule.bed': bed, 'genotypes_simule.bim': bim, 'genotypes_simule.fam': fam});
    loadCovariates(cov, 'genotypes_simule_covariables.csv');
  }

  Future<void> runQc() async {
    setState(() => busy = true);
    try {
      final opts = ((readNum(minSampleCall) ?? 0.95).clamp(0, 1).toDouble(), readNum(hetSd) ?? 3, (readNum(minVarCall) ?? 0.95).clamp(0, 1).toDouble(),
          (readNum(minMaf) ?? 0.01).clamp(0, 0.5).toDouble(), readNum(hweP) ?? 1e-6);
      final (json, data) = await compute(_runQc, (Map<String, Uint8List>.of(files), opts, currentLang));
      if (!mounted) return;
      setState(() {
        cleaned = data;
        pcCovs = const {};
        relatedRemoved = null;
        _refreshAnalysis();
        outcome = data.phenotype.any((p) => p != null) ? tr('statut', 'status') : null;
        caseLevel = outcome == null ? null : tr('cas', 'case');
        covs
          ..clear()
          ..addAll([if (data.sex.any((s) => s != null)) tr('sexe', 'sex')]);
      });
      widget.onResult(analysisResultFromJson(json), options: {'files': files.keys.toList()});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Lecture impossible : $e', 'Reading impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> runKinship() async {
    final g = cleaned;
    if (g == null) return;
    setState(() => busy = true);
    try {
      final (json, removed) = await compute(_runKinship, (g, currentLang));
      if (!mounted) return;
      setState(() {
        relatedRemoved = removed;
        pcCovs = const {};
        covs.removeWhere((c) => c.startsWith('PC'));
        _refreshAnalysis();
      });
      widget.onResult(analysisResultFromJson(json));
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> runPca() async {
    final g = scanData;
    if (g == null) return;
    setState(() => busy = true);
    try {
      final (json, covs0) = await compute(_runPca, (g, currentLang));
      if (!mounted) return;
      setState(() {
        pcCovs = covs0;
        covs.addAll(['PC1', 'PC2']);
      });
      widget.onResult(analysisResultFromJson(json), options: {'components': covs0.length});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> runScan() async {
    final g = scanData;
    if (g == null || outcome == null || (caseLevel == null && !mixed)) {
      showError(context, tr('Choisir le statut et la modalité « cas ».', 'Choose the status and the case level.'));
      return;
    }
    if (g.variantCount > maxScanVariants) {
      showError(context, tr('${g.variantCount} variants : au-delà de $maxScanVariants, utiliser PLINK ou REGENIE (calcul trop long sur l\'appareil).',
          '${g.variantCount} variants: beyond $maxScanVariants, use PLINK or REGENIE (computation too long on the device).'));
      return;
    }
    setState(() => busy = true);
    try {
      final table = genotypeDataset(g.subset(variantIdx: const []), covariates: covariateMap);
      if (mixed) {
        final numeric = table.dictionary[outcome!]!.type == VarType.numeric;
        final raw = table.text(outcome!);
        final y = [for (final v in raw) v == null ? null : (numeric ? parseNumber(v) : (v == caseLevel ? 1.0 : 0.0))];
        final cv = [
          for (final c in covs)
            (c, table.text(c), table.dictionary[c]!.type != VarType.numeric, table.dictionary[c]!.type != VarType.numeric ? table.levels(c).first : null)
        ];
        final logistic = !numeric && logisticMixed;
        final (json, z, n) = await compute(logistic ? _runGlmm : _runLmm, (g, y, cv, outcome!, currentLang, loco));
        if (!mounted) return;
        setState(() => _recordScan(g, z, n,
            logistic ? tr('le modèle mixte logistique', 'the logistic mixed model') : (loco ? tr('le modèle mixte LOCO', 'the LOCO mixed model') : tr('le modèle mixte', 'the mixed model'))));
        widget.onResult(analysisResultFromJson(json), options: {'model': 'lmm', 'variants': g.variantCount, 'covariates': covs.toList()});
        return;
      }
      final terms = [
        for (final c in covs)
          (c, table.dictionary[c]!.type != VarType.numeric, table.dictionary[c]!.type != VarType.numeric ? table.levels(c).first : null)
      ];
      final (json, z, n) = await compute(_runScan, (g, covariateMap, outcome!, caseLevel!, terms, correction, currentLang));
      if (!mounted) return;
      setState(() => _recordScan(g, z, n, covs.isEmpty
          ? tr('le balayage logistique non ajusté', 'the unadjusted logistic scan')
          : tr('le balayage logistique ajusté sur ${covs.join(', ')}', 'the logistic scan adjusted for ${covs.join(', ')}')));
      widget.onResult(analysisResultFromJson(json), options: {'variants': g.variantCount, 'covariates': covs.toList()});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> runLdsc() async {
    final s = lastScan;
    if (s == null) return;
    setState(() => busy = true);
    try {
      final json = await compute(_runLdsc, (s.$1, s.$2, s.$3, s.$4, currentLang));
      if (!mounted) return;
      widget.onResult(analysisResultFromJson(json), options: {'scan': s.$4});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Score de risque polygénique sur l'issue binaire choisie (découverte, validation et test selon l'ordre du fichier).
  Future<void> runPrs() async {
    final g = scanData;
    if (g == null || outcome == null) return;
    final table = genotypeDataset(g.subset(variantIdx: const []), covariates: covariateMap);
    if (table.levels(outcome!).length != 2) {
      showError(context, tr('Le score polygénique demande une issue binaire.', 'The polygenic score requires a binary outcome.'));
      return;
    }
    final level = caseLevel ?? table.levels(outcome!).last;
    final y = [for (final v in table.text(outcome!)) v == null ? null : (v == level ? 1.0 : 0.0)];
    final cv = [
      for (final c in covs)
        (c, table.text(c), table.dictionary[c]!.type != VarType.numeric, table.dictionary[c]!.type != VarType.numeric ? table.levels(c).first : null)
    ];
    setState(() => busy = true);
    try {
      final json = await compute(_runPrs, (g, y, outcome!, currentLang, cv));
      if (!mounted) return;
      widget.onResult(analysisResultFromJson(json), options: {'outcome': outcome, 'caseLevel': level});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Corrélation génétique entre les deux dernières issues balayées (mêmes génotypes, même allèle compté).
  Future<void> runRg() async {
    final s = lastScan;
    if (s == null || scansByTrait.length < 2) return;
    final keys = scansByTrait.keys.toList();
    final t1 = keys[keys.length - 2], t2 = keys.last;
    final a = scansByTrait[t1]!, b = scansByTrait[t2]!;
    setState(() => busy = true);
    try {
      final json = await compute(_runRg, (s.$1, a.$1, b.$1, math.min(a.$2, b.$2), t1, t2, currentLang));
      if (!mounted) return;
      widget.onResult(analysisResultFromJson(json), options: {'traits': [t1, t2]});
    } on StatInputError catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, tr('Calcul impossible : $e', 'Computation impossible: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expert = context.watch<AppState>().expertMode;
    final g = scanData;
    final table = g == null ? null : genotypeDataset(g.subset(variantIdx: const []), covariates: covariateMap);
    final outcomes = table == null
        ? const <String>[]
        : [for (final n in table.names.skip(1)) if (table.levels(n).length == 2 || (mixed && table.dictionary[n]!.type == VarType.numeric && !n.startsWith('PC'))) n];
    final outcomeNumeric = table != null && outcome != null && table.names.contains(outcome) && table.dictionary[outcome!]!.type == VarType.numeric;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Banner2(Severity.info,
          tr('Formats : VCF (ou .vcf.gz), PLINK texte (.ped + .map) ou binaire (.bed + .bim + .fam). Lecture et calculs sur l\'appareil.',
              'Formats: VCF (or .vcf.gz), text PLINK (.ped + .map) or binary PLINK (.bed + .bim + .fam). Reading and computation on the device.')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.upload_file), label: Text(tr('Choisir les fichiers', 'Choose the files')), onPressed: _pick),
        OutlinedButton.icon(icon: const Icon(Icons.table_view_outlined), label: Text(tr('Covariables (CSV, 1re colonne = identifiant)', 'Covariates (CSV, 1st column = identifier)')),
            onPressed: _pickCovariates),
        OutlinedButton.icon(icon: const Icon(Icons.science_outlined), label: Text(tr('Exemple simulé (300 sujets, 250 variants)', 'Simulated example (300 subjects, 250 variants)')),
            onPressed: loadExample),
        OutlinedButton.icon(icon: const Icon(Icons.diversity_3_outlined), label: Text(tr('Exemple avec stratification (2 populations, 400 sujets)', 'Example with stratification (2 populations, 400 subjects)')),
            onPressed: loadStratifiedExample),
        OutlinedButton.icon(icon: const Icon(Icons.family_restroom), label: Text(tr('Exemple avec apparentés (230 sujets, 20 000 variants)', 'Example with relatives (230 subjects, 20,000 variants)')),
            onPressed: loadRelatedExample),
        OutlinedButton.icon(icon: const Icon(Icons.groups_outlined), label: Text(tr('Exemple familial, trait quantitatif (600 sujets)', 'Family example, quantitative trait (600 subjects)')),
            onPressed: loadFamilyExample),
        OutlinedButton.icon(icon: const Icon(Icons.stacked_line_chart), label: Text(tr('Exemple en blocs de DL (1 000 sujets, 3 000 variants)', 'LD-block example (1,000 subjects, 3,000 variants)')),
            onPressed: loadLdExample),
        OutlinedButton.icon(icon: const Icon(Icons.functions), label: Text(tr('Exemple pour score polygénique (3 000 sujets)', 'Polygenic score example (3,000 subjects)')),
            onPressed: loadPrsExample),
        if (files.isNotEmpty) TextButton(onPressed: () => setState(() {
              files.clear();
              cleaned = null;
              relatedRemoved = null;
              _refreshAnalysis();
            }), child: Text(tr('Vider', 'Clear'))),
      ]),
      if (files.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Fichiers : ${files.keys.join(', ')}', 'Files: ${files.keys.join(', ')}'), style: Theme.of(context).textTheme.bodySmall)),
      if (covariateTable != null)
        Text(tr('Covariables : $covariateName (${covariateTable!.names.skip(1).join(', ')})', 'Covariates: $covariateName (${covariateTable!.names.skip(1).join(', ')})'),
            style: Theme.of(context).textTheme.bodySmall),
      ExpertHint(tr('seuils du contrôle de qualité', 'quality-control thresholds')),
      if (expert) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          NumField(tr('Taux d\'appel min. (sujets)', 'Min. call rate (subjects)'), minSampleCall, width: 200),
          NumField(tr('Hétérozygotie (ET)', 'Heterozygosity (SD)'), hetSd, width: 160),
          NumField(tr('Taux d\'appel min. (variants)', 'Min. call rate (variants)'), minVarCall, width: 200),
          NumField('MAF min.', minMaf),
          NumField(tr('HWE p min.', 'HWE min. p'), hweP),
        ]),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FilledButton.icon(
          onPressed: busy || files.isEmpty ? null : runQc,
          icon: busy && g == null ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined),
          label: Text(tr('Lire et contrôler la qualité', 'Read and check quality')),
        ),
      ),
      if (g != null && table != null) ...[
        const Divider(height: 28),
        Text(tr('Balayage des ${g.variantCount} variants retenus chez ${g.sampleCount} sujets', 'Scan of the ${g.variantCount} retained variants in ${g.sampleCount} subjects'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(tr('Logistique (apparentés exclus)', 'Logistic (relatives excluded)'))),
            ButtonSegment(value: true, label: Text(tr('Modèle mixte (apparentés gardés)', 'Mixed model (relatives kept)'))),
          ],
          selected: {mixed},
          onSelectionChanged: (v) => setState(() {
            mixed = v.first;
            lastScan = null;
            scansByTrait.clear();
            pcCovs = const {};
            covs.removeWhere((c) => c.startsWith('PC'));
          }),
        ),
        if (mixed && outcome != null && !outcomeNumeric)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: logisticMixed,
            onChanged: (v) => setState(() => logisticMixed = v),
            title: Text(tr('Issue binaire : modèle mixte logistique (GMMAT)', 'Binary outcome: logistic mixed model (GMMAT)')),
            subtitle: Text(tr('Test du score sur l\'échelle logit ; sinon modèle linéaire (EMMAX).', 'Score test on the logit scale; otherwise linear model (EMMAX).')),
          ),
        if (mixed && (outcomeNumeric || !logisticMixed))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: loco,
            onChanged: (v) => setState(() => loco = v),
            title: Text(tr('LOCO : parenté calculée sans le chromosome testé', 'LOCO: relatedness computed without the tested chromosome')),
            subtitle: Text(tr('Évite le léger excès de conservatisme ; plus long (un modèle par chromosome).', 'Avoids the slight conservativeness; slower (one model per chromosome).')),
          ),
        const SizedBox(height: 8),
        if (outcomes.isEmpty)
          Text(tr('Aucune issue utilisable : ajouter le statut cas/témoin (ou, pour le modèle mixte, un trait quantitatif) dans le fichier de covariables.', 'No usable outcome: add the case/control status (or, for the mixed model, a quantitative trait) in the covariate file.'),
              style: TextStyle(color: Theme.of(context).colorScheme.error))
        else
          Wrap(spacing: 12, runSpacing: 12, children: [
            Pick<String>(tr('Issue (cas/témoin)', 'Outcome (case/control)'), outcome, [for (final o in outcomes) (o, o)], (v) => setState(() {
                  outcome = v;
                  caseLevel = v == null ? null : table.levels(v).last;
                  covs.remove(v);
                })),
            if (outcome != null && !outcomeNumeric)
              Pick<String>(tr('Modalité « cas »', 'Case level'), caseLevel, [for (final l in table.levels(outcome!)) (l, l)], (v) => setState(() => caseLevel = v)),
            if (!mixed) Pick<PAdjust>(tr('Correction des tests multiples', 'Multiple-testing correction'), correction, [for (final m in PAdjust.values) (m, pAdjustLabel(m))],
                (v) => setState(() => correction = v ?? PAdjust.bh), width: 340),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: busy ? null : runKinship,
            icon: const Icon(Icons.family_restroom),
            label: Text(relatedRemoved == null
                ? tr('Apparentement (KING)', 'Relatedness (KING)')
                : tr('Apparentement calculé : ${relatedRemoved!.length} sujet(s) à écarter', 'Relatedness computed: ${relatedRemoved!.length} subject(s) to remove')),
          ),
        ),
        if (relatedRemoved != null && relatedRemoved!.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: excludeRelated,
            onChanged: (v) => setState(() {
              excludeRelated = v;
              pcCovs = const {};
              covs.removeWhere((c) => c.startsWith('PC'));
              _refreshAnalysis();
            }),
            title: Text(tr('Écarter les ${relatedRemoved!.length} sujets apparentés de l\'ACP et du balayage', 'Remove the ${relatedRemoved!.length} related subjects from the PCA and the scan')),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: busy ? null : runPca,
            icon: const Icon(Icons.scatter_plot_outlined),
            label: Text(pcCovs.isEmpty ? tr('ACP (stratification de population)', 'PCA (population stratification)') : tr('ACP calculée : CP1 à CP${pcCovs.length} disponibles', 'PCA computed: PC1 to PC${pcCovs.length} available')),
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(tr('Ajustement', 'Adjustment'), style: Theme.of(context).textTheme.labelLarge)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in table.names.skip(1).where((c) => c != outcome))
            FilterChip(label: Text(c), selected: covs.contains(c), onSelected: (s) => setState(() => s ? covs.add(c) : covs.remove(c))),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: busy || outcome == null ? null : runScan,
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.manage_search),
            label: Text(tr('Balayer les variants', 'Scan the variants')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: busy || lastScan == null ? null : runLdsc,
            icon: const Icon(Icons.stacked_line_chart),
            label: Text(tr('Régression LD score : polygénie ou confusion ?', 'LD score regression: polygenicity or confounding?')),
          ),
        ),
        if (lastScan == null)
          Text(tr('Disponible après un balayage (scores LD calculés sur ces génotypes).', 'Available after a scan (LD scores computed on these genotypes).'), style: Theme.of(context).textTheme.bodySmall),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: busy || scansByTrait.length < 2 ? null : runRg,
            icon: const Icon(Icons.compare_arrows),
            label: Text(scansByTrait.length < 2
                ? tr('Corrélation génétique entre deux traits', 'Genetic correlation between two traits')
                : tr('Corrélation génétique : ${scansByTrait.keys.elementAt(scansByTrait.length - 2)} – ${scansByTrait.keys.last}',
                    'Genetic correlation: ${scansByTrait.keys.elementAt(scansByTrait.length - 2)} – ${scansByTrait.keys.last}')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: busy || outcome == null || outcomeNumeric ? null : runPrs,
            icon: const Icon(Icons.functions),
            label: Text(covs.isEmpty
                ? tr('Score de risque polygénique (découverte, validation, test)', 'Polygenic risk score (discovery, validation, test)')
                : tr('Score de risque polygénique ajusté sur ${covs.join(', ')}', 'Polygenic risk score adjusted for ${covs.join(', ')}')),
          ),
        ),
        if (scansByTrait.length < 2)
          Text(tr('Balayer successivement deux issues (par exemple deux maladies) sur ces mêmes génotypes.', 'Scan two outcomes in turn (for example two diseases) on these same genotypes.'),
              style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}
