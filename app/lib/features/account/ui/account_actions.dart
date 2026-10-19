import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/http/api_client.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../data/account_manager.dart';
import 'sign_in_sheet.dart';

/// Signs the player out, then says they are a guest now. A "signing out" dialog covers the screen
/// while queued sessions are sent first, which can take a few seconds offline.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  _showBusy(context, l10n.settingsSigningOut);
  String message;
  try {
    await ref.read(accountManagerProvider).signOut();
    message = l10n.settingsSignedOut;
  } on Exception {
    message = l10n.errorGenericTitle;
  } finally {
    navigator.pop();
  }
  _toast(messenger, message);
}

void _showBusy(BuildContext context, String message) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: ColorTokens.backgroundScrim,
  builder: (_) => _BusyDialog(message: message),
);

/// Deletes the account, after the confirms the settings screen asked for. A "deleting" dialog
/// covers the screen meanwhile; the sign-in that proves it is the player opens over it.
Future<void> deleteAccount(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  _showBusy(context, l10n.settingsDeleting);
  String? message;
  try {
    final outcome = await ref
        .read(accountManagerProvider)
        .deleteAccount(askPassword: ({required wrongPassword}) => _askPassword(navigator.context, wrongPassword));
    if (outcome == DeleteOutcome.deleted) message = l10n.settingsDeleted;
  } on Exception catch (e) {
    message = deleteErrorMessage(l10n, e);
  } finally {
    navigator.pop();
  }
  if (message != null) _toast(messenger, message);
}

/// What the player is told when a deletion fails.
String deleteErrorMessage(AppLocalizations l10n, Exception error) {
  final cause = error is DeleteIncompleteException ? error.cause : error;
  if (cause is AuthFailure && cause.code == 'user-mismatch') return l10n.settingsReauthMismatch;
  if (error is DeleteIncompleteException) return l10n.settingsDeleteIncomplete;
  if (error is AuthFailure) {
    return switch (error.code) {
      'network-request-failed' => l10n.authErrorNetwork,
      'too-many-requests' => l10n.authErrorTooMany,
      'reauth-unavailable' => l10n.settingsReauthUnavailable,
      _ => l10n.settingsDeleteFailed,
    };
  }
  if (error is NetworkException) return l10n.authErrorNetwork;
  return l10n.settingsDeleteFailed;
}

void _toast(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> _askPassword(BuildContext context, bool wrongPassword) => showDialog<String>(
  context: context,
  barrierColor: ColorTokens.backgroundScrim,
  builder: (_) => PasswordDialog(wrongPassword: wrongPassword),
);

/// "Confirm it's you": the password of the email account about to be deleted. Pops with the
/// password, or null on cancel.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, this.wrongPassword = false});

  /// The last password typed was refused.
  final bool wrongPassword;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppDialog(
      title: l10n.settingsReauthTitle,
      body: l10n.settingsReauthBody,
      content: AuthField(
        controller: _password,
        label: l10n.authPasswordLabel,
        error: widget.wrongPassword ? l10n.authErrorPassword : null,
        obscure: true,
        autofocus: true,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _submit(),
      ),
      confirmLabel: l10n.settingsDeleteConfirm,
      onConfirm: _submit,
      cancelLabel: l10n.packsCancel,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: ColorTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RadiusTokens.large)),
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.n20),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: SizeTokens.icon,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: ColorTokens.textPrimary),
              ),
              const SizedBox(width: SpacingTokens.n16),
              Expanded(
                child: Semantics(liveRegion: true, child: Text(message, style: context.text.body)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
