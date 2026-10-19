import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/net/network_kind.dart';

void main() {
  test('Wi-Fi or Ethernet is unmetered, whatever else is listed', () {
    expect(NetworkKind.of([ConnectivityResult.wifi]), NetworkKind.unmetered);
    expect(NetworkKind.of([ConnectivityResult.ethernet]), NetworkKind.unmetered);
    expect(NetworkKind.of([ConnectivityResult.wifi, ConnectivityResult.mobile]), NetworkKind.unmetered);
    expect(NetworkKind.of([ConnectivityResult.wifi, ConnectivityResult.vpn]), NetworkKind.unmetered);
  });

  test('mobile data is cellular, also behind a VPN or with Bluetooth on', () {
    expect(NetworkKind.of([ConnectivityResult.mobile]), NetworkKind.cellular);
    expect(NetworkKind.of([ConnectivityResult.mobile, ConnectivityResult.vpn]), NetworkKind.cellular);
    expect(NetworkKind.of([ConnectivityResult.vpn, ConnectivityResult.mobile]), NetworkKind.cellular);
    expect(NetworkKind.of([ConnectivityResult.mobile, ConnectivityResult.bluetooth]), NetworkKind.cellular);
    expect(NetworkKind.of([ConnectivityResult.mobile, ConnectivityResult.other]), NetworkKind.cellular);
  });

  test('nothing is none; a link of unknown kind counts as unmetered', () {
    expect(NetworkKind.of([ConnectivityResult.none]), NetworkKind.none);
    expect(NetworkKind.of(const []), NetworkKind.none);
    expect(NetworkKind.of([ConnectivityResult.vpn]), NetworkKind.unmetered);
    expect(NetworkKind.of([ConnectivityResult.other]), NetworkKind.unmetered);
  });
}
