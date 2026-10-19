import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_db.dart';
import '../../../core/net/network_kind.dart';
import '../../../prototype/models.dart' as proto;
import '../../packs/application/offline_play.dart';
import '../../packs/data/clip_providers.dart';
import '../../packs/data/packs_providers.dart';
import 'session_controller.dart';
import '../data/game_library.dart';
import '../domain/eras.dart';
import '../domain/game_track.dart';
import '../domain/session_config.dart' as domain;

/// A song counts as playable for an era when a round can ask about it: this many at least, so
/// there are the four options a question needs. Eras below it are disabled in setup.
const minPlayableSongsPerEra = 4;

/// The player's last Play choices, saved in `app_settings` so Play and the Home quick-play line
/// keep them across launches. Genre is not saved: the round engine cannot filter by it yet.
class PlaySetupNotifier extends Notifier<proto.PlaySettings> {
  static const settingKey = 'play_setup';

  var _chosen = false;

  @override
  proto.PlaySettings build() {
    unawaited(_load());
    return const proto.PlaySettings();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDbProvider);
      final row = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals(settingKey))).getSingleOrNull();
      // A choice made while the saved one was loading wins.
      if (row == null || _chosen) return;
      state = _decode(row.value) ?? state;
    } catch (_) {
      // Nothing saved, or unreadable: the defaults stay.
    }
  }

  /// Keeps [settings] as the current choice and saves it. A failed save only loses it on restart.
  void choose(proto.PlaySettings settings) {
    _chosen = true;
    state = settings;
    unawaited(_save(settings));
  }

  Future<void> _save(proto.PlaySettings settings) async {
    try {
      final db = ref.read(appDbProvider);
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: settingKey,
              value: _encode(settings),
            ),
          );
    } catch (_) {}
  }

  static String _encode(proto.PlaySettings s) => jsonEncode({
    'era': s.generationId,
    'mode': s.mode.name,
    'guess': s.guess.name,
    'difficulty': s.difficulty.name,
  });

  static proto.PlaySettings? _decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final era = json['era'];
      if (era is! int || era < 0 || era > proto.EraId.modern) return null;
      return proto.PlaySettings(
        generationId: era,
        mode: proto.GameMode.values.byName(json['mode'] as String),
        guess: proto.GuessTarget.values.byName(json['guess'] as String),
        difficulty: proto.Difficulty.values.byName(
          json['difficulty'] as String,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

final playSetupProvider =
    NotifierProvider<PlaySetupNotifier, proto.PlaySettings>(
      PlaySetupNotifier.new,
    );

/// What the phone is connected to, updated when the connection changes.
final currentNetworkProvider = StreamProvider.autoDispose<NetworkKind>((ref) async* {
  final changes = ref.watch(networkChangesProvider)();
  yield await ref.watch(networkKindProvider)();
  yield* changes;
});

/// Whether clips can be fetched now: on Wi-Fi or another unmetered connection, or on mobile data
/// when the player allows it. Follows connection changes.
final clipAccessProvider = FutureProvider.autoDispose<bool>((ref) async {
  final current = ref.watch(currentNetworkProvider);
  final network = current.hasValue ? current.requireValue : await ref.watch(currentNetworkProvider.future);
  // Counted again when the player changes "Download upcoming songs on mobile data". The value
  // itself is read where it is saved, which is also what the prefetcher goes by.
  ref.watch(mobilePrefetchProvider);
  return switch (network) {
    NetworkKind.unmetered => true,
    NetworkKind.cellular => ref.watch(clipSettingsProvider).prefetchOnMobile(),
    NetworkKind.none => false,
  };
});

/// How many songs a round of one mode can ask about right now.
class PlayableSongs {
  const PlayableSongs({required this.perEra, required this.onDevice});

  /// Playable songs by era id. Key 0 is all eras.
  final Map<int, int> perEra;

  /// Songs whose clip is on the phone, whether or not the connection allows fetching the rest.
  final int onDevice;

  int countFor(int generationId) => perEra[generationId] ?? 0;

  /// The eras that have too few songs to play right now.
  Set<int> get disabledEras => {
    for (final id in proto.EraId.ordered)
      if (id != proto.EraId.all && countFor(id) < minPlayableSongsPerEra) id,
  };

  /// Whether all eras together have too few songs.
  bool get tooFew => countFor(proto.EraId.all) < minPlayableSongsPerEra;
}

/// Counted again whenever the catalog or the clips on the phone change, so a first launch shows
/// the starter songs as soon as they are registered.
final playableSongsProvider = FutureProvider.autoDispose
    .family<PlayableSongs, domain.GameMode>((ref, mode) async {
      ref.watch(clipsChangedProvider);
      try {
        await ref.watch(starterReadyProvider.future);
      } catch (_) {
        // No starter pack: count what is there.
      }
      final base = await ref.watch(supportDirectoryProvider.future);
      final library = await loadGameLibrary(ref.watch(appDbProvider), base);
      final fetchable = await ref.watch(clipAccessProvider.future);
      // Which Era? can only ask about a song that has a known era.
      bool askable(GameTrack t) => mode != domain.GameMode.generation || eraIds.contains(t.generationId);
      final ids = library.playableIds(mode, includeFetchable: fetchable);
      final perEra = <int, int>{proto.EraId.all: 0};
      for (final track in library.tracks) {
        if (!ids.contains(track.id) || !askable(track)) continue;
        perEra[proto.EraId.all] = perEra[proto.EraId.all]! + 1;
        final era = track.generationId;
        if (era != null) perEra[era] = (perEra[era] ?? 0) + 1;
      }
      final onDevice = library.tracks
          .where((t) => askable(t) && library.hasClip(t.id, mode))
          .length;
      return PlayableSongs(perEra: perEra, onDevice: onDevice);
    });

/// The round engine's mode for a chosen mode. Which Era? is the generation-guess mode.
domain.GameMode domainMode(proto.GameMode mode) => switch (mode) {
  proto.GameMode.intro => domain.GameMode.intro,
  proto.GameMode.middle => domain.GameMode.middle,
  proto.GameMode.era => domain.GameMode.generation,
};

/// What a session plays for the choices in [s].
///
/// Which Era? has no era filter (the answer would be the filter) and no question choice, so its
/// sessions are for all eras: they count on the all-eras leaderboards, under generation 0
/// (`docs/scoring.md`). Its clip is always 10 s of the intro, whatever the difficulty says.
domain.SessionConfig sessionConfigFor(proto.PlaySettings s) =>
    domain.SessionConfig(
      mode: domainMode(s.mode),
      difficulty: switch (s.difficulty) {
        proto.Difficulty.easy => domain.Difficulty.easy,
        proto.Difficulty.medium => domain.Difficulty.medium,
        proto.Difficulty.hard => domain.Difficulty.hard,
      },
      generationId: s.mode == proto.GameMode.era ? proto.EraId.all : s.generationId,
      questions: switch (s.guess) {
        proto.GuessTarget.song => domain.QuestionMix.song,
        proto.GuessTarget.artist => domain.QuestionMix.artist,
        proto.GuessTarget.mixed => domain.QuestionMix.mixed,
      },
    );

/// Applies [change] to the saved Play choices.
void updatePlaySetup(
  WidgetRef ref,
  proto.PlaySettings Function(proto.PlaySettings) change,
) {
  ref
      .read(playSetupProvider.notifier)
      .choose(change(ref.read(playSetupProvider)));
}

/// The choices Play uses: [settings], unless its era has too few songs right now, then all eras.
/// [songs] is null while the counts load, and then [settings] is used as it is.
///
/// Which Era? has no era filter and always plays a 10 s clip, so it reads as all eras and Easy
/// (10 s) everywhere: Home's line, the round's chips and the best score's key.
proto.PlaySettings effectivePlaySettings(
  proto.PlaySettings settings,
  PlayableSongs? songs,
) {
  if (settings.mode == proto.GameMode.era) {
    return settings.copyWith(generationId: proto.EraId.all, difficulty: proto.Difficulty.easy);
  }
  if (songs == null || !songs.disabledEras.contains(settings.generationId)) {
    return settings;
  }
  return settings.copyWith(generationId: proto.EraId.all);
}

/// Starts a session with [settings] in the background. The round screen shows it.
void startPlaying(WidgetRef ref, proto.PlaySettings settings) {
  unawaited(
    ref
        .read(sessionControllerProvider.notifier)
        .start(sessionConfigFor(settings)),
  );
}
