import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';
import '../../packs/domain/pack_update.dart';
import '../../packs/data/packs_api.dart';
import '../../packs/data/packs_providers.dart';

/// A yes-or-no setting, saved in `app_settings` under [key]. Until it is loaded, and when it was
/// never chosen, it is [fallback].
abstract class FlagSettingNotifier extends Notifier<bool> {
  String get key;
  bool get fallback;

  var _chosen = false;

  @override
  bool build() {
    unawaited(_load());
    return fallback;
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDbProvider);
      final row = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row == null || _chosen) return;
      state = row.value == '1';
    } catch (_) {
      // Unreadable: the fallback stays.
    }
  }

  void set(bool on) {
    _chosen = true;
    state = on;
    unawaited(_save(on));
  }

  Future<void> _save(bool on) async {
    try {
      final db = ref.read(appDbProvider);
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: on ? '1' : '0'),
          );
    } catch (_) {}
  }
}

class SoundNotifier extends FlagSettingNotifier {
  @override
  String get key => 'sound';
  @override
  bool get fallback => true;
}

class HapticsNotifier extends FlagSettingNotifier {
  @override
  String get key => 'haptics';
  @override
  bool get fallback => true;
}

final soundOnProvider = NotifierProvider<SoundNotifier, bool>(
  SoundNotifier.new,
);
final hapticsOnProvider = NotifierProvider<HapticsNotifier, bool>(
  HapticsNotifier.new,
);

/// What is installed on the phone, for the "Offline play" row.
class InstalledPacksSummary {
  const InstalledPacksSummary({required this.count, required this.bytes});
  final int count;
  final int bytes;

  /// The size in whole megabytes, rounded up so a small pack never shows 0 MB.
  int get megabytes => (bytes + 1024 * 1024 - 1) ~/ (1024 * 1024);
}

final installedPacksSummaryProvider = StreamProvider<InstalledPacksSummary>((
  ref,
) {
  final db = ref.watch(appDbProvider);
  return db
      .select(db.installedPacks)
      .watch()
      .map(
        (rows) => InstalledPacksSummary(
          count: rows.length,
          bytes: rows.fold(0, (sum, r) => sum + r.totalBytes),
        ),
      );
});

/// True when a pack on the listing is newer than the one installed. Offline, or when the list
/// cannot be fetched, there is no badge.
final packUpdateAvailableProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final List<PackListing> listings;
  try {
    listings = await ref.watch(packListingsProvider.future);
  } catch (_) {
    return false;
  }
  final installed = await ref.watch(installedVersionsProvider.future);
  return listings.any(
    (l) => isUpdateAvailable(
      installedVersion: installed[l.slug],
      listedVersion: l.version,
    ),
  );
});
