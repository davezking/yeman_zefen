import 'package:background_downloader/background_downloader.dart';
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
    await _configure();
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
    if (group != null) (_groups[group] ??= {}).add(task);
    final TaskStatusUpdate result;
    try {
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
