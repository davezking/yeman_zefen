import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'edge_shadow.dart';
import 'raised_surface.dart';

/// The main call to action: yellow, with a press edge. [small] is the compact
/// version used inside rows (Download, Sign in).
///
/// A null [onPressed] disables it and dims it like a disabled answer.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.small = false,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// The 44 dp row button instead of the 58 dp full-size one.
  final bool small;

  /// Fill the width. Ignored for [small] buttons, which size to their label.
  final bool expand;

  /// Drawn before the label (the Play button's triangle).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textStyles = context.text;
    final style = small
        ? AppTextStyles.withWeight(
            textStyles.bodySmall,
            TypeTokens.scaleButtonFontWeight,
          )
        : textStyles.button;
    return _Dimmed(
      enabled: onPressed != null,
      child: RaisedSurface(
        onTap: onPressed,
        inertButton: true,
        expand: expand && !small,
        minHeight: small
            ? SizeTokens.smallButtonMinHeight
            : SizeTokens.primaryButtonMinHeight,
        borderRadius: BorderRadius.circular(
          small ? RadiusTokens.small : RadiusTokens.large,
        ),
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
        shadows: small ? ElevationTokens.primarySmall : ElevationTokens.primary,
        inset: small ? const [] : ElevationTokens.primaryInset,
        child: _ButtonLabel(
          label: label,
          icon: icon,
          style: style.copyWith(color: ColorTokens.primaryOnFill),
        ),
      ),
    );
  }
}

/// A white button for the second choice on a screen ("Change era or mode").
/// [small] is the compact version used inside rows (Clear cache).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  /// The 44 dp row button instead of the 54 dp full-size one.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final textStyles = context.text;
    return _Dimmed(
      enabled: onPressed != null,
      child: RaisedSurface(
        onTap: onPressed,
        inertButton: true,
        expand: expand && !small,
        minHeight: small
            ? SizeTokens.smallButtonMinHeight
            : SizeTokens.secondaryButtonMinHeight,
        borderRadius: BorderRadius.circular(
          small ? RadiusTokens.small : RadiusTokens.card,
        ),
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
        ),
        shadows: small ? edgeShadow(ColorTokens.surfaceCardEdge) : ElevationTokens.row,
        child: _ButtonLabel(
          label: label,
          style: small
              ? AppTextStyles.withWeight(
                  textStyles.bodySmall,
                  TypeTokens.scaleButtonFontWeight,
                )
              : textStyles.bodyLarge,
        ),
      ),
    );
  }
}

/// A square white button holding one icon: back, close, cancel download.
/// [semanticLabel] is required because there is no visible text.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _Dimmed(
      enabled: onPressed != null,
      child: RaisedSurface(
        onTap: onPressed,
        inertButton: true,
        semanticLabel: semanticLabel,
        minWidth: SpacingTokens.touchTargetMin,
        minHeight: SpacingTokens.touchTargetMin,
        borderRadius: BorderRadius.circular(RadiusTokens.small),
        color: ColorTokens.surfaceCard,
        shadows: ElevationTokens.iconButton,
        child: Icon(
          icon,
          size: SizeTokens.icon,
          color: ColorTokens.textPrimary,
        ),
      ),
    );
  }
}

/// The back arrow at the top left of a screen. [semanticLabel] is "Back" (on
/// the round screen it is "Leave game").
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.chevron_left_rounded,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.label, required this.style, this.icon});

  final String label;
  final TextStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: style, textAlign: TextAlign.center);
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: SizeTokens.icon, color: style.color),
        const SizedBox(width: SpacingTokens.n8),
        Flexible(child: text),
      ],
    );
  }
}

/// Dims a disabled control the way disabled answers are dimmed.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  // The "disabled button" announcement comes from the surface itself
  // (RaisedSurface.inertButton), so it stays on the same node as the label.
  @override
  Widget build(BuildContext context) => enabled
      ? child
      : Opacity(opacity: context.game.answerDimOpacity, child: child);
}
