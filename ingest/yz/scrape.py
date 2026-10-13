"""CLI: scrape ethiozeima.com, upload source audio to R2, register tracks with the API.

    python -m yz.scrape --limit 20 --dry-run          # JSONL on disk, nothing uploaded or posted
    python -m yz.scrape --since 2024-01-01            # real run (needs the env vars in yz/config.py)

Run it from the `ingest/` directory.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import date

from .api_client import MAX_BATCH, ApiClient
from .config import Config, ConfigError
from .pipeline import Pipeline
from .source import EthiozeimaSource
from .storage import SourceStore

OUT_DIR = "ethiozeima_data"


def _iso_date(text: str) -> date:
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected YYYY-MM-DD, got {text!r}") from None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="python -m yz.scrape", description=__doc__.split("\n")[0])
    ap.add_argument("--limit", type=int, help="process at most this many posts")
    ap.add_argument("--since", type=_iso_date, metavar="DATE", help="only posts published on or after YYYY-MM-DD")
    ap.add_argument("--dry-run", action="store_true", help="write JSONL locally; upload and post nothing")
    ap.add_argument("--delay", type=float, default=float(os.environ.get("SCRAPE_DELAY", 2.0)),
                    help="seconds between requests to the source site (default 2, or $SCRAPE_DELAY)")
    ap.add_argument("--max-pages", type=int, default=50, help="max archive pages to walk (default 50)")
    ap.add_argument("--batch-size", type=int, default=MAX_BATCH, help=f"records per POST (max {MAX_BATCH})")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "dry-run.jsonl"), help="dry-run output file")
    ap.add_argument("--checkpoint", default=os.path.join(OUT_DIR, "checkpoint.json"), help="resume file")
    ap.add_argument("--fresh", action="store_true", help="ignore and replace any checkpoint")
    args = ap.parse_args(argv)
    if args.limit is not None and args.limit < 1:
        ap.error("--limit must be at least 1")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("yz.scrape")

    source = EthiozeimaSource(delay=args.delay, max_pages=args.max_pages, since=args.since)
    common = dict(limit=args.limit, batch_size=args.batch_size, out_path=args.out, checkpoint_path=args.checkpoint)

    if args.dry_run:
        pipeline = Pipeline(source, dry_run=True, **common)
    else:
        try:
            cfg = Config.from_env()
        except ConfigError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        api = ApiClient(cfg.api_base, cfg.cf_access_client_id, cfg.cf_access_client_secret)
        pipeline = Pipeline(
            source, api=api, store=SourceStore.from_config(cfg), job_id=cfg.job_id,
            gh_run_url=cfg.gh_run_url, resume=not args.fresh, **common,
        )

    try:
        stats = pipeline.run()
    except KeyboardInterrupt:
        log.warning("interrupted; re-run to resume from the checkpoint")
        return 130
    except Exception:
        log.exception("run failed")
        return 1

    where = f" -> {args.out}" if args.dry_run else ""
    log.info("done%s: %s", where, {k: v for k, v in stats.summary().items() if k != "error_samples"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
