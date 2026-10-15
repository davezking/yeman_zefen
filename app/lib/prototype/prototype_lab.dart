import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'mock_data.dart';
import 'models.dart';
import 'prototype_model.dart';

/// A small dev control over the prototype, for trying the screens' variants
/// (guest or signed in, offline, a failing download). It is not part of the
/// design and sits outside the screens: a round button in a corner that opens
/// a sheet of switches. Its text is English only.
class PrototypeLab extends StatelessWidget {
  const PrototypeLab({
    super.key,
    required this.model,
    required this.navigator,
    required this.child,
  });

  final PrototypeModel model;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        PositionedDirectional(
          top: MediaQuery.paddingOf(context).top + SpacingTokens.n2,
          end: SpacingTokens.n2,
          child: Semantics(
            button: true,
            label: 'Prototype states',
            child: GestureDetector(
              onTap: () {
                final ctx = navigator.currentContext;
                if (ctx == null) return;
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => _LabSheet(model: model),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(SpacingTokens.n8),
                child: Icon(
                  Icons.science_outlined,
                  size: SizeTokens.icon,
                  color: ColorTokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabSheet extends StatelessWidget {
  const _LabSheet({required this.model});

  final PrototypeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        Widget toggle(String label, bool value, ValueChanged<bool> on) =>
            SwitchListTile(title: Text(label), value: value, onChanged: on);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Prototype states (dev only)')),
                toggle(
                  'Signed in',
                  !model.user.isGuest,
                  (v) => model.update(
                    () => model.user = v ? mockSignedIn : mockGuest,
                  ),
                ),
                toggle(
                  'First run (no best score yet)',
                  model.user.bestScore == null,
                  (v) => model.update(
                    () => model.user = v
                        ? (model.user.isGuest
                              ? mockNewGuest
                              : const UserInfo.signedIn(
                                  displayName: 'Meron T.',
                                ))
                        : (model.user.isGuest ? mockGuest : mockSignedIn),
                  ),
                ),
                ListTile(
                  title: const Text('Connection'),
                  trailing: SegmentedButton<Connection>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: Connection.wifi,
                        label: Text('Wi-Fi'),
                      ),
                      ButtonSegment(
                        value: Connection.mobile,
                        label: Text('Mobile'),
                      ),
                      ButtonSegment(
                        value: Connection.offline,
                        label: Text('Off'),
                      ),
                    ],
                    selected: {model.connection},
                    onSelectionChanged: (s) =>
                        model.update(() => model.connection = s.first),
                  ),
                ),
                ListTile(
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
                        DropdownMenuItem(
                          value: problem.name,
                          child: Text(label),
                        ),
                    ],
                    onChanged: (v) => model.update(
                      () => model.failNextDownload = PackProblem.values
                          .where((p) => p.name == v)
                          .firstOrNull,
                    ),
                  ),
                ),
                ListTile(
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
                toggle(
                  'Apple button (iOS only)',
                  model.showApple,
                  (v) => model.update(() => model.showApple = v),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
