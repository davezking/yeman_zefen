import 'package:flutter/material.dart';

import '../../core/theme/app_text.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/app_localizations.dart';

/// Ad consent, before Results after the first finished game (only where
/// Google's UMP says consent is required). Continue opens Google's form.
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MessageLayout(
      icon: Icons.favorite_border_rounded,
      badgeColor: ColorTokens.paletteCoral,
      title: l10n.consentTitle,
      body: l10n.consentBody,
      primaryLabel: l10n.consentContinue,
      onPrimary: onContinue,
    );
  }
}

/// The installed version is below the minimum `/v1/config` asks for. The
/// player can update, or keep playing the songs on the phone.
class ForcedUpdateScreen extends StatelessWidget {
  const ForcedUpdateScreen({
    super.key,
    required this.ios,
    required this.onUpdate,
    required this.onPlayOffline,
  });

  /// The App Store wording instead of Google Play's.
  final bool ios;
  final VoidCallback onUpdate;
  final VoidCallback onPlayOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MessageLayout(
      icon: Icons.download_rounded,
      badgeColor: ColorTokens.paletteWhite,
      title: l10n.updateTitle,
      body: l10n.updateBody,
      primaryLabel: ios ? l10n.updateCtaIos : l10n.updateCtaAndroid,
      onPrimary: onUpdate,
      secondaryLabel: l10n.updatePlayOffline,
      onSecondary: onPlayOffline,
    );
  }
}

/// Offline, and every song on the phone was played recently.
class OutOfSongsScreen extends StatelessWidget {
  const OutOfSongsScreen({
    super.key,
    required this.onBrowsePacks,
    required this.onReplay,
  });

  /// Opens Settings › Offline play.
  final VoidCallback onBrowsePacks;

  /// A game that allows recently played songs.
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MessageLayout(
      icon: Icons.repeat_rounded,
      badgeColor: ColorTokens.paletteLavender,
      title: l10n.emptyOutOfSongsTitle,
      body: l10n.emptyOutOfSongsBody,
      primaryLabel: l10n.emptyOutOfSongsPacks,
      onPrimary: onBrowsePacks,
      secondaryLabel: l10n.emptyOutOfSongsReplay,
      onSecondary: onReplay,
    );
  }
}

/// Something went wrong: try again.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MessageLayout(
      icon: Icons.error_outline_rounded,
      badgeColor: ColorTokens.paletteSand,
      title: l10n.errorGenericTitle,
      body: l10n.errorGenericBody,
      primaryLabel: l10n.errorRetry,
      onPrimary: onRetry,
    );
  }
}

/// Where Google's UMP consent form appears. The form is Google's own screen,
/// so the prototype only marks its place (with the app's "Ad" label) and a
/// button to close it as if the player had answered.
class UmpFormPlaceholder extends StatelessWidget {
  const UmpFormPlaceholder({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: SizeTokens.messageHero / 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.surfaceSegmentTrack,
              borderRadius: BorderRadius.circular(RadiusTokens.card),
              border: Border.all(
                color: ColorTokens.surfaceCardEdge,
                width: SizeTokens.eraRing,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.privacy_tip_outlined,
                    size: SizeTokens.modeIconTile,
                    color: ColorTokens.textSecondary,
                  ),
                  const SizedBox(height: SpacingTokens.n8),
                  Text(
                    l10n.settingsAdPrivacy,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.withWeight(
                      text.bodySmall,
                      FontWeight.w700,
                    ).copyWith(color: ColorTokens.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: SpacingTokens.n16),
        PrimaryButton(label: l10n.consentContinue, onPressed: onDone),
      ],
    );
  }
}
