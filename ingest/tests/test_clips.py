"""The ffmpeg half of the cutter, run for real on a synthetic source: length, start point, fades, checksum."""

import hashlib
import re

import pytest

import audio
from yz.clips import (
    BITRATE,
    CLIP_MS,
    ENCODE_MS,
    FADE_MS,
    MIDDLE_FRACTION,
    TOLERANCE_MS,
    FfmpegTools,
    ToolError,
    clip_key,
    intro_start_from_silence,
    key_version,
    parse_silencedetect,
    require_ffmpeg,
)

needs_ffmpeg = audio.needs_ffmpeg
tools = FfmpegTools()


@pytest.fixture(scope="module")
def source(tmp_path_factory):
    path = tmp_path_factory.mktemp("src") / "source.mp3"
    audio.make_source(path)
    return path


def cut(source, start_ms, tmp_path, name="clip.mp3"):
    out = tmp_path / name
    tools.cut(source, start_ms, out)
    return out


# ------------------------------------------------------------- pure helpers


def test_clip_key_and_version_round_trip():
    assert clip_key(42, "intro", 3) == "clips/42/intro-v3.mp3"
    assert key_version("clips/42/intro-v3.mp3") == 3 and key_version("nonsense.mp3") is None


SILENCE_OUTPUT = """
[silencedetect @ 0x1] silence_start: 0
[silencedetect @ 0x1] silence_end: 2.04379 | silence_duration: 2.04379
[silencedetect @ 0x1] silence_start: 31.2
[silencedetect @ 0x1] silence_end: 33.5 | silence_duration: 2.3
"""


def test_parse_silencedetect():
    assert parse_silencedetect(SILENCE_OUTPUT) == [(0.0, 2.04379), (31.2, 33.5)]
    assert parse_silencedetect("silence_start: 5.0") == [(5.0, None)]  # runs to the end of the scan
    assert parse_silencedetect("nothing here") == []


@pytest.mark.parametrize(
    "stretches,expected",
    [
        ([(0.0, 2.04379), (31.2, 33.5)], 2044),  # leading silence: start at the first sound
        ([(-0.007, 1.5)], 1500),  # reported a hair before 0
        ([(31.2, 33.5)], 0),  # silence later in the song is not a lead-in
        ([(0.0, None)], 0),  # silent for the whole scan: nothing to skip to
        ([], 0),
    ],
)
def test_intro_start_from_silence(stretches, expected):
    assert intro_start_from_silence(stretches) == expected


def test_encode_length_is_chosen_so_both_ways_of_measuring_are_within_tolerance():
    # 383 frames of 1152 samples = 10.005 s by ffprobe; the audio inside is ENCODE_MS.
    assert abs(ENCODE_MS - CLIP_MS) <= TOLERANCE_MS
    frames = 383
    assert abs(frames * 1152 / 44_100 * 1000 - CLIP_MS) <= TOLERANCE_MS


# ------------------------------------------------------------- real ffmpeg


@needs_ffmpeg
def test_probe_duration_of_the_source(source):
    assert abs(tools.probe_duration_ms(source) - 40_046) <= 60  # whole MP3 frames are 26 ms; builds differ by a frame or two


@needs_ffmpeg
@pytest.mark.parametrize("start_ms", [0, 6_000, 20_500, 29_000])
def test_a_clip_is_ten_seconds_by_ffprobe_and_by_decoding(source, tmp_path, start_ms):
    clip = cut(source, start_ms, tmp_path)
    assert abs(float(audio.probe(clip, "format=duration")) * 1000 - CLIP_MS) <= TOLERANCE_MS
    decoded_ms = len(audio.decode_mono(clip)) / audio.SR * 1000
    assert abs(decoded_ms - CLIP_MS) <= TOLERANCE_MS


@needs_ffmpeg
def test_clip_format_is_cbr_128_kbps_mp3_at_44_1_khz_stereo(source, tmp_path):
    clip = cut(source, 6_000, tmp_path)
    assert audio.probe(clip, "stream=codec_name") == "mp3"
    assert audio.probe(clip, "stream=bit_rate") == str(int(BITRATE[:-1]) * 1000)
    assert audio.probe(clip, "stream=sample_rate") == "44100"
    assert audio.probe(clip, "stream=channels") == "2"
    # constant bit rate: the file size follows from the duration (+ a small header frame)
    assert abs(clip.stat().st_size - 16_000 * float(audio.probe(clip, "format=duration"))) < 1_500


@needs_ffmpeg
@pytest.mark.parametrize("offset_ms", [0, 30, 50])
def test_clip_starts_exactly_at_the_start_point(source, tmp_path, offset_ms):
    """The pitch changes at 6.000 s; starting `offset_ms` earlier puts the change `offset_ms` into the clip."""
    samples = audio.decode_mono(cut(source, 6_000 - offset_ms, tmp_path))
    begins = audio.high_pitch_begins_ms(samples)
    assert begins is not None and abs(begins - offset_ms) <= 3, f"880 Hz began at {begins} ms, expected {offset_ms}"


@needs_ffmpeg
def test_clip_fades_in_and_out_without_a_click(source, tmp_path):
    samples = audio.decode_mono(cut(source, 6_000, tmp_path))
    steady = audio.rms(samples, 5.0, 5.1)
    assert steady > 500  # the clip is loud in the middle and stays loud all the way through
    assert audio.rms(samples, 9.0, 9.1) == pytest.approx(steady, rel=0.1)
    # first sample: silence, then a ramp over FADE_MS
    assert max(abs(x) for x in samples[:4]) <= 50
    assert audio.rms(samples, 0.0, 0.002) < steady * 0.15
    assert audio.rms(samples, FADE_MS / 2000 - 0.001, FADE_MS / 2000 + 0.001) == pytest.approx(steady * 0.5, rel=0.35)
    assert audio.rms(samples, FADE_MS / 1000 + 0.002, FADE_MS / 1000 + 0.006) == pytest.approx(steady, rel=0.1)
    # and the same at the end
    assert max(abs(x) for x in samples[-4:]) <= 50
    assert audio.rms(samples, len(samples) / audio.SR - 0.002, len(samples) / audio.SR) < steady * 0.15


@needs_ffmpeg
def test_same_input_and_start_give_the_same_bytes(source, tmp_path):
    a = cut(source, 6_000, tmp_path, "a.mp3").read_bytes()
    b = cut(source, 6_000, tmp_path, "b.mp3").read_bytes()
    assert hashlib.sha256(a).hexdigest() == hashlib.sha256(b).hexdigest()
    assert hashlib.sha256(a).hexdigest() != hashlib.sha256(cut(source, 6_001, tmp_path, "c.mp3").read_bytes()).hexdigest()


@needs_ffmpeg
def test_the_bytes_do_not_depend_on_the_ffmpeg_version(source, tmp_path):
    """The checksum is how a re-cut is recognised as unchanged, so nothing build-specific may be written
    into the file: no tags, no empty-but-sized ID3 frames, and no ffmpeg version string."""
    clip = cut(source, 6_000, tmp_path)
    raw = clip.read_bytes()
    assert audio.probe(clip, "format_tags") == ""
    assert raw[:3] == b"ID3" and raw[6:10] == bytes([0, 0, 0, 10])  # an empty ID3v2 header, nothing in it
    assert not re.search(rb"Lavf\d", raw)  # bitexact writes "Lavf lame", not "Lavf61.1.100"


@needs_ffmpeg
def test_silence_at_the_start_is_skipped(source):
    assert abs(tools.detect_intro_start_ms(source) - 2_000) <= 60


@needs_ffmpeg
def test_no_leading_silence_means_start_at_zero(tmp_path):
    path = tmp_path / "loud.mp3"
    audio.make_source(path, silence_s=0.001, low_s=15, high_s=15)  # sound from the first moment
    assert tools.detect_intro_start_ms(path) == 0


@needs_ffmpeg
def test_cutting_a_file_that_is_not_audio_raises(tmp_path):
    bad = tmp_path / "bad.mp3"
    bad.write_bytes(b"this is not audio")
    with pytest.raises(ToolError):
        tools.cut(bad, 0, tmp_path / "out.mp3")
    with pytest.raises(ToolError):
        tools.probe_duration_ms(bad)


def test_require_ffmpeg_names_what_is_missing(monkeypatch):
    monkeypatch.setattr("yz.clips.shutil.which", lambda name: None)
    with pytest.raises(ToolError, match="ffmpeg and ffprobe"):
        require_ffmpeg()


def test_middle_clip_default_is_45_percent():
    assert MIDDLE_FRACTION == 0.45
