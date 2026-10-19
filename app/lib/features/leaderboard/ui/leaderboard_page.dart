import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../prototype/models.dart';
import '../../account/register_prompt_controller.dart';
import '../../account/ui/register_sheet.dart';
import '../application/leaderboard_providers.dart';
import 'leaderboard_screen.dart';

/// The live leaderboard: the board from `GET /v1/leaderboard`, the player's own row from
/// `/v1/leaderboard/me`, and for a guest a sign-in bar in place of the rank.
class LeaderboardPage extends ConsumerWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(leaderboardQueryProvider);
    final board = ref.watch(leaderboardProvider);
    // A query change or a reload shows the skeleton, not the previous scope's rows.
    final loading = LeaderboardView(
      scope: query.scope,
      generationId: query.generationId,
      entries: const [],
      user: const UserInfo.guest(),
      state: LeaderboardState.loading,
    );
    final view = switch (board) {
      _ when board.isLoading => loading,
      AsyncData(:final value) => value,
      // The provider turns failed requests into the offline state itself; anything else that
      // escapes it shows the same state rather than a skeleton that never ends.
      _ => LeaderboardView(
        scope: query.scope,
        generationId: query.generationId,
        entries: const [],
        user: const UserInfo.guest(),
        state: LeaderboardState.offlineNone,
      ),
    };

    return LeaderboardScreen(
      view: view,
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      onScope: (s) => ref.read(leaderboardQueryProvider.notifier).setScope(s),
      onEra: (id) => ref.read(leaderboardQueryProvider.notifier).setEra(id),
      onSignIn: () => _signIn(context, ref),
      onRetry: () => ref.invalidate(leaderboardProvider),
    );
  }

  /// The guest's sign-in bar. Tapping it is the guest asking, so the sheet opens unless the
  /// controller says no; closing it while still a guest counts as a dismissal.
  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(registerPromptControllerProvider);
    if (!controller.shouldPromptFromLeaderboard()) return;
    final done = await showRegisterSheet(context);
    if (!done && !controller.isRegistered) await controller.dismiss();
  }
}
