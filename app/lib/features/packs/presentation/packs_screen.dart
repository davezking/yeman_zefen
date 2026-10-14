import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final listings = ref.watch(packListingsProvider);
    final installed = ref.watch(installedVersionsProvider).asData?.value ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Song packs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
                const Text('Could not load the packs. Check your connection.', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('$e', key: const Key('packs-error'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(packListingsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (packs) => packs.isEmpty
            ? const Center(child: Text('No packs are published yet.'))
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
    setState(() => _working = true);
    try {
      await ref.read(packServiceProvider).install(widget.pack);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Install failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final installed = widget.installedVersion;
    final hasUpdate = isUpdateAvailable(installedVersion: installed, listedVersion: pack.version);
    final upToDate = installed != null && !hasUpdate;
    final progress = ref.watch(packInstallProgressProvider(pack.slug)).asData?.value;
    final installing = _working && progress != null && !progress.isTerminal;

    final label = upToDate
        ? 'Installed'
        : hasUpdate
            ? 'Update'
            : 'Install';

    return ListTile(
      title: Text(pack.nameAm == pack.nameEn ? pack.nameEn : '${pack.nameAm}\n${pack.nameEn}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pack.trackCount} songs · ${_megabytes(pack.totalBytes)} · v${pack.version}'
            '${installed == null ? '' : ' (installed v$installed)'}',
          ),
          if (installing) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              key: const Key('install-progress'),
              value: progress.bytesTotal == 0 ? null : progress.bytesDone / progress.bytesTotal,
            ),
            const SizedBox(height: 4),
            Text(_describe(progress), key: const Key('install-status')),
          ],
        ],
      ),
      isThreeLine: installing,
      trailing: FilledButton(
        onPressed: upToDate || _working ? null : _install,
        child: Text(_working ? 'Installing' : label),
      ),
    );
  }

  static String _megabytes(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _describe(PackInstallProgress p) {
    final state = switch (p.state) {
      PackInstallState.queued => 'Waiting',
      PackInstallState.downloading => 'Downloading',
      PackInstallState.verifying => 'Checking',
      PackInstallState.installed => 'Installed',
      PackInstallState.failed => 'Failed',
    };
    return '$state ${p.filesDone}/${p.filesTotal} files';
  }
}
