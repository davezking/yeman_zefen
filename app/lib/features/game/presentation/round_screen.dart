import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/session_controller.dart';
import '../application/session_state.dart';
import '../domain/session_config.dart';

/// One round: the clip plays, a bar counts down the answer window, and four
/// options appear. Plain widgets: the designed version replaces this in Phase 4.
class RoundScreen extends ConsumerStatefulWidget {
  const RoundScreen({super.key});

  @override
  ConsumerState<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends ConsumerState<RoundScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Going to the background pauses the round. Coming back shows Resume.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ref.read(sessionControllerProvider.notifier).pauseForBackground();
    }
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text('Your score for this game will not be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep playing')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && context.mounted) {
      ref.read(sessionControllerProvider.notifier).leave();
      context.go('/start');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next.phase == SessionPhase.finished && previous?.phase != SessionPhase.finished) {
        context.go('/results');
      }
    });
    final state = ref.watch(sessionControllerProvider);
    final round = state.round;
    final over = state.phase == SessionPhase.failed || state.phase == SessionPhase.idle;

    return PopScope(
      canPop: over,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(round == null ? 'Get ready' : 'Round ${round.number} of ${round.total}'),
          leading: IconButton(
            tooltip: 'Leave',
            icon: const Icon(Icons.close),
            onPressed: () => over ? context.go('/start') : _confirmLeave(context, ref),
          ),
        ),
        body: switch (state.phase) {
          SessionPhase.failed => _Message(
              text: state.error ?? 'The game could not start.',
              action: FilledButton(onPressed: () => context.go('/start'), child: const Text('Back')),
            ),
          SessionPhase.idle => _Message(
              text: 'No game is running.',
              action: FilledButton(onPressed: () => context.go('/start'), child: const Text('Start a game')),
            ),
          SessionPhase.preparing || SessionPhase.finished => const Center(child: CircularProgressIndicator()),
          SessionPhase.playing => round == null
              ? const Center(child: CircularProgressIndicator())
              : _RoundBody(round: round),
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, key: const Key('message'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      );
}

class _RoundBody extends ConsumerWidget {
  const _RoundBody({required this.round});

  final RoundView round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answering = round.phase == RoundPhase.answering;
    final showOptions = answering || round.phase == RoundPhase.feedback;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            round.kind == QuestionKind.artist ? 'Who sings this?' : 'Which song is this?',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 8,
            child: answering
                // A new key restarts the bar when the round is replayed after a call.
                ? _CountdownBar(
                    key: ValueKey('${round.number}-${round.attempt}'),
                    windowMs: round.windowMs,
                    remainingMs: round.remainingMs,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          if (round.phase == RoundPhase.loading) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (round.phase == RoundPhase.interrupted)
            Expanded(
              child: _Message(
                text: 'Paused. The clip plays again when you resume. The time you already used still counts.',
                action: FilledButton(
                  onPressed: ref.read(sessionControllerProvider.notifier).resume,
                  child: const Text('Resume'),
                ),
              ),
            ),
          if (showOptions) ...[
            if (round.phase == RoundPhase.feedback) _Feedback(round: round),
            Expanded(
              child: ListView(
                children: [
                  for (final option in round.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OptionButton(
                        option: option,
                        round: round,
                        onPressed: answering
                            ? () => ref.read(sessionControllerProvider.notifier).answer(option.id)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.option, required this.round, required this.onPressed});

  final AnswerOption option;
  final RoundView round;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final feedback = round.phase == RoundPhase.feedback;
    final isCorrect = feedback && option.id == round.correctId;
    final isWrongChoice = feedback && option.id == round.chosenId && option.id != round.correctId;
    final color = isCorrect ? Colors.green : (isWrongChoice ? Colors.red : null);

    return FilledButton(
      key: Key('option-${option.id}'),
      style: color == null
          ? null
          : FilledButton.styleFrom(backgroundColor: color, disabledBackgroundColor: color, foregroundColor: Colors.white, disabledForegroundColor: Colors.white),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(option.label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.round});

  final RoundView round;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (round.timedOut) {
      text = "Time's up";
    } else if (!round.valid) {
      text = 'Too fast to count. 0 points';
    } else if (round.isCorrect) {
      text = 'Correct! +${round.points}';
    } else {
      text = 'Wrong. 0 points';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        key: const Key('feedback'),
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// A bar that empties over the answer window. After a pause it starts part
/// empty, at the time that was left. It only shows the time; the session
/// controller owns the real timer.
class _CountdownBar extends StatelessWidget {
  const _CountdownBar({super.key, required this.windowMs, required this.remainingMs});

  final int windowMs;
  final int remainingMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: remainingMs / windowMs, end: 0),
      duration: Duration(milliseconds: remainingMs),
      builder: (context, value, _) => LinearProgressIndicator(key: const Key('countdown'), value: value),
    );
  }
}
