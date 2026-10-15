import 'package:flutter/material.dart';

import 'prototype/prototype_app.dart';
import 'prototype/prototype_model.dart';

/// Entry point for the clickable prototype: the hi-fi screens on mock data.
/// No services or config are needed:
///   flutter run -t lib/main_prototype.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    PrototypeApp(
      showAppStart: true,
      // Start as a new player would: language, welcome, then a game.
      // The language is preselected from the phone's: Amharic for `am`,
      // English for anything else.
      model: PrototypeModel(
        languageCode:
            WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
                'am'
            ? 'am'
            : 'en',
      )..firstLaunch = true,
    ),
  );
}
