import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_text.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../../../prototype/models.dart';

/// Home: the greeting, the best score and what Play will start, three ways to
/// play, and the Leaderboard entry (`docs/design/screens.md`, "Home").
///
/// Plain data and callbacks only. Guest, signed-in, first-run and offline are
/// all the same screen with different data. Home never prompts for a download.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.quickPlay,
    required this.onPlay,
    required this.onModeSelected,
    required this.onLeaderboard,
    required this.onSettings,
    this.offline = false,
    this.hasDownloadedPacks = false,
    this.builtInSongCount = 0,
    this.modes = GameMode.values,
  });

  /// The modes offered as rows. The app offers only the modes its round engine can play.
  final List<GameMode> modes;

  final UserInfo user;

  /// What the Play button starts (the last-used era, mode and difficulty).
  final PlaySettings quickPlay;

  /// No connection: shows the banner and plays from the songs on the phone.
  final bool offline;

  /// Any pack is installed; the offline banner then says "downloaded" songs too.
  final bool hasDownloadedPacks;
  final int builtInSongCount;

  final VoidCallback onPlay;

  /// A mode row was tapped: open Mode select with this mode chosen.
  final ValueChanged<GameMode> onModeSelected;
  final VoidCallback onLeaderboard;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;

    final leaderboardSub = offline
        ? l10n.homeLeaderboardOffline
        : user.isGuest
        ? l10n.homeLeaderboardGuest
        : user.weeklyRank != null
        ? l10n.resultsWeeklyRank(user.weeklyRank!)
        : l10n.lbNotRanked;

    final best = user.bestScore;
    final bestTile = best == null
        ? StatTile.text(label: l10n.homeBestLabel, text: l10n.homeBestNone)
        : StatTile.number(
            label: l10n.homeBestLabel,
            number: NumberFormat.decimalPattern(
              Localizations.localeOf(context).toString(),
            ).format(best),
          );
    final playsTile = StatTile.text(
      label: l10n.homeQuickPlayLabel,
      text: offline
          ? l10n.quickPlaySummaryOffline(quickPlay)
          : l10n.quickPlaySummary(quickPlay),
    );

    return Scaffold(
      body: HeroScaffold(
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n20,
          SpacingTokens.n30,
          SpacingTokens.n20,
          SpacingTokens.n26,
        ),
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n28,
          SpacingTokens.n18,
          SpacingTokens.n14,
        ),
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LogoTiles(semanticLabel: l10n.appName),
            const SizedBox(height: SpacingTokens.n14),
            if (offline) ...[
              DarkBanner(
                icon: Icons.wifi_off_rounded,
                text: hasDownloadedPacks
                    ? l10n.offlineBanner
                    : l10n.offlineBannerBuiltInOnly(builtInSongCount),
              ),
              const SizedBox(height: SpacingTokens.n14),
            ],
            Text(l10n.homeHello, style: text.title),
            const SizedBox(height: SpacingTokens.n14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: bestTile),
                  const SizedBox(width: SpacingTokens.n10),
                  Expanded(child: playsTile),
                ],
              ),
            ),
          ],
        ),
        body: [
          Semantics(
            header: true,
            child: Text(
              l10n.homeChooseMode,
              style: AppTextStyles.withWeight(text.body, FontWeight.w800),
            ),
          ),
          for (final mode in modes)
            ListRow(
              title: l10n.modeName(mode),
              subtitle: l10n.modeHomeShort(mode),
              icon: modeIcon(mode),
              iconColor: modeColor(mode),
              onTap: () => onModeSelected(mode),
            ),
          ListRow(
            title: l10n.homeLeaderboard,
            subtitle: leaderboardSub,
            icon: Icons.emoji_events_outlined,
            dark: true,
            onTap: onLeaderboard,
          ),
        ],
        bottomBar: AppBottomBar(
          current: NavTab.home,
          homeLabel: l10n.navHome,
          playLabel: l10n.navPlay,
          settingsLabel: l10n.navSettings,
          onHome: () {},
          onPlay: onPlay,
          onSettings: onSettings,
        ),
      ),
    );
  }
}
