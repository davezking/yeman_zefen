import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_text.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../../../prototype/models.dart';

/// Results: the total, how many were right, a new-best badge, where the score
/// stands, and one row per round. Then Play again, Change era or mode, Home.
///
/// Variants, all from [ResultsView]: guest (a dark row opens the sign-in sheet)
/// or signed in (this week's rank); new best; and the score's state: still
/// the phone's own count, the server's, saved for later (offline) or not
/// counted for rankings.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({
    super.key,
    required this.view,
    required this.onPlayAgain,
    required this.onChange,
    required this.onHome,
    required this.onSignIn,
    required this.onLeaderboard,
  });

  final ResultsView view;
  final VoidCallback onPlayAgain;

  /// "Change era or mode": back to setup.
  final VoidCallback onChange;
  final VoidCallback onHome;

  /// The guest row was tapped.
  final VoidCallback onSignIn;

  /// The signed-in rank row was tapped.
  final VoidCallback onLeaderboard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final locale = Localizations.localeOf(context);
    final v = view;
    final grouped = NumberFormat.decimalPattern(locale.toString());

    // Where the score stands: counted on the phone and waiting for the server, saved to send later,
    // refused by the server, or confirmed by it (and, if it differs from the phone's count, said so).
    final note = switch (v.sync) {
      ScoreSync.provisional => (Icons.sync_rounded, l10n.resultsSyncing),
      ScoreSync.savedOffline => (
        Icons.cloud_off_rounded,
        l10n.resultsSavedOffline,
      ),
      ScoreSync.rejected => (Icons.info_outline_rounded, l10n.resultsNotRanked),
      ScoreSync.synced
          when v.provisionalScore != null && v.provisionalScore != v.score =>
        (
          Icons.cloud_done_rounded,
          l10n.resultsServerDiffers(v.score, v.provisionalScore!),
        ),
      ScoreSync.synced => null,
    };

    final rankLine = v.user.isGuest
        ? l10n.resultsGuestRank
        : (v.user.weeklyRank != null
              ? l10n.resultsWeeklyRank(v.user.weeklyRank!)
              : l10n.lbNotRanked);

    return Scaffold(
      body: HeroScaffold(
        denseText: true,
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n20,
          SpacingTokens.n32,
          SpacingTokens.n20,
          SpacingTokens.n24,
        ),
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n16,
          SpacingTokens.n24,
          SpacingTokens.n16,
          SpacingTokens.n16,
        ),
        bodyGap: SpacingTokens.n10,
        hero: Semantics(
          container: true,
          child: Column(
            children: [
              Text(
                l10n.resultsTitle,
                style: text.bodySmall.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
              const SizedBox(height: SpacingTokens.n6),
              AnimatedCount(
                value: v.score,
                fromZero: true,
                builder: (context, shown) =>
                    Text(grouped.format(shown), style: text.score),
              ),
              const SizedBox(height: SpacingTokens.n6),
              Text(
                l10n.resultsCorrectCount(v.correctCount, v.rounds.length),
                style: text.bodyLarge,
              ),
              if (v.newBest) ...[
                const SizedBox(height: SpacingTokens.n6),
                ScoreBadge.best(label: l10n.resultsNewBest),
              ],
            ],
          ),
        ),
        body: [
          _RankRow(
            label: rankLine,
            onTap: v.user.isGuest ? onSignIn : onLeaderboard,
          ),
          if (note != null)
            Semantics(
              liveRegion: true,
              key: const Key('score-note'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    note.$1,
                    size: SizeTokens.icon,
                    color: ColorTokens.textSecondary,
                  ),
                  const SizedBox(width: SpacingTokens.n8),
                  Expanded(
                    child: Text(
                      note.$2,
                      style: text.caption.copyWith(
                        color: ColorTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (v.skipped > 0)
            Text(
              l10n.resultsSkipped(v.skipped),
              key: const Key('skipped'),
              style: text.caption.copyWith(color: ColorTokens.textSecondary),
            ),
          if (v.flagged)
            Text(
              l10n.resultsFlagged,
              key: const Key('flagged'),
              style: text.caption.copyWith(color: ColorTokens.textSecondary),
            ),
          if (v.saveError != null)
            Text(
              l10n.resultsSaveError(v.saveError!),
              key: const Key('save-error'),
              style: text.caption.copyWith(color: ColorTokens.textError),
            ),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.n2),
              child: Text(
                l10n.resultsRounds,
                style: AppTextStyles.withWeight(
                  text.bodySmall,
                  FontWeight.w800,
                ),
              ),
            ),
          ),
          for (var i = 0; i < v.rounds.length; i++)
            _RoundRow(
              number: v.rounds[i].number ?? i + 1,
              result: v.rounds[i],
              line: l10n.trackLine(v.rounds[i].track, locale),
              correctLabel: l10n.feedbackCorrect,
              wrongLabel: l10n.feedbackWrong,
              points: v.rounds[i].correct
                  ? l10n.feedbackPoints(v.rounds[i].points)
                  : '0',
            ),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(label: l10n.resultsPlayAgain, onPressed: onPlayAgain),
            const SizedBox(height: SpacingTokens.n10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.resultsChange,
                      small: true,
                      expand: true,
                      onPressed: onChange,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.n10),
                  Expanded(
                    child: SecondaryButton(
                      label: l10n.resultsHome,
                      small: true,
                      expand: true,
                      onPressed: onHome,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark row under the total: sign in to rank (guest), or this week's rank.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      onTap: onTap,
      semanticLabel: label,
      expand: true,
      minHeight: SizeTokens.secondaryButtonMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.n14,
        vertical: SpacingTokens.n10,
      ),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ColorTokens.paletteSlate, ColorTokens.surfaceDark],
      ),
      shadows: ElevationTokens.dark,
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            size: SizeTokens.iconLarge,
            color: ColorTokens.primaryAccentOnDark,
          ),
          const SizedBox(width: SpacingTokens.n10),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.withWeight(
                context.text.label,
                FontWeight.w600,
              ).copyWith(color: ColorTokens.textOnDark),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: SizeTokens.iconLarge,
            color: ColorTokens.textOnDark,
          ),
        ],
      ),
    );
  }
}

/// One round: its number, a check or an X (with its color), "Song · Artist"
/// and the points.
class _RoundRow extends StatelessWidget {
  const _RoundRow({
    required this.number,
    required this.result,
    required this.line,
    required this.correctLabel,
    required this.wrongLabel,
    required this.points,
  });

  final int number;
  final RoundResult result;
  final String line;
  final String correctLabel;
  final String wrongLabel;
  final String points;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final game = context.game;
    final ok = result.correct;
    final color = ok ? game.correct.heading : game.wrong.heading;
    final numbers = AppTextStyles.withWeight(
      AppTextStyles.latin(text.label),
      FontWeight.w700,
    );
    return Semantics(
      key: Key('round-$number'),
      container: true,
      label: '$number, ${ok ? correctLabel : wrongLabel}, $line, $points',
      child: ExcludeSemantics(
        child: RaisedSurface(
          expand: true,
          minHeight: SizeTokens.chipMinHeight + SpacingTokens.n8,
          borderRadius: BorderRadius.circular(RadiusTokens.small),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
          ),
          shadows: edgeShadow(
            ColorTokens.surfaceCardEdge,
            dy: SpacingTokens.n4,
          ),
          child: Row(
            children: [
              SizedBox(
                width: SpacingTokens.n20,
                child: Text(number.toString(), style: numbers),
              ),
              Icon(
                ok ? Icons.check_rounded : Icons.close_rounded,
                size: SizeTokens.iconSmall,
                color: color,
              ),
              const SizedBox(width: SpacingTokens.n8),
              Expanded(
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.withWeight(text.label, FontWeight.w600),
                ),
              ),
              const SizedBox(width: SpacingTokens.n8),
              Text(points, style: numbers),
            ],
          ),
        ),
      ),
    );
  }
}
