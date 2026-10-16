import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../db/app_db.dart';
import '../http/api_client.dart';
import '../http/api_providers.dart';

/// Remembers when each account was last sent to the server.
abstract class ProfileSyncStore {
  /// Epoch ms (UTC) of the last successful sync for [key], or null.
  Future<int?> lastSyncedAt(String key);

  Future<void> markSynced(String key, int atMs);
}

/// Keeps the timestamps in the `local_counters` table, so a restart does not
/// forget them and a second launch within the window sends nothing.
class DbProfileSyncStore implements ProfileSyncStore {
  DbProfileSyncStore(this.db);

  final AppDb db;

  @override
  Future<int?> lastSyncedAt(String key) async {
    final row = await (db.select(db.localCounters)..where((t) => t.name.equals(key))).getSingleOrNull();
    return row?.count;
  }

  @override
  Future<void> markSynced(String key, int atMs) => db.customStatement(
    'INSERT INTO local_counters (name, count) VALUES (?, ?) '
    'ON CONFLICT(name) DO UPDATE SET count = excluded.count',
    [key, atMs],
  );
}

/// Tells the server who this player is (`PUT /v1/me`): after sign-in, and on
/// each app open, but at most once per [minInterval] for the same account.
///
/// The server takes the identity, anonymity and country itself; the app sends
/// nothing but an optional display name. A failed call is not recorded, so the
/// next trigger tries again.
class ProfileSync {
  ProfileSync({
    required this.api,
    required this.store,
    DateTime Function()? now,
    this.minInterval = const Duration(hours: 6),
  }) : _now = now ?? DateTime.now;

  final ApiClient api;
  final ProfileSyncStore store;
  final Duration minInterval;
  final DateTime Function() _now;

  final _inFlight = <String, Future<void>>{};

  /// Sends `PUT /v1/me` for [auth] unless that account was synced less than
  /// [minInterval] ago. Returns true when a request went out and succeeded.
  /// Never throws: the profile is not needed to play.
  Future<bool> syncIfDue(AuthState auth) async {
    final uid = auth.uid;
    if (uid == null) return false;
    // Linking a guest to an account keeps the uid but changes anonymity, which
    // the server must hear about now, so anonymity is part of the key.
    final key = 'profile_synced_at:$uid:${auth.isAnonymous ? 'guest' : 'registered'}';
    // Overlapping calls for the same account share one request.
    final running = _inFlight[key];
    if (running != null) {
      await running;
      return false;
    }
    final completer = Completer<void>();
    _inFlight[key] = completer.future;
    try {
      final nowMs = _now().toUtc().millisecondsSinceEpoch;
      final last = await store.lastSyncedAt(key);
      // A clock set back counts as due rather than blocking sync for hours.
      if (last != null && nowMs >= last && nowMs - last < minInterval.inMilliseconds) return false;
      await api.putJson('/v1/me', body: <String, Object?>{});
      await store.markSynced(key, nowMs);
      return true;
    } catch (_) {
      // Offline or a server error: the next trigger tries again.
      return false;
    } finally {
      _inFlight.remove(key);
      completer.complete();
    }
  }
}

final profileSyncProvider = Provider<ProfileSync>(
  (ref) => ProfileSync(api: ref.watch(apiClientProvider), store: DbProfileSyncStore(ref.watch(appDbProvider))),
);

/// Runs [ProfileSync] for as long as it is watched. The auth stream starts
/// with the current user, so the first run is the app open, and it fires again
/// whenever the user changes (sign-in, linking, signing in again after a
/// deletion).
final profileSyncStarterProvider = Provider<void>((ref) {
  final sync = ref.watch(profileSyncProvider);
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, next) {
    final auth = next.value;
    if (auth != null) unawaited(sync.syncIfDue(auth));
  }, fireImmediately: true);
});
