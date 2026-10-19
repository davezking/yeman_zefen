import 'package:flutter_test/flutter_test.dart';
import 'package:yeman_zefen/features/game/application/play_setup.dart';
import 'package:yeman_zefen/features/game/domain/session_config.dart' as domain;
import 'package:yeman_zefen/prototype/models.dart' as proto;

/// What Play starts for the choices on the mode and setup screens.
void main() {
  group('intro and middle', () {
    test('every mode, difficulty and question choice maps to the same names the payload uses', () {
      for (final mode in [proto.GameMode.intro, proto.GameMode.middle]) {
        for (final difficulty in proto.Difficulty.values) {
          for (final guess in proto.GuessTarget.values) {
            final config = sessionConfigFor(proto.PlaySettings(mode: mode, difficulty: difficulty, guess: guess, generationId: 3));
            expect(config.mode.name, mode.name);
            expect(config.difficulty.name, difficulty.name);
            expect(config.questions.name, guess.name, reason: 'song, artist and mixed keep their names');
            expect(config.generationId, 3);
          }
        }
      }
    });

    test('Mixed is a mix of song and artist questions', () {
      final config = sessionConfigFor(const proto.PlaySettings(guess: proto.GuessTarget.mixed));
      expect(config.questions, domain.QuestionMix.mixed);
    });
  });

  group('Which Era?', () {
    test('is the generation mode', () {
      expect(domainMode(proto.GameMode.era), domain.GameMode.generation);
    });

    test('reads as all eras and Easy (10 s) on every screen, whatever was saved', () {
      const saved = proto.PlaySettings(mode: proto.GameMode.era, generationId: 3, difficulty: proto.Difficulty.hard);
      final shown = effectivePlaySettings(saved, null);
      expect((shown.generationId, shown.difficulty), (proto.EraId.all, proto.Difficulty.easy));
    });

    test('other modes keep the saved era and difficulty', () {
      const saved = proto.PlaySettings(generationId: 3, difficulty: proto.Difficulty.hard);
      final shown = effectivePlaySettings(saved, null);
      expect((shown.generationId, shown.difficulty), (3, proto.Difficulty.hard));
    });

    test('is for all eras whatever era is saved: it counts on the all-eras boards under generation 0', () {
      final config = sessionConfigFor(const proto.PlaySettings(mode: proto.GameMode.era, generationId: 4));
      expect((config.mode, config.generationId), (domain.GameMode.generation, 0));
    });
  });
}
