import 'package:chetz_core/chetz_core.dart';

/// One daily puzzle in `manifests/daily.json`.
class DailyManifestEntry {
  const DailyManifestEntry({
    required this.date,
    required this.variant,
    required this.id,
    required this.url,
    required this.checksum,
    required this.version,
  });

  final String date;
  final DailyVariant variant;
  final String id;
  final String url;
  final String? checksum;
  final int version;

  static DailyManifestEntry fromJson(Map<String, dynamic> j) => DailyManifestEntry(
        date: j['date'] as String,
        variant: DailyVariant.fromCode(j['variant'] as String),
        id: j['id'] as String,
        url: j['url'] as String,
        checksum: j['checksum'] as String?,
        version: (j['version'] as int?) ?? 1,
      );
}

class DailyManifest {
  const DailyManifest({required this.lang, required this.entries, this.version = 1, this.generatedAt});

  final String lang;
  final int version;
  final String? generatedAt;
  final List<DailyManifestEntry> entries;

  static DailyManifest fromJson(Map<String, dynamic> j) => DailyManifest(
        lang: (j['lang'] as String?) ?? 'he',
        version: (j['version'] as int?) ?? 1,
        generatedAt: j['generatedAt'] as String?,
        entries: ((j['entries'] as List?) ?? const [])
            .map((e) => DailyManifestEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  DailyManifestEntry? entryFor(String date, DailyVariant variant) {
    for (final e in entries) {
      if (e.date == date && e.variant == variant) return e;
    }
    return null;
  }

  DailyManifestEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// One puzzle of a pack as listed in `manifests/packs.json`.
class PackPuzzleEntry {
  const PackPuzzleEntry({required this.id, required this.index, this.url, this.checksum, this.difficulty, this.words});

  final String id;
  final int index;
  final String? url;
  final String? checksum;
  final double? difficulty;
  final int? words;

  static PackPuzzleEntry fromJson(Map<String, dynamic> j) => PackPuzzleEntry(
        id: j['id'] as String,
        index: j['index'] as int,
        url: j['url'] as String?,
        checksum: j['checksum'] as String?,
        difficulty: (j['difficulty'] as num?)?.toDouble(),
        words: j['words'] as int?,
      );
}

/// A pack as the app sees it: merged from the packs manifest and/or a bundled
/// `pack.json` descriptor.
class PackInfo {
  const PackInfo({
    required this.id,
    required this.lang,
    required this.level,
    required this.index,
    required this.title,
    required this.puzzleCount,
    required this.puzzles,
    this.url,
    this.checksum,
    this.free = true,
    this.pictures = false,
  });

  final String id;
  final String lang;
  final int level;
  final int index;

  /// Picture-clue pack.
  final bool pictures;

  /// Title per UI language code.
  final Map<String, String> title;
  final int puzzleCount;
  final List<PackPuzzleEntry> puzzles;
  final String? url;
  final String? checksum;
  final bool free;

  String titleFor(String uiLang) => title[uiLang] ?? title['en'] ?? title.values.firstOrNull ?? id;

  PackPuzzleEntry? puzzleAt(int index) {
    for (final p in puzzles) {
      if (p.index == index) return p;
    }
    return null;
  }

  PackPuzzleEntry? puzzleById(String id) {
    for (final p in puzzles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// From a `packs.json` manifest entry.
  static PackInfo fromManifestJson(Map<String, dynamic> j) => PackInfo(
        id: j['id'] as String,
        lang: (j['lang'] as String?) ?? 'he',
        level: j['level'] as int,
        index: j['index'] as int,
        title: _title(j['title']),
        puzzleCount: (j['puzzleCount'] as int?) ?? ((j['puzzles'] as List?)?.length ?? 0),
        puzzles: ((j['puzzles'] as List?) ?? const [])
            .map((p) => PackPuzzleEntry.fromJson(p as Map<String, dynamic>))
            .toList(),
        url: j['url'] as String?,
        checksum: j['checksum'] as String?,
        free: (j['free'] as bool?) ?? true,
        pictures: (j['pictures'] as bool?) ?? false,
      );

  /// From a bundled `pack.json` descriptor: puzzles are listed as ids, with
  /// an optional `checksums` map {puzzleId: "sha256:…"} and a `pictures` flag.
  static PackInfo fromDescriptorJson(Map<String, dynamic> j) {
    final ids = ((j['puzzles'] as List?) ?? const []);
    final checksums = j['checksums'] is Map ? (j['checksums'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())) : const <String, String>{};
    return PackInfo(
      id: j['id'] as String,
      lang: (j['lang'] as String?) ?? 'he',
      level: j['level'] as int,
      index: j['index'] as int,
      title: _title(j['title']),
      puzzleCount: (j['puzzleCount'] as int?) ?? ids.length,
      puzzles: [
        for (var k = 0; k < ids.length; k++)
          ids[k] is String
              ? PackPuzzleEntry(id: ids[k] as String, index: k + 1, checksum: checksums[ids[k] as String])
              : PackPuzzleEntry.fromJson(ids[k] as Map<String, dynamic>),
      ],
      free: (j['free'] as bool?) ?? true,
      pictures: (j['pictures'] as bool?) ?? false,
    );
  }

  static Map<String, String> _title(Object? v) {
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    if (v is String) return {'he': v, 'en': v};
    return const {};
  }

  /// Prefer manifest data (urls, checksums) but keep descriptor data when the
  /// manifest lacks it.
  PackInfo mergedWith(PackInfo other) => PackInfo(
        id: id,
        lang: lang,
        level: level,
        index: index,
        title: title.isEmpty ? other.title : title,
        puzzleCount: puzzleCount == 0 ? other.puzzleCount : puzzleCount,
        puzzles: puzzles.isEmpty
            ? other.puzzles
            : [
                for (final p in puzzles)
                  p.url == null && other.puzzleById(p.id)?.url != null ? other.puzzleById(p.id)! : p,
              ],
        url: url ?? other.url,
        checksum: checksum ?? other.checksum,
        free: free && other.free,
        pictures: pictures || other.pictures,
      );
}

class PacksManifest {
  const PacksManifest({required this.lang, required this.packs, this.version = 1, this.generatedAt});

  final String lang;
  final int version;
  final String? generatedAt;
  final List<PackInfo> packs;

  static PacksManifest fromJson(Map<String, dynamic> j) => PacksManifest(
        lang: (j['lang'] as String?) ?? 'he',
        version: (j['version'] as int?) ?? 1,
        generatedAt: j['generatedAt'] as String?,
        packs: ((j['packs'] as List?) ?? const [])
            .map((p) => PackInfo.fromManifestJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// `assets/puzzles/<lang>/index.json` written by tools/sync_assets.sh.
class BundledIndex {
  const BundledIndex({required this.lang, required this.puzzles, required this.packs, required this.dailies});

  final String lang;

  /// puzzle id → asset path
  final Map<String, String> puzzles;

  /// pack id → asset path of its pack.json
  final Map<String, String> packs;

  /// `YYYY-MM-DD/variant` → asset path
  final Map<String, String> dailies;

  static BundledIndex fromJson(Map<String, dynamic> j) => BundledIndex(
        lang: (j['lang'] as String?) ?? 'he',
        puzzles: _strMap(j['puzzles']),
        packs: _strMap(j['packs']),
        dailies: _strMap(j['dailies']),
      );

  static Map<String, String> _strMap(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val.toString())) : const {};

  String? dailyAsset(String date, DailyVariant v) => dailies['$date/${v.code}'];
}
