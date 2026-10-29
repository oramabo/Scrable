import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/providers.dart';
import '../../core/util/feedback.dart';
import 'settings_model.dart';

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = ref.read(bootstrapProvider).settings;
    ref.read(analyticsProvider).setContext(lang: s.puzzleLang, uiLang: s.uiLang);
    return s;
  }

  void _set(AppSettings next) {
    state = next;
    // Fire-and-forget; the repository writes atomically.
    ref.read(settingsRepositoryProvider).save(next).ignore();
  }

  void update(AppSettings Function(AppSettings) fn) => _set(fn(state));

  void setUiLang(String lang) {
    if (lang == state.uiLang) return;
    _set(state.copyWith(uiLang: lang));
    ref.read(analyticsProvider)
      ..setContext(uiLang: lang)
      ..track(AnalyticsEvents.languageSwitched, {'ui_lang': lang, 'kind': 'ui'});
  }

  void setPuzzleLang(String lang) {
    if (lang == state.puzzleLang) return;
    _set(state.copyWith(puzzleLang: lang, clearKeyboardLayout: true));
    ref.read(analyticsProvider)
      ..setContext(lang: lang)
      ..track(AnalyticsEvents.languageSwitched, {'lang': lang, 'kind': 'puzzle'});
  }

  void setKeyboardLayout(String id) => _set(state.copyWith(keyboardLayoutId: id));

  void setTextScale(double scale) {
    _set(state.copyWith(textScale: scale));
    _a11y('text_scale', scale);
  }

  void setHighContrast(bool on) {
    _set(state.copyWith(highContrast: on));
    _a11y('high_contrast', on);
  }

  void setThemeMode(ThemeMode mode) => _set(state.copyWith(themeMode: mode));
  void setHaptics(bool on) => _set(state.copyWith(haptics: on));
  void setSounds(bool on) => _set(state.copyWith(sounds: on));
  void setShowTimer(bool on) => _set(state.copyWith(showTimer: on));
  void setSkipFilled(bool on) => _set(state.copyWith(skipFilled: on));
  void setAutoNextWord(bool on) => _set(state.copyWith(autoNextWord: on));

  void setBigKeyboard(bool on) {
    _set(state.copyWith(bigKeyboard: on));
    _a11y('big_keyboard', on);
  }

  void setModeForLevel(int level, PlayMode mode) =>
      _set(state.copyWith(modePerLevel: {...state.modePerLevel, level: mode}));

  void setSkipHintConfirm(bool on) => _set(state.copyWith(skipHintConfirm: on));
  void completeOnboarding() => _set(state.copyWith(onboardingDone: true));
  void completeTutorial() => _set(state.copyWith(tutorialDone: true));
  void setLastPuzzle(String id) {
    if (state.lastPuzzleId != id) _set(state.copyWith(lastPuzzleId: id));
  }

  void clearLastPuzzle() => _set(state.copyWith(clearLastPuzzle: true));
  void setAdConsentDone() => _set(state.copyWith(adConsentDone: true));

  void applySeniorsPreset() {
    _set(state.withSeniorsPreset());
    _a11y('seniors_preset', true);
  }

  /// Called once per app launch.
  void markSession(int nowMs) =>
      _set(state.copyWith(sessionCount: state.sessionCount + 1, installedAt: state.installedAt ?? nowMs));

  /// Replaces everything with defaults (data deletion).
  void reset() => _set(const AppSettings(onboardingDone: true));

  void _a11y(String setting, Object value) =>
      ref.read(analyticsProvider).track(AnalyticsEvents.a11ySettingChanged, {'setting': setting, 'value': value});
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Haptics implementation follows the setting.
final hapticsProvider = Provider<Haptics>(
  (ref) => ref.watch(settingsProvider.select((s) => s.haptics)) ? const SystemHaptics() : const NoHaptics(),
);

/// Active puzzle language profile.
final puzzleLanguageProvider = Provider<LanguageProfile>(
  (ref) => Languages.byCode(ref.watch(settingsProvider.select((s) => s.puzzleLang))),
);

/// Content repository of the active puzzle language.
final puzzleContentProvider = Provider(
  (ref) => ref.watch(contentRepositoryProvider(ref.watch(settingsProvider.select((s) => s.puzzleLang)))),
);
