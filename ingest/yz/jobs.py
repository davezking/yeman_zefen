"""Job bookkeeping for the GitHub workflows (the scrape and cut CLIs report their own progress).

    python -m yz.jobs create --kind scrape [--since 2026-09-13] [--limit N]
        Make a job row for a run that started on a schedule, so it has an id. Prints the id and, inside
        Actions, writes `job_id=<id>` to $GITHUB_OUTPUT.

    python -m yz.jobs fail [--message TEXT] [--job-id N | --from-run-title TITLE] [--run-url URL]
        Mark a job failed, unless it already finished. A run can die before the scraper or cutter ever
        reports (a bad argument, pip failing, the runner being cancelled), and then the job would sit
        `queued` or `running` for good. The workflows call this from a step that runs on failure.

Both read API_BASE, and INGEST_TOKEN or CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET; `fail` also reads JOB_ID unless it is
told which job. Run it from the `ingest/` directory.
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
from collections.abc import Callable, Mapping

from .api_client import ApiClient, ApiError
from .config import ConfigError, api_credentials, github_run_url, require

log = logging.getLogger("yz.jobs")

DEFAULT_FAILURE = "the workflow run ended before the job reported a result"
_TITLE_JOB = re.compile(r"\bjob (\d+)\s*$")


def job_id_from_title(title: str) -> int | None:
    """The workflows name their runs "... job <id>", so a run that never reached a step can still be traced."""
    m = _TITLE_JOB.search(title.strip())
    return int(m.group(1)) if m else None


def _client(env: Mapping[str, str]) -> ApiClient:
    base = require(env, "API_BASE")["API_BASE"]
    client_id, client_secret, token = api_credentials(env)
    return ApiClient(base.rstrip("/"), client_id, client_secret, token=token)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="python -m yz.jobs", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create", help="make a job row for a scheduled run")
    create.add_argument("--kind", choices=["scrape"], required=True)
    create.add_argument("--since", metavar="DATE", help="recorded as the job's params")
    create.add_argument("--limit", type=int, metavar="N", help="recorded as the job's params")

    fail = sub.add_parser("fail", help="mark a job failed unless it already finished")
    fail.add_argument("--message", default=DEFAULT_FAILURE, help="why, recorded in the job's summary")
    which = fail.add_mutually_exclusive_group()
    which.add_argument("--job-id", type=int, metavar="N", help="the job (default: $JOB_ID)")
    which.add_argument("--from-run-title", metavar="TITLE", help='take the job id from a run title ending "job N"')
    fail.add_argument("--run-url", help="link the job to this run (default: the run we are in)")

    args = ap.parse_args(argv)
    if args.command == "create" and args.limit is not None and args.limit < 1:
        ap.error("--limit must be at least 1")
    return args


def _create(args: argparse.Namespace, env: Mapping[str, str], client: ApiClient) -> int:
    params: dict = {}
    if args.since:
        params["since"] = args.since
    if args.limit is not None:
        params["limit"] = args.limit
    job_id = client.create_job(args.kind, params)
    print(job_id)
    if env.get("GITHUB_OUTPUT"):
        with open(env["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
            f.write(f"job_id={job_id}\n")
    return 0


def _fail(args: argparse.Namespace, env: Mapping[str, str], client: ApiClient) -> int:
    if args.from_run_title is not None:
        job_id = job_id_from_title(args.from_run_title)
        if job_id is None:
            log.info("run %r is not named after a job; nothing to mark", args.from_run_title)
            return 0  # some other workflow, or one that has no job: not our business
    elif args.job_id is not None:
        job_id = args.job_id
    else:
        job_id = int(require(env, "JOB_ID")["JOB_ID"])
    try:
        client.set_job_status(job_id, "failed", summary={"error": args.message}, gh_run_url=args.run_url or github_run_url(env))
    except ApiError as exc:
        if exc.status == 409 and exc.code == "job_finished":
            log.info("job %d already finished; leaving its result as it is", job_id)
            return 0
        if exc.status == 404:
            log.warning("job %d does not exist; nothing to mark", job_id)
            return 0
        raise
    log.info("job %d marked failed: %s", job_id, args.message)
    return 0


def main(argv: list[str] | None = None, *, env: Mapping[str, str] | None = None, client_factory: Callable[[Mapping[str, str]], ApiClient] = _client) -> int:
    args = parse_args(argv)
    env = os.environ if env is None else env
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        client = client_factory(env)
        return _create(args, env, client) if args.command == "create" else _fail(args, env, client)
    except (ConfigError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except Exception:
        log.exception("%s failed", args.command)
        return 1


if __name__ == "__main__":
    sys.exit(main())
