import 'dart:async';
import 'dart:math';

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/config/game_config.dart';
import '../../../core/providers.dart';
import '../../../core/util/debouncer.dart';
import '../../../core/util/feedback.dart';
import '../../ads/ads_service.dart';
import '../../daily/daily_controller.dart';
import '../../settings/settings_controller.dart';
import '../../wallet/ledger.dart';
import '../../wallet/wallet_controller.dart';
import '../data/progress_repository.dart';
import 'progress_providers.dart';
import 'puzzle_session.dart';

/// The bundled puzzle used as the onboarding tutorial (Hebrew).
const tutorialPuzzleId = 'he-l1-p01-01';

/// First puzzle of pack 1 / level 1 of a language: the tutorial puzzle.
String tutorialPuzzleIdFor(String lang) => '$lang-l1-p01-01';

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
/// hints and coins, autosave (debounced 500 ms, immediate on hint/pause/
/// completion) and completion rewards.
class PuzzleController extends AsyncNotifier<PuzzleSession> {
  PuzzleController(this.puzzleId);

  final String puzzleId;

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

  @override
  Future<PuzzleSession> build() async {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _autosave.flush();
      _autosave.dispose();
    });

    final lang = Languages.byCode(_langOf(puzzleId));
    final content = ref.read(contentRepositoryProvider(lang.code));
    final puzzle = await content.loadPuzzle(puzzleId);
    final profile = Languages.byCode(puzzle.lang);
    final settings = ref.read(settingsProvider);
    final config = ref.read(gameConfigProvider);
    final repo = ref.read(progressRepositoryProvider);
    final now = ref.read(clockProvider).nowMs;

    var progress = await repo.load(puzzleId);
    var fresh = false;
    if (progress == null) {
      fresh = true;
      final mode = settings.modePerLevel[puzzle.level] ??
          (puzzle.daily?.variant == DailyVariant.hard ? PlayMode.newspaper : config.defaultModeForLevel(puzzle.level));
      progress = PuzzleProgress.fresh(
        puzzleId: puzzle.id,
        puzzleVersion: puzzle.meta.version,
        shape: puzzle.shape,
        mode: mode,
        now: now,
      );
    }
    final cloud = ref.read(cloudSyncProvider);
    if (cloud.enabled) {
      final remote = await cloud.pullProgress(puzzleId);
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

    ref.read(settingsProvider.notifier).setLastPuzzle(puzzleId);
    final analytics = ref.read(analyticsProvider);
    if (fresh) {
      analytics.track(AnalyticsEvents.puzzleStart, {'level': puzzle.level, 'mode': progress.mode.code, 'puzzle': puzzle.id});
      if (puzzle.daily != null) {
        analytics.track(AnalyticsEvents.dailyOpen, {'date': puzzle.daily!.date, 'variant': puzzle.daily!.variant.code});
      }
    }

    final session = PuzzleSession(
      puzzle: puzzle,
      lang: profile,
      progress: progress,
      finalMask: FinalLetterPolicy.mask(puzzle),
      selection: selection,
      timerRunning: !progress.completed,
      isTutorial: !settings.tutorialDone && puzzleId == tutorialPuzzleIdFor(puzzle.lang),
    );
    if (!progress.completed) _startTimer();
    if (fresh) unawaited(_persist(session));
    return session;
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
    if (!ref.read(puzzleTimerEnabledProvider)) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _s;
      if (s != null && s.timerRunning && !s.isComplete) elapsedMs.value += 1000;
    });
  }

  PuzzleProgress _snapshot(PuzzleSession s) => s.progress.copyWith(
        elapsedMs: elapsedMs.value,
        activeWordId: s.selection?.wordId,
        clearActiveWord: s.selection == null,
        cursorCell: s.selection?.cell,
        clearCursor: s.selection == null,
        revision: s.progress.revision,
      );

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

  Future<void> _persist(PuzzleSession s) async {
    // Serialise writes; keep only the latest pending snapshot.
    if (_saving) {
      _pendingSave = s;
      return;
    }
    _saving = true;
    try {
      final progress = _snapshot(s);
      await ref.read(progressRepositoryProvider).save(progress, s.puzzle);
      ref.read(progressSummariesProvider.notifier).upsert(ProgressSummary.of(progress, s.puzzle));
      final cloud = ref.read(cloudSyncProvider);
      if (cloud.enabled) unawaited(cloud.pushProgress(progress));
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
    final next = _nav(s).tapCell(cell, s.selection, s.progress);
    if (next == null || next == s.selection) return;
    _emit(s.copyWith(selection: next));
    unawaited(ref.read(hapticsProvider).tick());
    _scheduleSave();
  }

  void selectWord(String wordId) {
    final s = _s;
    if (s == null || !s.puzzle.wordById.containsKey(wordId)) return;
    _emit(s.copyWith(selection: _nav(s).selectWord(wordId, s.progress)));
    _scheduleSave();
  }

  void nextWord() {
    final s = _s;
    if (s?.selection == null) return;
    _emit(s!.copyWith(selection: _nav(s).nextWord(s.selection!, s.progress)));
    _scheduleSave();
  }

  void prevWord() {
    final s = _s;
    if (s?.selection == null) return;
    _emit(s!.copyWith(selection: _nav(s).prevWord(s.selection!, s.progress)));
    _scheduleSave();
  }

  /// Switch to the crossing word through the cursor cell, if any.
  void toggleDirection() {
    final s = _s;
    final sel = s?.selection;
    if (s == null || sel == null) return;
    final other = _nav(s).crossingWord(sel);
    if (other == null) return;
    _emit(s.copyWith(selection: Selection(wordId: other, cell: sel.cell)));
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
    final s = _s;
    if (s == null || s.isComplete) return;
    final sel = s.selection;
    if (sel == null) return;
    final nav = _nav(s);
    if (s.progress.entry(sel.cell).isLocked) {
      // Skip locked cells (revealed/confirmed) and type into the next one.
      final next = nav.afterType(sel, s.progress);
      if (next == sel) return;
      _emit(s.copyWith(selection: next));
      return typeSymbol(symbol);
    }
    final checker = _checker(s);
    final now = _now;
    final progress = checker.type(sel.cell, symbol, s.progress, now: now, pencil: s.pencilMode);
    var session = s.copyWith(
      progress: progress,
      undoStack: _pushUndo(s.undoStack, s.progress),
      lastTypedCell: sel.cell,
      errorsNoticeShown: false,
      clearFeedback: true,
    );
    session = _applyModeFeedback(session, sel.cell, checker, now);
    session = session.copyWith(selection: nav.afterType(sel, session.progress));
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
            ref.read(analyticsProvider).track(AnalyticsEvents.wordSolved, {'word': id, 'clue_id': w.clueId});
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
            ref.read(analyticsProvider).track(AnalyticsEvents.wordSolved, {'word': id, 'clue_id': w.clueId});
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

  void backspace() {
    final s = _s;
    if (s == null || s.isComplete) return;
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

  /// Hebrew geresh key: turns the last typed base letter (ג ז צ ת ד) into its
  /// geresh variant symbol.
  void applyGeresh() {
    final s = _s;
    if (s == null || s.isComplete) return;
    final cell = s.lastTypedCell ?? s.selection?.cell;
    if (cell == null) return;
    final entry = s.progress.entry(cell);
    if (entry.isEmpty || entry.isLocked) return;
    final base = entry.symbol!;
    int? variant;
    for (var v = 0; v < s.lang.alphabetSize; v++) {
      if (v != base && s.lang.baseSymbol(v) == base) {
        variant = v;
        break;
      }
    }
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
    final s = _s;
    if (s == null || s.isComplete) return;
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
    final s = _s;
    if (s == null || s.isComplete) return;
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

  // ------------------------------------------------------------------- hints

  int hintPrice(HintType type) {
    final s = _s;
    if (s == null) return 0;
    return ref.read(gameConfigProvider).hintPrice(type, level: s.puzzle.level, mode: s.progress.mode);
  }

  Future<HintResult> useHint(HintType type) async {
    final s = _s;
    if (s == null || s.isComplete) return const HintResult(HintStatus.notApplicable);
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
      } else if (!wallet.spend(_ledgerTypeFor(type), price, refId: '${s.puzzle.id}:${type.code}:$_now')) {
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

  // -------------------------------------------------------------- completion

  PuzzleSession _checkCompletion(PuzzleSession session, PuzzleChecker checker) {
    if (session.isComplete || !checker.isComplete(session.progress)) return session;
    return _complete(session);
  }

  PuzzleSession _complete(PuzzleSession session) {
    final config = ref.read(gameConfigProvider);
    final puzzle = session.puzzle;
    final now = _now;
    var progress = session.progress.copyWith(completed: true, completedAt: now, elapsedMs: elapsedMs.value);
    final stars = PuzzleChecker.starsFor(progress, parMs: config.parMs(puzzle.level));
    progress = progress.copyWith(stars: stars);

    final wallet = ref.read(walletProvider.notifier);
    final ledger = ref.read(walletProvider);
    var coins = 0;
    int? streak;
    final daily = puzzle.daily;
    if (daily != null) {
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
        unawaited(ref.read(cloudSyncProvider).submitDaily(puzzle: puzzle, progress: progress));
      }
    } else {
      final reward = config.completionReward(puzzle.level, stars: stars);
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
    );
    return _fb(
      session.copyWith(progress: progress, completion: summary, timerRunning: false),
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

  /// Interstitial hook — only from the completion sheet, never during solving.
  Future<bool> showCompletionInterstitial({required bool adsFree}) =>
      ref.read(adsServiceProvider).showInterstitialIfAllowed(AdPlacements.completionInterstitial, adsFree: adsFree);
}

final puzzleSessionProvider = AsyncNotifierProvider.autoDispose.family<PuzzleController, PuzzleSession, String>(
  PuzzleController.new,
);
