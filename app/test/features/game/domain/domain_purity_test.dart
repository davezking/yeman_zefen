import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The round engine is pure Dart so the server's Phase 3 rules can be checked
/// against it, and so it runs in plain `dart test`. Only `dart:math` and
/// `dart:convert` are allowed, plus files in the same folder.
void main() {
  final dir = Directory('lib/features/game/domain');
  final allowedDart = {'dart:math', 'dart:convert'};

  test('the domain folder was found', () {
    expect(dir.existsSync(), isTrue);
    expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart')), isNotEmpty);
  });

  for (final file in dir.existsSync() ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart')) : <File>[]) {
    test('${file.uri.pathSegments.last} imports only dart:math, dart:convert and its own folder', () {
      final directives = file
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.startsWith('import ') || l.startsWith('export ') || l.startsWith('part '));
      for (final line in directives) {
        final uri = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(line)!.group(1)!;
        final isRelative = !uri.contains(':') && !uri.startsWith('/') && !uri.contains('/');
        expect(isRelative || allowedDart.contains(uri), isTrue, reason: '${file.path}: $line');
      }
    });
  }
}
