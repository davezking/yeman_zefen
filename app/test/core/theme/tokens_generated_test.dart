import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/gen_tokens.dart';

void main() {
  test(
    'lib/core/theme/tokens.dart is up to date with docs/design/tokens.json',
    () {
      final json = jsonDecode(
        File('../docs/design/tokens.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = generateTokens(json);
      final actual = File('lib/core/theme/tokens.dart').readAsStringSync();
      expect(
        actual,
        expected,
        reason: 'tokens.json changed. Run: dart run tool/gen_tokens.dart',
      );
    },
  );

  group('generateTokens', () {
    String gen(Map<String, dynamic> json) => generateTokens(json);

    test('turns colors, with alpha, and aliases into Color consts', () {
      final out = gen({
        'color': {
          r'$type': 'color',
          'ink': {r'$value': '#2b2118'},
          'glow': {r'$value': 'rgba(240,86,58,0.45)'},
          'text': {r'$value': '{color.ink}', r'$description': 'Main text'},
        },
      });
      expect(out, contains('static const Color ink = Color(0xFF2B2118);'));
      // 0.45 * 255 = 114.75, which rounds to 115 = 0x73.
      expect(out, contains('static const Color glow = Color(0x73F0563A);'));
      expect(out, contains('/// Main text\n  static const Color text = ink;'));
    });

    test('splits an object value into one const per member and names digits safely', () {
      final out = gen({
        'size': {
          r'$type': 'dimension',
          'playButton': {
            r'$value': {'minWidth': '140px', 'height': '62px'},
          },
        },
        'spacing': {
          r'$type': 'dimension',
          '12': {r'$value': '12px'},
        },
      });
      expect(out, contains('static const double playButtonMinWidth = 140.0;'));
      expect(out, contains('static const double playButtonHeight = 62.0;'));
      expect(out, contains('static const double n12 = 12.0;'));
    });

    test('reads four lengths as CSS corners (top-left, top-right, bottom-right, bottom-left)', () {
      final out = gen({
        'radius': {
          r'$type': 'dimension',
          'sheet': {r'$value': '32px 32px 0 0'},
        },
      });
      expect(
        out,
        contains(
          'BorderRadius.only(topLeft: Radius.circular(32.0), topRight: Radius.circular(32.0), bottomRight: Radius.circular(0.0), bottomLeft: Radius.circular(0.0))',
        ),
      );
    });

    test('splits shadows into outer BoxShadows and inset highlights', () {
      final out = gen({
        'elevation': {
          r'$type': 'shadow',
          'primary': {
            r'$value': '0 6px 0 #D99418, 0 12px 26px rgba(255,170,46,0.40), inset 0 2px 0 rgba(255,255,255,0.6)',
          },
        },
      });
      expect(out, contains('static const List<BoxShadow> primary = ['));
      expect(out, contains('offset: Offset(0.0, 12.0), blurRadius: 26.0'));
      expect(out, contains('static const List<InsetShadow> primaryInset = ['));
      expect(
        out,
        contains(
          'InsetShadow(color: Color(0x99FFFFFF), dx: 0.0, dy: 2.0, blur: 0.0)',
        ),
      );
    });

    test('reads durations, curves and font weights', () {
      final out = gen({
        'motion': {
          'duration': {
            r'$type': 'duration',
            'press': {r'$value': '120ms'},
          },
          'easing': {
            r'$type': 'cubicBezier',
            'standard': {
              r'$value': [0.25, 0.1, 0.25, 1],
            },
          },
        },
        'typography': {
          'weight': {
            r'$type': 'fontWeight',
            'bold': {r'$value': 700},
          },
        },
      });
      expect(
        out,
        contains(
          'static const Duration durationPress = Duration(milliseconds: 120);',
        ),
      );
      expect(
        out,
        contains(
          'static const Cubic easingStandard = Cubic(0.25, 0.1, 0.25, 1.0);',
        ),
      );
      expect(
        out,
        contains('static const FontWeight weightBold = FontWeight.w700;'),
      );
    });

    test('is deterministic', () {
      final json = jsonDecode(
        File('../docs/design/tokens.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(gen(json), gen(json));
    });

    test('fails loudly on input it does not understand', () {
      expect(() => gen({'banana': <String, dynamic>{}}), throwsFormatException);
      expect(
        () => gen({
          'color': {
            'x': {r'$type': 'gradient', r'$value': 'nope'},
          },
        }),
        throwsFormatException,
      );
      expect(
        () => gen({
          'color': {
            r'$type': 'color',
            'x': {r'$value': 'red'},
          },
        }),
        throwsFormatException,
      );
    });
  });
}
