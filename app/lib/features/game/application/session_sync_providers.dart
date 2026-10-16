import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/db/app_db.dart';
import '../../../core/http/api_providers.dart';
import '../data/session_sync.dart';
import 'session_controller.dart';

final sessionSyncProvider = Provider<SessionSync>((ref) {
  final auth = ref.watch(authServiceProvider);
  final sync = SessionSync(db: ref.watch(appDbProvider), api: ref.watch(apiClientProvider), auth: () => auth.current);
  ref.onDispose(sync.dispose);
  return sync;
});

/// Keeps the upload of finished sessions going for as long as it is read:
/// when the app starts, once the player has a uid (sessions played before the
/// first sign-in wait for it), when the connection comes back, after each
/// session ends, and when the app returns to the foreground.
///
/// The first three skip the backoff of sessions that failed for want of a
/// connection (the network may be fine now), but never a wait the server asked
/// for; a resume and a session end respect every backoff.
final sessionSyncStarterProvider = Provider<void>((ref) {
  final sync = ref.watch(sessionSyncProvider);
  ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, next) {
    if (next.value?.hasUid ?? false) unawaited(sync.syncNow(force: true));
  }, fireImmediately: true);
  final online = connectivityOnlineChanges().listen((online) {
    if (online) unawaited(sync.syncNow(force: true));
  });
  final saved = ref.watch(sessionStoreProvider).saved.listen((_) => unawaited(sync.syncNow()));
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(sync.syncNow()));
  ref.onDispose(() {
    unawaited(online.cancel());
    unawaited(saved.cancel());
    lifecycle.dispose();
  });
});
