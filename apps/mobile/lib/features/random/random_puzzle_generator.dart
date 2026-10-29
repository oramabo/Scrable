import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:flutter/foundation.dart';

/// The gzipped device lexicon + layout templates of one language.
class DeviceData {
  const DeviceData({required this.lang, required this.lexiconGz, required this.templatesGz});
  final String lang;
  final Uint8List lexiconGz;
  final Uint8List templatesGz;
}

class RandomPuzzleException implements Exception {
  const RandomPuzzleException(this.message);
  final String message;
  @override
  String toString() => 'RandomPuzzleException: $message';
}

/// Builds fresh, unranked puzzles on the device from the bundled lexicon.
abstract class RandomPuzzleGenerator {
  /// A new [PuzzleKind.practice] puzzle of [level] with id
  /// `<lang>-random-<timestamp>`. Throws [RandomPuzzleException] when the
  /// language has no device data or the builder gives up.
  Future<Puzzle> generate({required String lang, required int level, String? seed, String? id});

  void dispose();
}

/// Parses the device data once per language and runs the `chetz_core` builder.
/// Pure Dart: used directly by the in-process generator and inside the worker
/// isolate of [DeviceRandomPuzzleGenerator].
class DeviceGeneratorCore {
  DeviceGeneratorCore._(this.lang, this.lexicon, this.templates) : builder = PuzzleBuilder(lexicon);

  factory DeviceGeneratorCore.fromData(DeviceData data) {
    final profile = Languages.byCode(data.lang);
    final lexJson = jsonDecode(utf8.decode(gzip.decode(data.lexiconGz))) as Map<String, dynamic>;
    final tplJson = jsonDecode(utf8.decode(gzip.decode(data.templatesGz)));
    final rawTemplates = tplJson is List ? tplJson : ((tplJson as Map<String, dynamic>)['templates'] as List);
    final templates = [for (final t in rawTemplates) LayoutTemplate.fromJson(t as Map<String, dynamic>)];
    return DeviceGeneratorCore._(profile, Lexicon.fromDevice(profile, lexJson), templates);
  }

  final LanguageProfile lang;
  final Lexicon lexicon;
  final List<LayoutTemplate> templates;
  final PuzzleBuilder builder;

  Puzzle build({required int level, required String seed, required String id}) {
    try {
      return builder
          .build(BuildRequest(id: id, kind: PuzzleKind.practice, level: level, seed: seed, templates: templates))
          .puzzle;
    } on BuildFailure catch (e) {
      // Keep the tail of the builder log: it names the failing stage.
      final tail = e.log.length > 6 ? e.log.sublist(e.log.length - 6) : e.log;
      throw RandomPuzzleException('${e.message}: ${tail.join(' | ')}');
    }
  }
}

String randomPuzzleId(String lang, int nowMs) => '$lang-random-$nowMs';

bool isRandomPuzzleId(String id) => id.contains('-random-');

String newRandomSeed([math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  return List.generate(4, (_) => r.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join();
}

/// Generator backed by one long-lived worker isolate per language: the
/// lexicon (≈1.4 MB gzipped, tens of thousands of words) is decoded and
/// indexed once, then each request takes 0.1–1 s off the UI thread.
///
/// [inProcess] runs the core on the calling isolate instead (tests, where
/// real isolates cannot be awaited under FakeAsync, and platforms without
/// isolates).
class DeviceRandomPuzzleGenerator implements RandomPuzzleGenerator {
  DeviceRandomPuzzleGenerator({required this.dataFor, this.inProcess = false, this.now});

  /// Loads the device files of a language, or null when it has none.
  final Future<DeviceData?> Function(String lang) dataFor;
  final bool inProcess;

  /// Clock for ids (defaults to the wall clock).
  final int Function()? now;

  final Map<String, Future<_Backend>> _backends = {};

  @override
  Future<Puzzle> generate({required String lang, required int level, String? seed, String? id}) async {
    final backend = await (_backends[lang] ??= _open(lang));
    final puzzleId = id ?? randomPuzzleId(lang, now?.call() ?? DateTime.now().millisecondsSinceEpoch);
    return backend.build(level: level, seed: seed ?? newRandomSeed(), id: puzzleId);
  }

  Future<_Backend> _open(String lang) async {
    final data = await dataFor(lang);
    if (data == null) {
      _backends.remove(lang)?.ignore();
      throw const RandomPuzzleException('no device data for this language');
    }
    try {
      if (inProcess) return _InProcessBackend(DeviceGeneratorCore.fromData(data));
      return await _IsolateBackend.spawn(data);
    } catch (e) {
      _backends.remove(lang)?.ignore();
      if (e is RandomPuzzleException) rethrow;
      throw RandomPuzzleException('device data unreadable: $e');
    }
  }

  @override
  void dispose() {
    for (final b in _backends.values) {
      b.then((x) => x.dispose()).ignore();
    }
    _backends.clear();
  }
}

abstract class _Backend {
  Future<Puzzle> build({required int level, required String seed, required String id});
  void dispose();
}

class _InProcessBackend implements _Backend {
  _InProcessBackend(this.core);
  final DeviceGeneratorCore core;

  @override
  Future<Puzzle> build({required int level, required String seed, required String id}) async =>
      core.build(level: level, seed: seed, id: id);

  @override
  void dispose() {}
}

/// Worker protocol: main → worker `[requestId, level, seed, id]`;
/// worker → main `[requestId, puzzleJson | null, error | null]`.
class _IsolateBackend implements _Backend {
  _IsolateBackend._(this._isolate, this._port, this._receive);

  final Isolate _isolate;
  final SendPort _port;
  final ReceivePort _receive;
  final Map<int, Completer<Puzzle>> _pending = {};
  int _seq = 0;
  static const _codec = PuzzleCodec();

  static Future<_IsolateBackend> spawn(DeviceData data) async {
    final receive = ReceivePort();
    final ready = Completer<Object>();
    late final StreamSubscription<dynamic> sub;
    _IsolateBackend? backend;
    sub = receive.listen((msg) {
      if (!ready.isCompleted) {
        ready.complete(msg as Object);
        return;
      }
      backend?._onMessage(msg);
    });
    final isolate = await Isolate.spawn<_WorkerInit>(
      _workerMain,
      _WorkerInit(receive.sendPort, data),
      errorsAreFatal: true,
      debugName: 'chetz-generator-${data.lang}',
    );
    final first = await ready.future;
    if (first is! SendPort) {
      unawaited(sub.cancel());
      receive.close();
      isolate.kill(priority: Isolate.immediate);
      throw RandomPuzzleException('worker failed to start: $first');
    }
    backend = _IsolateBackend._(isolate, first, receive);
    return backend;
  }

  void _onMessage(dynamic msg) {
    if (msg is! List || msg.length < 3) return;
    final completer = _pending.remove(msg[0] as int);
    if (completer == null) return;
    final error = msg[2];
    if (error != null) {
      completer.completeError(RandomPuzzleException(error.toString()));
      return;
    }
    try {
      completer.complete(_codec.fromJson(jsonDecode(msg[1] as String) as Map<String, dynamic>));
    } catch (e) {
      completer.completeError(RandomPuzzleException('bad puzzle from worker: $e'));
    }
  }

  @override
  Future<Puzzle> build({required int level, required String seed, required String id}) {
    final requestId = ++_seq;
    final completer = Completer<Puzzle>();
    _pending[requestId] = completer;
    _port.send([requestId, level, seed, id]);
    return completer.future;
  }

  @override
  void dispose() {
    _receive.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const RandomPuzzleException('generator disposed'));
    }
    _pending.clear();
  }
}

class _WorkerInit {
  const _WorkerInit(this.reply, this.data);
  final SendPort reply;
  final DeviceData data;
}

void _workerMain(_WorkerInit init) {
  DeviceGeneratorCore core;
  try {
    core = DeviceGeneratorCore.fromData(init.data);
  } catch (e) {
    init.reply.send('init failed: $e');
    return;
  }
  const codec = PuzzleCodec();
  final port = ReceivePort();
  init.reply.send(port.sendPort);
  port.listen((msg) {
    final req = msg as List;
    final requestId = req[0] as int;
    try {
      final puzzle = core.build(level: req[1] as int, seed: req[2] as String, id: req[3] as String);
      init.reply.send([requestId, codec.encode(puzzle, obfuscate: false), null]);
    } catch (e) {
      init.reply.send([requestId, null, e.toString()]);
    }
  });
}
