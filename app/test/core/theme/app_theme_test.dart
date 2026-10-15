import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/theme/app_text.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/core/theme/game_tokens.dart';
import 'package:yeman_zefen/core/theme/tokens.dart';

void main() {
  const en = Locale('en');
  const am = Locale('am');

  group('AppTextStyles', () {
    test('English puts Poppins first, with Fidel as the fallback, at the Latin line height', () {
      final s = AppTextStyles.forLocale(en);
      expect(s.body.fontFamily, 'Poppins');
      expect(s.body.fontFamilyFallback, ['Noto Sans Ethiopic']);
      expect(s.body.height, TypeTokens.lineHeightLatin);
      expect(s.bodyLarge.fontSize, 16);
      expect(s.bodyLarge.fontWeight, FontWeight.w700);
    });

    test(
      'Amharic puts Noto Sans Ethiopic first, with its own taller line height',
      () {
        final s = AppTextStyles.forLocale(am);
        expect(s.body.fontFamily, 'Noto Sans Ethiopic');
        expect(s.body.fontFamilyFallback, ['Poppins']);
        expect(s.body.height, TypeTokens.lineHeightEthiopic);
        expect(s.body.height, greaterThan(TypeTokens.lineHeightLatin));
      },
    );

    test('dense Amharic uses the tighter Fidel line height', () {
      expect(
        AppTextStyles.forLocale(am, dense: true).body.height,
        TypeTokens.lineHeightEthiopicDense,
      );
      expect(
        AppTextStyles.forLocale(en, dense: true).body.height,
        TypeTokens.lineHeightLatin,
      );
    });

    test('headings use the heading line height in both scripts', () {
      for (final locale in [en, am]) {
        final s = AppTextStyles.forLocale(locale);
        expect(s.title.height, TypeTokens.lineHeightHeading);
        expect(s.titleSmall.height, TypeTokens.lineHeightHeading);
        expect(s.display.height, TypeTokens.lineHeightHeading);
      }
    });

    test('the score is always Poppins, even in Amharic', () {
      final s = AppTextStyles.forLocale(am);
      expect(s.score.fontFamily, 'Poppins');
      expect(s.score.fontSize, 52);
    });

    test('every style asks for its weight explicitly, so the variable Fidel font follows', () {
      final s = AppTextStyles.forLocale(am);
      for (final style in [
        s.caption,
        s.label,
        s.bodySmall,
        s.body,
        s.bodyLarge,
        s.button,
        s.titleSmall,
        s.title,
        s.display,
        s.score,
      ]) {
        expect(style.fontVariations, [
          FontVariation.weight(style.fontWeight!.value.toDouble()),
        ]);
      }
      final heavier = AppTextStyles.withWeight(s.body, FontWeight.w800);
      expect(heavier.fontWeight, FontWeight.w800);
      expect(heavier.fontVariations, [FontVariation.weight(800)]);
    });

    test('the Material text theme is mapped from the scale', () {
      final s = AppTextStyles.forLocale(en);
      final t = s.toTextTheme();
      expect(t.bodyMedium, s.body);
      expect(t.labelLarge, s.button);
      expect(t.titleLarge, s.titleSmall);
    });
  });

  group('buildAppTheme', () {
    test('carries the game tokens and the text styles of its language', () {
      final theme = buildAppTheme(am);
      expect(theme.extension<GameTokens>(), isNotNull);
      expect(
        theme.extension<AppTextStyles>()!.body.fontFamily,
        'Noto Sans Ethiopic',
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Noto Sans Ethiopic');
      expect(buildAppTheme(en).textTheme.bodyMedium!.fontFamily, 'Poppins');
    });

    test('uses the brand colors', () {
      final scheme = buildAppTheme(en).colorScheme;
      expect(scheme.primary, ColorTokens.paletteSun400);
      expect(scheme.onPrimary, ColorTokens.paletteInk);
      expect(scheme.error, ColorTokens.paletteRed700);
      expect(
        buildAppTheme(en).scaffoldBackgroundColor,
        ColorTokens.paletteWhite,
      );
    });

    test('the main button meets the 48 dp touch target', () {
      final style = buildAppTheme(en).filledButtonTheme.style!;
      expect(
        style.minimumSize!.resolve({})!.height,
        greaterThanOrEqualTo(SpacingTokens.touchTargetMin),
      );
    });
  });

  group('GameTokens', () {
    test(
      'has a color for all eras and falls back to "all eras" for an unknown id',
      () {
        const game = GameTokens.light;
        expect(game.eraColor(2), ColorTokens.era80s);
        expect(game.eraColor(5), ColorTokens.eraModern);
        expect(game.eraColor(99), ColorTokens.eraAll);
        expect(game.eraColors.keys.toSet(), {0, 1, 2, 3, 4, 5});
      },
    );

    test('correct and wrong differ in color', () {
      const game = GameTokens.light;
      expect(game.correct.bottom, isNot(game.wrong.bottom));
      expect(game.correct.heading, ColorTokens.correctText);
    });
  });
}
