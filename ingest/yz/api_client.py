"""Client for the Worker's /admin/ingest/* routes, authenticated with a Cloudflare Access service token."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable

import requests

log = logging.getLogger(__name__)

MAX_BATCH = 100  # the API rejects more than 100 records per request
RETRY_STATUSES = frozenset({408, 425, 429, 500, 502, 503, 504})
USER_AGENT = "YemanZefenIngest/1.0 (+https://github.com/davezking/yeman_zefen)"


class ApiError(Exception):
    """The API answered with an error (or something that is not the API at all)."""

    def __init__(self, status: int, code: str, message: str):
        super().__init__(f"{status} {code}: {message}")
        self.status = status
        self.code = code
        self.message = message


def _error_from(resp: requests.Response) -> ApiError:
    """Build an ApiError from `{ "error": { "code", "message" } }`, or from whatever came back."""
    try:
        err = resp.json()["error"]
        return ApiError(resp.status_code, str(err["code"]), str(err["message"]))
    except (ValueError, KeyError, TypeError):
        hint = ""
        if 300 <= resp.status_code < 400:
            hint = " (redirect: Cloudflare Access did not accept the service token)"
        return ApiError(resp.status_code, f"http_{resp.status_code}", f"unexpected response{hint}")


class ApiClient:
    def __init__(
        self,
        base_url: str,
        client_id: str,
        client_secret: str,
        *,
        session: requests.Session | None = None,
        retries: int = 5,
        backoff: float = 1.0,
        timeout: float = 60.0,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.base_url = base_url.rstrip("/")
        self.retries = retries
        self.backoff = backoff
        self.timeout = timeout
        self._sleep = sleep
        self.session = session if session is not None else requests.Session()
        self.session.headers.update(
            {
                "CF-Access-Client-Id": client_id,
                "CF-Access-Client-Secret": client_secret,
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
            }
        )

    # ------------------------------------------------------------- transport

    def _request(self, method: str, path: str, body: dict) -> dict:
        """Send JSON, retrying network errors, 408/425/429 and 5xx with exponential backoff.
        Every ingest write is idempotent, so a retry after a lost response is safe."""
        url = f"{self.base_url}{path}"
        last: Exception | None = None
        for attempt in range(self.retries + 1):
            retry_after = 0.0
            try:
                # No redirects: an invalid Access token is answered with a redirect to a login page.
                resp = self.session.request(method, url, json=body, timeout=self.timeout, allow_redirects=False)
            except requests.RequestException as exc:
                last = exc
            else:
                if resp.status_code < 300:
                    try:
                        return resp.json()
                    except ValueError:
                        raise ApiError(resp.status_code, "bad_response", "expected JSON from the API") from None
                last = _error_from(resp)
                if resp.status_code not in RETRY_STATUSES:
                    raise last
                try:
                    retry_after = min(float(resp.headers.get("Retry-After", 0)), 60.0)
                except (TypeError, ValueError):
                    retry_after = 0.0
            if attempt == self.retries:
                break
            wait = max(self.backoff * 2**attempt, retry_after)
            log.warning("%s %s failed (%s); retry %d/%d in %.1fs", method, path, last, attempt + 1, self.retries, wait)
            self._sleep(wait)
        assert last is not None
        raise last

    # ------------------------------------------------------------- endpoints

    def post_tracks(self, job_id: int, tracks: list[dict]) -> dict:
        """POST tracks in requests of at most 100. Returns `{ "counts": {...}, "results": [...] }`
        merged across requests. A request the Worker finds too large (413) is halved and retried."""
        merged: dict = {"counts": {"created": 0, "updated": 0, "skipped": 0}, "results": []}
        for start in range(0, len(tracks), MAX_BATCH):
            self._post_chunk(job_id, tracks[start : start + MAX_BATCH], merged)
        return merged

    def _post_chunk(self, job_id: int, chunk: list[dict], merged: dict) -> None:
        try:
            data = self._request("POST", "/admin/ingest/tracks", {"jobId": job_id, "tracks": chunk})
        except ApiError as exc:
            if exc.status == 413 and len(chunk) > 1:
                half = len(chunk) // 2
                self._post_chunk(job_id, chunk[:half], merged)
                self._post_chunk(job_id, chunk[half:], merged)
                return
            raise
        for key in merged["counts"]:
            merged["counts"][key] += data.get("counts", {}).get(key, 0)
        merged["results"].extend(data.get("results", []))

    def set_job_status(
        self, job_id: int, status: str, *, summary: dict | None = None, gh_run_url: str | None = None
    ) -> dict:
        body: dict = {"status": status}
        if summary is not None:
            body["summary"] = summary
        if gh_run_url:
            body["ghRunUrl"] = gh_run_url
        return self._request("POST", f"/admin/ingest/jobs/{job_id}/status", body)
