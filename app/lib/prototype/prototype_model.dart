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
  }) : packs = List.of(packs);

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

  void download(String id) {
    final problem = failNextDownload;
    failNextDownload = null;
    setPack(
      id,
      (p) => PackItem(
        id: p.id,
        nameAm: p.nameAm,
        nameEn: p.nameEn,
        generationId: p.generationId,
        songCount: p.songCount,
        sizeMb: p.sizeMb,
        status: PackStatus.downloading,
        progress: 0,
        updateSizeMb: p.updateSizeMb,
      ),
    );
    _startTicker(id, failWith: problem);
  }

  void cancel(String id) {
    _tickers.remove(id)?.cancel();
    setPack(
      id,
      (p) => p.copyWith(status: PackStatus.notInstalled, clearProgress: true),
    );
  }

  void remove(String id) {
    _tickers.remove(id)?.cancel();
    setPack(
      id,
      (p) => p.copyWith(status: PackStatus.notInstalled, clearProgress: true),
    );
  }

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
            (p) =>
                p.copyWith(status: PackStatus.installed, clearProgress: true),
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
