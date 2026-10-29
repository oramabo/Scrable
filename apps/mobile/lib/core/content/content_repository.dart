import 'dart:convert';

import 'package:chetz_core/chetz_core.dart';

import '../storage/json_store.dart';
import 'content_source.dart';
import 'manifests.dart';

class PuzzleUnavailableException implements Exception {
  const PuzzleUnavailableException(this.id, [this.reason = 'not found']);
  final String id;
  final String reason;
  @override
  String toString() => 'PuzzleUnavailable($id: $reason)';
}

class PuzzleCorruptException implements Exception {
  const PuzzleCorruptException(this.id);
  final String id;
  @override
  String toString() => 'PuzzleCorrupt($id)';
}

/// Loads puzzles, packs and dailies for one puzzle language.
///
/// Order: bundled assets first (index.json → asset path), then the CDN
/// (manifest url, cached in [cache]) when a base URL is configured. Every
/// decoded puzzle is checksum-verified with [PuzzleCodec.verifyChecksum] and,
/// when the manifest lists a checksum, compared against it too.
class ContentRepository {
  ContentRepository({
    required this.lang,
    required this.bundled,
    this.cdn,
    this.cache,
    this.codec = const PuzzleCodec(),
    this.assetRoot = 'assets/puzzles',
  });

  final String lang;
  final ContentSource bundled;
  final ContentSource? cdn;
  final JsonStore? cache;
  final PuzzleCodec codec;
  final String assetRoot;

  BundledIndex? _index;
  bool _indexLoaded = false;
  PacksManifest? _packs;
  bool _packsLoaded = false;
  DailyManifest? _daily;
  bool _dailyLoaded = false;
  final Map<String, Puzzle> _puzzles = {};
  final Map<String, PackInfo> _descriptors = {};

  String get _base => '$assetRoot/$lang';

  Future<BundledIndex?> index() async {
    if (_indexLoaded) return _index;
    _indexLoaded = true;
    final text = await bundled.readText('$_base/index.json');
    if (text != null) {
      try {
        _index = BundledIndex.fromJson(jsonDecode(text) as Map<String, dynamic>);
      } on FormatException {
        _index = null;
      }
    }
    return _index;
  }

  /// Bundled manifest, replaced by the CDN manifest when that is newer.
  Future<PacksManifest?> packsManifest({bool refresh = false}) async {
    if (_packsLoaded && !refresh) return _packs;
    _packsLoaded = true;
    final local = await _readJson(bundled, '$_base/manifests/packs.json');
    PacksManifest? result = local == null ? null : PacksManifest.fromJson(local);
    if (cdn != null) {
      final remote = await _readJson(cdn!, 'puzzles/$lang/manifests/packs.json');
      if (remote != null) {
        final rm = PacksManifest.fromJson(remote);
        if (result == null || _newer(rm.generatedAt, result.generatedAt)) result = rm;
      }
    }
    return _packs = result;
  }

  Future<DailyManifest?> dailyManifest({bool refresh = false}) async {
    if (_dailyLoaded && !refresh) return _daily;
    _dailyLoaded = true;
    final local = await _readJson(bundled, '$_base/manifests/daily.json');
    DailyManifest? result = local == null ? null : DailyManifest.fromJson(local);
    if (cdn != null) {
      final remote = await _readJson(cdn!, 'puzzles/$lang/manifests/daily.json');
      if (remote != null) {
        final rm = DailyManifest.fromJson(remote);
        if (result == null || _newer(rm.generatedAt, result.generatedAt)) result = rm;
      }
    }
    return _daily = result;
  }

  /// Whether any content exists for this language at all.
  Future<bool> hasContent() async {
    final idx = await index();
    if (idx != null && (idx.puzzles.isNotEmpty || idx.packs.isNotEmpty)) return true;
    final m = await packsManifest();
    return m != null && m.packs.isNotEmpty;
  }

  /// All packs, sorted by level then index. Union of the manifest and the
  /// bundled pack descriptors.
  Future<List<PackInfo>> packs() async {
    final byId = <String, PackInfo>{};
    final manifest = await packsManifest();
    if (manifest != null) {
      for (final p in manifest.packs) {
        byId[p.id] = p;
      }
    }
    final idx = await index();
    if (idx != null) {
      for (final e in idx.packs.entries) {
        final d = await _descriptor(e.key, e.value);
        if (d == null) continue;
        byId[e.key] = byId.containsKey(e.key) ? byId[e.key]!.mergedWith(d) : d;
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.level != b.level ? a.level.compareTo(b.level) : a.index.compareTo(b.index));
    return list;
  }

  Future<List<PackInfo>> packsOfLevel(int level) async => (await packs()).where((p) => p.level == level).toList();

  Future<PackInfo?> pack(String id) async {
    for (final p in await packs()) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<PackInfo?> _descriptor(String id, String asset) async {
    if (_descriptors.containsKey(id)) return _descriptors[id];
    final j = await _readJson(bundled, asset);
    if (j == null) return null;
    return _descriptors[id] = PackInfo.fromDescriptorJson(j);
  }

  /// Whether the puzzle can be opened without network.
  Future<bool> isBundled(String puzzleId) async => (await index())?.puzzles.containsKey(puzzleId) ?? false;

  Future<Puzzle> loadPuzzle(String id) async {
    final cached = _puzzles[id];
    if (cached != null) return cached;

    final idx = await index();
    final asset = idx?.puzzles[id];
    if (asset != null) {
      final text = await bundled.readText(asset);
      if (text != null) return _puzzles[id] = _decode(id, text, expectedChecksum: null);
    }

    // Daily asset keyed by date/variant.
    if (idx != null) {
      final daily = (await dailyManifest())?.byId(id);
      if (daily != null) {
        final dAsset = idx.dailyAsset(daily.date, daily.variant);
        if (dAsset != null) {
          final text = await bundled.readText(dAsset);
          if (text != null) return _puzzles[id] = _decode(id, text, expectedChecksum: daily.checksum);
        }
      }
    }

    // Local download cache.
    final cachedJson = await cache?.read('puzzle_cache/$id');
    final entry = await _manifestEntry(id);
    if (cachedJson != null) {
      try {
        return _puzzles[id] = _decodeJson(id, cachedJson, expectedChecksum: entry?.checksum);
      } on PuzzleCorruptException {
        await cache?.delete('puzzle_cache/$id');
      }
    }

    // CDN.
    if (cdn != null && entry != null && entry.url != null) {
      final text = await cdn!.readText(entry.url!);
      if (text != null) {
        final puzzle = _decode(id, text, expectedChecksum: entry.checksum);
        await cache?.write('puzzle_cache/$id', jsonDecode(text) as Map<String, dynamic>);
        return _puzzles[id] = puzzle;
      }
      throw PuzzleUnavailableException(id, 'download failed');
    }
    throw PuzzleUnavailableException(id, cdn == null ? 'offline' : 'not in manifest');
  }

  Future<({String? url, String? checksum})?> _manifestEntry(String id) async {
    final packs = await packsManifest();
    if (packs != null) {
      for (final p in packs.packs) {
        final e = p.puzzleById(id);
        if (e != null) return (url: e.url, checksum: e.checksum);
      }
    }
    final daily = (await dailyManifest())?.byId(id);
    if (daily != null) return (url: daily.url, checksum: daily.checksum);
    return null;
  }

  /// Daily puzzle id for a local date, or null when no manifest lists it.
  Future<String?> dailyPuzzleId(String date, DailyVariant variant) async {
    final m = await dailyManifest();
    final e = m?.entryFor(date, variant);
    if (e != null) return e.id;
    final idx = await index();
    if (idx?.dailyAsset(date, variant) != null) return '$lang-d-$date-${variant.code}';
    return null;
  }

  Future<Puzzle?> loadDaily(String date, DailyVariant variant) async {
    final id = await dailyPuzzleId(date, variant);
    if (id == null) return null;
    final cached = _puzzles[id];
    if (cached != null) return cached;
    final idx = await index();
    final asset = idx?.dailyAsset(date, variant);
    if (asset != null) {
      final text = await bundled.readText(asset);
      if (text != null) {
        final entry = (await dailyManifest())?.entryFor(date, variant);
        return _puzzles[id] = _decode(id, text, expectedChecksum: entry?.checksum);
      }
    }
    try {
      return await loadPuzzle(id);
    } on PuzzleUnavailableException {
      return null;
    }
  }

  /// Whether the daily for [date]/[variant] can be opened right now.
  Future<bool> isDailyAvailable(String date, DailyVariant variant) async {
    final idx = await index();
    if (idx?.dailyAsset(date, variant) != null) return true;
    if (cdn == null) return false;
    return (await dailyManifest())?.entryFor(date, variant) != null;
  }

  Puzzle _decode(String id, String text, {required String? expectedChecksum}) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw PuzzleCorruptException(id);
    }
    return _decodeJson(id, j, expectedChecksum: expectedChecksum);
  }

  Puzzle _decodeJson(String id, Map<String, dynamic> j, {required String? expectedChecksum}) {
    Puzzle p;
    try {
      p = codec.fromJson(j);
    } catch (_) {
      throw PuzzleCorruptException(id);
    }
    if (!codec.verifyChecksum(p)) throw PuzzleCorruptException(id);
    if (expectedChecksum != null && p.meta.checksum != null && p.meta.checksum != expectedChecksum) {
      throw PuzzleCorruptException(id);
    }
    return p;
  }

  Future<Map<String, dynamic>?> _readJson(ContentSource src, String path) async {
    final text = await src.readText(path);
    if (text == null) return null;
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  static bool _newer(String? a, String? b) {
    if (a == null) return false;
    if (b == null) return true;
    return a.compareTo(b) > 0;
  }

  /// Drops in-memory caches (tests / language switch).
  void reset() {
    _index = null;
    _indexLoaded = false;
    _packs = null;
    _packsLoaded = false;
    _daily = null;
    _dailyLoaded = false;
    _puzzles.clear();
    _descriptors.clear();
  }
}
