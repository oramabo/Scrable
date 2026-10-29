import 'package:flutter/material.dart';

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

  static const light = GridColors(
    paper: Color(0xFFF6F1E7),
    clueFill: Color(0xFFE6DDCB),
    clueText: Color(0xFF3A3129),
    letterFill: Color(0xFFFFFDF8),
    letterText: Color(0xFF1F1A15),
    activeWord: Color(0xFFFFE9BC),
    activeCell: Color(0xFFFFCF73),
    activeBorder: Color(0xFFB5471F),
    correctTint: Color(0xFFDCEFD6),
    wrongTint: Color(0xFFF9D6D0),
    wrongMark: Color(0xFFB3261E),
    revealedTint: Color(0xFFD8E5F6),
    revealedMark: Color(0xFF2B5FA8),
    pencilText: Color(0xFF8A8176),
    gridLine: Color(0xFF8C8273),
    arrow: Color(0xFF4A4136),
    keyFill: Color(0xFFFFFCF6),
    keyText: Color(0xFF1F1A15),
    keyActionFill: Color(0xFFE6DDCB),
    keyPressed: Color(0xFFFFCF73),
    lineWidth: 1,
  );

  static const dark = GridColors(
    paper: Color(0xFF16140F),
    clueFill: Color(0xFF3A342B),
    clueText: Color(0xFFEAE2D2),
    letterFill: Color(0xFF221F19),
    letterText: Color(0xFFF5EFE4),
    activeWord: Color(0xFF4A3B1A),
    activeCell: Color(0xFF7A5A1E),
    activeBorder: Color(0xFFF2A35C),
    correctTint: Color(0xFF24402A),
    wrongTint: Color(0xFF4C2522),
    wrongMark: Color(0xFFFF8A80),
    revealedTint: Color(0xFF203552),
    revealedMark: Color(0xFF8AB4F8),
    pencilText: Color(0xFF9A9183),
    gridLine: Color(0xFF5A5245),
    arrow: Color(0xFFD8D0C0),
    keyFill: Color(0xFF2B2720),
    keyText: Color(0xFFF5EFE4),
    keyActionFill: Color(0xFF3A342B),
    keyPressed: Color(0xFF7A5A1E),
    lineWidth: 1,
  );

  static const highContrastLight = GridColors(
    paper: Color(0xFFFFFFFF),
    clueFill: Color(0xFFCFCFCF),
    clueText: Color(0xFF000000),
    letterFill: Color(0xFFFFFFFF),
    letterText: Color(0xFF000000),
    activeWord: Color(0xFFFFF176),
    activeCell: Color(0xFFFFB300),
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
    keyPressed: Color(0xFFFFB300),
    lineWidth: 2,
  );

  static const highContrastDark = GridColors(
    paper: Color(0xFF000000),
    clueFill: Color(0xFF333333),
    clueText: Color(0xFFFFFFFF),
    letterFill: Color(0xFF000000),
    letterText: Color(0xFFFFFFFF),
    activeWord: Color(0xFF5C4D00),
    activeCell: Color(0xFFA88600),
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
    keyPressed: Color(0xFFA88600),
    lineWidth: 2,
  );

  @override
  GridColors copyWith() => this;

  @override
  GridColors lerp(ThemeExtension<GridColors>? other, double t) => t < 0.5 ? this : (other as GridColors? ?? this);
}

/// Light "warm paper" and dark Material 3 themes with Hebrew-friendly fonts.
abstract final class AppTheme {
  static const brand = Color(0xFFB5471F);
  static const brandSecondary = Color(0xFF2F6F6D);

  static String fontFamilyFor(String uiLang) => uiLang == 'he' ? 'NotoSansHebrew' : 'Inter';
  static List<String> fallbackFor(String uiLang) => uiLang == 'he' ? const ['Inter'] : const ['NotoSansHebrew'];

  static ThemeData build({required Brightness brightness, required bool highContrast, required String uiLang}) {
    final dark = brightness == Brightness.dark;
    final grid = highContrast
        ? (dark ? GridColors.highContrastDark : GridColors.highContrastLight)
        : (dark ? GridColors.dark : GridColors.light);

    var scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    scheme = scheme.copyWith(
      primary: highContrast ? (dark ? const Color(0xFFFFB38A) : const Color(0xFF7A2A0C)) : (dark ? const Color(0xFFF2A35C) : brand),
      secondary: brandSecondary,
      surface: grid.paper,
      onSurface: grid.letterText,
      surfaceContainerHighest: grid.clueFill,
      surfaceContainer: dark ? const Color(0xFF221F19) : const Color(0xFFFFFCF6),
      outline: highContrast ? grid.gridLine : null,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
