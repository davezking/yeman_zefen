import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ads/ads_providers.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../prototype/models.dart' as proto;
import '../../account/data/profile_api.dart';
import '../../account/ui/account_actions.dart';
import '../../account/ui/register_sheet.dart';
import '../../game/application/play_setup.dart';
import '../../packs/application/offline_play.dart';
import '../application/settings_providers.dart';
import 'settings_screen.dart';

/// Settings with the real language, sound, account, offline packs and version. Sign-in opens the
/// register sheet; sign-out and account deletion leave the player a new guest. "Ad privacy
/// choices" opens Google's privacy options form, and shows only where Google requires it.
///
/// About has no page yet.
class SettingsRoute extends ConsumerWidget {
  const SettingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth =
        ref.watch(authStateProvider).asData?.value ?? AuthState.signedOut;
    final registered = auth.hasUid && !auth.isAnonymous;
    final packs = ref.watch(installedPacksSummaryProvider).asData?.value;
    final songs = ref
        .watch(
          playableSongsProvider(domainMode(ref.watch(playSetupProvider).mode)),
        )
        .asData
        ?.value;
    final quick = effectivePlaySettings(ref.watch(playSetupProvider), songs);

    return SettingsScreen(
      languageCode: ref.watch(localeProvider).languageCode,
      soundOn: ref.watch(soundOnProvider),
      hapticsOn: ref.watch(hapticsOnProvider),
      user: registered
          ? proto.UserInfo.signedIn(
              displayName: ref.watch(ownNameProvider).asData?.value ?? '',
            )
          : const proto.UserInfo.guest(),
      offlinePackCount: packs?.count ?? 0,
      offlineSizeMb: packs?.megabytes ?? 0,
      offlineUpdateAvailable: ref.watch(packUpdateAvailableProvider),
      version: ref.watch(appVersionProvider).asData?.value ?? '',
      onLanguage: (code) =>
          ref.read(localeChoiceProvider.notifier).choose(Locale(code)),
      onSound: ref.read(soundOnProvider.notifier).set,
      onHaptics: ref.read(hapticsOnProvider.notifier).set,
      providers: registered ? signInProviders(auth.providers) : const [],
      onSignIn: () => showRegisterSheet(context),
      onSignOut: () => signOut(context, ref),
      onDeleteAccount: () => deleteAccount(context, ref),
      onOfflinePlay: () => context.go('/packs'),
      onAdPrivacy: ref.watch(privacyOptionsRequiredProvider)
          ? () => ref.read(consentServiceProvider).openPrivacyOptions()
          : null,
      onPrivacy: () {
        if (AppConfig.privacyUrl.isEmpty) return;
        launchUrl(
          Uri.parse(AppConfig.privacyUrl),
          mode: LaunchMode.externalApplication,
        );
      },
      onAbout: _notYet,
      onHome: () => context.go('/'),
      onPlay: () {
        startPlaying(ref, quick);
        context.go('/play');
      },
    );
  }
}

void _notYet() {}

/// Firebase provider ids as the account row names them, in a fixed order. Unknown ones are left out.
List<proto.SignInProvider> signInProviders(List<String> ids) => [
  if (ids.contains('apple.com')) proto.SignInProvider.apple,
  if (ids.contains('google.com')) proto.SignInProvider.google,
  if (ids.contains('password')) proto.SignInProvider.email,
];
