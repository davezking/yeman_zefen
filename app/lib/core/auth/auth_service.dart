import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who the player is, as far as Firebase knows.
class AuthState {
  const AuthState({this.uid, this.isAnonymous = true, this.providers = const []});

  /// No identity yet: first launch while offline, before sign-in succeeds.
  static const signedOut = AuthState();

  /// Null until the first anonymous sign-in succeeds. Sessions recorded before
  /// then are queued locally without a UID.
  final String? uid;
  final bool isAnonymous;

  /// Provider ids linked to the account (`google.com`, `password`, `apple.com`).
  /// Empty for a guest.
  final List<String> providers;

  bool get hasUid => uid != null;

  @override
  bool operator ==(Object other) =>
      other is AuthState &&
      other.uid == uid &&
      other.isAnonymous == isAnonymous &&
      _sameList(other.providers, providers);

  @override
  int get hashCode => Object.hash(uid, isAnonymous, Object.hashAll(providers));

  @override
  String toString() => 'AuthState(uid: $uid, isAnonymous: $isAnonymous, providers: $providers)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The part of Firebase Auth the app uses. Tests replace it, so nothing here
/// needs a Firebase project.
abstract class AuthBackend {
  /// The signed-in user right now, or null.
  AuthState get current;

  /// Emits whenever the signed-in user changes (sign-in, sign-out, linking).
  Stream<AuthState> get changes;

  Future<void> signInAnonymously();

  /// A fresh-enough ID token for the signed-in user, or null when signed out.
  Future<String?> idToken({bool forceRefresh = false});
}

class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static AuthState _stateOf(User? user) => user == null
      ? AuthState.signedOut
      : AuthState(
          uid: user.uid,
          isAnonymous: user.isAnonymous,
          providers: [for (final info in user.providerData) info.providerId],
        );

  @override
  AuthState get current => _stateOf(_auth.currentUser);

  // userChanges (not authStateChanges) also fires when an account is linked,
  // which is how a guest becoming a registered player shows up.
  @override
  Stream<AuthState> get changes => _auth.userChanges().map(_stateOf);

  @override
  Future<void> signInAnonymously() => _auth.signInAnonymously();

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _auth.currentUser?.getIdToken(forceRefresh);
}

typedef RetryTimerFactory = Timer Function(Duration delay, void Function() callback);

/// Signs every player in, guests included, without showing any UI.
///
/// On start, if nobody is signed in, it signs in anonymously. If that fails
/// (offline on first launch is the usual reason), the app carries on without a
/// UID. The sign-in is retried with backoff, and straight away when
/// connectivity comes back.
class AuthService {
  AuthService({
    required this.backend,
    Stream<bool>? onlineChanges,
    this.retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
    ],
    RetryTimerFactory? timer,
  }) : assert(retryDelays.isNotEmpty),
       _onlineChanges = onlineChanges ?? connectivityOnlineChanges(),
       _timer = timer ?? Timer.new;

  final AuthBackend backend;

  /// Waits between failed sign-ins. The last one repeats until a sign-in works.
  final List<Duration> retryDelays;

  final Stream<bool> _onlineChanges;
  final RetryTimerFactory _timer;

  StreamSubscription<bool>? _onlineSub;
  Future<bool>? _inFlight;
  Timer? _retry;
  int _failures = 0;
  bool _started = false;
  bool _disposed = false;

  AuthState get current => backend.current;

  /// The current state first, then every change.
  ///
  /// Subscribes to the backend before reading the current state, so a change
  /// that lands in between is not lost.
  Stream<AuthState> get states {
    StreamSubscription<AuthState>? sub;
    late final StreamController<AuthState> controller;
    controller = StreamController<AuthState>(
      onListen: () {
        sub = backend.changes.listen(controller.add, onError: controller.addError);
        controller.add(backend.current);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return controller.stream.distinct();
  }

  /// Starts the sign-in and its retries. Does not wait for the network: a
  /// first launch with no connection still gets to the game. Called by
  /// [authServiceProvider]; calling it again does nothing.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _onlineSub = _onlineChanges.listen((online) {
      if (!online) return;
      // Back online: try now instead of waiting out the backoff.
      _retry?.cancel();
      _retry = null;
      _failures = 0;
      unawaited(ensureSignedIn());
    });
    unawaited(ensureSignedIn());
  }

  /// Signs in anonymously when there is no user. Safe to call repeatedly:
  /// concurrent callers share one attempt. Returns whether a user exists
  /// afterwards.
  Future<bool> ensureSignedIn() {
    if (backend.current.hasUid) return Future.value(true);
    return _inFlight ??= _signIn().whenComplete(() => _inFlight = null);
  }

  Future<bool> _signIn() async {
    try {
      await backend.signInAnonymously();
      _retry?.cancel();
      _retry = null;
      _failures = 0;
      return true;
    } catch (_) {
      // Offline, a captive portal, or a transient Firebase error.
      _scheduleRetry();
      return false;
    }
  }

  void _scheduleRetry() {
    if (!_started || _disposed || (_retry?.isActive ?? false)) return;
    final delay = retryDelays[_failures < retryDelays.length ? _failures : retryDelays.length - 1];
    _failures++;
    _retry = _timer(delay, () {
      _retry = null;
      unawaited(ensureSignedIn());
    });
  }

  /// The ID token for API calls. With no user yet it tries the anonymous
  /// sign-in first, and returns null only if that fails.
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (!backend.current.hasUid && !await ensureSignedIn()) return null;
    return backend.idToken(forceRefresh: forceRefresh);
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _onlineSub?.cancel();
  }
}

/// True when the device has any connection, false when it has none, on every change.
Stream<bool> connectivityOnlineChanges() => Connectivity().onConnectivityChanged.map(
  (results) => results.any((r) => r != ConnectivityResult.none),
);

final authBackendProvider = Provider<AuthBackend>((ref) => FirebaseAuthBackend());

/// Started as soon as it is created, so a rebuilt service signs in too.
final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(backend: ref.watch(authBackendProvider))..start();
  ref.onDispose(service.dispose);
  return service;
});

/// uid, isAnonymous and linked providers. `uid` is null until the first
/// anonymous sign-in succeeds.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).states);
