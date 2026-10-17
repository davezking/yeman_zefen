import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/models.dart';

/// The contents of the sign-in bottom sheet: "Keep your scores", with Apple
/// (iOS only, and first), Google and email. Show it in an [AppSheet] (or with
/// `showAppBottomSheet`) over Results or the leaderboard.
///
/// While [status] is [SignInStatus.signingIn] every button is off and the one
/// for [signingInWith] shows a spinner. [SignInStatus.linkFailed] adds the
/// message that the player's scores could not be attached yet.
class SignInSheet extends StatelessWidget {
  const SignInSheet({
    super.key,
    required this.onProvider,
    required this.onNotNow,
    this.showApple = false,
    this.status = SignInStatus.idle,
    this.signingInWith,
  });

  /// Apple's button is shown on iOS only, and first (App Store guideline 4.8).
  final bool showApple;
  final SignInStatus status;
  final SignInProvider? signingInWith;
  final ValueChanged<SignInProvider> onProvider;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final busy = status == SignInStatus.signingIn;

    Widget button(SsoKind kind, SignInProvider provider, String label) {
      final thisOne = busy && signingInWith == provider;
      return SsoButton(
        kind: kind,
        label: thisOne ? l10n.authSigningIn : label,
        busy: thisOne,
        onPressed: busy ? null : () => onProvider(provider),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RaisedSurface(
              minWidth: SizeTokens.modeIconTile,
              minHeight: SizeTokens.modeIconTile,
              borderRadius: BorderRadius.circular(RadiusTokens.modeIcon),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ColorTokens.paletteSun300, ColorTokens.paletteSun500],
              ),
              shadows: ElevationTokens.primarySmall,
              child: const Icon(
                Icons.emoji_events_outlined,
                size: SizeTokens.iconLarge,
                color: ColorTokens.textPrimary,
              ),
            ),
            const SizedBox(width: SpacingTokens.n12),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l10n.authPromptTitle, style: text.title),
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.n12),
        Text(
          l10n.authPromptBody,
          style: text.body.copyWith(color: ColorTokens.textSecondary),
        ),
        const SizedBox(height: SpacingTokens.n12),
        Row(
          children: [
            const Icon(
              Icons.check_rounded,
              size: SizeTokens.icon,
              color: ColorTokens.correctText,
            ),
            const SizedBox(width: SpacingTokens.n8),
            Expanded(
              child: Text(
                l10n.authPromptCarryOver,
                style: text.label.copyWith(color: ColorTokens.correctText),
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.n12),
        if (status == SignInStatus.linkFailed) ...[
          Semantics(
            liveRegion: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ColorTokens.surfaceErrorCard,
                borderRadius: BorderRadius.circular(RadiusTokens.small),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SpacingTokens.n12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: SizeTokens.icon,
                      color: ColorTokens.textError,
                    ),
                    const SizedBox(width: SpacingTokens.n8),
                    Expanded(
                      child: Text(
                        l10n.authLinkFailed,
                        style: text.label.copyWith(
                          color: ColorTokens.textError,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.n12),
        ],
        if (showApple) ...[
          button(SsoKind.apple, SignInProvider.apple, l10n.authApple),
          const SizedBox(height: SpacingTokens.n12),
        ],
        button(SsoKind.google, SignInProvider.google, l10n.authGoogle),
        const SizedBox(height: SpacingTokens.n12),
        button(SsoKind.email, SignInProvider.email, l10n.authEmail),
        TextButton(
          onPressed: busy ? null : onNotNow,
          child: Text(
            l10n.authNotNow,
            style: AppTextStyles.withWeight(
              text.body,
              FontWeight.w600,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
  }
}

/// The email step: an address and a password, with the errors for each, and
/// "Create an account" to switch between signing in and signing up. Uses the
/// same sheet, field and button styles as the first step.
class EmailSignInSheet extends StatefulWidget {
  const EmailSignInSheet({
    super.key,
    required this.onSubmit,
    required this.onForgot,
    required this.onBack,
    this.creating = false,
    this.onToggleCreate,
    this.error = EmailError.none,
    this.busy = false,
  });

  /// True: the form creates an account (its button says Next, and a display-name
  /// step follows). False: it signs in.
  final bool creating;
  final VoidCallback? onToggleCreate;
  final EmailError error;
  final bool busy;
  final void Function(String email, String password) onSubmit;
  final VoidCallback onForgot;
  final VoidCallback onBack;

  @override
  State<EmailSignInSheet> createState() => _EmailSignInSheetState();
}

class _EmailSignInSheetState extends State<EmailSignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    TextStyle link() => AppTextStyles.withWeight(
      text.body,
      FontWeight.w600,
    ).copyWith(decoration: TextDecoration.underline);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppBackButton(
                  onPressed: widget.busy ? null : widget.onBack,
                  semanticLabel: l10n.navBack,
                ),
                const SizedBox(width: SpacingTokens.n12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.authEmail, style: text.titleSmall),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.n16),
            _Field(
              controller: _email,
              label: l10n.authEmailLabel,
              error: widget.error == EmailError.email
                  ? l10n.authErrorEmail
                  : null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              enabled: !widget.busy,
            ),
            const SizedBox(height: SpacingTokens.n12),
            _Field(
              controller: _password,
              label: l10n.authPasswordLabel,
              error: widget.error == EmailError.password
                  ? l10n.authErrorPassword
                  : null,
              obscure: true,
              autofillHints: const [AutofillHints.password],
              enabled: !widget.busy,
            ),
            const SizedBox(height: SpacingTokens.n16),
            PrimaryButton(
              label: widget.creating ? l10n.commonNext : l10n.authEmailSubmit,
              onPressed: widget.busy
                  ? null
                  : () => widget.onSubmit(_email.text, _password.text),
            ),
            if (widget.busy)
              Padding(
                padding: const EdgeInsets.only(top: SpacingTokens.n8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.authSigningIn,
                    textAlign: TextAlign.center,
                    style: text.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
                ),
              ),
            if (!widget.creating)
              TextButton(
                onPressed: widget.busy ? null : widget.onForgot,
                child: Text(l10n.authEmailForgot, style: link()),
              ),
            if (widget.onToggleCreate != null)
              TextButton(
                onPressed: widget.busy ? null : widget.onToggleCreate,
                // Back to signing in uses the sign-in button's word.
                child: Text(
                  widget.creating ? l10n.authEmailSubmit : l10n.authEmailCreate,
                  style: link(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// After the first sign-in: the name other players see on the leaderboard.
class DisplayNameSheet extends StatefulWidget {
  const DisplayNameSheet({
    super.key,
    required this.onSave,
    this.initialName = '',
    this.error = NameError.none,
    this.busy = false,
  });

  final String initialName;
  final NameError error;
  final bool busy;
  final ValueChanged<String> onSave;

  @override
  State<DisplayNameSheet> createState() => _DisplayNameSheetState();
}

class _DisplayNameSheetState extends State<DisplayNameSheet> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = context.text;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final error = switch (widget.error) {
      NameError.tooShort => l10n.authNameErrorShort,
      NameError.taken => l10n.authNameErrorTaken,
      NameError.failed => l10n.errorGenericTitle,
      NameError.none => null,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.authNameTitle, style: text.title),
            ),
            const SizedBox(height: SpacingTokens.n8),
            Text(
              l10n.authNameBody,
              style: text.body.copyWith(color: ColorTokens.textSecondary),
            ),
            const SizedBox(height: SpacingTokens.n16),
            _Field(
              controller: _name,
              label: l10n.authNameLabel,
              error: error,
              enabled: !widget.busy,
              autofillHints: const [AutofillHints.nickname],
            ),
            const SizedBox(height: SpacingTokens.n16),
            PrimaryButton(
              label: l10n.authNameSave,
              onPressed: widget.busy ? null : () => widget.onSave(_name.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text field in the app's style: a white card with its label above the
/// text, and the error in red under it (with an icon, not color alone).
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final hasError = error != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(RadiusTokens.card),
      borderSide: BorderSide(
        color: hasError ? ColorTokens.textError : ColorTokens.surfaceCardEdge,
        width: SizeTokens.eraRing,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          style: text.bodyLarge,
          cursorColor: ColorTokens.textPrimary,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: text.body.copyWith(color: ColorTokens.textSecondary),
            floatingLabelStyle:
                AppTextStyles.withWeight(text.label, FontWeight.w700).copyWith(
                  color: hasError
                      ? ColorTokens.textError
                      : ColorTokens.textPrimary,
                ),
            filled: true,
            fillColor: ColorTokens.surfaceCard,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.n16,
              vertical: SpacingTokens.n14,
            ),
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: border.borderSide.copyWith(
                color: hasError
                    ? ColorTokens.textError
                    : ColorTokens.surfaceDark,
              ),
            ),
            disabledBorder: border,
            errorBorder: border,
          ),
        ),
        if (hasError)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: SpacingTokens.n6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: SizeTokens.icon,
                    color: ColorTokens.textError,
                  ),
                  const SizedBox(width: SpacingTokens.n6),
                  Expanded(
                    child: Text(
                      error!,
                      style: text.label.copyWith(color: ColorTokens.textError),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
