import 'dart:convert';
import 'dart:io';

/// Key → JSON document storage. Keys may contain `/` to group documents
/// (`progress/he-l1-p01-01`). Implementations: [FileJsonStore] (one file per
/// key under the app documents directory) and [MemoryJsonStore] (tests).
abstract class JsonStore {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
  Future<void> delete(String key);

  /// Keys starting with [prefix] (all keys when null).
  Future<List<String>> keys({String? prefix});
  Future<void> clear();
}

class MemoryJsonStore implements JsonStore {
  final Map<String, String> _docs = {};

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final s = _docs[key];
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _docs[key] = jsonEncode(value);
  }

  @override
  Future<void> delete(String key) async {
    _docs.remove(key);
  }

  @override
  Future<List<String>> keys({String? prefix}) async =>
      _docs.keys.where((k) => prefix == null || k.startsWith(prefix)).toList()..sort();

  @override
  Future<void> clear() async => _docs.clear();
}

class FileJsonStore implements JsonStore {
  FileJsonStore(this.root);

  final Directory root;

  File _file(String key) => File('${root.path}/$key.json');

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    try {
      final s = await f.readAsString();
      if (s.isEmpty) return null;
      return jsonDecode(s) as Map<String, dynamic>;
    } on FormatException {
      // Corrupt file (e.g. interrupted write): treat as missing.
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    final f = _file(key);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> keys({String? prefix}) async {
    if (!await root.exists()) return const [];
    final out = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      var rel = e.path.substring(root.path.length);
      if (rel.startsWith('/')) rel = rel.substring(1);
      rel = rel.substring(0, rel.length - '.json'.length);
      if (prefix == null || rel.startsWith(prefix)) out.add(rel);
    }
    out.sort();
    return out;
  }

  @override
  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
