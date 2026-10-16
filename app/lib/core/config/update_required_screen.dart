import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'app_config.dart';

/// Shown instead of the app when its version is below the server's `minAppVersion`. It has no
/// way past: the player can only update.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.updateRequiredTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(l10n.updateRequiredBody, textAlign: TextAlign.center),
                if (AppConfig.storeUrl.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => launchUrl(Uri.parse(AppConfig.storeUrl), mode: LaunchMode.externalApplication),
                    child: Text(l10n.updateRequiredButton),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
