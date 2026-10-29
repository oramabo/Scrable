import '../engine/progress.dart';

/// Gameplay events the app records; stats, achievements and missions are all
/// derived from them so every number in the game has one source of truth.
enum GameEventType {
  puzzleCompleted,
  wordSolved,
  hintUsed,
  coinsEarned,
  coinsSpent,
  alphabetCyclerUsed,
  resultShared,
  loginDay,
}

class GameEvent {
  const GameEvent({
    required this.type,
    required this.timestampMs,
    this.lang,
    this.puzzleId,
    this.level,
    this.isDaily = false,
    this.dailyVariant,
    this.dailyDate,
    this.perfect = false,
    this.mode,
    this.elapsedMs,
    this.parMs,
    this.hintsUsed = 0,
    this.wordsSolved = 0,
    this.coins = 0,
    this.completedPack = false,
    this.localHour,
  });

  factory GameEvent.puzzleCompleted({
    required int timestampMs,
    required String lang,
    required String puzzleId,
    required int level,
    required PlayMode mode,
    required int elapsedMs,
    required int parMs,
    required int hintsUsed,
    required int wordsSolved,
    bool isDaily = false,
    String? dailyVariant,
    String? dailyDate,
    bool completedPack = false,
    int? localHour,
  }) =>
      GameEvent(
        type: GameEventType.puzzleCompleted,
        timestampMs: timestampMs,
        lang: lang,
        puzzleId: puzzleId,
        level: level,
        mode: mode,
        elapsedMs: elapsedMs,
        parMs: parMs,
        hintsUsed: hintsUsed,
        wordsSolved: wordsSolved,
        perfect: hintsUsed == 0 && mode != PlayMode.relaxed,
        isDaily: isDaily,
        dailyVariant: dailyVariant,
        dailyDate: dailyDate,
        completedPack: completedPack,
        localHour: localHour,
      );

  factory GameEvent.wordSolved({required int timestampMs, required String lang}) =>
      GameEvent(type: GameEventType.wordSolved, timestampMs: timestampMs, lang: lang, wordsSolved: 1);
  factory GameEvent.hintUsed({required int timestampMs, required int coins}) =>
      GameEvent(type: GameEventType.hintUsed, timestampMs: timestampMs, hintsUsed: 1, coins: coins);
  factory GameEvent.coinsEarned({required int timestampMs, required int coins}) =>
      GameEvent(type: GameEventType.coinsEarned, timestampMs: timestampMs, coins: coins);
  factory GameEvent.coinsSpent({required int timestampMs, required int coins}) =>
      GameEvent(type: GameEventType.coinsSpent, timestampMs: timestampMs, coins: coins);
  factory GameEvent.alphabetCyclerUsed({required int timestampMs}) =>
      GameEvent(type: GameEventType.alphabetCyclerUsed, timestampMs: timestampMs);
  factory GameEvent.resultShared({required int timestampMs}) => GameEvent(type: GameEventType.resultShared, timestampMs: timestampMs);
  factory GameEvent.loginDay({required int timestampMs, required String date}) =>
      GameEvent(type: GameEventType.loginDay, timestampMs: timestampMs, dailyDate: date);

  final GameEventType type;
  final int timestampMs;
  final String? lang;
  final String? puzzleId;
  final int? level;
  final bool isDaily;
  final String? dailyVariant;

  /// ISO date of the daily (or of the login day).
  final String? dailyDate;
  final bool perfect;
  final PlayMode? mode;
  final int? elapsedMs;
  final int? parMs;
  final int hintsUsed;
  final int wordsSolved;
  final int coins;
  final bool completedPack;

  /// Local hour of day (0-23) when the puzzle was completed.
  final int? localHour;

  bool get underPar => elapsedMs != null && parMs != null && elapsedMs! <= parMs!;
  bool get underHalfPar => elapsedMs != null && parMs != null && elapsedMs! * 2 <= parMs!;

  Map<String, dynamic> toJson() => {
        't': type.name,
        'ts': timestampMs,
        if (lang != null) 'lang': lang,
        if (puzzleId != null) 'puzzleId': puzzleId,
        if (level != null) 'level': level,
        if (isDaily) 'daily': true,
        if (dailyVariant != null) 'variant': dailyVariant,
        if (dailyDate != null) 'date': dailyDate,
        if (perfect) 'perfect': true,
        if (mode != null) 'mode': mode!.code,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (parMs != null) 'parMs': parMs,
        if (hintsUsed != 0) 'hints': hintsUsed,
        if (wordsSolved != 0) 'words': wordsSolved,
        if (coins != 0) 'coins': coins,
        if (completedPack) 'pack': true,
        if (localHour != null) 'hour': localHour,
      };

  static GameEvent fromJson(Map<String, dynamic> j) => GameEvent(
        type: GameEventType.values.firstWhere((v) => v.name == j['t']),
        timestampMs: j['ts'] as int,
        lang: j['lang'] as String?,
        puzzleId: j['puzzleId'] as String?,
        level: j['level'] as int?,
        isDaily: (j['daily'] as bool?) ?? false,
        dailyVariant: j['variant'] as String?,
        dailyDate: j['date'] as String?,
        perfect: (j['perfect'] as bool?) ?? false,
        mode: j['mode'] == null ? null : PlayMode.fromCode(j['mode'] as String),
        elapsedMs: j['elapsedMs'] as int?,
        parMs: j['parMs'] as int?,
        hintsUsed: (j['hints'] as int?) ?? 0,
        wordsSolved: (j['words'] as int?) ?? 0,
        coins: (j['coins'] as int?) ?? 0,
        completedPack: (j['pack'] as bool?) ?? false,
        localHour: j['hour'] as int?,
      );
}
