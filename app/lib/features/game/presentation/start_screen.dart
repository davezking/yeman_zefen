import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../application/session_controller.dart';
import '../domain/eras.dart';
import '../domain/session_config.dart';

/// Picks the mode, era, difficulty and kind of question, then starts a session.
/// Plain widgets: the designed version replaces this in Phase 4.
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  var _mode = GameMode.intro;
  var _era = 0;
  var _difficulty = Difficulty.medium;
  var _questions = QuestionMix.mixed;

  /// All eras, then the eras with installed songs, in the seed's order.
  List<int> _eraChoices(Set<int> installed) => [0, ...eraIds.where(installed.contains)];

  /// The picked era, or all eras when the picked one has no songs any more.
  int _eraIn(List<int> choices) => choices.contains(_era) ? _era : 0;

  void _start() {
    final era = _eraIn(_eraChoices(ref.read(installedErasProvider).asData?.value ?? const {}));
    final config = SessionConfig(
      mode: _mode,
      difficulty: _difficulty,
      generationId: era,
      questions: _questions,
    );
    // Runs until the session ends, so it is not awaited.
    unawaited(ref.read(sessionControllerProvider.notifier).start(config));
    context.go('/play');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final eras = _eraChoices(ref.watch(installedErasProvider).asData?.value ?? const {});
    final era = _eraIn(eras);
    final best = ref.watch(bestScoreProvider((_mode, era))).asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.startTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Heading(l10n.startWhatPlays),
          SegmentedButton<GameMode>(
            segments: [
              ButtonSegment(value: GameMode.intro, label: Text(l10n.homeQuickPlayModeIntro)),
              ButtonSegment(value: GameMode.middle, label: Text(l10n.homeQuickPlayModeMiddle)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          _Heading(l10n.eraTitle),
          DropdownButton<int>(
            isExpanded: true,
            value: era,
            items: [
              for (final id in eras) DropdownMenuItem(value: id, child: Text(l10n.eraLabel(id))),
            ],
            onChanged: (v) => setState(() => _era = v ?? 0),
          ),
          _Heading(l10n.difficultyTitle),
          SegmentedButton<Difficulty>(
            segments: [
              for (final d in Difficulty.values)
                ButtonSegment(
                  value: d,
                  label: Text(_difficultyLabel(l10n, d)),
                ),
            ],
            selected: {_difficulty},
            onSelectionChanged: (s) => setState(() => _difficulty = s.first),
          ),
          _Heading(l10n.startQuestions),
          SegmentedButton<QuestionMix>(
            segments: [
              ButtonSegment(value: QuestionMix.song, label: Text(l10n.modeGuessSong)),
              ButtonSegment(value: QuestionMix.artist, label: Text(l10n.modeGuessArtist)),
              ButtonSegment(value: QuestionMix.mixed, label: Text(l10n.startQuestionsMixed)),
            ],
            selected: {_questions},
            onSelectionChanged: (s) => setState(() => _questions = s.first),
          ),
          const SizedBox(height: 24),
          Text(
            best == null ? l10n.startBestNone : l10n.bestScore(best),
            key: const Key('best-score'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _start, child: Text(l10n.setupStart(SessionConfig.defaultRounds))),
        ],
      ),
    );
  }

  static String _difficultyLabel(AppLocalizations l10n, Difficulty d) => switch (d) {
        Difficulty.easy => l10n.difficultyEasy,
        Difficulty.medium => l10n.difficultyMedium,
        Difficulty.hard => l10n.difficultyHard,
      };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
