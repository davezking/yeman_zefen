import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The page layout most screens share: a yellow [hero] with a curved bottom, and
/// a scrolling body that starts [SpacingTokens.heroOverlap] under the curve so
/// the curve sits on a cream band that fades to white. An optional [bottomBar]
/// (Home and Settings) is pinned below.
///
/// [body] is laid out top to bottom with [bodyGap] between items. [footer]
/// (the screen's primary button) sits at the bottom of the body when the
/// content is short and scrolls with it when the content is long, so nothing is
/// clipped at text scale 1.3 or in Amharic.
///
/// [denseText] uses the tighter Fidel line height (era setup, Offline play,
/// Settings: screens with many rows).
class HeroScaffold extends StatelessWidget {
  const HeroScaffold({
    super.key,
    required this.hero,
    required this.body,
    this.footer,
    this.bottomBar,
    this.heroPadding = const EdgeInsets.fromLTRB(
      SpacingTokens.n18,
      SpacingTokens.n14,
      SpacingTokens.n18,
      SpacingTokens.n26,
    ),
    this.heroRadius = RadiusTokens.hero,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      SpacingTokens.n18,
      SpacingTokens.n28,
      SpacingTokens.n18,
      SpacingTokens.n22,
    ),
    this.bodyGap = SpacingTokens.n12,
    this.denseText = false,
  });

  /// The content of the yellow area. Its height is whatever the content needs.
  final Widget hero;
  final List<Widget> body;

  /// Pinned to the bottom of the body when there is room, scrolls otherwise.
  final Widget? footer;
  final Widget? bottomBar;
  final EdgeInsets heroPadding;
  final BorderRadius heroRadius;
  final EdgeInsets bodyPadding;
  final double bodyGap;
  final bool denseText;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final heroBox = _Hero(
      padding: heroPadding.copyWith(top: heroPadding.top + safeTop),
      radius: heroRadius,
      child: hero,
    );
    final bodyBox = _Body(
      padding: bodyPadding,
      gap: bodyGap,
      footer: footer,
      reserveBottomSafeArea: bottomBar == null,
      children: body,
    );

    Widget page = Column(
      children: [
        Expanded(
          child: CustomMultiChildLayout(
            delegate: _HeroOverlapLayout(),
            // The body is painted first so the hero's curve and shadow lie over it.
            children: [
              LayoutId(id: _Slot.body, child: bodyBox),
              LayoutId(id: _Slot.hero, child: heroBox),
            ],
          ),
        ),
        ?bottomBar,
      ],
    );

    if (denseText) {
      final theme = Theme.of(context);
      final locale = Localizations.localeOf(context);
      page = Theme(
        data: theme.copyWith(
          extensions: [
            context.game,
            AppTextStyles.forLocale(locale, dense: true),
          ],
        ),
        child: page,
      );
    }
    return page;
  }
}

enum _Slot { hero, body }

/// Lays the body out [SpacingTokens.heroOverlap] under the hero's bottom edge.
class _HeroOverlapLayout extends MultiChildLayoutDelegate {
  _HeroOverlapLayout();

  @override
  void performLayout(Size size) {
    final hero = layoutChild(
      _Slot.hero,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    positionChild(_Slot.hero, Offset.zero);
    final bodyTop = (hero.height + SpacingTokens.heroOverlap).clamp(
      0.0,
      size.height,
    );
    layoutChild(
      _Slot.body,
      BoxConstraints.tight(Size(size.width, size.height - bodyTop)),
    );
    positionChild(_Slot.body, Offset(0, bodyTop));
  }

  @override
  bool shouldRelayout(_HeroOverlapLayout oldDelegate) => false;
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.padding,
    required this.radius,
    required this.child,
  });

  final EdgeInsets padding;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ElevationTokens.hero,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ColorTokens.heroTop,
            ColorTokens.heroMiddle,
            ColorTokens.heroBottom,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: DecoratedBox(
        // The white glow behind the focal element.
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: RadialGradient(
            center: const Alignment(0, 0.24),
            radius: 0.75,
            // Fades to the same white at zero opacity, not to transparent black.
            colors: [
              ColorTokens.heroGlow,
              ColorTokens.heroGlow.withValues(alpha: 0),
            ],
          ),
        ),
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.padding,
    required this.gap,
    required this.footer,
    required this.reserveBottomSafeArea,
    required this.children,
  });

  final EdgeInsets padding;
  final double gap;
  final Widget? footer;
  final bool reserveBottomSafeArea;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottomInset = reserveBottomSafeArea
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    return ColoredBox(
      color: ColorTokens.backgroundScreen,
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: SizeTokens.heroFadeHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ColorTokens.backgroundHeroFade,
                    ColorTokens.backgroundScreen,
                  ],
                ),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                // The padding is inside, so it counts toward the height the
                // body fills; around the sliver it would push the footer down.
                child: Padding(
                  padding: padding.copyWith(
                    bottom: padding.bottom + bottomInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        children[i],
                      ],
                      if (footer != null) ...[
                        SizedBox(height: gap),
                        const Spacer(),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
