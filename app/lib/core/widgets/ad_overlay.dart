import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The stand-in for a full-screen ad (the interstitial between rounds, and the
/// rewarded ad behind the hint): a dark screen with an "Ad" badge and its
/// countdown, and a caption underneath. Real ads replace this in Phase 5.
class AdOverlay extends StatelessWidget {
  const AdOverlay({super.key, required this.badge, required this.caption});

  /// "Ad · 2": the ad label and the seconds left.
  final String badge;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$badge. $caption',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ColorTokens.backgroundAdOverlay,
                ColorTokens.backgroundAdOverlayEnd,
              ],
            ),
          ),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.n24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: ColorTokens.paletteSun400,
                      borderRadius: BorderRadius.circular(RadiusTokens.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.n12,
                        vertical: SpacingTokens.n4,
                      ),
                      child: Text(
                        badge,
                        style: AppTextStyles.withWeight(
                          text.label,
                          FontWeight.w800,
                        ).copyWith(color: ColorTokens.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.n20),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: text.titleSmall.copyWith(
                      color: ColorTokens.textOnDark,
                    ),
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
