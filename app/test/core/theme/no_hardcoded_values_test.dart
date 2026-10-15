import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The theme and the components must take every color, size and duration from
/// tokens.dart (generated from docs/design/tokens.json), so a design change is
/// one edit in the JSON. This scans the source for the usual ways of sneaking
/// a literal in. If it flags something legitimate, add a token or, for a value
/// that is not a design value, an entry to [_allowed] with the reason.
void main() {
  // Files that may hold literals: tokens.dart is generated from the JSON.
  const exempt = {'tokens.dart', 'token_types.dart'};

  final files =
      [
            ...Directory('lib/core/widgets').listSync().whereType<File>(),
            ...Directory('lib/core/theme').listSync().whereType<File>(),
          ]
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !exempt.contains(f.uri.pathSegments.last),
          )
          .toList();

  // A number other than 0, not part of an identifier (n12, w800) or a wider number.
  const num = r'(?<![\w.])(?!0\b)\d+(?:\.\d+)?\b';
  final rules = <String, RegExp>{
    'a Color literal': RegExp(r'\bColor\(0x'),
    'a Colors.* constant': RegExp(r'\bColors\.'),
    'a Duration literal': RegExp(r'\bDuration\('),
    'a literal font size': RegExp('fontSize:\\s*$num'),
    'a literal icon size': RegExp('\\bsize:\\s*$num'),
    'a literal radius': RegExp(
      '(?:BorderRadius\\.circular|Radius\\.circular)\\(\\s*$num',
    ),
    'a literal gap': RegExp('(?:SizedBox|EdgeInsets\\.\\w+)\\([^)]*$num'),
    'a literal width or height': RegExp(
      '\\b(?:width|height|minWidth|minHeight|dimension):\\s*$num',
    ),
    'a literal offset': RegExp('Offset\\(\\s*$num'),
  };

  // Layout values that are not design tokens, by file, with the reason.
  const allowed = <String, Set<String>>{};

  test('there are files to scan', () => expect(files, isNotEmpty));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('$name has no hard-coded design values', () {
      final problems = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final rule in rules.entries) {
          if (rule.value.hasMatch(line) &&
              !(allowed[name] ?? const {}).contains(line.trim())) {
            problems.add('$name:${i + 1}: ${rule.key}: ${line.trim()}');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
