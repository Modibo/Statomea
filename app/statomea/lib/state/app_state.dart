import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:statomea_core/statomea_core.dart';

import '../services/storage.dart';
import '../services/update/update_check.dart';

/// État applicatif : projets (stockés localement), mode d'affichage, langue,
/// leçons. Le moteur statistique est appelé par les écrans ; l'état ne fait
/// qu'enregistrer les résultats dans le journal du projet.
class AppState extends ChangeNotifier {
  final ProjectStorage storage;

  /// Lecture de la version publiée (remplaçable dans les tests).
  final Future<UpdateInfo?> Function() updateFetcher;
  AppState(this.storage, {Future<UpdateInfo?> Function()? updateFetcher}) : updateFetcher = updateFetcher ?? fetchUpdate;

  /// Vérification des nouvelles versions (réglable) ; version disponible et version écartée par l'utilisateur.
  bool checkUpdates = true;
  UpdateInfo? updateAvailable;
  String? dismissedUpdate;
  DateTime? lastUpdateCheck;

  final List<Project> projects = [];
  bool expertMode = false;
  String localeCode = 'fr';
  /// Leçons dans la langue courante (reconstruites au changement de langue).
  List<Lesson> get lessons => _lessons[currentLang] ??= buildLessons();
  final Map<Lang, List<Lesson>> _lessons = {};
  bool loaded = false;

  Future<void> load() async {
    projects
      ..clear()
      ..addAll(await storage.loadAll());
    expertMode = await storage.readBool('expertMode') ?? false;
    localeCode = await storage.readString('locale') ?? 'fr';
    setLang(localeCode == 'en' ? Lang.en : Lang.fr);
    checkUpdates = await storage.readBool('checkUpdates') ?? true;
    dismissedUpdate = await storage.readString('dismissedUpdate');
    loaded = true;
    notifyListeners();
  }

  /// Interroge la version publiée ([manual] : même si le réglage est désactivé). Renvoie la version trouvée.
  Future<UpdateInfo?> checkForUpdate({bool manual = false}) async {
    if (!checkUpdates && !manual) return null;
    final u = await updateFetcher();
    lastUpdateCheck = DateTime.now();
    updateAvailable = u;
    notifyListeners();
    return u;
  }

  /// Bandeau à afficher : une version plus récente, que l'utilisateur n'a pas écartée.
  UpdateInfo? get pendingUpdate => updateAvailable != null && updateAvailable!.version != dismissedUpdate ? updateAvailable : null;

  void dismissUpdate() {
    dismissedUpdate = updateAvailable?.version;
    if (dismissedUpdate != null) storage.writeString('dismissedUpdate', dismissedUpdate!);
    notifyListeners();
  }

  void setCheckUpdates(bool v) {
    checkUpdates = v;
    storage.writeBool('checkUpdates', v);
    if (!v) updateAvailable = null;
    notifyListeners();
  }

  void setExpert(bool v) {
    expertMode = v;
    storage.writeBool('expertMode', v);
    notifyListeners();
  }

  void setLocale(String code) {
    localeCode = code;
    setLang(code == 'en' ? Lang.en : Lang.fr);
    storage.writeString('locale', code);
    notifyListeners();
  }

  static String now() => DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  Project createProject(String title) {
    final id = 'p${DateTime.now().microsecondsSinceEpoch}';
    final p = Project(id: id, title: title.trim().isEmpty ? tr('Projet sans titre', 'Untitled project') : title.trim(), createdAt: now());
    projects.insert(0, p);
    save(p);
    return p;
  }

  Future<void> save(Project p) async {
    await storage.save(p);
    notifyListeners();
  }

  Timer? _debounce;

  /// Enregistrement différé (saisie au clavier).
  void saveSoon(Project p) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => storage.save(p));
  }

  /// Suppression complète : projet, données, journal et réponses aux grilles.
  Future<void> delete(Project p) async {
    projects.removeWhere((x) => x.id == p.id);
    await storage.delete(p.id);
    notifyListeners();
  }

  /// Ajoute un résultat au journal du projet (toute analyse calculée dans un
  /// projet est journalisée automatiquement).
  JournalEntry record(Project p, AnalysisResult r, {Dataset? data, Map<String, Object?> options = const {}}) {
    final e = JournalEntry.fromResult(r,
        id: 'a${(p.journal.length + 1).toString().padLeft(3, '0')}', timestamp: now(), data: data ?? p.dataset, options: options);
    p.journal.add(e);
    p.completed.add(Step.computation);
    save(p);
    return e;
  }

  /// Lit un projet exporté sans l'enregistrer (aperçu avant confirmation).
  /// Un identifiant déjà présent n'est jamais écrasé.
  ProjectImport prepareImport(String text) =>
      importProject(text, existingIds: {for (final p in projects) p.id}, newId: () => 'p${DateTime.now().microsecondsSinceEpoch}');

  /// Enregistre un projet importé, après confirmation.
  Future<void> addImported(Project p) async {
    projects.insert(0, p);
    await save(p);
  }

  Future<Project> openDemo(String which) async {
    final existing = projects.where((p) => p.id == 'demo-$which').toList();
    if (existing.isNotEmpty) return existing.first;
    final Project p;
    switch (which) {
      case 'aghbs':
        p = buildDemoAghbs(await rootBundle.loadString('assets/demos/aghbs_simule.csv'));
      case 'meta':
        p = buildDemoMeta(await rootBundle.loadString('assets/demos/bcg_colditz1994.csv'));
      case 'gwas':
        Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
        final args = (await b('gwas_simule.bed'), await rootBundle.loadString('assets/demos/gwas_simule.bim'), await rootBundle.loadString('assets/demos/gwas_simule.fam'),
            await rootBundle.loadString('assets/demos/gwas_covariables_simule.csv'), currentLang);
        p = await compute(_buildGwas, args);
      case 'polygenic':
        Future<Uint8List> b(String f) async => (await rootBundle.load('assets/demos/$f')).buffer.asUint8List();
        final args = (await b('genotypes_dl_simule.bed'), await rootBundle.loadString('assets/demos/genotypes_dl_simule.bim'),
            await rootBundle.loadString('assets/demos/genotypes_dl_simule.fam'), await rootBundle.loadString('assets/demos/genotypes_dl_traits.csv'), currentLang);
        p = await compute(_buildPolygenic, args);
      case 'survie':
        p = buildDemoSurvivalAdvanced(await rootBundle.loadString('assets/demos/risques_concurrents_simule.csv'));
      case 'mr':
        p = buildDemoMr(await rootBundle.loadString('assets/demos/mr_ldl_chd.csv'));
      case 'tb':
        p = buildDemoTb(await rootBundle.loadString('assets/demos/tb_rifampicine_simule.csv'), await rootBundle.loadString('assets/demos/tb_references_simule.fasta'),
            await rootBundle.loadString('assets/demos/tb_isolat_simule.fasta'));
      default:
        final csv = await rootBundle.loadString('assets/demos/cardiometabolique_simule.csv');
        final ext = await rootBundle.loadString('assets/demos/cardiometabolique_externe_simule.csv');
        p = await compute(_buildPrediction, (csv, ext, currentLang));
    }
    projects.insert(0, p);
    await save(p);
    return p;
  }
}

// Un isolat ne partage pas la langue courante : elle est transmise explicitement.
Project _buildGwas((Uint8List, String, String, String, Lang) a) => withLang(a.$5, () => buildDemoGwas(a.$1, a.$2, a.$3, a.$4));

Project _buildPolygenic((Uint8List, String, String, String, Lang) a) => withLang(a.$5, () => buildDemoPolygenic(a.$1, a.$2, a.$3, a.$4));

Project _buildPrediction((String, String, Lang) a) => withLang(a.$3, () => buildDemoPrediction(a.$1, externalCsv: a.$2));
