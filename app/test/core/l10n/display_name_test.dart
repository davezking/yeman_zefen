import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/l10n/display_name.dart';

void main() {
  const am = Locale('am');
  const en = Locale('en');
  const both = DisplayName(am: 'ዘፈን', latin: 'Zefen');

  group('of', () {
    test('is Fidel in Amharic and Latin in English', () {
      expect(both.of(am), 'ዘፈን');
      expect(both.of(en), 'Zefen');
    });

    test('uses the other script when the preferred one is missing', () {
      const latinOnly = DisplayName(latin: 'Zefen');
      const fidelOnly = DisplayName(am: 'ዘፈን');
      expect(latinOnly.of(am), 'Zefen');
      expect(fidelOnly.of(en), 'ዘፈን');
    });

    test('uses the fallback only when both scripts are missing', () {
      expect(const DisplayName().of(am, fallback: 'Unknown'), 'Unknown');
      expect(const DisplayName().of(en), '');
      expect(both.of(en, fallback: 'Unknown'), 'Zefen');
    });

    test('any other language gets the Latin name', () {
      expect(both.of(const Locale('fr')), 'Zefen');
    });
  });

  group('alternate', () {
    test('is the other script, for a subtitle', () {
      expect(both.alternate(am), 'Zefen');
      expect(both.alternate(en), 'ዘፈን');
    });

    test('is null when there is no other script or it is the same text', () {
      expect(const DisplayName(am: 'ዘፈን').alternate(am), isNull);
      expect(const DisplayName(am: 'ዘፈን').alternate(en), isNull);
      expect(const DisplayName(am: 'Same', latin: 'Same').alternate(en), isNull);
    });
  });

  group('DisplayName.of', () {
    test('trims, and treats blank text as missing', () {
      final name = DisplayName.of('  ዘፈን ', '   ');
      expect(name.am, 'ዘፈን');
      expect(name.latin, isNull);
      expect(DisplayName.of(null, '').isEmpty, isTrue);
    });
  });

  test('names with the same text are equal', () {
    expect(const DisplayName(am: 'ሀ', latin: 'a'), const DisplayName(am: 'ሀ', latin: 'a'));
    expect(const DisplayName(am: 'ሀ', latin: 'a') == const DisplayName(am: 'ሀ'), isFalse);
  });
}
