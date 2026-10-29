import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'content_source.dart';

/// Resolves and caches picture-clue images.
///
/// Lookup order for `src` (e.g. `images/hw_123.jpg`): memory → bundled asset
/// `assets/puzzles/<lang>/<src>` → file cache under [cacheDir] → CDN
/// `<lang>/<src>` (then written to the file cache). Decoded [ui.Image]s are
/// kept for the painter; [version] bumps whenever a new image is ready so
/// the grid can repaint.
typedef ImageDecoder = Future<ui.Image> Function(Uint8List bytes);

/// Default decoder: the engine's codec.
Future<ui.Image> engineDecode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

class ClueImageStore {
  ClueImageStore({
    required this.bundled,
    this.cdn,
    this.cacheDir,
    this.assetRoot = 'assets/puzzles',
    this.decode = engineDecode,
  });

  final ContentSource bundled;
  final ContentSource? cdn;
  final Directory? cacheDir;
  final String assetRoot;

  /// Bytes → image; injectable so tests can avoid the engine decoder.
  final ImageDecoder decode;

  final Map<String, Uint8List> _bytes = {};
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<Uint8List?>> _loading = {};
  final Set<String> _missing = {};
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  static String keyOf(String lang, String src) => '$lang/$src';

  /// Pre-populates the caches synchronously (tests, prefetch pipelines).
  void seed(String lang, String src, Uint8List bytes, {ui.Image? image}) {
    final key = keyOf(lang, src);
    _bytes[key] = bytes;
    if (image != null) _images[key] = image;
    version.value++;
  }

  /// Already-decoded image, or null (call [image] to start loading).
  ui.Image? imageIfLoaded(String lang, String src) => _images[keyOf(lang, src)];
  Uint8List? bytesIfLoaded(String lang, String src) => _bytes[keyOf(lang, src)];
  bool isMissing(String lang, String src) => _missing.contains(keyOf(lang, src));

  Future<Uint8List?> bytes(String lang, String src) {
    final key = keyOf(lang, src);
    final cached = _bytes[key];
    if (cached != null) return Future.value(cached);
    if (_missing.contains(key)) return Future.value(null);
    // Block body: returning the removed Future from whenComplete would make
    // the result wait on itself.
    return _loading[key] ??= _fetch(lang, src, key).whenComplete(() {
      _loading.remove(key);
    });
  }

  Future<Uint8List?> _fetch(String lang, String src, String key) async {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      final remote = await cdn?.readBytes(src);
      return _store(key, remote);
    }
    var data = await bundled.readBytes('$assetRoot/$lang/$src');
    data ??= await _readCacheFile(lang, src);
    if (data == null && cdn != null) {
      data = await cdn!.readBytes('$lang/$src');
      if (data != null) unawaited(_writeCacheFile(lang, src, data));
    }
    return _store(key, data);
  }

  Uint8List? _store(String key, Uint8List? data) {
    if (data == null || data.isEmpty) {
      _missing.add(key);
      version.value++;
      return null;
    }
    _bytes[key] = data;
    return data;
  }

  /// Decoded image (null when unavailable). Safe to call repeatedly.
  Future<ui.Image?> image(String lang, String src) async {
    final key = keyOf(lang, src);
    final ready = _images[key];
    if (ready != null) return ready;
    final data = await bytes(lang, src);
    if (data == null) return null;
    if (_images.containsKey(key)) return _images[key];
    try {
      final image = await decode(data);
      _images[key] = image;
      version.value++;
      return image;
    } catch (e) {
      debugPrint('image decode failed for $key: $e');
      _missing.add(key);
      version.value++;
      return null;
    }
  }

  File? _cacheFile(String lang, String src) {
    final dir = cacheDir;
    if (dir == null) return null;
    return File('${dir.path}/images/$lang/$src');
  }

  Future<Uint8List?> _readCacheFile(String lang, String src) async {
    final f = _cacheFile(lang, src);
    if (f == null || !await f.exists()) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCacheFile(String lang, String src, Uint8List data) async {
    final f = _cacheFile(lang, src);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data, flush: true);
    } catch (e) {
      debugPrint('image cache write failed: $e');
    }
  }

  void dispose() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _bytes.clear();
    version.dispose();
  }
}
