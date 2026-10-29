/// Client-side mirrors of the backend's `matches/{id}`, `coopRooms/{id}` and
/// callable results (functions/src/handlers/versus.ts, coop.ts,
/// trophyLeaderboard.ts). Every parser accepts the loosely typed maps that
/// cloud_functions and cloud_firestore hand back.
library;

Map<String, dynamic> asStringMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return {for (final e in v.entries) e.key.toString(): e.value};
  return const {};
}

int? _int(Object? v) => v is num ? v.toInt() : null;
double _double(Object? v) => v is num ? v.toDouble() : 0;

enum MatchStatus {
  waiting,
  ready,
  running,
  finished,
  cancelled;

  static MatchStatus parse(Object? v) => MatchStatus.values.firstWhere((s) => s.name == v, orElse: () => MatchStatus.waiting);
}

enum MatchResult {
  win,
  loss,
  draw,
  forfeit;

  static MatchResult? parse(Object? v) {
    for (final r in MatchResult.values) {
      if (r.name == v) return r;
    }
    return null;
  }
}

/// Coins / XP / season points a server handler credited for a match or room.
class RewardOutcome {
  const RewardOutcome({this.coins = 0, this.xp = 0, this.seasonPoints = 0, this.credited = false, this.capped = false, this.seasonId});
  final int coins;
  final int xp;
  final int seasonPoints;
  final bool credited;
  final bool capped;
  final String? seasonId;

  static RewardOutcome? parse(Object? v) {
    if (v is! Map) return null;
    final m = asStringMap(v);
    return RewardOutcome(
      coins: _int(m['coins']) ?? 0,
      xp: _int(m['xp']) ?? 0,
      seasonPoints: _int(m['seasonPoints']) ?? 0,
      credited: m['credited'] == true,
      capped: m['capped'] == true,
      seasonId: m['seasonId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'coins': coins, 'xp': xp, 'seasonPoints': seasonPoints, 'credited': credited, 'capped': capped, if (seasonId != null) 'seasonId': seasonId};
}

class MatchPlayer {
  const MatchPlayer({
    required this.displayName,
    this.progress = 0,
    this.ready = false,
    this.finishedAt,
    this.elapsedMs,
    this.hintsUsed,
    this.result,
    this.trophyDelta,
    this.trophiesAfter,
    this.rewards,
  });

  final String displayName;

  /// 0..1 share of letter cells filled, as reported by that player's client.
  final double progress;
  final bool ready;
  final int? finishedAt;
  final int? elapsedMs;
  final int? hintsUsed;
  final MatchResult? result;
  final int? trophyDelta;
  final int? trophiesAfter;
  final RewardOutcome? rewards;

  bool get finished => finishedAt != null;

  MatchPlayer copyWith({
    double? progress,
    bool? ready,
    int? finishedAt,
    int? elapsedMs,
    int? hintsUsed,
    MatchResult? result,
    int? trophyDelta,
    int? trophiesAfter,
    RewardOutcome? rewards,
  }) =>
      MatchPlayer(
        displayName: displayName,
        progress: progress ?? this.progress,
        ready: ready ?? this.ready,
        finishedAt: finishedAt ?? this.finishedAt,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        hintsUsed: hintsUsed ?? this.hintsUsed,
        result: result ?? this.result,
        trophyDelta: trophyDelta ?? this.trophyDelta,
        trophiesAfter: trophiesAfter ?? this.trophiesAfter,
        rewards: rewards ?? this.rewards,
      );

  static MatchPlayer fromJson(Object? v) {
    final m = asStringMap(v);
    return MatchPlayer(
      displayName: (m['displayName'] as String?) ?? 'Player',
      progress: _double(m['progress']).clamp(0.0, 1.0),
      ready: m['ready'] == true,
      finishedAt: _int(m['finishedAt']),
      elapsedMs: _int(m['elapsedMs']),
      hintsUsed: _int(m['hintsUsed']),
      result: MatchResult.parse(m['result']),
      trophyDelta: _int(m['trophyDelta']),
      trophiesAfter: _int(m['trophiesAfter']),
      rewards: RewardOutcome.parse(m['rewards']),
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'progress': progress,
        if (ready) 'ready': true,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (hintsUsed != null) 'hintsUsed': hintsUsed,
        if (result != null) 'result': result!.name,
        if (trophyDelta != null) 'trophyDelta': trophyDelta,
        if (trophiesAfter != null) 'trophiesAfter': trophiesAfter,
        if (rewards != null) 'rewards': rewards!.toJson(),
      };
}

class MatchDoc {
  const MatchDoc({
    required this.id,
    required this.lang,
    required this.level,
    required this.puzzleId,
    required this.hostUid,
    required this.players,
    required this.status,
    this.mode = 'invite',
    this.inviteCode,
    this.startedAt,
    this.finishedAt,
    this.closeReason,
  });

  final String id;
  final String lang;
  final int level;
  final String puzzleId;
  final String mode;
  final String? inviteCode;
  final String hostUid;
  final Map<String, MatchPlayer> players;
  final MatchStatus status;
  final int? startedAt;
  final int? finishedAt;
  final String? closeReason;

  bool get isRunning => status == MatchStatus.running && startedAt != null;
  bool get isClosed => status == MatchStatus.finished || status == MatchStatus.cancelled;

  MatchPlayer? player(String? uid) => uid == null ? null : players[uid];
  String? opponentUid(String? uid) {
    for (final k in players.keys) {
      if (k != uid) return k;
    }
    return null;
  }

  MatchPlayer? opponent(String? uid) => players[opponentUid(uid)];

  MatchDoc copyWith({
    Map<String, MatchPlayer>? players,
    MatchStatus? status,
    int? startedAt,
    int? finishedAt,
    String? closeReason,
    String? inviteCode,
  }) =>
      MatchDoc(
        id: id,
        lang: lang,
        level: level,
        puzzleId: puzzleId,
        mode: mode,
        inviteCode: inviteCode ?? this.inviteCode,
        hostUid: hostUid,
        players: players ?? this.players,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        closeReason: closeReason ?? this.closeReason,
      );

  static MatchDoc fromJson(String id, Object? v) {
    final m = asStringMap(v);
    final players = asStringMap(m['players']);
    return MatchDoc(
      id: id,
      lang: (m['lang'] as String?) ?? 'he',
      level: _int(m['level']) ?? 1,
      puzzleId: (m['puzzleId'] as String?) ?? '',
      mode: (m['mode'] as String?) ?? 'invite',
      inviteCode: m['inviteCode'] as String?,
      hostUid: (m['hostUid'] as String?) ?? '',
      players: {for (final e in players.entries) e.key: MatchPlayer.fromJson(e.value)},
      status: MatchStatus.parse(m['status']),
      startedAt: _int(m['startedAt']),
      finishedAt: _int(m['finishedAt']),
      closeReason: m['closeReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'level': level,
        'puzzleId': puzzleId,
        'mode': mode,
        'inviteCode': inviteCode,
        'hostUid': hostUid,
        'players': {for (final e in players.entries) e.key: e.value.toJson()},
        'status': status.name,
        if (startedAt != null) 'startedAt': startedAt,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (closeReason != null) 'closeReason': closeReason,
      };
}

class FindMatchResult {
  const FindMatchResult.queued() : queued = true, match = null;
  const FindMatchResult.matched(this.match) : queued = false;
  final bool queued;
  final MatchDoc? match;
}

class FinishMatchResult {
  const FinishMatchResult({required this.status, required this.result, required this.elapsedMs, required this.opponentFinished, this.player});
  final MatchStatus status;
  final MatchResult? result;
  final int elapsedMs;
  final bool opponentFinished;
  final MatchPlayer? player;

  static FinishMatchResult fromJson(Object? v) {
    final m = asStringMap(v);
    return FinishMatchResult(
      status: MatchStatus.parse(m['status']),
      result: MatchResult.parse(m['result']),
      elapsedMs: _int(m['elapsedMs']) ?? 0,
      opponentFinished: m['opponentFinished'] == true,
      player: m['player'] == null ? null : MatchPlayer.fromJson(m['player']),
    );
  }
}

class TrophyEntry {
  const TrophyEntry({required this.uid, required this.displayName, required this.trophies, required this.rank});
  final String uid;
  final String displayName;
  final int trophies;
  final int rank;

  static TrophyEntry fromJson(Object? v) {
    final m = asStringMap(v);
    return TrophyEntry(
      uid: (m['uid'] as String?) ?? '',
      displayName: (m['displayName'] as String?) ?? 'Player',
      trophies: _int(m['trophies']) ?? 0,
      rank: _int(m['rank']) ?? 0,
    );
  }
}

class TrophyBoard {
  const TrophyBoard({required this.entries, this.me});
  final List<TrophyEntry> entries;
  final TrophyEntry? me;

  static TrophyBoard fromJson(Object? v) {
    final m = asStringMap(v);
    return TrophyBoard(
      entries: [for (final e in (m['entries'] as List? ?? const [])) TrophyEntry.fromJson(e)],
      me: m['me'] == null ? null : TrophyEntry.fromJson(m['me']),
    );
  }
}

// --------------------------------------------------------------------- co-op

enum RoomStatus {
  open,
  running,
  finished;

  static RoomStatus parse(Object? v) => RoomStatus.values.firstWhere((s) => s.name == v, orElse: () => RoomStatus.open);
}

class RoomMember {
  const RoomMember({required this.displayName, required this.color, this.cursor, this.lastSeenAt = 0, this.joinedAt = 0, this.rewards});
  final String displayName;

  /// 0..3, unique in the room; colours cursors and freshly placed letters.
  final int color;
  final int? cursor;
  final int lastSeenAt;
  final int joinedAt;
  final RewardOutcome? rewards;

  RoomMember copyWith({int? cursor, bool clearCursor = false, int? lastSeenAt, RewardOutcome? rewards}) => RoomMember(
        displayName: displayName,
        color: color,
        cursor: clearCursor ? null : (cursor ?? this.cursor),
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        joinedAt: joinedAt,
        rewards: rewards ?? this.rewards,
      );

  static RoomMember fromJson(Object? v) {
    final m = asStringMap(v);
    return RoomMember(
      displayName: (m['displayName'] as String?) ?? 'Player',
      color: _int(m['color']) ?? 0,
      cursor: _int(m['cursor']),
      lastSeenAt: _int(m['lastSeenAt']) ?? 0,
      joinedAt: _int(m['joinedAt']) ?? 0,
      rewards: RewardOutcome.parse(m['rewards']),
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'color': color,
        'cursor': cursor,
        'lastSeenAt': lastSeenAt,
        'joinedAt': joinedAt,
        if (rewards != null) 'rewards': rewards!.toJson(),
      };
}

class CoopRoomDoc {
  const CoopRoomDoc({
    required this.id,
    required this.lang,
    required this.puzzleId,
    required this.hostUid,
    required this.members,
    required this.status,
    this.code,
    this.createdAt = 0,
    this.startedAt,
    this.finishedAt,
    this.finishReason,
  });

  final String id;
  final String lang;
  final String puzzleId;
  final String hostUid;
  final String? code;
  final Map<String, RoomMember> members;
  final RoomStatus status;
  final int createdAt;
  final int? startedAt;
  final int? finishedAt;
  final String? finishReason;

  bool get isRunning => status == RoomStatus.running;
  bool get isFinished => status == RoomStatus.finished;
  bool get solved => isFinished && finishReason == 'solved';

  /// Members sorted by join time (stable colours / avatar order).
  List<MapEntry<String, RoomMember>> get orderedMembers =>
      members.entries.toList()..sort((a, b) => a.value.joinedAt != b.value.joinedAt ? a.value.joinedAt.compareTo(b.value.joinedAt) : a.key.compareTo(b.key));

  CoopRoomDoc copyWith({
    Map<String, RoomMember>? members,
    RoomStatus? status,
    String? hostUid,
    int? startedAt,
    int? finishedAt,
    String? finishReason,
  }) =>
      CoopRoomDoc(
        id: id,
        lang: lang,
        puzzleId: puzzleId,
        hostUid: hostUid ?? this.hostUid,
        code: code,
        members: members ?? this.members,
        status: status ?? this.status,
        createdAt: createdAt,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        finishReason: finishReason ?? this.finishReason,
      );

  static CoopRoomDoc fromJson(String id, Object? v) {
    final m = asStringMap(v);
    final members = asStringMap(m['members']);
    return CoopRoomDoc(
      id: id,
      lang: (m['lang'] as String?) ?? 'he',
      puzzleId: (m['puzzleId'] as String?) ?? '',
      hostUid: (m['hostUid'] as String?) ?? '',
      code: m['code'] as String?,
      members: {for (final e in members.entries) e.key: RoomMember.fromJson(e.value)},
      status: RoomStatus.parse(m['status']),
      createdAt: _int(m['createdAt']) ?? 0,
      startedAt: _int(m['startedAt']),
      finishedAt: _int(m['finishedAt']),
      finishReason: m['finishReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'puzzleId': puzzleId,
        'hostUid': hostUid,
        'code': code,
        'members': {for (final e in members.entries) e.key: e.value.toJson()},
        'status': status.name,
        'createdAt': createdAt,
        if (startedAt != null) 'startedAt': startedAt,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (finishReason != null) 'finishReason': finishReason,
      };
}

/// One shared grid cell: `coopRooms/{roomId}/cells/{cellIndex}`.
class CoopCell {
  const CoopCell({required this.index, required this.symbol, required this.by, required this.at});
  final int index;

  /// Null = cleared.
  final int? symbol;
  final String by;
  final int at;

  static CoopCell fromJson(String docId, Object? v) {
    final m = asStringMap(v);
    return CoopCell(index: int.tryParse(docId) ?? -1, symbol: _int(m['symbol']), by: (m['by'] as String?) ?? '', at: _int(m['at']) ?? 0);
  }

  Map<String, dynamic> toJson() => {'symbol': symbol, 'by': by, 'at': at};
}

class FinishRoomResult {
  const FinishRoomResult({required this.status, required this.rewarded, required this.members});
  final RoomStatus status;
  final bool rewarded;
  final Map<String, RewardOutcome> members;

  static FinishRoomResult fromJson(Object? v) {
    final m = asStringMap(v);
    final members = asStringMap(m['members']);
    return FinishRoomResult(
      status: RoomStatus.parse(m['status']),
      rewarded: m['rewarded'] == true,
      members: {for (final e in members.entries) e.key: RewardOutcome.parse(e.value) ?? const RewardOutcome()},
    );
  }
}

/// Normalises a typed invite code the way the server does: trimmed,
/// upper-cased, spaces and dashes dropped; null unless six alphanumerics.
String? normalizeInviteCode(String? input) {
  if (input == null) return null;
  final code = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) ? code : null;
}
