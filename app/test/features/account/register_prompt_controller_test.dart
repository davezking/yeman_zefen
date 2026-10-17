import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/core/auth/auth_service.dart';
import 'package:yeman_zefen/core/config/remote_config.dart';
import 'package:yeman_zefen/core/db/app_db.dart';
import 'package:yeman_zefen/features/account/register_prompt_controller.dart';
import 'package:yeman_zefen/features/game/data/session_store.dart';

import '../game/data/session_fixtures.dart';

const _day = Duration.millisecondsPerDay;

void main() {
  late AppDb db;
  late SessionStore sessions;
  late int now;
  late RemoteConfig config;
  late AuthState who;
  late RegisterPromptController controller;

  // A fresh controller over the same database, as a restart would make.
  RegisterPromptController restarted() => RegisterPromptController(
    sessions: sessions,
    db: db,
    config: () => config,
    auth: () => who,
    nowMs: () => now,
  );

  var sessionNumber = 0;
  Future<void> finishSessions(int count) async {
    for (var i = 0; i < count; i++) {
      sessionNumber++;
      await sessions.saveCompleted(
        payload: payloadOf(id: 'session-$sessionNumber'),
        score: 10,
        nowMs: now,
      );
    }
  }

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    sessions = SessionStore(db);
    now = 1760000000000;
    config = RemoteConfig.defaults; // asks after 5 sessions, cooldown 7 days
    who = const AuthState(uid: 'guest-uid');
    controller = restarted();
  });

  tearDown(() => db.close());

  group('after results', () {
    test('a guest is not asked before session N', () async {
      await finishSessions(4);

      expect(await controller.shouldPromptAfterResults(), isFalse);
    });

    test('a guest is asked at the results screen of session N', () async {
      await finishSessions(5);

      expect(await controller.shouldPromptAfterResults(), isTrue);
    });

    test(
      'the count follows the config, so a changed threshold applies at once',
      () async {
        await finishSessions(3);
        config = RemoteConfig.fromJson({
          ...config.toJson(),
          'registerPromptAfterSessions': 3,
        });

        expect(await controller.shouldPromptAfterResults(), isTrue);
      },
    );

    test('counts every saved session, even after its upload is done', () async {
      await finishSessions(2);

      expect(await sessions.completedSessionCount(), 2);
    });
  });

  group('after a dismissal', () {
    test('stays hidden for the cooldown, then is asked again', () async {
      await finishSessions(5);
      await controller.dismiss();

      now += 7 * _day - 1;
      expect(await controller.shouldPromptAfterResults(), isFalse);

      now += 1;
      expect(await controller.shouldPromptAfterResults(), isTrue);
    });

    test('is remembered across a restart', () async {
      await finishSessions(5);
      await controller.dismiss();

      now += 1 * _day;
      expect(await restarted().shouldPromptAfterResults(), isFalse);
    });

    test('a later dismissal starts the cooldown again', () async {
      await finishSessions(5);
      await controller.dismiss();
      now += 7 * _day;
      await controller.dismiss();

      now += 6 * _day;
      expect(await controller.shouldPromptAfterResults(), isFalse);
    });

    test('a changed cooldown applies at once', () async {
      await finishSessions(5);
      await controller.dismiss();
      config = RemoteConfig.fromJson({
        ...config.toJson(),
        'registerPromptCooldownDays': 1,
      });

      now += 1 * _day;
      expect(await controller.shouldPromptAfterResults(), isTrue);
    });
  });

  group('from the leaderboard', () {
    test('a guest is asked at once, without any sessions', () async {
      expect(await controller.shouldPromptFromLeaderboard(), isTrue);
    });

    test('a dismissal in the cooldown hides it there too', () async {
      await controller.dismiss();

      expect(await controller.shouldPromptFromLeaderboard(), isFalse);
      now += 7 * _day;
      expect(await controller.shouldPromptFromLeaderboard(), isTrue);
    });
  });

  group('who is asked', () {
    test('a registered player is never asked, after results or from the leaderboard', () async {
      who = const AuthState(
        uid: 'user',
        isAnonymous: false,
        providers: ['google.com'],
      );
      await finishSessions(5);

      expect(await controller.shouldPromptAfterResults(), isFalse);
      expect(await controller.shouldPromptFromLeaderboard(), isFalse);
    });

    test('a device with no account yet is not asked', () async {
      who = AuthState.signedOut;
      await finishSessions(5);

      expect(await controller.shouldPromptAfterResults(), isFalse);
      expect(await controller.shouldPromptFromLeaderboard(), isFalse);
    });

    test('a guest who has just registered is no longer asked', () async {
      await finishSessions(5);
      who = const AuthState(
        uid: 'guest-uid',
        isAnonymous: false,
        providers: ['password'],
      );

      expect(await controller.shouldPromptAfterResults(), isFalse);
    });
  });
}
