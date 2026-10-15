import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'raised_surface.dart';

/// Which account the player signs in with.
enum SsoKind { apple, google, email }

/// One "Continue with ..." button on the sign-in sheet. Apple's is black, the
/// others white. [busy] swaps its icon for a spinner (that one is signing in);
/// a null [onPressed] switches it off while another is.
///
/// The Apple and Google marks are stand-ins (the Apple glyph, a letter G):
/// release builds must use each provider's own button artwork and guidelines.
class SsoButton extends StatelessWidget {
  const SsoButton({
    super.key,
    required this.kind,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final SsoKind kind;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dark = kind == SsoKind.apple;
    final ink = dark ? ColorTokens.paletteWhite : ColorTokens.textPrimary;
    final enabled = onPressed != null || busy;
    final style = AppTextStyles.withWeight(
      context.text.bodyLarge,
      FontWeight.w700,
    ).copyWith(color: ink);

    final Widget mark = busy
        ? SizedBox.square(
            dimension: SizeTokens.iconLarge,
            child: CircularProgressIndicator(
              strokeWidth: SizeTokens.iconStroke,
              color: ink,
            ),
          )
        : switch (kind) {
            SsoKind.apple => Icon(
              Icons.apple,
              size: SizeTokens.iconLarge,
              color: ink,
            ),
            SsoKind.google => Text(
              'G',
              style: AppTextStyles.latin(context.text.bodyLarge)
                  .copyWith(color: ink),
            ),
            SsoKind.email => Icon(
              Icons.mail_outline_rounded,
              size: SizeTokens.iconLarge,
              color: ink,
            ),
          };

    final button = RaisedSurface(
      onTap: busy ? null : onPressed,
      inertButton: true,
      // The mark is decoration; the button reads as its words.
      semanticLabel: label,
      expand: true,
      minHeight: SizeTokens.secondaryButtonMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n16),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [
                ColorTokens.surfaceAppleButtonTop,
                ColorTokens.surfaceAppleButton,
              ]
            : const [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: dark ? ElevationTokens.appleButton : ElevationTokens.row,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: SpacingTokens.n10),
          Flexible(
            child: Text(label, textAlign: TextAlign.center, style: style),
          ),
        ],
      ),
    );
    return enabled
        ? button
        : Opacity(opacity: context.game.answerDimOpacity, child: button);
  }
}
