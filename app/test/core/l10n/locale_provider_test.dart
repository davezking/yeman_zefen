import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/core/l10n/locale_provider.dart';

class _Store implements LocaleStore {
  _Store([this.saved]);
  Locale? saved;
  var writes = 0;
  Object? failWith;

  @override
  Future<Locale?> read() async {
    if (failWith != null) throw failWith!;
    return saved;
  }

  @override
  Future<void> write(Locale locale) async {
    if (failWith != null) throw failWith!;
    writes++;
    saved = locale;
  }
}

ProviderContainer _container({required Locale device, LocaleStore? store}) {
  final container = ProviderContainer(
    overrides: [
      deviceLocaleProvider.overrideWithBuild((ref, _) => device),
      localeStoreProvider.overrideWithValue(store ?? _Store()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the default', () {
    test('is Amharic when the device language is Amharic', () {
      expect(_container(device: const Locale('am', 'ET')).read(localeProvider), amharic);
      expect(_container(device: const Locale('am')).read(localeProvider), amharic);
    });

    test('is English for every other device language', () {
      for (final device in [const Locale('en', 'US'), const Locale('fr'), const Locale('ti', 'ET'), const Locale('om')]) {
        expect(_container(device: device).read(localeProvider), english, reason: '$device');
      }
    });
  });

  group('choosing a language', () {
    test('switches at once and saves the choice', () async {
      final store = _Store();
      final container = _container(device: const Locale('en'), store: store);
      final seen = <Locale>[];
      container.listen(localeProvider, (_, next) => seen.add(next));

      await container.read(localeChoiceProvider.notifier).choose(amharic);

      expect(container.read(localeProvider), amharic);
      expect(seen, [amharic]);
      expect(store.saved, amharic);
    });

    test('keeps the choice over the device language', () async {
      final container = _container(device: const Locale('en'));
      await container.read(localeChoiceProvider.notifier).choose(amharic);
      await container.read(localeChoiceProvider.notifier).choose(english);
      expect(container.read(localeProvider), english);
    });

    test('a region or an unsupported language is stored as one of the two languages', () async {
      final store = _Store();
      final container = _container(device: const Locale('en'), store: store);
      await container.read(localeChoiceProvider.notifier).choose(const Locale('am', 'ET'));
      expect(container.read(localeProvider), amharic);
      await container.read(localeChoiceProvider.notifier).choose(const Locale('fr'));
      expect(container.read(localeProvider), english);
      expect(store.saved, english);
    });

    test('still switches when the choice cannot be saved', () async {
      final store = _Store()..failWith = StateError('disk full');
      final container = _container(device: const Locale('en'), store: store);
      await container.read(localeChoiceProvider.notifier).choose(amharic);
      expect(container.read(localeProvider), amharic);
    });
  });

  group('the saved choice', () {
    test('wins over the device language once loaded', () async {
      final container = _container(device: const Locale('en'), store: _Store(amharic));
      await primeLocale(container);
      expect(container.read(localeProvider), amharic);
    });

    test('is English even on an Amharic device when the player chose English', () async {
      final container = _container(device: const Locale('am'), store: _Store(english));
      await primeLocale(container);
      expect(container.read(localeProvider), english);
    });

    test('with nothing saved the device language stays', () async {
      final container = _container(device: const Locale('am'), store: _Store());
      await primeLocale(container);
      expect(container.read(localeProvider), amharic);
    });

    test('an unreadable store leaves the device language', () async {
      final container = _container(device: const Locale('am'), store: _Store()..failWith = StateError('locked'));
      await primeLocale(container);
      expect(container.read(localeProvider), amharic);
    });

    test('survives a restart: a new container reads what the last one saved', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);

      Future<Locale> launch() async {
        final container = ProviderContainer(
          overrides: [
            deviceLocaleProvider.overrideWithBuild((ref, _) => const Locale('en')),
            localeStoreProvider.overrideWithValue(DbLocaleStore(db)),
          ],
        );
        addTearDown(container.dispose);
        await primeLocale(container);
        return container.read(localeProvider);
      }

      expect(await launch(), english);
      final first = ProviderContainer(
        overrides: [
          deviceLocaleProvider.overrideWithBuild((ref, _) => const Locale('en')),
          localeStoreProvider.overrideWithValue(DbLocaleStore(db)),
        ],
      );
      addTearDown(first.dispose);
      await first.read(localeChoiceProvider.notifier).choose(amharic);

      expect(await launch(), amharic);
    });
  });

  group('a change of the device language', () {
    testWidgets('is followed while the player has not chosen', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final container = ProviderContainer(overrides: [localeStoreProvider.overrideWithValue(_Store())]);
      addTearDown(container.dispose);
      expect(container.read(localeProvider), english);

      tester.platformDispatcher.localeTestValue = const Locale('am', 'ET');
      await tester.pump();
      expect(container.read(localeProvider), amharic);
    });

    testWidgets('does not undo the player\'s choice', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final container = ProviderContainer(overrides: [localeStoreProvider.overrideWithValue(_Store())]);
      addTearDown(container.dispose);
      await container.read(localeChoiceProvider.notifier).choose(english);

      tester.platformDispatcher.localeTestValue = const Locale('am', 'ET');
      await tester.pump();
      expect(container.read(deviceLocaleProvider), const Locale('am', 'ET'));
      expect(container.read(localeProvider), english);
    });
  });

  group('DbLocaleStore', () {
    late AppDb db;
    late DbLocaleStore store;

    setUp(() {
      db = AppDb(NativeDatabase.memory());
      store = DbLocaleStore(db);
    });
    tearDown(() => db.close());

    test('has no choice at first', () async => expect(await store.read(), isNull));

    test('writes over the earlier choice', () async {
      await store.write(amharic);
      await store.write(english);
      expect(await store.read(), english);
      expect(await db.select(db.appSettings).get(), hasLength(1));
    });

    test('ignores a stored value that is not a supported language', () async {
      await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'locale', value: 'xx'));
      expect(await store.read(), isNull);
    });
  });
}
