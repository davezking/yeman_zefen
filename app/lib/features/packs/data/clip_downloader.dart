import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class ClipDownloadException implements Exception {
  const ClipDownloadException(this.message, {this.noSpace = false});
  final String message;

  /// The phone did not have room for the file.
  final bool noSpace;

  @override
  String toString() => 'ClipDownloadException: $message';
}

/// Fetches one clip to `relativePath` under the app support directory.
/// Throws [ClipDownloadException] if the download does not finish.
abstract class ClipDownloader {
  /// [group] names the downloads [cancelGroup] can stop together (a pack's). With [wifiOnly]
  /// the download waits for Wi-Fi or another unmetered connection instead of using mobile data.
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
    String? group,
    bool wifiOnly = false,
  });

  /// Stops the downloads of [group] that are queued, running or waiting to retry. They fail
  /// with [ClipDownloadException].
  Future<void> cancelGroup(String group);
}

/// Production downloader, using `background_downloader`, which keeps going
/// while the app is in the background.
///
/// Behaviour this relies on, checked in the plugin's source (9.6.4): on Android
/// a queued download waits for a network connection before it starts, and a
/// failed download is retried up to [retries] times, waiting 1, 2, 4 ... s
/// between tries (about 17 minutes for 10). When the retries run out the
/// install fails, and installing again keeps every file that already verified.
/// iOS has not been checked yet.
class BackgroundClipDownloader implements ClipDownloader {
  BackgroundClipDownloader({FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  /// The plugin's maximum.
  static const retries = 10;

  /// The space, in MB, a download must leave free. Below it the plugin fails the download with
  /// "Insufficient space" instead of filling the phone.
  static const minFreeSpaceMb = 20;

  /// The running downloads of each group, for [cancelGroup].
  final _groups = <String, Set<DownloadTask>>{};

  Future<void>? _configured;

  /// Turns on the plugin's free-space check, once.
  Future<void> _configure() => _configured ??= _downloader
      .configure(globalConfig: (Config.checkAvailableSpace, minFreeSpaceMb))
      .then((_) {}, onError: (Object _) {});

  @override
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
    String? group,
    bool wifiOnly = false,
  }) async {
    final task = DownloadTask(
      url: url,
      directory: p.posix.dirname(relativePath),
      filename: p.posix.basename(relativePath),
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      retries: retries,
      allowPause: true,
      requiresWiFi: wifiOnly,
    );
    // In its group before the first await, so a [cancelGroup] from now on reaches it.
    if (group != null) (_groups[group] ??= {}).add(task);
    final TaskStatusUpdate result;
    try {
      await _configure();
      if (group != null && !(_groups[group]?.contains(task) ?? false)) {
        throw ClipDownloadException('canceled before it started: $url');
      }
      result = await _downloader.download(
        task,
        onProgress: (fraction) {
          // Negative values are status codes from the plugin, not progress.
          if (fraction >= 0) onProgress(fraction.clamp(0.0, 1.0));
        },
      );
    } finally {
      if (group != null) _groups[group]?.remove(task);
    }
    if (result.status != TaskStatus.complete) {
      final exception = result.exception;
      throw ClipDownloadException(
        '${result.status.name} for $url${exception == null ? '' : ': ${exception.description}'}',
        // How the plugin reports its free-space check on Android and iOS.
        noSpace: exception is TaskFileSystemException && exception.description.contains('Insufficient space'),
      );
    }
  }

  @override
  Future<void> cancelGroup(String group) async {
    final tasks = _groups.remove(group);
    if (tasks == null || tasks.isEmpty) return;
    await _downloader.cancelAll(tasks: tasks);
  }
}

/// Downloader for the clips a session streams while it plays: a plain HTTP request that starts at
/// once. [BackgroundClipDownloader] hands each file to the OS scheduler (WorkManager on Android),
/// which can hold a download back for seconds, longer than a round waits for its clip. A session
/// only needs its clips while it is on screen, so it does not need background downloads.
class HttpClipDownloader implements ClipDownloader {
  HttpClipDownloader({required this.supportDirectory, http.Client? client}) : _client = client ?? http.Client();

  final Future<Directory> Function() supportDirectory;
  final http.Client _client;

  /// A clip is a few hundred KB; a connection this slow would not keep up with the game anyway.
  static const timeout = Duration(seconds: 20);

  @override
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
    String? group,
    bool wifiOnly = false,
  }) async {
    final base = await supportDirectory();
    final file = File(p.join(base.path, relativePath));
    final part = File('${file.path}.part');
    try {
      await file.parent.create(recursive: true);
      final response = await _client.send(http.Request('GET', Uri.parse(url))).timeout(timeout);
      if (response.statusCode != 200) {
        throw ClipDownloadException('HTTP ${response.statusCode} for $url');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await response.stream.timeout(timeout).forEach((chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) onProgress((received / total).clamp(0.0, 1.0));
        });
      } finally {
        await sink.close();
      }
      await part.rename(file.path);
    } on ClipDownloadException {
      rethrow;
    } on FileSystemException catch (e) {
      throw ClipDownloadException('could not save $url: ${e.message}', noSpace: e.osError?.errorCode == 28);
    } catch (e) {
      throw ClipDownloadException('failed for $url: $e');
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  /// Session downloads have no groups: they are short and finish on their own.
  @override
  Future<void> cancelGroup(String group) async {}

  void close() => _client.close();
}
