import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/play_setup.dart';
import '../domain/session_config.dart' as domain;
import 'setup_screen.dart';

/// Era and difficulty setup. Eras with too few songs playable right now are disabled, and the
/// genre chips are hidden until the round engine can filter by genre.
class SetupRoute extends ConsumerWidget {
  const SetupRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(playSetupProvider);
    final songs = ref
        .watch(playableSongsProvider(domainMode(saved.mode)))
        .asData
        ?.value;
    final settings = effectivePlaySettings(saved, songs);
    final disabled = songs?.disabledEras ?? const <int>{};

    return SetupScreen(
      mode: settings.mode,
      generationId: settings.generationId,
      genre: settings.genre,
      difficulty: settings.difficulty,
      disabledEras: disabled,
      tooFewSongs: songs?.tooFew ?? false,
      totalRounds: domain.SessionConfig.defaultRounds,
      showGenres: false,
      onEra: (id) => updatePlaySetup(ref, (s) => s.copyWith(generationId: id)),
      // Genre chips are hidden, so this is never called.
      onGenre: (_) {},
      onDifficulty: (d) =>
          updatePlaySetup(ref, (s) => s.copyWith(difficulty: d)),
      onBack: () => context.canPop() ? context.pop() : context.go('/mode'),
      onStart: () {
        startPlaying(ref, settings);
        context.go('/play');
      },
    );
  }
}
