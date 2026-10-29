import 'dart:async';

import 'package:chetz_core/meta.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'multiplayer_models.dart';

class MultiplayerException implements Exception {
  const MultiplayerException(this.code, [this.message = '']);
  final String code;
  final String message;
  @override
  String toString() => 'MultiplayerException($code: $message)';
}

/// Versus matches and co-op rooms on the deployed backend (callables +
/// Firestore listeners). Disabled unless Firebase is on and the player is
/// signed in; the fake implementation drives widget tests.
abstract class MultiplayerService {
  const MultiplayerService();

  bool get enabled;
  String? get uid;

  // ------------------------------------------------------------- versus
  Future<MatchDoc> createMatch({required String lang, required int level, String? puzzleId});
  Future<MatchDoc> joinMatch(String inviteCode);
  Future<FindMatchResult> findMatch({required String lang, required int level});

  /// Emits the match id once the queue entry `matchQueue/{lang}_{level}/entries/{uid}`
  /// is matched.
  Stream<String?> watchQueue({required String lang, required int level});
  Stream<MatchDoc?> watchMatch(String matchId);
  Future<void> startMatch(String matchId);
  Future<void> reportProgress(String matchId, double progress);
  Future<FinishMatchResult> finishMatch({required String matchId, required int elapsedMs, required int hintsUsed, String? solutionHash});
  Future<void> leaveMatch(String matchId);
  Future<void> cancelMatch(String matchId);
  Future<TrophyBoard?> trophyLeaderboard({required String lang, int limit = 50});

  // -------------------------------------------------------------- co-op
  Future<CoopRoomDoc> createCoopRoom({required String lang, required String puzzleId});
  Future<CoopRoomDoc> joinCoopRoom(String code);
  Stream<CoopRoomDoc?> watchRoom(String roomId);
  Stream<List<CoopCell>> watchCells(String roomId);
  Future<void> startCoopRoom(String roomId);
  Future<void> writeCell(String roomId, int cell, int? symbol);
  Future<void> updateCursor(String roomId, int? cell);
  Future<FinishRoomResult> finishCoopRoom({required String roomId, String? solutionHash});
  Future<void> leaveCoopRoom(String roomId);
}

class DisabledMultiplayerService extends MultiplayerService {
  const DisabledMultiplayerService();

  Never _off() => throw const MultiplayerException('disabled', 'multiplayer needs Firebase');

  @override
  bool get enabled => false;
  @override
  String? get uid => null;
  @override
  Future<MatchDoc> createMatch({required String lang, required int level, String? puzzleId}) async => _off();
  @override
  Future<MatchDoc> joinMatch(String inviteCode) async => _off();
  @override
  Future<FindMatchResult> findMatch({required String lang, required int level}) async => _off();
  @override
  Stream<String?> watchQueue({required String lang, required int level}) => const Stream.empty();
  @override
  Stream<MatchDoc?> watchMatch(String matchId) => const Stream.empty();
  @override
  Future<void> startMatch(String matchId) async {}
  @override
  Future<void> reportProgress(String matchId, double progress) async {}
  @override
  Future<FinishMatchResult> finishMatch({required String matchId, required int elapsedMs, required int hintsUsed, String? solutionHash}) async => _off();
  @override
  Future<void> leaveMatch(String matchId) async {}
  @override
  Future<void> cancelMatch(String matchId) async {}
  @override
  Future<TrophyBoard?> trophyLeaderboard({required String lang, int limit = 50}) async => null;
  @override
  Future<CoopRoomDoc> createCoopRoom({required String lang, required String puzzleId}) async => _off();
  @override
  Future<CoopRoomDoc> joinCoopRoom(String code) async => _off();
  @override
  Stream<CoopRoomDoc?> watchRoom(String roomId) => const Stream.empty();
  @override
  Stream<List<CoopCell>> watchCells(String roomId) => const Stream.empty();
  @override
  Future<void> startCoopRoom(String roomId) async {}
  @override
  Future<void> writeCell(String roomId, int cell, int? symbol) async {}
  @override
  Future<void> updateCursor(String roomId, int? cell) async {}
  @override
  Future<FinishRoomResult> finishCoopRoom({required String roomId, String? solutionHash}) async => _off();
  @override
  Future<void> leaveCoopRoom(String roomId) async {}
}

/// In-memory backend with the server's rules (functions/src/handlers) and
/// knobs to play the opponent / other members: `simulate*` methods.
class FakeMultiplayerService extends MultiplayerService {
  FakeMultiplayerService({
    this.uid = 'me',
    this.opponentUid = 'rival',
    this.opponentName = 'נועה',
    this.puzzleIdFor,
    int Function()? now,
    this.autoMatch = false,
    this.myTrophies = 100,
    this.theirTrophies = 100,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  @override
  final String uid;
  final String opponentUid;
  final String opponentName;

  /// Picks the puzzle of a match / room for (lang, level); defaults to pack 1 puzzle 1.
  final String Function(String lang, int level)? puzzleIdFor;
  final int Function() _now;

  /// `findMatch` returns a ready match immediately instead of queueing.
  bool autoMatch;
  int myTrophies;
  int theirTrophies;
  String myDisplayName = 'את/ה';

  final Map<String, MatchDoc> matches = {};
  final Map<String, CoopRoomDoc> rooms = {};
  final Map<String, Map<int, CoopCell>> cells = {};
  final Map<String, StreamController<MatchDoc?>> _matchStreams = {};
  final Map<String, StreamController<CoopRoomDoc?>> _roomStreams = {};
  final Map<String, StreamController<List<CoopCell>>> _cellStreams = {};
  final StreamController<String?> _queue = StreamController<String?>.broadcast();
  final List<double> reportedProgress = [];
  final List<String> calls = [];
  int _ids = 0;
  String? queuedKey;

  @override
  bool get enabled => true;

  String _newId(String prefix) => '$prefix${++_ids}';
  String _puzzle(String lang, int level) => puzzleIdFor?.call(lang, level) ?? '$lang-l$level-p01-01';

  StreamController<MatchDoc?> _matchStream(String id) => _matchStreams.putIfAbsent(id, () => StreamController<MatchDoc?>.broadcast());
  StreamController<CoopRoomDoc?> _roomStream(String id) => _roomStreams.putIfAbsent(id, () => StreamController<CoopRoomDoc?>.broadcast());
  StreamController<List<CoopCell>> _cellStream(String id) => _cellStreams.putIfAbsent(id, () => StreamController<List<CoopCell>>.broadcast());

  void _putMatch(MatchDoc m) {
    matches[m.id] = m;
    _matchStream(m.id).add(m);
  }

  void _putRoom(CoopRoomDoc r) {
    rooms[r.id] = r;
    _roomStream(r.id).add(r);
  }

  MatchDoc _match(String id) {
    final m = matches[id];
    if (m == null) throw const MultiplayerException('not-found');
    return m;
  }

  CoopRoomDoc _room(String id) {
    final r = rooms[id];
    if (r == null) throw const MultiplayerException('not-found');
    return r;
  }

  // ------------------------------------------------------------- versus

  @override
  Future<MatchDoc> createMatch({required String lang, required int level, String? puzzleId}) async {
    calls.add('createMatch');
    final id = _newId('m');
    final m = MatchDoc(
      id: id,
      lang: lang,
      level: level,
      puzzleId: puzzleId ?? _puzzle(lang, level),
      hostUid: uid,
      inviteCode: 'ABC12${_ids % 10}',
      players: {uid: MatchPlayer(displayName: myDisplayName)},
      status: MatchStatus.waiting,
    );
    _putMatch(m);
    return m;
  }

  @override
  Future<MatchDoc> joinMatch(String inviteCode) async {
    calls.add('joinMatch');
    final code = normalizeInviteCode(inviteCode);
    for (final m in matches.values) {
      if (m.inviteCode == code && m.status == MatchStatus.waiting) {
        final joined = m.copyWith(players: {...m.players, uid: MatchPlayer(displayName: myDisplayName)}, status: MatchStatus.ready);
        _putMatch(joined);
        return joined;
      }
    }
    throw const MultiplayerException('not-found', 'this invite code is not valid any more');
  }

  /// A match hosted by the opponent that the player joins by code.
  MatchDoc simulateHostedMatch({String lang = 'he', int level = 1, String code = 'ZZZ999'}) {
    final id = _newId('m');
    final m = MatchDoc(
      id: id,
      lang: lang,
      level: level,
      puzzleId: _puzzle(lang, level),
      hostUid: opponentUid,
      inviteCode: code,
      players: {opponentUid: MatchPlayer(displayName: opponentName)},
      status: MatchStatus.waiting,
    );
    _putMatch(m);
    return m;
  }

  @override
  Future<FindMatchResult> findMatch({required String lang, required int level}) async {
    calls.add('findMatch');
    if (autoMatch) {
      final id = _newId('m');
      final m = MatchDoc(
        id: id,
        lang: lang,
        level: level,
        puzzleId: _puzzle(lang, level),
        mode: 'random',
        hostUid: opponentUid,
        players: {opponentUid: MatchPlayer(displayName: opponentName), uid: MatchPlayer(displayName: myDisplayName)},
        status: MatchStatus.ready,
      );
      _putMatch(m);
      return FindMatchResult.matched(m);
    }
    queuedKey = '${lang}_$level';
    return const FindMatchResult.queued();
  }

  /// Somebody popped the player's queue entry: a ready match appears.
  MatchDoc simulateQueueMatched({String lang = 'he', int level = 1}) {
    final id = _newId('m');
    final m = MatchDoc(
      id: id,
      lang: lang,
      level: level,
      puzzleId: _puzzle(lang, level),
      mode: 'random',
      hostUid: opponentUid,
      players: {opponentUid: MatchPlayer(displayName: opponentName), uid: MatchPlayer(displayName: myDisplayName)},
      status: MatchStatus.ready,
    );
    _putMatch(m);
    queuedKey = null;
    _queue.add(id);
    return m;
  }

  @override
  Stream<String?> watchQueue({required String lang, required int level}) => _queue.stream;

  @override
  Stream<MatchDoc?> watchMatch(String matchId) async* {
    yield matches[matchId];
    yield* _matchStream(matchId).stream;
  }

  void simulateOpponentJoin(String matchId) {
    final m = _match(matchId);
    _putMatch(m.copyWith(players: {...m.players, opponentUid: MatchPlayer(displayName: opponentName)}, status: MatchStatus.ready));
  }

  @override
  Future<void> startMatch(String matchId) async {
    calls.add('startMatch');
    final m = _match(matchId);
    if (m.status == MatchStatus.running) return;
    if (m.status != MatchStatus.ready) throw MultiplayerException('failed-precondition', 'match is ${m.status.name}');
    final players = {...m.players, uid: m.players[uid]!.copyWith(ready: true)};
    final everyoneReady = players.values.every((p) => p.ready);
    if (uid == m.hostUid || everyoneReady) {
      _putMatch(m.copyWith(players: players, status: MatchStatus.running, startedAt: _now()));
    } else {
      _putMatch(m.copyWith(players: players));
    }
  }

  /// The opponent (guest) presses ready; the host (me) must still start.
  void simulateOpponentReady(String matchId) {
    final m = _match(matchId);
    final p = m.players[opponentUid];
    if (p == null) return;
    _putMatch(m.copyWith(players: {...m.players, opponentUid: p.copyWith(ready: true)}));
  }

  /// The opponent hosts and starts the match.
  void simulateHostStart(String matchId) {
    final m = _match(matchId);
    _putMatch(m.copyWith(status: MatchStatus.running, startedAt: _now()));
  }

  @override
  Future<void> reportProgress(String matchId, double progress) async {
    calls.add('reportProgress');
    reportedProgress.add(progress);
    final m = _match(matchId);
    if (m.status != MatchStatus.running) return;
    _putMatch(m.copyWith(players: {...m.players, uid: m.players[uid]!.copyWith(progress: progress)}));
  }

  void simulateOpponentProgress(String matchId, double progress) {
    final m = _match(matchId);
    final p = m.players[opponentUid];
    if (p == null) return;
    _putMatch(m.copyWith(players: {...m.players, opponentUid: p.copyWith(progress: progress)}));
  }

  MatchDoc _settle(MatchDoc m, Map<String, MatchResult> results, String reason) {
    final players = Map<String, MatchPlayer>.from(m.players);
    for (final e in results.entries) {
      final mine = e.key == uid ? myTrophies : theirTrophies;
      final theirs = e.key == uid ? theirTrophies : myTrophies;
      final delta = switch (e.value) {
        MatchResult.win => Trophies.winDelta(mine, theirs),
        MatchResult.loss || MatchResult.forfeit => Trophies.lossDelta(mine, theirs),
        MatchResult.draw => 0,
      };
      final finished = players[e.key]!.finished;
      final rewards = (e.value == MatchResult.win || e.value == MatchResult.loss) && finished
          ? RewardOutcome(
              coins: e.value == MatchResult.win ? 40 : 10,
              xp: e.value == MatchResult.win ? XpCurve.matchWinXp : XpCurve.matchLossXp,
              seasonPoints: e.value == MatchResult.win ? SeasonPass.pointsMatchWin : SeasonPass.pointsMatchLoss,
              credited: true,
            )
          : const RewardOutcome();
      players[e.key] = players[e.key]!.copyWith(
        result: e.value,
        trophyDelta: delta,
        trophiesAfter: Trophies.applyDelta(mine, delta),
        rewards: rewards,
      );
      if (e.key == uid) myTrophies = Trophies.applyDelta(mine, delta);
    }
    final closed = m.copyWith(players: players, status: MatchStatus.finished, finishedAt: _now(), closeReason: reason);
    _putMatch(closed);
    return closed;
  }

  @override
  Future<FinishMatchResult> finishMatch({required String matchId, required int elapsedMs, required int hintsUsed, String? solutionHash}) async {
    calls.add('finishMatch');
    var m = _match(matchId);
    final me = m.players[uid]!;
    if (me.finished) {
      return FinishMatchResult(status: m.status, result: me.result, elapsedMs: me.elapsedMs ?? 0, opponentFinished: m.opponent(uid)?.finished ?? false, player: me);
    }
    if (m.status != MatchStatus.running) throw MultiplayerException('failed-precondition', 'match is ${m.status.name}');
    final now = _now();
    final serverElapsed = now - (m.startedAt ?? now);
    m = m.copyWith(players: {...m.players, uid: me.copyWith(finishedAt: now, elapsedMs: serverElapsed, hintsUsed: hintsUsed, progress: 1)});
    final other = m.opponent(uid);
    final otherUid = m.opponentUid(uid);
    if (other != null && otherUid != null && other.finished) {
      final tie = (other.elapsedMs ?? 0) == serverElapsed;
      m = _settle(m, tie ? {uid: MatchResult.draw, otherUid: MatchResult.draw} : {uid: MatchResult.loss, otherUid: MatchResult.win}, 'both_finished');
    } else {
      _putMatch(m);
    }
    final mine = m.players[uid]!;
    return FinishMatchResult(status: m.status, result: mine.result, elapsedMs: serverElapsed, opponentFinished: other?.finished ?? false, player: mine);
  }

  /// The opponent finishes now; settles the match when the player already has.
  void simulateOpponentFinish(String matchId, {int? elapsedMs}) {
    var m = _match(matchId);
    final other = m.players[opponentUid];
    if (other == null || other.finished) return;
    final now = _now();
    final elapsed = elapsedMs ?? (now - (m.startedAt ?? now));
    m = m.copyWith(players: {...m.players, opponentUid: other.copyWith(finishedAt: now, elapsedMs: elapsed, progress: 1)});
    final me = m.players[uid];
    if (me != null && me.finished) {
      final tie = (me.elapsedMs ?? 0) == elapsed;
      _settle(m, tie ? {uid: MatchResult.draw, opponentUid: MatchResult.draw} : {uid: MatchResult.win, opponentUid: MatchResult.loss}, 'both_finished');
    } else {
      _putMatch(m);
    }
  }

  @override
  Future<void> leaveMatch(String matchId) async {
    calls.add('leaveMatch');
    final m = _match(matchId);
    if (m.isClosed) return;
    if (m.status == MatchStatus.waiting || m.status == MatchStatus.ready) {
      _putMatch(m.copyWith(status: MatchStatus.cancelled, finishedAt: _now(), closeReason: 'cancelled'));
      return;
    }
    if (m.players[uid]?.finished ?? false) return;
    final otherUid = m.opponentUid(uid);
    _settle(m, {uid: MatchResult.forfeit, ?otherUid: MatchResult.win}, 'forfeit');
  }

  @override
  Future<void> cancelMatch(String matchId) async {
    calls.add('cancelMatch');
    final m = _match(matchId);
    if (m.isClosed) return;
    _putMatch(m.copyWith(status: MatchStatus.cancelled, finishedAt: _now(), closeReason: 'cancelled'));
  }

  TrophyBoard? board;

  @override
  Future<TrophyBoard?> trophyLeaderboard({required String lang, int limit = 50}) async => board;

  // -------------------------------------------------------------- co-op

  @override
  Future<CoopRoomDoc> createCoopRoom({required String lang, required String puzzleId}) async {
    calls.add('createCoopRoom');
    final id = _newId('r');
    final now = _now();
    final r = CoopRoomDoc(
      id: id,
      lang: lang,
      puzzleId: puzzleId,
      hostUid: uid,
      code: 'ROOM4${_ids % 10}',
      members: {uid: RoomMember(displayName: myDisplayName, color: 0, joinedAt: now, lastSeenAt: now)},
      status: RoomStatus.open,
      createdAt: now,
    );
    cells[id] = {};
    _putRoom(r);
    return r;
  }

  /// A room hosted by someone else that the player joins by code.
  CoopRoomDoc simulateHostedRoom({String lang = 'he', String? puzzleId, String code = 'JOIN42'}) {
    final id = _newId('r');
    final now = _now();
    final r = CoopRoomDoc(
      id: id,
      lang: lang,
      puzzleId: puzzleId ?? _puzzle(lang, 1),
      hostUid: opponentUid,
      code: code,
      members: {opponentUid: RoomMember(displayName: opponentName, color: 0, joinedAt: now, lastSeenAt: now)},
      status: RoomStatus.open,
      createdAt: now,
    );
    cells[id] = {};
    _putRoom(r);
    return r;
  }

  @override
  Future<CoopRoomDoc> joinCoopRoom(String code) async {
    calls.add('joinCoopRoom');
    final c = normalizeInviteCode(code);
    for (final r in rooms.values) {
      if (r.code == c && !r.isFinished) {
        if (r.members.containsKey(uid)) return r;
        if (r.members.length >= 4) throw const MultiplayerException('failed-precondition', 'room is full');
        final now = _now();
        final used = r.members.values.map((m) => m.color).toSet();
        final color = [0, 1, 2, 3].firstWhere((c) => !used.contains(c), orElse: () => 3);
        final joined = r.copyWith(members: {...r.members, uid: RoomMember(displayName: myDisplayName, color: color, joinedAt: now, lastSeenAt: now)});
        _putRoom(joined);
        return joined;
      }
    }
    throw const MultiplayerException('not-found', 'this room code is not valid any more');
  }

  void simulateMemberJoin(String roomId, {required String memberUid, required String name}) {
    final r = _room(roomId);
    final now = _now();
    final used = r.members.values.map((m) => m.color).toSet();
    final color = [0, 1, 2, 3].firstWhere((c) => !used.contains(c), orElse: () => 3);
    _putRoom(r.copyWith(members: {...r.members, memberUid: RoomMember(displayName: name, color: color, joinedAt: now, lastSeenAt: now)}));
  }

  @override
  Stream<CoopRoomDoc?> watchRoom(String roomId) async* {
    yield rooms[roomId];
    yield* _roomStream(roomId).stream;
  }

  @override
  Stream<List<CoopCell>> watchCells(String roomId) async* {
    yield (cells[roomId] ?? {}).values.toList();
    yield* _cellStream(roomId).stream;
  }

  @override
  Future<void> startCoopRoom(String roomId) async {
    calls.add('startCoopRoom');
    final r = _room(roomId);
    if (r.hostUid != uid) throw const MultiplayerException('permission-denied', 'only the host can start the room');
    if (r.isRunning) return;
    _putRoom(r.copyWith(status: RoomStatus.running, startedAt: _now()));
  }

  void simulateHostStartRoom(String roomId) {
    final r = _room(roomId);
    _putRoom(r.copyWith(status: RoomStatus.running, startedAt: _now()));
  }

  void _setCell(String roomId, CoopCell c) {
    final map = cells.putIfAbsent(roomId, () => {});
    map[c.index] = c;
    _cellStream(roomId).add(map.values.toList());
  }

  @override
  Future<void> writeCell(String roomId, int cell, int? symbol) async {
    calls.add('writeCell');
    _setCell(roomId, CoopCell(index: cell, symbol: symbol, by: uid, at: _now()));
  }

  void simulateRemoteCell(String roomId, int cell, int? symbol, {String? by}) =>
      _setCell(roomId, CoopCell(index: cell, symbol: symbol, by: by ?? opponentUid, at: _now()));

  @override
  Future<void> updateCursor(String roomId, int? cell) async {
    final r = rooms[roomId];
    final me = r?.members[uid];
    if (r == null || me == null) return;
    _putRoom(r.copyWith(members: {...r.members, uid: me.copyWith(cursor: cell, clearCursor: cell == null, lastSeenAt: _now())}));
  }

  void simulateRemoteCursor(String roomId, int? cell, {String? by}) {
    final r = _room(roomId);
    final who = by ?? opponentUid;
    final m = r.members[who];
    if (m == null) return;
    _putRoom(r.copyWith(members: {...r.members, who: m.copyWith(cursor: cell, clearCursor: cell == null, lastSeenAt: _now())}));
  }

  @override
  Future<FinishRoomResult> finishCoopRoom({required String roomId, String? solutionHash}) async {
    calls.add('finishCoopRoom');
    final r = _room(roomId);
    if (r.isFinished) {
      return FinishRoomResult(status: r.status, rewarded: r.finishReason == 'solved', members: {for (final e in r.members.entries) if (e.value.rewards != null) e.key: e.value.rewards!});
    }
    if (r.hostUid != uid) throw const MultiplayerException('permission-denied', 'only the host can confirm completion');
    final rewarded = r.members.length >= 2;
    final members = {
      for (final e in r.members.entries)
        e.key: e.value.copyWith(rewards: rewarded ? const RewardOutcome(coins: 25, xp: 30, credited: true) : const RewardOutcome()),
    };
    _putRoom(r.copyWith(members: members, status: RoomStatus.finished, finishedAt: _now(), finishReason: 'solved'));
    return FinishRoomResult(status: RoomStatus.finished, rewarded: rewarded, members: {for (final e in members.entries) e.key: e.value.rewards!});
  }

  /// The (remote) host confirms completion.
  void simulateHostFinishRoom(String roomId) {
    final r = _room(roomId);
    final rewarded = r.members.length >= 2;
    final members = {
      for (final e in r.members.entries)
        e.key: e.value.copyWith(rewards: rewarded ? const RewardOutcome(coins: 25, xp: 30, credited: true) : const RewardOutcome()),
    };
    _putRoom(r.copyWith(members: members, status: RoomStatus.finished, finishedAt: _now(), finishReason: 'solved'));
  }

  @override
  Future<void> leaveCoopRoom(String roomId) async {
    calls.add('leaveCoopRoom');
    final r = rooms[roomId];
    if (r == null || !r.members.containsKey(uid) || r.isFinished) return;
    final members = Map<String, RoomMember>.from(r.members)..remove(uid);
    if (members.isEmpty) {
      _putRoom(r.copyWith(members: members, status: RoomStatus.finished, finishedAt: _now(), finishReason: 'abandoned'));
    } else {
      _putRoom(r.copyWith(members: members, hostUid: r.hostUid == uid ? members.keys.first : r.hostUid));
    }
  }

  void dispose() {
    for (final c in _matchStreams.values) {
      c.close();
    }
    for (final c in _roomStreams.values) {
      c.close();
    }
    for (final c in _cellStreams.values) {
      c.close();
    }
    _queue.close();
  }
}

/// Callables + Firestore listeners against the deployed backend.
class FirebaseMultiplayerService extends MultiplayerService {
  FirebaseMultiplayerService({required this.uid, FirebaseFunctions? functions, FirebaseFirestore? firestore})
      // ignore: prefer_initializing_formals
      : _functions = functions,
        // ignore: prefer_initializing_formals
        _firestore = firestore;

  @override
  final String uid;
  final FirebaseFunctions? _functions;
  final FirebaseFirestore? _firestore;

  FirebaseFunctions get _fn => _functions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  bool get enabled => true;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _fn.httpsCallable(name).call<Object?>(data);
      return asStringMap(res.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('$name failed: ${e.code} ${e.message}');
      throw MultiplayerException(e.code, e.message ?? '');
    } catch (e) {
      debugPrint('$name failed: $e');
      throw MultiplayerException('unavailable', '$e');
    }
  }

  @override
  Future<MatchDoc> createMatch({required String lang, required int level, String? puzzleId}) async {
    final r = await _call('createMatch', {'lang': lang, 'level': level, 'puzzleId': ?puzzleId});
    return MatchDoc.fromJson(r['matchId'] as String, r['match']).copyWith(inviteCode: r['inviteCode'] as String?);
  }

  @override
  Future<MatchDoc> joinMatch(String inviteCode) async {
    final r = await _call('joinMatch', {'inviteCode': inviteCode});
    return MatchDoc.fromJson(r['matchId'] as String, r['match']);
  }

  @override
  Future<FindMatchResult> findMatch({required String lang, required int level}) async {
    final r = await _call('findMatch', {'lang': lang, 'level': level});
    if (r['queued'] == true) return const FindMatchResult.queued();
    return FindMatchResult.matched(MatchDoc.fromJson(r['matchId'] as String, r['match']));
  }

  @override
  Stream<String?> watchQueue({required String lang, required int level}) => _db
      .collection('matchQueue')
      .doc('${lang}_$level')
      .collection('entries')
      .doc(uid)
      .snapshots()
      .map((s) {
        final data = s.data();
        return data != null && data['status'] == 'matched' ? data['matchId'] as String? : null;
      });

  @override
  Stream<MatchDoc?> watchMatch(String matchId) =>
      _db.collection('matches').doc(matchId).snapshots().map((s) => s.exists ? MatchDoc.fromJson(matchId, s.data()) : null);

  @override
  Future<void> startMatch(String matchId) => _call('startMatch', {'matchId': matchId});

  @override
  Future<void> reportProgress(String matchId, double progress) async {
    try {
      await _call('reportProgress', {'matchId': matchId, 'progress': progress.clamp(0.0, 1.0)});
    } on MultiplayerException catch (e) {
      // Throttled by the server (≥ 1 s) or already finished: not an error for the UI.
      if (e.code != 'resource-exhausted' && e.code != 'failed-precondition') rethrow;
    }
  }

  @override
  Future<FinishMatchResult> finishMatch({required String matchId, required int elapsedMs, required int hintsUsed, String? solutionHash}) async =>
      FinishMatchResult.fromJson(await _call('finishMatch', {
        'matchId': matchId,
        'elapsedMs': elapsedMs,
        'hintsUsed': hintsUsed,
        'solutionHash': ?solutionHash,
      }));

  @override
  Future<void> leaveMatch(String matchId) => _call('leaveMatch', {'matchId': matchId});

  @override
  Future<void> cancelMatch(String matchId) => _call('cancelMatch', {'matchId': matchId});

  @override
  Future<TrophyBoard?> trophyLeaderboard({required String lang, int limit = 50}) async {
    try {
      return TrophyBoard.fromJson(await _call('trophyLeaderboard', {'lang': lang, 'limit': limit}));
    } on MultiplayerException {
      return null;
    }
  }

  @override
  Future<CoopRoomDoc> createCoopRoom({required String lang, required String puzzleId}) async {
    final r = await _call('createCoopRoom', {'lang': lang, 'puzzleId': puzzleId});
    return CoopRoomDoc.fromJson(r['roomId'] as String, r['room']);
  }

  @override
  Future<CoopRoomDoc> joinCoopRoom(String code) async {
    final r = await _call('joinCoopRoom', {'code': code});
    return CoopRoomDoc.fromJson(r['roomId'] as String, r['room']);
  }

  DocumentReference<Map<String, dynamic>> _roomRef(String roomId) => _db.collection('coopRooms').doc(roomId);

  @override
  Stream<CoopRoomDoc?> watchRoom(String roomId) => _roomRef(roomId).snapshots().map((s) => s.exists ? CoopRoomDoc.fromJson(roomId, s.data()) : null);

  @override
  Stream<List<CoopCell>> watchCells(String roomId) =>
      _roomRef(roomId).collection('cells').snapshots().map((q) => [for (final d in q.docs) CoopCell.fromJson(d.id, d.data())]);

  @override
  Future<void> startCoopRoom(String roomId) => _call('startCoopRoom', {'roomId': roomId});

  @override
  Future<void> writeCell(String roomId, int cell, int? symbol) async {
    try {
      await _roomRef(roomId).collection('cells').doc('$cell').set({'symbol': symbol, 'by': uid, 'at': DateTime.now().millisecondsSinceEpoch});
    } catch (e) {
      debugPrint('coop cell write failed: $e');
    }
  }

  @override
  Future<void> updateCursor(String roomId, int? cell) async {
    try {
      await _roomRef(roomId).set({
        'members': {
          uid: {'cursor': cell, 'lastSeenAt': DateTime.now().millisecondsSinceEpoch}
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('coop cursor write failed: $e');
    }
  }

  @override
  Future<FinishRoomResult> finishCoopRoom({required String roomId, String? solutionHash}) async =>
      FinishRoomResult.fromJson(await _call('finishCoopRoom', {'roomId': roomId, 'solutionHash': ?solutionHash}));

  @override
  Future<void> leaveCoopRoom(String roomId) => _call('leaveCoopRoom', {'roomId': roomId});
}
