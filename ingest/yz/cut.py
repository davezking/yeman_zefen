"""CLI: cut the intro and middle clips for tracks, upload them to R2 and register them with the API.

    python -m yz.cut --track-ids 1,2,3                          # both clips of these tracks
    python -m yz.cut --all-missing [--limit 50]                 # every clip that is not ready yet
    python -m yz.cut --track-id 7 --type intro --start-ms 41200 # recut one clip from a chosen start

Needs ffmpeg on the PATH and the environment variables listed in yz/config.py (JOB_ID is a cut or recut job).
Run it from the `ingest/` directory.
"""

from __future__ import annotations

import argparse
import logging
import sys

from .api_client import ApiClient
from .clips import CLIP_TYPES, Cutter, CutRequest, Selection, ToolError, require_ffmpeg
from .config import Config, ConfigError
from .storage import ClipStore, SourceStore


def _id_list(text: str) -> tuple[int, ...]:
    try:
        ids = tuple(int(part) for part in text.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected comma-separated track ids, got {text!r}") from None
    if not ids or any(i < 1 for i in ids):
        raise argparse.ArgumentTypeError("track ids are positive integers")
    return ids


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="python -m yz.cut", description=__doc__.split("\n")[0])
    which = ap.add_mutually_exclusive_group(required=True)
    which.add_argument("--track-ids", type=_id_list, metavar="1,2,3", help="cut these tracks")
    which.add_argument("--all-missing", action="store_true", help="cut every track that lacks a ready clip")
    which.add_argument("--track-id", type=int, metavar="ID", help="recut one track (use with --type and --start-ms)")
    ap.add_argument("--type", choices=CLIP_TYPES, help="only this clip (default: both)")
    ap.add_argument("--start-ms", type=int, metavar="N", help="start the clip here instead of at its usual start")
    ap.add_argument("--limit", type=int, metavar="N", help="with --all-missing: at most this many tracks")
    args = ap.parse_args(argv)

    if args.track_id is not None and args.track_id < 1:
        ap.error("--track-id must be a positive integer")
    if args.start_ms is not None:
        if args.start_ms < 0:
            ap.error("--start-ms cannot be negative")
        if args.track_id is None and not (args.track_ids and len(args.track_ids) == 1):
            ap.error("--start-ms needs a single track (--track-id)")
        if args.type is None:
            ap.error("--start-ms needs --type: a start applies to one clip")
    if args.limit is not None:
        if not args.all_missing:
            ap.error("--limit goes with --all-missing")
        if args.limit < 1:
            ap.error("--limit must be at least 1")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("yz.cut")

    try:
        cfg = Config.from_env()
        require_ffmpeg()
    except (ConfigError, ToolError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.all_missing:
        selection = Selection(missing=True, limit=args.limit)
    else:
        selection = Selection(track_ids=args.track_ids if args.track_ids else (args.track_id,))
    request = CutRequest(
        types=(args.type,) if args.type else CLIP_TYPES,
        start_ms=args.start_ms,
        only_not_ready=args.all_missing,  # a --all-missing run never touches a clip that is already ready
    )

    api = ApiClient(cfg.api_base, cfg.cf_access_client_id, cfg.cf_access_client_secret, token=cfg.ingest_token)
    cutter = Cutter(api, SourceStore.from_config(cfg), ClipStore.from_config(cfg), cfg.job_id, gh_run_url=cfg.gh_run_url)
    try:
        stats = cutter.run(selection, request)
    except KeyboardInterrupt:
        log.warning("interrupted; re-run to carry on (clips already registered are left as they are)")
        return 130
    except Exception:
        log.exception("run failed")
        return 1

    log.info("done: %s", {k: v for k, v in stats.summary().items() if k != "error_samples"})
    return 0


if __name__ == "__main__":
    sys.exit(main())
