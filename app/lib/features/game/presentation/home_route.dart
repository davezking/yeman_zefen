import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/net/network_kind.dart';

import '../../../core/auth/auth_service.dart';
import '../../../prototype/models.dart' as proto;
import '../../account/data/profile_api.dart';
import '../../settings/application/settings_providers.dart';
import '../application/play_setup.dart';
import '../application/session_controller.dart';
import 'home_screen.dart';

/// Home with the player's real data: the quick-play choices, the best score for them, the
/// account state and whether the phone is offline. Home never asks for a download.
class HomeRoute extends ConsumerWidget {
  const HomeRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(playSetupProvider);
    final songs = ref
        .watch(playableSongsProvider(domainMode(saved.mode)))
        .asData
        ?.value;
    final quick = effectivePlaySettings(saved, songs);

    final best = ref
        .watch(bestScoreProvider((domainMode(quick.mode), quick.generationId)))
        .asData
        ?.value;
    final auth =
        ref.watch(authStateProvider).asData?.value ?? AuthState.signedOut;
    final user = auth.hasUid && !auth.isAnonymous
        ? proto.UserInfo.signedIn(
            displayName: ref.watch(ownNameProvider).asData?.value ?? '',
            bestScore: best,
          )
        : proto.UserInfo.guest(bestScore: best);
    final offline =
        ref.watch(currentNetworkProvider).asData?.value == NetworkKind.none;
    final packs = ref.watch(installedPacksSummaryProvider).asData?.value;

    return HomeScreen(
      user: user,
      quickPlay: quick,
      offline: offline,
      hasDownloadedPacks: (packs?.count ?? 0) > 0,
      builtInSongCount: songs?.onDevice ?? 0,
      modes: const [proto.GameMode.intro, proto.GameMode.middle],
      onPlay: () {
        startPlaying(ref, quick);
        context.go('/play');
      },
      onModeSelected: (mode) {
        updatePlaySetup(ref, (s) => s.copyWith(mode: mode));
        context.go('/mode');
      },
      onLeaderboard: () => context.go('/leaderboard'),
      onSettings: () => context.go('/settings'),
    );
  }
}
