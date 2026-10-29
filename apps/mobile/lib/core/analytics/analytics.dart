import 'package:flutter/foundation.dart';

/// Event names from docs/GAME_PLAN.md §6.6.
abstract final class AnalyticsEvents {
  static const puzzleStart = 'puzzle_start';
  static const puzzleComplete = 'puzzle_complete';
  static const wordSolved = 'word_solved';
  static const hintUsed = 'hint_used';
  static const checkUsed = 'check_used';
  static const adRequested = 'ad_requested';
  static const adShown = 'ad_shown';
  static const adRewarded = 'ad_rewarded';
  static const paywallView = 'paywall_view';
  static const purchase = 'purchase';
  static const packUnlock = 'pack_unlock';
  static const dailyOpen = 'daily_open';
  static const dailyComplete = 'daily_complete';
  static const streakChange = 'streak_change';
  static const onboardingStep = 'onboarding_step';
  static const a11ySettingChanged = 'a11y_setting_changed';
  static const languageSwitched = 'language_switched';
}

/// Product analytics sink. Every event carries `lang` (puzzle language) and
/// `ui_lang`. PostHog can be plugged in later behind this interface.
abstract class Analytics {
  const Analytics();

  void setContext({String? lang, String? uiLang});
  void track(String event, [Map<String, Object?> props = const {}]);
}

class NoopAnalytics extends Analytics {
  const NoopAnalytics();
  @override
  void setContext({String? lang, String? uiLang}) {}
  @override
  void track(String event, [Map<String, Object?> props = const {}]) {}
}

/// Prints events in debug builds; keeps the last events for inspection.
class LoggingAnalytics extends Analytics {
  LoggingAnalytics({this.keep = 200});

  final int keep;
  String? _lang;
  String? _uiLang;
  final List<Map<String, Object?>> events = [];

  @override
  void setContext({String? lang, String? uiLang}) {
    _lang = lang ?? _lang;
    _uiLang = uiLang ?? _uiLang;
  }

  @override
  void track(String event, [Map<String, Object?> props = const {}]) {
    final payload = <String, Object?>{'event': event, 'lang': _lang, 'ui_lang': _uiLang, ...props};
    events.add(payload);
    if (events.length > keep) events.removeAt(0);
    if (kDebugMode) debugPrint('[analytics] $payload');
  }
}
