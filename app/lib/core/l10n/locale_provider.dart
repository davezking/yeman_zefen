import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';

/// The UI languages (FR-18), by language code.
const amharic = Locale('am');
const english = Locale('en');

/// The UI language for a device that reports [device]: Amharic when the device language is
/// Amharic, English for everything else.
Locale localeForDevice(Locale device) => device.languageCode == 'am' ? amharic : english;

/// The saved language choice, kept between launches.
abstract class LocaleStore {
  /// The language the player chose, or null when they have not (or what is stored is not usable).
  Future<Locale?> read();

  Future<void> write(Locale locale);
}

/// Keeps the choice in the `app_settings` table under `locale`.
class DbLocaleStore implements LocaleStore {
  DbLocaleStore(this.db);

  final AppDb db;
  static const _key = 'locale';

  @override
  Future<Locale?> read() async {
    final row = await (db.select(db.appSettings)..where((t) => t.key.equals(_key))).getSingleOrNull();
    return switch (row?.value) {
      'am' => amharic,
      'en' => english,
      _ => null,
    };
  }

  @override
  Future<void> write(Locale locale) =>
      db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: _key, value: locale.languageCode));
}

final localeStoreProvider = Provider<LocaleStore>((ref) => DbLocaleStore(ref.watch(appDbProvider)));

/// The language the device reports. A provider so tests can pick one.
final deviceLocaleProvider = Provider<Locale>((ref) => PlatformDispatcher.instance.locale);

/// The UI language. It starts from the device and then follows the player's choice, which
/// is saved. Changing it rebuilds the app in the new language at once, with no restart.
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  /// The player's saved choice, once [restore] has loaded it.
  Locale? _chosen;

  @override
  Locale build() => _chosen ?? localeForDevice(ref.watch(deviceLocaleProvider));

  /// Applies the saved choice (null: none yet). Called before the first frame, so the app never
  /// shows the device language first and then flips.
  void restore(Locale? saved) {
    _chosen = saved;
    state = saved ?? localeForDevice(ref.read(deviceLocaleProvider));
  }

  /// Switches the language now and saves the choice. A failed save is logged: the switch stays,
  /// and the language reverts to the device's only on the next launch.
  Future<void> choose(Locale locale) async {
    final next = localeForDevice(locale);
    _chosen = next;
    state = next;
    try {
      await ref.read(localeStoreProvider).write(next);
    } catch (e, st) {
      developer.log('language choice not saved', name: 'locale', error: e, stackTrace: st);
    }
  }
}

/// Loads the saved language into [container] (read in main.dart before `runApp`).
Future<void> primeLocale(ProviderContainer container) async {
  try {
    container.read(localeProvider.notifier).restore(await container.read(localeStoreProvider).read());
  } catch (e, st) {
    developer.log('saved language not loaded', name: 'locale', error: e, stackTrace: st);
  }
}
