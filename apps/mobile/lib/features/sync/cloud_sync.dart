import 'package:chetz_core/chetz_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../wallet/ledger.dart';

class SyncLedgerResult {
  const SyncLedgerResult({required this.serverBalance, required this.acceptedIds, required this.rejectedIds});
  final int serverBalance;
  final List<String> acceptedIds;
  final List<String> rejectedIds;
}

/// Anonymous-auth cloud sync for progress and the coin ledger, plus the
/// leaderboard submission for the hard daily. Disabled unless
/// `AppConfig.firebaseEnabled` and Firebase initialised successfully.
abstract class CloudSync {
  const CloudSync();

  bool get enabled;
  String? get userId;

  Future<void> initialize();
  Future<void> pushProgress(PuzzleProgress progress);
  Future<PuzzleProgress?> pullProgress(String puzzleId);

  /// Sends pending ledger entries to the `syncLedger` callable.
  Future<SyncLedgerResult?> syncLedger(Ledger ledger);

  /// Submits a completed hard daily to the `submitDaily` callable.
  Future<bool> submitDaily({required Puzzle puzzle, required PuzzleProgress progress});
}

class DisabledCloudSync extends CloudSync {
  const DisabledCloudSync();
  @override
  bool get enabled => false;
  @override
  String? get userId => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pushProgress(PuzzleProgress progress) async {}
  @override
  Future<PuzzleProgress?> pullProgress(String puzzleId) async => null;
  @override
  Future<SyncLedgerResult?> syncLedger(Ledger ledger) async => null;
  @override
  Future<bool> submitDaily({required Puzzle puzzle, required PuzzleProgress progress}) async => false;
}

class FakeCloudSync extends CloudSync {
  final Map<String, PuzzleProgress> pushed = {};
  final List<String> submitted = [];
  int? serverBalance;

  @override
  bool get enabled => true;
  @override
  String? get userId => 'fake-user';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> pushProgress(PuzzleProgress progress) async => pushed[progress.puzzleId] = progress;
  @override
  Future<PuzzleProgress?> pullProgress(String puzzleId) async => pushed[puzzleId];
  @override
  Future<SyncLedgerResult?> syncLedger(Ledger ledger) async => SyncLedgerResult(
        serverBalance: serverBalance ?? ledger.balance,
        acceptedIds: ledger.pendingEntries.map((e) => e.id).toList(),
        rejectedIds: const [],
      );
  @override
  Future<bool> submitDaily({required Puzzle puzzle, required PuzzleProgress progress}) async {
    submitted.add(puzzle.id);
    return true;
  }
}

/// Firestore layout from docs/GAME_PLAN.md §6.5:
/// `users/{uid}/progress/{puzzleId}`, callables `syncLedger`, `submitDaily`.
class FirebaseCloudSync extends CloudSync {
  FirebaseCloudSync({FirebaseAuth? authClient, FirebaseFirestore? firestoreClient, FirebaseFunctions? functionsClient})
      : _auth = authClient,
        _firestore = firestoreClient,
        _functions = functionsClient;

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseFunctions? _functions;
  User? _user;

  @override
  bool get enabled => _user != null;
  @override
  String? get userId => _user?.uid;

  @override
  Future<void> initialize() async {
    try {
      _auth ??= FirebaseAuth.instance;
      _firestore ??= FirebaseFirestore.instance;
      _functions ??= FirebaseFunctions.instance;
      _user = _auth!.currentUser ?? (await _auth!.signInAnonymously()).user;
    } catch (e) {
      debugPrint('cloud sync init failed: $e');
      _user = null;
    }
  }

  DocumentReference<Map<String, dynamic>> _progressDoc(String puzzleId) =>
      _firestore!.collection('users').doc(_user!.uid).collection('progress').doc(puzzleId);

  @override
  Future<void> pushProgress(PuzzleProgress progress) async {
    if (!enabled) return;
    try {
      await _progressDoc(progress.puzzleId).set(progress.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('push progress failed: $e');
    }
  }

  @override
  Future<PuzzleProgress?> pullProgress(String puzzleId) async {
    if (!enabled) return null;
    try {
      final snap = await _progressDoc(puzzleId).get();
      final data = snap.data();
      return data == null ? null : PuzzleProgress.fromJson(data);
    } catch (e) {
      debugPrint('pull progress failed: $e');
      return null;
    }
  }

  @override
  Future<SyncLedgerResult?> syncLedger(Ledger ledger) async {
    if (!enabled) return null;
    try {
      final res = await _functions!.httpsCallable('syncLedger').call<Map<String, dynamic>>({
        'entries': ledger.pendingEntries.map((e) => e.toJson()).toList(),
        'localBalance': ledger.balance,
      });
      final data = res.data;
      return SyncLedgerResult(
        serverBalance: (data['balance'] as num?)?.toInt() ?? ledger.balance,
        acceptedIds: ((data['accepted'] as List?) ?? const []).map((e) => e.toString()).toList(),
        rejectedIds: ((data['rejected'] as List?) ?? const [])
            .map((e) => e is Map ? e['id'].toString() : e.toString())
            .toList(),
      );
    } catch (e) {
      debugPrint('syncLedger failed: $e');
      return null;
    }
  }

  @override
  Future<bool> submitDaily({required Puzzle puzzle, required PuzzleProgress progress}) async {
    if (!enabled || puzzle.daily == null) return false;
    try {
      await _functions!.httpsCallable('submitDaily').call<Map<String, dynamic>>({
        'puzzleId': puzzle.id,
        'lang': puzzle.lang,
        'date': puzzle.daily!.date,
        'variant': puzzle.daily!.variant.code,
        'elapsedMs': progress.elapsedMs,
        'lettersRevealed': progress.lettersRevealed,
        'wordsRevealed': progress.wordsRevealed,
        'checksUsed': progress.checksUsed,
        'mode': progress.mode.code,
        'solutionHash': PuzzleCodec.solutionHash(puzzle),
      });
      return true;
    } catch (e) {
      debugPrint('submitDaily failed: $e');
      return false;
    }
  }
}
