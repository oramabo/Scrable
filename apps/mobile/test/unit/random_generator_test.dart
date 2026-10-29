
import 'package:chetz_app/core/analytics/analytics.dart';
import 'package:chetz_app/core/content/content_repository.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/features/puzzle/application/progress_providers.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/random/random_puzzle_generator.dart';
import 'package:chetz_app/features/random/random_puzzle_providers.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:chetz_app/features/wallet/wallet_controller.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// On-device generation from the bundled device lexicon + templates
/// (`assets/puzzles/<lang>/device`), in process and through the worker isolate,
/// then a generated level-1 puzzle solved through the controller.
void main() {
  late MapContentSource content;
  late MapContentSource contentEn;

  setUpAll(() async {
    content = await loadBundledContent(device: true);
    contentEn = await loadBundledContent(lang: 'en', device: true);
    expect(content.binaries.keys, contains('assets/puzzles/he/device/lexicon.json.gz'), reason: 'run tools/sync_assets.sh');
  });

  group('DeviceRandomPuzzleGenerator', () {
    test('builds level-1 and level-3 Hebrew puzzles in process (lexicon parsed once)', () async {
      final gen = inProcessGenerator(content, now: () => 1700000000000);
      final sw = Stopwatch()..start();
      final p1 = await gen.generate(lang: 'he', level: 1, seed: 'test-seed-1');
      final firstMs = sw.elapsedMilliseconds;
      sw.reset();
      final p3 = await gen.generate(lang: 'he', level: 3, seed: 'test-seed-3');
      final secondMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('random he: L1 ${firstMs}ms (incl. lexicon load), L3 ${secondMs}ms');

      expect(p1.id, 'he-random-1700000000000');
      expect(p1.kind, PuzzleKind.practice);
      expect(p1.level, 1);
      expect(p1.lang, 'he');
      expect(p1.words.length, greaterThanOrEqualTo(10));
      expect(const PuzzleCodec().verifyChecksum(p1), isTrue);
      expect(p3.level, 3);
      expect(p3.rows * p3.cols, greaterThan(p1.rows * p1.cols), reason: 'level 3 grids are bigger');
      expect(p3.words.length, greaterThan(p1.words.length));
      // Every letter cell is covered by a word of the solution.
      for (final i in p1.letterCellIndices) {
        expect(p1.solution[i], greaterThanOrEqualTo(0));
      }
      gen.dispose();
    });

    test('builds an English level-1 puzzle in process', () async {
      final gen = inProcessGenerator(contentEn, now: () => 42);
      final p = await gen.generate(lang: 'en', level: 1, seed: 'en-seed');
      expect(p.id, 'en-random-42');
      expect(p.lang, 'en');
      expect(p.kind, PuzzleKind.practice);
      gen.dispose();
    });

    test('worker isolate backend builds the same puzzle for the same seed', () async {
      final inProc = inProcessGenerator(content);
      final iso = DeviceRandomPuzzleGenerator(
        dataFor: (lang) => loadDeviceData(ContentRepository(lang: lang, bundled: content)),
        now: () => 7,
      );
      final a = await inProc.generate(lang: 'he', level: 1, seed: 'same-seed', id: 'he-random-7');
      final b = await iso.generate(lang: 'he', level: 1, seed: 'same-seed');
      expect(b.id, 'he-random-7');
      expect(b.solution, a.solution, reason: 'deterministic per seed across backends');
      expect(b.words.map((w) => w.id).toList(), a.words.map((w) => w.id).toList());
      expect(b.meta.generator?.templateId, a.meta.generator?.templateId);
      // (The checksum covers `createdAt`, so it legitimately differs per build.)
      // A second request reuses the live worker (no re-parse).
      final sw = Stopwatch()..start();
      final c = await iso.generate(lang: 'he', level: 2);
      expect(c.level, 2);
      expect(sw.elapsedMilliseconds, lessThan(15000));
      iso.dispose();
      inProc.dispose();
    });

    test('a language without device data fails cleanly', () async {
      final gen = DeviceRandomPuzzleGenerator(dataFor: (_) async => null, inProcess: true);
      expect(() => gen.generate(lang: 'he', level: 1), throwsA(isA<RandomPuzzleException>()));
    });

    test('random ids and seeds', () {
      expect(randomPuzzleId('he', 5), 'he-random-5');
      expect(isRandomPuzzleId('he-random-5'), isTrue);
      expect(isRandomPuzzleId('he-l1-p01-01'), isFalse);
      expect(newRandomSeed().length, 32);
    });
  });

  test('a generated level-1 puzzle is stored in the cache, opened and solved through the controller', () async {
    final store = MemoryJsonStore();
    final container = ProviderContainer(overrides: testOverrides(content: content, store: store));
    addTearDown(container.dispose);

    final id = await generateAndStoreRandomPuzzle(
      container.read(randomPuzzleGeneratorProvider),
      store,
      const NoopAnalytics(),
      lang: 'he',
      level: 1,
    );
    expect(id, startsWith('he-random-'));
    expect(await store.read('puzzle_cache/$id'), isNotNull, reason: 'saved under its id for the content repository');

    // Subscribe the summaries index before solving: it follows the repository's
    // broadcast change stream (events before the first listener are dropped).
    container.read(randomPuzzlesProvider);
    final session0 = await container.read(puzzleSessionProvider(id).future);
    final controller = container.read(puzzleSessionProvider(id).notifier);
    final puzzle = session0.puzzle;
    expect(puzzle.kind, PuzzleKind.practice);
    expect(session0.progress.mode, PlayMode.normal);

    for (final i in puzzle.letterCellIndices) {
      if (container.read(puzzleSessionProvider(id)).requireValue.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(puzzle.solution[i]);
    }
    final done = container.read(puzzleSessionProvider(id)).requireValue;
    expect(done.isComplete, isTrue);
    expect(done.completion, isNotNull);
    // Unranked: half the level-1 reward (20 base + 50% three-star bonus = 30 → 15),
    // plus the first-completion bonus (100), each paid once.
    expect(done.completion!.coinsEarned, 15 + 100);
    final ledger = container.read(walletProvider);
    expect(ledger.hasEntry(LedgerEntryType.earnComplete, id), isTrue);
    expect(ledger.entries.firstWhere((e) => e.refId == id).amount, 15);
    // Listed under "random", never counted as pack stars.
    await controller.flush();
    await Future<void>.delayed(Duration.zero); // the change stream delivers asynchronously
    final randoms = container.read(randomPuzzlesProvider);
    expect(randoms.map((s) => s.puzzleId), contains(id));
    expect(container.read(progressAggregatesProvider).stars, 0, reason: 'practice puzzles are unranked');
  });
}

