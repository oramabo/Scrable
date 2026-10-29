import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// A scheduled local notification (what the fake records and the real
/// service hands to the platform).
class ScheduledNotification {
  const ScheduledNotification({required this.id, required this.at, required this.title, required this.body, required this.channel});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String channel;

  @override
  String toString() => 'ScheduledNotification($id $channel @$at "$title")';
}

/// Local notifications behind an interface so the scheduling logic is
/// testable without a platform.
abstract class NotificationsService {
  const NotificationsService();

  bool get available;

  /// Asks the OS for permission (Android 13+ / iOS). True when granted.
  Future<bool> requestPermission();

  Future<void> schedule(ScheduledNotification n);

  /// Cancels every notification whose id is in [ids].
  Future<void> cancel(Iterable<int> ids);
  Future<void> cancelAll();
}

/// No-op (tests without notifications, unsupported platforms).
class DisabledNotificationsService extends NotificationsService {
  const DisabledNotificationsService();
  @override
  bool get available => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(ScheduledNotification n) async {}
  @override
  Future<void> cancel(Iterable<int> ids) async {}
  @override
  Future<void> cancelAll() async {}
}

/// Records what would be scheduled.
class FakeNotificationsService extends NotificationsService {
  FakeNotificationsService({this.granted = true});
  bool granted;
  int permissionRequests = 0;
  final Map<int, ScheduledNotification> scheduled = {};

  @override
  bool get available => true;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> schedule(ScheduledNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(Iterable<int> ids) async {
    for (final id in ids) {
      scheduled.remove(id);
    }
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

/// flutter_local_notifications. Times are local wall-clock instants; they are
/// converted to UTC `TZDateTime`s so no device time-zone database lookup is
/// needed (each occurrence is scheduled individually, which also sidesteps
/// DST drift of repeating schedules).
class LocalNotificationsService extends NotificationsService {
  LocalNotificationsService({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;
  bool _failed = false;

  @override
  bool get available => !_failed;

  Future<bool> _init() async {
    if (_initialised) return true;
    if (_failed) return false;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
      await _plugin.initialize(settings: const InitializationSettings(android: android, iOS: ios));
      _initialised = true;
      return true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
      _failed = true;
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.requestPermissions(alert: true, badge: false, sound: true)) ?? false;
      return true;
    } catch (e) {
      debugPrint('notification permission failed: $e');
      return false;
    }
  }

  @override
  Future<void> schedule(ScheduledNotification n) async {
    if (!await _init()) return;
    if (!n.at.isAfter(DateTime.now())) return;
    try {
      final when = tz.TZDateTime.from(n.at.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: when,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            n.channel,
            n.channel == dailyChannel ? 'Daily puzzle' : 'Streak',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('schedule notification failed: $e');
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    if (!await _init()) return;
    for (final id in ids) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static const dailyChannel = 'chetz_daily';
  static const streakChannel = 'chetz_streak';
}
