import 'package:connectivity_plus/connectivity_plus.dart';

/// What the phone is connected to, as far as clip downloads care.
enum NetworkKind {
  none,

  /// Wi-Fi, Ethernet or anything that is not metered mobile data.
  unmetered,

  /// Only mobile data.
  cellular;

  static NetworkKind of(List<ConnectivityResult> results) {
    final usable = results.where((r) => r != ConnectivityResult.none).toList();
    if (usable.isEmpty) return none;
    return usable.every((r) => r == ConnectivityResult.mobile) ? cellular : unmetered;
  }
}

Future<NetworkKind> currentNetworkKind() async => NetworkKind.of(await Connectivity().checkConnectivity());
