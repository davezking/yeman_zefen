import 'package:flutter/material.dart';

import '../theme/token_types.dart';
import '../theme/tokens.dart';

/// The content frame of a bottom sheet: cream fading to white, rounded top
/// corners and the grabber. Use it directly to lay a sheet out inline, or
/// through [showAppBottomSheet] to show one over the screen.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child, this.semanticLabel});

  final Widget child;

  /// Names the sheet for screen readers (its title).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: semanticLabel != null,
      scopesRoute: semanticLabel != null,
      namesRoute: semanticLabel != null,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: RadiusTokens.sheet,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ColorTokens.paletteSun50, ColorTokens.backgroundScreen],
            stops: [0, 0.4],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SpacingTokens.n20,
              SpacingTokens.n12,
              SpacingTokens.n20,
              SpacingTokens.n20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ColorTokens.paletteSand,
                        borderRadius: BorderRadius.all(
                          Radius.circular(RadiusTokens.progress),
                        ),
                      ),
                      child: SizedBox(
                        width: SizeTokens.grabberWidth,
                        height: SizeTokens.grabberHeight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.n12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [builder]'s content in an [AppSheet] over a dimmed screen. Resolves
/// to whatever the sheet pops with, or null if it was dismissed.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? semanticLabel,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: transparentColor,
    barrierColor: ColorTokens.backgroundScrim,
    elevation: 0,
    builder: (sheetContext) =>
        AppSheet(semanticLabel: semanticLabel, child: builder(sheetContext)),
  );
}
