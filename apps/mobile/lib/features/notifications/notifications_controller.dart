import 'dart:async';

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/util/clock.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../daily/daily_history.dart';
import '../meta/game_events_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';
import 'notifications_service.dart';

/// Overridden in main (real plugin) and tests (fake).
final notificationsServiceProvider = Provider<NotificationsService>((ref) => const DisabledNotificationsService());

/// Pure scheduling plan: which notifications should exist for the next
/// [days] days given the settings and daily history.
class NotificationPlan {
  const NotificationPlan({required this.scheduled, required this.cancelledIds});
  final List<ScheduledNotification> scheduled;
  final List<int> cancelledIds;

  static const dailyBaseId = 1000;
  static const streakBaseId = 2000;
  static const streakHour = 20;

  /// Ids this planner ever uses (so a re-plan can clear stale ones).
  static List<int> allIds(int days) => [
        for (var i = 0; i < days; i++) dailyBaseId + i,
        for (var i = 0; i < days; i++) streakBaseId + i,
      ];

  static NotificationPlan build({
    required AppSettings settings,
    required DailyHistory history,
    required DateTime now,
    required String dailyTitle,
    required String dailyBody,
    required String streakTitle,
    required String streakBody,
    int days = 7,
  }) {
    final out = <ScheduledNotification>[];
    final cancelled = <int>[];
    final today = dateOnly(now);
    for (var i = 0; i < days; i++) {
      final day = today.add(Duration(days: i));
      final key = dateKey(day);
      final ready = DateTime(day.year, day.month, day.day, settings.notificationsHour);
      if (settings.notificationsDailyReady && ready.isAfter(now)) {
        out.add(ScheduledNotification(id: dailyBaseId + i, at: ready, title: dailyTitle, body: dailyBody, channel: LocalNotificationsService.dailyChannel));
      } else {
        cancelled.add(dailyBaseId + i);
      }
      final risk = DateTime(day.year, day.month, day.day, streakHour);
      // Only when that day's daily is not done yet (today: known; later days: unknown → schedule, re-planned daily).
      final doneToday = i == 0 && (history.isCompleted(key, DailyVariant.easy) || history.isCompleted(key, DailyVariant.hard));
      if (settings.notificationsStreak && risk.isAfter(now) && !doneToday) {
        out.add(ScheduledNotification(id: streakBaseId + i, at: risk, title: streakTitle, body: streakBody, channel: LocalNotificationsService.streakChannel));
      } else {
        cancelled.add(streakBaseId + i);
      }
    }
    return NotificationPlan(scheduled: out, cancelledIds: cancelled);
  }
}

/// Keeps the OS schedule in sync with settings + daily history: called at
/// startup, on resume, when a daily is completed and when a toggle changes.
class NotificationsController extends Notifier<int> {
  @override
  int build() => 0;

  Future<void> reschedule(AppLocalizations l10n) async {
    final service = ref.read(notificationsServiceProvider);
    if (!service.available) return;
    final settings = ref.read(settingsProvider);
    final plan = NotificationPlan.build(
      settings: settings,
      history: ref.read(dailyHistoryProvider),
      now: ref.read(clockProvider).now(),
      dailyTitle: l10n.notifDailyReady,
      dailyBody: l10n.notifDailyReadyBody,
      streakTitle: l10n.notifStreakRisk,
      streakBody: l10n.notifStreakRiskBody,
    );
    await service.cancel(plan.cancelledIds);
    for (final n in plan.scheduled) {
      await service.schedule(n);
    }
    state++;
  }

  /// Turns reminders on (asks the OS first). Returns false when denied.
  Future<bool> enable(AppLocalizations l10n, {bool daily = true, bool streak = true}) async {
    final granted = await ref.read(notificationsServiceProvider).requestPermission();
    final ctl = ref.read(settingsProvider.notifier);
    ctl.setNotificationsAsked();
    if (!granted) {
      ctl.setNotifications(daily: false, streak: false);
      return false;
    }
    ctl.setNotifications(daily: daily, streak: streak);
    await reschedule(l10n);
    return true;
  }

  Future<void> disableAll(AppLocalizations l10n) async {
    ref.read(settingsProvider.notifier).setNotifications(daily: false, streak: false);
    await ref.read(notificationsServiceProvider).cancelAll();
    state++;
  }
}

final notificationsProvider = NotifierProvider<NotificationsController, int>(NotificationsController.new);

/// Whether to show the opt-in prompt now: after the second completed daily,
/// never asked before, notifications available.
bool shouldAskForNotifications(AppSettings settings, int dailiesCompleted, {required bool available}) =>
    available && !settings.notificationsAsked && dailiesCompleted >= 2;

/// Shows the opt-in dialog (with the reason) when due. Returns true when the
/// player enabled reminders.
Future<bool> maybeAskForNotifications(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final dailies = ref.read(playerStatsProvider).dailiesCompleted;
  if (!shouldAskForNotifications(settings, dailies, available: ref.read(notificationsServiceProvider).available)) return false;
  final l10n = context.l10n;
  final enable = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(l10n.notifOptInTitle),
      content: Text(l10n.notifOptInBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.notifNotNow)),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.notifEnable)),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (enable != true) {
    ref.read(settingsProvider.notifier).setNotificationsAsked();
    return false;
  }
  final ok = await ref.read(notificationsProvider.notifier).enable(l10n);
  if (!ok && context.mounted) showSnack(context, l10n.notifDenied);
  return ok;
}
