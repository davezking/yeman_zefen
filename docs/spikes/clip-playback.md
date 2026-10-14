# Spike: clip playback on real devices

Status: **code done, device measurements not yet taken.** The tables below are empty on purpose. Fill them in from a
real Android phone and a real iPhone. Emulators and simulators do not give usable audio timing.

Task: P1S4 task 3 (`docs/phase-1-sprint-4-prompts.md`). Background: the PRD's "prototype the clip-seek early".

## What was built

- `app/lib/core/audio/clip_player.dart`: `ClipPlayer`, which keeps two `AudioPlayer`s (through `ClipVoice`). One holds
  the current round's clip, the other preloads the next. `prepare()` swaps to the preloaded one when it is the same
  clip and limit, so a round starts without waiting for a file to load.
- The difficulty limit (3, 5 or 10 s) is a `ClippingAudioSource` end (`clip_voice.dart`), so the player enforces the
  stop itself. It is not a Dart timer.
- `play()` completes when audio is actually playing: `playing`, state `ready`, and the position has advanced past zero.
  The time from the call to that moment is the **start latency**.
- `stop()` asks the player to pause in the same turn it is called.
- `lib/core/audio/game_audio_session.dart`: audio session for short game clips. Android takes transient focus that
  allows ducking; iOS uses `playback` with `duckOthers` and notifies others on deactivation. Other apps are ducked while a
  clip plays and restored after, never taken over.
- Interruptions: a call, another app taking audio, or headphones unplugged stops the clip and is reported on
  `ClipPlayer.interrupted`, so the game can pause the round. A notification that only ducks the volume does not stop it.
  `just_audio`'s own interruption handling is off (`handleInterruptions: false`), because it would resume a clip mid-way
  after a call and make response times meaningless.
- Debug screen: `/debug/clip-playback`, linked from the home screen in the `dev` flavor only.

## Decision to confirm: two players or one playlist

Two players were chosen on reasoning, not on a measurement: the next clip is not known until the round engine picks it,
and a `ConcatenatingAudioSource` would have to be edited while playing. **Not yet compared on a device.** If start
latency with preload is over the target below, try the playlist and record both here.

## How to measure

1. Install a pack on the device (a `dev` build, so the debug link shows). Use a real pack, not a fixture.
2. Home screen, "Clip playback debug". Pick a track, clip type, limit.
3. For each device, run each case **at least 10 times** and write down every run, not an average:
   - 3 s, 5 s and 10 s, **with** "Preload before play".
   - 3 s **without** preload, for comparison.
4. Read off: `Start latency`, `Prepare` (the swap, near 0 with preload), and after the clip ends `Wall clock` and
   `Position` (these show the stop).
5. Listen for a click or pop at the start and at the stop. Use headphones, then the speaker.
6. Interruptions, each at least 3 times, per device:
   - Phone call arrives while a clip plays, then ends.
   - A notification sound arrives while a clip plays.
   - Headphones unplugged while a clip plays.
   - Other music playing before the clip starts: it should duck, then come back.
   Record whether the app crashed, whether the debug screen showed the interruption, and whether the next Play worked.

## Targets (from the task)

- Start latency under about 150 ms with preload, on both devices.
- A 3 s clip stops within +/-50 ms of 3 s on both.
- An incoming call or notification sound does not crash or desync the player.

## Results

Devices: _Android: model, OS version._ _iOS: model, OS version._ Build: _flavor, debug/profile/release._

### Start latency (ms), with preload

| Device | Limit | Runs (ms) | Min | Median | Max |
|---|---|---|---|---|---|
| Android | 3 s | | | | |
| Android | 5 s | | | | |
| Android | 10 s | | | | |
| iPhone | 3 s | | | | |
| iPhone | 5 s | | | | |
| iPhone | 10 s | | | | |

### Start latency (ms), 3 s, without preload

| Device | Runs (ms) | Min | Median | Max |
|---|---|---|---|---|
| Android | | | | |
| iPhone | | | | |

### Stop accuracy

Wall clock is from audio confirmed playing to the stop, so it includes any start offset. Position is where the player
reported it stopped.

| Device | Limit | Wall clock runs (ms) | Position runs (ms) | Worst error vs limit (ms) |
|---|---|---|---|---|
| Android | 3 s | | | |
| Android | 5 s | | | |
| Android | 10 s | | | |
| iPhone | 3 s | | | |
| iPhone | 5 s | | | |
| iPhone | 10 s | | | |

### Click or pop

| Device | Output | At start | At stop | Notes |
|---|---|---|---|---|
| Android | Speaker | | | |
| Android | Headphones | | | |
| iPhone | Speaker | | | |
| iPhone | Headphones | | | |

### Interruptions

| Device | Case | Crash | Reported on screen | Next Play worked | Notes |
|---|---|---|---|---|---|
| Android | Phone call | | | | |
| Android | Notification sound | | | | |
| Android | Headphones unplugged | | | | |
| Android | Other music ducks and returns | | | | |
| iPhone | Phone call | | | | |
| iPhone | Notification sound | | | | |
| iPhone | Headphones unplugged | | | | |
| iPhone | Other music ducks and returns | | | | |

## Conclusions

_To fill in after measuring: whether the targets are met, whether two players or the playlist is used, and anything
that needs a follow-up task._
