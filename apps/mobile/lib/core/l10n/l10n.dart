import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

export '../../l10n/generated/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Localised helpers that depend on enums from the engine.
extension L10nNames on AppLocalizations {
  String levelName(int level) => switch (level) {
        1 => levelName1,
        2 => levelName2,
        3 => levelName3,
        4 => levelName4,
        _ => levelName5,
      };

  String modeName(PlayMode mode) => switch (mode) {
        PlayMode.relaxed => modeRelaxed,
        PlayMode.normal => modeNormal,
        PlayMode.newspaper => modeNewspaper,
      };

  String modeDescription(PlayMode mode) => switch (mode) {
        PlayMode.relaxed => modeRelaxedDescription,
        PlayMode.normal => modeNormalDescription,
        PlayMode.newspaper => modeNewspaperDescription,
      };

  String dirName(Dir dir) => dir == Dir.across ? clueAcross : clueDown;

  String layoutName(String id) => switch (id) {
        'alphabetical' => layoutAlphabetical,
        'standard' => layoutStandard,
        'qwerty' => layoutQwerty,
        'abc' => layoutAbc,
        _ => id,
      };

  String dailyVariantName(DailyVariant v) => v == DailyVariant.easy ? dailyEasyTitle : dailyHardTitle;
}

/// Text direction of a puzzle language, independent of the UI locale.
TextDirection puzzleTextDirection(LanguageProfile lang) =>
    lang.direction == ReadingDirection.rtl ? TextDirection.rtl : TextDirection.ltr;
