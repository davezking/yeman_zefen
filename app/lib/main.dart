import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio/game_audio_session.dart';
import 'core/auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();
  await initializeFirebase();
  await configureGameAudioSession();
  final container = ProviderContainer();
  // Not awaited: with no network the anonymous sign-in waits, and the game
  // still starts with its bundled and cached clips.
  container.read(authServiceProvider).start();
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
