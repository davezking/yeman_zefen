import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../prototype/models.dart' as proto;
import '../application/play_setup.dart';
import 'mode_select_screen.dart';

/// Mode select with the saved choices. Era guessing is not offered until the round engine plays it.
class ModeRoute extends ConsumerWidget {
  const ModeRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playSetupProvider);
    return ModeSelectScreen(
      mode: settings.mode,
      guess: settings.guess,
      modes: const [proto.GameMode.intro, proto.GameMode.middle],
      onModeChanged: (mode) =>
          updatePlaySetup(ref, (s) => s.copyWith(mode: mode)),
      onGuessChanged: (guess) =>
          updatePlaySetup(ref, (s) => s.copyWith(guess: guess)),
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      onNext: () => context.go('/setup'),
    );
  }
}
