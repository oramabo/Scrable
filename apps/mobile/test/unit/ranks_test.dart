import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/profile/profile_model.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XP ranks (XpCurve, טירון → מאסטר)', () {
    test('rank titles follow the XP level', () {
      expect(rankTitle(XpCurve.rankIndex(XpCurve.levelForXp(0)), 'he'), 'טירון');
      expect(rankTitle(XpCurve.rankIndex(5), 'he'), 'חובב');
      expect(rankTitle(XpCurve.rankIndex(20), 'en'), 'Advanced');
      expect(rankTitle(XpCurve.rankIndex(55), 'he'), 'מאסטר');
      expect(rankTitle(99, 'en'), 'Master', reason: 'clamped');
    });

    test('level progress is 0..1 inside a level', () {
      expect(XpCurve.levelProgress(0), 0);
      final mid = XpCurve.xpForLevel(3) + (XpCurve.xpForLevel(4) - XpCurve.xpForLevel(3)) ~/ 2;
      expect(XpCurve.levelProgress(mid), closeTo(0.5, 0.02));
      expect(XpCurve.levelForXp(XpCurve.xpForLevel(7)), 7);
    });
  });

  group('Avatars & profile', () {
    test('12 built-in avatars with unique ids', () {
      expect(Avatars.all.length, 12);
      expect(Avatars.all.map((a) => a.id).toSet().length, 12);
      expect(Avatars.byId('nope').id, Avatars.all.first.id);
      expect(Avatars.byId('owl').nameEn, 'Owl');
    });

    test('profile json round trip and name clearing', () {
      const p = ProfileData(displayName: 'דנה', avatarId: 'fox', updatedAt: 5);
      final back = ProfileData.fromJson(p.toJson());
      expect(back.displayName, 'דנה');
      expect(back.avatarId, 'fox');
      expect(p.copyWith(clearName: true).displayName, isNull);
      expect(const ProfileData().displayName, isNull, reason: 'localised default is applied by the UI');
    });
  });
}
