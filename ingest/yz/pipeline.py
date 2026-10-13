"""scrape -> build record -> upload audio -> collect -> POST, with a checkpoint and job status updates."""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Protocol

from .api_client import MAX_BATCH
from .dedupe import flag_duplicates
from .normalize import normalize_record
from .storage import source_key
from .transliterate import transliterate_record

log = logging.getLogger(__name__)

# Field limits of the ingest API (api/src/routes/admin/ingest.ts). One bad record 400s a whole batch,
# so records are shaped to fit before they are sent.
MAX_SOURCE_URL = 2000
MAX_TITLE = 300
MAX_ARTIST = 200
MAX_ALBUM = 300
MAX_FLAGS = 10
MIN_YEAR, MAX_YEAR = 1800, 2100
MAX_ERROR_SAMPLES = 20


class PipelineError(Exception):
    pass


class Source(Protocol):
    def iter_urls(self): ...
    def parse(self, url: str) -> dict | None: ...
    def audio_size(self, mp3_url: str) -> int | None: ...
    def fetch_audio(self, mp3_url: str) -> bytes | None: ...


# ------------------------------------------------------------------ records


def _text(value: object, limit: int) -> str | None:
    text = str(value or "").strip()[:limit].strip()
    return text or None


def _year(value: object) -> int | None:
    text = str(value or "").strip()
    return int(text) if re.fullmatch(r"\d{4}", text) and MIN_YEAR <= int(text) <= MAX_YEAR else None


def build_record(parsed: dict) -> dict:
    """Map the scraper's fields onto the ingest API's track record."""
    return {
        "sourceUrl": parsed["source_url"],
        "titleAm": _text(parsed.get("title_amharic"), MAX_TITLE),
        "titleLatin": _text(parsed.get("title_latin"), MAX_TITLE),
        "artistAm": _text(parsed.get("artist_amharic"), MAX_ARTIST),
        "artistLatin": _text(parsed.get("artist_latin"), MAX_ARTIST),
        "artistAliases": [],
        "album": _text(parsed.get("album"), MAX_ALBUM),
        "releaseYear": _year(parsed.get("year")),
        "genres": [],
        "durationMs": None,
        "sourceAudioKey": None,
        "flags": [],
    }


def validate_record(record: dict) -> str | None:
    """Why the API would reject this record, or None if it is fine."""
    url = record.get("sourceUrl") or ""
    if not url.startswith(("http://", "https://")) or len(url) > MAX_SOURCE_URL:
        return "invalid sourceUrl"
    if not record.get("artistAm"):
        return "no Fidel artist name"
    if len(record.get("flags", [])) > MAX_FLAGS:
        return "too many flags"
    return None


# ----------------------------------------------------------------- pipeline


@dataclass
class RunStats:
    attempted: int = 0  # posts looked at
    scraped: int = 0  # posts turned into a record
    created: int = 0
    updated: int = 0
    skipped: int = 0
    flagged: int = 0
    errors: int = 0
    audio_uploaded: int = 0
    audio_unchanged: int = 0
    error_samples: list[str] = field(default_factory=list)

    def error(self, message: str) -> None:
        self.errors += 1
        log.warning(message)
        if len(self.error_samples) < MAX_ERROR_SAMPLES:
            self.error_samples.append(message)

    def summary(self) -> dict:
        return {
            "scraped": self.scraped,
            "created": self.created,
            "updated": self.updated,
            "skipped": self.skipped,
            "flagged": self.flagged,
            "errors": self.errors,
            "audio_uploaded": self.audio_uploaded,
            "audio_unchanged": self.audio_unchanged,
            "error_samples": self.error_samples,
        }


class Pipeline:
    def __init__(
        self,
        source: Source,
        *,
        api=None,
        store=None,
        job_id: int | None = None,
        gh_run_url: str | None = None,
        dry_run: bool = False,
        out_path: str = "ethiozeima_data/dry-run.jsonl",
        checkpoint_path: str = "ethiozeima_data/checkpoint.json",
        limit: int | None = None,
        batch_size: int = MAX_BATCH,
        resume: bool = True,
    ):
        if not dry_run and (api is None or store is None or job_id is None):
            raise ValueError("a real run needs api, store and job_id")
        self.source = source
        self.api = api
        self.store = store
        self.job_id = job_id
        self.gh_run_url = gh_run_url
        self.dry_run = dry_run
        self.out_path = out_path
        self.checkpoint_path = checkpoint_path
        self.limit = limit
        self.batch_size = max(1, min(batch_size, MAX_BATCH))
        self.resume = resume
        self.stats = RunStats()

    # ------------------------------------------------------------------ run

    def run(self) -> RunStats:
        if not self.dry_run:
            self.api.set_job_status(self.job_id, "running", gh_run_url=self.gh_run_url)
        try:
            self._process()
        except Exception as exc:
            log.error("run failed: %s", exc)
            if not self.dry_run:
                try:
                    self.api.set_job_status(
                        self.job_id, "failed", summary={**self.stats.summary(), "failure": str(exc)}
                    )
                except Exception:
                    log.exception("could not report the failure to the API")
            raise
        if not self.dry_run:
            self.api.set_job_status(self.job_id, "succeeded", summary=self.stats.summary())
            self._clear_checkpoint()  # a finished run has nothing to resume
        return self.stats

    def _process(self) -> None:
        if self.dry_run:
            os.makedirs(os.path.dirname(self.out_path) or ".", exist_ok=True)
            open(self.out_path, "w", encoding="utf-8").close()

        pending: list[dict] = []
        for url in self._urls_to_process():
            if self.limit is not None and self.stats.attempted >= self.limit:
                break
            self.stats.attempted += 1
            record = self._build(url)
            if record is not None:
                pending.append(record)
            if len(pending) >= self.batch_size:
                self._flush(pending, url)
                pending = []
        if pending:
            self._flush(pending, pending[-1]["sourceUrl"])

        if self.stats.attempted > 0 and self.stats.scraped == 0:
            raise PipelineError(f"none of the {self.stats.attempted} posts could be turned into a record")

    def _urls_to_process(self):
        """Post URLs after the checkpoint (if any). The archive is newest first, so everything after
        the checkpoint URL is what the interrupted run had not reached yet."""
        urls = iter(self.source.iter_urls())
        last = self._load_checkpoint() if self.resume and not self.dry_run else None
        if last is None:
            return urls
        skipped: list[str] = []
        for url in urls:
            if url == last:
                log.info("resuming after %s (skipped %d already processed posts)", last, len(skipped) + 1)
                return urls
            skipped.append(url)
        log.warning("checkpoint URL %s not found in the archive; processing everything", last)
        return iter(skipped)

    # --------------------------------------------------------------- records

    def _build(self, url: str) -> dict | None:
        """One post -> one record ready to send, or None (counted as an error)."""
        try:
            parsed = self.source.parse(url)
            if parsed is None:
                self.stats.error(f"could not fetch {url}")
                return None
            record = transliterate_record(normalize_record(build_record(parsed)))
        except Exception as exc:  # one odd page must not stop the run
            log.exception("failed to parse %s", url)
            self.stats.error(f"could not parse {url}: {exc}")
            return None

        problem = validate_record(record)
        if problem:
            self.stats.error(f"skipped {url}: {problem}")
            return None

        self._attach_audio(record, parsed.get("mp3_url") or "")
        self.stats.scraped += 1
        return record

    def _attach_audio(self, record: dict, mp3_url: str) -> None:
        url = record["sourceUrl"]
        if not mp3_url:
            record["flags"].append({"reason": "missing_audio", "details": {"cause": "no_mp3_link"}})
            return
        key = source_key(url)
        if self.dry_run:  # nothing is downloaded or uploaded
            record["sourceAudioKey"] = key
            return

        existing = self.store.size(key)
        if existing is not None and self.source.audio_size(mp3_url) == existing:
            self.stats.audio_unchanged += 1  # already in R2 and the same size: no download either
            record["sourceAudioKey"] = key
            return

        data = self.source.fetch_audio(mp3_url)
        if data is None:
            self.stats.error(f"audio download failed for {url}")
            record["flags"].append({"reason": "missing_audio", "details": {"cause": "download_failed"}})
            return
        if self.store.ensure(key, data):
            self.stats.audio_uploaded += 1
        else:
            self.stats.audio_unchanged += 1
        record["sourceAudioKey"] = key

    # ----------------------------------------------------------------- flush

    def _flush(self, batch: list[dict], last_url: str) -> None:
        batch = flag_duplicates(batch)
        self.stats.flagged += sum(1 for r in batch if r["flags"])
        if self.dry_run:
            with open(self.out_path, "a", encoding="utf-8") as f:
                for record in batch:
                    f.write(json.dumps(record, ensure_ascii=False) + "\n")
            return
        counts = self.api.post_tracks(self.job_id, batch)["counts"]
        self.stats.created += counts["created"]
        self.stats.updated += counts["updated"]
        self.stats.skipped += counts["skipped"]
        log.info("posted %d tracks: %s", len(batch), counts)
        self._save_checkpoint(last_url)

    # ------------------------------------------------------------ checkpoint

    def _load_checkpoint(self) -> str | None:
        try:
            with open(self.checkpoint_path, encoding="utf-8") as f:
                return json.load(f).get("lastUrl") or None
        except (OSError, ValueError):
            return None

    def _save_checkpoint(self, url: str) -> None:
        os.makedirs(os.path.dirname(self.checkpoint_path) or ".", exist_ok=True)
        tmp = self.checkpoint_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"lastUrl": url, "updatedAt": datetime.now(timezone.utc).isoformat()}, f)
        os.replace(tmp, self.checkpoint_path)

    def _clear_checkpoint(self) -> None:
        try:
            os.remove(self.checkpoint_path)
        except FileNotFoundError:
            pass
