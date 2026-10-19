import 'package:flutter/material.dart';

import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'list_row.dart';
import 'raised_surface.dart';

/// Where a song pack is in its life on this phone.
enum PackStatus {
  /// Available, not on the phone. Shows [PackCard.actionLabel] ("Download").
  notInstalled,

  /// Downloading: a progress bar ([PackCard.progress]) and a cancel button.
  downloading,

  /// Downloaded, checking the files.
  verifying,

  /// On the phone. Shows [PackCard.statusLabel] ("Downloaded") with a check.
  installed,

  /// On the phone, a newer version exists. Shows [PackCard.actionLabel] ("Update · 12 MB").
  updateAvailable,

  /// The download failed: an inline error with a retry button.
  failed,

  /// The songs that ship inside the app. Always there; nothing to do.
  builtIn,
}

/// A song pack in Settings › Offline play. Plain data in, callbacks out: the
/// app's pack service decides the status.
class PackCard extends StatelessWidget {
  const PackCard({
    super.key,
    required this.name,
    required this.meta,
    required this.status,
    this.generationId = 0,
    this.progress,
    this.statusLabel,
    this.actionLabel,
    this.cancelLabel,
    this.errorMessage,
    this.retryLabel,
    this.onAction,
    this.onCancel,
    this.onRetry,
  });

  final String name;

  /// The second line: "40 songs · 12 MB" (with "42% · " in front while downloading).
  final String meta;
  final PackStatus status;

  /// Picks the color of the pack's art tile. Ignored for [PackStatus.builtIn], which is brand yellow.
  final int generationId;

  /// 0 to 1 while [PackStatus.downloading]; null shows an unmeasured bar.
  final double? progress;

  /// "Downloaded", "Always there", "Checking files…", "Update available".
  final String? statusLabel;
  final String? actionLabel;
  final String? cancelLabel;
  final String? errorMessage;
  final String? retryLabel;
  final VoidCallback? onAction;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    final text = context.text;
    final art = status == PackStatus.builtIn
        ? ColorTokens.paletteSun400
        : game.eraColor(generationId);
    final failed = status == PackStatus.failed;

    // A long button label (an update's size, a large text size) gets at most
    // 40% of the screen and wraps, so the pack's name keeps its room.
    final trailingMaxWidth = MediaQuery.sizeOf(context).width * 0.4;
    final heading = Row(
      children: [
        IconTile(color: art),
        const SizedBox(width: SpacingTokens.n12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: text.bodySmall),
              Text(
                meta,
                style: text.caption.copyWith(color: ColorTokens.textSecondary),
              ),
              if (status == PackStatus.downloading ||
                  status == PackStatus.verifying) ...[
                const SizedBox(height: SpacingTokens.n6),
                _Progress(
                  value: status == PackStatus.verifying ? null : progress,
                ),
              ],
              if (statusLabel != null &&
                  (status == PackStatus.verifying ||
                      status == PackStatus.updateAvailable))
                Text(
                  statusLabel!,
                  style: text.caption.copyWith(color: ColorTokens.correctText),
                ),
            ],
          ),
        ),
        const SizedBox(width: SpacingTokens.n8),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: trailingMaxWidth),
          child: _Trailing(card: this),
        ),
      ],
    );

    if (failed) {
      return RaisedSurface(
        expand: true,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        padding: const EdgeInsets.all(SpacingTokens.n12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ColorTokens.surfaceErrorCard,
            ColorTokens.surfaceErrorCardEnd,
          ],
        ),
        shadows: ElevationTokens.errorCard,
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(color: art),
                  const SizedBox(width: SpacingTokens.n12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: text.bodySmall),
                        Text(
                          meta,
                          style: text.caption.copyWith(
                            color: ColorTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.n10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: SizeTokens.icon,
                    color: ColorTokens.textError,
                  ),
                  const SizedBox(width: SpacingTokens.n8),
                  Expanded(
                    child: Text(
                      errorMessage ?? '',
                      style: text.label.copyWith(color: ColorTokens.textError),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.n10),
              if (retryLabel != null)
                PrimaryButton(
                  label: retryLabel!,
                  small: true,
                  expand: false,
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      );
    }

    return RaisedSurface(
      expand: true,
      minHeight: SizeTokens.listRowMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      padding: const EdgeInsets.symmetric(
        horizontal: SpacingTokens.n12,
        vertical: SpacingTokens.n8,
      ),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: ElevationTokens.card,
      child: heading,
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing({required this.card});

  final PackCard card;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    switch (card.status) {
      case PackStatus.notInstalled:
      case PackStatus.updateAvailable:
        return PrimaryButton(
          label: card.actionLabel ?? '',
          small: true,
          expand: false,
          onPressed: card.onAction,
        );
      case PackStatus.downloading:
        return AppIconButton(
          icon: Icons.close_rounded,
          onPressed: card.onCancel,
          semanticLabel: card.cancelLabel ?? '',
        );
      case PackStatus.verifying:
        return const SizedBox.shrink();
      case PackStatus.installed:
      case PackStatus.builtIn:
        final check = card.status == PackStatus.installed;
        final style = AppTextStyles.withWeight(
          text.caption,
          FontWeight.w700,
        ).copyWith(color: ColorTokens.correctText);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (check) ...[
              const Icon(
                Icons.check_rounded,
                size: SizeTokens.iconSmall,
                color: ColorTokens.correctText,
              ),
              const SizedBox(width: SpacingTokens.n4),
            ],
            Flexible(child: Text(card.statusLabel ?? '', style: style)),
          ],
        );
      case PackStatus.failed:
        return const SizedBox.shrink();
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final game = context.game;
    return Semantics(
      value: value == null ? null : '${(value! * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusTokens.progress),
        child: SizedBox(
          height: SizeTokens.packProgressHeight,
          child: value == null
              ? LinearProgressIndicator(
                  minHeight: SizeTokens.packProgressHeight,
                  backgroundColor: ColorTokens.surfaceDivider,
                  color: game.timerFillStart,
                )
              : ColoredBox(
                  color: ColorTokens.surfaceDivider,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: value!.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [game.timerFillStart, game.timerFillEnd],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
