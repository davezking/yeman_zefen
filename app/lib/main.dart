import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio/game_audio_session.dart';
import 'core/auth/account_linker.dart';
import 'core/auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/l10n/locale_provider.dart';
import 'core/config/remote_config.dart';
import 'core/profile/profile_sync.dart';
import 'features/game/application/session_sync_providers.dart';
import 'features/packs/data/clip_providers.dart';

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
  // Finishes the server side of an account link that was cut off (offline, or the app closed).
  container.read(accountSyncStarterProvider);
  // The saved language, so the first frame is already in it.
  await primeLocale(container);
  // The server's tunables: the cached ones before the first frame, the server's on every start.
  await primeRemoteConfig(container);
  container.read(remoteConfigStarterProvider);
  // Uploads finished sessions: on start, once signed in, when back online, after each session, on resume.
  container.read(sessionSyncStarterProvider);
  // Registers the bundled starter clips, then keeps the catalog fresh: on start and every 12 hours.
  container.read(catalogStarterProvider);
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
