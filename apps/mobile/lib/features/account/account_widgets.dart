import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import 'account_controller.dart';
import 'account_service.dart';
import 'username_rules.dart';

/// Signs in with the device's store account, then asks for a username when
/// the account has none. Returns true once signed in (with or without a
/// username: the picker can be dismissed and reopened from the profile).
Future<bool> runSignIn(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final AccountState state;
  try {
    state = await ref.read(accountProvider.notifier).signIn(AccountProvider.forPlatform);
  } on AccountException catch (e) {
    if (context.mounted && e.error != AccountError.cancelled) {
      showSnack(context, e.error == AccountError.network ? l10n.signInNetwork : l10n.signInFailed);
    }
    return false;
  }
  if (state.username == null && context.mounted) await showUsernameSheet(context);
  return true;
}

/// "Sign in with Google" on Android, "Sign in with Apple" on iOS.
class SignInButton extends ConsumerWidget {
  const SignInButton({super.key, this.onSignedIn});

  final VoidCallback? onSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final apple = AccountProvider.forPlatform == AccountProvider.apple;
    Future<void> tap() async {
      if (await runSignIn(context, ref)) onSignedIn?.call();
    }

    final label = Text(apple ? l10n.signInWithApple : l10n.signInWithGoogle);
    final icon = Icon(apple ? Icons.apple : Icons.account_circle_outlined);
    return SizedBox(
      width: double.infinity,
      child: apple
          ? FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
              onPressed: tap,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(onPressed: tap, icon: icon, label: label),
    );
  }
}

/// Username picker; returns the claimed name, or null when dismissed.
Future<String?> showUsernameSheet(BuildContext context, {String? initial}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => UsernameSheet(initial: initial),
    );

class UsernameSheet extends ConsumerStatefulWidget {
  const UsernameSheet({super.key, this.initial});
  final String? initial;

  @override
  ConsumerState<UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends ConsumerState<UsernameSheet> {
  late final _name = TextEditingController(text: widget.initial ?? '');
  String? _serverError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _serverError = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _localError(String name) {
    if (name.isEmpty) return null;
    final l10n = context.l10n;
    return switch (UsernameRules.problem(name)) {
      null => null,
      'reserved' => l10n.usernameReserved,
      _ => l10n.usernameRules,
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final l10n = context.l10n;
    try {
      final name = await ref.read(accountProvider.notifier).claimUsername(_name.text);
      if (mounted) Navigator.of(context).pop(name);
    } on AccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError = switch (e.error) {
          AccountError.usernameTaken => l10n.usernameTaken,
          AccountError.usernameReserved => l10n.usernameReserved,
          AccountError.usernameInvalid => l10n.usernameRules,
          AccountError.network => l10n.signInNetwork,
          _ => l10n.signInFailed,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = _name.text.trim();
    final error = _serverError ?? _localError(name);
    final valid = UsernameRules.problem(name) == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.usernameTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(l10n.usernameBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: UsernameRules.maxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => valid && !_saving ? _save() : null,
            decoration: InputDecoration(
              labelText: l10n.usernameLabel,
              helperText: l10n.usernameRules,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: valid && !_saving && _serverError == null ? _save : null,
            child: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.usernameSave),
          ),
        ],
      ),
    );
  }
}

/// Profile section: sign-in for guests; username, email and sign-out once
/// signed in. Hidden when cloud sync (Firebase) is off.
class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountServiceProvider).available) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.accountTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!account.signedIn) ...[
              Text(l10n.accountGuestBody, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              const SignInButton(),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(account.provider == AccountProvider.apple ? Icons.apple : Icons.account_circle_outlined),
                title: Text(account.username ?? l10n.usernameMissing),
                subtitle: account.email == null ? null : Text(account.email!),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => showUsernameSheet(context, initial: account.username),
                    child: Text(account.username == null ? l10n.usernameTitle : l10n.usernameChange),
                  ),
                  TextButton(onPressed: () => _confirmSignOut(context, ref), child: Text(l10n.signOut)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.signOutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.signOut)),
        ],
      ),
    );
    if (ok == true) await ref.read(accountProvider.notifier).signOut();
  }
}
