import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/config/remote_config.dart';
import '../../core/db/app_db.dart';
import '../game/application/session_controller.dart';
import '../game/data/session_store.dart';

/// Decides when a guest is asked to register. Nothing here shows UI: the results screen and the
/// leaderboard ask, and show the sheet when the answer is yes.
///
/// A guest is asked after the results screen of session N (`registerPromptAfterSessions`), and
/// again at a results screen once the cooldown after a dismissal has passed. Tapping "see my rank"
/// is the player asking, so it opens the sheet for anyone not registered, whatever the count or
/// cooldown. A registered player is never asked.
class RegisterPromptController {
  RegisterPromptController({
    required this.sessions,
    required this.db,
    required this.config,
    required this.auth,
    required this.nowMs,
  });

  final SessionStore sessions;
  final AppDb db;

  /// Read on every call, so a config refresh applies at once.
  final RemoteConfig Function() config;

  /// Read on every call, so a sign-in or a link applies at once.
  final AuthState Function() auth;

  /// Epoch ms, UTC. A parameter so tests can move the clock.
  final int Function() nowMs;

  /// The last dismissal, epoch ms, in `local_counters` (as the profile sync keeps its times).
  static const dismissedAtKey = 'register_prompt_dismissed_at';

  /// Call on the results screen after a session is saved. True when the sheet should open.
  Future<bool> shouldPromptAfterResults() async {
    if (!_isGuest) return false;
    final completed = await sessions.completedSessionCount();
    if (completed < config().registerPromptAfterSessions) return false;
    return _cooldownPassed();
  }

  /// Call when the player taps "see my rank". True for anyone not registered: there is no rank to
  /// show yet. A device with no account at all is asked too, since signing in creates one.
  bool shouldPromptFromLeaderboard() => !isRegistered;

  /// Signed in with a provider (not a guest).
  bool get isRegistered {
    final who = auth();
    return who.hasUid && !who.isAnonymous;
  }

  /// The player closed the sheet without registering. Starts the cooldown.
  Future<void> dismiss() => db.customStatement(
    'INSERT INTO local_counters (name, count) VALUES (?, ?) '
    'ON CONFLICT(name) DO UPDATE SET count = excluded.count',
    [dismissedAtKey, nowMs()],
  );

  /// A guest with an account. A signed-out device is not asked after results: it has no history
  /// to keep yet.
  bool get _isGuest {
    final who = auth();
    return who.hasUid && who.isAnonymous;
  }

  /// No dismissal, or the last one is a cooldown old. A dismissal in the future (the clock was
  /// wrong then) counts as old, so a fixed clock does not hide the prompt for that long.
  Future<bool> _cooldownPassed() async {
    final row = await (db.select(
      db.localCounters,
    )..where((t) => t.name.equals(dismissedAtKey))).getSingleOrNull();
    if (row == null) return true;
    final now = nowMs();
    final cooldownMs =
        config().registerPromptCooldownDays * Duration.millisecondsPerDay;
    return row.count > now || now - row.count >= cooldownMs;
  }
}

final registerPromptControllerProvider = Provider<RegisterPromptController>(
  (ref) => RegisterPromptController(
    sessions: ref.watch(sessionStoreProvider),
    db: ref.watch(appDbProvider),
    config: () => ref.read(remoteConfigProvider),
    auth: () => ref.read(authServiceProvider).current,
    nowMs: () => DateTime.now().millisecondsSinceEpoch,
  ),
);
