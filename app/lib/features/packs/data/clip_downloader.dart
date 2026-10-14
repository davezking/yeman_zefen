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

/// Production downloader. Uses `background_downloader`, which keeps going
/// while the app is backgrounded, retries on network errors, and waits for a
/// connection instead of failing when the network is off.
class BackgroundClipDownloader implements ClipDownloader {
  BackgroundClipDownloader({FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  /// Call once at startup. Holds queued downloads until a network is available,
  /// so a download that was interrupted by losing the connection resumes on reconnect.
  static Future<void> configure() {
    return FileDownloader().configure(
      globalConfig: [(Config.holdingQueue, Config.whenAble)],
    );
  }

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
      retries: 5,
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
