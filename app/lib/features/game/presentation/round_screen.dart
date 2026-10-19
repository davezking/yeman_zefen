import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../../../prototype/models.dart';

/// The round: the cassette, the timer, the question and four answers, then the
/// reveal. It draws one [RoundView] and reports what the player does; the clock
/// and the rules are not here (the prototype's simulation, and later the real
/// engine, own them).
///
/// States, all from [RoundView]: clip playing, answering, correct reveal, wrong
/// reveal with the right answer shown, hint available, hint applied, time-out,
/// and paused (hint sheet, ad, leave dialog or the app in the background).
class RoundScreen extends StatelessWidget {
  const RoundScreen({
    super.key,
    required this.view,
    required this.onAnswer,
    required this.onHint,
    required this.onContinue,
    required this.onLeaveRequested,
    required this.onLeaveConfirmed,
    required this.onLeaveCancelled,
    required this.onWatchHintAd,
    required this.onDeclineHint,
    this.onResume,
  });

  final RoundView view;

  /// An answer tile was tapped (its index, 0 to 3).
  final ValueChanged<int> onAnswer;
  final VoidCallback onHint;

  /// A tap on the wrong-answer screen: move on now.
  final VoidCallback onContinue;

  /// The back button.
  final VoidCallback onLeaveRequested;
  final VoidCallback onLeaveConfirmed;
  final VoidCallback onLeaveCancelled;
  final VoidCallback onWatchHintAd;
  final VoidCallback onDeclineHint;

  /// "Resume" on the paused overlay, shown when the app comes back from the background.
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final locale = Localizations.localeOf(context);
    final v = view;
    final locked = v.overlay != RoundOverlay.none;

    final pill = v.timerPaused
        ? l10n.roundTimerPaused
        : l10n.roundSecondsLeft(v.secondsLeft);
    // Screen readers hear the time at 10 s and 5 s, not every second.
    final announce =
        v.phase == RoundPhase.answering &&
        !v.timerPaused &&
        (v.secondsLeft == 10 || v.secondsLeft == 5);

    final tiles = [
      for (var i = 0; i < v.options.length; i++)
        _tile(context, l10n, locale, i, locked),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // A tap anywhere skips the wrong-answer screen.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _skippable ? onContinue : null,
            child: HeroScaffold(
              bodyFoot: true,
              heroPadding: const EdgeInsets.fromLTRB(
                SpacingTokens.n18,
                SpacingTokens.n10,
                SpacingTokens.n18,
                SpacingTokens.n20,
              ),
              bodyPadding: const EdgeInsets.fromLTRB(
                SpacingTokens.n16,
                SpacingTokens.n26,
                SpacingTokens.n16,
                SpacingTokens.n16,
              ),
              hero: Column(
                children: [
                  _TopRow(
                    counter: l10n.roundCounter(v.roundNumber, v.totalRounds),
                    score: v.score,
                    scoreLabel: l10n.roundScore,
                    leaveLabel: l10n.roundLeave,
                    onLeave: onLeaveRequested,
                  ),
                  const SizedBox(height: SpacingTokens.n12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: SpacingTokens.n8,
                    runSpacing: SpacingTokens.n8,
                    children: [
                      EraChip(
                        label: l10n.eraLabel(v.eraFilterId),
                        generationId: v.eraFilterId,
                      ),
                      EraChip(
                        label: l10n.difficultyLabel(v.difficulty),
                        generationId: EraId.all,
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.n12),
                  PlayingIndicator(
                    playing: v.clipPlaying,
                    semanticLabel: l10n.a11yPlaying,
                  ),
                  const SizedBox(height: SpacingTokens.n12),
                  TimerBar(
                    fraction: v.timeFraction,
                    // Waiting for the clip: a full bar and no seconds.
                    label: v.phase == RoundPhase.loading ? null : pill,
                    semanticLabel: v.phase == RoundPhase.loading
                        ? l10n.roundLoading
                        : v.timerPaused
                        ? l10n.roundTimerPaused
                        : l10n.a11yTimer(v.secondsLeft),
                  ),
                  if (announce)
                    Semantics(
                      liveRegion: true,
                      label: l10n.a11yTimer(v.secondsLeft),
                      child: const SizedBox.shrink(),
                    ),
                ],
              ),
              body: [
                _Status(view: v, l10n: l10n, locale: locale),
                EqualHeightGrid(children: tiles),
              ],
              footer: SizedBox(
                height: SizeTokens.secondaryButtonMinHeight + SpacingTokens.n10,
                child: Center(child: _footer(context, l10n, text)),
              ),
            ),
          ),
          _Overlays(
            view: v,
            onWatchHintAd: onWatchHintAd,
            onDeclineHint: onDeclineHint,
            onLeaveConfirmed: onLeaveConfirmed,
            onLeaveCancelled: onLeaveCancelled,
            onResume: onResume,
          ),
        ],
      ),
    );
  }

  bool get _skippable =>
      view.overlay == RoundOverlay.none &&
      (view.phase == RoundPhase.wrong || view.phase == RoundPhase.timeout);

  Widget _tile(
    BuildContext context,
    AppLocalizations l10n,
    Locale locale,
    int i,
    bool locked,
  ) {
    final v = view;
    if (v.phase == RoundPhase.loading) {
      // The box keeps the grid's height while the skeleton waits to appear.
      return const SizedBox(
        height: SizeTokens.answerTileMinHeight,
        child: SkeletonDelay(
          child: SkeletonBox(
            height: SizeTokens.answerTileMinHeight,
            radius: RadiusTokens.large,
          ),
        ),
      );
    }
    final label = l10n.optionLabel(v.options[i], v.kind, locale);
    final a11y = l10n.a11yAnswer(i + 1, label);
    if (v.phase == RoundPhase.answering) {
      final removed = v.removed.contains(i);
      return AnswerTile(
        text: label,
        semanticLabel: a11y,
        state: removed ? AnswerState.removed : AnswerState.idle,
        onTap: removed || locked ? null : () => onAnswer(i),
      );
    }
    if (i == v.correctIndex) {
      return AnswerTile(
        text: label,
        semanticLabel: a11y,
        state: AnswerState.correct,
        stateLabel: l10n.feedbackCorrect,
      );
    }
    if (i == v.pickedIndex) {
      return AnswerTile(
        text: label,
        semanticLabel: a11y,
        state: AnswerState.wrong,
        stateLabel: l10n.feedbackYourPick,
      );
    }
    return AnswerTile(
      text: label,
      semanticLabel: a11y,
      state: v.removed.contains(i) ? AnswerState.removed : AnswerState.disabled,
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l10n,
    AppTextStyles text,
  ) {
    final v = view;
    switch (v.phase) {
      case RoundPhase.loading:
        return const SizedBox.shrink();
      case RoundPhase.answering:
        if (v.hintAvailable) {
          return _HintButton(
            label: l10n.roundHintButton,
            onTap: v.overlay == RoundOverlay.none ? onHint : null,
          );
        }
        if (v.hintUsed) {
          return Text(
            l10n.feedbackHintUsed,
            style: text.label.copyWith(color: ColorTokens.textSecondary),
          );
        }
        return const SizedBox.shrink();
      case RoundPhase.wrong || RoundPhase.timeout:
        return TextButton(
          onPressed: _skippable ? onContinue : null,
          child: Text(
            l10n.feedbackTapToContinue(v.feedbackSecondsLeft),
            style: AppTextStyles.withWeight(
              text.body,
              FontWeight.w600,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        );
      case RoundPhase.correct:
        return v.hintUsed
            ? Text(
                l10n.feedbackHintUsed,
                style: text.label.copyWith(color: ColorTokens.textSecondary),
              )
            : const SizedBox.shrink();
    }
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.counter,
    required this.score,
    required this.scoreLabel,
    required this.leaveLabel,
    required this.onLeave,
  });

  final String counter;
  final int score;
  final String Function(int points) scoreLabel;
  final String leaveLabel;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Row(
      children: [
        AppBackButton(onPressed: onLeave, semanticLabel: leaveLabel),
        Expanded(
          child: Text(
            counter,
            textAlign: TextAlign.center,
            // The counter is always Poppins, in both languages.
            style: AppTextStyles.withWeight(
              AppTextStyles.latin(text.body),
              FontWeight.w700,
            ),
          ),
        ),
        AnimatedCount(
          value: score,
          builder: (context, shown) => Text(
            scoreLabel(shown),
            style: AppTextStyles.withWeight(text.bodySmall, FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// The 64 dp area under the hero: the question, or what happened.
class _Status extends StatelessWidget {
  const _Status({required this.view, required this.l10n, required this.locale});

  final RoundView view;
  final AppLocalizations l10n;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final game = context.game;
    final v = view;

    final String head;
    final Color color;
    TextStyle style = text.titleSmall;
    String? sub;
    switch (v.phase) {
      case RoundPhase.loading:
        head = l10n.roundLoading;
        color = ColorTokens.textPrimary;
        sub = l10n.roundLoadingNote;
      case RoundPhase.answering:
        head = l10n.questionText(v.kind);
        color = ColorTokens.textPrimary;
      case RoundPhase.correct:
        head = '${l10n.feedbackCorrect} ${l10n.feedbackPoints(v.points)}';
        color = game.correct.heading;
        style = text.title;
        sub = v.hintUsed
            ? l10n.feedbackHintUsed
            : l10n.feedbackSpeedBonus(v.speedBonus);
      case RoundPhase.wrong || RoundPhase.timeout:
        head = v.phase == RoundPhase.timeout
            ? l10n.feedbackTimeout
            : l10n.feedbackWrong;
        color = game.wrong.heading;
        style = text.title;
        sub = v.kind == QuestionKind.era
            ? l10n.feedbackRevealEra(l10n.eraLabel(v.track.generationId))
            : l10n.feedbackReveal(
                v.track.title(locale),
                v.track.artist(locale),
              );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          head,
          textAlign: TextAlign.center,
          style: style.copyWith(color: color),
        ),
        if (sub != null)
          Text(
            sub,
            textAlign: TextAlign.center,
            style: AppTextStyles.withWeight(
              text.label,
              FontWeight.w600,
            ).copyWith(color: ColorTokens.textSecondary),
          ),
      ],
    );

    // The pop: scale in. With reduced motion it is a plain fade.
    final reduce = context.reduceMotion;
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SizeTokens.answerTileMinHeight - SpacingTokens.n20,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: reduce ? game.fadeDuration : game.popDuration,
            switchInCurve: game.standardCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: reduce
                  ? child
                  : ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.96,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
            ),
            child: KeyedSubtree(key: ValueKey(v.phase), child: content),
          ),
        ),
      ),
    );
  }
}

/// The white "Hint" button with a lightbulb.
class _HintButton extends StatelessWidget {
  const _HintButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      onTap: onTap,
      inertButton: true,
      semanticLabel: label,
      minHeight: SizeTokens.secondaryButtonMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n18),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: ElevationTokens.row,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: SizeTokens.iconLarge,
            color: ColorTokens.textPrimary,
          ),
          const SizedBox(width: SpacingTokens.n8),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// What covers the round: the hint sheet, the two ads, the leave dialog. They
/// fade in, and the sheet also slides up unless the system asked for reduced
/// motion.
class _Overlays extends StatelessWidget {
  const _Overlays({
    required this.view,
    required this.onWatchHintAd,
    required this.onDeclineHint,
    required this.onLeaveConfirmed,
    required this.onLeaveCancelled,
    this.onResume,
  });

  final RoundView view;
  final VoidCallback onWatchHintAd;
  final VoidCallback onDeclineHint;
  final VoidCallback onLeaveConfirmed;
  final VoidCallback onLeaveCancelled;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final reduce = context.reduceMotion;
    final l10n = AppLocalizations.of(context);

    Widget scrimmed(Widget child, {Alignment align = Alignment.center}) =>
        Positioned.fill(
          child: ColoredBox(
            color: ColorTokens.backgroundScrim,
            child: Align(alignment: align, child: child),
          ),
        );

    Widget? layer;
    switch (view.overlay) {
      case RoundOverlay.none:
        layer = null;
      case RoundOverlay.hintSheet:
        layer = scrimmed(
          _HintSheet(
            seconds: view.overlaySeconds,
            onWatch: onWatchHintAd,
            onDecline: onDeclineHint,
          ),
          align: Alignment.bottomCenter,
        );
      case RoundOverlay.rewardedAd:
        layer = Positioned.fill(
          child: AdOverlay(
            badge: '${l10n.adLabel} · ${view.overlaySeconds}',
            caption: l10n.adRewardCaption,
          ),
        );
      case RoundOverlay.interstitial:
        layer = Positioned.fill(
          child: AdOverlay(
            badge: '${l10n.adLabel} · ${view.overlaySeconds}',
            caption: l10n.adInterstitialCaption,
          ),
        );
      case RoundOverlay.paused:
        layer = scrimmed(
          AppDialog(
            title: l10n.roundPausedTitle,
            body: l10n.roundPausedBody,
            confirmLabel: l10n.roundResume,
            onConfirm: onResume ?? () {},
          ),
        );
      case RoundOverlay.leaveDialog:
        layer = scrimmed(
          AppDialog(
            title: l10n.roundLeaveTitle,
            body: l10n.roundLeaveBody,
            confirmLabel: l10n.roundLeaveConfirm,
            cancelLabel: l10n.roundLeaveCancel,
            onConfirm: onLeaveConfirmed,
            onCancel: onLeaveCancelled,
          ),
        );
    }

    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: game.fadeDuration,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        transitionBuilder: (child, animation) {
          final fade = FadeTransition(opacity: animation, child: child);
          if (reduce || view.overlay != RoundOverlay.hintSheet) return fade;
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: fade,
          );
        },
        child: layer == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Stack(key: ValueKey(view.overlay), children: [layer]),
      ),
    );
  }
}

/// "Hint: remove 2 answers": the terms, the pause note, Watch ad and No thanks,
/// with a countdown to the moment it closes by itself.
class _HintSheet extends StatelessWidget {
  const _HintSheet({
    required this.seconds,
    required this.onWatch,
    required this.onDecline,
  });

  final int seconds;
  final VoidCallback onWatch;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    return AppSheet(
      semanticLabel: l10n.roundHint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.roundHint, style: text.titleSmall)),
              const SizedBox(width: SpacingTokens.n10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorTokens.paletteSun400,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.n10,
                    vertical: SpacingTokens.n2,
                  ),
                  child: Text(
                    l10n.roundHintClosesIn(seconds),
                    style: text.label,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.n12),
          Text(
            l10n.roundHintTerms,
            style: text.body.copyWith(color: ColorTokens.textSecondary),
          ),
          const SizedBox(height: SpacingTokens.n12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.surfaceSegmentTrack,
              borderRadius: BorderRadius.circular(RadiusTokens.small),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.n12,
                vertical: SpacingTokens.n10,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.pause_circle_outline_rounded,
                    size: SizeTokens.icon,
                    color: ColorTokens.textPrimary,
                  ),
                  const SizedBox(width: SpacingTokens.n10),
                  Expanded(
                    child: Text(
                      l10n.roundHintPaused,
                      style: AppTextStyles.withWeight(
                        text.label,
                        FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.n12),
          PrimaryButton(label: l10n.roundHintWatch, onPressed: onWatch),
          TextButton(
            onPressed: onDecline,
            child: Text(
              l10n.roundHintCancel,
              style: AppTextStyles.withWeight(
                text.body,
                FontWeight.w600,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }
}
