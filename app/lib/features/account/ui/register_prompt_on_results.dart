import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_client.dart';
import '../../../core/http/api_providers.dart';
import '../data/profile_api.dart';
import '../register_prompt_controller.dart';
import 'register_sheet.dart';

/// Wraps the results screen. Once it is on screen, asks the register prompt controller whether a
/// guest should be asked now; if so, opens the register sheet over the results. Only results ever
/// ask, never a round, so this is the one place the prompt opens after play.
class RegisterPromptOnResults extends ConsumerStatefulWidget {
  const RegisterPromptOnResults({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RegisterPromptOnResults> createState() => _RegisterPromptOnResultsState();
}

class _RegisterPromptOnResultsState extends ConsumerState<RegisterPromptOnResults> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the sheet opens over a results screen that is already drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    final controller = ref.read(registerPromptControllerProvider);
    if (controller.isRegistered) return _askForMissingName();
    if (!await controller.shouldPromptAfterResults() || !mounted) return;
    final done = await showRegisterSheet(context);
    // Closing the sheet after linking is not a dismissal: the player is no longer a guest.
    if (!done && !controller.isRegistered) await controller.dismiss();
  }

  /// A registered player who closed the sheet at the name step has no name on the board. They are
  /// asked for it again here. Offline, nothing is asked.
  Future<void> _askForMissingName() async {
    String? name;
    try {
      name = await fetchDisplayName(ref.read(apiClientProvider));
    } on ApiException {
      return;
    }
    if (name != null || !mounted) return;
    await showRegisterSheet(context, nameOnly: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
