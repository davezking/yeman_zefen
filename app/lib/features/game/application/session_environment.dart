import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

typedef TimerFactory = Timer Function(Duration duration, void Function() callback);

/// Everything the session flow takes from the outside: clocks, timers, the file
/// system, ids and connectivity. Tests replace it so a session runs without
/// waiting for real time.
class SessionEnvironment {
  const SessionEnvironment({
    required this.monotonicMs,
    required this.epochMs,
    required this.timer,
    required this.fileExists,
    required this.newId,
    required this.isOffline,
    required this.rng,
    this.feedbackDuration = const Duration(seconds: 1),
  });

  factory SessionEnvironment.real() {
    final watch = Stopwatch()..start();
    return SessionEnvironment(
      monotonicMs: () => watch.elapsedMicroseconds ~/ 1000,
      epochMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
      timer: Timer.new,
      fileExists: (path) => File(path).exists(),
      newId: () => const Uuid().v4(),
      isOffline: () async {
        final results = await Connectivity().checkConnectivity();
        return results.every((r) => r == ConnectivityResult.none);
      },
      rng: Random.new,
    );
  }

  /// A clock that only goes forward, for response times. Not affected by the
  /// user or the network changing the time of day.
  final int Function() monotonicMs;

  /// Epoch milliseconds, UTC, for timestamps in the payload.
  final int Function() epochMs;

  final TimerFactory timer;
  final Future<bool> Function(String path) fileExists;
  final String Function() newId;
  final Future<bool> Function() isOffline;
  final Random Function() rng;

  /// How long the right or wrong result stays on screen before the next round.
  final Duration feedbackDuration;
}
