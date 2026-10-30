import 'dart:async';
import 'dart:math';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/config/game_config.dart';
import '../../../core/providers.dart';
import '../../../core/util/debouncer.dart';
import '../../../core/util/feedback.dart';
import '../../ads/ads_service.dart';
import '../../daily/daily_controller.dart';
import '../../meta/game_events_controller.dart';
import '../../meta/image_credits.dart';
import '../../settings/settings_controller.dart';
import '../../sync/cloud_sync.dart';
import '../../wallet/ledger.dart';
import '../../wallet/wallet_controller.dart';
import '../data/progress_repository.dart';
import 'alphabet_cycler.dart';
import 'progress_providers.dart';
import 'puzzle_session.dart';

/// The bundled puzzle used as the onboarding tutorial (Hebrew).
const tutorialPuzzleId = 'he-tutorial-01';

/// The dedicated tutorial puzzle of a language (`content/<lang>/puzzles/tutorial/01.json`).
String tutorialPuzzleIdFor(String lang) => '$lang-tutorial-01';

/// A solving session is keyed by the puzzle id, optionally followed by a
/// multiplayer context: `<puzzleId>?match=<matchId>` (versus) or
/// `<puzzleId>?room=<roomId>` (co-op). Multiplayer sessions keep their own
/// progress row (never the solo one) and leave rewards to the server.
class SessionKey {
  const SessionKey(this.puzzleId, {this.matchId, this.roomId});

  final String puzzleId;
  final String? matchId;
  final String? roomId;

  bool get isMultiplayer => matchId != null || roomId != null;
  bool get isVersus => matchId != null;
  bool get isCoop => roomId != null;

  static SessionKey parse(String key) {
    final q = key.indexOf('?');
    if (q < 0) return SessionKey(key);
    final params = Uri.splitQueryString(key.substring(q + 1));
    return SessionKey(key.substring(0, q), matchId: params['match'], roomId: params['room']);
  }

  static String versus(String puzzleId, String matchId) => '$puzzleId?match=$matchId';
  static String coop(String puzzleId, String roomId) => '$puzzleId?room=$roomId';

  @override
  String toString() => isVersus ? versus(puzzleId, matchId!) : (isCoop ? coop(puzzleId, roomId!) : puzzleId);
}

enum HintStatus { applied, insufficientCoins, notApplicable, noSelection }

class HintResult {
  const HintResult(this.status, {this.price = 0, this.usedFreeHint = false});
  final HintStatus status;
  final int price;
  final bool usedFreeHint;
  bool get applied => status == HintStatus.applied;
}

/// Whether the solving timer ticks. Tests override it to `false` so no periodic
/// timer is left pending.
final puzzleTimerEnabledProvider = Provider<bool>((ref) => true);

/// Owns one solving session: loads puzzle + saved progress, applies every
/// input through the engine (navigator/checker), handles play-mode feedback,
/// hints and coins, the A→Z cycler, autosave (debounced 500 ms, immediate on
/// hint/pause/completion) and completion rewards + game events.
///
/// Persistence dependencies are captured in [build] so the dispose-time flush
/// never touches `ref` (Riverpod forbids using Ref inside life-cycles).
class PuzzleController extends AsyncNotifier<PuzzleSession> {
  PuzzleController(this.sessionId) : key = SessionKey.parse(sessionId);

  /// Family argument: puzzle id plus an optional multiplayer context.
  final String sessionId;
  final SessionKey key;

  String get puzzleId => key.puzzleId;

  static const undoLimit = 50;

  /// Active solving time; kept out of the session so the grid does not repaint
  /// every second.
  final ValueNotifier<int> elapsedMs = ValueNotifier<int>(0);

  Timer? _timer;
  final Debouncer _autosave = Debouncer(const Duration(milliseconds: 500));
  int _feedbackSeq = 0;
  final Random _rng = Random();
  bool _saving = false;
  PuzzleSession? _pendingSave;
  bool _cyclerEventRecorded = false;

  late ProgressRepository _repo;
  late CloudSync _cloud;

  @override
  Future<PuzzleSession> build() async {
    _repo = ref.read(progressRepositoryProvider);
    _cloud = ref.read(cloudSyncProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      // Flushes a pending autosave through the captured repository only.
      _autosave.flush();
      _autosave.dispose();
    });

    final lang = Languages.byCode(_langOf(puzzleId));
    final content = ref.read(contentRepositoryProvider(lang.code));
    final puzzle = await content.loadPuzzle(puzzleId);
    final profile = Languages.byCode(puzzle.lang);
    final settings = ref.read(settingsProvider);
    final config = ref.read(gameConfigProvider);
    final now = ref.read(clockProvider).nowMs;

    var progress = await _repo.load(sessionId);
    var fresh = false;
    if (progress == null) {
      fresh = true;
      // Multiplayer races are always played in normal mode (shared rules).
      final mode = key.isMultiplayer
          ? PlayMode.normal
          : settings.modePerLevel[puzzle.level] ??
              (puzzle.daily?.variant == DailyVariant.hard ? PlayMode.newspaper : config.defaultModeForLevel(puzzle.level));
      progress = PuzzleProgress.fresh(
        puzzleId: sessionId,
        puzzleVersion: puzzle.meta.version,
        shape: puzzle.shape,
        mode: mode,
        now: now,
      );
    }
    if (_cloud.enabled && !key.isMultiplayer) {
      final remote = await _cloud.pullProgress(puzzleId);
      if (remote != null) progress = PuzzleProgress.merge(progress, remote);
    }
    elapsedMs.value = progress.elapsedMs;

    final nav = PuzzleNavigator(puzzle, skipFilled: settings.skipFilled, autoNextWord: settings.autoNextWord);
    Selection? selection;
    if (progress.activeWordId != null &&
        progress.cursorCell != null &&
        puzzle.wordById.containsKey(progress.activeWordId)) {
      selection = Selection(wordId: progress.activeWordId!, cell: progress.cursorCell!);
    } else if (nav.readingOrder.isNotEmpty) {
      selection = nav.selectWord(nav.readingOrder.first.id, progress);
    }

    if (!key.isMultiplayer) ref.read(settingsProvider.notifier).setLastPuzzle(puzzleId);
    final analytics = ref.read(analyticsProvider);
    if (fresh) {
      analytics.track(AnalyticsEvents.puzzleStart, {'level': puzzle.level, 'mode': progress.mode.code, 'puzzle': puzzle.id});
      if (puzzle.daily != null) {
        analytics.track(AnalyticsEvents.dailyOpen, {'date': puzzle.daily!.date, 'variant': puzzle.daily!.variant.code});
      }
    }
    _preloadImages(puzzle);

    final session = PuzzleSession(
      puzzle: puzzle,
      lang: profile,
      progress: progress,
      // Grids show regular letters only (ף is shown as פ), never final forms.
      finalMask: List.filled(puzzle.shape.cellCount, false),
      selection: selection,
      timerRunning: !progress.completed,
      isTutorial: !settings.tutorialDone && (puzzle.kind == PuzzleKind.tutorial || puzzleId == tutorialPuzzleIdFor(puzzle.lang)),
    );
    if (!progress.completed) _startTimer();
    if (fresh) unawaited(_persist(session));
    return session;
  }

  /// Starts decoding picture clues and records their credits.
  void _preloadImages(Puzzle puzzle) {
    final srcs = <String>[
      for (final cell in puzzle.clueCells)
        for (final slot in cell.slots)
          if (slot.image != null) slot.image!.src,
    ];
    if (srcs.isEmpty) return;
    final store = ref.read(clueImageStoreProvider(puzzle.lang));
    for (final src in srcs) {
      unawaited(store.image(puzzle.lang, src));
    }
    ref.read(imageCreditsProvider.notifier).addFromPuzzle(puzzle);
  }

  static String _langOf(String id) {
    final dash = id.indexOf('-');
    final code = dash > 0 ? id.substring(0, dash) : 'he';
    return code == 'en' ? 'en' : 'he';
  }

  // ---------------------------------------------------------------- helpers

  PuzzleSession? get _s => state.value;
  int get _now => ref.read(clockProvider).nowMs;
  Puzzle get _puzzle => _s!.puzzle;
  GameEventsController get _events => ref.read(metaProvider.notifier);

  PuzzleNavigator _nav(PuzzleSession s) {
    final settings = ref.read(settingsProvider);
    return PuzzleNavigator(s.puzzle, skipFilled: settings.skipFilled, autoNextWord: settings.autoNextWord);
  }

  PuzzleChecker _checker(PuzzleSession s) =>
      PuzzleChecker(s.puzzle, s.lang, lenientVariants: ref.read(gameConfigProvider).lenientGeresh);

  void _emit(PuzzleSession s) => state = AsyncData(s);

  PuzzleSession _fb(PuzzleSession s, FeedbackKind kind, {String? wordId, int count = 0}) =>
      s.copyWith(feedback: SessionFeedback(kind, seq: ++_feedbackSeq, wordId: wordId, count: count));

  List<PuzzleProgress> _pushUndo(List<PuzzleProgress> stack, PuzzleProgress p) {
    final next = [...stack, p];
    return next.length > undoLimit ? next.sublist(next.length - undoLimit) : next;
  }

  void _startTimer() {
    _timer?.cancel();
    if (!ref.read(puzzleTimerEnabledProvider) || !ref.read(uiTimersEnabledProvider)) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _s;
      if (s != null && s.timerRunning && !s.isComplete) elapsedMs.value += 1000;
    });
  }

  PuzzleProgress _snapshot(PuzzleSession s) {
    // A cycler preview is transient: never persist it.
    var progress = s.progress;
    if (s.cyclerCell != null) progress = progress.withCell(s.cyclerCell!, CellEntry(updatedAt: progress.entry(s.cyclerCell!).updatedAt));
    return progress.copyWith(
      elapsedMs: elapsedMs.value,
      activeWordId: s.selection?.wordId,
      clearActiveWord: s.selection == null,
      cursorCell: s.selection?.cell,
      clearCursor: s.selection == null,
      revision: s.progress.revision,
    );
  }

  void _scheduleSave() {
    final s = _s;
    if (s == null) return;
    _autosave(() => _persist(s));
  }

  Future<void> _saveNow([PuzzleSession? session]) {
    _autosave.dispose();
    final s = session ?? _s;
    if (s == null) return Future.value();
    return _persist(s);
  }

  /// Writes through the captured repository (no `ref` use: this also runs
  /// from the dispose flush). The summaries index follows the repository's
  /// change stream.
  Future<void> _persist(PuzzleSession s) async {
    if (_saving) {
      _pendingSave = s;
      return;
    }
    _saving = true;
    try {
      final progress = _snapshot(s);
      await _repo.save(progress, s.puzzle);
      if (_cloud.enabled && !key.isMultiplayer) unawaited(_cloud.pushProgress(progress));
    } catch (e) {
      debugPrint('progress save failed: $e');
    } finally {
      _saving = false;
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending != null) unawaited(_persist(pending));
    }
  }

  // --------------------------------------------------------------- selection

  void tapCell(int cell) {
    final s = _s;
    if (s == null) return;
    if (s.puzzle.shape.kinds[cell] != CellKind.letter) return;
    if (s.isCycling && s.cyclerCell == cell) {
      confirmCycler();
      return;
    }
    final next = _nav(s).tapCell(cell, s.selection, s.progress);
    if (next == null || next == s.selection) return;
    _emit(_stopCycler(s).copyWith(selection: next));
    unawaited(ref.read(hapticsProvider).tick());
    _scheduleSave();
  }

  void selectWord(String wordId) {
    final s = _s;
    if (s == null || !s.puzzle.wordById.containsKey(wordId)) return;
    _emit(_stopCycler(s).copyWith(selection: _nav(s).selectWord(wordId, s.progress)));
    _scheduleSave();
  }

  void nextWord() {
    final s = _s;
    if (s?.selection == null) return;
    final base = _stopCycler(s!);
    _emit(base.copyWith(selection: _nav(base).nextWord(base.selection!, base.progress)));
    _scheduleSave();
  }

  void prevWord() {
    final s = _s;
    if (s?.selection == null) return;
    final base = _stopCycler(s!);
    _emit(base.copyWith(selection: _nav(base).prevWord(base.selection!, base.progress)));
    _scheduleSave();
  }

  /// Switch to the crossing word through the cursor cell, if any.
  void toggleDirection() {
    final s = _s;
    final sel = s?.selection;
    if (s == null || sel == null) return;
    final other = _nav(s).crossingWord(sel);
    if (other == null) return;
    _emit(_stopCycler(s).copyWith(selection: Selection(wordId: other, cell: sel.cell)));
    _scheduleSave();
  }

  void moveCursor(int cell) {
    final s = _s;
    final sel = s?.selection;
    if (s == null || sel == null) return;
    final w = s.puzzle.wordById[sel.wordId]!;
    if (!w.cells.map(s.puzzle.shape.indexOf).contains(cell)) return tapCell(cell);
    _emit(s.copyWith(selection: Selection(wordId: sel.wordId, cell: cell)));
  }

  // ------------------------------------------------------------------ typing

  void typeSymbol(int symbol) {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return;
    final sel = s0.selection;
    if (sel == null) return;
    // A normal key press while cycling types into the cycler cell and ends the cycle.
    final s = s0.isCycling ? _stopCycler(s0).copyWith(selection: Selection(wordId: sel.wordId, cell: s0.cyclerCell!)) : s0;
    final at = s.selection!;
    final nav = _nav(s);
    if (s.progress.entry(at.cell).isLocked) {
      // Skip locked cells (revealed/confirmed) and type into the next one.
      final next = nav.afterType(at, s.progress);
      if (next == at) return;
      _emit(s.copyWith(selection: next));
      return typeSymbol(symbol);
    }
    _applyLetter(s, at, symbol, pencil: s.pencilMode);
  }

  /// Shared by typing and cycler confirmation: writes [symbol] into [at],
  /// applies play-mode feedback, advances and checks completion.
  void _applyLetter(PuzzleSession s, Selection at, int symbol, {required bool pencil}) {
    final checker = _checker(s);
    final nav = _nav(s);
    final now = _now;
    final progress = checker.type(at.cell, symbol, s.progress, now: now, pencil: pencil);
    var session = s.copyWith(
      progress: progress,
      undoStack: _pushUndo(s.undoStack, s.progress),
      lastTypedCell: at.cell,
      errorsNoticeShown: false,
      clearFeedback: true,
      clearCycler: true,
    );
    session = _applyModeFeedback(session, at.cell, checker, now);
    session = session.copyWith(selection: nav.afterType(at, session.progress));
    session = _checkCompletion(session, checker);
    _emit(session);
    final fb = session.feedback?.kind;
    final haptics = ref.read(hapticsProvider);
    if (fb == FeedbackKind.wordWrong || fb == FeedbackKind.letterWrong) {
      unawaited(haptics.error());
    } else if (fb == FeedbackKind.wordCorrect) {
      unawaited(haptics.success());
      unawaited(ref.read(soundsProvider).play(SoundCue.wordCorrect));
    } else {
      unawaited(haptics.tick());
    }
    if (session.isComplete) {
      unawaited(_saveNow(session));
    } else {
      _scheduleSave();
    }
  }

  PuzzleSession _applyModeFeedback(PuzzleSession session, int cell, PuzzleChecker checker, int now) {
    var progress = session.progress;
    final puzzle = session.puzzle;
    final words = puzzle.index.wordsAt(cell);
    switch (progress.mode) {
      case PlayMode.normal:
        String? wrong;
        String? correct;
        for (final id in words) {
          final w = puzzle.wordById[id]!;
          if (!checker.isWordFilled(w, progress)) continue;
          final (next, ok) = checker.evaluateWord(w, progress, now: now);
          if (ok) {
            progress = next;
            correct ??= id;
            _wordSolved(session, w);
          } else {
            wrong ??= id;
          }
        }
        session = session.copyWith(progress: progress);
        if (wrong != null) return _fb(session, FeedbackKind.wordWrong, wordId: wrong);
        if (correct != null) return _fb(session, FeedbackKind.wordCorrect, wordId: correct);
        return session;
      case PlayMode.relaxed:
        if (progress.entry(cell).status == CellStatus.markedWrong) return _fb(session, FeedbackKind.letterWrong);
        for (final id in words) {
          final w = puzzle.wordById[id]!;
          if (checker.isWordFilled(w, progress) && checker.isWordCorrect(w, progress)) {
            _wordSolved(session, w);
            return _fb(session, FeedbackKind.wordCorrect, wordId: id);
          }
        }
        return session;
      case PlayMode.newspaper:
        if (progress.isFull && !checker.isComplete(progress) && !session.errorsNoticeShown) {
          return _fb(session.copyWith(errorsNoticeShown: true), FeedbackKind.puzzleHasErrors);
        }
        return session;
    }
  }

  void _wordSolved(PuzzleSession session, PuzzleWord w) {
    ref.read(analyticsProvider).track(AnalyticsEvents.wordSolved, {'word': w.id, 'clue_id': w.clueId});
    _events.recordWordSolved(session.puzzle.lang);
  }

  void backspace() {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return;
    final s = _stopCycler(s0);
    final sel = s.selection;
    if (sel == null) return;
    final nav = _nav(s);
    final target = nav.backspaceTarget(sel, s.progress);
    final entry = s.progress.entry(target.cell);
    var session = s.copyWith(selection: target, clearFeedback: true);
    if (!entry.isEmpty && !entry.isLocked) {
      final progress = _checker(s).clear(target.cell, s.progress, now: _now);
      session = session.copyWith(
        progress: progress,
        undoStack: _pushUndo(s.undoStack, s.progress),
        errorsNoticeShown: false,
        clearLastTyped: true,
      );
    }
    _emit(session);
    unawaited(ref.read(hapticsProvider).tick());
    _scheduleSave();
  }

  /// Co-op: a letter placed (or cleared, [symbol] null) by another member.
  /// Written without undo history or feedback; the word is evaluated as in
  /// normal mode and completion is checked. Locked cells are left alone.
  void applyRemoteLetter(int cell, int? symbol) {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return;
    if (s0.puzzle.shape.kinds[cell] != CellKind.letter) return;
    final s = _stopCycler(s0);
    final entry = s.progress.entry(cell);
    if (entry.isLocked) return;
    if (entry.symbol == symbol && !entry.pencil) return;
    final checker = _checker(s);
    final now = _now;
    var session = s;
    if (symbol == null) {
      if (entry.isEmpty) return;
      session = s.copyWith(progress: checker.clear(cell, s.progress, now: now), errorsNoticeShown: false);
    } else {
      final progress = checker.type(cell, symbol, s.progress, now: now, pencil: false);
      session = s.copyWith(progress: progress, errorsNoticeShown: false, clearFeedback: true);
      session = _applyModeFeedback(session, cell, checker, now);
      session = _checkCompletion(session, checker);
    }
    _emit(session);
    if (session.isComplete) {
      unawaited(_saveNow(session));
    } else {
      _scheduleSave();
    }
  }

  /// Hebrew geresh key: turns the last typed base letter (ג ז צ ת ד) into its
  /// geresh variant symbol.
  void applyGeresh() {
    final s = _s;
    if (s == null || s.isComplete || s.isCycling) return;
    final cell = s.lastTypedCell ?? s.selection?.cell;
    if (cell == null) return;
    final entry = s.progress.entry(cell);
    if (entry.isEmpty || entry.isLocked) return;
    final variant = s.lang.variantOf(entry.symbol!);
    if (variant == null) return;
    final checker = _checker(s);
    final now = _now;
    final progress = checker.type(cell, variant, s.progress, now: now, pencil: entry.pencil);
    var session = s.copyWith(progress: progress, undoStack: _pushUndo(s.undoStack, s.progress), clearFeedback: true);
    session = _applyModeFeedback(session, cell, checker, now);
    session = _checkCompletion(session, checker);
    _emit(session);
    _scheduleSave();
  }

  /// Hardware keyboard: a typed character mapped through the language profile.
  bool typeCharacter(String ch) {
    final s = _s;
    if (s == null) return false;
    final symbols = s.lang.normalize(ch);
    if (symbols == null || symbols.length != 1) return false;
    typeSymbol(symbols.single);
    return true;
  }

  void undo() {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return;
    final s = _stopCycler(s0);
    if (s.undoStack.isEmpty) {
      _emit(_fb(s, FeedbackKind.nothingToUndo));
      return;
    }
    final previous = s.undoStack.last;
    final session = _fb(
      s.copyWith(progress: previous, undoStack: s.undoStack.sublist(0, s.undoStack.length - 1), errorsNoticeShown: false),
      FeedbackKind.undone,
    );
    _emit(session);
    _scheduleSave();
  }

  void togglePencilMode() {
    final s = _s;
    if (s == null) return;
    _emit(s.copyWith(pencilMode: !s.pencilMode));
  }

  void setCellPencil(int cell, bool pencil) {
    final s = _s;
    if (s == null || s.isComplete) return;
    final entry = s.progress.entry(cell);
    if (entry.isEmpty || entry.isLocked || entry.pencil == pencil) return;
    _emit(s.copyWith(progress: s.progress.withCell(cell, entry.copyWith(pencil: pencil, updatedAt: _now), now: _now)));
    _scheduleSave();
  }

  void clearWord(String wordId) {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return;
    final s = _stopCycler(s0);
    final w = s.puzzle.wordById[wordId];
    if (w == null) return;
    final checker = _checker(s);
    var progress = s.progress;
    final now = _now;
    for (final p in w.cells) {
      progress = checker.clear(s.puzzle.shape.indexOf(p), progress, now: now);
    }
    if (identical(progress, s.progress)) return;
    _emit(s.copyWith(
      progress: progress,
      undoStack: _pushUndo(s.undoStack, s.progress),
      selection: _nav(s).selectWord(wordId, progress),
      errorsNoticeShown: false,
    ));
    _scheduleSave();
  }

  // ---------------------------------------------------------------- cycler

  /// Cell the A→Z cycler would write into, or null when unavailable.
  int? cyclerTarget([PuzzleSession? session]) {
    final s = session ?? _s;
    final word = s?.activeWord;
    if (s == null || word == null || s.isComplete) return null;
    return AlphabetCycler.targetCell(s.puzzle, word, s.progress, cyclingCell: s.cyclerCell);
  }

  /// Writes the next alphabet letter into the target cell as a pencil
  /// preview. No checking happens until [confirmCycler].
  void cycleNext() {
    final s = _s;
    if (s == null || s.isComplete) return;
    final cell = cyclerTarget(s);
    if (cell == null) return;
    final symbol = AlphabetCycler.next(s.lang, s.cyclerSymbol);
    final existing = s.progress.entry(cell);
    final progress = s.progress.withCell(
      cell,
      CellEntry(symbol: symbol, status: CellStatus.filled, pencil: true, updatedAt: existing.updatedAt),
    );
    final session = s.copyWith(
      progress: progress,
      selection: Selection(wordId: s.selection!.wordId, cell: cell),
      cyclerCell: cell,
      cyclerSymbol: symbol,
      undoStack: s.isCycling ? s.undoStack : _pushUndo(s.undoStack, s.progress),
      clearFeedback: true,
    );
    if (!_cyclerEventRecorded) {
      _cyclerEventRecorded = true;
      _events.recordCyclerUsed();
      ref.read(analyticsProvider).track('alphabet_cycler_used', {'puzzle': s.puzzle.id});
    }
    _emit(session);
    unawaited(ref.read(hapticsProvider).tick());
  }

  /// Locks the previewed letter in: it is typed normally (so normal mode
  /// evaluates the word and relaxed mode checks the letter).
  void confirmCycler() {
    final s = _s;
    if (s == null || !s.isCycling) return;
    final cell = s.cyclerCell!;
    final symbol = s.cyclerSymbol!;
    final restored = _stopCycler(s);
    _cyclerEventRecorded = false;
    _applyLetter(restored, Selection(wordId: s.selection!.wordId, cell: cell), symbol, pencil: false);
  }

  /// Drops the preview letter and ends the cycling session.
  void cancelCycler() {
    final s = _s;
    if (s == null || !s.isCycling) return;
    _cyclerEventRecorded = false;
    _emit(_stopCycler(s));
  }

  /// Session with the cycler preview removed (restores the cell's prior state).
  PuzzleSession _stopCycler(PuzzleSession s) {
    if (!s.isCycling) return s;
    final cell = s.cyclerCell!;
    final previous = s.undoStack.isNotEmpty ? s.undoStack.last.entry(cell) : CellEntry.blank;
    final progress = s.progress.withCell(cell, previous);
    _cyclerEventRecorded = false;
    return s.copyWith(
      progress: progress,
      undoStack: s.undoStack.isNotEmpty ? s.undoStack.sublist(0, s.undoStack.length - 1) : s.undoStack,
      clearCycler: true,
    );
  }

  // ------------------------------------------------------------------- hints

  int hintPrice(HintType type) {
    final s = _s;
    if (s == null) return 0;
    return ref.read(gameConfigProvider).hintPrice(type, level: s.puzzle.level, mode: s.progress.mode);
  }

  Future<HintResult> useHint(HintType type) async {
    final s0 = _s;
    if (s0 == null || s0.isComplete) return const HintResult(HintStatus.notApplicable);
    final s = _stopCycler(s0);
    final sel = s.selection;
    final word = s.activeWord;
    if (sel == null || word == null) return const HintResult(HintStatus.noSelection);
    final checker = _checker(s);
    final progress0 = s.progress;

    // Decide applicability and target before charging.
    int? target;
    switch (type) {
      case HintType.revealLetter:
        if (progress0.entry(sel.cell).status == CellStatus.revealed) return const HintResult(HintStatus.notApplicable);
        target = sel.cell;
      case HintType.randomLetter:
        target = checker.randomLetterCell(word, progress0, _rng.nextInt);
        if (target == null) return const HintResult(HintStatus.notApplicable);
      case HintType.smartLetter:
        target = checker.smartLetterCell(word, progress0);
        if (target == null) return const HintResult(HintStatus.notApplicable);
      case HintType.revealWord:
        if (word.cells.every((p) => progress0.entry(s.puzzle.shape.indexOf(p)).isLocked)) {
          return const HintResult(HintStatus.notApplicable);
        }
      case HintType.checkWord:
        if (word.cells.every((p) => progress0.entry(s.puzzle.shape.indexOf(p)).isEmpty)) {
          return const HintResult(HintStatus.notApplicable);
        }
      case HintType.checkPuzzle:
        if (progress0.filledCount == 0) return const HintResult(HintStatus.notApplicable);
      case HintType.firstLetters:
        break;
    }

    final price = hintPrice(type);
    var usedFree = false;
    if (price > 0) {
      final wallet = ref.read(walletProvider.notifier);
      if (wallet.freeHintsLeft() > 0) {
        wallet.useFreeHint();
        usedFree = true;
      } else if (!wallet.spend(_ledgerTypeFor(type), price, refId: '${s.puzzle.id}:${type.code}:$_now', trackEvent: false)) {
        return HintResult(HintStatus.insufficientCoins, price: price);
      }
    }

    final now = _now;
    var progress = progress0;
    FeedbackKind? fb;
    var count = 0;
    switch (type) {
      case HintType.revealLetter:
      case HintType.randomLetter:
      case HintType.smartLetter:
        progress = checker.revealLetter(target!, progress, now: now);
        fb = FeedbackKind.letterRevealed;
      case HintType.revealWord:
        progress = checker.revealWord(word, progress, now: now);
      case HintType.checkWord:
        final r = checker.check(progress, w: word, now: now);
        progress = r.progress;
        count = r.wrongCells.length;
        fb = FeedbackKind.checkResult;
      case HintType.checkPuzzle:
        final r = checker.check(progress, now: now);
        progress = r.progress;
        count = r.wrongCells.length;
        fb = FeedbackKind.checkResult;
      case HintType.firstLetters:
        progress = checker.revealFirstLetters(progress, now: now);
    }

    var session = s.copyWith(progress: progress, undoStack: const [], errorsNoticeShown: false, clearFeedback: true);
    final nav = _nav(session);
    if (target != null && target == sel.cell) {
      session = session.copyWith(selection: nav.afterType(sel, progress));
    } else if (type == HintType.revealWord || type == HintType.firstLetters) {
      final next = nav.nextIncompleteWord(sel.wordId, progress);
      if (next != null && checker.isWordFilled(word, progress)) {
        session = session.copyWith(selection: nav.selectWord(next.id, progress));
      }
    }
    if (fb != null) session = _fb(session, fb, count: count);
    session = _checkCompletion(session, checker);
    _emit(session);

    final analytics = ref.read(analyticsProvider);
    analytics.track(AnalyticsEvents.hintUsed, {'type': type.code, 'cost': usedFree ? 0 : price});
    if (type == HintType.checkWord || type == HintType.checkPuzzle) {
      analytics.track(AnalyticsEvents.checkUsed, {'scope': type.code, 'wrong': count});
    }
    _events.recordHintUsed(coins: usedFree ? 0 : price);
    unawaited(ref.read(soundsProvider).play(SoundCue.hint));
    await _saveNow(session);
    return HintResult(HintStatus.applied, price: price, usedFreeHint: usedFree);
  }

  static LedgerEntryType _ledgerTypeFor(HintType type) => switch (type) {
        HintType.revealLetter || HintType.randomLetter || HintType.smartLetter => LedgerEntryType.spendLetter,
        HintType.revealWord => LedgerEntryType.spendWord,
        HintType.checkWord || HintType.checkPuzzle => LedgerEntryType.spendCheck,
        HintType.firstLetters => LedgerEntryType.spendItem,
      };

  // -------------------------------------------------------------- play mode

  /// Only before the first letter is entered.
  bool setMode(PlayMode mode) {
    final s = _s;
    if (s == null || s.progress.filledCount > 0 || s.isComplete) return false;
    _emit(s.copyWith(progress: s.progress.copyWith(mode: mode)));
    ref.read(settingsProvider.notifier).setModeForLevel(s.puzzle.level, mode);
    _scheduleSave();
    return true;
  }

  bool get canChangeMode => (_s?.progress.filledCount ?? 1) == 0 && !(_s?.isComplete ?? true);

  // -------------------------------------------------------------- lifecycle

  Future<void> pause() async {
    final s = _s;
    if (s == null) return;
    _timer?.cancel();
    _timer = null;
    if (s.timerRunning) _emit(s.copyWith(timerRunning: false));
    await _saveNow();
  }

  void resume() {
    final s = _s;
    if (s == null || s.isComplete) return;
    if (!s.timerRunning) _emit(s.copyWith(timerRunning: true));
    _startTimer();
  }

  /// Flushes any pending autosave (called when leaving the screen).
  Future<void> flush() => _saveNow();

  void markTutorialDone() {
    ref.read(settingsProvider.notifier).completeTutorial();
    final s = _s;
    if (s != null && s.isTutorial) _emit(s.copyWith(isTutorial: false));
  }

  /// The player shared the result from the completion sheet.
  void recordShared() {
    _events.recordShared();
    ref.read(analyticsProvider).track('result_shared', {'puzzle': puzzleId});
  }

  // -------------------------------------------------------------- completion

  PuzzleSession _checkCompletion(PuzzleSession session, PuzzleChecker checker) {
    if (session.isComplete || !checker.isComplete(session.progress)) return session;
    return _complete(session);
  }

  PuzzleSession _complete(PuzzleSession session) {
    final config = ref.read(gameConfigProvider);
    final puzzle = session.puzzle;
    final clock = ref.read(clockProvider);
    final now = clock.nowMs;
    var progress = session.progress.copyWith(completed: true, completedAt: now, elapsedMs: elapsedMs.value);
    final stars = PuzzleChecker.starsFor(progress, parMs: config.parMs(puzzle.level));
    progress = progress.copyWith(stars: stars);

    final wallet = ref.read(walletProvider.notifier);
    final ledger = ref.read(walletProvider);
    var coins = 0;
    int? streak;
    var completedPack = false;
    final daily = puzzle.daily;
    // Versus / co-op: the server credits coins, XP and season points.
    final multiplayer = key.isMultiplayer;
    // FTUE (UX §5): the very first completed puzzle pays a welcome bonus.
    final firstCompletion = !multiplayer &&
        ref.read(metaProvider).stats.puzzlesCompleted == 0 &&
        !ledger.hasEntry(LedgerEntryType.earnComplete, 'first_completion');
    var firstBonus = 0;
    if (firstCompletion) {
      firstBonus = config.firstCompletionBonus;
      wallet.earn(LedgerEntryType.earnComplete, firstBonus, refId: 'first_completion');
      coins += firstBonus;
    }
    if (multiplayer) {
      // No local economy; the match / room controller shows the server's rewards.
    } else if (daily != null) {
      final reward = daily.variant == DailyVariant.easy ? config.dailyEasyReward : config.dailyHardReward;
      final refId = 'daily:${daily.date}:${daily.variant.code}';
      if (!ledger.hasEntry(LedgerEntryType.earnDaily, refId)) {
        wallet.earn(LedgerEntryType.earnDaily, reward, refId: refId);
        coins += reward;
      }
      streak = ref.read(dailyHistoryProvider.notifier).markCompleted(daily.date, daily.variant);
      if (ref.read(dailyHistoryProvider).bothCompleted(daily.date)) {
        final bothRef = 'daily:${daily.date}:both';
        if (!ref.read(walletProvider).hasEntry(LedgerEntryType.earnDaily, bothRef)) {
          wallet.earn(LedgerEntryType.earnDaily, config.dailyBothBonus, refId: bothRef);
          coins += config.dailyBothBonus;
        }
      }
      ref.read(analyticsProvider).track(AnalyticsEvents.dailyComplete, {
        'date': daily.date,
        'variant': daily.variant.code,
        'time': progress.elapsedMs,
        'streak': streak,
      });
      if (daily.variant == DailyVariant.hard) {
        unawaited(_cloud.submitDaily(puzzle: puzzle, progress: progress));
      }
    } else {
      // Random on-device puzzles are unranked: half the reward (GameConfig).
      final reward = config.completionReward(puzzle.level, stars: stars, kind: puzzle.kind);
      if (!ledger.hasEntry(LedgerEntryType.earnComplete, puzzle.id)) {
        wallet.earn(LedgerEntryType.earnComplete, reward, refId: puzzle.id);
        coins += reward;
      }
      final pack = puzzle.pack;
      if (pack != null) {
        final summaries = ref.read(progressSummariesProvider);
        final others = summaries.values.where((s) => s.packId == pack.id && s.completed && s.puzzleId != puzzle.id).length;
        final total = puzzle.kind == PuzzleKind.pack ? 30 : others + 1;
        final packRef = 'pack:${pack.id}';
        if (others + 1 >= total && !ledger.hasEntry(LedgerEntryType.earnComplete, packRef)) {
          completedPack = true;
          wallet.earn(LedgerEntryType.earnComplete, config.packCompletionBonus, refId: packRef);
          coins += config.packCompletionBonus;
        }
      }
    }

    unawaited(ref.read(adsServiceProvider).recordPuzzleCompleted());
    ref.read(analyticsProvider).track(AnalyticsEvents.puzzleComplete, {
      'level': puzzle.level,
      'mode': progress.mode.code,
      'time': progress.elapsedMs,
      'hints': progress.hintsUsed,
      'stars': stars,
      'puzzle': puzzle.id,
    });
    unawaited(ref.read(hapticsProvider).success());
    unawaited(ref.read(soundsProvider).play(SoundCue.puzzleComplete));

    // Words never reported through wordSolved events (newspaper mode confirms
    // nothing during play); fully revealed words do not count as solved.
    final checker = _checker(session);
    var wordsForEvent = 0;
    if (progress.mode == PlayMode.newspaper) {
      for (final w in puzzle.words) {
        final revealed = w.cells.every((p) => session.progress.entry(puzzle.shape.indexOf(p)).status == CellStatus.revealed);
        if (!revealed && checker.isWordCorrect(w, progress)) wordsForEvent++;
      }
    }
    _events.record(
      GameEvent.puzzleCompleted(
        timestampMs: now,
        lang: puzzle.lang,
        puzzleId: puzzle.id,
        level: puzzle.level,
        mode: progress.mode,
        elapsedMs: progress.elapsedMs,
        parMs: config.parMs(puzzle.level),
        hintsUsed: progress.hintsUsed,
        wordsSolved: wordsForEvent,
        isDaily: daily != null,
        dailyVariant: daily?.variant.code,
        dailyDate: daily?.date,
        completedPack: completedPack,
        localHour: clock.now().hour,
      ),
      // Multiplayer XP / season points come from the server's result.
      progression: !multiplayer,
    );

    final learned = _learnedWords(session);
    _timer?.cancel();
    _timer = null;

    final summary = CompletionSummary(
      elapsedMs: progress.elapsedMs,
      hintsUsed: progress.hintsUsed,
      stars: stars,
      coinsEarned: coins,
      learned: learned,
      isDaily: daily != null,
      perfect: progress.hintsUsed == 0,
      streak: streak,
      firstCompletion: firstCompletion,
      firstCompletionBonus: firstBonus,
    );
    return _fb(
      session.copyWith(progress: progress, completion: summary, timerRunning: false, clearCycler: true),
      FeedbackKind.puzzleCompleted,
    );
  }

  /// Three answers worth remembering: the hardest words of the puzzle.
  List<LearnedWord> _learnedWords(PuzzleSession session) {
    final words = [...session.puzzle.words]..sort((a, b) => b.difficulty.compareTo(a.difficulty));
    return [
      for (final w in words.take(3))
        LearnedWord(answer: session.answerOf(w), clue: session.puzzle.clueTextOf(w.id), wordId: w.id),
    ];
  }

  /// Next puzzle in the same pack, if any.
  Future<String?> nextPuzzleId() async {
    final pack = _s?.puzzle.pack;
    if (pack == null) return null;
    final info = await ref.read(contentRepositoryProvider(_puzzle.lang)).pack(pack.id);
    return info?.puzzleAt(pack.index + 1)?.id;
  }

  /// Share of letter cells filled (0..1); reported to the opponent in versus.
  double get filledFraction {
    final p = _s?.progress;
    if (p == null || p.letterCount == 0) return 0;
    return p.filledCount / p.letterCount;
  }

  /// Interstitial hook — only from the completion sheet, never during solving.
  Future<bool> showCompletionInterstitial({required bool adsFree}) =>
      ref.read(adsServiceProvider).showInterstitialIfAllowed(AdPlacements.completionInterstitial, adsFree: adsFree);
}

final puzzleSessionProvider = AsyncNotifierProvider.autoDispose.family<PuzzleController, PuzzleSession, String>(
  PuzzleController.new,
);
