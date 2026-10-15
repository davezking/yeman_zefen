import 'package:flutter/material.dart';

/// Reads a [ThemeExtension] from the nearest [Theme], with a clear error when
/// the theme was not built with `buildAppTheme`.
T lookupExtension<T extends ThemeExtension<T>>(BuildContext context) {
  final extension = Theme.of(context).extension<T>();
  assert(
    extension != null,
    'The Theme has no $T. Build it with buildAppTheme() from core/theme/app_theme.dart.',
  );
  return extension!;
}
