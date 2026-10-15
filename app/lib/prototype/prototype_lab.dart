import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import 'mock_data.dart';
import 'models.dart';
import 'prototype_jumps.dart';
import 'prototype_model.dart';

/// The hidden dev menu: jump to any screen or state, and switch the player
/// (guest or signed in), the connection (online or offline) and the language.
/// It is not part of the design and has no button: put three fingers on the
/// screen at once (or press Ctrl+Shift+D on a keyboard). Its text is English
/// only.
class PrototypeLab extends StatefulWidget {
  const PrototypeLab({
    super.key,
    required this.model,
    required this.router,
    required this.navigator,
    required this.child,
  });

  final PrototypeModel model;
  final GoRouter router;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<PrototypeLab> createState() => _PrototypeLabState();
}

class _PrototypeLabState extends State<PrototypeLab> {
  final _fingers = <int>{};
  bool _open = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyD &&
        keyboard.isControlPressed &&
        keyboard.isShiftPressed) {
      _show();
      return true;
    }
    return false;
  }

  void _lift(PointerEvent event) => _fingers.remove(event.pointer);

  void _show() {
    final context = widget.navigator.currentContext;
    if (context == null || _open) return;
    _open = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _LabSheet(
        model: widget.model,
        onJump: (target) => _jump(sheetContext, target),
      ),
    ).whenComplete(() => _open = false);
  }

  void _jump(BuildContext sheetContext, JumpTarget target) {
    Navigator.of(sheetContext).pop();
    widget.model.resetStates();
    widget.model.update(() => target.prepare?.call(widget.model));
    widget.router.go(target.path);
    final then = target.then;
    if (then != null) _openOver(then);
  }

  /// Opens a sheet once the jump's screen is in place: the router applies a
  /// new location on the next frame, so after the one following it.
  Future<void> _openOver(
    void Function(BuildContext context, PrototypeModel model) then,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final context = widget.navigator.currentContext;
    if (mounted && context != null && context.mounted) {
      then(context, widget.model);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _fingers.add(event.pointer);
        if (_fingers.length == 3) _show();
      },
      onPointerUp: _lift,
      onPointerCancel: _lift,
      child: widget.child,
    );
  }
}

class _LabSheet extends StatelessWidget {
  const _LabSheet({required this.model, required this.onJump});

  final PrototypeModel model;
  final ValueChanged<JumpTarget> onJump;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<JumpTarget>>{};
    for (final t in prototypeJumps) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final theme = Theme.of(context);
          Widget heading(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(
              SpacingTokens.n16,
              SpacingTokens.n16,
              SpacingTokens.n16,
              SpacingTokens.n8,
            ),
            child: Text(text, style: theme.textTheme.titleSmall),
          );
          Widget toggle(String label, bool value, ValueChanged<bool> on) =>
              SwitchListTile(
                dense: true,
                title: Text(label),
                value: value,
                onChanged: on,
              );
          Widget segmented<T>(
            String label,
            T value,
            List<(T, String)> options,
            ValueChanged<T> on,
          ) => ListTile(
            title: Text(label),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.n8),
              child: SegmentedButton<T>(
                showSelectedIcon: false,
                segments: [
                  for (final (v, text) in options)
                    ButtonSegment(value: v, label: Text(text)),
                ],
                selected: {value},
                onSelectionChanged: (s) => on(s.first),
              ),
            ),
          );
          final player = model.user.isGuest
              ? (model.user.bestScore == null ? 'new' : 'guest')
              : 'registered';
          return ListView(
            controller: scroll,
            children: [
              const ListTile(
                title: Text('Prototype dev menu'),
                subtitle: Text(
                  'Hidden: three fingers on the screen, or Ctrl+Shift+D.',
                ),
              ),
              segmented<String>(
                'Player',
                player,
                const [
                  ('guest', 'Guest'),
                  ('new', 'Guest, first run'),
                  ('registered', 'Registered'),
                ],
                (v) => model.update(
                  () => model.user = switch (v) {
                    'registered' => mockSignedIn,
                    'new' => mockNewGuest,
                    _ => mockGuest,
                  },
                ),
              ),
              segmented<Connection>('Connection', model.connection, const [
                (Connection.wifi, 'Wi-Fi'),
                (Connection.mobile, 'Mobile'),
                (Connection.offline, 'Offline'),
              ], model.setConnection),
              segmented<String>('Language', model.languageCode, const [
                ('am', 'አማርኛ'),
                ('en', 'English'),
              ], (v) => model.update(() => model.languageCode = v)),
              heading('Jump to a screen'),
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.n16,
                  ),
                  child: Text(entry.key, style: theme.textTheme.labelMedium),
                ),
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.n16),
                  child: Wrap(
                    spacing: SpacingTokens.n8,
                    runSpacing: SpacingTokens.n8,
                    children: [
                      for (final t in entry.value)
                        ActionChip(
                          label: Text(t.label),
                          onPressed: () => onJump(t),
                        ),
                    ],
                  ),
                ),
              ],
              heading('States'),
              ListTile(
                dense: true,
                title: const Text('Next download'),
                // Keyed by name: a null value would show as no selection.
                trailing: DropdownButton<String>(
                  value: model.failNextDownload?.name ?? 'ok',
                  items: [
                    const DropdownMenuItem(
                      value: 'ok',
                      child: Text('succeeds'),
                    ),
                    for (final (problem, label) in const [
                      (PackProblem.downloadFailed, 'fails'),
                      (PackProblem.corrupt, 'is corrupt'),
                      (PackProblem.storageFull, 'storage full'),
                    ])
                      DropdownMenuItem(value: problem.name, child: Text(label)),
                  ],
                  onChanged: (v) => model.update(
                    () => model.failNextDownload = PackProblem.values
                        .where((p) => p.name == v)
                        .firstOrNull,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text('Next sign-in'),
                trailing: DropdownButton<SignInOutcome>(
                  value: model.nextSignIn,
                  items: const [
                    DropdownMenuItem(
                      value: SignInOutcome.works,
                      child: Text('works'),
                    ),
                    DropdownMenuItem(
                      value: SignInOutcome.linkFails,
                      child: Text('scores fail to link'),
                    ),
                  ],
                  onChanged: (v) => model.update(
                    () => model.nextSignIn = v ?? SignInOutcome.works,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text('Score on Results'),
                trailing: DropdownButton<String>(
                  value: model.forcedSync?.name ?? 'auto',
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('automatic')),
                    DropdownMenuItem(
                      value: 'provisional',
                      child: Text('provisional'),
                    ),
                    DropdownMenuItem(value: 'synced', child: Text('synced')),
                    DropdownMenuItem(
                      value: 'savedOffline',
                      child: Text('saved offline'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('not counted'),
                    ),
                  ],
                  onChanged: (v) => model.update(
                    () => model.forcedSync = ScoreSync.values
                        .where((s) => s.name == v)
                        .firstOrNull,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text("Round 2's clip"),
                trailing: DropdownButton<ClipArrival>(
                  value: model.nextClip,
                  items: const [
                    DropdownMenuItem(
                      value: ClipArrival.onTime,
                      child: Text('on time'),
                    ),
                    DropdownMenuItem(
                      value: ClipArrival.slow,
                      child: Text('3 s late'),
                    ),
                    DropdownMenuItem(
                      value: ClipArrival.never,
                      child: Text('never comes'),
                    ),
                  ],
                  onChanged: (v) => model.update(
                    () => model.nextClip = v ?? ClipArrival.onTime,
                  ),
                ),
              ),
              toggle(
                'Apple button (iOS only)',
                model.showApple,
                (v) => model.update(() => model.showApple = v),
              ),
              toggle(
                'Update required',
                model.updateRequired,
                (v) => model.update(() => model.updateRequired = v),
              ),
              toggle(
                'Ad consent required (after the first game)',
                model.consentRequired,
                (v) => model.update(() {
                  model.consentRequired = v;
                  model.consentDone = false;
                }),
              ),
              toggle(
                'Offline: every song played recently',
                model.allSongsPlayed,
                (v) => model.update(() => model.allSongsPlayed = v),
              ),
              toggle(
                'Leaderboard is empty',
                model.boardEmpty,
                (v) => model.update(() => model.boardEmpty = v),
              ),
              toggle(
                'Offline: a saved board exists',
                model.boardCached,
                (v) => model.update(() => model.boardCached = v),
              ),
              toggle(
                'Lists load slowly (skeletons)',
                model.slowLists,
                (v) => model.update(() => model.slowLists = v),
              ),
              toggle(
                'Leaderboard fails to load (once)',
                model.boardFails,
                (v) => model.update(() => model.boardFails = v),
              ),
              toggle(
                'Sending offline games fails',
                model.syncFails,
                (v) => model.update(() => model.syncFails = v),
              ),
              const SizedBox(height: SpacingTokens.n24),
            ],
          );
        },
      ),
    );
  }
}
