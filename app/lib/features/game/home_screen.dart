import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

/// Throwaway spike screen. It proves the Amharic font and the l10n wiring, nothing more.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('የማን ዘፈን', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 16),
            Text(l10n.homeTagline),
            const SizedBox(height: 16),
            FilledButton(onPressed: () {}, child: Text(l10n.playButton)),
            // Measurement tooling for the spike. Not shown in prod builds.
            if (AppConfig.flavor == 'dev')
              TextButton(
                onPressed: () => context.push('/debug/clip-playback'),
                child: const Text('Clip playback debug'),
              ),
          ],
        ),
      ),
    );
  }
}
