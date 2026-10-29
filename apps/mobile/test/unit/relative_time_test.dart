import 'package:chetz_app/core/util/relative_time.dart';
import 'package:chetz_app/l10n/generated/app_localizations_en.dart';
import 'package:chetz_app/l10n/generated/app_localizations_he.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final he = AppLocalizationsHe();
  final en = AppLocalizationsEn();

  test('Hebrew countdowns read as whole phrases', () {
    expect(relativeDuration(he, const Duration(hours: 12)), 'בעוד 12 שעות');
    expect(relativeDuration(he, const Duration(hours: 1, minutes: 20)), 'בעוד שעה');
    expect(relativeDuration(he, const Duration(hours: 2)), 'בעוד שעתיים');
    expect(relativeDuration(he, const Duration(minutes: 45)), 'בעוד 45 דקות');
    expect(relativeDuration(he, const Duration(days: 3, hours: 2)), 'בעוד 3 ימים');
    expect(he.dailyResetIn(relativeDuration(he, const Duration(hours: 12))), 'מתחדש בעוד 12 שעות');
    expect(he.missionResetIn(relativeDuration(he, const Duration(minutes: 5))), 'מתאפס בעוד 5 דקות');
  });

  test('English countdowns are short', () {
    expect(relativeDuration(en, const Duration(hours: 12)), 'in 12 h');
    expect(relativeDuration(en, const Duration(hours: 1)), 'in 1 h');
    expect(relativeDuration(en, const Duration(minutes: 3)), 'in 3 min');
    expect(relativeDuration(en, const Duration(days: 2)), 'in 2 days');
    expect(relativeDuration(en, Duration.zero), 'right now');
    expect(en.dailyResetIn(relativeDuration(en, const Duration(hours: 12))), 'Resets in 12 h');
  });
}
