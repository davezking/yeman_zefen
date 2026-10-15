import 'package:flutter/material.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'app_button.dart';

/// A confirmation dialog in the app's style: a title, a short body, a yellow
/// confirm button and a white cancel button.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Dialog(
        backgroundColor: ColorTokens.surfaceCard,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.n24,
          vertical: SpacingTokens.n24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.large),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SpacingTokens.n20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: text.titleSmall),
              const SizedBox(height: SpacingTokens.n8),
              Text(
                body,
                style: text.body.copyWith(color: ColorTokens.textSecondary),
              ),
              const SizedBox(height: SpacingTokens.n20),
              PrimaryButton(label: confirmLabel, onPressed: onConfirm),
              const SizedBox(height: SpacingTokens.n10),
              SecondaryButton(label: cancelLabel, onPressed: onCancel),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an [AppDialog]. Resolves to true on confirm, false on cancel, and
/// null if it was dismissed by tapping outside or going back.
Future<bool?> showAppDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: ColorTokens.backgroundScrim,
    builder: (dialogContext) => AppDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: () => Navigator.of(dialogContext).pop(true),
      onCancel: () => Navigator.of(dialogContext).pop(false),
    ),
  );
}
