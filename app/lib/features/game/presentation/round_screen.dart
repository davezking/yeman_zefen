import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../application/session_controller.dart';
import '../application/session_state.dart';
import '../domain/session_config.dart';
import 'session_texts.dart';

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
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.roundLeaveTitle),
          content: Text(l10n.roundLeaveBody),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.roundLeaveCancel)),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.roundLeaveConfirm)),
          ],
        );
      },
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
    final l10n = AppLocalizations.of(context);
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
          title: Text(round == null ? l10n.roundGetReady : l10n.roundCounter(round.number, round.total)),
          leading: IconButton(
            tooltip: l10n.roundLeave,
            icon: const Icon(Icons.close),
            onPressed: () => over ? context.go('/start') : _confirmLeave(context, ref),
          ),
        ),
        body: switch (state.phase) {
          SessionPhase.failed => _Message(
              text: state.error == null ? l10n.roundCouldNotStart : l10n.sessionErrorText(state.error!),
              action: FilledButton(onPressed: () => context.go('/start'), child: Text(l10n.navBack)),
            ),
          SessionPhase.idle => _Message(
              text: l10n.roundNoGame,
              action: FilledButton(onPressed: () => context.go('/start'), child: Text(l10n.roundStartGame)),
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
    final l10n = AppLocalizations.of(context);
    final answering = round.phase == RoundPhase.answering;
    final showOptions = answering || round.phase == RoundPhase.feedback;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            round.kind == QuestionKind.artist ? l10n.roundQuestionArtist : l10n.roundQuestionSong,
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
                text: l10n.roundPausedBody,
                action: FilledButton(
                  onPressed: ref.read(sessionControllerProvider.notifier).resume,
                  child: Text(l10n.roundResume),
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
    final l10n = AppLocalizations.of(context);
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
        child: Text(l10n.nameOf(option.name, Localizations.localeOf(context)), textAlign: TextAlign.center),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.round});

  final RoundView round;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String text;
    if (round.timedOut) {
      text = l10n.feedbackTimeout;
    } else if (!round.valid) {
      text = l10n.feedbackTooFast;
    } else if (round.isCorrect) {
      text = l10n.feedbackCorrectPoints(round.points ?? 0);
    } else {
      text = l10n.feedbackWrong;
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
