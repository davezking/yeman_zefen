import 'package:flutter/material.dart';

import '../../core/theme/app_text.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/app_localizations.dart';
import '../labels.dart';
import '../models.dart';

/// Era, genre and difficulty: the last step before a game starts.
///
/// Offline, an era with too few songs on the phone is disabled and says what
/// would fix it ("Needs internet or a downloaded pack"). A combination with too
/// few songs shows a message and switches Start off.
class SetupScreen extends StatelessWidget {
  const SetupScreen({
    super.key,
    required this.mode,
    required this.generationId,
    required this.genre,
    required this.difficulty,
    required this.onEra,
    required this.onGenre,
    required this.onDifficulty,
    required this.onBack,
    required this.onStart,
    this.disabledEras = const {},
    this.tooFewSongs = false,
    this.totalRounds = 10,
  });

  final GameMode mode;
  final int generationId;
  final Genre genre;
  final Difficulty difficulty;
  final ValueChanged<int> onEra;
  final ValueChanged<Genre> onGenre;
  final ValueChanged<Difficulty> onDifficulty;
  final VoidCallback onBack;
  final VoidCallback onStart;

  /// Eras the phone has too few songs for (offline only). They cannot be picked.
  final Set<int> disabledEras;

  /// The chosen era and genre together have too few songs.
  final bool tooFewSongs;
  final int totalRounds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final heading = AppTextStyles.withWeight(text.bodySmall, FontWeight.w800);

    return Scaffold(
      body: HeroScaffold(
        denseText: true,
        heroRadius: RadiusTokens.heroDense,
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n12,
          SpacingTokens.n18,
          SpacingTokens.n20,
        ),
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n24,
          SpacingTokens.n18,
          SpacingTokens.n20,
        ),
        bodyGap: SpacingTokens.n10,
        hero: Row(
          children: [
            AppBackButton(onPressed: onBack, semanticLabel: l10n.navBack),
            const SizedBox(width: SpacingTokens.n12),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l10n.modeName(mode), style: text.titleSmall),
              ),
            ),
          ],
        ),
        body: [
          Semantics(header: true, child: Text(l10n.eraTitle, style: heading)),
          EqualHeightGrid(
            spacing: SpacingTokens.n10,
            children: [
              for (final id in EraId.ordered)
                EraCard(
                  label: l10n.eraLabel(id),
                  subtitle: disabledEras.contains(id)
                      ? l10n.eraOfflineUnavailable
                      : l10n.eraRange(id),
                  generationId: id,
                  selected: id == generationId,
                  enabled: !disabledEras.contains(id),
                  onTap: () => onEra(id),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.n4),
            child: Semantics(
              header: true,
              child: Text(l10n.genreTitle, style: heading),
            ),
          ),
          Wrap(
            spacing: SpacingTokens.n8,
            runSpacing: SpacingTokens.n8,
            children: [
              for (final g in Genre.values)
                AppChoiceChip(
                  label: l10n.genreLabel(g),
                  selected: g == genre,
                  onTap: () => onGenre(g),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.n4),
            child: Semantics(
              header: true,
              child: Text(l10n.difficultyTitle, style: heading),
            ),
          ),
          SegmentedControl<Difficulty>(
            compact: true,
            semanticLabel: l10n.difficultyTitle,
            selected: difficulty,
            onChanged: onDifficulty,
            options: [
              for (final d in Difficulty.values)
                SegmentOption(value: d, label: l10n.difficultyLabel(d)),
            ],
          ),
          if (tooFewSongs)
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: SizeTokens.icon,
                    color: ColorTokens.textError,
                  ),
                  const SizedBox(width: SpacingTokens.n8),
                  Expanded(
                    child: Text(
                      l10n.setupTooFewSongs,
                      style: text.label.copyWith(color: ColorTokens.textError),
                    ),
                  ),
                ],
              ),
            ),
        ],
        footer: PrimaryButton(
          label: l10n.setupStart(totalRounds),
          // Nothing to start with too few songs, or with an era the phone cannot play.
          onPressed: tooFewSongs || disabledEras.contains(generationId)
              ? null
              : onStart,
        ),
      ),
    );
  }
}
