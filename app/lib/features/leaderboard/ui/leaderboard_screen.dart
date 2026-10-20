import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_text.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../../../prototype/models.dart';

/// The leaderboard: yellow from top to bottom, this week or all time, an era
/// filter, the top three on a podium, the rest in rows, and at the bottom
/// either a sign-in bar (guest) or the player's own pinned row.
///
/// Empty, offline with a saved copy, and offline with nothing saved are the
/// same screen with a different [LeaderboardView.state].
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({
    super.key,
    required this.view,
    required this.onBack,
    required this.onScope,
    required this.onEra,
    required this.onSignIn,
    this.onRetry,
    this.onReport,
  });

  final LeaderboardView view;
  final VoidCallback onBack;
  final ValueChanged<LeaderboardScope> onScope;

  /// An era was picked from the filter (0 for all eras).
  final ValueChanged<int> onEra;
  final VoidCallback onSignIn;

  /// Offline with nothing saved: loads the board again. No button when null.
  final VoidCallback? onRetry;

  /// A row or podium place was tapped to report its name as offensive. Rows with no name, and
  /// the player's own name, cannot be reported. Nothing is tappable when null.
  final ValueChanged<LeaderboardEntry>? onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final v = view;
    final top = MediaQuery.paddingOf(context).top;
    final showBoard =
        v.state == LeaderboardState.ready ||
        v.state == LeaderboardState.offlineCached;
    final podium = v.entries.take(3).toList();
    final rest = v.entries.skip(3).toList();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ColorTokens.heroTop,
              ColorTokens.heroMiddle,
              ColorTokens.heroFullScreenBottom,
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                SpacingTokens.n18,
                SpacingTokens.n14 + top,
                SpacingTokens.n18,
                SpacingTokens.n8,
              ),
              child: Row(
                children: [
                  AppBackButton(onPressed: onBack, semanticLabel: l10n.navBack),
                  const SizedBox(width: SpacingTokens.n12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(l10n.lbTitle, style: text.titleSmall),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.n18,
                SpacingTokens.n4,
                SpacingTokens.n18,
                SpacingTokens.n10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedControl<LeaderboardScope>(
                    style: SegmentedStyle.onYellow,
                    semanticLabel: l10n.lbTitle,
                    selected: v.scope,
                    onChanged: onScope,
                    options: [
                      SegmentOption(
                        value: LeaderboardScope.weekly,
                        label: l10n.lbWeekly,
                      ),
                      SegmentOption(
                        value: LeaderboardScope.allTime,
                        label: l10n.lbAllTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.n10),
                  _EraFilter(
                    label: l10n.lbEra(l10n.eraLabel(v.generationId)),
                    selected: v.generationId,
                    onSelected: onEra,
                  ),
                ],
              ),
            ),
            if (v.state == LeaderboardState.offlineCached)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.n18,
                  0,
                  SpacingTokens.n18,
                  SpacingTokens.n10,
                ),
                child: DarkBanner(
                  icon: Icons.wifi_off_rounded,
                  text: l10n.lbOffline(v.cachedAt ?? ''),
                ),
              ),
            Expanded(
              child: v.state == LeaderboardState.loading
                  ? const _Loading()
                  : showBoard
                  ? _Board(
                      podium: podium,
                      rest: rest,
                      reporter: onReport == null ? null : _Reporter(onReport!, v.user.displayName),
                    )
                  : _Message(
                      icon: v.state == LeaderboardState.empty
                          ? Icons.emoji_events_outlined
                          : Icons.wifi_off_rounded,
                      text: v.state == LeaderboardState.empty
                          ? l10n.lbEmpty
                          : l10n.lbOfflineNone,
                      retryLabel: l10n.errorRetry,
                      onRetry: v.state == LeaderboardState.offlineNone
                          ? onRetry
                          : null,
                    ),
            ),
            if (v.state != LeaderboardState.loading)
              _Footer(view: v, onSignIn: onSignIn),
          ],
        ),
      ),
    );
  }
}

/// The era dropdown chip.
/// [LeaderboardScreen.onReport] for the board's rows: a row with no name, or with the player's
/// own name, has nothing to report.
class _Reporter {
  const _Reporter(this.onReport, this.ownName);

  final ValueChanged<LeaderboardEntry> onReport;
  final String? ownName;

  VoidCallback? tapFor(LeaderboardEntry e) =>
      e.name.isEmpty || e.name == ownName ? null : () => onReport(e);
}

class _EraFilter extends StatelessWidget {
  const _EraFilter({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    return PopupMenuButton<int>(
      tooltip: label,
      initialValue: selected,
      onSelected: onSelected,
      color: ColorTokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RadiusTokens.card),
      ),
      itemBuilder: (context) => [
        for (final id in EraId.ordered)
          PopupMenuItem<int>(
            value: id,
            child: Text(
              l10n.eraLabel(id),
              style: id == selected
                  ? AppTextStyles.withWeight(text.body, FontWeight.w800)
                  : text.body,
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SpacingTokens.touchTargetMin,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.surfaceCard,
              borderRadius: BorderRadius.circular(RadiusTokens.pill),
              boxShadow: ElevationTokens.iconButton,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.n12,
                vertical: SpacingTokens.n10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: text.label),
                  const SizedBox(width: SpacingTokens.n6),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: SizeTokens.icon,
                    color: ColorTokens.textPrimary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.podium, required this.rest, this.reporter});

  final List<LeaderboardEntry> podium;
  final List<LeaderboardEntry> rest;
  final _Reporter? reporter;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.n16,
        SpacingTokens.n4,
        SpacingTokens.n16,
        SpacingTokens.n8,
      ),
      children: [
        _Podium(entries: podium, reporter: reporter),
        const SizedBox(height: SpacingTokens.n14),
        for (final e in rest) ...[
          _Row(entry: e, reporter: reporter),
          const SizedBox(height: SpacingTokens.n8),
        ],
      ],
    );
  }
}

/// The top three: second and third at the sides, first larger and in the middle
/// with a crown.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries, this.reporter});

  final List<LeaderboardEntry> entries;
  final _Reporter? reporter;

  @override
  Widget build(BuildContext context) {
    // Left to right: 2nd, 1st, 3rd.
    final order = [
      if (entries.length > 1) entries[1],
      if (entries.isNotEmpty) entries[0],
      if (entries.length > 2) entries[2],
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < order.length; i++) ...[
          if (i > 0) const SizedBox(width: SpacingTokens.n16),
          Flexible(child: _PodiumPlace(entry: order[i], reporter: reporter)),
        ],
      ],
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({required this.entry, this.reporter});

  final LeaderboardEntry entry;
  final _Reporter? reporter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final first = entry.rank == 1;
    final grouped = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(entry.points);
    final report = reporter?.tapFor(entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: report,
      child: Semantics(
        container: true,
        label: '${entry.rank}, ${entry.name}, ${l10n.lbPoints(entry.points)}',
        onTap: report,
        onTapHint: report == null ? null : l10n.lbReportHint,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (first) ...[
                const _Crown(),
                const SizedBox(height: SpacingTokens.n4),
              ],
              AvatarTile(
                bordered: true,
                colorIndex: entry.colorIndex,
                size: first ? SizeTokens.podiumFirst : SizeTokens.podiumOther,
              ),
              const SizedBox(height: SpacingTokens.n4),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.withWeight(
                  text.caption,
                  first ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: first
                      ? ColorTokens.surfaceDark
                      : ColorTokens.paletteWhite,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.n10,
                    vertical: SpacingTokens.n2,
                  ),
                  child: Text(
                    grouped,
                    style:
                        AppTextStyles.withWeight(
                          AppTextStyles.latin(text.caption),
                          FontWeight.w700,
                        ).copyWith(
                          color: first
                              ? ColorTokens.primaryAccentOnDark
                              : ColorTokens.textPrimary,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The crown over first place, drawn as a path (no image).
class _Crown extends StatelessWidget {
  const _Crown();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(SizeTokens.crownWidth, SizeTokens.crownHeight),
      painter: _CrownPainter(),
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // A 26 x 20 drawing: M2 6 l6 5 5-9 5 9 6-5 -2 12 H4 z
    final sx = size.width / 26;
    final sy = size.height / 20;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    final path = Path()
      ..moveTo(p(2, 6).dx, p(2, 6).dy)
      ..lineTo(p(8, 11).dx, p(8, 11).dy)
      ..lineTo(p(13, 2).dx, p(13, 2).dy)
      ..lineTo(p(18, 11).dx, p(18, 11).dy)
      ..lineTo(p(24, 6).dx, p(24, 6).dy)
      ..lineTo(p(22, 18).dx, p(22, 18).dy)
      ..lineTo(p(4, 18).dx, p(4, 18).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = ColorTokens.surfaceDark);
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => false;
}

/// A rank 4 and below: rank, avatar, name, points on a translucent white row.
class _Row extends StatelessWidget {
  const _Row({required this.entry, this.highlighted = false, this.reporter});

  final LeaderboardEntry entry;
  final _Reporter? reporter;

  /// The player's own row.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final numbers = AppTextStyles.withWeight(
      AppTextStyles.latin(text.bodySmall),
      FontWeight.w700,
    );
    final report = reporter?.tapFor(entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: report,
      child: Semantics(
        container: true,
        label: '${entry.rank}, ${entry.name}, ${l10n.lbPoints(entry.points)}',
        onTap: report,
        onTapHint: report == null ? null : l10n.lbReportHint,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: highlighted
                  ? ColorTokens.surfaceCard
                  : ColorTokens.surfaceCardOnYellow,
              borderRadius: BorderRadius.circular(RadiusTokens.large),
              border: highlighted
                  ? Border.all(
                      color: ColorTokens.surfaceDark,
                      width: SizeTokens.eraRing,
                    )
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SizeTokens.leaderboardRowMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.n14,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: SpacingTokens.n24,
                      child: Text(entry.rank.toString(), style: numbers),
                    ),
                    AvatarTile(
                      colorIndex: entry.colorIndex,
                      size: SizeTokens.leaderboardAvatar,
                    ),
                    const SizedBox(width: SpacingTokens.n12),
                    Expanded(
                      child: Text(
                        highlighted ? l10n.lbYou : entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.withWeight(
                          text.bodySmall,
                          highlighted ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(l10n.lbPoints(entry.points), style: numbers),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Loading the leaderboard…" and, if it takes more than a moment, the shape
/// of the board: a podium and seven rows, shimmering.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget row() => Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.n8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorTokens.surfaceSkeletonOnYellow,
          borderRadius: BorderRadius.circular(RadiusTokens.large),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SizeTokens.leaderboardRowMinHeight,
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: SpacingTokens.n14),
            child: Row(
              children: [
                SkeletonBox(
                  onYellow: true,
                  width: SpacingTokens.n16,
                  height: SizeTokens.skeletonLine,
                ),
                SizedBox(width: SpacingTokens.n12),
                SkeletonBox(
                  onYellow: true,
                  width: SizeTokens.leaderboardAvatar,
                  height: SizeTokens.leaderboardAvatar,
                  radius: RadiusTokens.small,
                ),
                SizedBox(width: SpacingTokens.n12),
                Expanded(
                  child: SkeletonBox(
                    onYellow: true,
                    height: SizeTokens.skeletonLine,
                  ),
                ),
                SizedBox(width: SpacingTokens.n32),
                SkeletonBox(
                  onYellow: true,
                  width: SizeTokens.modeIconTile,
                  height: SizeTokens.skeletonLine,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SpacingTokens.n18,
            0,
            SpacingTokens.n18,
            SpacingTokens.n14,
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(l10n.lbLoading, style: context.text.label),
          ),
        ),
        Expanded(
          child: SkeletonDelay(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.n16,
              ),
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SkeletonBox(
                      onYellow: true,
                      width: SizeTokens.podiumOther,
                      height: SizeTokens.podiumOther,
                      radius: RadiusTokens.card,
                    ),
                    SizedBox(width: SpacingTokens.n16),
                    SkeletonBox(
                      onYellow: true,
                      width: SizeTokens.podiumFirst,
                      height: SizeTokens.podiumFirst,
                      radius: RadiusTokens.modeCard,
                    ),
                    SizedBox(width: SpacingTokens.n16),
                    SkeletonBox(
                      onYellow: true,
                      width: SizeTokens.podiumOther,
                      height: SizeTokens.podiumOther,
                      radius: RadiusTokens.card,
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.n18),
                for (var i = 0; i < 7; i++) row(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.retryLabel,
    this.onRetry,
  });

  final IconData icon;
  final String text;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.n32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: SizeTokens.modeIconTile,
                color: ColorTokens.textOnHero,
              ),
              const SizedBox(height: SpacingTokens.n12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: context.text.bodyLarge,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: SpacingTokens.n16),
                SecondaryButton(
                  label: retryLabel,
                  small: true,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar pinned at the bottom: a guest is asked to sign in; a signed-in
/// player sees their own rank.
class _Footer extends StatelessWidget {
  const _Footer({required this.view, required this.onSignIn});

  final LeaderboardView view;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final Widget content;
    if (view.user.isGuest) {
      content = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lbGuestTitle,
                  style: AppTextStyles.withWeight(
                    text.bodyLarge,
                    FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.lbGuestBody,
                  style: text.caption.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.n12),
          PrimaryButton(
            label: l10n.lbGuestCta,
            small: true,
            expand: false,
            onPressed: onSignIn,
          ),
        ],
      );
    } else if (view.me != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lbYourRank(view.me!.rank),
            style: text.caption.copyWith(color: ColorTokens.textSecondary),
          ),
          const SizedBox(height: SpacingTokens.n6),
          _Row(entry: view.me!, highlighted: true),
        ],
      );
    } else {
      content = Semantics(
        liveRegion: true,
        child: Text(l10n.lbNotRanked, style: text.bodySmall),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ColorTokens.backgroundScreen,
        borderRadius: RadiusTokens.sheet,
        boxShadow: ElevationTokens.bottomBar,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n16,
          SpacingTokens.n18,
          SpacingTokens.n22 + bottom,
        ),
        child: content,
      ),
    );
  }
}
