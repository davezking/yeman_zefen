import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/display_name.dart';
import '../../../l10n/app_localizations.dart';
import '../data/packs_api.dart';
import '../data/packs_providers.dart';
import '../domain/pack_install_progress.dart';
import '../domain/pack_update.dart';

/// Lists the published packs, with an install or update button and progress.
/// Plain widgets: the designed version replaces this in Phase 4.
class PacksScreen extends ConsumerWidget {
  const PacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final listings = ref.watch(packListingsProvider);
    final installed = ref.watch(installedVersionsProvider).asData?.value ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.packsTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(packListingsProvider),
          ),
        ],
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.packsLoadError, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('$e', key: const Key('packs-error'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(packListingsProvider),
                  child: Text(l10n.errorRetry),
                ),
              ],
            ),
          ),
        ),
        data: (packs) => packs.isEmpty
            ? Center(child: Text(l10n.packsNone))
            : ListView.separated(
                itemCount: packs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _PackTile(pack: packs[i], installedVersion: installed[packs[i].slug]),
              ),
      ),
    );
  }
}

class _PackTile extends ConsumerStatefulWidget {
  const _PackTile({required this.pack, required this.installedVersion});

  final PackListing pack;
  final int? installedVersion;

  @override
  ConsumerState<_PackTile> createState() => _PackTileState();
}

class _PackTileState extends ConsumerState<_PackTile> {
  /// True from the tap until the install ends, including fetching the manifest,
  /// which the installer's own progress does not cover.
  var _working = false;

  Future<void> _install() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).errorDownload;
    setState(() => _working = true);
    try {
      await ref.read(packServiceProvider).install(widget.pack);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final pack = widget.pack;
    final installed = widget.installedVersion;
    final hasUpdate = isUpdateAvailable(installedVersion: installed, listedVersion: pack.version);
    final upToDate = installed != null && !hasUpdate;
    final progress = ref.watch(packInstallProgressProvider(pack.slug)).asData?.value;
    final installing = _working && progress != null && !progress.isTerminal;

    final label = upToDate
        ? l10n.packsDownloaded
        : hasUpdate
            ? l10n.packsUpdateButton
            : l10n.packsDownload;

    return ListTile(
      title: Text(DisplayName.of(pack.nameAm, pack.nameEn).of(locale)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            installed == null
                ? l10n.packsMeta(pack.trackCount, _megabytes(pack.totalBytes), pack.version)
                : l10n.packsMetaInstalled(pack.trackCount, _megabytes(pack.totalBytes), pack.version, installed),
          ),
          if (installing) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              key: const Key('install-progress'),
              value: progress.bytesTotal == 0 ? null : progress.bytesDone / progress.bytesTotal,
            ),
            const SizedBox(height: 4),
            Text(_describe(l10n, progress), key: const Key('install-status')),
          ],
        ],
      ),
      isThreeLine: installing,
      trailing: FilledButton(
        onPressed: upToDate || _working ? null : _install,
        child: Text(_working ? l10n.packsInstalling : label),
      ),
    );
  }

  static String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  static String _describe(AppLocalizations l10n, PackInstallProgress p) {
    final state = switch (p.state) {
      PackInstallState.queued => l10n.packsStateWaiting,
      PackInstallState.downloading => l10n.packsStateDownloading,
      PackInstallState.verifying => l10n.packsStateChecking,
      PackInstallState.installed => l10n.packsStateInstalled,
      PackInstallState.failed => l10n.packsStateFailed,
    };
    return l10n.packsFilesProgress(state, p.filesDone, p.filesTotal);
  }
}
