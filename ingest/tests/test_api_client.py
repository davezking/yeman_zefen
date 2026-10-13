"""ApiClient: auth headers, retries with backoff, batching, 413 splitting, error mapping. No network."""

import pytest
import requests

from yz.api_client import MAX_BATCH, ApiClient, ApiError


class FakeResponse:
    def __init__(self, status=200, body=None, headers=None, text_body=False):
        self.status_code = status
        self._body = body
        self.headers = headers or {}
        self._text_body = text_body

    def json(self):
        if self._text_body or self._body is None:
            raise ValueError("not json")
        return self._body


class FakeSession:
    """Plays back a list of responses (or exceptions), recording each request."""

    def __init__(self, *responses):
        self.headers = {}
        self.responses = list(responses)
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append({"method": method, "url": url, **kwargs})
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def ok(created=0, updated=0, skipped=0, results=()):
    return FakeResponse(200, {"counts": {"created": created, "updated": updated, "skipped": skipped}, "results": list(results)})


def err(status, code="boom", message="nope", headers=None):
    return FakeResponse(status, {"error": {"code": code, "message": message}}, headers)


def client(session, **kw):
    sleeps = []
    c = ApiClient("https://api.test/", "id-123", "secret-456", session=session, sleep=sleeps.append, **kw)
    c.sleeps = sleeps
    return c


def records(n):
    return [{"sourceUrl": f"https://ethiozeima.com/2014/11/02/s-{i}/", "artistAm": "ጥላሁን"} for i in range(n)]


def test_sends_access_headers_and_json_body():
    s = FakeSession(ok(created=1))
    c = client(s)
    c.post_tracks(7, records(1))
    assert s.headers["CF-Access-Client-Id"] == "id-123"
    assert s.headers["CF-Access-Client-Secret"] == "secret-456"
    call = s.calls[0]
    assert (call["method"], call["url"]) == ("POST", "https://api.test/admin/ingest/tracks")
    assert call["json"]["jobId"] == 7 and len(call["json"]["tracks"]) == 1
    assert call["allow_redirects"] is False


def test_splits_into_batches_of_100_and_merges_counts():
    s = FakeSession(ok(created=100), ok(created=60, updated=40), ok(skipped=50))
    out = client(s).post_tracks(1, records(250))
    assert [len(c["json"]["tracks"]) for c in s.calls] == [100, 100, 50]
    assert MAX_BATCH == 100
    assert out["counts"] == {"created": 160, "updated": 40, "skipped": 50}


def test_retries_5xx_and_network_errors_with_exponential_backoff():
    s = FakeSession(err(503), requests.ConnectionError("reset"), err(502), ok(created=1))
    c = client(s, backoff=1.0)
    assert c.post_tracks(1, records(1))["counts"]["created"] == 1
    assert len(s.calls) == 4
    assert c.sleeps == [1.0, 2.0, 4.0]


def test_429_honours_retry_after():
    s = FakeSession(err(429, headers={"Retry-After": "7"}), ok(created=1))
    c = client(s, backoff=1.0)
    c.post_tracks(1, records(1))
    assert c.sleeps == [7.0]


def test_gives_up_after_the_retry_budget():
    s = FakeSession(*[err(503, "unavailable", "down")] * 3)
    c = client(s, retries=2)
    with pytest.raises(ApiError) as e:
        c.post_tracks(1, records(1))
    assert (e.value.status, e.value.code) == (503, "unavailable")
    assert len(s.calls) == 3


def test_4xx_is_not_retried_and_keeps_the_error_code():
    s = FakeSession(err(400, "validation_error", "bad body"))
    with pytest.raises(ApiError) as e:
        client(s).post_tracks(1, records(1))
    assert (e.value.status, e.value.code, e.value.message) == (400, "validation_error", "bad body")
    assert len(s.calls) == 1


def test_access_redirect_is_reported_not_followed():
    s = FakeSession(FakeResponse(302, text_body=True, headers={"Location": "https://team.cloudflareaccess.com/login"}))
    with pytest.raises(ApiError) as e:
        client(s).post_tracks(1, records(1))
    assert e.value.status == 302 and "service token" in e.value.message
    assert len(s.calls) == 1


def test_200_that_is_not_json_is_an_error():
    s = FakeSession(FakeResponse(200, text_body=True))
    with pytest.raises(ApiError) as e:
        client(s).post_tracks(1, records(1))
    assert e.value.code == "bad_response"


def test_413_halves_the_batch():
    s = FakeSession(err(413, "payload_too_large"), ok(created=2), ok(created=2))
    out = client(s).post_tracks(1, records(4))
    assert [len(c["json"]["tracks"]) for c in s.calls] == [4, 2, 2]
    assert out["counts"]["created"] == 4


def test_413_on_a_single_record_is_raised():
    s = FakeSession(err(413, "payload_too_large"))
    with pytest.raises(ApiError):
        client(s).post_tracks(1, records(1))


def test_set_job_status_body():
    s = FakeSession(FakeResponse(200, {"job": {}}), FakeResponse(200, {"job": {}}))
    c = client(s)
    c.set_job_status(9, "running", gh_run_url="https://github.com/o/r/actions/runs/1")
    c.set_job_status(9, "succeeded", summary={"scraped": 3})
    assert s.calls[0]["url"] == "https://api.test/admin/ingest/jobs/9/status"
    assert s.calls[0]["json"] == {"status": "running", "ghRunUrl": "https://github.com/o/r/actions/runs/1"}
    assert s.calls[1]["json"] == {"status": "succeeded", "summary": {"scraped": 3}}


def test_get_catalog_snapshot_is_a_bodyless_get():
    snap = {"artists": [], "tracks": []}
    s = FakeSession(FakeResponse(200, snap))
    out = client(s).get_catalog_snapshot()
    assert out == snap
    call = s.calls[0]
    assert (call["method"], call["url"]) == ("GET", "https://api.test/admin/ingest/catalog-snapshot")
    assert call["json"] is None  # no request body on the GET
