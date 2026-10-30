import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/features/account/account_controller.dart';
import 'package:chetz_app/features/account/account_service.dart';
import 'package:chetz_app/features/account/account_widgets.dart';
import 'package:chetz_app/features/account/username_rules.dart';
import 'package:chetz_app/features/profile/profile_controller.dart';
import 'package:chetz_app/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  group('UsernameRules (mirror of functions/src/lib/username.ts)', () {
    test('accepts Hebrew and Latin letters, digits and inner _ or .', () {
      for (final ok in ['dana', 'דנה_לוי', 'Puzzler99', 'a.b_c', 'חץ2026']) {
        expect(UsernameRules.problem(ok), isNull, reason: ok);
      }
    });

    test('rejects bad lengths, characters and reserved names', () {
      expect(UsernameRules.problem('ab'), 'length');
      expect(UsernameRules.problem('x' * 21), 'length');
      for (final bad in ['_dana', 'dana.', 'da..na', 'da na', 'דָּנָה', 'dana!', 'émile']) {
        expect(UsernameRules.problem(bad), 'characters', reason: bad);
      }
      for (final reserved in ['Admin', 'ad.min', 'CHETZ', 'מנהל']) {
        expect(UsernameRules.problem(reserved), 'reserved', reason: reserved);
      }
    });

    test('the key ignores case, final letters and separators', () {
      expect(UsernameRules.key('Dana_Levi'), UsernameRules.key('dana.levi'));
      expect(UsernameRules.key('שלום'), UsernameRules.key('שלומ'));
    });
  });

  group('account card', () {
    late MapContentSource content;
    setUpAll(() async => content = await loadBundledContent());

    Future<ProviderContainer> pumpProfile(WidgetTester tester, AccountService service) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(wrapScreen(
        const ProfileTab(),
        overrides: testOverrides(content: content, extra: [accountServiceProvider.overrideWithValue(service)]),
      ));
      await settle(tester);
      return ProviderScope.containerOf(tester.element(find.byType(ProfileTab)));
    }

    testWidgets('hidden while cloud sync is off', (tester) async {
      await pumpProfile(tester, const DisabledAccountService());
      expect(find.byType(SignInButton), findsNothing);
      expect(find.text('חשבון'), findsNothing);
    });

    testWidgets('guest → sign in with Google → a taken name is refused → the username becomes the profile name', (tester) async {
      final service = FakeAccountService(taken: {'dana'});
      final container = await pumpProfile(tester, service);

      await tester.tap(find.text('התחברות עם Google'));
      await settle(tester);
      expect(find.byType(UsernameSheet), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'שמירה')).onPressed, isNull, reason: 'too short');

      await tester.enterText(find.byType(TextField), 'dana');
      await tester.pump();
      await tester.tap(find.text('שמירה'));
      await settle(tester);
      expect(find.text('שם המשתמש הזה כבר תפוס'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'דנה_לוי');
      await tester.pump();
      await tester.tap(find.text('שמירה'));
      await settle(tester);

      expect(find.byType(UsernameSheet), findsNothing);
      expect(container.read(accountProvider).username, 'דנה_לוי');
      expect(container.read(profileProvider).displayName, 'דנה_לוי');
      expect(find.text('player@example.com'), findsOneWidget);
      expect(find.text('שינוי שם משתמש'), findsOneWidget);
    });

    testWidgets('a cancelled sign-in stays a guest without an error', (tester) async {
      final service = FakeAccountService(signInError: AccountError.cancelled);
      final container = await pumpProfile(tester, service);
      await tester.tap(find.text('התחברות עם Google'));
      await settle(tester);
      expect(find.byType(UsernameSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(container.read(accountProvider).signedIn, isFalse);
    });

    testWidgets('signing out returns to the guest card', (tester) async {
      final service = FakeAccountService(state: const AccountState(provider: AccountProvider.google, email: 'p@example.com', username: 'dana'));
      final container = await pumpProfile(tester, service);
      expect(find.text('p@example.com'), findsOneWidget);
      await tester.tap(find.text('התנתקות'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'התנתקות'));
      await settle(tester);
      expect(container.read(accountProvider).signedIn, isFalse);
      expect(find.text('התחברות עם Google'), findsOneWidget);
    });
  });
}
