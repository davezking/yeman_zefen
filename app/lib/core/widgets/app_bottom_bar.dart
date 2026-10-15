import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// Which tab of the bottom bar is current.
enum NavTab { home, settings }

/// The bar on Home and Settings: a Home button, the big Play button, and a
/// Settings button. The current tab's button is dark with a yellow icon. Play
/// is not a tab: it starts a game with the last-used settings.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.current,
    required this.homeLabel,
    required this.playLabel,
    required this.settingsLabel,
    required this.onHome,
    required this.onPlay,
    required this.onSettings,
  });

  final NavTab current;
  final String homeLabel;
  final String playLabel;
  final String settingsLabel;
  final VoidCallback onHome;
  final VoidCallback onPlay;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ColorTokens.backgroundScreen,
        borderRadius: RadiusTokens.bottomBar,
        boxShadow: ElevationTokens.bottomBar,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SpacingTokens.n26,
          SpacingTokens.n14,
          SpacingTokens.n26,
          SpacingTokens.n20 + bottom,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavButton(
              icon: Icons.home_outlined,
              label: homeLabel,
              current: current == NavTab.home,
              onTap: onHome,
            ),
            _PlayButton(label: playLabel, onTap: onPlay),
            _NavButton(
              icon: Icons.tune_rounded,
              label: settingsLabel,
              current: current == NavTab.settings,
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      onTap: onTap,
      selected: current,
      semanticLabel: label,
      minWidth: SizeTokens.navButton,
      minHeight: SizeTokens.navButton,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      color: current ? ColorTokens.surfaceDark : ColorTokens.surfaceCard,
      shadows: current ? ElevationTokens.dark : ElevationTokens.row,
      child: Icon(
        icon,
        size: SizeTokens.iconLarge,
        color: current
            ? ColorTokens.primaryAccentOnDark
            : ColorTokens.textPrimary,
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      onTap: onTap,
      semanticLabel: label,
      minWidth: SizeTokens.playButtonMinWidth,
      minHeight: SizeTokens.playButtonHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.playButton),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n16),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ColorTokens.primaryFillTop,
          ColorTokens.primaryFill,
          ColorTokens.primaryFillBottom,
        ],
        stops: [0, 0.5, 1],
      ),
      shadows: ElevationTokens.primary,
      inset: ElevationTokens.primaryInset,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_arrow_rounded,
            size: SizeTokens.iconLarge,
            color: ColorTokens.primaryOnFill,
          ),
          const SizedBox(width: SpacingTokens.n8),
          Flexible(
            child: Text(
              label,
              style: context.text.button.copyWith(
                color: ColorTokens.primaryOnFill,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
