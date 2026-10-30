import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Store-account sign-in: Google on Android, Apple on iOS.
enum AccountProvider {
  google('google.com'),
  apple('apple.com');

  const AccountProvider(this.id);

  /// Firebase provider id.
  final String id;

  /// The provider offered on this device.
  static AccountProvider get forPlatform => defaultTargetPlatform == TargetPlatform.iOS ? apple : google;
}

class AccountState {
  const AccountState({this.provider, this.email, this.username});

  /// Null while playing as a guest (anonymous Firebase account).
  final AccountProvider? provider;
  final String? email;

  /// Claimed with [AccountService.claimUsername]; null until chosen.
  final String? username;

  bool get signedIn => provider != null;

  AccountState copyWith({String? username}) => AccountState(provider: provider, email: email, username: username ?? this.username);
}

enum AccountError { cancelled, unavailable, network, usernameTaken, usernameInvalid, usernameReserved, failed }

class AccountException implements Exception {
  const AccountException(this.error);
  final AccountError error;
  @override
  String toString() => 'AccountException($error)';
}

/// Links the anonymous Firebase account to Google or Apple (same uid, so
/// progress and coins stay) and claims a unique username through the
/// `claimUsername` callable. Errors are [AccountException]s.
abstract class AccountService {
  const AccountService();
  bool get available;
  Future<AccountState> load();
  Future<AccountState> signIn(AccountProvider provider);
  Future<String> claimUsername(String username);

  /// Back to a fresh guest account; data saved in the signed-in account stays there.
  Future<void> signOut();
}

class DisabledAccountService extends AccountService {
  const DisabledAccountService();
  @override
  bool get available => false;
  @override
  Future<AccountState> load() async => const AccountState();
  @override
  Future<AccountState> signIn(AccountProvider provider) => throw const AccountException(AccountError.unavailable);
  @override
  Future<String> claimUsername(String username) => throw const AccountException(AccountError.unavailable);
  @override
  Future<void> signOut() async {}
}

class FakeAccountService extends AccountService {
  FakeAccountService({this.state = const AccountState(), Set<String>? taken, this.signInError}) : taken = taken ?? {};
  AccountState state;
  final Set<String> taken;
  AccountError? signInError;
  @override
  bool get available => true;
  @override
  Future<AccountState> load() async => state;
  @override
  Future<AccountState> signIn(AccountProvider provider) async {
    if (signInError != null) throw AccountException(signInError!);
    return state = AccountState(provider: provider, email: 'player@example.com', username: state.username);
  }

  @override
  Future<String> claimUsername(String username) async {
    if (!state.signedIn) throw const AccountException(AccountError.failed);
    if (taken.contains(username.toLowerCase())) throw const AccountException(AccountError.usernameTaken);
    state = state.copyWith(username: username);
    return username;
  }

  @override
  Future<void> signOut() async => state = const AccountState();
}

class FirebaseAccountService extends AccountService {
  FirebaseAccountService({this.authClient, this.firestoreClient, this.functionsClient, this.googleServerClientId});

  /// Injected in tests; production uses the default instances.
  final FirebaseAuth? authClient;
  final FirebaseFirestore? firestoreClient;
  final FirebaseFunctions? functionsClient;

  /// OAuth web client id; null reads `default_web_client_id` from google-services.json.
  final String? googleServerClientId;
  bool _googleReady = false;

  FirebaseAuth get _auth => authClient ?? FirebaseAuth.instance;

  @override
  bool get available => true;

  @override
  Future<AccountState> load() async {
    final user = _auth.currentUser;
    final provider = _linked(user);
    if (user == null || provider == null) return const AccountState();
    String? username;
    try {
      final snap = await (firestoreClient ?? FirebaseFirestore.instance).collection('users').doc(user.uid).get();
      username = snap.data()?['username'] as String?;
    } catch (e) {
      debugPrint('account load failed: $e');
    }
    final email = user.email ?? user.providerData.map((p) => p.email).whereType<String>().firstOrNull;
    return AccountState(provider: provider, email: email, username: username);
  }

  AccountProvider? _linked(User? user) {
    for (final info in user?.providerData ?? const <UserInfo>[]) {
      for (final p in AccountProvider.values) {
        if (info.providerId == p.id) return p;
      }
    }
    return null;
  }

  @override
  Future<AccountState> signIn(AccountProvider provider) async {
    try {
      switch (provider) {
        case AccountProvider.google:
          await _linkOrSwitch(await _googleCredential());
        case AccountProvider.apple:
          await _linkOrSwitchWithProvider(AppleAuthProvider()..addScope('email'));
      }
    } on GoogleSignInException catch (e) {
      throw AccountException(e.code == GoogleSignInExceptionCode.canceled ? AccountError.cancelled : AccountError.failed);
    } on FirebaseAuthException catch (e) {
      debugPrint('sign-in failed: ${e.code}');
      throw AccountException(switch (e.code) {
        'network-request-failed' => AccountError.network,
        'web-context-canceled' || 'canceled' || 'user-cancelled' => AccountError.cancelled,
        _ => AccountError.failed,
      });
    }
    return load();
  }

  Future<AuthCredential> _googleCredential() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: googleServerClientId);
      _googleReady = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AccountException(AccountError.failed);
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Links to the current guest account; when the store account already
  /// belongs to a Chetz account (another device), switches to that one.
  Future<void> _linkOrSwitch(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      await _auth.signInWithCredential(credential);
      return;
    }
    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') return;
      if (e.code != 'credential-already-in-use') rethrow;
      await _auth.signInWithCredential(e.credential ?? credential);
    }
  }

  Future<void> _linkOrSwitchWithProvider(AuthProvider provider) async {
    final user = _auth.currentUser;
    if (user == null) {
      await _auth.signInWithProvider(provider);
      return;
    }
    try {
      await user.linkWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') return;
      if (e.code != 'credential-already-in-use' || e.credential == null) rethrow;
      await _auth.signInWithCredential(e.credential!);
    }
  }

  @override
  Future<String> claimUsername(String username) async {
    try {
      final res = await (functionsClient ?? FirebaseFunctions.instance).httpsCallable('claimUsername').call<Map<String, dynamic>>({'username': username});
      return res.data['username'] as String;
    } on FirebaseFunctionsException catch (e) {
      final reason = e.details is Map ? (e.details as Map)['reason'] : null;
      throw AccountException(switch (e.code) {
        'already-exists' => AccountError.usernameTaken,
        'invalid-argument' => reason == 'reserved' ? AccountError.usernameReserved : AccountError.usernameInvalid,
        'unavailable' || 'deadline-exceeded' => AccountError.network,
        _ => AccountError.failed,
      });
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('google sign-out failed: $e');
    }
    await _auth.signOut();
    await _auth.signInAnonymously();
  }
}
