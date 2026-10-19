import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show AuthCredential;
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';

class FakeBackend implements AuthBackend {
  FakeBackend({this.failSignIn = false});

  bool failSignIn;
  int signInCalls = 0;

  /// When set, sign-in waits for this before finishing.
  Completer<void>? gate;

  AuthState _current = AuthState.signedOut;
  final _controller = StreamController<AuthState>.broadcast(sync: true);

  void setUser(AuthState state) {
    _current = state;
    _controller.add(state);
  }

  @override
  AuthState get current => _current;

  @override
  Stream<AuthState> get changes => _controller.stream;

  @override
  Future<void> signInAnonymously() async {
    signInCalls++;
    if (gate != null) await gate!.future;
    if (failSignIn) throw Exception('network-request-failed');
    setUser(const AuthState(uid: 'guest-1'));
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => _current.hasUid ? 'token' : null;

  @override
  Future<void> linkWithCredential(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> signInWithCredential(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() async => setUser(AuthState.signedOut);

  @override
  Future<DateTime?> lastSignInAt() async => null;

  @override
  Future<void> reauthenticate(AuthCredential credential) => throw UnimplementedError();

  @override
  Future<void> deleteUser() => throw UnimplementedError();
}

/// Records retry timers instead of waiting for them.
class FakeTimers {
  final delays = <Duration>[];
  final _callbacks = <void Function()>[];
  final _timers = <_FakeTimer>[];

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    _callbacks.add(callback);
    final timer = _FakeTimer();
    _timers.add(timer);
    return timer;
  }

  bool get hasPending => _timers.isNotEmpty && _timers.last.isActive;

  /// Fires the latest timer, as if its delay had passed.
  void fireLatest() {
    final timer = _timers.last;
    if (!timer.isActive) throw StateError('no pending timer');
    timer.cancel();
    _callbacks.last();
  }
}

class _FakeTimer implements Timer {
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  @override
  int get tick => 0;
}

void main() {
  late FakeTimers timers;

  setUp(() => timers = FakeTimers());

  AuthService serviceFor(FakeBackend backend, {Stream<bool>? online}) => AuthService(
    backend: backend,
    onlineChanges: online ?? const Stream.empty(),
    retryDelays: const [Duration(seconds: 5), Duration(seconds: 30)],
    timer: timers.call,
  );

  test('signs in anonymously on start when nobody is signed in', () async {
    final backend = FakeBackend();
    final service = serviceFor(backend)..start();
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    expect(service.current.uid, 'guest-1');
    expect(service.current.isAnonymous, isTrue);
    expect(timers.delays, isEmpty);
    await service.dispose();
  });

  test('does not sign in again when a user already exists', () async {
    final backend = FakeBackend()..setUser(const AuthState(uid: 'u1', isAnonymous: false, providers: ['google.com']));
    final service = serviceFor(backend)..start();
    await pumpEventQueue();
    expect(backend.signInCalls, 0);
    expect(service.current.uid, 'u1');
    await service.dispose();
  });

  test('offline first launch: start does not throw and the game goes on without a UID', () async {
    final backend = FakeBackend(failSignIn: true);
    final service = serviceFor(backend)..start();
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    expect(service.current, AuthState.signedOut);
    await service.dispose();
  });

  test('a failed sign-in is retried with backoff, even with no connectivity change', () async {
    final backend = FakeBackend(failSignIn: true);
    final service = serviceFor(backend)..start();
    await pumpEventQueue();
    expect(timers.delays, [const Duration(seconds: 5)]);

    timers.fireLatest();
    await pumpEventQueue();
    expect(backend.signInCalls, 2);
    // The last delay repeats.
    timers.fireLatest();
    await pumpEventQueue();
    expect(timers.delays, [const Duration(seconds: 5), const Duration(seconds: 30), const Duration(seconds: 30)]);

    backend.failSignIn = false;
    timers.fireLatest();
    await pumpEventQueue();
    expect(service.current.uid, 'guest-1');
    expect(timers.hasPending, isFalse);
    await service.dispose();
  });

  test('coming back online retries straight away and resets the backoff', () async {
    final online = StreamController<bool>();
    final backend = FakeBackend(failSignIn: true);
    final service = serviceFor(backend, online: online.stream)..start();
    await pumpEventQueue();
    expect(timers.hasPending, isTrue);

    backend.failSignIn = false;
    online.add(true);
    await pumpEventQueue();
    expect(backend.signInCalls, 2);
    expect(service.current.uid, 'guest-1');
    expect(timers.hasPending, isFalse);
    await service.dispose();
    await online.close();
  });

  test('going offline does not trigger a sign-in attempt', () async {
    final online = StreamController<bool>();
    final backend = FakeBackend(failSignIn: true);
    final service = serviceFor(backend, online: online.stream)..start();
    await pumpEventQueue();
    online.add(false);
    await pumpEventQueue();
    expect(backend.signInCalls, 1);
    await service.dispose();
    await online.close();
  });

  test('concurrent callers share one sign-in and all see its result', () async {
    final backend = FakeBackend()..gate = Completer<void>();
    final service = serviceFor(backend);
    final first = service.ensureSignedIn();
    final second = service.ensureSignedIn();
    backend.gate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(backend.signInCalls, 1);
    await service.dispose();
  });

  test('idToken signs in first when there is no user yet', () async {
    final backend = FakeBackend();
    final service = serviceFor(backend);
    expect(await service.idToken(), 'token');
    expect(backend.signInCalls, 1);
    await service.dispose();
  });

  test('idToken is null when the sign-in fails', () async {
    final service = serviceFor(FakeBackend(failSignIn: true));
    expect(await service.idToken(), isNull);
    await service.dispose();
  });

  test('dispose cancels a pending retry', () async {
    final backend = FakeBackend(failSignIn: true);
    final service = serviceFor(backend)..start();
    await pumpEventQueue();
    expect(timers.hasPending, isTrue);
    await service.dispose();
    expect(timers.hasPending, isFalse);
  });

  test('states emits the current state first, then changes', () async {
    final backend = FakeBackend();
    final service = serviceFor(backend);
    final seen = <AuthState>[];
    final sub = service.states.listen(seen.add);
    await pumpEventQueue();
    service.start();
    await pumpEventQueue();
    expect(seen, [AuthState.signedOut, const AuthState(uid: 'guest-1')]);
    await sub.cancel();
    await service.dispose();
  });

  test('states does not lose a change made right as it is listened to', () async {
    final backend = FakeBackend();
    final service = serviceFor(backend);
    final seen = <AuthState>[];
    final sub = service.states.listen(seen.add);
    // Synchronously, before any microtask runs.
    backend.setUser(const AuthState(uid: 'guest-1'));
    await pumpEventQueue();
    expect(seen.last.uid, 'guest-1');
    await sub.cancel();
    await service.dispose();
  });

  test('AuthState compares by value', () {
    expect(const AuthState(uid: 'a', providers: ['x']), const AuthState(uid: 'a', providers: ['x']));
    expect(const AuthState(uid: 'a'), isNot(const AuthState(uid: 'b')));
  });
}
