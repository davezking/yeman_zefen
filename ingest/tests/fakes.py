"""In-memory stand-ins shared by the ingest tests."""

from yz.api_client import ApiError


class NotFound(Exception):
    def __init__(self, code="404"):
        self.response = {"Error": {"Code": code}, "ResponseMetadata": {"HTTPStatusCode": 404}}


class AccessDenied(Exception):
    def __init__(self):
        self.response = {"Error": {"Code": "AccessDenied"}, "ResponseMetadata": {"HTTPStatusCode": 403}}


class _Body:
    """The streaming body get_object returns."""

    def __init__(self, data):
        self._data = data

    def iter_chunks(self, size):
        for i in range(0, len(self._data), size):
            yield self._data[i : i + size]


class FakeS3:
    """The two S3 calls SourceStore makes."""

    def __init__(self):
        self.objects = {}
        self.puts = []
        self.put_calls = []
        self.fail_with = None

    def head_object(self, Bucket, Key):
        if self.fail_with:
            raise self.fail_with
        if Key not in self.objects:
            raise NotFound()
        return {"ContentLength": len(self.objects[Key])}

    def put_object(self, Bucket, Key, Body, ContentType, **extra):
        self.puts.append((Bucket, Key, ContentType))
        self.put_calls.append({"Bucket": Bucket, "Key": Key, "ContentType": ContentType, **extra})
        self.objects[Key] = Body

    def get_object(self, Bucket, Key):
        if self.fail_with:
            raise self.fail_with
        if Key not in self.objects:
            raise NotFound("NoSuchKey")
        return {"Body": _Body(self.objects[Key])}


class FakeApi:
    """Records what the pipeline sends; `fail_on_post=2` makes the 2nd POST fail."""

    def __init__(self, fail_on_post=None, fail_status_report=False, snapshot=None):
        self.posts = []
        self.statuses = []
        self.fail_on_post = fail_on_post
        self.fail_status_report = fail_status_report
        self.snapshot = snapshot or {"artists": [], "tracks": []}
        self.snapshot_calls = 0
        self.created_jobs = []
        self.status_calls = []

    def get_catalog_snapshot(self):
        self.snapshot_calls += 1
        return self.snapshot

    def create_job(self, kind, params=None):
        self.created_jobs.append((kind, params))
        return 100 + len(self.created_jobs)

    def post_tracks(self, job_id, tracks):
        if self.fail_on_post == len(self.posts) + 1:
            raise ApiError(500, "internal", "boom")
        self.posts.append(list(tracks))
        return {"counts": {"created": len(tracks), "updated": 0, "skipped": 0}, "results": []}

    def set_job_status(self, job_id, status, *, summary=None, gh_run_url=None):
        if self.fail_status_report and status == "failed":
            raise ApiError(500, "internal", "cannot report")
        self.statuses.append((status, summary))
        self.status_calls.append({"job_id": job_id, "status": status, "summary": summary, "gh_run_url": gh_run_url})


def url(i):
    return f"https://ethiozeima.com/2014/11/02/song-{i}/"


def parsed(i, **over):
    """What the legacy parse_post returns for a well-formed post."""
    post = {
        "artist_latin": "Tilahun Gessesse", "artist_amharic": "ጥላሁን ገሠሠ",
        "title_latin": f"Zefen {i}", "title_amharic": f"ዘፈን {i}",
        "album": "Greatest Hits", "year": "1975",
        "source_url": url(i), "mp3_url": f"https://ethiozeima.com/audio/song-{i}.mp3",
        "local_audio_path": "", "clip_start_time": "",
    }
    post.update(over)
    return post


class FakeSource:
    """Serves `n` posts (or a custom {url: parsed | None} dict) and counts what is asked of it."""

    def __init__(self, n=0, posts=None, audio=None):
        self.posts = posts if posts is not None else {url(i): parsed(i) for i in range(1, n + 1)}
        self.audio = audio if audio is not None else {p["mp3_url"]: f"mp3-bytes-{i}".encode() for i, p in
                                                     enumerate((p for p in self.posts.values() if p), 1)}
        self.parsed, self.sized, self.fetched = [], [], []

    def iter_urls(self):
        return iter(list(self.posts))

    def parse(self, u):
        self.parsed.append(u)
        return self.posts[u]

    def audio_size(self, mp3_url):
        self.sized.append(mp3_url)
        return len(self.audio[mp3_url]) if mp3_url in self.audio else None

    def fetch_audio(self, mp3_url):
        self.fetched.append(mp3_url)
        return self.audio.get(mp3_url)


class FakeClipApi(FakeApi):
    """The API's side of cutting. Serves clip targets and applies the registration rules the Worker does:
    a clip is only rewritten, and its version bumped, when it was not ready or something about it changed."""

    def __init__(self, tracks=None, **kw):
        super().__init__(**kw)
        # id -> {"status", "sourceAudioKey", "durationMs", "clips": {type: {startMs, lengthMs, r2Key, sha256, bytes, version, status}}}
        self.tracks = tracks if tracks is not None else {}
        self.registrations = []  # every post_clips call: (clips, flags)
        self.duration_posts = []  # the durations sent with each post_clips call
        self.open_flags = set()

    def add_track(self, track_id, source_key="source/x.mp3", status="needs_review", clips=None):
        self.tracks[track_id] = {"status": status, "sourceAudioKey": source_key, "durationMs": None, "clips": clips or {}}

    def _target(self, track_id):
        t = self.tracks[track_id]
        return {
            "id": track_id, "status": t["status"], "sourceAudioKey": t["sourceAudioKey"], "durationMs": t["durationMs"],
            "clips": [{"type": ty, **c} for ty, c in sorted(t["clips"].items())],
        }

    def get_clip_targets(self, *, track_ids=None, missing=False, after=0, limit=100):
        if track_ids is not None:
            return {"tracks": [self._target(i) for i in sorted(track_ids) if i in self.tracks], "next": None}
        ids = [
            i for i, t in sorted(self.tracks.items())
            if i > after and t["status"] in ("ingested", "needs_review", "approved") and t["sourceAudioKey"]
            and sum(1 for c in t["clips"].values() if c["status"] == "ready") < 2
        ][:limit]
        return {"tracks": [self._target(i) for i in ids], "next": ids[-1] if len(ids) == limit else None}

    def post_clips(self, job_id, clips, flags=None, durations=None):
        self.registrations.append((list(clips), list(flags or [])))
        self.duration_posts.append(list(durations or []))
        duration_results = []
        for d in durations or []:
            t = self.tracks[d["trackId"]]
            changed = t["durationMs"] != d["durationMs"]
            t["durationMs"] = d["durationMs"]
            duration_results.append({"trackId": d["trackId"], "result": "updated" if changed else "skipped"})
        counts, results, flag_results = {"created": 0, "updated": 0, "skipped": 0}, [], []
        for c in clips:
            clip_map = self.tracks[c["trackId"]]["clips"]
            prev = clip_map.get(c["type"])
            row = {k: c[k] for k in ("startMs", "lengthMs", "r2Key", "sha256", "bytes")}
            if prev is None:
                clip_map[c["type"]] = {**row, "version": 1, "status": "ready"}
                outcome = "created"
            elif prev["status"] == "ready" and all(prev[k] == row[k] for k in row):
                outcome = "skipped"
            else:
                clip_map[c["type"]] = {**row, "version": prev["version"] + 1, "status": "ready"}
                outcome = "updated"
            counts[outcome] += 1
            results.append({"trackId": c["trackId"], "type": c["type"], "version": clip_map[c["type"]]["version"], "result": outcome})
        for f in flags or []:
            key = (f["trackId"], f["reason"], repr(sorted((f.get("details") or {}).items())))
            flag_results.append({"trackId": f["trackId"], "reason": f["reason"], "result": "skipped" if key in self.open_flags else "created"})
            self.open_flags.add(key)
        return {"counts": counts, "results": results, "flags": flag_results, "durations": duration_results}
