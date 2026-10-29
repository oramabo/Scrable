import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Player-chosen colours for the custom theme.
@immutable
class CustomTheme {
  const CustomTheme({
    this.primary = const Color(0xFF1F8A8A),
    this.background = const Color(0xFFF7F3EA),
    this.highlight = const Color(0xFFF9C68E),
  });

  final Color primary;
  final Color background;

  /// Active word / active cell colour in the grid.
  final Color highlight;

  Brightness get brightness => background.computeLuminance() < 0.35 ? Brightness.dark : Brightness.light;

  /// Text colour with the best contrast against the background.
  Color get onBackground => bestTextColor(background);

  CustomTheme copyWith({Color? primary, Color? background, Color? highlight}) => CustomTheme(
        primary: primary ?? this.primary,
        background: background ?? this.background,
        highlight: highlight ?? this.highlight,
      );

  Map<String, dynamic> toJson() => {'primary': primary.toARGB32(), 'background': background.toARGB32(), 'highlight': highlight.toARGB32()};

  static CustomTheme fromJson(Map<String, dynamic> j) => CustomTheme(
        primary: Color((j['primary'] as int?) ?? 0xFF1F8A8A),
        background: Color((j['background'] as int?) ?? 0xFFF7F3EA),
        highlight: Color((j['highlight'] as int?) ?? 0xFFF9C68E),
      );

  @override
  bool operator ==(Object other) =>
      other is CustomTheme && other.primary == primary && other.background == background && other.highlight == highlight;
  @override
  int get hashCode => Object.hash(primary, background, highlight);
}

/// WCAG 2.1 contrast ratio (1..21) using relative luminance.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = math.max(la, lb);
  final dark = math.min(la, lb);
  return (light + 0.05) / (dark + 0.05);
}

/// Minimum contrast for normal text (WCAG AA).
const double minTextContrast = 4.5;

/// Minimum contrast for large text / UI components (WCAG AA).
const double minUiContrast = 3.0;

/// Black or white, whichever contrasts more with [background].
Color bestTextColor(Color background) =>
    contrastRatio(Colors.black, background) >= contrastRatio(Colors.white, background) ? Colors.black : Colors.white;

/// Warnings for a custom theme: text on background, primary on background,
/// text on highlight.
class ContrastReport {
  const ContrastReport({required this.textOnBackground, required this.primaryOnBackground, required this.textOnHighlight});

  final double textOnBackground;
  final double primaryOnBackground;
  final double textOnHighlight;

  bool get textOk => textOnBackground >= minTextContrast;
  bool get primaryOk => primaryOnBackground >= minUiContrast;
  bool get highlightOk => textOnHighlight >= minTextContrast;
  bool get allOk => textOk && primaryOk && highlightOk;

  /// The palette may be applied: text stays readable on the background and on
  /// the highlighted word (UX §2 — combinations under 4.5:1 are refused).
  bool get isApplicable => textOk && highlightOk;

  static ContrastReport of(CustomTheme t) => ContrastReport(
        textOnBackground: contrastRatio(t.onBackground, t.background),
        primaryOnBackground: contrastRatio(t.primary, t.background),
        textOnHighlight: contrastRatio(t.onBackground, t.highlight),
      );
}

/// Blends [a] towards [b] by [t].
Color blend(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RRGGBB` / `RRGGBB`; null when invalid.
Color? parseHex(String text) {
  final s = text.trim().replaceFirst('#', '');
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
