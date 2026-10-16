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

/// Signs every player in, guests included, without showing any UI.
///
/// On start, if nobody is signed in, it signs in anonymously. If that fails
/// (offline on first launch is the usual reason), the app carries on without a
/// UID and the sign-in is retried when connectivity comes back.
class AuthService {
  AuthService({required this.backend, Stream<bool>? onlineChanges})
    : _onlineChanges = onlineChanges ?? _connectivityOnline();

  final AuthBackend backend;
  final Stream<bool> _onlineChanges;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<bool>? _onlineSub;
  bool _signingIn = false;
  bool _started = false;
  final _states = StreamController<AuthState>.broadcast();

  AuthState get current => backend.current;

  /// The current state first, then every change.
  Stream<AuthState> get states async* {
    yield current;
    yield* _states.stream;
  }

  /// Starts watching auth and signs in if needed. Does not wait for the
  /// network: a first launch with no connection still gets to the game.
  void start() {
    if (_started) return;
    _started = true;
    _authSub = backend.changes.listen(_states.add);
    _onlineSub = _onlineChanges.listen((online) {
      if (online) unawaited(ensureSignedIn());
    });
    unawaited(ensureSignedIn());
  }

  /// Signs in anonymously when there is no user. Safe to call repeatedly.
  /// Returns whether a user exists afterwards.
  Future<bool> ensureSignedIn() async {
    if (backend.current.hasUid) return true;
    if (_signingIn) return false;
    _signingIn = true;
    try {
      await backend.signInAnonymously();
      return true;
    } catch (_) {
      // Offline or a transient Firebase error. The connectivity listener tries again.
      return false;
    } finally {
      _signingIn = false;
    }
  }

  /// The ID token for API calls, or null when there is no user yet.
  Future<String?> idToken({bool forceRefresh = false}) =>
      backend.idToken(forceRefresh: forceRefresh);

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _onlineSub?.cancel();
    await _states.close();
  }
}

Stream<bool> _connectivityOnline() => Connectivity().onConnectivityChanged.map(
  (results) => results.any((r) => r != ConnectivityResult.none),
);

final authBackendProvider = Provider<AuthBackend>((ref) => FirebaseAuthBackend());

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(backend: ref.watch(authBackendProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// uid, isAnonymous and linked providers. `uid` is null until the first
/// anonymous sign-in succeeds.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).states);
