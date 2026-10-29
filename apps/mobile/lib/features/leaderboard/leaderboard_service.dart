import 'package:chetz_core/chetz_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.score,
    required this.elapsedMs,
    this.displayName,
    this.hints = 0,
    this.mode,
    this.rank,
  });

  final String uid;

  /// Server-computed score: time + penalties (lower is better).
  final int score;
  final int elapsedMs;
  final String? displayName;
  final int hints;
  final String? mode;
  final int? rank;

  LeaderboardEntry withRank(int r) =>
      LeaderboardEntry(uid: uid, score: score, elapsedMs: elapsedMs, displayName: displayName, hints: hints, mode: mode, rank: r);

  static LeaderboardEntry fromJson(String uid, Map<String, dynamic> j) => LeaderboardEntry(
        uid: uid,
        score: (j['score'] as num?)?.toInt() ?? 0,
        elapsedMs: (j['elapsedMs'] as num?)?.toInt() ?? 0,
        displayName: j['displayName'] as String?,
        hints: (j['hints'] as num?)?.toInt() ?? 0,
        mode: j['mode'] as String?,
      );
}

class LeaderboardPage {
  const LeaderboardPage({required this.entries, this.me, this.total});
  final List<LeaderboardEntry> entries;

  /// The player's own entry (with rank) when they submitted.
  final LeaderboardEntry? me;
  final int? total;
}

/// Read-only leaderboard for the hard daily. Null results mean "unavailable"
/// (offline / Firebase disabled), which the UI turns into an empty state.
abstract class LeaderboardService {
  const LeaderboardService();
  bool get available;
  Future<LeaderboardPage?> top({required String lang, required String date, required DailyVariant variant, int limit = 100});
}

class DisabledLeaderboardService extends LeaderboardService {
  const DisabledLeaderboardService();
  @override
  bool get available => false;
  @override
  Future<LeaderboardPage?> top({required String lang, required String date, required DailyVariant variant, int limit = 100}) async => null;
}

class FakeLeaderboardService extends LeaderboardService {
  FakeLeaderboardService({this.page});
  LeaderboardPage? page;
  @override
  bool get available => page != null;
  @override
  Future<LeaderboardPage?> top({required String lang, required String date, required DailyVariant variant, int limit = 100}) async =>
      page;
}

/// `leaderboards/{lang}_{date}_{variant}/entries/{uid}` ordered by `score`.
class FirestoreLeaderboardService extends LeaderboardService {
  FirestoreLeaderboardService({required this.uid, FirebaseFirestore? firestoreClient}) : _firestore = firestoreClient;

  final String? uid;
  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  bool get available => true;

  @override
  Future<LeaderboardPage?> top({required String lang, required String date, required DailyVariant variant, int limit = 100}) async {
    try {
      final col = _db.collection('leaderboards').doc('${lang}_${date}_${variant.code}').collection('entries');
      final snap = await col.orderBy('score').limit(limit).get();
      final entries = <LeaderboardEntry>[];
      var rank = 0;
      LeaderboardEntry? me;
      for (final d in snap.docs) {
        rank++;
        final e = LeaderboardEntry.fromJson(d.id, d.data()).withRank(rank);
        entries.add(e);
        if (d.id == uid) me = e;
      }
      if (me == null && uid != null) {
        final mine = await col.doc(uid).get();
        final data = mine.data();
        if (data != null) {
          final e = LeaderboardEntry.fromJson(uid!, data);
          final better = await col.where('score', isLessThan: e.score).count().get();
          me = e.withRank((better.count ?? 0) + 1);
        }
      }
      final total = await col.count().get();
      return LeaderboardPage(entries: entries, me: me, total: total.count);
    } catch (e) {
      debugPrint('leaderboard failed: $e');
      return null;
    }
  }
}
