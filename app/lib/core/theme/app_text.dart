import 'package:flutter/material.dart';

import 'tokens.dart';

/// The design's type scale (tokens.json `typography.scale`) as ready-made
/// [TextStyle]s for one language.
///
/// Amharic puts Noto Sans Ethiopic first, so Fidel gets its own, taller line
/// height; every other language puts Poppins first. Either way the other font
/// is the fallback, so Latin words inside Amharic text (and the other way
/// round) still render. Scores and counters are always Poppins.
///
/// Build styles from here instead of `TextStyle(fontSize: ...)`. If you change
/// a weight with `copyWith`, use [withWeight] so the Fidel font follows.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles._({
    required this.caption,
    required this.label,
    required this.bodySmall,
    required this.body,
    required this.bodyLarge,
    required this.button,
    required this.titleSmall,
    required this.title,
    required this.display,
    required this.score,
  });

  /// Styles for [locale]. [dense] uses the tighter Fidel line height meant for
  /// screens with many rows (era setup, offline play, settings).
  factory AppTextStyles.forLocale(Locale locale, {bool dense = false}) {
    final amharic = locale.languageCode == 'am';
    final primary = amharic
        ? TypeTokens.familyEthiopic
        : TypeTokens.familyLatin;
    final fallback = amharic
        ? TypeTokens.familyLatin
        : TypeTokens.familyEthiopic;
    final body = amharic
        ? (dense
              ? TypeTokens.lineHeightEthiopicDense
              : TypeTokens.lineHeightEthiopic)
        : TypeTokens.lineHeightLatin;

    TextStyle make(
      double size,
      FontWeight weight, {
      double? height,
      bool latinOnly = false,
    }) {
      return TextStyle(
        fontFamily: latinOnly ? TypeTokens.familyLatin : primary,
        fontFamilyFallback: [latinOnly ? TypeTokens.familyEthiopic : fallback],
        fontSize: size,
        fontWeight: weight,
        // Noto Sans Ethiopic is one variable font, so its weight has to be
        // asked for explicitly. Poppins is static and ignores this.
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
        height: height ?? body,
        color: ColorTokens.textPrimary,
      );
    }

    return AppTextStyles._(
      caption: make(
        TypeTokens.scaleCaptionFontSize,
        TypeTokens.scaleCaptionFontWeight,
      ),
      label: make(
        TypeTokens.scaleLabelFontSize,
        TypeTokens.scaleLabelFontWeight,
      ),
      bodySmall: make(
        TypeTokens.scaleBodySmallFontSize,
        TypeTokens.scaleBodySmallFontWeight,
      ),
      body: make(TypeTokens.scaleBodyFontSize, TypeTokens.scaleBodyFontWeight),
      bodyLarge: make(
        TypeTokens.scaleBodyLargeFontSize,
        TypeTokens.scaleBodyLargeFontWeight,
      ),
      button: make(
        TypeTokens.scaleButtonFontSize,
        TypeTokens.scaleButtonFontWeight,
      ),
      titleSmall: make(
        TypeTokens.scaleTitleSmallFontSize,
        TypeTokens.scaleTitleSmallFontWeight,
        height: TypeTokens.lineHeightHeading,
      ),
      title: make(
        TypeTokens.scaleTitleFontSize,
        TypeTokens.scaleTitleFontWeight,
        height: TypeTokens.lineHeightHeading,
      ),
      display: make(
        TypeTokens.scaleDisplayFontSize,
        TypeTokens.scaleDisplayFontWeight,
        height: TypeTokens.lineHeightHeading,
      ),
      score: make(
        TypeTokens.scaleScoreFontSize,
        TypeTokens.scaleScoreFontWeight,
        height: TypeTokens.lineHeightScore,
        latinOnly: true,
      ),
    );
  }

  /// Meta lines, stat labels.
  final TextStyle caption;

  /// Chips, section headers, answer marks.
  final TextStyle label;

  /// List row titles.
  final TextStyle bodySmall;

  /// Paragraphs.
  final TextStyle body;

  /// Answer tiles.
  final TextStyle bodyLarge;

  /// Primary buttons.
  final TextStyle button;

  /// Screen titles, the round question.
  final TextStyle titleSmall;

  /// Feedback heading, message screens, the Home greeting.
  final TextStyle title;

  /// Welcome and onboarding.
  final TextStyle display;

  /// The big total on Results. Always Poppins.
  final TextStyle score;

  /// [style] with another weight, applied to the variable Fidel font too.
  static TextStyle withWeight(TextStyle style, FontWeight weight) =>
      style.copyWith(
        fontWeight: weight,
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
      );

  /// [style] in Poppins whatever the language, for numbers inside Amharic text.
  static TextStyle latin(TextStyle style) => style.copyWith(
    fontFamily: TypeTokens.familyLatin,
    fontFamilyFallback: [TypeTokens.familyEthiopic],
  );

  /// The Material roles, mapped from the scale so stock widgets (AppBar,
  /// dialogs, buttons) match the design without extra styling.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: score,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: display,
    headlineMedium: title,
    headlineSmall: title,
    titleLarge: titleSmall,
    titleMedium: bodyLarge,
    titleSmall: bodySmall,
    bodyLarge: bodyLarge,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: label,
    labelSmall: caption,
  );

  @override
  AppTextStyles copyWith({
    TextStyle? caption,
    TextStyle? label,
    TextStyle? bodySmall,
    TextStyle? body,
    TextStyle? bodyLarge,
    TextStyle? button,
    TextStyle? titleSmall,
    TextStyle? title,
    TextStyle? display,
    TextStyle? score,
  }) => AppTextStyles._(
    caption: caption ?? this.caption,
    label: label ?? this.label,
    bodySmall: bodySmall ?? this.bodySmall,
    body: body ?? this.body,
    bodyLarge: bodyLarge ?? this.bodyLarge,
    button: button ?? this.button,
    titleSmall: titleSmall ?? this.titleSmall,
    title: title ?? this.title,
    display: display ?? this.display,
    score: score ?? this.score,
  );

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextStyles._(
      caption: l(caption, other.caption),
      label: l(label, other.label),
      bodySmall: l(bodySmall, other.bodySmall),
      body: l(body, other.body),
      bodyLarge: l(bodyLarge, other.bodyLarge),
      button: l(button, other.button),
      titleSmall: l(titleSmall, other.titleSmall),
      title: l(title, other.title),
      display: l(display, other.display),
      score: l(score, other.score),
    );
  }
}
