import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/packs/domain/pack_update.dart';

void main() {
  test('a newer listed version is an update', () {
    expect(isUpdateAvailable(installedVersion: 1, listedVersion: 2), isTrue);
  });

  test('the same version is not an update', () {
    expect(isUpdateAvailable(installedVersion: 2, listedVersion: 2), isFalse);
  });

  test('an older listed version is not an update', () {
    expect(isUpdateAvailable(installedVersion: 3, listedVersion: 2), isFalse);
  });

  test('a pack that is not installed has no update', () {
    expect(isUpdateAvailable(installedVersion: null, listedVersion: 1), isFalse);
  });
}
