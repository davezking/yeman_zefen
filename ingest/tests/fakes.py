"""In-memory stand-ins shared by the ingest tests."""

from yz.api_client import ApiError


class NotFound(Exception):
    def __init__(self, code="404"):
        self.response = {"Error": {"Code": code}, "ResponseMetadata": {"HTTPStatusCode": 404}}


class AccessDenied(Exception):
    def __init__(self):
        self.response = {"Error": {"Code": "AccessDenied"}, "ResponseMetadata": {"HTTPStatusCode": 403}}


class FakeS3:
    """The two S3 calls SourceStore makes."""

    def __init__(self):
        self.objects = {}
        self.puts = []
        self.fail_with = None

    def head_object(self, Bucket, Key):
        if self.fail_with:
            raise self.fail_with
        if Key not in self.objects:
            raise NotFound()
        return {"ContentLength": len(self.objects[Key])}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.puts.append((Bucket, Key, ContentType))
        self.objects[Key] = Body


class FakeApi:
    """Records what the pipeline sends; `fail_on_post=2` makes the 2nd POST fail."""

    def __init__(self, fail_on_post=None, fail_status_report=False):
        self.posts = []
        self.statuses = []
        self.fail_on_post = fail_on_post
        self.fail_status_report = fail_status_report

    def post_tracks(self, job_id, tracks):
        if self.fail_on_post == len(self.posts) + 1:
            raise ApiError(500, "internal", "boom")
        self.posts.append(list(tracks))
        return {"counts": {"created": len(tracks), "updated": 0, "skipped": 0}, "results": []}

    def set_job_status(self, job_id, status, *, summary=None, gh_run_url=None):
        if self.fail_status_report and status == "failed":
            raise ApiError(500, "internal", "cannot report")
        self.statuses.append((status, summary))


def url(i):
    return f"https://ethiozeima.com/2014/11/02/song-{i}/"


def parsed(i, **over):
    """What the legacy parse_post returns for a well-formed post."""
    post = {
        "artist_latin": "Tilahun Gessesse", "artist_amharic": "ጥላሁን ገሠሠ",
        "title_latin": f"Song {i}", "title_amharic": f"ዘፈን {i}",
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
