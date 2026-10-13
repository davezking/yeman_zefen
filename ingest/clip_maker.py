#!/usr/bin/env python3
"""
clip_maker.py
=============
Cuts each song in tracks.csv down to a short "intro" clip for the guessing game.

NOTE: this is the original local, CSV-based tool. The pipeline cuts clips with `python -m yz.cut`
(10 s CBR 128 kbps, intro and middle, uploaded to R2 and registered with the API). See docs/ops.md.

Reads:  ethiozeima_data/tracks.csv   (made by ethiozeima_scraper.py)
Writes: ethiozeima_data/clips/<track_id>.mp3
        ethiozeima_data/tracks_with_clips.csv   (adds a clip_path column)

How the start point is chosen, per row:
    - If clip_start_time is set in the CSV (a number of seconds), start there.
    - Otherwise fall back to --default-start (default 0).
Pick good start seconds by ear and put them in the clip_start_time column — that
is what makes a guessing game fun (skip slow lead-ins, land on the hook).

Requirements:
    - ffmpeg installed and on your PATH  (https://ffmpeg.org/download.html)
      check with:  ffmpeg -version

Usage:
    python clip_maker.py                 # 10s clips, fade in/out
    python clip_maker.py --length 7      # 7-second clips
    python clip_maker.py --default-start 8   # start 8s in when CSV has no value
    python clip_maker.py --no-fade
"""

import argparse
import csv
import os
import subprocess
import sys

OUT_DIR = "ethiozeima_data"
CSV_IN = os.path.join(OUT_DIR, "tracks.csv")
CSV_OUT = os.path.join(OUT_DIR, "tracks_with_clips.csv")
CLIP_DIR = os.path.join(OUT_DIR, "clips")


def have_ffmpeg():
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def cut_clip(src, dst, start, length, fade):
    """Call ffmpeg to cut [start, start+length] from src into dst."""
    cmd = ["ffmpeg", "-y", "-ss", str(start), "-i", src, "-t", str(length)]
    if fade:
        # 0.3s fade in at the start, 0.5s fade out at the end of the clip
        fade_out_start = max(0, length - 0.5)
        cmd += ["-af", f"afade=t=in:st=0:d=0.3,afade=t=out:st={fade_out_start}:d=0.5"]
    cmd += ["-acodec", "libmp3lame", "-q:a", "2", dst]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0


def main():
    ap = argparse.ArgumentParser(description="Cut each track to a short intro clip.")
    ap.add_argument("--length", type=float, default=10.0, help="clip length in seconds (default 10)")
    ap.add_argument("--default-start", type=float, default=0.0,
                    help="start second to use when a row has no clip_start_time (default 0)")
    ap.add_argument("--no-fade", action="store_true", help="disable fade in/out")
    args = ap.parse_args()

    if not have_ffmpeg():
        print("ERROR: ffmpeg not found. Install it and make sure `ffmpeg -version` works.")
        sys.exit(1)

    if not os.path.exists(CSV_IN):
        print(f"ERROR: {CSV_IN} not found. Run ethiozeima_scraper.py first.")
        sys.exit(1)

    os.makedirs(CLIP_DIR, exist_ok=True)

    with open(CSV_IN, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    fade = not args.no_fade
    made = skipped = failed = 0

    for row in rows:
        src = row.get("local_audio_path", "").strip()
        track_id = row.get("track_id", "").strip() or f"row{made + skipped + failed}"
        if not src or not os.path.exists(src):
            row["clip_path"] = ""
            skipped += 1
            continue

        # start point: CSV value if present and numeric, else the default
        raw = row.get("clip_start_time", "").strip()
        try:
            start = float(raw) if raw else args.default_start
        except ValueError:
            start = args.default_start

        dst = os.path.join(CLIP_DIR, f"{track_id}.mp3")
        ok = cut_clip(src, dst, start, args.length, fade)
        if ok:
            row["clip_path"] = dst
            made += 1
            print(f"[{track_id}] {start:g}s → {args.length:g}s  ✓  {row.get('title_latin','')}")
        else:
            row["clip_path"] = ""
            failed += 1
            print(f"[{track_id}] FAILED  {row.get('title_latin','')}")

    fieldnames = list(rows[0].keys()) if rows else []
    if "clip_path" not in fieldnames:
        fieldnames.append("clip_path")
    with open(CSV_OUT, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nDone. {made} clips made, {skipped} skipped (no audio), {failed} failed.")
    print(f"Clips:    {CLIP_DIR}/")
    print(f"Updated:  {CSV_OUT}")


if __name__ == "__main__":
    main()
