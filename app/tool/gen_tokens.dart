// Generates lib/core/theme/tokens.dart from docs/design/tokens.json.
//
//   dart run tool/gen_tokens.dart            write the file
//   dart run tool/gen_tokens.dart --check    exit 1 if the file is out of date
//
// tokens.json is the single source of truth. Never edit tokens.dart by hand:
// change the JSON and run this. test/core/theme/tokens_generated_test.dart
// fails when the two disagree, so a forgotten run is caught in CI.
//
// Each top-level section becomes a class (`color` -> ColorTokens) and each
// token a static const named from its path (`color.correct.fillTop` ->
// ColorTokens.correctFillTop). A token whose value is an object is split into
// one const per member (`size.playButton.minWidth` -> SizeTokens.playButtonMinWidth).
// A value of the form "{color.palette.sun400}" becomes an alias of that const.
// Shadows are split in two: the outer shadows are a List<BoxShadow>, and any
// `inset` parts go into a List<InsetShadow> named `...Inset` (Flutter has no
// inset shadows; widgets paint them as a highlight, see InsetGloss).
import 'dart:convert';
import 'dart:io';

const _tokensPath = '../docs/design/tokens.json';
const _outPath = 'lib/core/theme/tokens.dart';

const _classNames = <String, String>{
  'color': 'ColorTokens',
  'typography': 'TypeTokens',
  'spacing': 'SpacingTokens',
  'radius': 'RadiusTokens',
  'elevation': 'ElevationTokens',
  'size': 'SizeTokens',
  'motion': 'MotionTokens',
  'timing': 'TimingTokens',
};

Future<void> main(List<String> args) async {
  final json =
      jsonDecode(File(_tokensPath).readAsStringSync()) as Map<String, dynamic>;
  final out = generateTokens(json);
  final file = File(_outPath);
  if (args.contains('--check')) {
    final current = file.existsSync() ? file.readAsStringSync() : '';
    if (current != out) {
      stderr.writeln(
        '$_outPath is out of date. Run: dart run tool/gen_tokens.dart',
      );
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(out);
  stdout.writeln('Wrote $_outPath');
}

/// Pure so that tests can call it: tokens.json (decoded) in, Dart source out.
String generateTokens(Map<String, dynamic> json) {
  final sections = <String, List<_Token>>{};
  for (final entry in json.entries) {
    if (entry.key.startsWith(r'$')) continue;
    if (!_classNames.containsKey(entry.key)) {
      throw FormatException(
        'Unknown top-level section "${entry.key}" in tokens.json',
      );
    }
    final tokens = <_Token>[];
    _walk(entry.value as Map<String, dynamic>, [entry.key], null, tokens);
    sections[entry.key] = tokens;
  }

  final b = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln(
      '// Source: docs/design/tokens.json. Regenerate with: dart run tool/gen_tokens.dart',
    )
    // Keeps `dart format` from reflowing this file, which would make it differ from the generator's output.
    ..writeln('// dart format off')
    ..writeln()
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln()
    ..writeln("import 'token_types.dart';");

  for (final entry in sections.entries) {
    final names = <String>{};
    b
      ..writeln()
      ..writeln('abstract final class ${_classNames[entry.key]} {');
    final emitted = <String>[];
    for (final token in entry.value) {
      emitted.addAll(_emit(token, names));
    }
    b
      ..writeAll(emitted)
      ..writeln('}');
  }
  return b.toString();
}

class _Token {
  _Token(this.path, this.type, this.value, this.description);
  final List<String> path;
  final String? type;
  final Object? value;
  final String? description;
}

void _walk(
  Map<String, dynamic> node,
  List<String> path,
  String? inheritedType,
  List<_Token> out,
) {
  final type = node[r'$type'] as String? ?? inheritedType;
  for (final entry in node.entries) {
    if (entry.key.startsWith(r'$')) continue;
    final child = entry.value;
    if (child is! Map<String, dynamic>) {
      throw FormatException(
        '${[...path, entry.key].join('.')} is neither a token nor a group',
      );
    }
    final childPath = [...path, entry.key];
    if (child.containsKey(r'$value')) {
      out.add(
        _Token(
          childPath,
          child[r'$type'] as String? ?? type,
          child[r'$value'],
          child[r'$description'] as String?,
        ),
      );
    } else {
      _walk(child, childPath, type, out);
    }
  }
}

String _camel(List<String> parts) {
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    b.write(i == 0 ? p : p[0].toUpperCase() + p.substring(1));
  }
  var name = b.toString();
  // Identifiers cannot start with a digit (spacing "12" -> n12).
  if (RegExp(r'^[0-9]').hasMatch(name)) name = 'n$name';
  return name;
}

List<String> _emit(_Token t, Set<String> names) {
  final where = t.path.join('.');
  // Path without the section, e.g. [correct, fillTop].
  final local = t.path.sublist(1);
  final value = t.value;

  if (value is Map<String, dynamic>) {
    // An object value: one const per member.
    return [
      for (final member in value.entries)
        ..._emitOne(
          [...local, member.key],
          _memberType(member.key, t.type),
          member.value,
          t.description,
          names,
          '$where.${member.key}',
        ),
    ];
  }
  return _emitOne(local, t.type, value, t.description, names, where);
}

/// Members of an object value are typed by their key, since the object itself has no single type.
String? _memberType(String key, String? parentType) {
  switch (key) {
    case 'fontWeight':
      return 'fontWeight';
    case 'fontSize':
      return 'fontSizeNumber';
  }
  return parentType;
}

List<String> _emitOne(
  List<String> local,
  String? type,
  Object? value,
  String? description,
  Set<String> names,
  String where,
) {
  final name = _camel(local);
  if (!names.add(name)) {
    throw FormatException('Two tokens map to the name "$name" ($where)');
  }
  final doc = description == null
      ? ''
      : '  /// ${description.replaceAll('\n', ' ')}\n';

  String line(String dartType, String expr) =>
      '$doc  static const $dartType $name = $expr;\n';

  if (value is String && value.startsWith('{') && value.endsWith('}')) {
    // Alias: {color.palette.sun400} -> the const holding it.
    final target = _camel(
      value.substring(1, value.length - 1).split('.').skip(1).toList(),
    );
    return [line(_aliasType(type, where), target)];
  }

  switch (type) {
    case 'color':
      return [line('Color', _color(value as String, where))];
    case 'dimension':
      final parts = (value as String).trim().split(RegExp(r'\s+'));
      if (parts.length == 1) return [line('double', _px(parts.first, where))];
      if (parts.length == 4) {
        // CSS corner order: top-left, top-right, bottom-right, bottom-left.
        final c = parts.map((p) => _px(p, where)).toList();
        return [
          line(
            'BorderRadius',
            'BorderRadius.only(topLeft: Radius.circular(${c[0]}), topRight: Radius.circular(${c[1]}), bottomRight: Radius.circular(${c[2]}), bottomLeft: Radius.circular(${c[3]}))',
          ),
        ];
      }
      throw FormatException('$where: expected 1 or 4 lengths, got "$value"');
    case 'fontSizeNumber':
      return [line('double', (value as num).toDouble().toString())];
    case 'number':
      final n = value as num;
      return [n is int ? line('int', '$n') : line('double', '$n')];
    case 'fontWeight':
      final w = (value as num).toInt();
      if (w < 100 || w > 900 || w % 100 != 0) {
        throw FormatException('$where: bad font weight $w');
      }
      return [line('FontWeight', 'FontWeight.w$w')];
    case 'fontFamily':
      final families = (value as List).cast<String>();
      final fallbacks = families.length > 1
          ? ' Fallbacks in the design: ${families.skip(1).join(', ')}.'
          : '';
      return [
        '  /// Font family.$fallbacks\n  static const String $name = ${_str(families.first)};\n',
      ];
    case 'duration':
      final m = RegExp(r'^(\d+)ms$').firstMatch(value as String);
      if (m == null) {
        throw FormatException(
          '$where: expected a duration in ms, got "$value"',
        );
      }
      return [line('Duration', 'Duration(milliseconds: ${m.group(1)})')];
    case 'cubicBezier':
      final c = (value as List).cast<num>().map((n) => n.toDouble()).toList();
      if (c.length != 4) {
        throw FormatException('$where: a cubic bezier needs 4 numbers');
      }
      return [line('Cubic', 'Cubic(${c.join(', ')})')];
    case 'shadow':
      return _shadow(name, doc, value as String, where);
    case 'string':
      return [line('String', _str(value as String))];
  }
  throw FormatException('$where: unsupported token type "$type"');
}

String _aliasType(String? type, String where) {
  switch (type) {
    case 'color':
      return 'Color';
    case 'dimension':
    case 'fontSizeNumber':
      return 'double';
    case 'fontWeight':
      return 'FontWeight';
    case 'duration':
      return 'Duration';
  }
  throw FormatException(
    '$where: aliases are only supported for colors, dimensions, weights and durations',
  );
}

String _str(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String _px(String s, String where) {
  final m = RegExp(r'^(-?\d+(?:\.\d+)?)(?:px)?$').firstMatch(s);
  if (m == null) {
    throw FormatException('$where: expected a length like "12px", got "$s"');
  }
  return double.parse(m.group(1)!).toString();
}

String _color(String s, String where) {
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s);
  if (hex != null) return 'Color(0xFF${hex.group(1)!.toUpperCase()})';
  final rgba = RegExp(
    r'^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)$',
  ).firstMatch(s);
  if (rgba != null) {
    final a = (double.parse(rgba.group(4)!) * 255).round().clamp(0, 255);
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return 'Color(0x${h(a)}${h(int.parse(rgba.group(1)!))}${h(int.parse(rgba.group(2)!))}${h(int.parse(rgba.group(3)!))})';
  }
  throw FormatException('$where: expected #RRGGBB or rgba(r,g,b,a), got "$s"');
}

/// Splits [s] on [sep] outside parentheses.
List<String> _splitTop(String s, Pattern sep) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth == 0 && s.startsWith(sep, i)) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

List<String> _shadow(String name, String doc, String css, String where) {
  final outer = <String>[];
  final inner = <String>[];
  for (final layer in _splitTop(css, ',')) {
    var words = _splitTop(layer, RegExp(r'\s'));
    final inset = words.first == 'inset';
    if (inset) words = words.sublist(1);
    // x y blur [spread] color
    final colorWord = words.last;
    final lengths = words.sublist(0, words.length - 1);
    if (lengths.length < 3 || lengths.length > 4) {
      throw FormatException('$where: bad shadow "$layer"');
    }
    final x = _px(lengths[0], where);
    final y = _px(lengths[1], where);
    final blur = _px(lengths[2], where);
    final color = _color(colorWord, where);
    if (lengths.length == 4 && double.parse(_px(lengths[3], where)) != 0) {
      throw FormatException('$where: shadow spread is not supported');
    }
    if (inset) {
      inner.add('InsetShadow(color: $color, dx: $x, dy: $y, blur: $blur)');
    } else {
      outer.add(
        'BoxShadow(color: $color, offset: Offset($x, $y), blurRadius: $blur)',
      );
    }
  }
  return [
    if (outer.isNotEmpty)
      '$doc  static const List<BoxShadow> $name = [\n${outer.map((s) => '    $s,\n').join()}  ];\n',
    if (inner.isNotEmpty)
      '  /// Inset parts of [$name], painted as a highlight by InsetGloss.\n  static const List<InsetShadow> ${name}Inset = [\n${inner.map((s) => '    $s,\n').join()}  ];\n',
  ];
}
