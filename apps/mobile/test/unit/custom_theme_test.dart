import 'package:chetz_app/core/theme/app_theme.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/settings/theme/custom_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WCAG contrast', () {
    test('black on white is 21:1, same colour is 1:1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
    });

    test('mid grey on white fails AA for text', () {
      final grey = const Color(0xFF9E9E9E);
      expect(contrastRatio(grey, Colors.white), lessThan(minTextContrast));
      expect(bestTextColor(Colors.white), Colors.black);
      expect(bestTextColor(const Color(0xFF141A22)), Colors.white);
    });

    test('report flags unreadable palettes and refuses them', () {
      const good = CustomTheme(primary: Color(0xFFF28C28), background: Color(0xFFF7F3EA), highlight: Color(0xFFF9C68E));
      expect(ContrastReport.of(good).textOk, isTrue);
      expect(ContrastReport.of(good).isApplicable, isTrue);
      // Any grey background reads against black or white (≥ 4.58:1), so the
      // refusal comes from the highlight: black text on a dark highlight.
      const bad = CustomTheme(primary: Color(0xFF808080), background: Color(0xFFFFFFFF), highlight: Color(0xFF333333));
      final r = ContrastReport.of(bad);
      expect(r.textOk, isTrue);
      expect(r.highlightOk, isFalse);
      expect(r.textOnHighlight, lessThan(4.5));
      expect(r.isApplicable, isFalse);
    });

    test('brightness derives from the background', () {
      expect(const CustomTheme(background: Color(0xFF141A22)).brightness, Brightness.dark);
      expect(const CustomTheme(background: Color(0xFFF7F3EA)).brightness, Brightness.light);
    });
  });

  group('CustomTheme persistence', () {
    test('json round trip and settings integration', () {
      const t = CustomTheme(primary: Color(0xFF123456), background: Color(0xFFFFFFFF), highlight: Color(0xFFABCDEF));
      expect(CustomTheme.fromJson(t.toJson()), t);
      final s = const AppSettings(useCustomTheme: true, customTheme: t);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.useCustomTheme, isTrue);
      expect(back.customTheme, t);
    });

    test('hex helpers', () {
      expect(hexOf(const Color(0xFF00FF7F)), '#00FF7F');
      expect(parseHex('#00ff7f'), const Color(0xFF00FF7F));
      expect(parseHex('zzz'), isNull);
    });
  });

  group('AppTheme', () {
    test('custom colours drive primary, background and grid highlight', () {
      const t = CustomTheme(primary: Color(0xFF1E88E5), background: Color(0xFFFFFFFF), highlight: Color(0xFFFFE082));
      final theme = AppTheme.build(brightness: Brightness.light, highContrast: false, uiLang: 'he', custom: t);
      expect(theme.colorScheme.primary, t.primary);
      expect(theme.scaffoldBackgroundColor, t.background);
      final grid = theme.extension<GridColors>()!;
      expect(grid.activeCell, t.highlight);
      expect(grid.paper, t.background);
    });

    test('high contrast wins over custom colours', () {
      const t = CustomTheme(primary: Color(0xFF1E88E5), background: Color(0xFFFFFFFF), highlight: Color(0xFFFFE082));
      final theme = AppTheme.build(brightness: Brightness.light, highContrast: true, uiLang: 'en', custom: t);
      expect(theme.extension<GridColors>()!.gridLine, GridColors.highContrastLight.gridLine);
      expect(theme.colorScheme.primary, isNot(t.primary));
    });

    test('UX tokens: paper, ink and arrow orange', () {
      final light = AppTheme.build(brightness: Brightness.light, highContrast: false, uiLang: 'he');
      expect(light.scaffoldBackgroundColor, const Color(0xFFF7F3EA));
      expect(light.colorScheme.primary, const Color(0xFFF28C28));
      expect(light.colorScheme.onSurface, const Color(0xFF1F2937));
      final dark = AppTheme.build(brightness: Brightness.dark, highContrast: false, uiLang: 'he');
      expect(dark.scaffoldBackgroundColor, const Color(0xFF141A22));
    });
  });
}
