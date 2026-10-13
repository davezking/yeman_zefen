"""ethiozeima.com as a record source: the legacy scraping logic behind a small, throttled interface."""

from __future__ import annotations

import time
from collections.abc import Callable, Iterator
from datetime import date

import requests

import ethiozeima_scraper as legacy


class Throttle:
    """Keeps at least `delay` seconds between requests to the source site."""

    def __init__(
        self,
        delay: float,
        *,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.delay = delay
        self._clock = clock
        self._sleep = sleep
        self._last: float | None = None

    def wait(self) -> None:
        if self._last is not None:
            remaining = self._last + self.delay - self._clock()
            if remaining > 0:
                self._sleep(remaining)
        self._last = self._clock()


class EthiozeimaSource:
    def __init__(
        self,
        *,
        delay: float = 2.0,
        max_pages: int = 50,
        since: date | None = None,
        session: requests.Session | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.delay = delay
        self.max_pages = max_pages
        self.since = since
        self.session = session if session is not None else requests.Session()
        self._sleep = sleep
        self._throttle = Throttle(delay, sleep=sleep)

    def iter_urls(self) -> Iterator[str]:
        """Post permalinks, newest first. Archive pages are fetched as they are needed."""
        return legacy.iter_post_urls(self.session, self.delay, self.max_pages, self.since, self._sleep)

    def parse(self, url: str) -> dict | None:
        """The legacy `parse_post` fields for one post, or None when it cannot be fetched."""
        self._throttle.wait()
        return legacy.parse_post(self.session, url)

    def audio_size(self, mp3_url: str) -> int | None:
        """Size the site reports for the MP3 (HEAD), or None."""
        self._throttle.wait()
        return legacy.head_size(self.session, mp3_url)

    def fetch_audio(self, mp3_url: str) -> bytes | None:
        """The MP3 bytes, or None when the download fails or is empty."""
        self._throttle.wait()
        resp = legacy.get(self.session, mp3_url)
        return resp.content if resp is not None and resp.content else None
