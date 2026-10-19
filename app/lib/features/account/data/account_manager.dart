import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_linker.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/db/app_db.dart';
import '../../../core/http/api_providers.dart';
import '../../game/application/session_sync_providers.dart';

/// Asks the player for their password, to prove it is them before a deletion. [wrongPassword] is
/// true when the last one typed was refused. Null when they cancelled.
typedef PasswordPrompt = Future<String?> Function({required bool wrongPassword});

enum DeleteOutcome {
  /// The account is gone, on the server and in Firebase. The app is a new guest.
  deleted,

  /// The player closed the sign-in that proves it is them. Nothing changed.
  cancelled,
}

/// The server deleted the account's data, but Firebase still has the account: the player stayed
/// signed in. Deleting again finishes it. [cause] is what stopped it ([AuthFailure], or the
/// re-authentication being cancelled when null).
class DeleteIncompleteException implements Exception {
  const DeleteIncompleteException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'DeleteIncompleteException($cause)';
}

/// Signs a registered player out, or deletes their account. Either way the app goes on as a new
/// guest.
class AccountManager {
  AccountManager({
    required this.backend,
    required this.auth,
    required this.credentials,
    required this.api,
    required this.db,
    required this.flushSessions,
    this.flushTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AuthBackend backend;
  final AuthService auth;
  final CredentialSource credentials;
  final AccountApi api;
  final AppDb db;

  /// Sends the finished sessions still waiting to be uploaded. Never throws.
  final Future<void> Function() flushSessions;
  final DateTime Function() _now;

  /// How long a sign-in counts as recent. Firebase asks for one within 5 minutes before a deletion;
  /// a little less leaves time for the server step.
  static const recentSignIn = Duration(minutes: 4);

  /// How long a sign-out waits for waiting sessions to upload.
  final Duration flushTimeout;

  /// Signs out, then starts a new guest. Sessions waiting to upload are sent first, so they count
  /// for this account: they carry no uid, and after the sign-out they would go to the guest. Any
  /// that cannot go now (offline) go to the guest; signing back in later merges them back.
  Future<void> signOut() async {
    final before = backend.current;
    if (!before.hasUid || before.isAnonymous) return;
    try {
      await flushSessions().timeout(flushTimeout);
    } on TimeoutException {
      // Offline, most likely: the rest wait for the guest.
    }
    await backend.signOut();
    await credentials.signOut();
    unawaited(auth.ensureSignedIn());
  }

  /// Deletes the account: its data on the server, then the Firebase account.
  ///
  /// Firebase deletes only after a recent sign-in, so when the last one is older the player signs in
  /// again first, with the same provider ([askPassword] for an email account). A cancel there
  /// changes nothing. Then:
  /// - `DELETE /v1/me`. An [ApiException] (offline, a server error) also changes nothing.
  /// - The account's unsent sessions, local bests and pending link step are dropped.
  /// - The Firebase account is deleted. Should Firebase still ask for a sign-in, it is asked once
  ///   more; failing that, [DeleteIncompleteException].
  ///
  /// Throws [AuthFailure] when the sign-in before anything changed fails.
  Future<DeleteOutcome> deleteAccount({required PasswordPrompt askPassword}) async {
    final before = backend.current;
    if (!before.hasUid || before.isAnonymous) throw const AuthFailure('not-registered');

    if (!await _signedInRecently() && !await _reauthenticate(askPassword)) return DeleteOutcome.cancelled;

    await api.deleteMe();
    await _forgetLocal();

    try {
      await backend.deleteUser();
    } on AuthFailure catch (e) {
      if (e.code != 'requires-recent-login') throw DeleteIncompleteException(e);
      try {
        if (!await _reauthenticate(askPassword)) throw const DeleteIncompleteException();
        await backend.deleteUser();
      } on AuthFailure catch (e) {
        throw DeleteIncompleteException(e);
      }
    }
    await credentials.signOut();
    unawaited(auth.ensureSignedIn());
    return DeleteOutcome.deleted;
  }

  Future<bool> _signedInRecently() async {
    final at = await backend.lastSignInAt();
    return at != null && _now().difference(at) < recentSignIn;
  }

  /// Signs in again with the account's own provider. False when the player cancelled.
  Future<bool> _reauthenticate(PasswordPrompt askPassword) async {
    final state = backend.current;
    final provider = reauthProvider(state, credentials);
    if (provider == null) throw const AuthFailure('reauth-unavailable');
    var wrongPassword = false;
    while (true) {
      final AuthCredential? credential;
      if (provider == 'password') {
        final password = await askPassword(wrongPassword: wrongPassword);
        credential = password == null ? null : EmailAuthProvider.credential(email: state.email!, password: password);
      } else {
        credential = provider == 'apple.com' ? await credentials.apple() : await credentials.google();
      }
      if (credential == null) return false;
      try {
        await backend.reauthenticate(credential);
        return true;
      } on AuthFailure catch (e) {
        if (provider != 'password' || !isWrongPassword(e.code)) rethrow;
        wrongPassword = true;
      }
    }
  }

  Future<void> _forgetLocal() => db.transaction(() async {
    await db.delete(db.pendingSessions).go();
    await db.delete(db.localBests).go();
    await db.delete(db.pendingAccountSync).go();
  });
}

/// The linked provider to sign in again with: one that needs nothing typed first, when this phone
/// offers it. Null when none of the account's providers can be used here.
String? reauthProvider(AuthState state, CredentialSource credentials) {
  final providers = state.providers;
  if (providers.contains('apple.com') && credentials.appleAvailable) return 'apple.com';
  if (providers.contains('google.com') && credentials.googleAvailable) return 'google.com';
  if (providers.contains('password') && state.email != null) return 'password';
  return null;
}

/// Firebase's codes for a password that does not match the account.
bool isWrongPassword(String code) =>
    code == 'wrong-password' || code == 'invalid-credential' || code == 'invalid-login-credentials';

final accountManagerProvider = Provider<AccountManager>((ref) {
  final sync = ref.watch(sessionSyncProvider);
  return AccountManager(
    backend: ref.watch(authBackendProvider),
    auth: ref.watch(authServiceProvider),
    credentials: ref.watch(credentialSourceProvider),
    api: HttpAccountApi(ref.watch(apiClientProvider)),
    db: ref.watch(appDbProvider),
    flushSessions: () => sync.syncNow(force: true),
  );
});
