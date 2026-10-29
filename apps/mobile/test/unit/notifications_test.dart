import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/daily/daily_controller.dart';
import 'package:chetz_app/features/daily/daily_history.dart';
import 'package:chetz_app/features/notifications/notifications_controller.dart';
import 'package:chetz_app/features/notifications/notifications_service.dart';
import 'package:chetz_app/features/settings/settings_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/l10n/generated/app_localizations_he.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12);

  group('NotificationPlan', () {
    test('daily-ready at the chosen hour for the coming week, skipping past hours', () {
      final plan = NotificationPlan.build(
        settings: const AppSettings(notificationsDailyReady: true, notificationsHour: 9),
        history: DailyHistory(),
        now: now,
        dailyTitle: 'd',
        dailyBody: 'b',
        streakTitle: 's',
        streakBody: 'b',
      );
      final daily = plan.scheduled.where((n) => n.channel == LocalNotificationsService.dailyChannel).toList();
      expect(daily.length, 6, reason: "today's 09:00 already passed");
      expect(daily.first.at, DateTime(2026, 10, 29, 9));
      expect(plan.cancelledIds, contains(NotificationPlan.dailyBaseId));
      expect(plan.scheduled.where((n) => n.channel == LocalNotificationsService.streakChannel), isEmpty, reason: 'streak reminder off');
    });

    test('streak-at-risk at 20:00 only while today\'s daily is not done', () {
      final history = DailyHistory().markCompleted('2026-10-28', DailyVariant.easy);
      final plan = NotificationPlan.build(
        settings: const AppSettings(notificationsStreak: true),
        history: history,
        now: now,
        dailyTitle: 'd',
        dailyBody: 'b',
        streakTitle: 's',
        streakBody: 'b',
      );
      final streak = plan.scheduled.where((n) => n.channel == LocalNotificationsService.streakChannel).toList();
      expect(streak.first.at, DateTime(2026, 10, 29, 20), reason: 'today is done → tomorrow is the first reminder');
      expect(plan.cancelledIds, contains(NotificationPlan.streakBaseId));

      final notDone = NotificationPlan.build(
        settings: const AppSettings(notificationsStreak: true),
        history: DailyHistory(),
        now: now,
        dailyTitle: 'd',
        dailyBody: 'b',
        streakTitle: 's',
        streakBody: 'b',
      );
      expect(notDone.scheduled.first.at, DateTime(2026, 10, 28, 20));
      expect(notDone.scheduled.first.id, NotificationPlan.streakBaseId);
    });
  });

  test('the opt-in prompt is due after the second completed daily, once', () {
    expect(shouldAskForNotifications(const AppSettings(), 1, available: true), isFalse);
    expect(shouldAskForNotifications(const AppSettings(), 2, available: true), isTrue);
    expect(shouldAskForNotifications(const AppSettings(notificationsAsked: true), 5, available: true), isFalse);
    expect(shouldAskForNotifications(const AppSettings(), 2, available: false), isFalse);
  });

  test('enabling asks the OS, stores the toggles and schedules; a daily completion re-plans', () async {
    final fake = FakeNotificationsService();
    final clock = FixedClock(now);
    final container = ProviderContainer(overrides: testOverrides(content: MapContentSource(), clock: clock, notifications: fake));
    addTearDown(container.dispose);
    final l10n = AppLocalizationsHe();
    final ctl = container.read(notificationsProvider.notifier);

    expect(await ctl.enable(l10n), isTrue);
    expect(fake.permissionRequests, 1);
    final s = container.read(settingsProvider);
    expect(s.notificationsAsked, isTrue);
    expect(s.notificationsDailyReady, isTrue);
    expect(s.notificationsStreak, isTrue);
    expect(fake.scheduled[NotificationPlan.streakBaseId]?.at, DateTime(2026, 10, 28, 20));
    expect(fake.scheduled[NotificationPlan.streakBaseId]?.title, l10n.notifStreakRisk);
    expect(fake.scheduled[NotificationPlan.dailyBaseId + 1]?.title, l10n.notifDailyReady);

    // Today's daily done → today's streak reminder goes away.
    container.read(dailyHistoryProvider.notifier).markCompleted('2026-10-28', DailyVariant.hard);
    await ctl.reschedule(l10n);
    expect(fake.scheduled.containsKey(NotificationPlan.streakBaseId), isFalse);

    await ctl.disableAll(l10n);
    expect(fake.scheduled, isEmpty);
    expect(container.read(settingsProvider).notificationsDailyReady, isFalse);

    // Denied permission: toggles stay off.
    fake.granted = false;
    expect(await ctl.enable(l10n), isFalse);
    expect(container.read(settingsProvider).notificationsStreak, isFalse);
  });
}
