import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/app_config.dart';
import '../db/app_db.dart';
import '../http/api_client.dart';
import '../http/api_providers.dart';
import 'auth_service.dart';

/// Gets a provider credential from the platform's sign-in UI. Null when the player cancels.
abstract class CredentialSource {
  bool get googleAvailable;
  bool get appleAvailable;
  Future<AuthCredential?> google();
  Future<AuthCredential?> apple();
}

class PlatformCredentialSource implements CredentialSource {
  bool _googleReady = false;

  @override
  bool get googleAvailable => AppConfig.googleServerClientId.isNotEmpty;

  // Sign in with Apple is required on iOS (App Store guideline 4.8) and optional on Android.
  @override
  bool get appleAvailable =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || (AppConfig.appleOnAndroid && defaultTargetPlatform == TargetPlatform.android));

  @override
  Future<AuthCredential?> google() async {
    final signIn = GoogleSignIn.instance;
    if (!_googleReady) {
      await signIn.initialize(serverClientId: AppConfig.googleServerClientId);
      _googleReady = true;
    }
    try {
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure('google-no-id-token');
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthFailure('google-${e.code.name}', e.description);
    }
  }

  @override
  Future<AuthCredential?> apple() async {
    // Apple embeds the SHA-256 of the nonce in its token; Firebase checks it against the raw one,
    // so a token caught in transit cannot be replayed.
    final rawNonce = randomNonce();
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: sha256Hex(rawNonce),
      );
      final idToken = apple.identityToken;
      if (idToken == null) throw const AuthFailure('apple-no-id-token');
      return OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthFailure('apple-${e.code.name}', e.message);
    }
  }
}

/// 32 random characters from a URL-safe alphabet, from a secure source.
String randomNonce([int length = 32, Random? random]) {
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final r = random ?? Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// The account endpoints the linker calls.
abstract class AccountApi {
  /// `POST /v1/me/registered`: the uid was kept; the server rebuilds its leaderboard rows.
  Future<void> registered();

  /// `POST /v1/me/merge`: moves the guest's sessions into the signed-in account.
  Future<void> merge(String anonymousIdToken);
}

class HttpAccountApi implements AccountApi {
  HttpAccountApi(this.client);

  final ApiClient client;

  @override
  Future<void> registered() => client.postJson('/v1/me/registered');

  @override
  Future<void> merge(String anonymousIdToken) =>
      client.postJson('/v1/me/merge', body: {'anonymousIdToken': anonymousIdToken});
}

/// A server step still to send. [anonymousIdToken] is set for a merge.
class PendingAccountStep {
  const PendingAccountStep.registered() : anonymousIdToken = null;
  const PendingAccountStep.merge(String this.anonymousIdToken);

  final String? anonymousIdToken;
  bool get isMerge => anonymousIdToken != null;
}

abstract class PendingAccountStore {
  Future<PendingAccountStep?> read();
  Future<void> write(PendingAccountStep step);
  Future<void> clear();
}

class DbPendingAccountStore implements PendingAccountStore {
  DbPendingAccountStore(this.db);

  final AppDb db;

  @override
  Future<PendingAccountStep?> read() async {
    final row = await db.select(db.pendingAccountSync).getSingleOrNull();
    if (row == null) return null;
    final token = row.anonymousIdToken;
    return row.kind == 'merge' && token != null ? PendingAccountStep.merge(token) : const PendingAccountStep.registered();
  }

  @override
  Future<void> write(PendingAccountStep step) => db.into(db.pendingAccountSync).insertOnConflictUpdate(
    PendingAccountSyncCompanion.insert(
      kind: step.isMerge ? 'merge' : 'registered',
      anonymousIdToken: Value(step.anonymousIdToken),
      createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    ),
  );

  @override
  Future<void> clear() => db.delete(db.pendingAccountSync).go();
}

enum LinkOutcome {
  /// The guest's uid now has the provider; its history stays where it is.
  linked,

  /// The provider belonged to another account. The app is now signed in to it, and the guest's
  /// history is merged into it.
  merged,

  /// Signed in to an existing account with no guest history to bring.
  signedIn,

  /// The player closed the sign-in UI.
  cancelled,
}

class LinkResult {
  const LinkResult(this.outcome, {this.serverSynced = true});

  final LinkOutcome outcome;

  /// False when the Firebase part worked but the server call did not (offline). The app is
  /// signed in either way; the server step is kept and retried by [AccountLinker.retryPending].
  final bool serverSynced;
}

/// Turns a guest into a registered player.
///
/// Linking keeps the uid, so the guest's sessions are already the account's; the server only has
/// to mark it registered and rebuild its leaderboard rows. When the credential already belongs to
/// another account, the guest's ID token is taken (and saved) first, then the app signs in to that
/// account and asks the server to merge the guest's history into it.
class AccountLinker {
  AccountLinker({required this.backend, required this.credentials, required this.api, required this.store});

  final AuthBackend backend;
  final CredentialSource credentials;
  final AccountApi api;
  final PendingAccountStore store;

  Future<void>? _retrying;

  Future<LinkResult> linkWithGoogle() async {
    final credential = await credentials.google();
    return credential == null ? const LinkResult(LinkOutcome.cancelled) : _link(credential);
  }

  Future<LinkResult> linkWithApple() async {
    final credential = await credentials.apple();
    return credential == null ? const LinkResult(LinkOutcome.cancelled) : _link(credential);
  }

  /// A new email account for this guest. An email that already has an account signs in to it
  /// (with this password) and merges the guest's history.
  Future<LinkResult> linkWithEmail(String email, String password) =>
      _link(EmailAuthProvider.credential(email: email.trim(), password: password));

  /// A returning player signing in with email. A guest's history on this phone is merged in.
  Future<LinkResult> signInWithEmail(String email, String password) =>
      _signInTo(EmailAuthProvider.credential(email: email.trim(), password: password));

  Future<void> sendPasswordReset(String email) => backend.sendPasswordResetEmail(email.trim());

  Future<LinkResult> _link(AuthCredential credential) async {
    final before = backend.current;
    // No user at all yet (first launch offline): there is no guest history to keep.
    if (!before.hasUid) return _signInTo(credential);
    try {
      await backend.linkWithCredential(credential);
    } on CredentialInUseException catch (e) {
      // Two registered accounts are never merged; a registered player has to sign out first.
      if (!before.isAnonymous) throw const AuthFailure('credential-already-in-use');
      return _signInTo(e.credential);
    }
    // The cached token still says "anonymous"; the server must see the linked provider.
    await backend.idToken(forceRefresh: true);
    return LinkResult(LinkOutcome.linked, serverSynced: await _send(const PendingAccountStep.registered()));
  }

  Future<LinkResult> _signInTo(AuthCredential credential) async {
    final wasGuest = backend.current.hasUid && backend.current.isAnonymous;
    // The guest's token has to be taken before signing in: afterwards the guest is gone from
    // this device. It is saved first, so a crash or lost connection does not lose the history.
    final guestToken = wasGuest ? await backend.idToken() : null;
    if (guestToken != null) await store.write(PendingAccountStep.merge(guestToken));
    try {
      await backend.signInWithCredential(credential);
    } catch (_) {
      // Still the guest (a wrong password, say): nothing to merge.
      if (guestToken != null) await store.clear();
      rethrow;
    }
    if (guestToken == null) return const LinkResult(LinkOutcome.signedIn);
    return LinkResult(LinkOutcome.merged, serverSynced: await _send(PendingAccountStep.merge(guestToken)));
  }

  /// Sends [step], keeping it for a retry if the server could not be reached.
  Future<bool> _send(PendingAccountStep step) async {
    await store.write(step);
    try {
      final token = step.anonymousIdToken;
      if (token != null) {
        await api.merge(token);
      } else {
        await api.registered();
      }
      await store.clear();
      return true;
    } on NetworkException {
      return false;
    } on ServerException {
      return false;
    } on RateLimitedException {
      return false;
    } on ApiException {
      // 401 (the guest token is over 30 days old), 403, 409 (the guest has registered on its own):
      // retrying cannot help.
      await store.clear();
      return false;
    }
  }

  /// Sends a server step left over from an earlier link. Called on start and when the user changes.
  Future<void> retryPending() => _retrying ??= _retry().whenComplete(() => _retrying = null);

  Future<void> _retry() async {
    final step = await store.read();
    if (step == null) return;
    // Only a registered user can send either step; a guest who has not finished linking waits.
    if (!backend.current.hasUid || backend.current.isAnonymous) return;
    if (!step.isMerge) await backend.idToken(forceRefresh: true);
    await _send(step);
  }
}

final credentialSourceProvider = Provider<CredentialSource>((ref) => PlatformCredentialSource());

final accountLinkerProvider = Provider<AccountLinker>(
  (ref) => AccountLinker(
    backend: ref.watch(authBackendProvider),
    credentials: ref.watch(credentialSourceProvider),
    api: HttpAccountApi(ref.watch(apiClientProvider)),
    store: DbPendingAccountStore(ref.watch(appDbProvider)),
  ),
);

/// Retries a pending server step on start and whenever the signed-in user changes.
final accountSyncStarterProvider = Provider<void>((ref) {
  final linker = ref.watch(accountLinkerProvider);
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, next) {
    if (next.value != null) unawaited(linker.retryPending());
  }, fireImmediately: true);
});
