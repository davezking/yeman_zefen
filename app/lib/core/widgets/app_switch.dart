import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';

/// The on/off toggle (Settings, Offline play): a teal track with a white knob.
/// It is announced as a switch with [semanticLabel], and has a full-size touch
/// target around the small track. A null [onChanged] switches it off (dims it).
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.semanticHint,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  /// Read after the label: the help text under the title, when there is one.
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final duration = context.reduceMotion ? Duration.zero : game.fadeDuration;
    final enabled = onChanged != null;
    final track = AnimatedContainer(
      duration: duration,
      curve: game.standardCurve,
      width: SizeTokens.toggleWidth,
      height: SizeTokens.toggleHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SizeTokens.toggleHeight),
        color: value ? null : ColorTokens.surfaceCardEdge,
        gradient: value
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ColorTokens.paletteTeal500, ColorTokens.toggleOn],
              )
            : null,
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: game.standardCurve,
        alignment: value
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.all(SizeTokens.toggleKnobInset),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: ColorTokens.toggleKnob,
            ),
            child: SizedBox.square(dimension: SizeTokens.toggleKnob),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      enabled: enabled,
      toggled: value,
      label: semanticLabel,
      hint: semanticHint,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: SpacingTokens.touchTargetMin,
              minHeight: SpacingTokens.touchTargetMin,
            ),
            child: Center(
              child: enabled
                  ? track
                  : Opacity(opacity: game.answerDimOpacity, child: track),
            ),
          ),
        ),
      ),
    );
  }
}
