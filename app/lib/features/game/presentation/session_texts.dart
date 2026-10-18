import 'package:flutter/widgets.dart';

import '../../../core/l10n/display_name.dart';
import '../../../l10n/app_localizations.dart';
import '../../../prototype/labels.dart';
import '../application/session_state.dart';

/// Words for session state, in the language the UI is in now. Screens call these while building,
/// so a language switch changes what is on screen at once.
extension SessionTexts on AppLocalizations {
  /// A song or artist name in [locale]'s script, or "Unknown" when the catalog has none.
  String nameOf(DisplayName name, Locale locale) => name.of(locale, fallback: nameUnknown);

  String sessionErrorText(SessionError error) => switch (error.problem) {
        SessionProblem.noSongs => sessionErrorNoSongs,
        SessionProblem.tooFewSongs => sessionErrorTooFewSongs,
        SessionProblem.tooFewArtists => sessionErrorTooFewArtists,
        SessionProblem.noSongsInEra => sessionErrorNoSongsInEra(eraLabel(error.generationId ?? 0)),
        SessionProblem.clipsFailed => sessionErrorClipsFailed(error.count ?? 0),
        SessionProblem.unexpected => sessionErrorUnexpected(error.detail ?? ''),
      };
}
