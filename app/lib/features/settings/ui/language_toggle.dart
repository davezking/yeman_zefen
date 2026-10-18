import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/locale_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Picks the UI language. The change applies to the whole app at once, this screen included.
/// Each language is named in its own script, so it can be found from the other one.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider);
    return Semantics(
      container: true,
      label: l10n.settingsLanguage,
      child: SegmentedButton<Locale>(
        key: const Key('language-toggle'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: amharic, label: Text(l10n.onboardLangAmharic)),
          ButtonSegment(value: english, label: Text(l10n.onboardLangEnglish)),
        ],
        selected: {localeForDevice(current)},
        onSelectionChanged: (s) => ref.read(localeProvider.notifier).choose(s.first),
      ),
    );
  }
}
