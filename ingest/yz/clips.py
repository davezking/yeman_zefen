"""Cut the intro and middle clips from source audio, store them in R2 and register them with the API.

Clip spec: 10 s of MP3, CBR 128 kbps, 44.1 kHz stereo, starting exactly at the chosen start point, with a
30 ms fade in and out. Clips live in the public bucket `yz-clips` as `clips/{trackId}/{type}-v{version}.mp3`
and are registered with `POST /admin/ingest/clips`.

Versions and keys. The version is part of the key and the API owns it: registering a clip bumps its version
exactly when something about it changed (or it was not ready). So the cutter works out first whether the clip
differs from what is registered. If it does not, nothing is uploaded or sent. If it does, it uploads to
`version + 1` and registers that key, which is the version the API will assign. Objects are therefore never
rewritten once registered, which is what lets them be cached forever.
"""

from __future__ import annotations

import hashlib
import logging
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

CLIP_TYPES = ("intro", "middle")
CLIP_MS = 10_000  # the clip's nominal length: what is registered as lengthMs
FADE_MS = 30
SAMPLE_RATE = 44_100
BITRATE = "128k"
TOLERANCE_MS = 30  # a finished clip must measure 10.0 s +/- this, by ffprobe

# MP3 is framed in 1152-sample (26.1 ms) frames and the encoder adds 1105 samples of delay, so ffprobe
# reports the length of the whole frames: encoding exactly 10.000 s gives 384 frames = 10.031 s, which is
# just outside the tolerance, while the decoded audio is exactly 10.000 s. Encoding 9.975 s gives 383 frames
# = 10.005 s by ffprobe and 9.975 s decoded, so both ways of measuring the clip are within 30 ms of 10 s.
ENCODE_MS = 9_975

SHORT_AUDIO_MS = 25_000  # a source shorter than this is flagged short_audio
MIDDLE_FRACTION = 0.45  # default start of the middle clip, as a share of the source's duration
SILENCE_DB = -40  # below this is silence...
SILENCE_SECONDS = 0.3  # ...once it lasts this long
SILENCE_SCAN_SECONDS = 120  # only the start of the source is searched for leading silence
LEADING_SILENCE_EPSILON = 0.1  # silence "starting at 0" may be reported a few ms either side of it


class ToolError(RuntimeError):
    """ffmpeg or ffprobe failed, or produced something unusable."""


def clip_key(track_id: int, clip_type: str, version: int) -> str:
    return f"clips/{track_id}/{clip_type}-v{version}.mp3"


def key_version(key: str) -> int | None:
    m = re.search(r"-v(\d+)\.mp3$", key)
    return int(m.group(1)) if m else None


# ------------------------------------------------------------------- ffmpeg


def require_ffmpeg() -> None:
    missing = [t for t in ("ffmpeg", "ffprobe") if shutil.which(t) is None]
    if missing:
        raise ToolError(f"{' and '.join(missing)} not found on PATH (install ffmpeg)")


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        tail = " | ".join(result.stderr.strip().splitlines()[-3:])
        raise ToolError(f"{cmd[0]} failed ({result.returncode}): {tail}")
    return result


_SILENCE_START = re.compile(r"silence_start: (-?[\d.]+)")
_SILENCE_END = re.compile(r"silence_end: (-?[\d.]+)")


def parse_silencedetect(stderr: str) -> list[tuple[float, float | None]]:
    """(start, end) of each silent stretch ffmpeg reported, in seconds. A stretch that runs to the end
    of the scanned audio has no `silence_end`, so its end is None."""
    stretches: list[tuple[float, float | None]] = []
    for line in stderr.splitlines():
        if (m := _SILENCE_START.search(line)) is not None:
            stretches.append((float(m.group(1)), None))
        elif (m := _SILENCE_END.search(line)) is not None and stretches:
            stretches[-1] = (stretches[-1][0], float(m.group(1)))
    return stretches


def intro_start_from_silence(stretches: list[tuple[float, float | None]]) -> int:
    """Where the first sound is, in ms: the end of a silence that starts at the very beginning, else 0."""
    if stretches and stretches[0][0] <= LEADING_SILENCE_EPSILON and stretches[0][1] is not None:
        return max(0, round(stretches[0][1] * 1000))
    return 0


class FfmpegTools:
    """The three things the cutter needs from ffmpeg. Tests of the cutter's decisions swap in a fake."""

    def probe_duration_ms(self, path: str | Path) -> int:
        out = _run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)])
        try:
            return round(float(out.stdout.strip()) * 1000)
        except ValueError:
            raise ToolError(f"ffprobe gave no duration for {path}") from None

    def detect_intro_start_ms(self, path: str | Path) -> int:
        """Skip leading silence (-40 dB for at least 0.3 s)."""
        out = _run(
            [
                "ffmpeg", "-hide_banner", "-nostdin", "-t", str(SILENCE_SCAN_SECONDS), "-i", str(path), "-vn",
                "-af", f"silencedetect=noise={SILENCE_DB}dB:d={SILENCE_SECONDS}", "-f", "null", "-",
            ]
        )
        return intro_start_from_silence(parse_silencedetect(out.stderr))

    def cut(self, src: str | Path, start_ms: int, dest: str | Path) -> None:
        """Decode, trim to the start point at sample accuracy, fade, and encode.

        The trim is done inside the filter graph (atrim, then asetpts to restart the clock at 0) rather than
        with an output-side -ss: with -ss the fades are timed against the source file's clock, which puts
        the fade-in before the clip starts and the fade-out a few seconds in, leaving the rest silent."""
        fade, total = FADE_MS / 1000, ENCODE_MS / 1000
        graph = (
            f"atrim=start={start_ms / 1000:.3f}:duration={total:.3f},asetpts=PTS-STARTPTS,"
            f"afade=t=in:st=0:d={fade:.3f},afade=t=out:st={total - fade:.3f}:d={fade:.3f}"
        )
        _run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", str(src), "-vn", "-af", graph,
                "-ar", str(SAMPLE_RATE), "-ac", "2", "-c:a", "libmp3lame", "-b:a", BITRATE,
                # Same input and settings must give the same bytes, whatever the ffmpeg build.
                "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(dest),
            ]
        )


# ------------------------------------------------------------------- model


@dataclass(frozen=True)
class ExistingClip:
    type: str
    start_ms: int
    length_ms: int
    r2_key: str | None
    sha256: str | None
    bytes: int | None
    version: int
    status: str

    @classmethod
    def from_api(cls, d: dict) -> ExistingClip:
        return cls(d["type"], d["startMs"], d["lengthMs"], d["r2Key"], d["sha256"], d["bytes"], d["version"], d["status"])


@dataclass(frozen=True)
class Target:
    id: int
    status: str
    source_audio_key: str | None
    duration_ms: int | None
    clips: dict[str, ExistingClip]

    @classmethod
    def from_api(cls, d: dict) -> Target:
        clips = {c["type"]: ExistingClip.from_api(c) for c in d.get("clips", [])}
        return cls(d["id"], d["status"], d.get("sourceAudioKey"), d.get("durationMs"), clips)


@dataclass(frozen=True)
class Selection:
    """Which tracks to cut: named ids, or every track that is missing a ready clip."""

    track_ids: tuple[int, ...] = ()
    missing: bool = False
    limit: int | None = None  # for `missing`: at most this many tracks


@dataclass(frozen=True)
class CutRequest:
    types: tuple[str, ...] = CLIP_TYPES
    start_ms: int | None = None  # an explicit start (a recut); needs exactly one track and one type
    only_not_ready: bool = False  # leave clips that are already ready alone (--all-missing)


@dataclass
class CutStats:
    tracks: int = 0
    created: int = 0  # clips cut for the first time
    updated: int = 0  # clips cut again with a new version
    unchanged: int = 0  # clips that came out identical to what is registered
    flagged: int = 0
    durations: int = 0  # source lengths recorded on tracks (new or changed)
    errors: int = 0
    error_samples: list[str] = field(default_factory=list)

    def error(self, message: str) -> None:
        self.errors += 1
        log.warning(message)
        if len(self.error_samples) < 20:
            self.error_samples.append(message)

    def summary(self) -> dict:
        return {
            "tracks": self.tracks, "created": self.created, "updated": self.updated, "unchanged": self.unchanged,
            "flagged": self.flagged, "durations": self.durations, "errors": self.errors,
            "error_samples": self.error_samples,
        }


# ------------------------------------------------------------------ cutter

REGISTER_AT = 90  # send to the API once this many clips, flags or durations wait (its limit is 100 of each)


class Cutter:
    def __init__(self, api, source_store, clip_store, job_id: int, *, tools=None, gh_run_url: str | None = None):
        self.api = api
        self.source_store = source_store
        self.clip_store = clip_store
        self.job_id = job_id
        self.tools = tools if tools is not None else FfmpegTools()
        self.gh_run_url = gh_run_url
        self.stats = CutStats()
        self._clips: list[dict] = []
        self._flags: list[dict] = []
        self._durations: list[dict] = []

    # -------------------------------------------------------------- run

    def run(self, selection: Selection, request: CutRequest = CutRequest()) -> CutStats:
        self.api.set_job_status(self.job_id, "running", gh_run_url=self.gh_run_url)
        try:
            targets = self._load_targets(selection)
            with tempfile.TemporaryDirectory(prefix="yz-cut-") as workdir:
                for target in targets:
                    self._cut_track(target, request, Path(workdir))
                    if max(len(self._clips), len(self._flags), len(self._durations)) >= REGISTER_AT:
                        self._register()
            self._register()
        except Exception as exc:
            log.error("run failed: %s", exc)
            try:
                self.api.set_job_status(self.job_id, "failed", summary={**self.stats.summary(), "failure": str(exc)})
            except Exception:
                log.exception("could not report the failure to the API")
            raise
        self.api.set_job_status(self.job_id, "succeeded", summary=self.stats.summary())
        return self.stats

    def _load_targets(self, selection: Selection) -> list[Target]:
        targets: list[Target] = []
        if selection.track_ids:
            wanted = list(dict.fromkeys(selection.track_ids))
            for i in range(0, len(wanted), 200):
                chunk = wanted[i : i + 200]
                found = {t["id"]: Target.from_api(t) for t in self.api.get_clip_targets(track_ids=chunk)["tracks"]}
                for track_id in chunk:
                    if track_id in found:
                        targets.append(found[track_id])
                    else:
                        self.stats.error(f"track {track_id} does not exist")
        if selection.missing:
            after = 0
            while selection.limit is None or len(targets) < selection.limit:
                page = self.api.get_clip_targets(missing=True, after=after, limit=100)
                targets.extend(Target.from_api(t) for t in page["tracks"])
                if page["next"] is None:
                    break
                after = page["next"]
            if selection.limit is not None:
                targets = targets[: selection.limit]
        return targets

    # ------------------------------------------------------------ one track

    def _cut_track(self, target: Target, request: CutRequest, workdir: Path) -> None:
        self.stats.tracks += 1
        if not target.source_audio_key:
            self._flag(target.id, "missing_audio", cause="no_source_key")
            return
        src = workdir / f"{target.id}.src"
        if not self.source_store.download(target.source_audio_key, src):
            self._flag(target.id, "missing_audio", cause="not_in_storage", key=target.source_audio_key)
            return
        try:
            duration_ms = self.tools.probe_duration_ms(src)
            # The scraper cannot know a song's length; the cutter measures it, so it records it. The clip
            # editor needs it to check a new start time, and duplicate detection to compare lengths.
            if duration_ms != target.duration_ms:
                self._durations.append({"trackId": target.id, "durationMs": duration_ms})
                self.stats.durations += 1
            if duration_ms < SHORT_AUDIO_MS:
                self._flag(target.id, "short_audio", durationMs=duration_ms)
            if duration_ms < CLIP_MS:
                raise ValueError(f"source is {duration_ms} ms, shorter than a {CLIP_MS} ms clip")
            for clip_type in request.types:
                existing = target.clips.get(clip_type)
                if request.only_not_ready and existing is not None and existing.status == "ready":
                    continue
                try:
                    self._cut_one(target, clip_type, existing, request, src, duration_ms, workdir)
                except (ToolError, ValueError) as exc:
                    self.stats.error(f"track {target.id} {clip_type}: {exc}")
        except (ToolError, ValueError) as exc:
            self.stats.error(f"track {target.id}: {exc}")
        finally:
            src.unlink(missing_ok=True)

    def _start_ms(self, clip_type: str, existing: ExistingClip | None, request: CutRequest, duration_ms: int, src: Path) -> int:
        latest = duration_ms - CLIP_MS  # the last start that still leaves a whole clip
        if request.start_ms is not None:
            start, why = request.start_ms, "requested start"
        elif existing is not None:
            start, why = existing.start_ms, "registered start"  # an admin's choice, or the one used last time
        else:
            start = (
                self.tools.detect_intro_start_ms(src) if clip_type == "intro" else int(duration_ms * MIDDLE_FRACTION)
            )
            return max(0, min(start, latest))  # a default is nudged to fit; a chosen start is never moved
        if not 0 <= start <= latest:
            raise ValueError(f"{why} {start} ms leaves less than {CLIP_MS} ms of a {duration_ms} ms source")
        return start

    def _cut_one(
        self, target: Target, clip_type: str, existing: ExistingClip | None, request: CutRequest,
        src: Path, duration_ms: int, workdir: Path,
    ) -> None:
        start_ms = self._start_ms(clip_type, existing, request, duration_ms, src)
        out = workdir / f"{target.id}-{clip_type}.mp3"
        self.tools.cut(src, start_ms, out)
        measured_ms = self.tools.probe_duration_ms(out)
        if abs(measured_ms - CLIP_MS) > TOLERANCE_MS:  # never register a clip of the wrong length
            raise ToolError(f"the cut clip measures {measured_ms} ms, not {CLIP_MS} ms +/- {TOLERANCE_MS} ms")
        data = out.read_bytes()
        out.unlink(missing_ok=True)
        sha = hashlib.sha256(data).hexdigest()

        unchanged = (
            existing is not None and existing.status == "ready" and existing.r2_key is not None
            and existing.start_ms == start_ms and existing.length_ms == CLIP_MS
            and existing.sha256 == sha and existing.bytes == len(data)
        )
        if unchanged:
            self.stats.unchanged += 1
            return

        version = existing.version + 1 if existing is not None else 1  # what the API will assign
        key = clip_key(target.id, clip_type, version)
        self.clip_store.upload(key, data)
        self._clips.append(
            {"trackId": target.id, "type": clip_type, "startMs": start_ms, "lengthMs": CLIP_MS,
             "r2Key": key, "sha256": sha, "bytes": len(data)}
        )
        if existing is None:
            self.stats.created += 1
        else:
            self.stats.updated += 1

    # --------------------------------------------------------------- flags

    def _flag(self, track_id: int, reason: str, **details: object) -> None:
        self._flags.append({"trackId": track_id, "reason": reason, "details": details})
        self.stats.flagged += 1

    # ------------------------------------------------------------ register

    def _register(self) -> None:
        if not self._clips and not self._flags and not self._durations:
            return
        response = self.api.post_clips(self.job_id, self._clips, self._flags, self._durations)
        assigned = {(r["trackId"], r["type"]): r for r in response["results"]}
        for clip in self._clips:
            got = assigned.get((clip["trackId"], clip["type"]))
            expected = key_version(clip["r2Key"])
            if got is None or got["version"] != expected:
                self.stats.error(
                    f"track {clip['trackId']} {clip['type']}: registered as version "
                    f"{got['version'] if got else '?'} but uploaded as {clip['r2Key']}"
                )
        log.info(
            "registered %d clips, %d flags, %d durations: %s",
            len(self._clips), len(self._flags), len(self._durations), response["counts"],
        )
        self._clips, self._flags, self._durations = [], [], []
