"""Helpers for tests that run real ffmpeg: build a synthetic source and measure what comes out."""

import array
import math
import os
import shutil
import subprocess

import pytest

SR = 44_100
HAVE_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None

# Locally, a machine without ffmpeg skips the real-audio tests. In CI (which installs ffmpeg) a missing
# ffmpeg is a broken setup, so the tests run and fail instead of quietly not running.
needs_ffmpeg = pytest.mark.skipif(
    not HAVE_FFMPEG and not os.environ.get("CI"), reason="ffmpeg and ffprobe are not installed"
)

# The synthetic source: 2 s of silence, 4 s of 440 Hz, then 34 s of 880 Hz (mono, 192 kbps MP3, ~40 s).
# The pitch changes at exactly 6.000 s, so where 880 Hz begins in a clip shows where the clip started.
SILENCE_S, LOW_S, HIGH_S = 2, 4, 34
SWITCH_S = SILENCE_S + LOW_S


def make_source(path, silence_s=SILENCE_S, low_s=LOW_S, high_s=HIGH_S):
    graph = (
        f"anullsrc=r=44100:cl=mono,atrim=0:{silence_s}[a];"
        f"sine=f=440:r=44100,atrim=0:{low_s},volume=0.5[b];"
        f"sine=f=880:r=44100,atrim=0:{high_s},volume=0.5[c];"
        "[a][b][c]concat=n=3:v=0:a=1"
    )
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-filter_complex", graph, "-b:a", "192k", str(path)],
        check=True,
    )


def probe(path, entry):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", entry, "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def decode_mono(path):
    raw = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(path), "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True, check=True,
    ).stdout
    samples = array.array("h")
    samples.frombytes(raw)
    return samples


def rms(samples, start_s, end_s):
    seg = samples[int(start_s * SR) : int(end_s * SR)]
    return math.sqrt(sum(x * x for x in seg) / len(seg)) if seg else 0.0


def frequency(samples, start_s, end_s):
    """Pitch of a short stretch, by counting zero crossings."""
    seg = samples[int(start_s * SR) : int(end_s * SR)]
    crossings = sum(1 for i in range(1, len(seg)) if (seg[i - 1] < 0) != (seg[i] < 0))
    return crossings / 2 / ((end_s - start_s))


def high_pitch_begins_ms(samples, limit_ms=200):
    """Milliseconds into the clip at which the 880 Hz section starts (None if not within `limit_ms`)."""
    for ms in range(limit_ms):
        if frequency(samples, ms / 1000, ms / 1000 + 0.004) > 660:
            return ms
    return None
