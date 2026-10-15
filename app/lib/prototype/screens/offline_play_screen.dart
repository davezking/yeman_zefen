import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../core/theme/app_text.dart';
import '../../core/theme/theme_context.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/app_localizations.dart';
import '../models.dart';

/// Settings › Offline play: the two data toggles, what is on the phone (the
/// built-in songs, downloaded packs, the clip cache) and the packs available
/// to download. Every state of a pack row is a [PackItem.status].
///
/// Dialogs (remove a pack, download on mobile data) are shown here; what
/// happens after the player confirms is for the callbacks.
class OfflinePlayScreen extends StatelessWidget {
  const OfflinePlayScreen({
    super.key,
    required this.wifiOnly,
    required this.mobilePrefetch,
    required this.cache,
    required this.builtInSongCount,
    required this.packs,
    required this.connection,
    required this.onBack,
    required this.onWifiOnly,
    required this.onMobilePrefetch,
    required this.onClearCache,
    required this.onDownload,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
    this.loadingPacks = false,
  });

  /// The list of packs to download is still loading: rows of skeletons.
  final bool loadingPacks;
  final bool wifiOnly;
  final bool mobilePrefetch;
  final CacheUsage cache;
  final int builtInSongCount;
  final List<PackItem> packs;
  final Connection connection;

  final VoidCallback onBack;
  final ValueChanged<bool> onWifiOnly;
  final ValueChanged<bool> onMobilePrefetch;
  final VoidCallback onClearCache;

  /// Download or update the pack with this id (after the mobile-data question).
  final ValueChanged<String> onDownload;
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onRetry;

  /// Remove the pack with this id (after the confirmation).
  final ValueChanged<String> onRemove;

  /// Starts [start] for [pack] (a download, an update or a retry), asking
  /// first when it would use mobile data while "Wi-Fi only" is on.
  Future<void> _download(
    BuildContext context,
    PackItem pack,
    ValueChanged<String> start,
  ) async {
    if (connection == Connection.mobile && wifiOnly) {
      final l10n = AppLocalizations.of(context);
      final go = await showAppDialog(
        context,
        title: l10n.packsMobileDataTitle,
        body: l10n.packsMobileDataBody(pack.downloadSizeMb),
        confirmLabel: l10n.packsMobileDataConfirm,
        cancelLabel: l10n.packsMobileDataWait,
      );
      if (go != true) return;
    }
    start(pack.id);
  }

  Future<void> _remove(BuildContext context, PackItem pack) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final sure = await showAppDialog(
      context,
      title: l10n.packsRemove,
      body: l10n.packsRemoveConfirm(pack.name(locale)),
      confirmLabel: l10n.packsRemove,
      cancelLabel: l10n.packsCancel,
    );
    if (sure == true) onRemove(pack.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final offline = connection == Connection.offline;
    final heading = AppTextStyles.withWeight(text.label, FontWeight.w800);

    final onPhone = packs.where((p) => p.isOnPhone).toList();
    final available = packs.where((p) => !p.isOnPhone).toList();

    return Scaffold(
      body: HeroScaffold(
        denseText: true,
        heroRadius: RadiusTokens.heroDense,
        heroPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n18,
          SpacingTokens.n12,
          SpacingTokens.n18,
          SpacingTokens.n20,
        ),
        bodyPadding: const EdgeInsets.fromLTRB(
          SpacingTokens.n16,
          SpacingTokens.n24,
          SpacingTokens.n16,
          SpacingTokens.n16,
        ),
        bodyGap: SpacingTokens.n10,
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppBackButton(onPressed: onBack, semanticLabel: l10n.navBack),
                const SizedBox(width: SpacingTokens.n12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.packsTitle, style: text.titleSmall),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.n10),
            Text(
              l10n.packsIntro,
              style: AppTextStyles.withWeight(
                text.label,
                FontWeight.w600,
              ).copyWith(color: ColorTokens.textOnHero),
            ),
          ],
        ),
        body: [
          SettingsGroup(
            children: [
              SettingsRow.toggle(
                title: l10n.packsWifiOnly,
                value: wifiOnly,
                onChanged: onWifiOnly,
              ),
              SettingsRow.toggle(
                title: l10n.packsMobilePrefetch,
                subtitle: l10n.packsMobilePrefetchHelp,
                value: mobilePrefetch,
                onChanged: onMobilePrefetch,
              ),
            ],
          ),
          _OnPhoneHeader(
            title: l10n.packsOnPhone,
            cache: l10n.packsCache(cache.usedMb),
            clearLabel: l10n.packsClearCache,
            onClear: onClearCache,
          ),
          PackCard(
            name: l10n.packsBuiltIn,
            meta: l10n.packsBuiltInMeta(builtInSongCount),
            status: PackStatus.builtIn,
            statusLabel: l10n.packsAlways,
          ),
          for (final pack in onPhone)
            // Only a pack at rest can be removed; one being updated is cancelled.
            pack.status == PackStatus.installed ||
                    pack.status == PackStatus.updateAvailable
                ? _RemovablePack(
                    id: pack.id,
                    label: l10n.packsRemove,
                    onRemove: () => _remove(context, pack),
                    child: _card(context, pack),
                  )
                : _card(context, pack),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(
                top: SpacingTokens.n4,
                left: SpacingTokens.n2,
              ),
              child: Text(l10n.packsAvailable, style: heading),
            ),
          ),
          if (offline)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.packsOffline,
                style: text.caption.copyWith(color: ColorTokens.textSecondary),
              ),
            ),
          if (loadingPacks) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.loadingGeneric,
                style: text.caption.copyWith(color: ColorTokens.textSecondary),
              ),
            ),
            SkeletonDelay(
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(height: SpacingTokens.n10),
                    const _PackSkeleton(),
                  ],
                ],
              ),
            ),
          ] else
            for (final pack in available) _card(context, pack),
        ],
      ),
    );
  }

  /// One pack row, in whatever state the pack is in.
  Widget _card(BuildContext context, PackItem pack) {
    final l10n = AppLocalizations.of(context);
    final offline = connection == Connection.offline;
    final String statusLabel;
    switch (pack.status) {
      case PackStatus.installed:
        statusLabel = l10n.packsDownloaded;
      case PackStatus.updateAvailable:
        statusLabel = l10n.packsUpdateAvailable;
      default:
        statusLabel = l10n.packsVerifying;
    }
    return PackCard(
      name: pack.name(Localizations.localeOf(context)),
      meta: _meta(l10n, pack),
      status: pack.status,
      generationId: pack.generationId,
      progress: pack.progress,
      statusLabel: statusLabel,
      actionLabel: pack.status == PackStatus.updateAvailable
          ? l10n.packsUpdate(pack.downloadSizeMb)
          : l10n.packsDownload,
      cancelLabel: l10n.packsCancel,
      errorMessage: _errorMessage(l10n, pack),
      // A corrupt download is fetched again by itself: nothing to press.
      retryLabel: pack.problem == PackProblem.corrupt ? null : l10n.errorRetry,
      onAction: offline ? null : () => _download(context, pack, onDownload),
      onCancel: () => onCancel(pack.id),
      onRetry: offline ? null : () => _download(context, pack, onRetry),
    );
  }

  /// "40 songs · 12 MB", with "42% · " in front while downloading. An update
  /// shows the size of the update.
  String _meta(AppLocalizations l10n, PackItem pack) {
    final size = pack.updating ? pack.downloadSizeMb : pack.sizeMb;
    final base = '${l10n.packsSongs(pack.songCount)} · ${l10n.packsSize(size)}';
    if (pack.status == PackStatus.downloading && pack.progress != null) {
      final percent = (pack.progress! * 100).round();
      return '${l10n.packsProgress(percent)} · $base';
    }
    return base;
  }

  String _errorMessage(AppLocalizations l10n, PackItem pack) =>
      switch (pack.problem) {
        PackProblem.corrupt => l10n.errorPackCorrupt,
        PackProblem.storageFull => l10n.packsStorageFull(pack.shortfallMb ?? 0),
        _ => l10n.errorDownload,
      };
}

class _OnPhoneHeader extends StatelessWidget {
  const _OnPhoneHeader({
    required this.title,
    required this.cache,
    required this.clearLabel,
    required this.onClear,
  });

  final String title;
  final String cache;
  final String clearLabel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.only(top: SpacingTokens.n4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: SpacingTokens.n8,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.withWeight(text.label, FontWeight.w800),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cache,
                style: text.caption.copyWith(color: ColorTokens.textSecondary),
              ),
              const SizedBox(width: SpacingTokens.n8),
              SecondaryButton(
                label: clearLabel,
                small: true,
                onPressed: onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A downloaded pack that can be removed by swiping it away or long-pressing
/// it, and by a screen reader's custom action. Swiping only asks: the row
/// stays until the confirmation is answered and the data changes.
class _RemovablePack extends StatelessWidget {
  const _RemovablePack({
    required this.id,
    required this.label,
    required this.onRemove,
    required this.child,
  });

  /// The pack's id: what keeps the swipe state with the right row.
  final String id;
  final String label;
  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: label): onRemove},
      child: GestureDetector(
        onLongPress: onRemove,
        child: Dismissible(
          key: ValueKey(id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            onRemove();
            return false;
          },
          background: DecoratedBox(
            decoration: BoxDecoration(
              color: ColorTokens.surfaceErrorCard,
              borderRadius: BorderRadius.circular(RadiusTokens.card),
            ),
            child: const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: SpacingTokens.n16),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: SizeTokens.iconLarge,
                  color: ColorTokens.textError,
                ),
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The shape of a pack row while the list loads.
class _PackSkeleton extends StatelessWidget {
  const _PackSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorTokens.surfaceCard,
        borderRadius: BorderRadius.circular(RadiusTokens.card),
        boxShadow: ElevationTokens.card,
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SpacingTokens.n12,
          vertical: SpacingTokens.n10,
        ),
        child: Row(
          children: [
            SkeletonBox(
              width: SizeTokens.iconTile,
              height: SizeTokens.iconTile,
              radius: RadiusTokens.small,
            ),
            SizedBox(width: SpacingTokens.n12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: SizeTokens.skeletonLine),
                  SizedBox(height: SpacingTokens.n8),
                  SkeletonBox(
                    width: SizeTokens.playButtonMinWidth,
                    height: SizeTokens.skeletonLine,
                  ),
                ],
              ),
            ),
            SizedBox(width: SpacingTokens.n32),
            SkeletonBox(
              width: SizeTokens.modeIconTile,
              height: SizeTokens.smallButtonMinHeight,
              radius: RadiusTokens.small,
            ),
          ],
        ),
      ),
    );
  }
}
