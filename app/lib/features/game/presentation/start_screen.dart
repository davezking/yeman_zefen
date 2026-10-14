import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  void _start() {
    final config = SessionConfig(
      mode: _mode,
      difficulty: _difficulty,
      generationId: _era,
      questions: _questions,
    );
    // Runs until the session ends, so it is not awaited.
    unawaited(ref.read(sessionControllerProvider.notifier).start(config));
    context.go('/play');
  }

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(bestScoreProvider((_mode, _era))).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Heading('What plays'),
          SegmentedButton<GameMode>(
            segments: const [
              ButtonSegment(value: GameMode.intro, label: Text('Intro')),
              ButtonSegment(value: GameMode.middle, label: Text('Middle')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const _Heading('Era'),
          DropdownButton<int>(
            isExpanded: true,
            value: _era,
            items: [
              for (final id in [0, ...eraNames.keys]) DropdownMenuItem(value: id, child: Text(eraName(id))),
            ],
            onChanged: (v) => setState(() => _era = v ?? 0),
          ),
          const _Heading('Difficulty'),
          SegmentedButton<Difficulty>(
            segments: [
              for (final d in Difficulty.values)
                ButtonSegment(
                  value: d,
                  label: Text('${_capitalize(d.name)} · ${d.clipLengthMs ~/ 1000} s'),
                ),
            ],
            selected: {_difficulty},
            onSelectionChanged: (s) => setState(() => _difficulty = s.first),
          ),
          const _Heading('Questions'),
          SegmentedButton<QuestionMix>(
            segments: const [
              ButtonSegment(value: QuestionMix.song, label: Text('Song')),
              ButtonSegment(value: QuestionMix.artist, label: Text('Artist')),
              ButtonSegment(value: QuestionMix.mixed, label: Text('Mixed')),
            ],
            selected: {_questions},
            onSelectionChanged: (s) => setState(() => _questions = s.first),
          ),
          const SizedBox(height: 24),
          Text(
            best == null ? 'No best score yet for this mode and era.' : 'Best score: $best',
            key: const Key('best-score'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _start, child: const Text('Start')),
        ],
      ),
    );
  }

  static String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);
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
