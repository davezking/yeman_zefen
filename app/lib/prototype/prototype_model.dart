import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mock_data.dart';
import 'models.dart';

/// The prototype's whole state, on mock data. It stands in for the services
/// that Phase 4 wires to the screens, and exists only here: no screen imports it.
class PrototypeModel extends ChangeNotifier {
  PrototypeModel({
    this.languageCode = 'en',
    this.user = mockGuest,
    this.connection = Connection.wifi,
    List<PackItem> packs = mockPacks,
    bool resumeDownloads = true,
  }) : packs = List.of(packs) {
    // The mock data has a download under way: keep it moving. Tests that do
    // not want timers running pass false.
    if (resumeDownloads) {
      for (final p in this.packs) {
        if (p.status == PackStatus.downloading) _startTicker(p.id);
      }
    }
  }

  String languageCode;
  bool soundOn = true;
  bool hapticsOn = true;
  UserInfo user;
  Connection connection;
  PlaySettings quickPlay = const PlaySettings(
    generationId: EraId.eighties,
    mode: GameMode.intro,
  );

  bool wifiOnly = true;
  bool mobilePrefetch = true;
  CacheUsage cache = mockCache;
  List<PackItem> packs;

  /// What the next download does: complete (null) or fail in this way.
  PackProblem? failNextDownload;

  final _tickers = <String, Timer>{};

  bool get offline => connection == Connection.offline;
  bool get hasDownloadedPacks => packs.any((p) => p.isOnPhone);
  int get installedPackCount => packs.where((p) => p.isOnPhone).length;
  int get installedSizeMb =>
      packs.where((p) => p.isOnPhone).fold(0, (sum, p) => sum + p.sizeMb);
  bool get updateAvailable =>
      packs.any((p) => p.status == PackStatus.updateAvailable);

  /// Eras with too few songs on the phone to play, when there is no connection.
  Set<int> get disabledEras {
    if (!offline) return const {};
    const minSongs = 10;
    final perEra = {...mockBuiltInSongsByEra};
    for (final p in packs.where((p) => p.isOnPhone)) {
      perEra[p.generationId] = (perEra[p.generationId] ?? 0) + p.songCount;
    }
    return {
      for (final id in EraId.ordered)
        if (id != EraId.all && (perEra[id] ?? 0) < minSongs) id,
    };
  }

  /// The chosen era and genre have no songs together (the mock catalog is small).
  bool tooFewSongsFor(PlaySettings s) {
    if (s.genre == Genre.any || s.generationId == EraId.all) return false;
    return !mockTracks.any(
      (t) => t.generationId == s.generationId && t.genre == s.genre,
    );
  }

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  void setPack(String id, PackItem Function(PackItem) change) {
    packs = [for (final p in packs) p.id == id ? change(p) : p];
    notifyListeners();
  }

  /// Downloads a pack, or the update of one already on the phone.
  void download(String id) {
    final problem = failNextDownload;
    failNextDownload = null;
    setPack(
      id,
      (p) => p.copyWith(
        status: PackStatus.downloading,
        progress: 0,
        updating: p.isOnPhone,
        clearProblem: true,
      ),
    );
    _startTicker(id, failWith: problem);
  }

  /// Stops a download. An update goes back to waiting; the installed version stays.
  void cancel(String id) {
    _tickers.remove(id)?.cancel();
    setPack(
      id,
      (p) => p.updating ? _backToUpdateAvailable(p) : _notInstalled(p),
    );
  }

  void remove(String id) {
    _tickers.remove(id)?.cancel();
    setPack(id, _notInstalled);
  }

  PackItem _notInstalled(PackItem p) => p.copyWith(
    status: PackStatus.notInstalled,
    clearProgress: true,
    clearProblem: true,
    updating: false,
  );

  PackItem _backToUpdateAvailable(PackItem p) => p.copyWith(
    status: PackStatus.updateAvailable,
    clearProgress: true,
    clearProblem: true,
    updating: false,
  );

  void _startTicker(String id, {PackProblem? failWith}) {
    _tickers.remove(id)?.cancel();
    _tickers[id] = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      final pack = packs.firstWhere((p) => p.id == id);
      final next = (pack.progress ?? 0) + 0.05;
      if (failWith != null && next >= 0.3) {
        timer.cancel();
        _tickers.remove(id);
        setPack(
          id,
          (p) => p.copyWith(
            status: PackStatus.failed,
            problem: failWith,
            shortfallMb: failWith == PackProblem.storageFull ? 8 : null,
          ),
        );
        // A corrupt file is fetched again without asking, as the error says.
        if (failWith == PackProblem.corrupt) {
          _tickers[id] = Timer(const Duration(seconds: 2), () {
            _tickers.remove(id);
            download(id);
          });
        }
      } else if (next >= 1) {
        timer.cancel();
        _tickers.remove(id);
        setPack(
          id,
          (p) => p.copyWith(status: PackStatus.verifying, progress: 1),
        );
        _tickers[id] = Timer(const Duration(seconds: 1), () {
          _tickers.remove(id);
          setPack(
            id,
            (p) => p.copyWith(
              status: PackStatus.installed,
              clearProgress: true,
              clearUpdate: true,
            ),
          );
        });
      } else {
        setPack(id, (p) => p.copyWith(progress: next));
      }
    });
  }

  @override
  void dispose() {
    for (final t in _tickers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
