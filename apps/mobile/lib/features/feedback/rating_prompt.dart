import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/providers.dart';
import '../meta/game_events_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';

/// When to ask the store for a rating. The system dialog is shown straight
/// away, with no "do you like the app?" question first: Google Play and the
/// App Store do not allow filtering or steering who gets the prompt. Feedback
/// has its own entry in Settings and the puzzle menu instead.
abstract final class RatingPolicy {
  static const minPuzzlesCompleted = 5;
  static const minDaysInstalled = 2;
  static const cooldownDays = 120;
  static const maxPrompts = 3;

  static const _dayMs = 24 * 60 * 60 * 1000;

  /// Right after a completed puzzle: enough play behind them, installed for
  /// a couple of days, not asked in the last four months, at most three times.
  static bool shouldAsk(AppSettings settings, {required int puzzlesCompleted, required int nowMs}) {
    if (puzzlesCompleted < minPuzzlesCompleted) return false;
    if (settings.reviewPromptCount >= maxPrompts) return false;
    final installed = settings.installedAt;
    if (installed == null || nowMs - installed < minDaysInstalled * _dayMs) return false;
    final last = settings.reviewPromptedAt;
    return last == null || nowMs - last >= cooldownDays * _dayMs;
  }
}

/// Requests the store's review dialog when [RatingPolicy] allows it. Returns
/// true when it was requested (the store may still decide not to show it).
Future<bool> maybeRequestReview(WidgetRef ref) async {
  final nowMs = ref.read(clockProvider).nowMs;
  final completed = ref.read(playerStatsProvider).puzzlesCompleted;
  if (!RatingPolicy.shouldAsk(ref.read(settingsProvider), puzzlesCompleted: completed, nowMs: nowMs)) return false;
  final review = ref.read(reviewServiceProvider);
  if (!await review.isAvailable()) return false;
  ref.read(settingsProvider.notifier).markReviewPrompted(nowMs);
  ref.read(analyticsProvider).track(AnalyticsEvents.reviewPrompt, {'puzzles_completed': completed});
  await review.request();
  return true;
}
