import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/providers.dart';
import '../profile/profile_controller.dart';
import 'account_service.dart';

/// The player's store account and username. Signing in links the guest
/// account, so nothing local changes; a claimed username also becomes the
/// profile name shown in the app.
class AccountController extends Notifier<AccountState> {
  @override
  AccountState build() {
    unawaited(_load());
    return const AccountState();
  }

  AccountService get _service => ref.read(accountServiceProvider);

  Future<void> _load() async {
    final loaded = await _service.load();
    if (ref.mounted) state = loaded;
  }

  Future<AccountState> signIn(AccountProvider provider) async {
    final next = await _service.signIn(provider);
    state = next;
    ref.read(analyticsProvider).track(AnalyticsEvents.signedIn, {'provider': provider.id, 'has_username': next.username != null});
    if (next.username != null) ref.read(profileProvider.notifier).setDisplayName(next.username!);
    return next;
  }

  Future<String> claimUsername(String username) async {
    final claimed = await _service.claimUsername(username.trim());
    state = state.copyWith(username: claimed);
    ref.read(profileProvider.notifier).setDisplayName(claimed);
    ref.read(analyticsProvider).track(AnalyticsEvents.usernameClaimed);
    return claimed;
  }

  Future<void> signOut() async {
    await _service.signOut();
    state = const AccountState();
  }
}

final accountProvider = NotifierProvider<AccountController, AccountState>(AccountController.new);
