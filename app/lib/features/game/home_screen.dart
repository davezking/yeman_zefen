import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../settings/ui/language_toggle.dart';
import 'debug/debug_links.dart';

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
            Text(l10n.appName, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 16),
            Text(l10n.homeTagline),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go('/start'), child: Text(l10n.playButton)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => context.go('/packs'), child: Text(l10n.packsTitle)),
            OutlinedButton(onPressed: () => context.go('/leaderboard'), child: Text(l10n.homeLeaderboard)),
            const SizedBox(height: 16),
            const LanguageToggle(),
            const DebugLinks(),
          ],
        ),
      ),
    );
  }
}
