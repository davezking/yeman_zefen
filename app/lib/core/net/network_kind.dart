import 'package:connectivity_plus/connectivity_plus.dart';

/// What the phone is connected to, as far as clip downloads care.
enum NetworkKind {
  none,

  /// Wi-Fi, Ethernet or anything that is not metered mobile data.
  unmetered,

  /// Only mobile data.
  cellular;

  /// Wi-Fi or Ethernet makes the connection unmetered. Otherwise mobile data makes it cellular,
  /// whatever else is listed: a VPN, Bluetooth or `other` runs over the mobile link then, so a
  /// VPN on 4G still counts as mobile data for the data saver.
  static NetworkKind of(List<ConnectivityResult> results) {
    if (results.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet)) return unmetered;
    if (results.contains(ConnectivityResult.mobile)) return cellular;
    return results.any((r) => r != ConnectivityResult.none) ? unmetered : none;
  }
}

Future<NetworkKind> currentNetworkKind() async => NetworkKind.of(await Connectivity().checkConnectivity());

/// What the phone is connected to, each time that changes.
Stream<NetworkKind> networkKindChanges() => Connectivity().onConnectivityChanged.map(NetworkKind.of);
