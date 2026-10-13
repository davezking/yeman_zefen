"""python -m yz.scrape: argument handling and wiring."""

import json

import pytest

import yz.scrape as cli
from fakes import FakeApi, FakeS3, FakeSource, url
from yz.config import REQUIRED_VARS
from yz.storage import SourceStore


def test_dry_run_writes_jsonl_without_any_configuration(tmp_path, monkeypatch):
    for name in REQUIRED_VARS:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setattr(cli, "EthiozeimaSource", lambda **kw: FakeSource(5))
    out = tmp_path / "out.jsonl"
    code = cli.main(["--dry-run", "--limit", "3", "--out", str(out), "--checkpoint", str(tmp_path / "c.json")])
    assert code == 0
    assert [json.loads(l)["sourceUrl"] for l in out.read_text(encoding="utf-8").splitlines()] == [url(1), url(2), url(3)]


def test_real_run_without_configuration_exits_2_naming_the_variables(monkeypatch, capsys):
    for name in REQUIRED_VARS:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setattr(cli, "EthiozeimaSource", lambda **kw: FakeSource(1))
    assert cli.main([]) == 2
    assert "JOB_ID" in capsys.readouterr().err


def test_real_run_wires_the_job_id_and_checkpoint(tmp_path, monkeypatch):
    env = {
        "API_BASE": "https://api.test", "CF_ACCESS_CLIENT_ID": "i", "CF_ACCESS_CLIENT_SECRET": "s",
        "R2_ENDPOINT": "https://acct.r2.cloudflarestorage.com", "R2_ACCESS_KEY_ID": "k",
        "R2_SECRET_ACCESS_KEY": "v", "JOB_ID": "42",
    }
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    api = FakeApi()
    monkeypatch.setattr(cli, "EthiozeimaSource", lambda **kw: FakeSource(2))
    monkeypatch.setattr(cli, "ApiClient", lambda *a, **kw: api)
    monkeypatch.setattr(cli.SourceStore, "from_config", classmethod(lambda cls, cfg: SourceStore(FakeS3(), cfg.r2_bucket)))
    assert cli.main(["--checkpoint", str(tmp_path / "c.json")]) == 0
    assert [s for s, _ in api.statuses] == ["running", "succeeded"] and len(api.posts[0]) == 2


def test_run_failure_exits_1(tmp_path, monkeypatch):
    monkeypatch.setattr(cli, "EthiozeimaSource", lambda **kw: FakeSource(posts={url(1): None}))
    assert cli.main(["--dry-run", "--out", str(tmp_path / "o.jsonl")]) == 1


@pytest.mark.parametrize("argv", [["--limit", "0"], ["--since", "yesterday"], ["--since", "2024-13-01"]])
def test_bad_arguments_are_rejected(argv):
    with pytest.raises(SystemExit) as e:
        cli.parse_args(argv)
    assert e.value.code == 2


def test_since_is_parsed_as_a_date():
    from datetime import date

    assert cli.parse_args(["--since", "2024-01-31"]).since == date(2024, 1, 31)
