import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio/game_audio_session.dart';
import 'core/auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/profile/profile_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();
  await initializeFirebase();
  await configureGameAudioSession();
  final container = ProviderContainer();
  // Creating the service starts the anonymous sign-in without waiting for it:
  // with no network the game still starts with its bundled and cached clips.
  container.read(authServiceProvider);
  // Tells the server who the player is once signed in, and again on each app open (at most every 6 hours).
  container.read(profileSyncStarterProvider);
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
