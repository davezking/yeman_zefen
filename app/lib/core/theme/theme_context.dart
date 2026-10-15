import 'package:flutter/widgets.dart';

import 'app_text.dart';
import 'game_tokens.dart';
import 'theme_lookup.dart';

/// Shorthands for what the app theme carries. They fail loudly when the theme
/// was not built with [buildAppTheme], so a missing theme shows up in tests
/// rather than as silently wrong colors.
extension AppThemeContext on BuildContext {
  GameTokens get game => lookupExtension<GameTokens>(this);

  AppTextStyles get text => lookupExtension<AppTextStyles>(this);

  /// True when the user asked the system to cut animations.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
