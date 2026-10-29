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

/// Versus race state next to a solving session: the live match document,
/// both progress values and the player's own finish.
class VersusSessionState {
  const VersusSessionState({
    this.match,
    this.myProgress = 0,
    this.opponentProgress = 0,
    this.finished = false,
    this.finishResult,
    this.error,
  });

  final MatchDoc? match;
  final double myProgress;
  final double opponentProgress;

  /// The player submitted `finishMatch`.
  final bool finished;
  final FinishMatchResult? finishResult;
  final String? error;

  bool get closed => match?.isClosed ?? false;

  VersusSessionState copyWith({
    MatchDoc? match,
    double? myProgress,
    double? opponentProgress,
    bool? finished,
    FinishMatchResult? finishResult,
    String? error,
  }) =>
      VersusSessionState(
        match: match ?? this.match,
        myProgress: myProgress ?? this.myProgress,
        opponentProgress: opponentProgress ?? this.opponentProgress,
        finished: finished ?? this.finished,
        finishResult: finishResult ?? this.finishResult,
        error: error ?? this.error,
      );
}

/// Glue between the puzzle controller and the match: reports progress at most
/// once a second, submits `finishMatch` on completion (with the solution hash)
/// and mirrors the opponent's progress from the match document.
class VersusSessionController extends Notifier<VersusSessionState> {
  VersusSessionController(this.sessionId) : key = SessionKey.parse(sessionId);

  final String sessionId;
  final SessionKey key;

  int _lastReportMs = -1 << 40;
  double? _pendingProgress;
  Timer? _reportTimer;
  bool _finishing = false;
  bool _resultRecorded = false;

  @override
  VersusSessionState build() {
    final matchId = key.matchId!;
    ref.onDispose(() => _reportTimer?.cancel());

    ref.listen(matchStreamProvider(matchId), (prev, next) {
      final m = next.value;
      if (m != null) _onMatch(m);
    });
    ref.listen(puzzleSessionProvider(sessionId), (prev, next) {
      final s = next.value;
      if (s != null) _onSession(s);
    });

    // Values already present when the controller starts (`ref.listen` only
    // fires on changes, and `state` is not readable inside build).
    final uid = ref.read(multiplayerServiceProvider).uid;
    final match = ref.read(matchStreamProvider(matchId)).value;
    final session = ref.read(puzzleSessionProvider(sessionId)).value;
    Future.microtask(() {
      if (!ref.mounted) return;
      if (match != null) _onMatch(match);
      if (session != null) _onSession(session);
    });
    return VersusSessionState(match: match, opponentProgress: match?.opponent(uid)?.progress ?? 0);
  }

  void _onMatch(MatchDoc m) {
    final uid = ref.read(multiplayerServiceProvider).uid;
    final opp = m.opponent(uid);
    state = state.copyWith(match: m, opponentProgress: opp?.progress ?? state.opponentProgress);
    _maybeRecordResult(m, uid);
  }

  void _onSession(PuzzleSession s) {
    final letters = s.progress.letterCount;
    final fraction = letters == 0 ? 0.0 : s.progress.filledCount / letters;
    if (fraction != state.myProgress) {
      state = state.copyWith(myProgress: fraction);
      _report(fraction);
    }
    if (s.isComplete && !state.finished && !_finishing) unawaited(_finish(s));
  }

  void _report(double fraction) {
    final m = state.match;
    if (m == null || !m.isRunning || state.finished) return;
    final now = ref.read(clockProvider).nowMs;
    final elapsed = now - _lastReportMs;
    if (elapsed >= 1000) {
      _lastReportMs = now;
      _pendingProgress = null;
      unawaited(ref.read(multiplayerServiceProvider).reportProgress(m.id, fraction));
      return;
    }
    // Throttled: keep the latest value and flush it when the second is over.
    _pendingProgress = fraction;
    if (_reportTimer != null || !ref.read(uiTimersEnabledProvider)) return;
    _reportTimer = Timer(Duration(milliseconds: 1000 - elapsed), () {
      _reportTimer = null;
      final p = _pendingProgress;
      if (p != null) _report(p);
    });
  }

  Future<void> _finish(PuzzleSession s) async {
    final m = state.match;
    if (m == null) return;
    _finishing = true;
    _reportTimer?.cancel();
    _reportTimer = null;
    try {
      final result = await ref.read(multiplayerServiceProvider).finishMatch(
            matchId: m.id,
            elapsedMs: s.progress.elapsedMs,
            hintsUsed: s.progress.hintsUsed,
            solutionHash: PuzzleCodec.solutionHash(s.puzzle),
          );
      state = state.copyWith(finished: true, finishResult: result, myProgress: 1);
    } catch (e) {
      debugPrint('finishMatch failed: $e');
      state = state.copyWith(error: '$e');
    } finally {
      _finishing = false;
    }
  }

  /// Mirrors the server's settlement into local XP / season points / trophies.
  void _maybeRecordResult(MatchDoc m, String? uid) {
    if (_resultRecorded || m.status != MatchStatus.finished) return;
    final me = m.player(uid);
    final result = me?.result;
    if (me == null || result == null) return;
    _resultRecorded = true;
    ref.read(metaProvider.notifier).recordMatchResult(
          matchId: m.id,
          won: result == MatchResult.win,
          draw: result == MatchResult.draw,
          trophyDelta: me.trophyDelta ?? 0,
        );
  }

  /// Leaves (forfeits a running match, cancels a lobby).
  Future<void> leave() async {
    final m = state.match;
    if (m == null) return;
    try {
      await ref.read(multiplayerServiceProvider).leaveMatch(m.id);
    } catch (e) {
      debugPrint('leaveMatch failed: $e');
    }
  }
}

final versusSessionProvider = NotifierProvider.autoDispose.family<VersusSessionController, VersusSessionState, String>(
  VersusSessionController.new,
);
