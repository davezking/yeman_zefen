import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/token_types.dart';
import '../theme/tokens.dart';
import 'edge_shadow.dart';
import 'raised_surface.dart';

/// One choice in a [SegmentedControl].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    this.textLocale,
  });

  final T value;
  final String label;

  /// Draws this label in another language's font and line height. The language
  /// switch shows "አማርኛ" and "English" each in its own script, whatever the
  /// app language is.
  final Locale? textLocale;
}

/// Where a [SegmentedControl] sits, which decides how its selected item looks.
enum SegmentedStyle {
  /// On a cream or white body: a cream track, the selected item a white key.
  light,

  /// On the yellow hero: a translucent track, the selected item dark with a
  /// yellow label.
  onHero,

  /// On a full-yellow screen (the leaderboard): a translucent track like
  /// [onHero], but the selected item is a white key like [light].
  onYellow,
}

/// A row of two or three exclusive choices (Song / Artist, Easy / Medium /
/// Hard, አማርኛ / English). All items are as tall as the tallest, so a label
/// that wraps in Amharic or at text scale 1.3 never leaves one shorter.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.style = SegmentedStyle.light,
    this.compact = false,
    this.semanticLabel,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final SegmentedStyle style;

  /// Smaller labels, for three items that would otherwise wrap (clip length).
  final bool compact;

  /// Names the group for screen readers ("Guess the", "Clip length").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final onHero = style != SegmentedStyle.light;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: onHero
              ? ColorTokens.surfaceSegmentTrackOnHero
              : ColorTokens.surfaceSegmentTrack,
          borderRadius: BorderRadius.circular(RadiusTokens.card),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.n6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const SizedBox(width: SpacingTokens.n6),
                  Expanded(
                    child: _Segment(
                      option: options[i],
                      selected: options[i].value == selected,
                      onHero: onHero,
                      darkSelected: style == SegmentedStyle.onHero,
                      compact: compact,
                      onTap: () => onChanged(options[i].value),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onHero,
    required this.darkSelected,
    required this.compact,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool selected;
  final bool onHero;

  /// The selected item is dark with a yellow label (Settings), not a white key.
  final bool darkSelected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = option.textLocale == null
        ? context.text
        : AppTextStyles.forLocale(option.textLocale!, dense: true);
    final base = AppTextStyles.withWeight(
      compact ? styles.label : styles.body,
      FontWeight.w700,
    );
    final Color textColor;
    if (!selected) {
      textColor = ColorTokens.textSecondary;
    } else {
      textColor = darkSelected
          ? ColorTokens.primaryAccentOnDark
          : ColorTokens.textPrimary;
    }
    final Color? fill;
    final List<BoxShadow> shadows;
    if (!selected) {
      fill = null;
      shadows = const [];
    } else if (darkSelected) {
      fill = ColorTokens.surfaceDark;
      shadows = edgeShadow(ColorTokens.surfaceDarkEdge, dy: SpacingTokens.n4);
    } else {
      fill = ColorTokens.surfaceCard;
      shadows = edgeShadow(ColorTokens.surfaceCardEdge, dy: SpacingTokens.n4);
    }
    return RaisedSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: option.label,
      expand: true,
      minHeight: SpacingTokens.touchTargetMin,
      borderRadius: BorderRadius.circular(RadiusTokens.small),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.n2,
        vertical: SpacingTokens.n2,
      ),
      color: fill ?? transparentColor,
      shadows: shadows,
      child: Text(
        option.label,
        textAlign: TextAlign.center,
        style: base.copyWith(color: textColor),
      ),
    );
  }
}
