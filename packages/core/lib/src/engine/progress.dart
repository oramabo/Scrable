import '../model/geometry.dart';

/// Status of a letter cell in an in-progress puzzle.
enum CellStatus {
  empty('empty'),
  filled('filled'),
  confirmedCorrect('correct'),
  markedWrong('wrong'),
  revealed('revealed');

  const CellStatus(this.code);
  final String code;
  static CellStatus fromCode(String code) =>
      CellStatus.values.firstWhere((v) => v.code == code, orElse: () => CellStatus.empty);
}

class CellEntry {
  const CellEntry({this.symbol, this.status = CellStatus.empty, this.pencil = false, this.updatedAt = 0});

  static const CellEntry blank = CellEntry();

  final int? symbol;
  final CellStatus status;
  final bool pencil;

  /// Milliseconds since epoch of the last change (for sync merges).
  final int updatedAt;

  bool get isEmpty => symbol == null;
  bool get isLocked => status == CellStatus.revealed || status == CellStatus.confirmedCorrect;

  CellEntry copyWith({int? symbol, bool clearSymbol = false, CellStatus? status, bool? pencil, int? updatedAt}) => CellEntry(
        symbol: clearSymbol ? null : (symbol ?? this.symbol),
        status: status ?? this.status,
        pencil: pencil ?? this.pencil,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        if (symbol != null) 's': symbol,
        'st': status.code,
        if (pencil) 'p': true,
        't': updatedAt,
      };
  static CellEntry fromJson(Map<String, dynamic> j) => CellEntry(
        symbol: j['s'] as int?,
        status: CellStatus.fromCode((j['st'] as String?) ?? 'empty'),
        pencil: (j['p'] as bool?) ?? false,
        updatedAt: (j['t'] as int?) ?? 0,
      );
}

/// How and when entries are checked against the solution.
enum PlayMode {
  /// Every letter is checked as it is typed; checks are free.
  relaxed('relaxed'),

  /// A completed word is evaluated as a whole; pinpointing errors costs coins.
  normal('normal'),

  /// Nothing is checked until the grid is full.
  newspaper('newspaper');

  const PlayMode(this.code);
  final String code;
  static PlayMode fromCode(String code) =>
      PlayMode.values.firstWhere((v) => v.code == code, orElse: () => PlayMode.normal);
}

/// Everything saved about one puzzle attempt. Immutable; use [copyWith].
class PuzzleProgress {
  PuzzleProgress({
    required this.puzzleId,
    required this.puzzleVersion,
    required List<CellEntry?> cells,
    this.mode = PlayMode.normal,
    this.elapsedMs = 0,
    this.lettersRevealed = 0,
    this.wordsRevealed = 0,
    this.checksUsed = 0,
    this.wrongEntries = 0,
    this.completed = false,
    this.completedAt,
    this.stars = 0,
    this.startedAt = 0,
    this.lastPlayedAt = 0,
    this.revision = 0,
    this.activeWordId,
    this.cursorCell,
  }) : cells = List.unmodifiable(cells);

  /// Fresh progress for a grid: `null` for clue cells, blank for letters.
  factory PuzzleProgress.fresh({
    required String puzzleId,
    required int puzzleVersion,
    required GridShape shape,
    PlayMode mode = PlayMode.normal,
    int now = 0,
  }) =>
      PuzzleProgress(
        puzzleId: puzzleId,
        puzzleVersion: puzzleVersion,
        cells: [for (final k in shape.kinds) k == CellKind.letter ? CellEntry.blank : null],
        mode: mode,
        startedAt: now,
        lastPlayedAt: now,
      );

  final String puzzleId;
  final int puzzleVersion;
  final List<CellEntry?> cells;
  final PlayMode mode;
  final int elapsedMs;
  final int lettersRevealed;
  final int wordsRevealed;
  final int checksUsed;
  final int wrongEntries;
  final bool completed;
  final int? completedAt;
  final int stars;
  final int startedAt;
  final int lastPlayedAt;
  final int revision;
  final String? activeWordId;
  final int? cursorCell;

  int get hintsUsed => lettersRevealed + wordsRevealed + checksUsed;
  bool get perfect => completed && hintsUsed == 0;

  int get filledCount => cells.where((c) => c != null && !c.isEmpty).length;
  int get letterCount => cells.where((c) => c != null).length;
  bool get isFull => filledCount == letterCount;

  CellEntry entry(int cell) => cells[cell] ?? CellEntry.blank;

  PuzzleProgress copyWith({
    List<CellEntry?>? cells,
    PlayMode? mode,
    int? elapsedMs,
    int? lettersRevealed,
    int? wordsRevealed,
    int? checksUsed,
    int? wrongEntries,
    bool? completed,
    int? completedAt,
    int? stars,
    int? lastPlayedAt,
    int? revision,
    String? activeWordId,
    bool clearActiveWord = false,
    int? cursorCell,
    bool clearCursor = false,
  }) =>
      PuzzleProgress(
        puzzleId: puzzleId,
        puzzleVersion: puzzleVersion,
        cells: cells ?? this.cells,
        mode: mode ?? this.mode,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        lettersRevealed: lettersRevealed ?? this.lettersRevealed,
        wordsRevealed: wordsRevealed ?? this.wordsRevealed,
        checksUsed: checksUsed ?? this.checksUsed,
        wrongEntries: wrongEntries ?? this.wrongEntries,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        stars: stars ?? this.stars,
        startedAt: startedAt,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        revision: revision ?? (this.revision + 1),
        activeWordId: clearActiveWord ? null : (activeWordId ?? this.activeWordId),
        cursorCell: clearCursor ? null : (cursorCell ?? this.cursorCell),
      );

  /// Returns a copy with [cell] replaced.
  PuzzleProgress withCell(int cell, CellEntry entry, {int? now}) {
    final next = List<CellEntry?>.from(cells);
    next[cell] = entry;
    return copyWith(cells: next, lastPlayedAt: now);
  }

  Map<String, dynamic> toJson() => {
        'puzzleId': puzzleId,
        'puzzleVersion': puzzleVersion,
        'cells': [for (final c in cells) c?.toJson()],
        'mode': mode.code,
        'elapsedMs': elapsedMs,
        'lettersRevealed': lettersRevealed,
        'wordsRevealed': wordsRevealed,
        'checksUsed': checksUsed,
        'wrongEntries': wrongEntries,
        'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        'stars': stars,
        'startedAt': startedAt,
        'lastPlayedAt': lastPlayedAt,
        'revision': revision,
        if (activeWordId != null) 'activeWordId': activeWordId,
        if (cursorCell != null) 'cursorCell': cursorCell,
      };

  static PuzzleProgress fromJson(Map<String, dynamic> j) => PuzzleProgress(
        puzzleId: j['puzzleId'] as String,
        puzzleVersion: (j['puzzleVersion'] as int?) ?? 1,
        cells: [for (final c in j['cells'] as List) c == null ? null : CellEntry.fromJson(c as Map<String, dynamic>)],
        mode: PlayMode.fromCode((j['mode'] as String?) ?? 'normal'),
        elapsedMs: (j['elapsedMs'] as int?) ?? 0,
        lettersRevealed: (j['lettersRevealed'] as int?) ?? 0,
        wordsRevealed: (j['wordsRevealed'] as int?) ?? 0,
        checksUsed: (j['checksUsed'] as int?) ?? 0,
        wrongEntries: (j['wrongEntries'] as int?) ?? 0,
        completed: (j['completed'] as bool?) ?? false,
        completedAt: j['completedAt'] as int?,
        stars: (j['stars'] as int?) ?? 0,
        startedAt: (j['startedAt'] as int?) ?? 0,
        lastPlayedAt: (j['lastPlayedAt'] as int?) ?? 0,
        revision: (j['revision'] as int?) ?? 0,
        activeWordId: j['activeWordId'] as String?,
        cursorCell: j['cursorCell'] as int?,
      );

  /// Merge two copies of the same attempt (cloud sync): per cell the newer
  /// entry wins; counters take the maximum; completion is sticky.
  static PuzzleProgress merge(PuzzleProgress a, PuzzleProgress b) {
    final cells = <CellEntry?>[];
    for (var i = 0; i < a.cells.length; i++) {
      final ca = a.cells[i];
      final cb = i < b.cells.length ? b.cells[i] : null;
      if (ca == null || cb == null) {
        cells.add(ca ?? cb);
      } else {
        cells.add(cb.updatedAt > ca.updatedAt ? cb : ca);
      }
    }
    final newer = b.lastPlayedAt >= a.lastPlayedAt ? b : a;
    int maxInt(int x, int y) => x > y ? x : y;
    return PuzzleProgress(
      puzzleId: a.puzzleId,
      puzzleVersion: maxInt(a.puzzleVersion, b.puzzleVersion),
      cells: cells,
      mode: newer.mode,
      elapsedMs: maxInt(a.elapsedMs, b.elapsedMs),
      lettersRevealed: maxInt(a.lettersRevealed, b.lettersRevealed),
      wordsRevealed: maxInt(a.wordsRevealed, b.wordsRevealed),
      checksUsed: maxInt(a.checksUsed, b.checksUsed),
      wrongEntries: maxInt(a.wrongEntries, b.wrongEntries),
      completed: a.completed || b.completed,
      completedAt: a.completedAt ?? b.completedAt,
      stars: maxInt(a.stars, b.stars),
      startedAt: a.startedAt == 0 ? b.startedAt : (b.startedAt == 0 ? a.startedAt : (a.startedAt < b.startedAt ? a.startedAt : b.startedAt)),
      lastPlayedAt: maxInt(a.lastPlayedAt, b.lastPlayedAt),
      revision: maxInt(a.revision, b.revision) + 1,
      activeWordId: newer.activeWordId,
      cursorCell: newer.cursorCell,
    );
  }
}
