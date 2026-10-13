"""python -m yz.cut: argument rules and wiring."""

import pytest

import yz.cut as cli
from fakes import FakeClipApi, FakeS3
from yz.clips import CutRequest, Selection, ToolError
from yz.config import REQUIRED_VARS

ENV = {
    "API_BASE": "https://api.test", "CF_ACCESS_CLIENT_ID": "i", "CF_ACCESS_CLIENT_SECRET": "s",
    "R2_ENDPOINT": "https://acct.r2.cloudflarestorage.com", "R2_ACCESS_KEY_ID": "k",
    "R2_SECRET_ACCESS_KEY": "v", "JOB_ID": "42",
}


def parse(*argv):
    return cli.parse_args(list(argv))


def rejected(*argv):
    with pytest.raises(SystemExit) as e:
        parse(*argv)
    assert e.value.code == 2


def test_the_three_ways_to_pick_tracks():
    assert parse("--track-ids", "1,2,3").track_ids == (1, 2, 3)
    assert parse("--all-missing").all_missing is True
    a = parse("--track-id", "7", "--type", "intro", "--start-ms", "41200")
    assert (a.track_id, a.type, a.start_ms) == (7, "intro", 41200)


@pytest.mark.parametrize(
    "argv",
    [
        [],  # one way of picking tracks is required
        ["--track-ids", "1", "--all-missing"],
        ["--track-ids", "1", "--track-id", "2"],
        ["--track-ids", "1,x"],
        ["--track-ids", "0"],
        ["--track-id", "0"],
        ["--all-missing", "--type", "other"],
        ["--all-missing", "--start-ms", "5000", "--type", "intro"],  # a start needs one track
        ["--track-ids", "1,2", "--start-ms", "5000", "--type", "intro"],
        ["--track-id", "1", "--start-ms", "5000"],  # a start needs a type
        ["--track-id", "1", "--type", "intro", "--start-ms", "-1"],
        ["--track-ids", "1", "--limit", "5"],  # limit is for --all-missing
        ["--all-missing", "--limit", "0"],
    ],
)
def test_bad_combinations_are_rejected(argv):
    rejected(*argv)


def test_a_start_may_name_a_single_track_in_a_list():
    assert parse("--track-ids", "5", "--type", "middle", "--start-ms", "30000").start_ms == 30000


@pytest.fixture
def wired(monkeypatch):
    for k, v in ENV.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(cli, "require_ffmpeg", lambda: None)
    api = FakeClipApi()
    seen = {}

    class Recorder:
        def __init__(self, *a, **kw):
            seen["init"] = kw

        def run(self, selection, request):
            seen["selection"], seen["request"] = selection, request
            from yz.clips import CutStats

            return CutStats()

    monkeypatch.setattr(cli, "ApiClient", lambda *a, **kw: api)
    monkeypatch.setattr(cli.SourceStore, "from_config", classmethod(lambda cls, cfg: object()))
    monkeypatch.setattr(cli.ClipStore, "from_config", classmethod(lambda cls, cfg: object()))
    monkeypatch.setattr(cli, "Cutter", lambda api, s, c, job_id, **kw: (seen.__setitem__("job_id", job_id), Recorder())[1])
    return seen


def test_track_ids_cut_both_clips(wired):
    assert cli.main(["--track-ids", "3,1"]) == 0
    assert wired["job_id"] == 42
    assert wired["selection"] == Selection(track_ids=(3, 1))
    assert wired["request"] == CutRequest(types=("intro", "middle"), start_ms=None, only_not_ready=False)


def test_all_missing_only_touches_clips_that_are_not_ready(wired):
    assert cli.main(["--all-missing", "--limit", "25"]) == 0
    assert wired["selection"] == Selection(missing=True, limit=25)
    assert wired["request"].only_not_ready is True


def test_a_recut_names_one_clip_and_its_start(wired):
    assert cli.main(["--track-id", "7", "--type", "intro", "--start-ms", "41200"]) == 0
    assert wired["selection"] == Selection(track_ids=(7,))
    assert wired["request"] == CutRequest(types=("intro",), start_ms=41200, only_not_ready=False)


def test_missing_configuration_exits_2_and_names_the_variables(monkeypatch, capsys):
    for name in REQUIRED_VARS:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setattr(cli, "require_ffmpeg", lambda: None)
    assert cli.main(["--all-missing"]) == 2
    assert "JOB_ID" in capsys.readouterr().err


def test_missing_ffmpeg_exits_2(monkeypatch, capsys):
    for k, v in ENV.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(cli, "require_ffmpeg", lambda: (_ for _ in ()).throw(ToolError("ffmpeg and ffprobe not found on PATH")))
    assert cli.main(["--all-missing"]) == 2
    assert "ffmpeg" in capsys.readouterr().err


def test_a_failed_run_exits_1(monkeypatch):
    for k, v in ENV.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(cli, "require_ffmpeg", lambda: None)
    monkeypatch.setattr(cli, "ApiClient", lambda *a, **kw: FakeClipApi())
    monkeypatch.setattr(cli.SourceStore, "from_config", classmethod(lambda cls, cfg: object()))
    monkeypatch.setattr(cli.ClipStore, "from_config", classmethod(lambda cls, cfg: object()))

    class Boom:
        def run(self, *a, **k):
            raise RuntimeError("boom")

    monkeypatch.setattr(cli, "Cutter", lambda *a, **kw: Boom())
    assert cli.main(["--all-missing"]) == 1
