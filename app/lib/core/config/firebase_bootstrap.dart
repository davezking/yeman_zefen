import 'package:firebase_core/firebase_core.dart';

import 'app_config.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

/// The Firebase project for the running flavor: `dev` -> the dev project,
/// `prod` -> the prod project.
FirebaseOptions firebaseOptionsFor(String flavor) => switch (flavor) {
  'dev' => dev.DefaultFirebaseOptions.currentPlatform,
  'prod' => prod.DefaultFirebaseOptions.currentPlatform,
  _ => throw StateError('Unknown flavor "$flavor"; expected dev or prod'),
};

Future<void> initializeFirebase() =>
    Firebase.initializeApp(options: firebaseOptionsFor(AppConfig.flavor));
