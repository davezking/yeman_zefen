import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../application/session_controller.dart';
import '../application/session_state.dart';
import '../domain/session_config.dart';
import 'session_texts.dart';

/// The total score and each round. Plain widgets: the designed version
/// replaces this in Phase 4.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(sessionControllerProvider).summary;

    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.resultsTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.resultsNone),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/setup'), child: Text(l10n.startTitle)),
            ],
          ),
        ),
      );
    }

    final config = summary.config;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resultsTitle), automaticallyImplyLeading: false),
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
            l10n.homeQuickPlaySettings(
              l10n.eraLabel(config.generationId),
              switch (config.mode) {
                GameMode.intro => l10n.homeQuickPlayModeIntro,
                GameMode.middle => l10n.homeQuickPlayModeMiddle,
                GameMode.generation => l10n.homeQuickPlayModeEra,
              },
              switch (config.difficulty) {
                Difficulty.easy => l10n.difficultyEasyShort,
                Difficulty.medium => l10n.difficultyMediumShort,
                Difficulty.hard => l10n.difficultyHardShort,
              },
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (summary.isNewBest)
            Text(l10n.resultsNewBest, key: const Key('new-best'), textAlign: TextAlign.center)
          else if (summary.bestBefore != null)
            Text(l10n.bestScore(summary.bestBefore!), key: const Key('best'), textAlign: TextAlign.center),
          if (summary.skipped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.resultsSkipped(summary.skipped),
                key: const Key('skipped'),
                textAlign: TextAlign.center,
              ),
            ),
          if (summary.flagged)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.resultsFlagged, key: const Key('flagged'), textAlign: TextAlign.center),
            ),
          if (summary.saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.resultsSaveError(summary.saveError!),
                key: const Key('save-error'),
                textAlign: TextAlign.center,
              ),
            ),
          const Divider(height: 32),
          for (final round in summary.rounds) _RoundRow(round: round),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => context.go('/setup'), child: Text(l10n.resultsPlayAgain)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.go('/'), child: Text(l10n.resultsHome)),
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
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final icon = round.chosenName == null
        ? Icons.timer_off
        : (round.correct ? Icons.check_circle : Icons.cancel);
    final color = round.correct ? Colors.green : Colors.red;
    return ListTile(
      key: Key('round-${round.number}'),
      leading: Icon(icon, color: color),
      title: Text(l10n.nameOf(round.correctName, locale)),
      subtitle: Text(
        round.chosenName == null
            ? l10n.feedbackTimeout
            : (round.correct
                ? l10n.feedbackCorrect
                // An era question's answer is an era, named in the UI language.
                : l10n.resultsYouChose(
                    round.chosenEraId != null ? l10n.eraLabel(round.chosenEraId!) : l10n.nameOf(round.chosenName!, locale),
                  )),
      ),
      trailing: Text('${round.points}'),
    );
  }
}
