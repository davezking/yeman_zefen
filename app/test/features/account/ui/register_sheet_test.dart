import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yeman_zefen/core/auth/account_linker.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/http/api_client.dart';
import 'package:yeman_zefen/core/http/api_providers.dart';
import 'package:yeman_zefen/core/theme/app_theme.dart';
import 'package:yeman_zefen/core/widgets/widgets.dart';
import 'package:yeman_zefen/features/account/data/account_manager.dart';
import 'package:yeman_zefen/features/account/ui/account_actions.dart';
import 'package:yeman_zefen/features/account/ui/register_sheet.dart';
import 'package:yeman_zefen/l10n/app_localizations.dart';
import 'package:yeman_zefen/l10n/app_localizations_en.dart';
import 'package:yeman_zefen/prototype/models.dart';

/// A linker whose every sign-in answers with [next]: a result, or an exception to throw.
class FakeLinker implements AccountLinker {
  Object next = const LinkResult(LinkOutcome.linked);

  Future<LinkResult> _answer() async {
    final n = next;
    if (n is LinkResult) return n;
    throw n;
  }

  @override
  Future<LinkResult> linkWithGoogle() => _answer();

  @override
  Future<LinkResult> linkWithApple() => _answer();

  @override
  Future<LinkResult> linkWithEmail(String email, String password) => _answer();

  @override
  Future<LinkResult> signInWithEmail(String email, String password) => _answer();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeLinker linker;

  /// `GET /v1/me` answers with [name] as the display name.
  Future<void> pump(WidgetTester tester, {String? name = 'Meron'}) async {
    linker = FakeLinker();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountLinkerProvider.overrideWithValue(linker),
          authStateProvider.overrideWith((ref) => Stream.value(AuthState.signedOut)),
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'https://api.test',
              idToken: ({bool forceRefresh = false}) async => 'token',
              client: MockClient(
                (_) async => http.Response(jsonEncode({'displayName': name}), 200, headers: {'content-type': 'application/json'}),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(const Locale('en')),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showRegisterSheet(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> google(WidgetTester tester) async {
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
  }

  Future<void> email(WidgetTester tester, {String address = 'a@b.co', String password = 'secret1'}) async {
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), address);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  group('Google and Apple', () {
    testWidgets('offline says so, and the buttons come back', (tester) async {
      await pump(tester);
      linker.next = const AuthFailure('network-request-failed');
      await google(tester);
      expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('a provider failure says sign-in did not work', (tester) async {
      await pump(tester);
      linker.next = const AuthFailure('google-unknownError');
      await google(tester);
      expect(find.text("Sign-in didn't work. Try again."), findsOneWidget);
    });

    testWidgets('a cancel says nothing', (tester) async {
      await pump(tester);
      linker.next = const LinkResult(LinkOutcome.cancelled);
      await google(tester);
      expect(find.text("Sign-in didn't work. Try again."), findsNothing);
      expect(find.text('No internet connection. Connect and try again.'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('a linked guest is told who they are signed in as', (tester) async {
      await pump(tester);
      await google(tester);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Signed in as Meron'), findsOneWidget);
    });

    testWidgets('signing in to an existing account says the progress was combined', (tester) async {
      await pump(tester);
      linker.next = const LinkResult(LinkOutcome.merged);
      await google(tester);
      expect(find.text('Progress combined: your guest scores were added to your account.'), findsOneWidget);
    });

    testWidgets('a server step still waiting says the scores will be attached later', (tester) async {
      await pump(tester);
      linker.next = const LinkResult(LinkOutcome.merged, serverSynced: false);
      await google(tester);
      expect(find.textContaining("We couldn't link your account."), findsOneWidget);
    });
  });

  group('email', () {
    testWidgets('a wrong password stays on the form with the password error', (tester) async {
      await pump(tester);
      linker.next = const AuthFailure('wrong-password');
      await email(tester);
      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('offline stays on the form and says so', (tester) async {
      await pump(tester);
      linker.next = const AuthFailure('network-request-failed');
      await email(tester);
      expect(find.text('No internet connection. Connect and try again.'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('too many tries asks to wait', (tester) async {
      await pump(tester);
      linker.next = const AuthFailure('too-many-requests');
      await email(tester);
      expect(find.text('Too many tries. Wait a few minutes and try again.'), findsOneWidget);
    });
  });

  test('emailErrorFor', () {
    expect(emailErrorFor('invalid-email'), EmailError.email);
    expect(emailErrorFor('invalid-credential'), EmailError.password);
    expect(emailErrorFor('user-not-found'), EmailError.password);
    expect(emailErrorFor('network-request-failed'), EmailError.offline);
    expect(emailErrorFor('too-many-requests'), EmailError.tooMany);
    expect(emailErrorFor('user-disabled'), EmailError.failed);
  });

  test('deleteErrorMessage', () {
    final l10n = AppLocalizationsEn();
    expect(deleteErrorMessage(l10n, const NetworkException('offline')), l10n.authErrorNetwork);
    expect(deleteErrorMessage(l10n, const ServerException('internal', 'boom', status: 500)), l10n.settingsDeleteFailed);
    expect(deleteErrorMessage(l10n, const AuthFailure('network-request-failed')), l10n.authErrorNetwork);
    expect(deleteErrorMessage(l10n, const AuthFailure('user-mismatch')), l10n.settingsReauthMismatch);
    expect(deleteErrorMessage(l10n, const AuthFailure('reauth-unavailable')), l10n.settingsDeleteFailed);
    expect(deleteErrorMessage(l10n, const DeleteIncompleteException()), l10n.settingsDeleteIncomplete);
    expect(
      deleteErrorMessage(l10n, const DeleteIncompleteException(AuthFailure('user-mismatch'))),
      l10n.settingsReauthMismatch,
    );
  });
}
