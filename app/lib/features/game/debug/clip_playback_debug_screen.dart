import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/clip_player.dart';
import '../../../core/db/app_db.dart';
import '../../packs/data/packs_providers.dart';

class DebugTrack {
  const DebugTrack({
    required this.label,
    required this.introPath,
    required this.middlePath,
  });

  final String label;

  /// Absolute paths, or null when the track has no such clip.
  final String? introPath;
  final String? middlePath;
}

/// Installed tracks with their clip files resolved to absolute paths.
final debugClipTracksProvider = FutureProvider<List<DebugTrack>>((ref) async {
  final db = ref.watch(appDbProvider);
  final base = await ref.watch(supportDirectoryProvider.future);
  String? resolve(String? relative) => relative == null ? null : p.join(base.path, relative);

  final rows = await db.select(db.localTracks).get();
  return [
    for (final t in rows)
      DebugTrack(
        label: '${t.titleLatin ?? t.titleAm ?? 'Track ${t.id}'} · ${t.artistLatin ?? t.artistAm ?? ''}'
            ' (${t.packSlug} #${t.id})',
        introPath: resolve(t.introPath),
        middlePath: resolve(t.middlePath),
      ),
  ];
});

/// Throwaway screen for measuring clip playback on a real device: start
/// latency, and where and when a clip stops. Results go in
/// `docs/spikes/clip-playback.md`.
class ClipPlaybackDebugScreen extends ConsumerStatefulWidget {
  const ClipPlaybackDebugScreen({super.key});

  @override
  ConsumerState<ClipPlaybackDebugScreen> createState() => _ClipPlaybackDebugScreenState();
}

class _ClipPlaybackDebugScreenState extends ConsumerState<ClipPlaybackDebugScreen> {
  DebugTrack? _track;
  var _clip = 'intro';
  var _limitMs = 3000;
  var _preload = true;
  var _busy = false;

  String? _error;
  int? _prepareMs;
  int? _latencyMs;
  ClipStopInfo? _stop;
  int? _stopLimitMs;
  String? _interruption;

  late final ClipPlayer _player = ref.read(clipPlayerProvider);
  final _subscriptions = <StreamSubscription<ClipStopInfo>>[];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(_player.completed.listen(_onStopped));
    _subscriptions.add(_player.interrupted.listen((info) {
      _onStopped(info);
      if (mounted) setState(() => _interruption = 'Interrupted at ${info.positionMs} ms');
    }));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    unawaited(_player.stop());
    super.dispose();
  }

  void _onStopped(ClipStopInfo info) {
    if (mounted) setState(() => _stop = info);
  }

  Future<void> _play(DebugTrack track) async {
    final path = _clip == 'intro' ? track.introPath : track.middlePath;
    if (path == null) {
      setState(() => _error = 'This track has no $_clip clip');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _latencyMs = null;
      _prepareMs = null;
      _stop = null;
      _interruption = null;
      _stopLimitMs = _limitMs;
    });
    try {
      // With preload on, the clip is loaded into the idle player first, so the
      // timed prepare below is the swap a real round would do.
      if (_preload) await _player.preloadNext(path, _limitMs);
      final prepareWatch = Stopwatch()..start();
      await _player.prepare(path, _limitMs);
      final prepareMs = prepareWatch.elapsedMilliseconds;
      final start = await _player.play();
      if (mounted) {
        setState(() {
          _prepareMs = prepareMs;
          _latencyMs = start.latency.inMilliseconds;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopNow() async {
    final info = await _player.stop();
    if (info != null) _onStopped(info);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(debugClipTracksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Clip playback')),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load tracks: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No installed tracks. Install a pack first.'));
          }
          final track = _track ?? list.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButton<DebugTrack>(
                isExpanded: true,
                value: track,
                items: [
                  for (final t in list) DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _track = t),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'intro', label: Text('Intro')),
                  ButtonSegment(value: 'middle', label: Text('Middle')),
                ],
                selected: {_clip},
                onSelectionChanged: (s) => setState(() => _clip = s.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 3000, label: Text('3 s')),
                  ButtonSegment(value: 5000, label: Text('5 s')),
                  ButtonSegment(value: 10000, label: Text('10 s')),
                ],
                selected: {_limitMs},
                onSelectionChanged: (s) => setState(() => _limitMs = s.first),
              ),
              SwitchListTile(
                title: const Text('Preload before play'),
                value: _preload,
                onChanged: (v) => setState(() => _preload = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _play(track),
                      child: const Text('Play'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(onPressed: _stopNow, child: const Text('Stop')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Results(
                error: _error,
                prepareMs: _prepareMs,
                latencyMs: _latencyMs,
                stop: _stop,
                limitMs: _stopLimitMs,
                interruption: _interruption,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.error,
    required this.prepareMs,
    required this.latencyMs,
    required this.stop,
    required this.limitMs,
    required this.interruption,
  });

  final String? error;
  final int? prepareMs;
  final int? latencyMs;
  final ClipStopInfo? stop;
  final int? limitMs;
  final String? interruption;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final stop = this.stop;
    final limit = limitMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Text(error!, key: const Key('error'), style: style?.copyWith(color: Theme.of(context).colorScheme.error)),
        if (prepareMs != null) Text('Prepare: $prepareMs ms', key: const Key('prepare'), style: style),
        if (latencyMs != null) Text('Start latency: $latencyMs ms', key: const Key('latency'), style: style),
        if (stop != null) ...[
          Text('Stopped: ${stop.reason.name}', key: const Key('stop-reason'), style: style),
          Text('Position: ${stop.positionMs} ms', key: const Key('stop-position'), style: style),
          Text(
            limit != null && stop.reason == ClipStopReason.limit
                ? 'Wall clock: ${stop.playedMs} ms (${_signed(stop.playedMs - limit)} vs $limit ms)'
                : 'Wall clock: ${stop.playedMs} ms',
            key: const Key('stop-wall'),
            style: style,
          ),
        ],
        if (interruption != null) Text(interruption!, key: const Key('interruption'), style: style),
      ],
    );
  }

  static String _signed(int n) => n >= 0 ? '+$n' : '$n';
}
