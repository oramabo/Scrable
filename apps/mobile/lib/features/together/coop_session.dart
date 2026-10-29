import 'dart:async';

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../meta/game_events_controller.dart';
import '../puzzle/application/puzzle_controller.dart';
import '../puzzle/application/puzzle_session.dart';
import 'multiplayer_models.dart';
import 'multiplayer_providers.dart';

/// A letter another member just placed: tinted with their colour for a second.
class RemoteMark {
  const RemoteMark({required this.cell, required this.color, required this.atMs});
  final int cell;
  final int color;
  final int atMs;
}

class CoopSessionState {
  const CoopSessionState({this.room, this.marks = const {}, this.finishing = false, this.error});

  final CoopRoomDoc? room;

  /// cell → fresh remote letter (cleared after ~1 s).
  final Map<int, RemoteMark> marks;
  final bool finishing;
  final String? error;

  bool get finished => room?.isFinished ?? false;

  /// Other members' cursors: cell → colour index.
  Map<int, int> cursorsExcept(String? uid) {
    final out = <int, int>{};
    final r = room;
    if (r == null) return out;
    for (final e in r.members.entries) {
      final c = e.value.cursor;
      if (e.key == uid || c == null) continue;
      out[c] = e.value.color;
    }
    return out;
  }

  CoopSessionState copyWith({CoopRoomDoc? room, Map<int, RemoteMark>? marks, bool? finishing, String? error}) => CoopSessionState(
        room: room ?? this.room,
        marks: marks ?? this.marks,
        finishing: finishing ?? this.finishing,
        error: error ?? this.error,
      );
}

/// Shares one grid between room members: merges `cells/{index}` documents into
/// the local session, writes the player's own letters, publishes the cursor
/// (throttled to 1 s) and lets the host confirm completion.
class CoopSessionController extends Notifier<CoopSessionState> {
  CoopSessionController(this.sessionId) : key = SessionKey.parse(sessionId);

  final String sessionId;
  final SessionKey key;

  static const markDuration = Duration(milliseconds: 1000);

  final Map<int, int?> _applied = {};
  final Map<int, int?> _knownCells = {};
  int _lastCursorMs = -1 << 40;
  int? _pendingCursor;
  int? _sentCursor;
  Timer? _cursorTimer;
  Timer? _markTimer;
  bool _xpRecorded = false;

  String get roomId => key.roomId!;
  String? get _uid => ref.read(multiplayerServiceProvider).uid;

  @override
  CoopSessionState build() {
    ref.onDispose(() {
      _cursorTimer?.cancel();
      _markTimer?.cancel();
    });

    ref.listen(roomStreamProvider(roomId), (prev, next) {
      final r = next.value;
      if (r != null) _onRoom(r);
    });
    ref.listen(roomCellsProvider(roomId), (prev, next) {
      final cells = next.value;
      if (cells != null) _mergeCells(cells);
    });
    ref.listen(puzzleSessionProvider(sessionId), (prev, next) {
      final s = next.value;
      if (s != null) _onSession(prev?.value, s);
    });

    // Values already present when the controller starts.
    final room = ref.read(roomStreamProvider(roomId)).value;
    final cells = ref.read(roomCellsProvider(roomId)).value;
    final session = ref.read(puzzleSessionProvider(sessionId)).value;
    Future.microtask(() {
      if (!ref.mounted) return;
      if (room != null) _onRoom(room);
      if (cells != null) _mergeCells(cells);
      if (session != null) _onSession(null, session);
    });
    return CoopSessionState(room: room);
  }

  void _onRoom(CoopRoomDoc r) {
    state = state.copyWith(room: r);
    if (r.solved && !_xpRecorded) {
      _xpRecorded = true;
      ref.read(metaProvider.notifier).recordCoopFinished(r.id);
    }
  }

  void _onSession(PuzzleSession? prev, PuzzleSession s) {
    _publishOwnChanges(prev, s);
    _flushPending();
    final cursor = s.selection?.cell;
    if (cursor != _sentCursor) _publishCursor(cursor);
  }

  // ------------------------------------------------------------- inbound

  void _mergeCells(List<CoopCell> cells) {
    final uid = _uid;
    final room = state.room;
    var marks = state.marks;
    final now = ref.read(clockProvider).nowMs;
    for (final c in cells) {
      if (c.index < 0 || c.by == uid) continue;
      if (_knownCells.containsKey(c.index) && _knownCells[c.index] == c.symbol) continue;
      _knownCells[c.index] = c.symbol;
      _pending[c.index] = c.symbol;
      // Letters placed while we watch are highlighted; the first snapshot
      // (letters already on the grid when we joined) is not.
      if (_firstSnapshotSeen && c.symbol != null) {
        final color = room?.members[c.by]?.color ?? 1;
        marks = {...marks, c.index: RemoteMark(cell: c.index, color: color, atMs: now)};
      }
    }
    _firstSnapshotSeen = true;
    _flushPending();
    if (!identical(marks, state.marks)) {
      state = state.copyWith(marks: marks);
      _scheduleMarkSweep();
    }
  }

  /// Remote letters waiting for the puzzle session to finish loading.
  final Map<int, int?> _pending = {};

  void _flushPending() {
    if (_pending.isEmpty) return;
    if (ref.read(puzzleSessionProvider(sessionId)).value == null) return;
    final controller = ref.read(puzzleSessionProvider(sessionId).notifier);
    final batch = Map<int, int?>.from(_pending);
    _pending.clear();
    for (final e in batch.entries) {
      _applied[e.key] = e.value;
      controller.applyRemoteLetter(e.key, e.value);
    }
  }

  bool _firstSnapshotSeen = false;

  void _scheduleMarkSweep() {
    if (_markTimer != null || !ref.read(uiTimersEnabledProvider)) return;
    _markTimer = Timer(markDuration + const Duration(milliseconds: 50), () {
      _markTimer = null;
      final now = ref.read(clockProvider).nowMs;
      final keep = {for (final e in state.marks.entries) if (now - e.value.atMs < markDuration.inMilliseconds) e.key: e.value};
      state = state.copyWith(marks: keep);
      if (keep.isNotEmpty) _scheduleMarkSweep();
    });
  }

  // ------------------------------------------------------------ outbound

  void _publishOwnChanges(PuzzleSession? prev, PuzzleSession next) {
    final service = ref.read(multiplayerServiceProvider);
    final cells = next.progress.cells;
    for (var i = 0; i < cells.length; i++) {
      final e = cells[i];
      if (e == null) continue;
      final symbol = e.pencil ? null : e.symbol;
      final before = prev == null ? null : prev.progress.cells[i];
      final beforeSymbol = before == null || before.pencil ? null : before.symbol;
      if (symbol == beforeSymbol && prev != null) continue;
      if (prev == null && symbol == null) continue;
      // Echo of a remote letter we just applied: nothing to publish.
      if (_applied.containsKey(i) && _applied[i] == symbol) {
        _applied.remove(i);
        continue;
      }
      if (_knownCells[i] == symbol && symbol != null) continue;
      _knownCells[i] = symbol;
      unawaited(service.writeCell(roomId, i, symbol));
    }
  }

  void _publishCursor(int? cell) {
    final now = ref.read(clockProvider).nowMs;
    final elapsed = now - _lastCursorMs;
    if (elapsed >= 1000) {
      _lastCursorMs = now;
      _sentCursor = cell;
      _pendingCursor = null;
      unawaited(ref.read(multiplayerServiceProvider).updateCursor(roomId, cell));
      return;
    }
    _pendingCursor = cell;
    if (_cursorTimer != null || !ref.read(uiTimersEnabledProvider)) return;
    _cursorTimer = Timer(Duration(milliseconds: 1000 - elapsed), () {
      _cursorTimer = null;
      final c = _pendingCursor;
      if (c != _sentCursor) _publishCursor(c);
    });
  }

  /// Host only: confirms the solved grid; the server rewards every member.
  Future<FinishRoomResult?> finish() async {
    final s = ref.read(puzzleSessionProvider(sessionId)).value;
    if (s == null) return null;
    state = state.copyWith(finishing: true);
    try {
      return await ref.read(multiplayerServiceProvider).finishCoopRoom(roomId: roomId, solutionHash: PuzzleCodec.solutionHash(s.puzzle));
    } catch (e) {
      debugPrint('finishCoopRoom failed: $e');
      state = state.copyWith(error: '$e');
      return null;
    } finally {
      state = state.copyWith(finishing: false);
    }
  }

  Future<void> leave() async {
    try {
      await ref.read(multiplayerServiceProvider).leaveCoopRoom(roomId);
    } catch (e) {
      debugPrint('leaveCoopRoom failed: $e');
    }
  }
}

final coopSessionProvider = NotifierProvider.autoDispose.family<CoopSessionController, CoopSessionState, String>(
  CoopSessionController.new,
);
