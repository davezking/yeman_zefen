import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

class ClipDownloadException implements Exception {
  const ClipDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ClipDownloadException: $message';
}

/// Fetches one clip to `relativePath` under the app support directory.
/// Throws [ClipDownloadException] if the download does not finish.
abstract class ClipDownloader {
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
  });
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

  @override
  Future<void> download({
    required String url,
    required String relativePath,
    required void Function(double fraction) onProgress,
  }) async {
    final task = DownloadTask(
      url: url,
      directory: p.posix.dirname(relativePath),
      filename: p.posix.basename(relativePath),
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      retries: retries,
      allowPause: true,
    );
    final result = await _downloader.download(
      task,
      onProgress: (fraction) {
        // Negative values are status codes from the plugin, not progress.
        if (fraction >= 0) onProgress(fraction.clamp(0.0, 1.0));
      },
    );
    if (result.status != TaskStatus.complete) {
      throw ClipDownloadException('${result.status.name} for $url');
    }
  }
}
