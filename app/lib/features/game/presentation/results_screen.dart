import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/session_controller.dart';
import '../application/session_state.dart';
import '../domain/eras.dart';
import '../domain/session_config.dart';

/// The total score and each round. Plain widgets: the designed version
/// replaces this in Phase 4.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(sessionControllerProvider).summary;

    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No finished game to show.'),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/start'), child: const Text('New game')),
            ],
          ),
        ),
      );
    }

    final config = summary.config;
    return Scaffold(
      appBar: AppBar(title: const Text('Results'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${summary.totalScore}',
            key: const Key('total-score'),
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          Text(
            '${config.mode == GameMode.middle ? 'Middle' : 'Intro'} · ${eraName(config.generationId)} · '
            '${config.difficulty.name}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (summary.isNewBest)
            const Text('New best score!', key: Key('new-best'), textAlign: TextAlign.center)
          else if (summary.bestBefore != null)
            Text('Best score: ${summary.bestBefore}', key: const Key('best'), textAlign: TextAlign.center),
          if (summary.skipped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${summary.skipped} ${summary.skipped == 1 ? 'round was' : 'rounds were'} skipped because a clip '
                'could not be played.',
                key: const Key('skipped'),
                textAlign: TextAlign.center,
              ),
            ),
          if (summary.flagged)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Some answers were too fast to count.', key: Key('flagged'), textAlign: TextAlign.center),
            ),
          if (summary.saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This game could not be saved on the device: ${summary.saveError}',
                key: const Key('save-error'),
                textAlign: TextAlign.center,
              ),
            ),
          const Divider(height: 32),
          for (final round in summary.rounds) _RoundRow(round: round),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => context.go('/start'), child: const Text('Play again')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.go('/'), child: const Text('Home')),
        ],
      ),
    );
  }
}

class _RoundRow extends StatelessWidget {
  const _RoundRow({required this.round});

  final RoundSummary round;

  @override
  Widget build(BuildContext context) {
    final icon = round.chosenLabel == null
        ? Icons.timer_off
        : (round.correct ? Icons.check_circle : Icons.cancel);
    final color = round.correct ? Colors.green : Colors.red;
    return ListTile(
      key: Key('round-${round.number}'),
      leading: Icon(icon, color: color),
      title: Text(round.correctLabel),
      subtitle: Text(
        round.chosenLabel == null
            ? 'Time ran out'
            : (round.correct ? 'Correct' : 'You chose ${round.chosenLabel!.replaceAll('\n', ' · ')}'),
      ),
      trailing: Text('${round.points}'),
    );
  }
}
