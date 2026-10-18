import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';
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

/// The language the device reports. It follows a change of the phone's language while the app
/// runs, so a player who never chose one keeps matching the device. A provider so tests can pick one.
final deviceLocaleProvider = NotifierProvider<DeviceLocale, Locale>(DeviceLocale.new);

class DeviceLocale extends Notifier<Locale> with WidgetsBindingObserver {
  @override
  Locale build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.platformDispatcher.locale;
  }

  @override
  void didChangeLocales(List<Locale>? locales) => state = WidgetsBinding.instance.platformDispatcher.locale;
}

/// The language the player chose, or null until they choose one. Kept apart from [localeProvider]
/// because a notifier is rebuilt from scratch whenever its provider rebuilds: this one watches
/// nothing, so the choice survives a change of the device language.
final localeChoiceProvider = NotifierProvider<LocaleChoice, Locale?>(LocaleChoice.new);

class LocaleChoice extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  /// Applies the saved choice (null: none yet). Called before the first frame, so the app never
  /// shows the device language first and then flips.
  void restore(Locale? saved) => state = saved == null ? null : localeForDevice(saved);

  /// Switches the language now and saves the choice. A failed save is logged: the switch stays,
  /// and the language reverts to the device's only on the next launch.
  Future<void> choose(Locale locale) async {
    final next = localeForDevice(locale);
    state = next;
    try {
      await ref.read(localeStoreProvider).write(next);
    } catch (e, st) {
      developer.log('language choice not saved', name: 'locale', error: e, stackTrace: st);
    }
  }
}

/// The UI language: the player's choice, else the device's. Changing either rebuilds the app in the
/// new language at once, with no restart.
final localeProvider = Provider<Locale>(
  (ref) => ref.watch(localeChoiceProvider) ?? localeForDevice(ref.watch(deviceLocaleProvider)),
);

/// Loads the saved language into [container] (read in main.dart before `runApp`).
Future<void> primeLocale(ProviderContainer container) async {
  try {
    container.read(localeChoiceProvider.notifier).restore(await container.read(localeStoreProvider).read());
  } catch (e, st) {
    developer.log('saved language not loaded', name: 'locale', error: e, stackTrace: st);
  }
}
