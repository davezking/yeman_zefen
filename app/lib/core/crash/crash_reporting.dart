import 'package:flutter/foundation.dart';


import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';

/// Crashlytics needs Firebase up. Before [installCrashReporting] (and in tests) nothing is recorded.
bool get _ready => Firebase.apps.isNotEmpty;

/// Sends uncaught errors to Crashlytics and turns collection on for the prod flavor only. Call after
/// Firebase is initialized. The dev flavor keeps its errors on the console.
Future<void> installCrashReporting() async {
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(AppConfig.flavor == 'prod');

  final printFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    printFlutterError?.call(details);
    crashlytics.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}

/// The player's UID as the Crashlytics user (never an email). Null clears it on sign-out.
void setCrashUser(String? uid) {
  if (!_ready) return;
  FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
}

/// Logs a handled failure as a non-fatal issue. [reason] is a fixed label, such as `sync_parked`;
/// do not pass user data in it or in the error text.
void recordNonFatal(Object error, StackTrace? stack, {required String reason}) {
  if (!_ready) return;
  FirebaseCrashlytics.instance.recordError(
    error,
    stack,
    reason: reason,
    fatal: false,
  );
}

/// Keeps the Crashlytics user in step with the signed-in UID, on start and on each change.
final crashUserStarterProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AuthState>>(
    authStateProvider,
    (_, next) => setCrashUser(next.value?.uid),
    fireImmediately: true,
  );
});
