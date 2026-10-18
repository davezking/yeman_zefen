import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/prototype/mock_data.dart';
import 'package:yeman_zefen/prototype/models.dart';

void main() {
  group('screens stay free of providers and services', () {
    // Everything a screen may import. A new import has to be added here on
    // purpose: that is the moment to ask whether Phase 4 can still wire it.
    final allowed = <RegExp>[
      RegExp(r"^package:flutter/(material|semantics)\.dart"),
      RegExp(r"^package:intl/intl\.dart$"),
      RegExp(r'^\.\./\.\./core/theme/(app_text|theme_context|tokens)\.dart$'),
      RegExp(r'^\.\./\.\./core/widgets/widgets\.dart$'),
      RegExp(r'^\.\./\.\./l10n/app_localizations\.dart$'),
      RegExp(r'^\.\./(labels|models)\.dart$'),
      // The two screens that moved into features/ (they stay plain widgets, so the same rule applies).
      RegExp(r'^\.\./\.\./\.\./core/theme/(app_text|theme_context|tokens)\.dart$'),
      RegExp(r'^\.\./\.\./\.\./core/widgets/widgets\.dart$'),
      RegExp(r'^\.\./\.\./\.\./l10n/app_localizations\.dart$'),
      RegExp(r'^\.\./\.\./\.\./prototype/(labels|models)\.dart$'),
    ];

    final files = [
      ...Directory('lib/prototype/screens')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('lib/features/game/presentation/home_screen.dart'),
      File('lib/features/game/presentation/mode_select_screen.dart'),
      File('lib/features/game/presentation/setup_screen.dart'),
      File('lib/features/settings/presentation/settings_screen.dart'),
      File('lib/features/account/ui/sign_in_sheet.dart'),
      File('lib/features/leaderboard/ui/leaderboard_screen.dart'),
    ];

    test('there are screens to scan', () => expect(files.length, 11));


    for (final file in files) {
      final name = file.uri.pathSegments.last;
      test('$name imports only the allowed libraries', () {
        final imports = RegExp(
          r"""^import\s+['"]([^'"]+)['"]""",
          multiLine: true,
        ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!);
        final bad = imports.where((i) => !allowed.any((r) => r.hasMatch(i)));
        expect(bad, isEmpty, reason: '$name imports ${bad.join(', ')}');
      });
    }

    test('models.dart and labels.dart are plain too', () {
      for (final name in ['models', 'labels']) {
        final source = File('lib/prototype/$name.dart').readAsStringSync();
        expect(source, isNot(contains('riverpod')));
        expect(source, isNot(contains('features/')));
        expect(source, isNot(contains('core/db')));
        expect(source, isNot(contains('core/http')));
      }
    });
  });

  group('mock data', () {
    test('about 20 tracks with both scripts, across all five eras', () {
      expect(mockTracks.length, 20);
      expect(mockTracks.map((t) => t.generationId).toSet(), {1, 2, 3, 4, 5});
      expect(mockTracks.map((t) => t.id).toSet().length, 20);
      for (final t in mockTracks) {
        expect(t.titleAm, matches(RegExp(r'[ሀ-፿]')), reason: t.id);
        expect(t.artistAm, matches(RegExp(r'[ሀ-፿]')), reason: t.id);
        expect(t.titleLatin, matches(RegExp(r'^[A-Za-z ]+$')), reason: t.id);
        expect(t.artistLatin, matches(RegExp(r'^[A-Za-z ]+$')), reason: t.id);
      }
    });

    test('four packs in four different states', () {
      expect(mockPacks.length, 4);
      expect(mockPacks.map((p) => p.status).toSet().length, 4);
    });

    test('the cache is within its cap and the built-in songs add up', () {
      expect(mockCache.usedMb, lessThanOrEqualTo(mockCache.capMb));
      expect(mockBuiltInSongCount, 25);
    });

    test('a guest and a signed-in user', () {
      expect(mockGuest.isGuest, isTrue);
      expect(mockNewGuest.bestScore, isNull);
      expect(mockSignedIn.isGuest, isFalse);
      expect(mockSignedIn.weeklyRank, isNotNull);
    });

    test('names follow the script of the language', () {
      const t = Track(
        id: 'x',
        titleAm: 'እሬ መላ መላ',
        titleLatin: 'Ere Mela Mela',
        artistAm: 'ማሕሙድ አሕመድ',
        artistLatin: 'Mahmoud Ahmed',
        generationId: 1,
        genre: Genre.ethiojazz,
      );
      expect(t.title(const Locale('am')), 'እሬ መላ መላ');
      expect(t.artist(const Locale('en')), 'Mahmoud Ahmed');
    });
  });

  group('copy.md and the ARB files agree', () {
    // The ARB files are the app's copy; copy.md is the reviewed source. Every
    // string in the deck has to be in both, with the same placeholders.
    final deck = <String, List<String>>{};
    for (final line in File('../docs/design/copy.md').readAsLinesSync()) {
      final m = RegExp(r'^\| `([^`]+)` \| (.*) \| (.*) \|\s*$')
          .firstMatch(line);
      if (m != null) deck[m.group(1)!] = [m.group(2)!, m.group(3)!];
    }
    String arbKey(String key) {
      final parts = key.split('.');
      return parts.first +
          parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
    }

    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final am = jsonDecode(
      File('lib/l10n/app_am.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    List<String> placeholders(String s) =>
        RegExp(r'\{([A-Za-z]\w*)')
            .allMatches(s)
            .map((m) => m.group(1)!)
            .where((n) => n != 'plural' && n != 'other')
            .toSet()
            .toList()
          ..sort();

    test('the deck was found', () => expect(deck.length, greaterThan(200)));

    for (final e in deck.entries) {
      test('${e.key} is in both languages, unchanged', () {
        final key = arbKey(e.key);
        expect(en[key], e.value[0]);
        expect(am[key], e.value[1]);
        expect(
          placeholders(am[key] as String),
          placeholders(en[key] as String),
        );
      });
    }
  });
}
