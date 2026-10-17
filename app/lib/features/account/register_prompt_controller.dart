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
/// asks too, but only past the cooldown. A registered player is never asked.
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

  static const dismissedAtKey = 'register_prompt_dismissed_at';

  /// Call on the results screen after a session is saved. True when the sheet should open.
  Future<bool> shouldPromptAfterResults() async {
    final completed = await sessions.completedSessionCount();
    if (completed < config().registerPromptAfterSessions) return false;
    return _cooldownPassed();
  }

  /// Call when a guest taps "see my rank". True when the sheet should open.
  Future<bool> shouldPromptFromLeaderboard() => _cooldownPassed();

  /// The player closed the sheet without registering. Starts the cooldown.
  Future<void> dismiss() {
    return db
        .into(db.localValues)
        .insertOnConflictUpdate(
          LocalValuesCompanion.insert(key: dismissedAtKey, value: '${nowMs()}'),
        );
  }

  /// A guest with an account, and no dismissal in the cooldown. A signed-out device has no account
  /// to link to yet, so it is not asked.
  Future<bool> _cooldownPassed() async {
    final who = auth();
    if (!who.hasUid || !who.isAnonymous) return false;
    final dismissed = await _dismissedAtMs();
    if (dismissed == null) return true;
    final cooldownMs =
        config().registerPromptCooldownDays * Duration.millisecondsPerDay;
    return nowMs() - dismissed >= cooldownMs;
  }

  Future<int?> _dismissedAtMs() async {
    final row = await (db.select(
      db.localValues,
    )..where((t) => t.key.equals(dismissedAtKey))).getSingleOrNull();
    return row == null ? null : int.tryParse(row.value);
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
