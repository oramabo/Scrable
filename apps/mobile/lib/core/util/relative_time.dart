import '../l10n/l10n.dart';

/// Locale-aware "time until" text: "בעוד 12 שעות" / "in 12 h". Days when a
/// day or more is left, otherwise whole hours, otherwise minutes. Never mixes
/// units so the phrase reads naturally inside RTL and LTR sentences.
String relativeDuration(AppLocalizations l10n, Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d.inHours >= 24) return l10n.relativeDays(d.inDays);
  if (d.inHours >= 1) return l10n.relativeHours(d.inHours);
  return l10n.relativeMinutes(d.inMinutes);
}
