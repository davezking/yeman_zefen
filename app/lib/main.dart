import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio/game_audio_session.dart';
import 'core/config/app_config.dart';
import 'features/packs/data/clip_downloader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();
  await configureGameAudioSession();
  await BackgroundClipDownloader.configure();
  runApp(const ProviderScope(child: App()));
}
