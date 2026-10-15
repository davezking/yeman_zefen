import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/token_types.dart';
import '../theme/tokens.dart';
import 'app_switch.dart';
import 'raised_surface.dart';

/// A white card holding [SettingsRow]s separated by hairlines (Settings and the
/// two toggles on Offline play).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RaisedSurface(
      expand: true,
      borderRadius: BorderRadius.circular(RadiusTokens.large),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: ElevationTokens.row,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One line in a [SettingsGroup]: a title, an optional second line, and either
/// a switch, a chevron (it opens something), or a small widget of your own.
class SettingsRow extends StatelessWidget {
  /// A row that opens another screen or a sheet.
  const SettingsRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.badge = false,
    this.trailing,
  }) : value = null,
       onChanged = null;

  /// A row with an on/off switch. Tapping anywhere on it flips the switch.
  const SettingsRow.toggle({
    super.key,
    required this.title,
    required bool this.value,
    required this.onChanged,
    this.subtitle,
  }) : onTap = null,
       subtitleColor = null,
       titleColor = null,
       badge = false,
       trailing = null;

  final String title;
  final String? subtitle;

  /// The second line's color when it is not the usual muted one.
  final Color? subtitleColor;

  /// The title's color when it is not ink (Delete account is in the error red).
  final Color? titleColor;

  /// A yellow dot before the chevron: something here needs a look.
  final bool badge;

  /// Replaces the chevron (a small "Sign in" button).
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final titleStyle = AppTextStyles.withWeight(
      text.bodySmall,
      FontWeight.w600,
    );
    final titles = Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.n6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: titleColor == null
                ? titleStyle
                : titleStyle.copyWith(color: titleColor),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: text.caption.copyWith(
                color: subtitleColor ?? ColorTokens.textSecondary,
              ),
            ),
        ],
      ),
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SpacingTokens.touchTargetMin,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n16),
        child: Row(
          children: [
            // On a switch row the switch speaks the title and the help text.
            Expanded(
              child: value == null ? titles : ExcludeSemantics(child: titles),
            ),
            const SizedBox(width: SpacingTokens.n12),
            if (value != null)
              AppSwitch(
                value: value!,
                onChanged: onChanged,
                semanticLabel: title,
                semanticHint: subtitle,
              )
            else if (trailing != null)
              trailing!
            else ...[
              if (badge) ...[
                const _Dot(),
                const SizedBox(width: SpacingTokens.n8),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                size: SizeTokens.iconLarge,
                color: ColorTokens.textPrimary,
              ),
            ],
          ],
        ),
      ),
    );

    if (value != null) {
      // The switch is the one thing announced; the row is a bigger place to tap.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value!),
        child: row,
      );
    }
    if (onTap == null) return row;
    return Semantics(
      container: true,
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(transparentColor),
          child: row,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColorTokens.paletteCoral,
      ),
      child: SizedBox.square(dimension: SpacingTokens.n10),
    );
  }
}
