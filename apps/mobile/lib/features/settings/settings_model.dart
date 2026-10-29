import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import 'theme/custom_theme.dart';

/// User preferences. Persisted as one JSON document.
class AppSettings {
  const AppSettings({
    this.uiLang = 'he',
    this.puzzleLang = 'he',
    this.keyboardLayoutId,
    this.textScale = 1.0,
    this.highContrast = false,
    this.themeMode = ThemeMode.system,
    this.haptics = true,
    this.sounds = false,
    this.showTimer = false,
    this.skipFilled = true,
    this.autoNextWord = true,
    this.bigKeyboard = false,
    this.modePerLevel = const {},
    this.skipHintConfirm = false,
    this.onboardingDone = false,
    this.tutorialDone = false,
    this.lastPuzzleId,
    this.adConsentDone = false,
    this.installedAt,
    this.sessionCount = 0,
    this.useCustomTheme = false,
    this.customTheme = const CustomTheme(),
  });

  final String uiLang;
  final String puzzleLang;

  /// Null = the language profile's first layout.
  final String? keyboardLayoutId;
  final double textScale;
  final bool highContrast;
  final ThemeMode themeMode;
  final bool haptics;
  final bool sounds;
  final bool showTimer;
  final bool skipFilled;
  final bool autoNextWord;
  final bool bigKeyboard;

  /// Play mode chosen per level (overrides the config default).
  final Map<int, PlayMode> modePerLevel;
  final bool skipHintConfirm;
  final bool onboardingDone;
  final bool tutorialDone;
  final String? lastPuzzleId;
  final bool adConsentDone;
  final int? installedAt;
  final int sessionCount;

  /// Player-picked colours (Settings → Theme → custom).
  final bool useCustomTheme;
  final CustomTheme customTheme;

  Locale get uiLocale => Locale(uiLang);
  LanguageProfile get puzzleProfile => Languages.byCode(puzzleLang);

  KeyboardLayout keyboardLayoutFor(LanguageProfile lang) {
    final layouts = lang.keyboardLayouts;
    for (final l in layouts) {
      if (l.id == keyboardLayoutId) return l;
    }
    return layouts.first;
  }

  /// Minimum scale applied to the whole UI (grid clue text excluded).
  static const textScales = [0.9, 1.0, 1.15, 1.3, 1.5];

  AppSettings copyWith({
    String? uiLang,
    String? puzzleLang,
    String? keyboardLayoutId,
    bool clearKeyboardLayout = false,
    double? textScale,
    bool? highContrast,
    ThemeMode? themeMode,
    bool? haptics,
    bool? sounds,
    bool? showTimer,
    bool? skipFilled,
    bool? autoNextWord,
    bool? bigKeyboard,
    Map<int, PlayMode>? modePerLevel,
    bool? skipHintConfirm,
    bool? onboardingDone,
    bool? tutorialDone,
    String? lastPuzzleId,
    bool clearLastPuzzle = false,
    bool? adConsentDone,
    int? installedAt,
    int? sessionCount,
    bool? useCustomTheme,
    CustomTheme? customTheme,
  }) =>
      AppSettings(
        uiLang: uiLang ?? this.uiLang,
        puzzleLang: puzzleLang ?? this.puzzleLang,
        keyboardLayoutId: clearKeyboardLayout ? null : (keyboardLayoutId ?? this.keyboardLayoutId),
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        themeMode: themeMode ?? this.themeMode,
        haptics: haptics ?? this.haptics,
        sounds: sounds ?? this.sounds,
        showTimer: showTimer ?? this.showTimer,
        skipFilled: skipFilled ?? this.skipFilled,
        autoNextWord: autoNextWord ?? this.autoNextWord,
        bigKeyboard: bigKeyboard ?? this.bigKeyboard,
        modePerLevel: modePerLevel ?? this.modePerLevel,
        skipHintConfirm: skipHintConfirm ?? this.skipHintConfirm,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        tutorialDone: tutorialDone ?? this.tutorialDone,
        lastPuzzleId: clearLastPuzzle ? null : (lastPuzzleId ?? this.lastPuzzleId),
        adConsentDone: adConsentDone ?? this.adConsentDone,
        installedAt: installedAt ?? this.installedAt,
        sessionCount: sessionCount ?? this.sessionCount,
        useCustomTheme: useCustomTheme ?? this.useCustomTheme,
        customTheme: customTheme ?? this.customTheme,
      );

  /// The "seniors" preset: large text, high contrast, relaxed mode everywhere,
  /// big keyboard, haptics on.
  AppSettings withSeniorsPreset() => copyWith(
        textScale: 1.25,
        highContrast: true,
        bigKeyboard: true,
        haptics: true,
        showTimer: false,
        useCustomTheme: false,
        modePerLevel: {for (var l = 1; l <= 6; l++) l: PlayMode.relaxed},
      );

  Map<String, dynamic> toJson() => {
        'uiLang': uiLang,
        'puzzleLang': puzzleLang,
        if (keyboardLayoutId != null) 'keyboardLayoutId': keyboardLayoutId,
        'textScale': textScale,
        'highContrast': highContrast,
        'themeMode': themeMode.name,
        'haptics': haptics,
        'sounds': sounds,
        'showTimer': showTimer,
        'skipFilled': skipFilled,
        'autoNextWord': autoNextWord,
        'bigKeyboard': bigKeyboard,
        'modePerLevel': {for (final e in modePerLevel.entries) '${e.key}': e.value.code},
        'skipHintConfirm': skipHintConfirm,
        'onboardingDone': onboardingDone,
        'tutorialDone': tutorialDone,
        if (lastPuzzleId != null) 'lastPuzzleId': lastPuzzleId,
        'adConsentDone': adConsentDone,
        if (installedAt != null) 'installedAt': installedAt,
        'sessionCount': sessionCount,
        'useCustomTheme': useCustomTheme,
        'customTheme': customTheme.toJson(),
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final modes = <int, PlayMode>{};
    final rawModes = j['modePerLevel'];
    if (rawModes is Map) {
      for (final e in rawModes.entries) {
        final k = int.tryParse(e.key.toString());
        if (k != null) modes[k] = PlayMode.fromCode(e.value.toString());
      }
    }
    return AppSettings(
      uiLang: (j['uiLang'] as String?) ?? 'he',
      puzzleLang: (j['puzzleLang'] as String?) ?? 'he',
      keyboardLayoutId: j['keyboardLayoutId'] as String?,
      textScale: ((j['textScale'] as num?) ?? 1.0).toDouble(),
      highContrast: (j['highContrast'] as bool?) ?? false,
      themeMode: ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.system),
      haptics: (j['haptics'] as bool?) ?? true,
      sounds: (j['sounds'] as bool?) ?? false,
      showTimer: (j['showTimer'] as bool?) ?? false,
      skipFilled: (j['skipFilled'] as bool?) ?? true,
      autoNextWord: (j['autoNextWord'] as bool?) ?? true,
      bigKeyboard: (j['bigKeyboard'] as bool?) ?? false,
      modePerLevel: modes,
      skipHintConfirm: (j['skipHintConfirm'] as bool?) ?? false,
      onboardingDone: (j['onboardingDone'] as bool?) ?? false,
      tutorialDone: (j['tutorialDone'] as bool?) ?? false,
      lastPuzzleId: j['lastPuzzleId'] as String?,
      adConsentDone: (j['adConsentDone'] as bool?) ?? false,
      installedAt: j['installedAt'] as int?,
      sessionCount: (j['sessionCount'] as int?) ?? 0,
      useCustomTheme: (j['useCustomTheme'] as bool?) ?? false,
      customTheme: j['customTheme'] is Map ? CustomTheme.fromJson(j['customTheme'] as Map<String, dynamic>) : const CustomTheme(),
    );
  }
}
