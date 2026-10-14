import 'dart:io';

/// Reads a file from the repo's `docs/` folder. Tests run from `app/`, and
/// from the repo root when run by a tool that starts there.
String readDoc(String name) {
  for (final path in ['../docs/$name', 'docs/$name']) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  throw StateError('docs/$name not found from ${Directory.current.path}');
}
