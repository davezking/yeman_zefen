enum PackInstallState { queued, downloading, verifying, installed, failed, cancelled }

/// A snapshot of one pack's install. Byte counts include verified files and the
/// in-flight part of files still downloading.
class PackInstallProgress {
  const PackInstallProgress({
    required this.slug,
    required this.state,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.filesDone = 0,
    this.filesTotal = 0,
    this.error,
  });

  final String slug;
  final PackInstallState state;
  final int bytesDone;
  final int bytesTotal;
  final int filesDone;
  final int filesTotal;
  final String? error;

  bool get isTerminal =>
      state == PackInstallState.installed ||
      state == PackInstallState.failed ||
      state == PackInstallState.cancelled;
}
