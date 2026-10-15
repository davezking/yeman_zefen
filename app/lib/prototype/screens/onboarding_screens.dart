import 'package:flutter/material.dart';

import '../../core/theme/app_text.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/app_localizations.dart';

/// App start: the wordmark on the yellow hero and "Tuning up…".
class AppStartScreen extends StatelessWidget {
  const AppStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: _YellowFill(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LogoTiles(
              semanticLabel: l10n.appName,
              tileSize: SizeTokens.logoTileLarge,
            ),
            const SizedBox(height: SpacingTokens.n20),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.loadingApp,
                style: AppTextStyles.withWeight(
                  context.text.bodyLarge,
                  FontWeight.w600,
                ).copyWith(color: ColorTokens.textOnHero),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First launch, step 1: the language. The prompt is in both scripts, since
/// no language has been chosen yet, and each option is in its own script. The
/// app switches language as soon as one is tapped.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({
    super.key,
    required this.languageCode,
    required this.onLanguage,
    required this.onNext,
  });

  /// Preselected from the phone's locale: `am` for Amharic, `en` otherwise.
  final String languageCode;
  final ValueChanged<String> onLanguage;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final am = lookupAppLocalizations(const Locale('am'));
    final en = lookupAppLocalizations(const Locale('en'));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _HeroBlock(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LogoTiles(
                          semanticLabel: l10n.appName,
                          tileSize: SizeTokens.logoTileLarge,
                        ),
                        const SizedBox(height: SpacingTokens.n20),
                        Text(l10n.appName, style: text.display),
                        Text(
                          l10n.appTagline,
                          style: AppTextStyles.withWeight(
                            text.bodyLarge,
                            FontWeight.w600,
                          ).copyWith(color: ColorTokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.n20,
                    SpacingTokens.n26,
                    SpacingTokens.n20,
                    SpacingTokens.n28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          '${am.onboardLangTitle} · ${en.onboardLangTitle}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.withWeight(
                            text.bodyLarge,
                            FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.n14),
                      _LanguageOption(
                        label: am.onboardLangAmharic,
                        locale: const Locale('am'),
                        selected: languageCode == 'am',
                        onTap: () => onLanguage('am'),
                      ),
                      const SizedBox(height: SpacingTokens.n14),
                      _LanguageOption(
                        label: en.onboardLangEnglish,
                        locale: const Locale('en'),
                        selected: languageCode == 'en',
                        onTap: () => onLanguage('en'),
                      ),
                      const SizedBox(height: SpacingTokens.n14),
                      Text(
                        l10n.onboardLangLater,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.withWeight(
                          text.label,
                          FontWeight.w400,
                        ).copyWith(color: ColorTokens.textSecondary),
                      ),
                      const SizedBox(height: SpacingTokens.n14),
                      PrimaryButton(label: l10n.commonNext, onPressed: onNext),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.locale,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Locale locale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? ColorTokens.textOnDark : ColorTokens.textPrimary;
    final style = AppTextStyles.withWeight(
      AppTextStyles.forLocale(locale).titleSmall,
      FontWeight.w700,
    ).copyWith(color: ink);
    return RaisedSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      expand: true,
      minHeight: SizeTokens.listRowMinHeight,
      borderRadius: BorderRadius.circular(RadiusTokens.large),
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.n20),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: selected
            ? const [ColorTokens.paletteSlate, ColorTokens.surfaceDark]
            : const [ColorTokens.surfaceCard, ColorTokens.surfaceCardEnd],
      ),
      shadows: selected ? ElevationTokens.dark : ElevationTokens.answer,
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          // The radio: a ring with a yellow dot when chosen.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: SpacingTokens.n2),
            ),
            child: SizedBox.square(
              dimension: SizeTokens.iconLarge,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? ColorTokens.primaryAccentOnDark : null,
                  ),
                  child: const SizedBox.square(dimension: SpacingTokens.n12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First launch, step 2: what the game is, then straight into round 1 from the
/// songs that come with the app. No sign-up, no download, no consent first.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.sampleAnswers,
    required this.onStart,
  });

  /// Two names shown as answer tiles in the hero, as a preview of play.
  final List<String> sampleAnswers;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    return Scaffold(
      body: HeroScaffold(
        heroPadding: EdgeInsets.zero,
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n24,
          SpacingTokens.n30,
          SpacingTokens.n24,
          SpacingTokens.n24,
        ),
        hero: ExcludeSemantics(
          child: SizedBox(
            height: SizeTokens.welcomeHero,
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.n24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PlayingIndicator(playing: false),
                  const SizedBox(height: SpacingTokens.n20),
                  EqualHeightGrid(
                    spacing: SpacingTokens.n10,
                    children: [
                      for (final name in sampleAnswers) AnswerTile(text: name),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: [
          Semantics(
            header: true,
            child: Text(l10n.onboardWelcomeTitle, style: text.display),
          ),
          Text(
            l10n.onboardWelcomeBody,
            style: AppTextStyles.withWeight(
              text.bodyLarge,
              FontWeight.w400,
            ).copyWith(color: ColorTokens.textSecondary),
          ),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PageDots(count: 2, current: 1),
            const SizedBox(height: SpacingTokens.n18),
            PrimaryButton(label: l10n.onboardWelcomeStart, onPressed: onStart),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: SpacingTokens.n8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: i == current
                    ? ColorTokens.surfaceDark
                    : ColorTokens.paletteSand,
                borderRadius: BorderRadius.circular(RadiusTokens.progress),
              ),
              child: SizedBox(
                width: i == current
                    ? SizeTokens.pageDotActiveWidth
                    : SizeTokens.pageDotWidth,
                height: SizeTokens.pageDotWidth,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The yellow hero block with its curved bottom, filling what it is given.
class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: RadiusTokens.hero,
        boxShadow: ElevationTokens.hero,
        gradient: _heroGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.n24),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The whole screen in the hero's yellow (app start).
class _YellowFill extends StatelessWidget {
  const _YellowFill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _heroGradient),
      child: SizedBox.expand(
        child: SafeArea(child: Center(child: child)),
      ),
    );
  }
}

const _heroGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [ColorTokens.heroTop, ColorTokens.heroMiddle, ColorTokens.heroBottom],
  stops: [0, 0.55, 1],
);
