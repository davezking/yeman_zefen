import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yeman_zefen/features/packs/data/clip_downloader.dart';
import 'package:yeman_zefen/features/packs/data/pack_manifest.dart';

/// Deterministic fake clip bytes for a url.
List<int> bodyFor(String url) => utf8.encode('audio:$url');

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String clipUrl(int trackId, String type, int version) =>
    'https://cdn.test/clips/$trackId/$type-v$version.mp3';

Map<String, dynamic> _clip(int trackId, String type, int version) {
  final url = clipUrl(trackId, type, version);
  final body = bodyFor(url);
  return {
    'url': url,
    'sha256': sha256Hex(body),
    'bytes': body.length,
    'lengthMs': 10000,
  };
}

/// A valid manifest as a JSON map. Tests mutate it to make invalid ones.
Map<String, dynamic> manifestMap({
  String slug = 'golden-era',
  int version = 1,
  int tracks = 3,
}) {
  final list = <Map<String, dynamic>>[
    for (var id = 1; id <= tracks; id++)
      {
        'id': id,
        'titleAm': 'ዘፈን $id',
        'titleLatin': 'Song $id',
        'artistId': 7,
        'artistAm': 'ድምፃዊ',
        'artistLatin': 'Artist',
        'generationId': 2,
        'genreIds': [1],
        'releaseYear': 1975,
        'clips': {
          'intro': _clip(id, 'intro', version),
          'middle': _clip(id, 'middle', version),
        },
      },
  ];
  var total = 0;
  for (final track in list) {
    final clips = track['clips']! as Map<String, dynamic>;
    for (final clip in clips.values) {
      total += (clip as Map<String, dynamic>)['bytes']! as int;
    }
  }
  return {
    'schema': 1,
    'slug': slug,
    'version': version,
    'publishedAt': 1760000000000,
    'names': {'am': 'ወርቃማ ዘመን', 'en': 'Golden era'},
    'generationId': 2,
    'genreId': null,
    'tracks': list,
    'totalBytes': total,
  };
}

String manifestJson({String slug = 'golden-era', int version = 1, int tracks = 3}) =>
    jsonEncode(manifestMap(slug: slug, version: version, tracks: tracks));

PackManifest manifestOf(String json) => PackManifest.parse(json);

/// Serves [bodyFor] bytes by url. Can serve corrupt bytes or fail for chosen urls.
class FakeClipDownloader implements ClipDownloader {
  FakeClipDownloader(this.baseDir);

  final Directory baseDir;

  /// url -> how many downloads of it return wrong bytes before it serves the right ones.
  final corruptTimes = <String, int>{};

  /// urls whose download fails, like a lost connection.
  final failing = <String>{};

  /// urls whose download fails because the phone is full.
  final noSpace = <String>{};

  final calls = <String>[];
  var running = 0;
  var maxRunning = 0;

  /// The group and Wi-Fi rule each url was downloaded with.
  final groups = <String, String?>{};
  final wifiOnly = <String, bool>{};

  /// While set, downloads wait for it, unless their group is cancelled first.
  Completer<void>? hold;
  final cancelledGroups = <String>[];
  final _waiting = <String?, List<Completer<void>>>{};

  @override
  Future<void> cancelGroup(String group) async {
    cancelledGroups.add(group);
    for (final c in _waiting.remove(group) ?? const <Completer<void>>[]) {
      if (!c.isCompleted) c.completeError(const ClipDownloadException('canceled'));
    }
  }

  @override
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
    String? group,
    bool wifiOnly = false,
  }) async {
    calls.add(url);
    groups[url] = group;
    this.wifiOnly[url] = wifiOnly;
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      // Yield so concurrent downloads overlap and the parallelism limit is observable.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final held = hold;
      if (held != null) {
        final waiter = Completer<void>();
        (_waiting[group] ??= []).add(waiter);
        unawaited(held.future.then((_) {
          if (!waiter.isCompleted) waiter.complete();
        }));
        await waiter.future;
      }
      if (failing.contains(url)) {
        throw const ClipDownloadException('connection lost');
      }
      if (noSpace.contains(url)) {
        throw const ClipDownloadException('no space', noSpace: true);
      }
      var body = bodyFor(url);
      final remaining = corruptTimes[url] ?? 0;
      if (remaining > 0) {
        corruptTimes[url] = remaining - 1;
        body = [...body]..[0] ^= 0xff;
      }
      final file = File(p.join(baseDir.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(body);
      onProgress(1);
    } finally {
      running--;
    }
  }
}
