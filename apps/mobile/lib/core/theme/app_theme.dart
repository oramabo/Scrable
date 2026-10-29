import 'package:flutter/material.dart';

import '../../features/settings/theme/custom_theme.dart';

/// Colours of the puzzle grid and keyboard. Defined per theme variant so the
/// painter never hard-codes a colour.
@immutable
class GridColors extends ThemeExtension<GridColors> {
  const GridColors({
    required this.paper,
    required this.clueFill,
    required this.clueText,
    required this.letterFill,
    required this.letterText,
    required this.activeWord,
    required this.activeCell,
    required this.activeBorder,
    required this.correctTint,
    required this.wrongTint,
    required this.wrongMark,
    required this.revealedTint,
    required this.revealedMark,
    required this.pencilText,
    required this.gridLine,
    required this.arrow,
    required this.keyFill,
    required this.keyText,
    required this.keyActionFill,
    required this.keyPressed,
    required this.lineWidth,
    this.cellGap = 2,
    this.correctWash = const Color(0xFF1F8A8A),
  });

  final Color paper;
  final Color clueFill;
  final Color clueText;
  final Color letterFill;
  final Color letterText;
  final Color activeWord;
  final Color activeCell;
  final Color activeBorder;
  final Color correctTint;
  final Color wrongTint;
  final Color wrongMark;
  final Color revealedTint;
  final Color revealedMark;
  final Color pencilText;
  final Color gridLine;
  final Color arrow;
  final Color keyFill;
  final Color keyText;
  final Color keyActionFill;
  final Color keyPressed;
  final double lineWidth;

  /// Gap between cells (paper shows through); 0 draws grid lines instead.
  final double cellGap;

  /// Colour of the "correct word" wash animation.
  final Color correctWash;

  // docs/UX.md §2 — "a warm paper notebook that came alive".
  static const light = GridColors(
    paper: Color(0xFFF7F3EA),
    clueFill: Color(0xFFEFE9DC),
    clueText: Color(0xFF1F2937),
    letterFill: Color(0xFFFFFFFF),
    letterText: Color(0xFF1F2937),
    activeWord: Color(0xFFFCE4C8),
    activeCell: Color(0xFFF9C68E),
    activeBorder: Color(0xFFF28C28),
    correctTint: Color(0xFFD5EDEB),
    wrongTint: Color(0xFFF9DCDC),
    wrongMark: Color(0xFFE25D5D),
    revealedTint: Color(0xFFE2E8F5),
    revealedMark: Color(0xFF4A6FB5),
    pencilText: Color(0xFF8B93A1),
    gridLine: Color(0xFFC9C2B2),
    arrow: Color(0xFF1F2937),
    keyFill: Color(0xFFFFFFFF),
    keyText: Color(0xFF1F2937),
    keyActionFill: Color(0xFFEFE9DC),
    keyPressed: Color(0xFFF9C68E),
    lineWidth: 1,
  );

  static const dark = GridColors(
    paper: Color(0xFF141A22),
    clueFill: Color(0xFF28323F),
    clueText: Color(0xFFE8E6E1),
    letterFill: Color(0xFF1E2733),
    letterText: Color(0xFFE8E6E1),
    activeWord: Color(0xFF4A3A26),
    activeCell: Color(0xFF8A5A2B),
    activeBorder: Color(0xFFE8893A),
    correctTint: Color(0xFF1E3F40),
    wrongTint: Color(0xFF4A2A2E),
    wrongMark: Color(0xFFE57373),
    revealedTint: Color(0xFF26354F),
    revealedMark: Color(0xFF8FAAE0),
    pencilText: Color(0xFF8B93A1),
    gridLine: Color(0xFF3A4452),
    arrow: Color(0xFFE8E6E1),
    keyFill: Color(0xFF28323F),
    keyText: Color(0xFFE8E6E1),
    keyActionFill: Color(0xFF1E2733),
    keyPressed: Color(0xFF8A5A2B),
    lineWidth: 1,
    correctWash: Color(0xFF2A9D9D),
  );

  static const highContrastLight = GridColors(
    paper: Color(0xFFFFFFFF),
    clueFill: Color(0xFFE0E0E0),
    clueText: Color(0xFF000000),
    letterFill: Color(0xFFFFFFFF),
    letterText: Color(0xFF000000),
    activeWord: Color(0xFFFFE0B8),
    activeCell: Color(0xFFF28C28),
    activeBorder: Color(0xFF000000),
    correctTint: Color(0xFFB9F6CA),
    wrongTint: Color(0xFFFFB4AB),
    wrongMark: Color(0xFF9B0000),
    revealedTint: Color(0xFFB3D1FF),
    revealedMark: Color(0xFF002E99),
    pencilText: Color(0xFF444444),
    gridLine: Color(0xFF000000),
    arrow: Color(0xFF000000),
    keyFill: Color(0xFFFFFFFF),
    keyText: Color(0xFF000000),
    keyActionFill: Color(0xFFDDDDDD),
    keyPressed: Color(0xFFF28C28),
    lineWidth: 2,
    cellGap: 0,
    correctWash: Color(0xFF0B6B6B),
  );

  static const highContrastDark = GridColors(
    paper: Color(0xFF000000),
    clueFill: Color(0xFF2A2A2A),
    clueText: Color(0xFFFFFFFF),
    letterFill: Color(0xFF000000),
    letterText: Color(0xFFFFFFFF),
    activeWord: Color(0xFF5A3410),
    activeCell: Color(0xFFF28C28),
    activeBorder: Color(0xFFFFFFFF),
    correctTint: Color(0xFF0E4A1F),
    wrongTint: Color(0xFF6E0F0F),
    wrongMark: Color(0xFFFF9E9E),
    revealedTint: Color(0xFF0F2E6E),
    revealedMark: Color(0xFFA8C8FF),
    pencilText: Color(0xFFCCCCCC),
    gridLine: Color(0xFFFFFFFF),
    arrow: Color(0xFFFFFFFF),
    keyFill: Color(0xFF111111),
    keyText: Color(0xFFFFFFFF),
    keyActionFill: Color(0xFF333333),
    keyPressed: Color(0xFFF28C28),
    lineWidth: 2,
    cellGap: 0,
    correctWash: Color(0xFF4FC3C3),
  );

  /// Grid palette derived from player-chosen colours.
  factory GridColors.custom(CustomTheme t) {
    final dark = t.brightness == Brightness.dark;
    final text = t.onBackground;
    final bg = t.background;
    Color mix(Color a, Color b, double x) => Color.lerp(a, b, x) ?? a;
    final cellFill = dark ? mix(bg, Colors.white, 0.06) : mix(bg, Colors.white, 0.6);
    return GridColors(
      paper: bg,
      clueFill: mix(bg, text, dark ? 0.18 : 0.14),
      clueText: text,
      letterFill: cellFill,
      letterText: text,
      activeWord: mix(t.highlight, cellFill, 0.45),
      activeCell: t.highlight,
      activeBorder: t.primary,
      correctTint: dark ? const Color(0xFF24402A) : const Color(0xFFDCEFD6),
      wrongTint: dark ? const Color(0xFF4C2522) : const Color(0xFFF9D6D0),
      wrongMark: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
      revealedTint: dark ? const Color(0xFF203552) : const Color(0xFFD8E5F6),
      revealedMark: dark ? const Color(0xFF8AB4F8) : const Color(0xFF2B5FA8),
      pencilText: mix(text, bg, 0.45),
      gridLine: mix(text, bg, 0.4),
      arrow: text,
      keyFill: cellFill,
      keyText: text,
      keyActionFill: mix(bg, text, dark ? 0.18 : 0.14),
      keyPressed: t.highlight,
      lineWidth: 1,
    );
  }

  @override
  GridColors copyWith() => this;

  @override
  GridColors lerp(ThemeExtension<GridColors>? other, double t) => t < 0.5 ? this : (other as GridColors? ?? this);
}

/// Light "warm paper" and dark Material 3 themes with Hebrew-friendly fonts.
/// Tokens follow docs/UX.md §2.
abstract final class AppTheme {
  /// Arrow orange: primary CTA and active word.
  static const brand = Color(0xFFF28C28);

  /// Teal: correct.
  static const brandSecondary = Color(0xFF1F8A8A);

  /// Coral: wrong (always with an icon).
  static const coral = Color(0xFFE25D5D);

  /// Gold: coins and stars.
  static const gold = Color(0xFFE0B64A);
  static const ink = Color(0xFF1F2937);
  static const inkDark = Color(0xFFE8E6E1);

  static String fontFamilyFor(String uiLang) => uiLang == 'he' ? 'NotoSansHebrew' : 'Inter';
  static List<String> fallbackFor(String uiLang) => uiLang == 'he' ? const ['Inter'] : const ['NotoSansHebrew'];

  /// Builds the theme. [custom] (when given) overrides brightness, primary,
  /// background and grid highlight with the player's colours; high contrast
  /// always wins over custom colours.
  static ThemeData build({
    required Brightness brightness,
    required bool highContrast,
    required String uiLang,
    CustomTheme? custom,
  }) {
    final useCustom = custom != null && !highContrast;
    if (useCustom) brightness = custom.brightness;
    final dark = brightness == Brightness.dark;
    final grid = useCustom
        ? GridColors.custom(custom)
        : highContrast
            ? (dark ? GridColors.highContrastDark : GridColors.highContrastLight)
            : (dark ? GridColors.dark : GridColors.light);

    var scheme = ColorScheme.fromSeed(
      seedColor: useCustom ? custom.primary : brand,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    scheme = scheme.copyWith(
      primary: useCustom
          ? custom.primary
          : highContrast
              ? (dark ? const Color(0xFFFFA64D) : const Color(0xFFB85C00))
              : (dark ? const Color(0xFFE8893A) : brand),
      onPrimary: useCustom ? bestTextColor(custom.primary) : (highContrast && dark ? Colors.black : Colors.white),
      secondary: brandSecondary,
      onSecondary: Colors.white,
      tertiary: gold,
      error: coral,
      surface: grid.paper,
      onSurface: grid.letterText,
      surfaceContainerHighest: grid.clueFill,
      surfaceContainer: useCustom ? grid.letterFill : (dark ? const Color(0xFF1E2733) : const Color(0xFFFFFFFF)),
      outline: highContrast ? grid.gridLine : (dark ? const Color(0xFF3A4452) : const Color(0xFFC9C2B2)),
    );

    final family = fontFamilyFor(uiLang);
    final fallback = fallbackFor(uiLang);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final text = base.textTheme.apply(fontFamily: family, fontFamilyFallback: fallback);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family, fontFamilyFallback: fallback),
      scaffoldBackgroundColor: grid.paper,
      appBarTheme: AppBarTheme(
        backgroundColor: grid.paper,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: highContrast ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast ? BorderSide(color: grid.gridLine, width: 1.5) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: highContrast ? grid.gridLine : scheme.outline, width: highContrast ? 2 : 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: grid.activeWord,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, contentTextStyle: text.bodyLarge),
      dividerTheme: DividerThemeData(color: grid.gridLine.withValues(alpha: highContrast ? 1 : 0.3)),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        showDragHandle: true,
      ),
      extensions: [grid],
    );
  }
}

extension GridColorsX on BuildContext {
  GridColors get gridColors => Theme.of(this).extension<GridColors>() ?? GridColors.light;
}
