import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/net/network_kind.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../../../prototype/models.dart' as proto;
import '../../account/data/profile_api.dart';
import '../../account/ui/register_sheet.dart';
import '../application/play_setup.dart' show currentNetworkProvider;
import '../application/session_controller.dart';
import '../application/session_score.dart';
import '../application/session_state.dart';
import '../domain/session_config.dart';
import 'results_screen.dart';
import 'session_texts.dart';

/// The results with the real game: the phone's count at once, the server's score in its place when
/// the server has answered, and the register prompt on top when the controller asks for it
/// (`RegisterPromptOnResults`, in `app.dart`).
class ResultsRoute extends ConsumerWidget {
  const ResultsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(sessionControllerProvider).summary;
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.resultsTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.resultsNone),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/setup'), child: Text(l10n.startTitle)),
            ],
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context);
    final saved = ref.watch(sessionScoreProvider(summary.sessionId)).asData?.value ?? const SessionScore();
    final offline = ref.watch(currentNetworkProvider).asData?.value == NetworkKind.none;
    final auth = ref.watch(authStateProvider).asData?.value ?? AuthState.signedOut;
    final signedIn = auth.hasUid && !auth.isAnonymous;

    // "Checking your score…" only while an answer can actually come: the session is queued, the
    // phone is online with an account to send it under, and no send has failed yet. A session
    // that is not queued and has no server score was never saved (the save-error caption says
    // so) or the server took it without a score: there is nothing to wait for.
    final proto.ScoreSync sync;
    if (saved.serverScore != null) {
      sync = proto.ScoreSync.synced;
    } else if (saved.parked) {
      sync = proto.ScoreSync.rejected;
    } else if (!saved.queued) {
      sync = proto.ScoreSync.synced;
    } else if (offline || !auth.hasUid) {
      sync = proto.ScoreSync.savedOffline;
    } else if (saved.retrying) {
      sync = proto.ScoreSync.retrying;
    } else {
      sync = proto.ScoreSync.provisional;
    }

    // The server's score replaces the phone's, so "New best" is judged on the score shown.
    final score = saved.serverScore ?? summary.totalScore;
    final best = summary.bestBefore;
    final newBest = saved.serverScore == null ? summary.isNewBest : (best == null ? summary.isNewBest : score > best);

    final view = proto.ResultsView(
      score: score,
      provisionalScore: summary.totalScore,
      rounds: [for (final r in summary.rounds) _roundOf(r, l10n, locale)],
      user: signedIn
          ? proto.UserInfo.signedIn(displayName: ref.watch(ownNameProvider).asData?.value ?? '')
          : const proto.UserInfo.guest(),
      newBest: newBest,
      sync: sync,
      skipped: summary.skipped,
      flagged: summary.flagged,
      saveError: summary.saveError,
    );

    return ResultsScreen(
      view: view,
      onPlayAgain: () {
        // The same game again: the mode, era, difficulty and length that were just played.
        unawaited(ref.read(sessionControllerProvider.notifier).start(summary.config));
        context.go('/play');
      },
      onChange: () => context.go('/setup'),
      onHome: () => context.go('/'),
      onSignIn: () => showRegisterSheet(context),
      onLeaderboard: () => context.go('/leaderboard'),
    );
  }

  /// One round as the screen lists it: the song and its singer, or for Which Era? the song and the
  /// era it is from, named in the UI language.
  static proto.RoundResult _roundOf(RoundSummary r, AppLocalizations l10n, Locale locale) {
    // Names are resolved in the current language here, with the usual fallback for a name the
    // catalog does not have. The screen rebuilds on a language change, so the list follows it.
    final eraLine = r.kind == QuestionKind.era && r.correctEraId != null ? l10n.eraLabel(r.correctEraId!) : null;
    // The song that played; for an artist question the answer is the singer, so not that.
    final song = l10n.nameOf(r.trackName.isEmpty ? r.correctName : r.trackName, locale);
    final artist = eraLine ?? l10n.nameOf(r.artistName, locale);
    final track = proto.Track(
      id: '${r.number}',
      titleAm: song,
      titleLatin: song,
      artistAm: artist,
      artistLatin: artist,
      generationId: 0,
      genre: proto.Genre.any,
    );
    return proto.RoundResult(
      number: r.number,
      track: track,
      correct: r.correct,
      points: r.points,
      timedOut: r.chosenName == null,
    );
  }
}
