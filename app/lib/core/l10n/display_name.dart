import 'dart:ui';

/// A track or artist name in both scripts, as the catalog has it: Fidel (`am`) and Latin (`en`).
/// Either can be missing. Names are never transliterated at runtime (`docs/design/copy.md`).
class DisplayName {
  const DisplayName({this.am, this.latin});

  /// A name from catalog fields. Blank strings count as missing.
  factory DisplayName.of(String? am, String? latin) => DisplayName(am: _clean(am), latin: _clean(latin));

  final String? am;
  final String? latin;

  static String? _clean(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// True when the catalog has no name in either script.
  bool get isEmpty => am == null && latin == null;

  /// The name in [locale]'s script: Fidel for Amharic, Latin otherwise. The other script stands
  /// in when the preferred one is missing; [fallback] is used when both are.
  String of(Locale locale, {String fallback = ''}) =>
      (locale.languageCode == 'am' ? am ?? latin : latin ?? am) ?? fallback;

  /// The name in the other script, for a subtitle. Null when it is missing or the same text.
  String? alternate(Locale locale) {
    final shown = of(locale);
    final alt = locale.languageCode == 'am' ? latin : am;
    return alt == null || alt == shown ? null : alt;
  }

  @override
  bool operator ==(Object other) => other is DisplayName && other.am == am && other.latin == latin;

  @override
  int get hashCode => Object.hash(am, latin);
}
