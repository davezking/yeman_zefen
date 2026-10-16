import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';

class FakeBackend implements AuthBackend {
  FakeBackend({this.failSignIn = false});

  bool failSignIn;
  int signInCalls = 0;
  AuthState _current = AuthState.signedOut;
  final _controller = StreamController<AuthState>.broadcast();

  @override
  AuthState get current => _current;

  @override
  Stream<AuthState> get changes => _controller.stream;

  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    if (failSignIn) throw Exception('network-request-failed');
    _current = const AuthState(uid: 'guest-1');
    _controller.add(_current);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => _current.hasUid ? 'token' : null;
}

void main() {
  test('signs in anonymously on start when nobody is signed in', () async {
    final backend = FakeBackend();
    final service = AuthService(backend: backend, onlineChanges: const Stream.empty());
    service.start();
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    expect(service.current.uid, 'guest-1');
    expect(service.current.isAnonymous, isTrue);
    await service.dispose();
  });

  test('does not sign in again when a user already exists', () async {
    final backend = FakeBackend().._current = const AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com']);
    final service = AuthService(backend: backend, onlineChanges: const Stream.empty());
    service.start();
    await pumpEventQueue();
    expect(backend.signInCalls, 0);
    expect(service.current.uid, 'u1');
    await service.dispose();
  });

  test('offline first launch: start does not throw, the game goes on without a UID', () async {
    final backend = FakeBackend(failSignIn: true);
    final service = AuthService(backend: backend, onlineChanges: const Stream.empty());
    service.start();
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    expect(service.current, AuthState.signedOut);
    expect(await service.idToken(), isNull);
    await service.dispose();
  });

  test('retries the anonymous sign-in when connectivity returns', () async {
    final online = StreamController<bool>();
    final backend = FakeBackend(failSignIn: true);
    final service = AuthService(backend: backend, onlineChanges: online.stream);
    service.start();
    await pumpEventQueue();
    expect(service.current.hasUid, isFalse);

    backend.failSignIn = false;
    online.add(true);
    await pumpEventQueue();
    expect(backend.signInCalls, 2);
    expect(service.current.uid, 'guest-1');
    await service.dispose();
    await online.close();
  });

  test('going offline does not trigger a sign-in attempt', () async {
    final online = StreamController<bool>();
    final backend = FakeBackend(failSignIn: true);
    final service = AuthService(backend: backend, onlineChanges: online.stream);
    service.start();
    await pumpEventQueue();
    online.add(false);
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    await service.dispose();
    await online.close();
  });

  test('states emits the current state first, then changes', () async {
    final backend = FakeBackend();
    final service = AuthService(backend: backend, onlineChanges: const Stream.empty());
    final seen = <AuthState>[];
    final sub = service.states.listen(seen.add);
    await pumpEventQueue();
    service.start();
    await pumpEventQueue();
    expect(seen.first, AuthState.signedOut);
    expect(seen.last.uid, 'guest-1');
    await sub.cancel();
    await service.dispose();
  });

  test('AuthState compares by value', () {
    expect(const AuthState(uid: 'a', providers: ['x']), const AuthState(uid: 'a', providers: ['x']));
    expect(const AuthState(uid: 'a'), isNot(const AuthState(uid: 'b')));
  });
}
