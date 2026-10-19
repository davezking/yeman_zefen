import 'dart:async';

import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/account_linker.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/features/account/data/account_manager.dart';

/// Firebase as the manager sees it: one signed-in user, when they last signed in, and whether
/// a deletion wants a fresher sign-in.
class FakeFirebase implements AuthBackend {
  FakeFirebase(this._current);

  AuthState _current;

  /// How long ago the user last signed in, by Firebase's clock; null when it cannot be read.
  Duration? signInAge_ = Duration.zero;
  final log = <String>[];

  /// The password of the email account.
  String password = 'secret1';

  /// Google account the device's picker returns as signed in.
  String googleSubject = 'g-1';

  /// [deleteUser] answers `requires-recent-login` this many more times.
  int staleDeletes = 0;
  AuthFailure? deleteFails;

  final _changes = StreamController<AuthState>.broadcast(sync: true);

  @override
  AuthState get current => _current;

  @override
  Stream<AuthState> get changes => _changes.stream;

  void _set(AuthState s) {
    _current = s;
    _changes.add(s);
  }

  @override
  Future<void> signInAnonymously() async {
    log.add('anonymous');
    _set(const AuthState(uid: 'guest-new'));
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => _current.uid;

  @override
  Future<void> linkWithCredential(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> signInWithCredential(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() async {
    log.add('signOut');
    _set(AuthState.signedOut);
  }

  @override
  Future<Duration?> signInAge() async => signInAge_;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async => log.add('revokeApple:$authorizationCode');

  @override
  Future<void> reauthenticate(AuthCredential credential) async {
    if (credential is EmailAuthCredential) {
      log.add('reauth:password');
      if (credential.password != password) throw const AuthFailure('wrong-password');
    } else {
      final token = (credential as OAuthCredential).idToken;
      log.add('reauth:${credential.providerId}:$token');
      if (credential.providerId == 'google.com' && token != googleSubject) throw const AuthFailure('user-mismatch');
    }
    signInAge_ = Duration.zero;
    staleDeletes = 0;
  }

  @override
  Future<void> deleteUser() async {
    log.add('delete');
    if (staleDeletes > 0) {
      staleDeletes--;
      throw const AuthFailure('requires-recent-login');
    }
    final fails = deleteFails;
    if (fails != null) throw fails;
    _set(AuthState.signedOut);
  }
}

class FakeCredentials implements CredentialSource {
  FakeCredentials(this.firebase);

  final FakeFirebase firebase;

  /// The Google account the player picks; null closes the picker.
  String? pick = 'g-1';

  @override
  bool get googleAvailable => true;

  bool appleOffered = false;

  @override
  bool get appleAvailable => appleOffered;

  @override
  Future<AuthCredential?> google() async {
    firebase.log.add('picker:google');
    final p = pick;
    return p == null ? null : GoogleAuthProvider.credential(idToken: p);
  }

  @override
  Future<AuthCredential?> apple() async {
    firebase.log.add('picker:apple');
    return pick == null ? null : OAuthProvider('apple.com').credential(idToken: 'apple-1', rawNonce: 'n', accessToken: 'code-1');
  }

  @override
  Future<void> signOut() async => firebase.log.add('forgetGoogle');
}

class FakeApi implements AccountApi {
  FakeApi(this.firebase);

  final FakeFirebase firebase;
  ApiException? failWith;

  @override
  Future<void> registered() => throw UnimplementedError();

  @override
  Future<void> merge(String anonymousIdToken) => throw UnimplementedError();

  @override
  Future<void> deleteMe() async {
    firebase.log.add('DELETE /v1/me as ${firebase.current.uid}');
    final e = failWith;
    if (e != null) throw e;
  }
}

const _google = AuthState(uid: 'u-1', isAnonymous: false, providers: ['google.com'], email: 'a@b.co');
const _email = AuthState(uid: 'u-1', isAnonymous: false, providers: ['password'], email: 'a@b.co');

void main() {
  late FakeFirebase firebase;
  late FakeCredentials credentials;
  late FakeApi api;
  late AppDb db;
  late AuthService auth;
  late int flushes;
  late Future<void> Function() flush;

  AccountManager manager() => AccountManager(
        backend: firebase,
        auth: auth,
        credentials: credentials,
        api: api,
        db: db,
        flushSessions: () {
          flushes++;
          return flush();
        },
        flushTimeout: const Duration(milliseconds: 20),
      );

  void setUp_(AuthState who) {
    firebase = FakeFirebase(who);
    credentials = FakeCredentials(firebase);
    api = FakeApi(firebase);
    db = AppDb(NativeDatabase.memory());
    auth = AuthService(backend: firebase, onlineChanges: const Stream.empty());
    flushes = 0;
    // Says how many sessions were still queued when it ran.
    flush = () async => firebase.log.add('flush:${(await db.select(db.pendingSessions).get()).length}');
  }

  tearDown(() async {
    await auth.dispose();
    await db.close();
  });

  Future<void> seedLocal() async {
    await db.into(db.pendingSessions).insert(PendingSessionsCompanion.insert(id: 's-1', payloadJson: '{}', createdAt: 1));
    await db.into(db.localBests).insert(
          LocalBestsCompanion.insert(mode: 'intro', generationId: 0, bestScore: 900, achievedAt: 1),
        );
    await db.into(db.pendingAccountSync).insert(PendingAccountSyncCompanion.insert(kind: 'registered', createdAt: 1));
  }

  Future<List<int>> localCounts() async => [
        (await db.select(db.pendingSessions).get()).length,
        (await db.select(db.localBests).get()).length,
        (await db.select(db.pendingAccountSync).get()).length,
      ];

  Future<String?> noPassword({required bool wrongPassword}) async => fail('no password expected');

  group('sign out', () {
    test('sends waiting sessions, signs out, forgets the Google account and starts a new guest', () async {
      setUp_(_google);
      await manager().signOut();
      await pumpEventQueue();
      expect(firebase.log, ['flush:0', 'signOut', 'forgetGoogle', 'anonymous']);
      expect(firebase.current, const AuthState(uid: 'guest-new'));
    });

    test("drops the account's local bests, and keeps a pending link step for its own account", () async {
      setUp_(_google);
      await seedLocal();
      flush = () async {};
      await manager().signOut();
      expect(await localCounts(), [1, 0, 1]);
    });

    test('a second sign-out while one runs waits for it', () async {
      setUp_(_google);
      final gate = Completer<void>();
      flush = () => gate.future;
      final m = manager();
      final first = m.signOut();
      final second = m.signOut();
      gate.complete();
      await Future.wait([first, second]);
      await pumpEventQueue();
      expect(firebase.log.where((e) => e == 'signOut'), hasLength(1));
      expect(flushes, 1);
    });

    test('does not wait long for sessions that cannot go', () async {
      setUp_(_google);
      flush = () => Completer<void>().future;
      await manager().signOut();
      expect(firebase.log, ['signOut', 'forgetGoogle', 'anonymous']);
    });

    test('a guest has nothing to sign out of', () async {
      setUp_(const AuthState(uid: 'guest-1'));
      await manager().signOut();
      expect(firebase.log, isEmpty);
      expect(flushes, 0);
    });
  });

  group('delete', () {
    test('a recent sign-in deletes on the server, then locally, then in Firebase, and starts a guest', () async {
      setUp_(_google);
      await seedLocal();
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.deleted);
      await pumpEventQueue();
      // The queue is emptied before the send it waits for, so nothing reaches the server after.
      expect(firebase.log, ['flush:0', 'DELETE /v1/me as u-1', 'delete', 'forgetGoogle', 'anonymous']);
      expect(await localCounts(), [0, 0, 0]);
      expect(firebase.current.uid, 'guest-new');
    });

    test('an old sign-in signs in again with Google before anything is deleted', () async {
      setUp_(_google);
      firebase.signInAge_ = const Duration(minutes: 10);
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.deleted);
      expect(firebase.log.take(5), ['picker:google', 'reauth:google.com:g-1', 'flush:0', 'DELETE /v1/me as u-1', 'delete']);
    });

    test('no known sign-in time counts as old', () async {
      setUp_(_google);
      firebase.signInAge_ = null;
      await manager().deleteAccount(askPassword: noPassword);
      expect(firebase.log.first, 'picker:google');
    });

    test('closing the sign-in changes nothing', () async {
      setUp_(_google);
      await seedLocal();
      firebase.signInAge_ = const Duration(minutes: 10);
      credentials.pick = null;
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.cancelled);
      expect(firebase.log, ['picker:google']);
      expect(await localCounts(), [1, 1, 1]);
      expect(firebase.current, _google);
    });

    test('another Google account is refused before anything is deleted', () async {
      setUp_(_google);
      firebase.signInAge_ = const Duration(minutes: 10);
      credentials.pick = 'g-other';
      await expectLater(
        manager().deleteAccount(askPassword: noPassword),
        throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'user-mismatch')),
      );
      expect(firebase.log, isNot(contains('DELETE /v1/me as u-1')));
    });

    test('an email account asks for its password, again after a wrong one', () async {
      setUp_(_email);
      firebase.signInAge_ = const Duration(minutes: 10);
      final asked = <bool>[];
      final answers = ['nope', 'secret1'];
      final outcome = await manager().deleteAccount(
        askPassword: ({required wrongPassword}) async {
          asked.add(wrongPassword);
          return answers.removeAt(0);
        },
      );
      expect(outcome, DeleteOutcome.deleted);
      expect(asked, [false, true]);
      expect(firebase.log.take(4), ['reauth:password', 'reauth:password', 'flush:0', 'DELETE /v1/me as u-1']);
    });

    test('cancelling the password changes nothing', () async {
      setUp_(_email);
      firebase.signInAge_ = const Duration(minutes: 10);
      final outcome = await manager().deleteAccount(askPassword: ({required wrongPassword}) async => null);
      expect(outcome, DeleteOutcome.cancelled);
      expect(firebase.log, isEmpty);
    });

    test('a server that cannot be reached leaves the account; only its unsent sessions are gone', () async {
      setUp_(_google);
      await seedLocal();
      api.failWith = const NetworkException('offline');
      await expectLater(manager().deleteAccount(askPassword: noPassword), throwsA(isA<NetworkException>()));
      expect(firebase.log, ['flush:0', 'DELETE /v1/me as u-1']);
      expect(await localCounts(), [0, 1, 1]);
      expect(firebase.current, _google);
    });

    test('Firebase asking for a fresher sign-in after the server step signs in again and finishes', () async {
      setUp_(_google);
      firebase.staleDeletes = 1;
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.deleted);
      expect(firebase.log.skip(1).take(5), ['DELETE /v1/me as u-1', 'delete', 'picker:google', 'reauth:google.com:g-1', 'delete']);
    });

    test('closing that later sign-in leaves the account signed in, to finish by deleting again', () async {
      setUp_(_google);
      firebase.staleDeletes = 1;
      credentials.pick = null;
      await expectLater(manager().deleteAccount(askPassword: noPassword), throwsA(isA<DeleteIncompleteException>()));
      expect(firebase.current, _google);

      credentials.pick = 'g-1';
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.deleted);
    });

    test('another Firebase failure after the server step is incomplete too', () async {
      setUp_(_google);
      firebase.deleteFails = const AuthFailure('network-request-failed');
      await expectLater(
        manager().deleteAccount(askPassword: noPassword),
        throwsA(isA<DeleteIncompleteException>().having((e) => e.cause, 'cause', isA<AuthFailure>())),
      );
    });

    test('an Apple account signs in with Apple even when recent, and revokes its tokens', () async {
      setUp_(const AuthState(uid: 'u-1', isAnonymous: false, providers: ['apple.com']));
      credentials.appleOffered = true;
      expect(await manager().deleteAccount(askPassword: noPassword), DeleteOutcome.deleted);
      expect(firebase.log.take(6), [
        'picker:apple',
        'reauth:apple.com:apple-1',
        'flush:0',
        'DELETE /v1/me as u-1',
        'revokeApple:code-1',
        'delete',
      ]);
    });

    test('an account whose providers this phone does not offer cannot be confirmed', () async {
      setUp_(const AuthState(uid: 'u-1', isAnonymous: false, providers: ['apple.com']));
      firebase.signInAge_ = const Duration(minutes: 10);
      await expectLater(
        manager().deleteAccount(askPassword: noPassword),
        throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'reauth-unavailable')),
      );
      expect(firebase.log, isEmpty);
    });

    test('a guest cannot delete', () async {
      setUp_(const AuthState(uid: 'guest-1'));
      await expectLater(manager().deleteAccount(askPassword: noPassword), throwsA(isA<AuthFailure>()));
      expect(firebase.log, isEmpty);
    });
  });

  group('reauthProvider', () {
    test('prefers a provider with nothing to type, and needs an email for a password', () {
      setUp_(_google);
      expect(
        reauthProvider(const AuthState(uid: 'u', isAnonymous: false, providers: ['password', 'google.com'], email: 'a@b.co'), credentials),
        'google.com',
      );
      expect(reauthProvider(_email, credentials), 'password');
      expect(reauthProvider(const AuthState(uid: 'u', isAnonymous: false, providers: ['password']), credentials), isNull);
      // Apple is not offered on this phone.
      expect(reauthProvider(const AuthState(uid: 'u', isAnonymous: false, providers: ['apple.com']), credentials), isNull);
    });
  });
}
