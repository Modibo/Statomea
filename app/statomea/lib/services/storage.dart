import 'package:shared_preferences/shared_preferences.dart';
import 'package:statomea_core/statomea_core.dart';

/// Stockage local des projets (aucun serveur). Chaque projet est un document
/// JSON ; un index liste les identifiants. La suppression efface le document
/// et toutes les clés associées au projet.
abstract class ProjectStorage {
  Future<List<Project>> loadAll();
  Future<void> save(Project p);
  Future<void> delete(String id);
  Future<bool?> readBool(String key);
  Future<void> writeBool(String key, bool v);
  Future<String?> readString(String key);
  Future<void> writeString(String key, String v);
}

class PrefsStorage implements ProjectStorage {
  static const _index = 'statomea.projects';
  static String _key(String id) => 'statomea.project.$id';

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<List<Project>> loadAll() async {
    final p = await _p;
    final ids = p.getStringList(_index) ?? [];
    final out = <Project>[];
    for (final id in ids) {
      final s = p.getString(_key(id));
      if (s == null) continue;
      try {
        out.add(Project.decode(s));
      } catch (_) {
        // Document illisible (version antérieure) : ignoré, pas supprimé.
      }
    }
    return out;
  }

  @override
  Future<void> save(Project project) async {
    final p = await _p;
    final ids = p.getStringList(_index) ?? [];
    if (!ids.contains(project.id)) await p.setStringList(_index, [project.id, ...ids]);
    await p.setString(_key(project.id), project.encodeCompact());
  }

  @override
  Future<void> delete(String id) async {
    final p = await _p;
    final ids = p.getStringList(_index) ?? [];
    await p.setStringList(_index, [for (final x in ids) if (x != id) x]);
    for (final k in p.getKeys().where((k) => k.startsWith('statomea.project.$id'))) {
      await p.remove(k);
    }
  }

  @override
  Future<bool?> readBool(String key) async => (await _p).getBool('statomea.$key');
  @override
  Future<void> writeBool(String key, bool v) async => (await _p).setBool('statomea.$key', v);
  @override
  Future<String?> readString(String key) async => (await _p).getString('statomea.$key');
  @override
  Future<void> writeString(String key, String v) async => (await _p).setString('statomea.$key', v);
}

/// Stockage en mémoire (tests).
class MemoryStorage implements ProjectStorage {
  final Map<String, String> docs = {};
  final Map<String, Object> prefs = {};
  @override
  Future<List<Project>> loadAll() async => [for (final s in docs.values) Project.decode(s)];
  @override
  Future<void> save(Project p) async => docs[p.id] = p.encodeCompact();
  @override
  Future<void> delete(String id) async => docs.remove(id);
  @override
  Future<bool?> readBool(String key) async => prefs[key] as bool?;
  @override
  Future<void> writeBool(String key, bool v) async => prefs[key] = v;
  @override
  Future<String?> readString(String key) async => prefs[key] as String?;
  @override
  Future<void> writeString(String key, String v) async => prefs[key] = v;
}
