import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_linker.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/http/api_client.dart';
import '../../../core/http/api_providers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../prototype/models.dart';
import '../../leaderboard/application/leaderboard_providers.dart';
import '../data/profile_api.dart';
import 'sign_in_sheet.dart';

/// Opens the register sheet over the current screen. Resolves to true once the player is signed
/// in and has a name; false when they closed it without finishing, which the caller should count
/// as a dismissal.
Future<bool> showRegisterSheet(BuildContext context) async {
  final done = await showAppBottomSheet<bool>(context, builder: (_) => const RegisterSheet());
  return done ?? false;
}

enum _Step { choose, email, name }

/// The register sheet, wired to [AccountLinker]: Google, Apple (iOS, or Android when the build
/// asks for it) and email, then the display name. The sheets it shows come from
/// `sign_in_sheet.dart`, which takes plain data and callbacks.
class RegisterSheet extends ConsumerStatefulWidget {
  const RegisterSheet({super.key});

  @override
  ConsumerState<RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<RegisterSheet> {
  _Step _step = _Step.choose;
  SignInStatus _status = SignInStatus.idle;
  SignInProvider? _with;
  bool _creating = false;
  EmailError _emailError = EmailError.none;
  NameError _nameError = NameError.none;
  bool _savingName = false;

  bool get _busy => _status == SignInStatus.signingIn;

  bool get _appleOffered => AppConfig.appleOnAndroid || defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signInWith(SignInProvider provider) async {
    final linker = ref.read(accountLinkerProvider);
    setState(() {
      _status = SignInStatus.signingIn;
      _with = provider;
      _emailError = EmailError.none;
    });
    try {
      final result = provider == SignInProvider.apple ? await linker.linkWithApple() : await linker.linkWithGoogle();
      await _afterLink(result);
    } on Exception {
      // The provider refused, was closed by the platform, or failed. The buttons come back.
      _back(SignInStatus.idle);
    }
  }

  void _submitEmail(String email, String password) {
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = EmailError.email);
      return;
    }
    if (password.length < 6) {
      setState(() => _emailError = EmailError.password);
      return;
    }
    _runEmail(email, password);
  }

  Future<void> _runEmail(String email, String password) async {
    final linker = ref.read(accountLinkerProvider);
    setState(() {
      _status = SignInStatus.signingIn;
      _with = SignInProvider.email;
      _emailError = EmailError.none;
    });
    try {
      final result = _creating
          ? await linker.linkWithEmail(email, password)
          : await linker.signInWithEmail(email, password);
      await _afterLink(result);
    } on AuthFailure catch (e) {
      setState(() {
        _status = SignInStatus.idle;
        _emailError = emailErrorFor(e.code);
      });
    } on Exception {
      _back(SignInStatus.idle);
    }
  }

  Future<void> _afterLink(LinkResult result) async {
    if (!mounted) return;
    if (result.outcome == LinkOutcome.cancelled) {
      _back(SignInStatus.idle);
      return;
    }
    // Signed in (even when the server step is still waiting to go through). A signed-in account
    // with a name is done; anything else is asked for its name.
    ref.invalidate(ownNameProvider);
    final name = await ref.read(ownNameProvider.future);
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      _finish();
    } else {
      setState(() {
        _status = SignInStatus.idle;
        _step = _Step.name;
      });
    }
  }

  void _back(SignInStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _step = _Step.choose;
    });
  }

  void _finish() {
    ref.invalidate(leaderboardProvider);
    Navigator.of(context).pop(true);
  }

  Future<void> _saveName(String raw) async {
    final lengthError = nameLengthError(raw);
    if (lengthError != NameError.none) {
      setState(() => _nameError = lengthError);
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = NameError.none;
    });
    try {
      await saveDisplayName(ref.read(apiClientProvider), raw.trim());
      ref.invalidate(ownNameProvider);
      if (mounted) _finish();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingName = false;
        _nameError = nameErrorFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.choose:
        return SignInSheet(
          showApple: _appleOffered,
          status: _status,
          signingInWith: _with,
          onProvider: (p) => p == SignInProvider.email
              ? setState(() {
                  _step = _Step.email;
                  _status = SignInStatus.idle;
                })
              : _signInWith(p),
          onNotNow: () => Navigator.of(context).pop(false),
        );
      case _Step.email:
        return EmailSignInSheet(
          creating: _creating,
          error: _emailError,
          busy: _busy,
          onToggleCreate: () => setState(() {
            _creating = !_creating;
            _emailError = EmailError.none;
          }),
          onSubmit: _submitEmail,
          // Not wired yet: sending a reset needs the email typed on this form.
          onForgot: () {},
          onBack: () => setState(() {
            _step = _Step.choose;
            _emailError = EmailError.none;
          }),
        );
      case _Step.name:
        return DisplayNameSheet(error: _nameError, busy: _savingName, onSave: _saveName);
    }
  }
}

/// Maps Firebase's email error codes to the two messages the email form shows.
EmailError emailErrorFor(String code) => switch (code) {
  'invalid-email' => EmailError.email,
  'weak-password' => EmailError.password,
  'wrong-password' || 'invalid-credential' || 'user-not-found' => EmailError.password,
  _ => EmailError.none,
};
