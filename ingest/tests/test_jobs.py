"""python -m yz.jobs: make a job for a scheduled run, mark one failed when its run died silently."""

import pytest

import yz.jobs as jobs
from fakes import FakeApi
from yz.api_client import ApiClient, ApiError

ENV = {"API_BASE": "https://api.test/", "CF_ACCESS_CLIENT_ID": "i", "CF_ACCESS_CLIENT_SECRET": "s"}
RUN_ENV = {"GITHUB_SERVER_URL": "https://github.com", "GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "99"}


def run(argv, env=None, api=None):
    api = api or FakeApi()
    code = jobs.main(argv, env={**ENV, **(env or {})}, client_factory=lambda e: api)
    return code, api


# ---------------------------------------------------------------- titles


@pytest.mark.parametrize(
    "title,expected",
    [
        ("Scrape job 12", 12),
        ("Cut job 7", 7),
        ("Cut job 7  ", 7),
        ("Scrape (no job yet)", None),
        ("Cut job abc", None),
        ("Cut job 5 and then some", None),  # the id must end the title
        ("job 5", 5),
        ("", None),
        ("CI", None),
    ],
)
def test_job_id_from_title(title, expected):
    assert jobs.job_id_from_title(title) == expected


# ---------------------------------------------------------------- create


def test_create_prints_the_id_and_hands_it_to_the_workflow(tmp_path, capsys):
    out = tmp_path / "github_output"
    code, api = run(["create", "--kind", "scrape", "--since", "2026-09-13"], {"GITHUB_OUTPUT": str(out)})
    assert code == 0
    assert api.created_jobs == [("scrape", {"since": "2026-09-13"})]
    assert capsys.readouterr().out.strip() == "101"
    assert out.read_text() == "job_id=101\n"


def test_create_without_params_or_github_output(capsys):
    code, api = run(["create", "--kind", "scrape"])
    assert code == 0 and api.created_jobs == [("scrape", {})] and capsys.readouterr().out.strip() == "101"


def test_create_records_a_limit():
    assert run(["create", "--kind", "scrape", "--limit", "5"])[1].created_jobs == [("scrape", {"limit": 5})]


@pytest.mark.parametrize("argv", [["create"], ["create", "--kind", "cut"], ["create", "--kind", "scrape", "--limit", "0"], ["nonsense"], []])
def test_create_argument_errors(argv):
    with pytest.raises(SystemExit) as e:
        jobs.parse_args(argv)
    assert e.value.code == 2


def test_create_without_credentials_exits_2(capsys):
    code = jobs.main(["create", "--kind", "scrape"], env={}, client_factory=jobs._client)
    assert code == 2 and "API_BASE" in capsys.readouterr().err


def test_the_real_client_is_built_from_the_environment():
    client = jobs._client(ENV)
    assert isinstance(client, ApiClient) and client.base_url == "https://api.test"
    assert client.session.headers["CF-Access-Client-Id"] == "i"
    assert "Authorization" not in client.session.headers


def test_the_client_uses_the_ingest_token_where_there_is_no_access_service_token():
    client = jobs._client({"API_BASE": "https://api.test", "INGEST_TOKEN": "tok"})
    assert client.session.headers["Authorization"] == "Bearer tok"
    assert "CF-Access-Client-Id" not in client.session.headers


def test_the_client_needs_one_kind_of_credentials(capsys):
    code = jobs.main(["create", "--kind", "scrape"], env={"API_BASE": "https://api.test"}, client_factory=jobs._client)
    assert code == 2 and "INGEST_TOKEN" in capsys.readouterr().err


# ------------------------------------------------------------------ fail


def test_fail_marks_the_job_named_by_the_environment():
    code, api = run(["fail", "--message", "the run was cancelled"], {"JOB_ID": "12", **RUN_ENV})
    assert code == 0
    assert api.status_calls == [
        {"job_id": 12, "status": "failed", "summary": {"error": "the run was cancelled"}, "gh_run_url": "https://github.com/o/r/actions/runs/99"}
    ]


def test_fail_has_a_default_reason():
    _code, api = run(["fail"], {"JOB_ID": "3"})
    assert api.status_calls[0]["summary"] == {"error": jobs.DEFAULT_FAILURE} and api.status_calls[0]["gh_run_url"] is None


def test_fail_can_name_the_job_and_the_run_directly():
    _code, api = run(["fail", "--job-id", "8", "--run-url", "https://github.com/o/r/actions/runs/5"], {"JOB_ID": "12", **RUN_ENV})
    assert api.status_calls[0]["job_id"] == 8 and api.status_calls[0]["gh_run_url"].endswith("/runs/5")  # not the watcher's own run


def test_fail_finds_the_job_in_a_run_title():
    _code, api = run(["fail", "--from-run-title", "Cut job 41", "--run-url", "https://github.com/o/r/actions/runs/7"])
    assert api.status_calls[0]["job_id"] == 41


def test_fail_ignores_a_run_that_has_no_job():
    code, api = run(["fail", "--from-run-title", "Scrape (no job yet)"])
    assert code == 0 and api.status_calls == []


def test_fail_leaves_a_finished_job_alone():
    api = FakeApi()
    api.set_job_status = lambda *a, **k: (_ for _ in ()).throw(ApiError(409, "job_finished", "Job 12 already succeeded"))
    code, _ = run(["fail"], {"JOB_ID": "12"}, api)
    assert code == 0


def test_fail_tolerates_a_job_that_does_not_exist():
    api = FakeApi()
    api.set_job_status = lambda *a, **k: (_ for _ in ()).throw(ApiError(404, "job_not_found", "no such job"))
    assert run(["fail"], {"JOB_ID": "12"}, api)[0] == 0


def test_fail_does_not_hide_a_real_error():
    api = FakeApi()
    api.set_job_status = lambda *a, **k: (_ for _ in ()).throw(ApiError(500, "internal", "boom"))
    assert run(["fail"], {"JOB_ID": "12"}, api)[0] == 1


@pytest.mark.parametrize("env", [{}, {"JOB_ID": ""}, {"JOB_ID": "abc"}])
def test_fail_needs_a_usable_job_id(env, capsys):
    code, api = run(["fail"], env)
    assert code == 2 and api.status_calls == []


def test_the_two_ways_to_name_a_job_are_exclusive():
    with pytest.raises(SystemExit):
        jobs.parse_args(["fail", "--job-id", "1", "--from-run-title", "Cut job 2"])
