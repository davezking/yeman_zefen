import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'hero_scaffold.dart';
import 'raised_surface.dart';

/// The message-screen template (ad consent, forced update, out of songs,
/// errors): a tall hero with one big icon badge, then a title, a paragraph and
/// up to three actions at the bottom.
class MessageLayout extends StatelessWidget {
  const MessageLayout({
    super.key,
    required this.icon,
    required this.badgeColor,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.linkLabel,
    this.onLink,
  });

  final IconData icon;

  /// Coral for consent, white for update, lavender for out of songs.
  final Color badgeColor;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Scaffold(
      body: HeroScaffold(
        heroPadding: EdgeInsets.zero,
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n22,
          SpacingTokens.n32,
          SpacingTokens.n22,
          SpacingTokens.n22,
        ),
        hero: SizedBox(
          height: SizeTokens.messageHero,
          child: Center(
            child: ExcludeSemantics(
              child: DecoratedBox(
                // The translucent ring around the badge.
                decoration: BoxDecoration(
                  color: ColorTokens.cassetteRim,
                  borderRadius: BorderRadius.circular(
                    RadiusTokens.badge + SizeTokens.cassetteRim,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SizeTokens.cassetteRim),
                  child: RaisedSurface(
                    minWidth: SizeTokens.messageBadge,
                    minHeight: SizeTokens.messageBadge,
                    borderRadius: BorderRadius.circular(RadiusTokens.badge),
                    color: badgeColor,
                    shadows: ElevationTokens.iconButton,
                    inset: ElevationTokens.glossInset,
                    child: Icon(
                      icon,
                      size: SizeTokens.messageBadgeIcon,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: [
          Semantics(header: true, child: Text(title, style: text.title)),
          Text(
            body,
            style: text.body.copyWith(color: ColorTokens.textSecondary),
          ),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(label: primaryLabel, onPressed: onPrimary),
            if (secondaryLabel != null) ...[
              const SizedBox(height: SpacingTokens.n10),
              SecondaryButton(label: secondaryLabel!, onPressed: onSecondary),
            ],
            if (linkLabel != null)
              TextButton(onPressed: onLink, child: Text(linkLabel!)),
          ],
        ),
      ),
    );
  }
}
