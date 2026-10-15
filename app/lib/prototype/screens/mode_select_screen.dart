import 'package:flutter/material.dart';

import '../../core/theme/app_text.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/app_localizations.dart';
import '../labels.dart';
import '../models.dart';

/// Mode select: how do you want to play? Three large cards (Intro, Middle,
/// Which Era?) and, for the first two, whether to guess the song or the artist.
/// Next opens era setup; the choice is remembered and becomes what Play starts.
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({
    super.key,
    required this.mode,
    required this.guess,
    required this.onModeChanged,
    required this.onGuessChanged,
    required this.onBack,
    required this.onNext,
  });

  final GameMode mode;
  final GuessTarget guess;
  final ValueChanged<GameMode> onModeChanged;
  final ValueChanged<GuessTarget> onGuessChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    return Scaffold(
      body: HeroScaffold(
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n14,
          SpacingTokens.n18,
          SpacingTokens.n26,
        ),
        bodyGap: SpacingTokens.n14,
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBackButton(onPressed: onBack, semanticLabel: l10n.navBack),
            const SizedBox(height: SpacingTokens.n14),
            Semantics(
              header: true,
              child: Text(l10n.modeTitle, style: text.display),
            ),
          ],
        ),
        body: [
          for (final m in GameMode.values)
            ModeCard(
              title: l10n.modeName(m),
              description: l10n.modeDescription(m),
              tag: l10n.modeTag(m),
              icon: modeIcon(m),
              iconColor: modeColor(m),
              selected: m == mode,
              onTap: () => onModeChanged(m),
            ),
          // Which Era? asks for the era, so there is nothing to choose here.
          if (mode != GameMode.era) ...[
            Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.n4),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.modeGuessLabel,
                  style: AppTextStyles.withWeight(
                    text.bodySmall,
                    FontWeight.w800,
                  ),
                ),
              ),
            ),
            SegmentedControl<GuessTarget>(
              semanticLabel: l10n.modeGuessLabel,
              selected: guess,
              onChanged: onGuessChanged,
              options: [
                for (final g in GuessTarget.values)
                  SegmentOption(value: g, label: l10n.guessLabel(g)),
              ],
            ),
          ],
        ],
        footer: PrimaryButton(label: l10n.commonNext, onPressed: onNext),
      ),
    );
  }
}
