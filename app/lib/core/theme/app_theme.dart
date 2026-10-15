import 'package:flutter/material.dart';

import 'app_text.dart';
import 'game_tokens.dart';
import 'tokens.dart';

/// The app theme for [locale]. Only the text differs between languages (see
/// [AppTextStyles]); there is one light theme, since no dark theme was designed.
///
/// Stock Material widgets pick up the design from here. The designed
/// components in `core/widgets/` read [GameTokens] and [AppTextStyles] from
/// the theme too.
ThemeData buildAppTheme(Locale locale, {bool denseText = false}) {
  final text = AppTextStyles.forLocale(locale, dense: denseText);
  final game = GameTokens.light;

  const scheme = ColorScheme.light(
    primary: ColorTokens.primaryFill,
    onPrimary: ColorTokens.primaryOnFill,
    primaryContainer: ColorTokens.paletteSun50,
    onPrimaryContainer: ColorTokens.textPrimary,
    secondary: ColorTokens.paletteSage,
    onSecondary: ColorTokens.textPrimary,
    tertiary: ColorTokens.correctFill,
    onTertiary: ColorTokens.textOnAnswerState,
    error: ColorTokens.wrongFill,
    onError: ColorTokens.textOnAnswerState,
    surface: ColorTokens.backgroundScreen,
    onSurface: ColorTokens.textPrimary,
    onSurfaceVariant: ColorTokens.textSecondary,
    surfaceContainerLowest: ColorTokens.surfaceCard,
    surfaceContainerLow: ColorTokens.surfaceCardEnd,
    surfaceContainer: ColorTokens.surfaceCardEnd,
    surfaceContainerHigh: ColorTokens.surfaceCardEdge,
    surfaceContainerHighest: ColorTokens.surfaceCardEdge,
    outline: ColorTokens.textSecondary,
    outlineVariant: ColorTokens.surfaceDivider,
    shadow: ColorTokens.paletteInk,
    scrim: ColorTokens.paletteInk,
    inverseSurface: ColorTokens.surfaceDark,
    onInverseSurface: ColorTokens.textOnDark,
    inversePrimary: ColorTokens.primaryAccentOnDark,
  );

  final cornerLarge = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(RadiusTokens.large),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ColorTokens.backgroundScreen,
    fontFamily: text.body.fontFamily,
    fontFamilyFallback: text.body.fontFamilyFallback,
    textTheme: text.toTextTheme(),
    extensions: [game, text],
    appBarTheme: AppBarTheme(
      backgroundColor: ColorTokens.heroMiddle,
      foregroundColor: ColorTokens.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleSmall,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ColorTokens.primaryFill,
        foregroundColor: ColorTokens.primaryOnFill,
        minimumSize: const Size(
          SpacingTokens.touchTargetMin,
          SizeTokens.primaryButtonMinHeight,
        ),
        shape: cornerLarge,
        textStyle: text.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: ColorTokens.surfaceCard,
        foregroundColor: ColorTokens.textPrimary,
        side: BorderSide.none,
        minimumSize: const Size(
          SpacingTokens.touchTargetMin,
          SizeTokens.secondaryButtonMinHeight,
        ),
        shape: cornerLarge,
        textStyle: text.bodyLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ColorTokens.textPrimary,
        minimumSize: const Size(
          SpacingTokens.touchTargetMin,
          SpacingTokens.touchTargetMin,
        ),
        textStyle: AppTextStyles.withWeight(text.body, FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ColorTokens.surfaceCard,
      shape: cornerLarge,
      titleTextStyle: text.titleSmall,
      contentTextStyle: text.body.copyWith(color: ColorTokens.textSecondary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ColorTokens.paletteSun50,
      modalBarrierColor: ColorTokens.backgroundScrim,
      shape: RoundedRectangleBorder(borderRadius: RadiusTokens.sheet),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(ColorTokens.toggleKnob),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ColorTokens.toggleOn
            : ColorTokens.surfaceCardEdge,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(0.0),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: game.timerFillStart,
      linearTrackColor: game.timerTrack,
    ),
    dividerTheme: const DividerThemeData(
      color: ColorTokens.surfaceDivider,
      thickness: SizeTokens.hairline,
      space: SizeTokens.hairline,
    ),
  );
}
