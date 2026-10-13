"""The ingest workflows: their shape, the safety rules they must keep, and their shell scripts run for real.

Structure is checked on the parsed YAML; each `run:` script is then executed with a stand-in `python` that
records its arguments, so what the workflow would pass to the scraper and cutter is what is asserted.
"""

import os
import re
import stat
import subprocess
from pathlib import Path

import pytest

try:
    import yaml
except ImportError:  # a machine without PyYAML skips these; CI installs it, so there a missing one is a failure
    if os.environ.get("CI"):
        raise
    pytest.skip("PyYAML is not installed", allow_module_level=True)

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
OPS = (ROOT / "docs" / "ops.md").read_text(encoding="utf-8")
NAMES = ["ingest-scrape", "ingest-cut", "ingest-watch"]


def load(name):
    doc = yaml.safe_load((WORKFLOWS / f"{name}.yml").read_text(encoding="utf-8"))
    doc["on"] = doc.pop(True, doc.get("on"))  # YAML reads a bare `on` as the boolean True
    return doc


def steps(name):
    return [s for job in load(name)["jobs"].values() for s in job["steps"]]


def step(name, title):
    return next(s for s in steps(name) if s.get("name") == title)


# ------------------------------------------------------------------ shape


def test_the_workflows_are_named_for_their_files():
    for name in NAMES:
        assert load(name)["name"] == name


def test_scrape_runs_on_dispatch_and_weekly_with_the_inputs_the_worker_sends():
    on = load("ingest-scrape")["on"]
    assert set(on["workflow_dispatch"]["inputs"]) == {"job_id", "limit", "since"}
    assert not any(i.get("required") for i in on["workflow_dispatch"]["inputs"].values())  # a hand-started run makes its own job
    assert len(on["schedule"]) == 1 and re.fullmatch(r"\d+ \d+ \* \* \d", on["schedule"][0]["cron"])


def test_cut_runs_on_dispatch_only_with_job_id_and_args():
    on = load("ingest-cut")["on"]
    assert set(on) == {"workflow_dispatch"}
    assert set(on["workflow_dispatch"]["inputs"]) == {"job_id", "args"}
    assert all(i["required"] for i in on["workflow_dispatch"]["inputs"].values())


def test_scrape_and_cut_share_one_concurrency_group_and_never_cancel_a_run_in_progress():
    for name in ("ingest-scrape", "ingest-cut"):
        assert load(name)["concurrency"] == {"group": "ingest", "cancel-in-progress": False}


def test_the_watcher_is_not_queued_behind_the_runs_it_watches():
    wf = load("ingest-watch")
    assert wf["concurrency"]["group"] != "ingest"
    assert wf["on"]["workflow_run"] == {"workflows": ["ingest-scrape", "ingest-cut"], "types": ["completed"]}
    assert "success" in wf["jobs"]["mark-failed"]["if"] and "!=" in wf["jobs"]["mark-failed"]["if"]  # only unsuccessful runs


@pytest.mark.parametrize("name", NAMES)
def test_least_privilege_and_a_timeout(name):
    wf = load(name)
    assert wf["permissions"] == {"contents": "read"}
    assert all(job.get("timeout-minutes") for job in wf["jobs"].values())  # a hung run must end


def test_python_uses_a_pip_cache():
    for name in NAMES:
        setup = next(s for s in steps(name) if str(s.get("uses", "")).startswith("actions/setup-python"))
        assert setup["with"]["cache"] == "pip" and setup["with"]["cache-dependency-path"] == "ingest/requirements.txt"


def test_only_the_cutter_installs_ffmpeg():
    assert any("ffmpeg" in s.get("run", "") for s in steps("ingest-cut"))
    assert not any("ffmpeg" in s.get("run", "") for s in steps("ingest-scrape"))  # the scraper never calls it


@pytest.mark.parametrize("name", ["ingest-scrape", "ingest-cut"])
def test_a_last_step_marks_the_job_failed_when_the_run_fails_or_is_cancelled(name):
    job = next(iter(load(name)["jobs"].values()))
    last = job["steps"][-1]
    assert last["name"] == "Mark the job failed if the run did not report"
    assert "failure()" in last["if"] and "cancelled()" in last["if"]
    assert "python -m yz.jobs fail" in last["run"]
    effective_env = {**job.get("env", {}), **last.get("env", {})}  # the job's variables reach every step
    assert "JOB_ID" in effective_env and "API_BASE" in effective_env and "CF_ACCESS_CLIENT_SECRET" in effective_env


def test_run_names_carry_the_job_id_so_the_watcher_can_find_it():
    assert "Scrape job {0}" in load("ingest-scrape")["run-name"] and "inputs.job_id" in load("ingest-scrape")["run-name"]
    assert load("ingest-cut")["run-name"] == "Cut job ${{ inputs.job_id }}"


# ------------------------------------------------------------ safety rules


@pytest.mark.parametrize("name", NAMES)
def test_no_expression_is_pasted_into_a_script(name):
    """`${{ }}` inside `run:` is substituted before the shell parses it, so an input could inject commands.
    Values must reach scripts through `env:`; the only expression allowed in a script is the job's own status."""
    for s in steps(name):
        for expr in re.findall(r"\$\{\{(.*?)\}\}", s.get("run", "")):
            pytest.fail(f"{name}: step {s.get('name', s.get('run', '')[:40])!r} interpolates {expr.strip()!r} into its script")


def test_secrets_reach_only_the_steps_that_need_them():
    scrape = load("ingest-scrape")["jobs"]["scrape"]
    assert "R2_SECRET_ACCESS_KEY" not in scrape["env"]  # the R2 keys are on the scraping step alone
    assert "R2_SECRET_ACCESS_KEY" in step("ingest-scrape", "Scrape")["env"]
    assert not any("R2_" in k for k in load("ingest-watch")["jobs"]["mark-failed"]["env"])  # the watcher only talks to the API


def test_every_secret_the_workflows_use_is_documented():
    used = set()
    for name in NAMES:
        used |= set(re.findall(r"secrets\.([A-Z0-9_]+)", (WORKFLOWS / f"{name}.yml").read_text(encoding="utf-8")))
    assert used >= {"API_BASE", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET", "R2_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"}
    assert [s for s in sorted(used) if f"`{s}`" not in OPS] == []


def test_the_worker_secret_and_variables_are_documented():
    for name in ("GH_DISPATCH_TOKEN", "GH_REPO", "GH_REF"):
        assert f"`{name}`" in OPS


# --------------------------------------------------- the scripts, executed


@pytest.fixture
def sandbox(tmp_path):
    """A directory with a stand-in `python` that records its arguments (and a fixed `date`)."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log = tmp_path / "argv.log"
    shim = bin_dir / "python"
    shim.write_text(f'#!/bin/bash\nprintf \'%s\\n\' "$@" > "{log}"\necho "python called" >> "{tmp_path}/calls"\n')
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    work = tmp_path / "work"
    work.mkdir()

    def run(script, env=None):
        full = {"PATH": f"{bin_dir}:/usr/bin:/bin", "HOME": str(tmp_path), "GITHUB_OUTPUT": str(tmp_path / "out"), **(env or {})}
        done = subprocess.run(["bash", "-e", "-c", script], cwd=work, env=full, capture_output=True, text=True)
        argv = log.read_text().splitlines() if log.exists() else None
        out = (tmp_path / "out").read_text() if (tmp_path / "out").exists() else ""
        return done, argv, out

    run.work = work
    return run


def test_scrape_passes_the_limit_and_since_it_was_given(sandbox):
    script = step("ingest-scrape", "Scrape")["run"]
    done, argv, _ = sandbox(script, {"LIMIT": "3", "SINCE": "2026-01-31"})
    assert done.returncode == 0 and argv == ["-m", "yz.scrape", "--limit", "3", "--since", "2026-01-31"]


def test_scrape_with_no_limit_or_since_passes_neither(sandbox):
    done, argv, _ = sandbox(step("ingest-scrape", "Scrape")["run"], {"LIMIT": "", "SINCE": ""})
    assert done.returncode == 0 and argv == ["-m", "yz.scrape"]


def test_scrape_treats_its_inputs_as_data(sandbox):
    (sandbox.work / "victim").write_text("x")
    hostile = '5; touch pwned; echo $(touch pwned2) *'
    done, argv, _ = sandbox(step("ingest-scrape", "Scrape")["run"], {"LIMIT": hostile, "SINCE": "2026-01-01 --evil"})
    assert argv == ["-m", "yz.scrape", "--limit", hostile, "--since", "2026-01-01 --evil"]  # one argument each, untouched
    assert not (sandbox.work / "pwned").exists() and not (sandbox.work / "pwned2").exists()


def test_cut_splits_its_arguments_on_spaces(sandbox):
    script = step("ingest-cut", "Cut")["run"]
    done, argv, _ = sandbox(script, {"CUT_ARGS": "--track-id 7 --type intro --start-ms 41200"})
    assert done.returncode == 0 and argv == ["-m", "yz.cut", "--track-id", "7", "--type", "intro", "--start-ms", "41200"]
    done, argv, _ = sandbox(script, {"CUT_ARGS": "--all-missing --limit 25"})
    assert argv == ["-m", "yz.cut", "--all-missing", "--limit", "25"]


def test_cut_never_globs_or_evaluates_its_arguments(sandbox):
    (sandbox.work / "a.txt").write_text("")
    (sandbox.work / "b.txt").write_text("")
    script = step("ingest-cut", "Cut")["run"]
    done, argv, _ = sandbox(script, {"CUT_ARGS": "--all-missing * $(touch pwned) `touch pwned2` ; touch pwned3"})
    assert argv == ["-m", "yz.cut", "--all-missing", "*", "$(touch", "pwned)", "`touch", "pwned2`", ";", "touch", "pwned3"]
    assert not any((sandbox.work / n).exists() for n in ("pwned", "pwned2", "pwned3"))


def test_the_job_step_defaults_to_the_last_thirty_days_and_passes_the_date_on(sandbox):
    script = step("ingest-scrape", "Create the job")["run"]
    done, argv, out = sandbox(script, {"SINCE_INPUT": ""})
    since = re.search(r"since=(\d{4}-\d{2}-\d{2})", out).group(1)
    assert done.returncode == 0 and argv == ["-m", "yz.jobs", "create", "--kind", "scrape", "--since", since]
    from datetime import date, timedelta

    assert abs((date.today() - date.fromisoformat(since)).days - 30) <= 1


def test_the_job_step_honours_a_since_given_by_hand(sandbox):
    done, argv, out = sandbox(step("ingest-scrape", "Create the job")["run"], {"SINCE_INPUT": "2026-02-01"})
    assert argv[-2:] == ["--since", "2026-02-01"] and "since=2026-02-01" in out


def test_the_fail_steps_report_the_run_status(sandbox):
    for name in ("ingest-scrape", "ingest-cut"):
        done, argv, _ = sandbox(steps(name)[-1]["run"], {"RUN_STATUS": "cancelled"})
        assert done.returncode == 0 and argv[:3] == ["-m", "yz.jobs", "fail"] and "ended as cancelled" in argv[-1]


def test_the_watcher_passes_the_title_and_the_run_it_is_watching(sandbox):
    script = step("ingest-watch", "Mark the job failed")["run"]
    env = {"RUN_TITLE": "Cut job 12; touch pwned", "RUN_URL": "https://github.com/o/r/actions/runs/5", "CONCLUSION": "cancelled"}
    done, argv, _ = sandbox(script, env)
    assert argv[:3] == ["-m", "yz.jobs", "fail"] and argv[argv.index("--from-run-title") + 1] == "Cut job 12; touch pwned"
    assert argv[argv.index("--run-url") + 1] == env["RUN_URL"] and "ended as cancelled" in argv[-1]
    assert not (sandbox.work / "pwned").exists()
