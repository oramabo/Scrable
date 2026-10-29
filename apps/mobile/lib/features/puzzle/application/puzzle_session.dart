import 'package:chetz_core/chetz_core.dart';

/// One-shot UI feedback emitted by the controller (snackbar, announcement,
/// animation). [seq] increments so identical consecutive events still fire.
enum FeedbackKind {
  wordCorrect,
  wordWrong,
  letterWrong,
  puzzleHasErrors,
  puzzleNoErrors,
  checkResult,
  letterRevealed,
  nothingToUndo,
  undone,
  puzzleCompleted,
}

class SessionFeedback {
  const SessionFeedback(this.kind, {required this.seq, this.wordId, this.count = 0});
  final FeedbackKind kind;
  final int seq;
  final String? wordId;
  final int count;
}

class LearnedWord {
  const LearnedWord({required this.answer, required this.clue, required this.wordId});
  final String answer;
  final String clue;
  final String wordId;
}

class CompletionSummary {
  const CompletionSummary({
    required this.elapsedMs,
    required this.hintsUsed,
    required this.stars,
    required this.coinsEarned,
    required this.learned,
    required this.isDaily,
    required this.perfect,
    this.streak,
    this.firstCompletion = false,
    this.firstCompletionBonus = 0,
  });

  final int elapsedMs;
  final int hintsUsed;
  final int stars;
  final int coinsEarned;
  final List<LearnedWord> learned;
  final bool isDaily;
  final bool perfect;
  final int? streak;

  /// The player's very first completed puzzle (FTUE reward card).
  final bool firstCompletion;
  final int firstCompletionBonus;
}

/// Immutable view-state of a solving session.
class PuzzleSession {
  const PuzzleSession({
    required this.puzzle,
    required this.lang,
    required this.progress,
    required this.finalMask,
    this.selection,
    this.undoStack = const [],
    this.pencilMode = false,
    this.timerRunning = true,
    this.feedback,
    this.completion,
    this.lastTypedCell,
    this.isTutorial = false,
    this.errorsNoticeShown = false,
    this.cyclerCell,
    this.cyclerSymbol,
  });

  final Puzzle puzzle;
  final LanguageProfile lang;
  final PuzzleProgress progress;

  /// Cells displayed with the final letter form ([FinalLetterPolicy.mask]).
  final List<bool> finalMask;
  final Selection? selection;

  /// Previous progress snapshots (most recent last), capped by the controller.
  final List<PuzzleProgress> undoStack;
  final bool pencilMode;
  final bool timerRunning;
  final SessionFeedback? feedback;
  final CompletionSummary? completion;
  final int? lastTypedCell;
  final bool isTutorial;

  /// Newspaper mode: the "has errors" notice was shown for the current fill.
  final bool errorsNoticeShown;

  /// A→Z cycler: the cell holding a preview letter and that letter's symbol.
  final int? cyclerCell;
  final int? cyclerSymbol;

  bool get isCycling => cyclerCell != null;

  PuzzleWord? get activeWord => selection == null ? null : puzzle.wordById[selection!.wordId];
  bool get isComplete => progress.completed;

  /// Display string of a cell: letter (final form where the mask says so),
  /// or empty.
  String displayAt(int cell) {
    final e = progress.entry(cell);
    if (e.symbol == null) return '';
    return FinalLetterPolicy.display(lang, e.symbol!, finalMask[cell]);
  }

  /// Pattern of the active word, e.g. `_ _ א _`.
  String patternOf(PuzzleWord w) {
    final parts = <String>[];
    for (final p in w.cells) {
      final i = puzzle.shape.indexOf(p);
      final s = displayAt(i);
      parts.add(s.isEmpty ? '_' : s);
    }
    return parts.join(' ');
  }

  /// Full answer of a word, with final forms per the mask.
  String answerOf(PuzzleWord w) =>
      [for (final p in w.cells) FinalLetterPolicy.display(lang, puzzle.solutionAt(p), finalMask[puzzle.shape.indexOf(p)])]
          .join();

  PuzzleSession copyWith({
    PuzzleProgress? progress,
    Selection? selection,
    bool clearSelection = false,
    List<PuzzleProgress>? undoStack,
    bool? pencilMode,
    bool? timerRunning,
    SessionFeedback? feedback,
    bool clearFeedback = false,
    CompletionSummary? completion,
    int? lastTypedCell,
    bool clearLastTyped = false,
    bool? isTutorial,
    bool? errorsNoticeShown,
    int? cyclerCell,
    int? cyclerSymbol,
    bool clearCycler = false,
  }) =>
      PuzzleSession(
        puzzle: puzzle,
        lang: lang,
        progress: progress ?? this.progress,
        finalMask: finalMask,
        selection: clearSelection ? null : (selection ?? this.selection),
        undoStack: undoStack ?? this.undoStack,
        pencilMode: pencilMode ?? this.pencilMode,
        timerRunning: timerRunning ?? this.timerRunning,
        feedback: clearFeedback ? null : (feedback ?? this.feedback),
        completion: completion ?? this.completion,
        lastTypedCell: clearLastTyped ? null : (lastTypedCell ?? this.lastTypedCell),
        isTutorial: isTutorial ?? this.isTutorial,
        errorsNoticeShown: errorsNoticeShown ?? this.errorsNoticeShown,
        cyclerCell: clearCycler ? null : (cyclerCell ?? this.cyclerCell),
        cyclerSymbol: clearCycler ? null : (cyclerSymbol ?? this.cyclerSymbol),
      );
}
