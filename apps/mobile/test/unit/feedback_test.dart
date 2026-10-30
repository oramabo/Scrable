import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/features/feedback/feedback_service.dart';
import 'package:chetz_app/features/feedback/rating_prompt.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const day = 24 * 60 * 60 * 1000;
  final now = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;

  group('RatingPolicy', () {
    final installedLongAgo = AppSettings(installedAt: now - 10 * day);

    test('asks after five completed puzzles once the app has been installed for two days', () {
      expect(RatingPolicy.shouldAsk(installedLongAgo, puzzlesCompleted: 5, nowMs: now), isTrue);
      expect(RatingPolicy.shouldAsk(installedLongAgo, puzzlesCompleted: 4, nowMs: now), isFalse);
      expect(RatingPolicy.shouldAsk(AppSettings(installedAt: now - day), puzzlesCompleted: 20, nowMs: now), isFalse);
      expect(RatingPolicy.shouldAsk(const AppSettings(), puzzlesCompleted: 20, nowMs: now), isFalse, reason: 'install time unknown');
    });

    test('waits 120 days between prompts and stops after three', () {
      final asked = installedLongAgo.copyWith(reviewPromptedAt: now - 30 * day, reviewPromptCount: 1);
      expect(RatingPolicy.shouldAsk(asked, puzzlesCompleted: 50, nowMs: now), isFalse);
      expect(RatingPolicy.shouldAsk(asked, puzzlesCompleted: 50, nowMs: now + 90 * day), isTrue);
      final maxed = asked.copyWith(reviewPromptCount: 3, reviewPromptedAt: now - 400 * day);
      expect(RatingPolicy.shouldAsk(maxed, puzzlesCompleted: 500, nowMs: now), isFalse);
    });

    test('the prompt history survives a settings round trip', () {
      final s = AppSettings.fromJson(installedLongAgo.copyWith(reviewPromptedAt: now, reviewPromptCount: 2).toJson());
      expect(s.reviewPromptedAt, now);
      expect(s.reviewPromptCount, 2);
    });
  });

  group('FeedbackController', () {
    FeedbackReport report(String message) => FeedbackReport(kind: ReportKind.bug, message: message, createdAt: now);

    test('sends right away when the service is available', () async {
      final service = FakeFeedbackService();
      final ctl = FeedbackController(service, MemoryJsonStore());
      expect(await ctl.submit(report('crash on open')), FeedbackResult.sent);
      expect(service.sent.single.message, 'crash on open');
    });

    test('keeps reports on the device while offline and sends them later', () async {
      final service = FakeFeedbackService(available: false);
      final store = MemoryJsonStore();
      final ctl = FeedbackController(service, store);
      expect(await ctl.submit(report('one')), FeedbackResult.queued);
      expect(await ctl.submit(report('two')), FeedbackResult.queued);
      expect(service.sent, isEmpty);
      expect(await ctl.flush(), 2);

      service.available = true;
      expect(await ctl.flush(), 0);
      expect(service.sent.map((r) => r.message), ['one', 'two']);
      expect(await store.read(FeedbackController.outboxKey), isNull);
    });

    test('the outbox keeps only the newest reports', () async {
      final ctl = FeedbackController(FakeFeedbackService(available: false), MemoryJsonStore());
      for (var i = 0; i < FeedbackController.maxQueued + 5; i++) {
        await ctl.submit(report('r$i'));
      }
      final service = FakeFeedbackService();
      await FeedbackController(service, ctl.store).flush();
      expect(service.sent, hasLength(FeedbackController.maxQueued));
      expect(service.sent.first.message, 'r5');
    });

    test('reports round-trip through JSON with their context', () {
      final r = FeedbackReport(kind: ReportKind.clue, message: 'wrong', email: 'a@b.c', createdAt: now, context: {'puzzleId': 'he-l1-p01-01', 'clueId': 'hc_1'});
      final back = FeedbackReport.fromJson(r.toJson());
      expect(back.kind, ReportKind.clue);
      expect(back.email, 'a@b.c');
      expect(back.context, {'puzzleId': 'he-l1-p01-01', 'clueId': 'hc_1'});
    });
  });
}
