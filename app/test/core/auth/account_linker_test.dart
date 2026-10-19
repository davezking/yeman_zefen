import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/account_linker.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/http/api_client.dart';

/// Firebase as the linker sees it: a signed-in user, the accounts each credential belongs to,
/// and tokens that say whether they were issued to a guest.
class FakeFirebase implements AuthBackend {
  AuthState _current = const AuthState(uid: 'guest-1');

  /// Credential key (provider:subject) → uid of the account it belongs to.
  final owners = <String, String>{};
  final passwords = <String, String>{};
  final log = <String>[];
  int tokenSerial = 0;
  String? _cachedToken;
  bool failRefresh = false;

  /// Runs during sign-in, as the auth-state listener would.
  Future<void> Function()? onUserChanged;

  static String keyOf(AuthCredential c) =>
      c is EmailAuthCredential ? 'password:${c.email}' : '${c.providerId}:${(c as OAuthCredential).idToken}';

  @override
  AuthState get current => _current;

  @override
  Stream<AuthState> get changes => const Stream.empty();

  @override
  Future<void> signInAnonymously() async => _current = const AuthState(uid: 'guest-new');

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (!_current.hasUid) return null;
    if (forceRefresh && failRefresh) throw const AuthFailure('network-request-failed');
    if (forceRefresh || _cachedToken == null) {
      _cachedToken = '${_current.uid}:${_current.isAnonymous ? 'anon' : 'reg'}:${tokenSerial++}';
    }
    log.add('token:$_cachedToken');
    return _cachedToken;
  }

  /// Another registered account is signed in (its own token, not the cached one).
  void switchTo(String uid) {
    _cachedToken = null;
    _current = AuthState(uid: uid, isAnonymous: false);
  }

  void _setUser(String uid, String provider) {
    _current = AuthState(uid: uid, isAnonymous: false, providers: [provider]);
  }

  @override
  Future<void> linkWithCredential(AuthCredential credential) async {
    final key = keyOf(credential);
    log.add('link:$key');
    final owner = owners[key];
    if (owner != null && owner != _current.uid) throw CredentialInUseException(credential);
    owners[key] = _current.uid!;
    if (credential is EmailAuthCredential) passwords[key] = credential.password!;
    // Firebase updates the user; the cached token is the old one until refreshed.
    _current = AuthState(uid: _current.uid, isAnonymous: false, providers: [credential.providerId]);
  }

  @override
  Future<void> signInWithCredential(AuthCredential credential) async {
    final key = keyOf(credential);
    log.add('signIn:$key');
    final owner = owners[key];
    if (owner == null) throw const AuthFailure('user-not-found');
    if (credential is EmailAuthCredential && passwords[key] != credential.password) {
      throw const AuthFailure('wrong-password');
    }
    _cachedToken = null;
    _setUser(owner, credential.providerId);
    await onUserChanged?.call();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async => log.add('reset:$email');

  @override
  Future<void> signOut() async => _current = AuthState.signedOut;

  @override
  Future<DateTime?> lastSignInAt() async => null;

  @override
  Future<void> reauthenticate(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> deleteUser() => throw UnimplementedError();
}

class FakeCredentials implements CredentialSource {
  AuthCredential? googleCredential = GoogleAuthProvider.credential(idToken: 'g-sub-1');

  @override
  bool get googleAvailable => true;

  @override
  bool get appleAvailable => false;

  @override
  Future<AuthCredential?> google() async => googleCredential;

  @override
  Future<AuthCredential?> apple() async => null;

  @override
  Future<void> signOut() async {}
}

class FakeApi implements AccountApi {
  FakeApi(this.firebase);

  final FakeFirebase firebase;
  final calls = <String>[];
  ApiException? failWith;

  Future<void> _call(String what) async {
    // The request carries the current (possibly cached) token.
    final token = await firebase.idToken();
    calls.add('$what as $token');
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<void> registered() => _call('registered');

  @override
  Future<void> merge(String anonymousIdToken) => _call('merge($anonymousIdToken)');

  @override
  Future<void> deleteMe() => _call('deleteMe');
}

class MemoryStore implements PendingAccountStore {
  PendingAccountStep? step;

  @override
  Future<PendingAccountStep?> read() async => step;

  @override
  Future<void> write(PendingAccountStep s) async => step = s;

  @override
  Future<void> clear() async => step = null;
}

void main() {
  late FakeFirebase firebase;
  late FakeCredentials credentials;
  late FakeApi api;
  late MemoryStore store;
  late AccountLinker linker;

  setUp(() async {
    firebase = FakeFirebase();
    credentials = FakeCredentials();
    api = FakeApi(firebase);
    store = MemoryStore();
    linker = AccountLinker(backend: firebase, credentials: credentials, api: api, store: store);
    await firebase.idToken(); // the guest's token is cached, as on a real device
  });

  test('linking Google keeps the uid, refreshes the token, then registers', () async {
    final result = await linker.linkWithGoogle();
    expect(result.outcome, LinkOutcome.linked);
    expect(result.serverSynced, isTrue);
    expect(firebase.current.uid, 'guest-1');
    // The call goes out with a refreshed, registered token, not the cached guest one.
    expect(api.calls, ['registered as guest-1:reg:1']);
    expect(store.step, isNull);
  });

  test('a Google account that exists: guest token first, then sign in, then merge', () async {
    firebase.owners['google.com:g-sub-1'] = 'acct-9';
    final result = await linker.linkWithGoogle();
    expect(result.outcome, LinkOutcome.merged);
    expect(firebase.current.uid, 'acct-9');
    final signInAt = firebase.log.indexOf('signIn:google.com:g-sub-1');
    final guestTokenAt = firebase.log.indexOf('token:guest-1:anon:0');
    expect(guestTokenAt, lessThan(signInAt));
    expect(api.calls, ['merge(guest-1:anon:0) as acct-9:reg:1']);
    expect(store.step, isNull);
  });

  test('email: a new address links, an existing one signs in and merges', () async {
    expect((await linker.linkWithEmail(' a@b.et ', 'pw-1')).outcome, LinkOutcome.linked);
    expect(firebase.owners['password:a@b.et'], 'guest-1');

    // Another phone, another guest, same email.
    final phone2 = FakeFirebase()
      ..owners.addAll(firebase.owners)
      ..passwords.addAll(firebase.passwords)
      .._current = const AuthState(uid: 'guest-2');
    final api2 = FakeApi(phone2);
    final linker2 = AccountLinker(backend: phone2, credentials: credentials, api: api2, store: MemoryStore());
    final result = await linker2.linkWithEmail('a@b.et', 'pw-1');
    expect(result.outcome, LinkOutcome.merged);
    expect(phone2.current.uid, 'guest-1');
    expect(api2.calls.single, startsWith('merge(guest-2:anon:'));
  });

  test('signInWithEmail on a guest merges; a wrong password keeps the guest and saves nothing', () async {
    firebase.owners['password:x@y.et'] = 'acct-2';
    firebase.passwords['password:x@y.et'] = 'right';
    await expectLater(linker.signInWithEmail('x@y.et', 'wrong'), throwsA(isA<AuthFailure>()));
    expect(firebase.current.uid, 'guest-1');
    expect(store.step, isNull);
    expect(api.calls, isEmpty);

    expect((await linker.signInWithEmail('x@y.et', 'right')).outcome, LinkOutcome.merged);
    expect(api.calls.single, startsWith('merge(guest-1:anon:'));
  });

  test('offline after the merge sign-in: the guest token is kept and sent on retry', () async {
    firebase.owners['google.com:g-sub-1'] = 'acct-9';
    api.failWith = const NetworkException('offline');
    final result = await linker.linkWithGoogle();
    expect(result.outcome, LinkOutcome.merged);
    expect(result.serverSynced, isFalse);
    expect(store.step?.anonymousIdToken, 'guest-1:anon:0');

    api.failWith = null;
    await linker.retryPending();
    expect(api.calls.last, 'merge(guest-1:anon:0) as acct-9:reg:1');
    expect(store.step, isNull);
  });

  test('a registration cut off by a server error is retried with a fresh token', () async {
    api.failWith = const ServerException('internal', 'x', status: 500);
    expect((await linker.linkWithGoogle()).serverSynced, isFalse);
    expect(store.step?.isMerge, isFalse);
    api.failWith = null;
    await linker.retryPending();
    expect(api.calls.last, startsWith('registered as guest-1:reg:'));
    expect(store.step, isNull);
  });

  test('a refused merge (409, or a guest token over 30 days old) is not retried', () async {
    firebase.owners['google.com:g-sub-1'] = 'acct-9';
    api.failWith = const RequestException('already_registered', 'x', status: 409);
    expect((await linker.linkWithGoogle()).serverSynced, isFalse);
    expect(store.step, isNull);

    store.step = const PendingAccountStep.merge('old', targetUid: 'acct-9');
    api.failWith = const UnauthorizedException('invalid_anonymous_token', 'x');
    await linker.retryPending();
    expect(store.step, isNull);
  });

  test('other errors keep the step: a 404 from an old server, a 403, a 401 for the caller', () async {
    for (final error in const <ApiException>[
      NotFoundException('not_found', 'x'),
      ForbiddenException('registration_required', 'x'),
      UnauthorizedException('unauthorized', 'x'),
    ]) {
      store.step = const PendingAccountStep.merge('g', targetUid: 'guest-1');
      firebase.switchTo('guest-1');
      api.failWith = error;
      await linker.retryPending();
      expect(store.step, isNotNull, reason: error.code);
    }
  });

  test('a token refresh that fails right after linking still leaves the registration saved', () async {
    firebase.failRefresh = true;
    final result = await linker.linkWithGoogle();
    expect(result.outcome, LinkOutcome.linked);
    expect(result.serverSynced, isFalse);
    expect(store.step?.targetUid, 'guest-1');
    expect(api.calls, isEmpty);

    firebase.failRefresh = false;
    await linker.retryPending();
    expect(api.calls.single, startsWith('registered as guest-1:reg:'));
    expect(store.step, isNull);
  });

  test('a pending merge is sent only to the account it was for', () async {
    store.step = const PendingAccountStep.merge('guest-1:anon:0', targetUid: 'acct-A');
    firebase.switchTo('acct-B');
    await linker.retryPending();
    expect(api.calls, isEmpty);
    expect(store.step, isNotNull);

    firebase.switchTo('acct-A');
    await linker.retryPending();
    expect(api.calls.single, startsWith('merge(guest-1:anon:0) as acct-A:reg:'));
  });

  test('a merge saved before its sign-in finished goes to the account signed in now', () async {
    store.step = const PendingAccountStep.merge('guest-1:anon:0');
    firebase.switchTo('acct-C');
    await linker.retryPending();
    expect(api.calls.single, startsWith('merge(guest-1:anon:0) as acct-C'));
  });

  test('the user change during a merge sign-in does not send the merge twice', () async {
    firebase.owners['google.com:g-sub-1'] = 'acct-9';
    firebase.onUserChanged = linker.retryPending;
    expect((await linker.linkWithGoogle()).outcome, LinkOutcome.merged);
    expect(api.calls, hasLength(1));
  });

  test('a registered player cannot pull in another registered account', () async {
    await linker.linkWithGoogle(); // guest-1 is now registered with google
    firebase.owners['password:other@y.et'] = 'acct-3';
    await expectLater(
      linker.linkWithEmail('other@y.et', 'pw'),
      throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'credential-already-in-use')),
    );
    expect(firebase.current.uid, 'guest-1');
    expect(api.calls.where((c) => c.startsWith('merge')), isEmpty);
  });

  test('a cancelled sign-in does nothing', () async {
    credentials.googleCredential = null;
    expect((await linker.linkWithGoogle()).outcome, LinkOutcome.cancelled);
    expect(api.calls, isEmpty);
    expect(firebase.log.where((l) => !l.startsWith('token:')), isEmpty);
  });

  test('a pending step waits while the user is still a guest', () async {
    store.step = const PendingAccountStep.registered('guest-1');
    await linker.retryPending();
    expect(api.calls, isEmpty);
    expect(store.step, isNotNull);
  });

  test('password reset trims the address', () async {
    await linker.sendPasswordReset(' a@b.et ');
    expect(firebase.log.last, 'reset:a@b.et');
  });

  test('the Apple nonce is random and sent hashed', () {
    final a = randomNonce();
    expect(a, hasLength(32));
    expect(randomNonce(), isNot(a));
    expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
}
