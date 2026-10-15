import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Where each prototype screen lives. Flat on purpose: every screen can be
/// opened directly (the dev menu does), with Home as the place "back" ends.
abstract final class ProtoPath {
  static const splash = '/splash';
  static const language = '/language';
  static const welcome = '/welcome';
  static const home = '/';
  static const mode = '/mode';
  static const setup = '/setup';
  static const round = '/round';
  static const consent = '/consent';
  static const results = '/results';
  static const leaderboard = '/leaderboard';
  static const settings = '/settings';
  static const offlinePlay = '/settings/offline';
  static const update = '/update';
  static const outOfSongs = '/out-of-songs';
  static const error = '/error';
}

extension ProtoNavigation on BuildContext {
  /// Back one screen; when this screen was opened directly (from the dev menu
  /// or as the first page), Home.
  void popOrHome() => canPop() ? pop() : go(ProtoPath.home);
}
