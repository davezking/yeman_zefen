import 'package:flutter/widgets.dart';

import 'mock_data.dart';
import 'models.dart';
import 'prototype_flow.dart';
import 'prototype_model.dart';
import 'prototype_paths.dart';

/// A place the dev menu can jump to: a screen, with the mock state that makes
/// it show the variant wanted. Jumping first puts every edge-state switch back
/// to normal ([PrototypeModel.resetStates]); the player, the connection and
/// the language stay as chosen in the menu.
class JumpTarget {
  const JumpTarget(
    this.group,
    this.label,
    this.path, {
    this.prepare,
    this.then,
  });

  final String group;
  final String label;
  final String path;

  /// Sets the mock state this variant needs.
  final void Function(PrototypeModel model)? prepare;

  /// Runs once the screen is up: opens a sheet over it.
  final void Function(BuildContext context, PrototypeModel model)? then;
}

/// Every screen and state of the prototype, in the order a player meets them.
final prototypeJumps = <JumpTarget>[
  const JumpTarget('First launch', 'App start', ProtoPath.splash),
  JumpTarget(
    'First launch',
    'Language',
    ProtoPath.language,
    prepare: (m) => m.firstLaunch = true,
  ),
  JumpTarget(
    'First launch',
    'Welcome',
    ProtoPath.welcome,
    prepare: (m) => m.firstLaunch = true,
  ),

  const JumpTarget('Home', 'Home', ProtoPath.home),
  JumpTarget(
    'Home',
    'Home, no best score yet',
    ProtoPath.home,
    prepare: (m) => m.user = m.user.isGuest ? mockNewGuest : mockSignedIn,
  ),

  const JumpTarget('Play', 'Mode select', ProtoPath.mode),
  const JumpTarget('Play', 'Era, genre, difficulty', ProtoPath.setup),
  JumpTarget(
    'Play',
    'Era setup, offline (eras disabled)',
    ProtoPath.setup,
    prepare: (m) => m.connection = Connection.offline,
  ),
  const JumpTarget('Play', 'Round (plays a whole game)', ProtoPath.round),
  JumpTarget(
    'Play',
    "Round 2's clip is late",
    ProtoPath.round,
    prepare: (m) => m.nextClip = ClipArrival.slow,
  ),
  JumpTarget(
    'Play',
    "Round 2's clip never comes (skipped)",
    ProtoPath.round,
    prepare: (m) => m.nextClip = ClipArrival.never,
  ),

  JumpTarget(
    'After a game',
    'Ad consent',
    ProtoPath.consent,
    prepare: (m) => m.consentRequired = true,
  ),
  JumpTarget(
    'After a game',
    "Ad consent: Google's form",
    ProtoPath.consent,
    then: showUmpForm,
  ),
  JumpTarget(
    'After a game',
    'Results, new best',
    ProtoPath.results,
    prepare: (m) => m.lastResults = mockResults(user: m.user, newBest: true),
  ),
  JumpTarget(
    'After a game',
    'Results, score confirmed',
    ProtoPath.results,
    prepare: (m) {
      m.forcedSync = ScoreSync.synced;
      m.lastResults = mockResults(user: m.user, sync: ScoreSync.synced);
    },
  ),
  JumpTarget(
    'After a game',
    'Results, saved offline',
    ProtoPath.results,
    prepare: (m) {
      m.forcedSync = ScoreSync.savedOffline;
      m.lastResults = mockResults(user: m.user, sync: ScoreSync.savedOffline);
    },
  ),
  JumpTarget(
    'After a game',
    'Results, not counted',
    ProtoPath.results,
    prepare: (m) {
      m.forcedSync = ScoreSync.rejected;
      m.lastResults = mockResults(user: m.user, sync: ScoreSync.rejected);
    },
  ),
  JumpTarget(
    'After a game',
    'Sign-in sheet over Results',
    ProtoPath.results,
    prepare: (m) {
      m.user = mockGuest;
      m.lastResults = mockResults(user: mockGuest);
    },
    then: showSignInFlow,
  ),

  const JumpTarget('Leaderboard', 'Leaderboard', ProtoPath.leaderboard),
  JumpTarget(
    'Leaderboard',
    'Loading (skeleton)',
    ProtoPath.leaderboard,
    prepare: (m) => m.slowLists = true,
  ),
  JumpTarget(
    'Leaderboard',
    'Fails to load',
    ProtoPath.leaderboard,
    prepare: (m) => m.boardFails = true,
  ),
  JumpTarget(
    'Leaderboard',
    'Empty',
    ProtoPath.leaderboard,
    prepare: (m) => m.boardEmpty = true,
  ),
  JumpTarget(
    'Leaderboard',
    'Offline, saved copy',
    ProtoPath.leaderboard,
    prepare: (m) {
      m.connection = Connection.offline;
      m.boardCached = true;
    },
  ),
  JumpTarget(
    'Leaderboard',
    'Offline, nothing saved',
    ProtoPath.leaderboard,
    prepare: (m) {
      m.connection = Connection.offline;
      m.boardCached = false;
    },
  ),

  const JumpTarget('Settings', 'Settings', ProtoPath.settings),
  const JumpTarget('Settings', 'Offline play', ProtoPath.offlinePlay),
  JumpTarget(
    'Settings',
    'Offline play, loading (skeleton)',
    ProtoPath.offlinePlay,
    prepare: (m) => m.slowLists = true,
  ),
  JumpTarget(
    'Settings',
    'Offline play, next download fails',
    ProtoPath.offlinePlay,
    prepare: (m) => m.failNextDownload = PackProblem.downloadFailed,
  ),
  JumpTarget(
    'Settings',
    'Offline play, offline',
    ProtoPath.offlinePlay,
    prepare: (m) => m.connection = Connection.offline,
  ),
  JumpTarget(
    'Settings',
    "Ad privacy choices (Google's form)",
    ProtoPath.settings,
    then: showUmpForm,
  ),

  JumpTarget(
    'Messages',
    'Forced update',
    ProtoPath.update,
    prepare: (m) => m.updateRequired = true,
  ),
  JumpTarget(
    'Messages',
    'Out of songs (offline)',
    ProtoPath.outOfSongs,
    prepare: (m) {
      m.connection = Connection.offline;
      m.allSongsPlayed = true;
    },
  ),
  const JumpTarget('Messages', 'Generic error', ProtoPath.error),
];
