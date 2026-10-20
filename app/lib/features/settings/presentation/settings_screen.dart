import 'package:flutter/material.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/models.dart';

/// Settings: language, sound and vibration, the account, Offline play, privacy
/// and about. The language switch changes the app's language immediately.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.languageCode,
    required this.soundOn,
    required this.hapticsOn,
    required this.user,
    required this.offlinePackCount,
    required this.offlineSizeMb,
    required this.version,
    required this.onLanguage,
    required this.onSound,
    required this.onHaptics,
    required this.onSignIn,
    required this.onSignOut,
    required this.onDeleteAccount,
    required this.onOfflinePlay,
    required this.onAdPrivacy,
    required this.onPrivacy,
    required this.onAbout,
    required this.onHome,
    required this.onPlay,
    this.offlineUpdateAvailable = false,
    this.providers = const [],
  });

  /// `am` or `en`.
  final String languageCode;
  final bool soundOn;
  final bool hapticsOn;
  final UserInfo user;

  /// How a signed-in player signs in, shown under their name.
  final List<SignInProvider> providers;

  /// Packs on the phone and their total size, for the "Offline play" row.
  final int offlinePackCount;
  final int offlineSizeMb;

  /// An installed pack has an update: the Offline play row gets a badge.
  final bool offlineUpdateAvailable;
  final String version;

  final ValueChanged<String> onLanguage;
  final ValueChanged<bool> onSound;
  final ValueChanged<bool> onHaptics;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;
  final VoidCallback onOfflinePlay;
  /// Null hides the row: Google does not require privacy options here.
  final VoidCallback? onAdPrivacy;
  final VoidCallback onPrivacy;
  final VoidCallback onAbout;
  final VoidCallback onHome;
  final VoidCallback onPlay;

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required VoidCallback onConfirmed,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppDialog(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: l10n.packsCancel,
    );
    if (confirmed == true) onConfirmed();
  }

  /// Two confirms before anything is deleted: what deleting means, then a last "now?".
  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final first = await showAppDialog(
      context,
      title: l10n.settingsDelete,
      body: l10n.settingsDeleteBody,
      confirmLabel: l10n.settingsDeleteConfirm,
      cancelLabel: l10n.packsCancel,
    );
    if (first != true || !context.mounted) return;
    await _confirm(
      context,
      title: l10n.settingsDeleteFinalTitle,
      body: l10n.settingsDeleteFinalBody,
      confirmLabel: l10n.settingsDelete,
      onConfirmed: onDeleteAccount,
    );
  }

  String _accountSubtitle(AppLocalizations l10n) {
    final names = [
      for (final p in providers)
        switch (p) {
          SignInProvider.google => 'Google',
          SignInProvider.apple => 'Apple',
          SignInProvider.email => l10n.settingsProviderEmail,
        },
    ];
    return [
      if (user.displayName case final name? when name.isNotEmpty) name,
      if (names.isNotEmpty) l10n.settingsSignedInWith(names.join(' · ')),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;

    final accountRows = <Widget>[
      if (user.isGuest)
        SettingsRow(
          title: l10n.settingsGuest,
          onTap: null,
          trailing: PrimaryButton(
            label: l10n.settingsSignIn,
            small: true,
            expand: false,
            onPressed: onSignIn,
          ),
        )
      else ...[
        SettingsRow(
          title: l10n.settingsAccount,
          subtitle: _accountSubtitle(l10n),
          onTap: null,
          trailing: SecondaryButton(
            label: l10n.settingsSignOut,
            small: true,
            onPressed: () => _confirm(
              context,
              title: l10n.settingsSignOut,
              body: l10n.settingsSignOutConfirm,
              confirmLabel: l10n.settingsSignOut,
              onConfirmed: onSignOut,
            ),
          ),
        ),
      ],
      SettingsRow(
        title: l10n.settingsOffline(offlinePackCount, offlineSizeMb),
        subtitle: offlineUpdateAvailable ? l10n.packsUpdateAvailable : null,
        subtitleColor: ColorTokens.correctText,
        badge: offlineUpdateAvailable,
        onTap: onOfflinePlay,
      ),
      if (onAdPrivacy != null) SettingsRow(title: l10n.settingsAdPrivacy, onTap: onAdPrivacy),
    ];

    return Scaffold(
      body: HeroScaffold(
        denseText: true,
        heroRadius: RadiusTokens.heroDense,
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n26,
          SpacingTokens.n18,
          SpacingTokens.n22,
        ),
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n16,
          SpacingTokens.n24,
          SpacingTokens.n16,
          SpacingTokens.n12,
        ),
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.settingsTitle, style: text.title),
            ),
            const SizedBox(height: SpacingTokens.n12),
            Text(l10n.settingsLanguage, style: text.label),
            const SizedBox(height: SpacingTokens.n12),
            SegmentedControl<String>(
              style: SegmentedStyle.onHero,
              semanticLabel: l10n.settingsLanguage,
              selected: languageCode,
              onChanged: onLanguage,
              options: const [
                // Each in its own script, whatever the app language is.
                SegmentOption(
                  value: 'am',
                  label: 'አማርኛ',
                  textLocale: Locale('am'),
                ),
                SegmentOption(
                  value: 'en',
                  label: 'English',
                  textLocale: Locale('en'),
                ),
              ],
            ),
          ],
        ),
        body: [
          SettingsGroup(
            children: [
              SettingsRow.toggle(
                title: l10n.settingsSound,
                value: soundOn,
                onChanged: onSound,
              ),
              SettingsRow.toggle(
                title: l10n.settingsHaptics,
                value: hapticsOn,
                onChanged: onHaptics,
              ),
            ],
          ),
          SettingsGroup(children: accountRows),
          SettingsGroup(
            children: [
              SettingsRow(title: l10n.settingsPrivacy, onTap: onPrivacy),
              SettingsRow(title: l10n.settingsAbout, onTap: onAbout),
              if (!user.isGuest)
                SettingsRow(
                  title: l10n.settingsDelete,
                  titleColor: ColorTokens.textError,
                  onTap: () => _confirmDelete(context),
                ),
            ],
          ),
          Center(
            child: Text(
              l10n.settingsVersion(version),
              style: text.caption.copyWith(color: ColorTokens.textSecondary),
            ),
          ),
        ],
        bottomBar: AppBottomBar(
          current: NavTab.settings,
          homeLabel: l10n.navHome,
          playLabel: l10n.navPlay,
          settingsLabel: l10n.navSettings,
          onHome: onHome,
          onPlay: onPlay,
          onSettings: () {},
          settingsBadgeLabel: offlineUpdateAvailable
              ? l10n.packsUpdateAvailable
              : null,
        ),
      ),
    );
  }
}
