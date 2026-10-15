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
                  trailing: DropdownButton<PackProblem?>(
                    value: model.failNextDownload,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('succeeds')),
                      DropdownMenuItem(
                        value: PackProblem.downloadFailed,
                        child: Text('fails'),
                      ),
                      DropdownMenuItem(
                        value: PackProblem.corrupt,
                        child: Text('is corrupt'),
                      ),
                      DropdownMenuItem(
                        value: PackProblem.storageFull,
                        child: Text('storage full'),
                      ),
                    ],
                    onChanged: (v) =>
                        model.update(() => model.failNextDownload = v),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
