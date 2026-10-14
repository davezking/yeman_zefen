"""The cutter's decisions (versions, recuts, flags, errors) against fakes, then the same flow with real ffmpeg."""

import hashlib
import json

import pytest

import audio
from fakes import FakeClipApi, FakeS3
from yz.api_client import ApiError
from yz.clips import (
    CLIP_MS,
    Cutter,
    CutRequest,
    FfmpegTools,
    Selection,
    ToolError,
    clip_key,
    REGISTER_AT,
)
from yz.storage import ClipStore, SourceStore


class FakeTools:
    """Stands in for ffmpeg. A source is the JSON bytes {"dur": ms, "silence": ms}; a cut is a stable
    function of source and start, so it changes exactly when the real cut would."""

    def __init__(self, clip_ms=CLIP_MS):
        self.clip_ms = clip_ms
        self.cuts = []

    @staticmethod
    def _info(path):
        return json.loads(open(path, "rb").read()) if str(path).endswith(".src") else None

    def probe_duration_ms(self, path):
        info = self._info(path)
        return info["dur"] if info else self.clip_ms

    def detect_intro_start_ms(self, path):
        return self._info(path).get("silence", 0)

    def cut(self, src, start_ms, dest):
        self.cuts.append((str(src), start_ms))
        open(dest, "wb").write(b"clip|" + open(src, "rb").read() + b"|" + str(start_ms).encode())


def source(dur_ms=60_000, silence_ms=0, salt=""):
    return json.dumps({"dur": dur_ms, "silence": silence_ms, "salt": salt}).encode()


@pytest.fixture
def world():
    """An API with one track whose source audio is in storage."""
    api = FakeClipApi()
    src_s3, clip_s3 = FakeS3(), FakeS3()
    api.add_track(1, "source/1.mp3")
    src_s3.objects["source/1.mp3"] = source(60_000, silence_ms=2_000)

    def cutter(tools=None):
        return Cutter(api, SourceStore(src_s3), ClipStore(clip_s3), job_id=9, tools=tools or FakeTools())

    return api, src_s3, clip_s3, cutter


def sha(data):
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------- first cut


def test_first_cut_makes_both_clips_at_version_1_with_default_starts(world):
    api, _src, clip_s3, cutter = world
    stats = cutter().run(Selection(track_ids=(1,)))

    clips, _flags = api.registrations[0]
    by_type = {c["type"]: c for c in clips}
    assert by_type["intro"]["startMs"] == 2_000  # first sound, after 2 s of silence
    assert by_type["middle"]["startMs"] == 27_000  # 45% of 60 s
    for t in ("intro", "middle"):
        assert by_type[t]["r2Key"] == f"clips/1/{t}-v1.mp3" and by_type[t]["lengthMs"] == CLIP_MS
        data = clip_s3.objects[by_type[t]["r2Key"]]
        assert by_type[t]["sha256"] == sha(data) and by_type[t]["bytes"] == len(data)
    assert (stats.created, stats.updated, stats.unchanged, stats.errors) == (2, 0, 0, 0)
    assert [s for s, _ in api.statuses] == ["running", "succeeded"]
    assert api.statuses[-1][1]["created"] == 2


def test_uploads_are_public_immutable_audio(world):
    _api, _src, clip_s3, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    assert len(clip_s3.put_calls) == 2
    for call in clip_s3.put_calls:
        assert call["Bucket"] == "yz-clips" and call["ContentType"] == "audio/mpeg"
        assert call["CacheControl"] == "public, max-age=31536000, immutable"


def test_a_single_type_can_be_cut(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)), CutRequest(types=("middle",)))
    assert [c["type"] for c in api.registrations[0][0]] == ["middle"]


# ------------------------------------------------------ re-runs and versions


def test_rerunning_with_the_same_parameters_changes_nothing(world):
    api, _src, clip_s3, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    puts_before, versions_before = len(clip_s3.put_calls), {t: c["version"] for t, c in api.tracks[1]["clips"].items()}

    stats = cutter().run(Selection(track_ids=(1,)))
    assert (stats.created, stats.updated, stats.unchanged) == (0, 0, 2)
    assert len(clip_s3.put_calls) == puts_before  # nothing uploaded
    assert len(api.registrations) == 1  # and nothing sent
    assert {t: c["version"] for t, c in api.tracks[1]["clips"].items()} == versions_before


def test_a_new_start_makes_version_2_under_a_new_key_and_leaves_version_1_alone(world):
    api, _src, clip_s3, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    v1_bytes = clip_s3.objects["clips/1/intro-v1.mp3"]

    stats = cutter().run(Selection(track_ids=(1,)), CutRequest(types=("intro",), start_ms=9_000))
    assert (stats.created, stats.updated) == (0, 1)
    clip = api.registrations[1][0][0]
    assert (clip["startMs"], clip["r2Key"]) == (9_000, "clips/1/intro-v2.mp3")
    assert clip_s3.objects["clips/1/intro-v1.mp3"] == v1_bytes  # registered objects are never rewritten
    assert api.tracks[1]["clips"]["intro"]["version"] == 2 and api.tracks[1]["clips"]["middle"]["version"] == 1
    assert stats.errors == 0  # the version the API assigned is the one in the key


def test_the_same_recut_twice_does_not_bump_the_version_again(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    request = CutRequest(types=("intro",), start_ms=9_000)
    cutter().run(Selection(track_ids=(1,)), request)
    again = cutter().run(Selection(track_ids=(1,)), request)
    assert again.unchanged == 1 and api.tracks[1]["clips"]["intro"]["version"] == 2


def test_a_changed_source_gives_a_new_version_even_at_the_same_start(world):
    api, src_s3, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    src_s3.objects["source/1.mp3"] = source(60_000, silence_ms=2_000, salt="re-uploaded")
    stats = cutter().run(Selection(track_ids=(1,)))
    assert stats.updated == 2 and api.tracks[1]["clips"]["intro"]["version"] == 2


def test_a_clip_an_admin_moved_is_recut_at_their_start(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    # PATCH /admin/clips/:id stores the admin's start and sets the clip back to pending
    api.tracks[1]["clips"]["middle"].update(startMs=41_000, status="pending")

    stats = cutter().run(Selection(track_ids=(1,)))
    clip = api.registrations[1][0][0]
    assert (clip["type"], clip["startMs"], clip["r2Key"]) == ("middle", 41_000, "clips/1/middle-v2.mp3")
    assert (stats.updated, stats.unchanged) == (1, 1)  # the intro is untouched
    assert api.tracks[1]["clips"]["middle"]["status"] == "ready"


def test_a_pending_clip_that_comes_out_identical_still_gets_the_version_the_api_assigns(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    api.tracks[1]["clips"]["middle"]["status"] = "pending"  # not ready, so the API will bump it
    stats = cutter().run(Selection(track_ids=(1,)))
    assert api.registrations[1][0][0]["r2Key"] == "clips/1/middle-v2.mp3" and stats.errors == 0


def test_all_missing_leaves_ready_clips_alone(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    api.tracks[1]["clips"]["middle"]["status"] = "failed"
    tools = FakeTools()
    stats = cutter(tools).run(Selection(missing=True), CutRequest(only_not_ready=True))
    assert [c["type"] for c in api.registrations[1][0]] == ["middle"]
    assert len(tools.cuts) == 1 and stats.unchanged == 0  # the ready intro was not even cut


# ------------------------------------------------------------ start points


def test_default_starts_are_nudged_to_leave_a_whole_clip(world):
    api, src_s3, _clips, cutter = world
    api.add_track(2, "source/2.mp3")
    src_s3.objects["source/2.mp3"] = source(15_000, silence_ms=9_000)  # silence ends too late for a 10 s clip
    cutter().run(Selection(track_ids=(2,)))
    starts = {c["type"]: c["startMs"] for c in api.registrations[0][0]}
    assert starts == {"intro": 5_000, "middle": 5_000}  # 15 s - 10 s; 45% would be 6.75 s


def test_a_chosen_start_is_never_moved(world):
    api, _src, clip_s3, cutter = world
    stats = cutter().run(Selection(track_ids=(1,)), CutRequest(types=("intro",), start_ms=55_000))  # only 5 s left
    assert stats.errors == 1 and "55000" in stats.error_samples[0]
    assert not clip_s3.put_calls and api.registrations == [([], [])]  # no clip registered...
    assert api.duration_posts == [[{"trackId": 1, "durationMs": 60_000}]]  # ...but the source's length is recorded
    assert [s for s, _ in api.statuses] == ["running", "succeeded"]  # one bad request is not a failed job


# --------------------------------------------------------------- short/missing


def test_a_short_source_is_flagged_but_still_cut_if_it_fits_a_clip(world):
    api, src_s3, _clips, cutter = world
    api.add_track(2, "source/2.mp3")
    src_s3.objects["source/2.mp3"] = source(18_000)
    stats = cutter().run(Selection(track_ids=(2,)))
    clips, flags = api.registrations[0]
    assert len(clips) == 2 and flags == [{"trackId": 2, "reason": "short_audio", "details": {"durationMs": 18_000}}]
    assert (stats.flagged, stats.created, stats.errors) == (1, 2, 0)


def test_a_source_shorter_than_a_clip_is_flagged_and_cannot_be_cut(world):
    api, src_s3, clip_s3, cutter = world
    api.add_track(2, "source/2.mp3")
    src_s3.objects["source/2.mp3"] = source(8_000)
    stats = cutter().run(Selection(track_ids=(2,)))
    clips, flags = api.registrations[0]
    assert clips == [] and flags[0]["reason"] == "short_audio"
    assert (stats.flagged, stats.created, stats.errors) == (1, 0, 1)
    assert not clip_s3.put_calls


def test_a_source_that_is_not_in_storage_is_flagged_missing_audio(world):
    api, src_s3, _clips, cutter = world
    api.add_track(2, "source/gone.mp3")
    stats = cutter().run(Selection(track_ids=(2,)))
    assert api.registrations[0][1] == [
        {"trackId": 2, "reason": "missing_audio", "details": {"cause": "not_in_storage", "key": "source/gone.mp3"}}
    ]
    assert stats.flagged == 1 and stats.errors == 0


def test_a_track_with_no_source_key_is_flagged_missing_audio(world):
    api, _src, _clips, cutter = world
    api.add_track(2, source_key=None)
    cutter().run(Selection(track_ids=(2,)))
    assert api.registrations[0][1][0]["details"] == {"cause": "no_source_key"}


def test_flags_are_idempotent_when_the_job_is_rerun(world):
    api, _src, _clips, cutter = world
    api.add_track(2, "source/gone.mp3")
    cutter().run(Selection(track_ids=(2,)))
    cutter().run(Selection(track_ids=(2,)))
    assert len(api.open_flags) == 1  # the API de-duplicates; the cutter just re-reports


def test_one_bad_track_does_not_stop_the_others(world):
    api, src_s3, _clips, cutter = world
    api.add_track(2, "source/gone.mp3")
    api.add_track(3, "source/3.mp3")
    src_s3.objects["source/3.mp3"] = source(60_000)
    stats = cutter().run(Selection(track_ids=(1, 2, 3)))
    assert sorted({c["trackId"] for c in api.registrations[0][0]}) == [1, 3] and stats.flagged == 1


# ------------------------------------------------------------------ guards


def test_a_clip_of_the_wrong_length_is_never_uploaded_or_registered(world):
    api, _src, clip_s3, cutter = world
    stats = cutter(FakeTools(clip_ms=10_500)).run(Selection(track_ids=(1,)))
    assert stats.errors == 2 and "10500" in stats.error_samples[0]
    assert not clip_s3.put_calls and api.registrations == [([], [])]  # only the duration was sent


def test_a_version_mismatch_from_the_api_is_reported(world):
    api, _src, _clips, cutter = world
    original = api.post_clips

    def drifted(job_id, clips, flags=None, durations=None):
        out = original(job_id, clips, flags, durations)
        for r in out["results"]:
            r["version"] += 1  # the API says it assigned a different version than the key promised
        return out

    api.post_clips = drifted
    stats = cutter().run(Selection(track_ids=(1,)))
    assert stats.errors == 2 and "version" in stats.error_samples[0]


def test_unknown_track_ids_are_reported(world):
    api, _src, _clips, cutter = world
    stats = cutter().run(Selection(track_ids=(1, 404)))
    assert stats.errors == 1 and "404" in stats.error_samples[0] and stats.created == 2


def test_a_storage_failure_fails_the_job(world):
    api, _src, clip_s3, cutter = world
    clip_s3.put_object = lambda **kw: (_ for _ in ()).throw(RuntimeError("R2 is down"))
    with pytest.raises(RuntimeError, match="R2 is down"):
        cutter().run(Selection(track_ids=(1,)))
    assert [s for s, _ in api.statuses] == ["running", "failed"] and "R2 is down" in api.statuses[-1][1]["failure"]


def test_an_api_failure_while_registering_fails_the_job(world):
    api, _src, _clips, cutter = world
    api.post_clips = lambda *a, **k: (_ for _ in ()).throw(ApiError(500, "internal", "boom"))
    with pytest.raises(ApiError):
        cutter().run(Selection(track_ids=(1,)))
    assert api.statuses[-1][0] == "failed"


# ------------------------------------------------------------- selection


def test_all_missing_pages_through_the_catalog_and_honours_a_limit(world):
    api, src_s3, _clips, cutter = world
    for i in range(2, 8):
        api.add_track(i, f"source/{i}.mp3")
        src_s3.objects[f"source/{i}.mp3"] = source(60_000)
    api.get_clip_targets_calls = []
    original = api.get_clip_targets
    api.get_clip_targets = lambda **kw: (api.get_clip_targets_calls.append(kw), original(**{**kw, "limit": 2}))[1]

    stats = cutter().run(Selection(missing=True, limit=5), CutRequest(only_not_ready=True))
    assert stats.tracks == 5  # stopped at the limit
    assert [kw["after"] for kw in api.get_clip_targets_calls] == [0, 2, 4]  # followed `next`


def test_clips_are_registered_in_batches_under_the_api_limit(world):
    api, src_s3, _clips, cutter = world
    for i in range(2, 61):  # 60 tracks x 2 clips = 120 clips
        api.add_track(i, f"source/{i}.mp3")
        src_s3.objects[f"source/{i}.mp3"] = source(60_000)
    cutter().run(Selection(track_ids=tuple(range(1, 61))))
    sizes = [len(clips) for clips, _ in api.registrations]
    assert sum(sizes) == 120 and max(sizes) <= 100 and len(sizes) >= 2
    assert REGISTER_AT <= 100


# ------------------------------------------------- the same flow, real ffmpeg

needs_ffmpeg = audio.needs_ffmpeg


@pytest.fixture
def real_world(tmp_path):
    src = tmp_path / "source.mp3"
    audio.make_source(src)
    api, src_s3, clip_s3 = FakeClipApi(), FakeS3(), FakeS3()
    api.add_track(1, "source/1.mp3")
    src_s3.objects["source/1.mp3"] = src.read_bytes()
    return api, clip_s3, lambda: Cutter(api, SourceStore(src_s3), ClipStore(clip_s3), job_id=9, tools=FfmpegTools())


@needs_ffmpeg
def test_real_audio_rerun_keeps_the_checksum_and_a_new_start_bumps_the_version(real_world, tmp_path):
    api, clip_s3, cutter = real_world
    first = cutter().run(Selection(track_ids=(1,)))
    assert first.errors == 0 and first.created == 2
    intro = {c["type"]: c for c in api.registrations[0][0]}["intro"]
    assert abs(intro["startMs"] - 2_000) <= 60 and intro["r2Key"] == "clips/1/intro-v1.mp3"

    again = cutter().run(Selection(track_ids=(1,)))  # same parameters, same bytes
    assert (again.unchanged, again.created, again.updated) == (2, 0, 0) and len(api.registrations) == 1
    assert api.tracks[1]["clips"]["intro"]["sha256"] == intro["sha256"]

    moved = cutter().run(Selection(track_ids=(1,)), CutRequest(types=("intro",), start_ms=12_345))
    assert moved.updated == 1 and moved.errors == 0
    v2 = api.tracks[1]["clips"]["intro"]
    assert (v2["version"], v2["r2Key"], v2["startMs"]) == (2, "clips/1/intro-v2.mp3", 12_345)
    assert v2["sha256"] != intro["sha256"] and sha(clip_s3.objects[v2["r2Key"]]) == v2["sha256"]


@needs_ffmpeg
def test_real_audio_uploaded_clips_meet_the_spec(real_world, tmp_path):
    api, clip_s3, cutter = real_world
    cutter().run(Selection(track_ids=(1,)))
    for clip_type in ("intro", "middle"):
        meta = api.tracks[1]["clips"][clip_type]
        path = tmp_path / f"{clip_type}.mp3"
        path.write_bytes(clip_s3.objects[meta["r2Key"]])
        assert abs(float(audio.probe(path, "format=duration")) * 1000 - CLIP_MS) <= 30
        assert audio.probe(path, "stream=bit_rate") == "128000"
        assert meta["bytes"] == path.stat().st_size and meta["sha256"] == sha(path.read_bytes())
        samples = audio.decode_mono(path)
        assert max(abs(x) for x in samples[:4]) <= 50 and audio.rms(samples, 5.0, 5.1) > 500  # no click, not silent


@needs_ffmpeg
def test_real_audio_the_middle_clip_starts_at_45_percent(real_world):
    api, _clips, cutter = real_world
    cutter().run(Selection(track_ids=(1,)))
    middle = api.tracks[1]["clips"]["middle"]["startMs"]
    assert abs(middle - 0.45 * 40_046) <= 40  # 45% of the probed length, which is good to a frame or two


@needs_ffmpeg
def test_real_audio_a_source_that_is_too_short_is_flagged(tmp_path):
    api, src_s3, clip_s3 = FakeClipApi(), FakeS3(), FakeS3()
    short = tmp_path / "short.mp3"
    audio.make_source(short, silence_s=0.5, low_s=4, high_s=4)  # about 8.5 s
    api.add_track(1, "source/short.mp3")
    src_s3.objects["source/short.mp3"] = short.read_bytes()
    stats = Cutter(api, SourceStore(src_s3), ClipStore(clip_s3), 9, tools=FfmpegTools()).run(Selection(track_ids=(1,)))
    assert api.registrations[0][1][0]["reason"] == "short_audio" and stats.errors == 1 and not clip_s3.put_calls


@needs_ffmpeg
def test_real_audio_a_corrupt_source_is_an_error_not_a_crash(tmp_path):
    api, src_s3, clip_s3 = FakeClipApi(), FakeS3(), FakeS3()
    api.add_track(1, "source/bad.mp3")
    src_s3.objects["source/bad.mp3"] = b"definitely not audio" * 100
    stats = Cutter(api, SourceStore(src_s3), ClipStore(clip_s3), 9, tools=FfmpegTools()).run(Selection(track_ids=(1,)))
    assert stats.errors == 1 and not clip_s3.put_calls and api.statuses[-1][0] == "succeeded"


# ------------------------------------------------------------- durations


def test_the_measured_source_length_is_recorded_on_the_track(world):
    api, _src, _clips, cutter = world
    stats = cutter().run(Selection(track_ids=(1,)))
    assert api.duration_posts[0] == [{"trackId": 1, "durationMs": 60_000}]
    assert api.tracks[1]["durationMs"] == 60_000
    assert stats.durations == 1 and api.statuses[-1][1]["durations"] == 1
    assert len(api.registrations) == 1  # sent with the clips, not in a call of its own


def test_a_length_that_is_already_stored_is_not_sent_again(world):
    api, _src, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    again = cutter().run(Selection(track_ids=(1,)))  # clips unchanged, length unchanged
    assert again.durations == 0 and len(api.registrations) == 1  # nothing to send at all


def test_a_changed_source_length_is_sent_again(world):
    api, src_s3, _clips, cutter = world
    cutter().run(Selection(track_ids=(1,)))
    src_s3.objects["source/1.mp3"] = source(61_500, silence_ms=2_000)
    stats = cutter().run(Selection(track_ids=(1,)))
    assert stats.durations == 1 and api.tracks[1]["durationMs"] == 61_500


def test_a_short_source_still_gets_its_length_recorded(world):
    api, src_s3, _clips, cutter = world
    api.add_track(2, "source/2.mp3")
    src_s3.objects["source/2.mp3"] = source(8_000)  # too short to cut
    cutter().run(Selection(track_ids=(2,)))
    assert api.duration_posts[0] == [{"trackId": 2, "durationMs": 8_000}]


def test_missing_audio_records_no_length(world):
    api, _src, _clips, cutter = world
    api.add_track(2, "source/gone.mp3")
    cutter().run(Selection(track_ids=(2,)))
    assert api.duration_posts == [[]]


def test_durations_alone_trigger_a_flush_under_the_api_limit(world):
    api, src_s3, _clips, cutter = world
    for i in range(2, 121):  # 120 tracks whose clips are already registered, only the lengths are new
        api.add_track(i, f"source/{i}.mp3")
        src_s3.objects[f"source/{i}.mp3"] = source(60_000)
    cutter().run(Selection(track_ids=tuple(range(1, 121))), CutRequest(types=()))  # cut nothing, just measure
    sizes = [len(d) for d in api.duration_posts]
    assert sum(sizes) == 120 and max(sizes) <= 100 and len(sizes) >= 2
