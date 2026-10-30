import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/json_store.dart';

/// What a player is reporting. `clue` reports come from the puzzle screen and
/// carry the puzzle, word and clue ids so they reach the clue review queue.
enum ReportKind {
  bug('bug'),
  clue('clue'),
  idea('idea'),
  other('other');

  const ReportKind(this.code);
  final String code;

  static ReportKind fromCode(String code) => ReportKind.values.firstWhere((k) => k.code == code, orElse: () => ReportKind.other);
}

/// One piece of player feedback. [context] holds what the app knows without
/// asking (app version, platform, languages, puzzle/word/clue ids).
class FeedbackReport {
  const FeedbackReport({
    required this.kind,
    required this.message,
    required this.createdAt,
    this.email,
    this.context = const {},
  });

  static const maxMessageLength = 2000;

  final ReportKind kind;
  final String message;
  final String? email;
  final Map<String, Object?> context;

  /// Milliseconds since epoch on the device.
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'kind': kind.code,
        'message': message,
        if (email != null && email!.isNotEmpty) 'email': email,
        'context': context,
        'createdAt': createdAt,
      };

  static FeedbackReport fromJson(Map<String, dynamic> j) => FeedbackReport(
        kind: ReportKind.fromCode(j['kind'] as String? ?? 'other'),
        message: j['message'] as String? ?? '',
        email: j['email'] as String?,
        context: Map<String, Object?>.from((j['context'] as Map?) ?? const {}),
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// Delivers feedback. Returns false when the report could not be delivered
/// (offline, Firebase off); the [FeedbackController] keeps it for later.
abstract class FeedbackService {
  const FeedbackService();
  bool get available;
  Future<bool> send(FeedbackReport report);
}

class DisabledFeedbackService extends FeedbackService {
  const DisabledFeedbackService();
  @override
  bool get available => false;
  @override
  Future<bool> send(FeedbackReport report) async => false;
}

class FakeFeedbackService extends FeedbackService {
  FakeFeedbackService({this.available = true});
  @override
  bool available;
  final List<FeedbackReport> sent = [];
  @override
  Future<bool> send(FeedbackReport report) async {
    if (!available) return false;
    sent.add(report);
    return true;
  }
}

/// `feedback/{autoId}`: create-only for signed-in players (firestore.rules),
/// read in the admin tools.
class FirestoreFeedbackService extends FeedbackService {
  FirestoreFeedbackService({required this.uid, FirebaseFirestore? firestoreClient}) : _firestore = firestoreClient;

  final String? uid;
  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  bool get available => uid != null;

  @override
  Future<bool> send(FeedbackReport report) async {
    if (uid == null) return false;
    try {
      await _db.collection('feedback').add({...report.toJson(), 'uid': uid, 'status': 'new', 'receivedAt': FieldValue.serverTimestamp()});
      return true;
    } catch (e) {
      debugPrint('feedback send failed: $e');
      return false;
    }
  }
}

enum FeedbackResult { sent, queued }

/// Sends feedback now when possible, otherwise keeps it in an on-device
/// outbox that [flush] retries (app start, next report).
class FeedbackController {
  FeedbackController(this.service, this.store);

  static const outboxKey = 'feedback_outbox';
  static const maxQueued = 20;

  final FeedbackService service;
  final JsonStore store;

  Future<FeedbackResult> submit(FeedbackReport report) async {
    await flush();
    if (service.available && await service.send(report)) return FeedbackResult.sent;
    final pending = await _pending();
    await _save([...pending, report].reversed.take(maxQueued).toList().reversed.toList());
    return FeedbackResult.queued;
  }

  /// Sends queued reports; returns how many are still waiting.
  Future<int> flush() async {
    final pending = await _pending();
    if (pending.isEmpty || !service.available) return pending.length;
    final left = <FeedbackReport>[];
    for (final r in pending) {
      if (!await service.send(r)) left.add(r);
    }
    await _save(left);
    return left.length;
  }

  Future<List<FeedbackReport>> _pending() async {
    final doc = await store.read(outboxKey);
    return [for (final j in (doc?['pending'] as List?) ?? const []) FeedbackReport.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> _save(List<FeedbackReport> reports) async {
    if (reports.isEmpty) {
      await store.delete(outboxKey);
    } else {
      await store.write(outboxKey, {'pending': [for (final r in reports) r.toJson()]});
    }
  }
}
