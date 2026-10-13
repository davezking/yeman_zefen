"""Settings for a real (non dry-run) run, read from the environment."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

REQUIRED_VARS = (
    "API_BASE",
    "CF_ACCESS_CLIENT_ID",
    "CF_ACCESS_CLIENT_SECRET",
    "R2_ENDPOINT",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "JOB_ID",
)


class ConfigError(Exception):
    """A required setting is missing or malformed."""


@dataclass(frozen=True)
class Config:
    api_base: str
    cf_access_client_id: str
    cf_access_client_secret: str
    r2_endpoint: str
    r2_access_key_id: str
    r2_secret_access_key: str
    job_id: int
    r2_bucket: str = "yz-source"
    gh_run_url: str | None = None

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Config:
        env = os.environ if env is None else env
        missing = [name for name in REQUIRED_VARS if not env.get(name, "").strip()]
        if missing:
            raise ConfigError("missing environment variables: " + ", ".join(missing))
        try:
            job_id = int(env["JOB_ID"])
        except ValueError:
            job_id = 0
        if job_id <= 0:
            raise ConfigError(f"JOB_ID must be a positive integer, got {env['JOB_ID']!r}")

        # Set by GitHub Actions; lets the job row link back to the run.
        run_url = None
        if all(env.get(k) for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID")):
            run_url = f"{env['GITHUB_SERVER_URL']}/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}"

        return cls(
            api_base=env["API_BASE"].strip().rstrip("/"),
            cf_access_client_id=env["CF_ACCESS_CLIENT_ID"].strip(),
            cf_access_client_secret=env["CF_ACCESS_CLIENT_SECRET"].strip(),
            r2_endpoint=env["R2_ENDPOINT"].strip(),
            r2_access_key_id=env["R2_ACCESS_KEY_ID"].strip(),
            r2_secret_access_key=env["R2_SECRET_ACCESS_KEY"].strip(),
            job_id=job_id,
            r2_bucket=env.get("R2_BUCKET", "").strip() or "yz-source",
            gh_run_url=run_url,
        )
