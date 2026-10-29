import 'dart:async';

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/content/content_repository.dart';
import '../../core/providers.dart';
import '../../core/storage/json_store.dart';
import '../puzzle/application/progress_providers.dart';
import '../puzzle/data/progress_repository.dart';
import '../settings/settings_controller.dart';
import 'random_puzzle_generator.dart';

/// Loads a language's device data (gzipped lexicon + templates) from the
/// bundled content source via the index.
Future<DeviceData?> loadDeviceData(ContentRepository repo) async {
  final idx = await repo.index();
  if (idx == null || !idx.hasDeviceData) return null;
  final lex = await repo.bundled.readBytes(idx.device['lexicon']!);
  final tpl = await repo.bundled.readBytes(idx.device['templates']!);
  if (lex == null || tpl == null) return null;
  return DeviceData(lang: repo.lang, lexiconGz: lex, templatesGz: tpl);
}

/// The app-wide generator (one worker isolate per language, kept alive).
/// Tests override it with an in-process generator.
final randomPuzzleGeneratorProvider = Provider<RandomPuzzleGenerator>((ref) {
  final gen = DeviceRandomPuzzleGenerator(
    dataFor: (lang) => loadDeviceData(ref.read(contentRepositoryProvider(lang))),
    now: () => ref.read(clockProvider).nowMs,
  );
  ref.onDispose(gen.dispose);
  return gen;
});

/// Whether the active puzzle language ships device data (random puzzles).
final randomAvailableProvider = FutureProvider<bool>((ref) async {
  final idx = await ref.watch(puzzleContentProvider).index();
  return idx?.hasDeviceData ?? false;
});

/// Generates a random puzzle of [level] in [lang], stores it in the puzzle
/// cache (so the content repository can open it by id) and returns its id.
Future<String> generateAndStoreRandomPuzzle(
  RandomPuzzleGenerator generator,
  JsonStore store,
  Analytics analytics, {
  required String lang,
  required int level,
}) async {
  final puzzle = await generator.generate(lang: lang, level: level);
  await store.write('puzzle_cache/${puzzle.id}', const PuzzleCodec().toJson(puzzle));
  analytics.track('random_puzzle_generated', {'lang': lang, 'level': level, 'puzzle': puzzle.id});
  return puzzle.id;
}

/// Widget entry point: the active puzzle language unless [lang] is given.
Future<String> createRandomPuzzleFrom(WidgetRef ref, int level, {String? lang}) => generateAndStoreRandomPuzzle(
      ref.read(randomPuzzleGeneratorProvider),
      ref.read(jsonStoreProvider),
      ref.read(analyticsProvider),
      lang: lang ?? ref.read(settingsProvider).puzzleLang,
      level: level,
    );

/// Random puzzles the player opened, newest first (from the progress index).
final randomPuzzlesProvider = Provider<List<ProgressSummary>>((ref) {
  final lang = ref.watch(settingsProvider.select((s) => s.puzzleLang));
  final rows = ref
      .watch(progressSummariesProvider)
      .values
      .where((s) => s.kind == PuzzleKind.practice && isRandomPuzzleId(s.puzzleId) && s.puzzleId.startsWith('$lang-'))
      .toList()
    ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
  return rows;
});

/// Level of a random puzzle from its summary (the id carries no level).
int randomPuzzleLevel(ProgressSummary s) => s.level;

/// Exposed for diagnostics.
void logRandomFailure(Object e) => debugPrint('random puzzle failed: $e');
