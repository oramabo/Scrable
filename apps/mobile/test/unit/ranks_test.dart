import 'package:chetz_app/features/profile/profile_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ranks (GAME_PLAN §3.4 טירון → מאסטר)', () {
    test('thresholds by puzzles completed', () {
      expect(Ranks.forPuzzles(0).nameHe, 'טירון');
      expect(Ranks.forPuzzles(4).nameHe, 'טירון');
      expect(Ranks.forPuzzles(5).nameHe, 'חניך');
      expect(Ranks.forPuzzles(150).nameEn, 'Expert');
      expect(Ranks.forPuzzles(500).nameHe, 'מאסטר');
      expect(Ranks.forPuzzles(9999).nameHe, 'מאסטר');
    });

    test('progress towards the next rank', () {
      expect(Ranks.progress(0), 0);
      expect(Ranks.progress(10), closeTo(0.5, 0.001)); // between 5 and 15
      expect(Ranks.progress(500), 1);
      expect(Ranks.next(Ranks.forPuzzles(500)), isNull);
      expect(Ranks.next(Ranks.forPuzzles(0))!.minPuzzles, 5);
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
