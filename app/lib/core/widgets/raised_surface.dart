import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/token_types.dart';
import '../theme/tokens.dart';

/// A rounded surface with the design's "press edge": a solid shadow under the
/// surface, plus a soft one. Pressing moves it down by the edge height and
/// drops the edge, like a physical key. Every button, tile and card in the app
/// is one of these.
///
/// With no [onTap] it is just a decorated box. With [onTap] it is a button:
/// at least [SpacingTokens.touchTargetMin] square to hit, announced as a
/// button, and (unless the system asked for reduced motion) animated.
class RaisedSurface extends StatefulWidget {
  const RaisedSurface({
    super.key,
    required this.child,
    required this.shadows,
    this.inset = const [],
    this.gradient,
    this.color,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(RadiusTokens.large),
    ),
    this.padding = EdgeInsets.zero,
    this.minWidth = 0,
    this.minHeight = 0,
    this.expand = false,
    this.onTap,
    this.semanticLabel,
    this.selected,
    this.inertButton = false,
  });

  final Widget child;

  /// Outer shadows from [ElevationTokens]. A zero-blur shadow straight down is the press edge.
  final List<BoxShadow> shadows;

  /// Inset parts from [ElevationTokens] (`...Inset`), painted as a highlight along the top.
  final List<InsetShadow> inset;

  final Gradient? gradient;
  final Color? color;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double minWidth;
  final double minHeight;

  /// Fill the available width. Only valid where the width is bounded.
  final bool expand;

  /// Null makes the surface inert.
  final VoidCallback? onTap;

  /// Replaces the spoken text of the children. Use for tiles whose visible
  /// text is not the whole story ("Answer 2: Aster Aweke").
  final String? semanticLabel;

  /// For a choice among several (an era card): whether this one is chosen.
  /// Screen readers announce it; null means the surface is not a choice.
  final bool? selected;

  /// With no [onTap], still announce the surface as a button, a disabled one.
  /// For buttons and cards that are switched off rather than decorative.
  final bool inertButton;

  @override
  State<RaisedSurface> createState() => _RaisedSurfaceState();
}

class _RaisedSurfaceState extends State<RaisedSurface> {
  bool _pressed = false;

  @override
  void didUpdateWidget(RaisedSurface old) {
    super.didUpdateWidget(old);
    // InkWell does not report the end of a press when it leaves the tree
    // (a tile switched off while a finger is still on it), so the press is
    // dropped here. Otherwise the surface would come back looking pressed.
    if (widget.onTap == null) _pressed = false;
  }

  /// How far the surface drops when pressed: the height of its press edge.
  double get _edge {
    for (final s in widget.shadows) {
      if (s.blurRadius == 0 && s.offset.dx == 0) return s.offset.dy;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final pressed = _pressed && widget.onTap != null;
    final duration = context.reduceMotion ? Duration.zero : game.pressDuration;
    final restingShadows = widget.shadows;
    final pressedShadows = [
      for (final s in widget.shadows)
        if (s.blurRadius > 0) s,
    ];

    Widget surface = AnimatedContainer(
      duration: duration,
      curve: game.standardCurve,
      transform: Matrix4.translationValues(0, pressed ? _edge : 0, 0),
      constraints: BoxConstraints(
        minWidth: widget.expand ? double.infinity : widget.minWidth,
        minHeight: widget.minHeight,
      ),
      decoration: BoxDecoration(
        color: widget.gradient == null ? widget.color : null,
        gradient: widget.gradient,
        borderRadius: widget.borderRadius,
        boxShadow: pressed ? pressedShadows : restingShadows,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(padding: widget.padding, child: widget.child),
            for (final s in widget.inset) InsetGloss(shadow: s),
          ],
        ),
      ),
    );

    final onTap = widget.onTap;
    final label = widget.semanticLabel;
    if (onTap == null) {
      if (label == null && !widget.inertButton && widget.selected == null) {
        return surface;
      }
      // Not pressable, but still read out as one piece: "Answer 2: Aster
      // Aweke, Correct", or a switched-off button with its label.
      return Semantics(
        container: true,
        button: widget.inertButton ? true : null,
        enabled: widget.inertButton ? false : null,
        selected: widget.selected,
        label: label,
        child: ExcludeSemantics(excluding: label != null, child: surface),
      );
    }

    // A surface shorter than the minimum touch target still gets one: the
    // visible part is centred in a bigger hit area.
    final needsHitArea = widget.minHeight < SpacingTokens.touchTargetMin;
    if (needsHitArea) {
      surface = ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SpacingTokens.touchTargetMin,
          minWidth: SpacingTokens.touchTargetMin,
        ),
        child: Align(widthFactor: 1, heightFactor: 1, child: surface),
      );
    }

    // With a label, the children are silenced so the text is not read twice.
    // That also silences InkWell's own tap action, so it is given here instead.
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      selected: widget.selected,
      label: label,
      onTap: label == null ? null : onTap,
      child: ExcludeSemantics(
        excluding: label != null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onHighlightChanged: (down) => setState(() => _pressed = down),
            borderRadius: widget.borderRadius,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(transparentColor),
            child: surface,
          ),
        ),
      ),
    );
  }
}

/// The highlight that stands in for an inset shadow: a band along the top
/// edge, solid when the shadow has no blur and fading out when it has.
/// Place inside a [Stack] that clips to the surface's corners.
class InsetGloss extends StatelessWidget {
  const InsetGloss({super.key, required this.shadow});

  final InsetShadow shadow;

  @override
  Widget build(BuildContext context) {
    final fades = shadow.blur > 0;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: shadow.dy + shadow.blur / 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fades ? null : shadow.color,
            gradient: fades
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [shadow.color, shadow.color.withValues(alpha: 0)],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
