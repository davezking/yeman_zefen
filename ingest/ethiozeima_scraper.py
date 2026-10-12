#!/usr/bin/env python3
"""
ethiozeima_scraper.py
=====================
Builds an Amharic-music database from ethiozeima.com for a "guess the intro"
game: pulls metadata (artist / title / album / year, in both Latin and Fidel)
AND downloads each song's MP3.

IMPORTANT — rights:
    Only run the audio-download part if you actually hold a licence covering the
    SOUND RECORDINGS (masters), e.g. a blanket licence from the music
    association that explicitly covers recordings, not just the composition.
    The CSV this writes (tracks.csv) doubles as your USAGE LOG — the record of
    exactly which songs you used, which a pay-per-use royalty deal will ask for.
    Keep it; hand it to the association for accounting.

What it does:
    1. Walks the site's archive pages politely and collects every post URL.
    2. Opens each post and extracts:
         artist_latin, artist_amharic, title_latin, title_amharic,
         album, year, source_url, mp3_url
    3. Optionally downloads the MP3 (skips files already downloaded).
    4. Writes everything to tracks.csv (UTF-8 with BOM so Amharic shows
       correctly in Excel), plus a matching clip_start_time column left blank
       for you to fill later with the best "intro" moment per song.

Requirements:
    pip install requests beautifulsoup4

Usage:
    # metadata only (always safe — bare facts, no audio):
    python ethiozeima_scraper.py --no-audio

    # metadata + audio (only with a master licence):
    python ethiozeima_scraper.py

    # be gentle / limit while testing:
    python ethiozeima_scraper.py --delay 4 --max-pages 2 --no-audio
"""

import argparse
import csv
import os
import re
import sys
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://ethiozeima.com/"
OUT_DIR = "ethiozeima_data"
AUDIO_DIR = os.path.join(OUT_DIR, "audio")
CSV_PATH = os.path.join(OUT_DIR, "tracks.csv")

# A post permalink on this site looks like /2014/11/02/some-slug/
POST_URL_RE = re.compile(r"/\d{4}/\d{2}/\d{2}/[^/]+/?$")
MP3_RE = re.compile(r"https?://[^\s\"'<>]+?\.mp3", re.IGNORECASE)
YEAR_RE = re.compile(r"\[(\d{4})\]")
# Fidel field labels used on the site ("ርአስ" and the variant "ርእስ" both appear)
ARTIST_AM_RE = re.compile(r"አርቲስት\s*[:：]\s*([^\n<]+?)(?:አልበም|ርእስ|ርአስ|$)")
TITLE_AM_RE = re.compile(r"ር[አእ]ስ\s*[:：]\s*([^\n<]+)")
ALBUM_RE = re.compile(r"Album\s*[:：]\s*(.+?)\s*(?:\[\d{4}\]|Song\s*[:：]|$)", re.IGNORECASE)

HEADERS = {
    "User-Agent": "AmharicMusicGame/1.0 (metadata collection; contact: you@example.com)"
}

FIELDNAMES = [
    "track_id",
    "artist_latin",
    "artist_amharic",
    "title_latin",
    "title_amharic",
    "album",
    "year",
    "source_url",
    "mp3_url",
    "local_audio_path",
    "clip_start_time",  # left blank — fill with the best intro timestamp later
]


def get(session, url, retries=4):
    """GET with simple exponential backoff. Returns Response or None."""
    for attempt in range(retries):
        try:
            r = session.get(url, headers=HEADERS, timeout=30)
            if r.status_code == 200:
                return r
            if r.status_code == 404:
                return None
            # 429 / 5xx → back off and retry
        except requests.RequestException:
            pass
        wait = 2 ** attempt
        print(f"  …retry {attempt + 1} for {url} (waiting {wait}s)")
        time.sleep(wait)
    print(f"  !! giving up on {url}")
    return None


def collect_post_urls(session, delay, max_pages):
    """Walk /page/N/ archive pages and gather unique post permalinks."""
    found = []
    seen = set()
    page = 1
    while page <= max_pages:
        page_url = BASE_URL if page == 1 else urljoin(BASE_URL, f"page/{page}/")
        print(f"Archive page {page}: {page_url}")
        r = get(session, page_url)
        if r is None:
            break
        soup = BeautifulSoup(r.text, "html.parser")
        new_on_page = 0
        for a in soup.find_all("a", href=True):
            href = urljoin(BASE_URL, a["href"].split("#")[0])
            if urlparse(href).netloc.endswith("ethiozeima.com") and POST_URL_RE.search(
                urlparse(href).path
            ):
                if href not in seen:
                    seen.add(href)
                    found.append(href)
                    new_on_page += 1
        print(f"  found {new_on_page} new post links (total {len(found)})")
        if new_on_page == 0:
            break
        page += 1
        time.sleep(delay)
    return found


def parse_post(session, url):
    """Extract one track's fields from a post page. Missing fields come back ''."""
    r = get(session, url)
    if r is None:
        return None
    soup = BeautifulSoup(r.text, "html.parser")
    html = r.text
    text = soup.get_text("\n")

    # --- Latin artist + title come from the post's og:title ------------------
    # Format: "<Song> Lyrics – <Artist>"
    og = soup.find("meta", attrs={"property": "og:title"})
    title_full = og["content"].strip() if og and og.get("content") else ""
    title_latin = artist_latin = ""
    m = re.split(r"\s+Lyrics\s*[–\-]\s*", title_full, maxsplit=1)
    if len(m) == 2:
        title_latin, artist_latin = m[0].strip(), m[1].strip()
    elif title_full:
        title_latin = title_full.replace("Lyrics", "").strip()

    # --- Fidel artist + title ------------------------------------------------
    am_artist = ARTIST_AM_RE.search(text)
    am_title = TITLE_AM_RE.search(text)
    artist_amharic = am_artist.group(1).strip() if am_artist else ""
    title_amharic = am_title.group(1).strip() if am_title else ""

    # --- Album + year --------------------------------------------------------
    album_m = ALBUM_RE.search(text)
    album = album_m.group(1).strip() if album_m else ""
    year_m = YEAR_RE.search(text)  # first [YYYY] on the page (Latin/Gregorian side)
    year = year_m.group(1) if year_m else ""

    # --- MP3 -----------------------------------------------------------------
    mp3_match = MP3_RE.search(html)
    mp3_url = mp3_match.group(0) if mp3_match else ""

    return {
        "artist_latin": artist_latin,
        "artist_amharic": artist_amharic,
        "title_latin": title_latin,
        "title_amharic": title_amharic,
        "album": album,
        "year": year,
        "source_url": url,
        "mp3_url": mp3_url,
        "local_audio_path": "",
        "clip_start_time": "",
    }


def download_audio(session, mp3_url, delay):
    """Download an MP3, skipping if already present. Returns local path or ''."""
    if not mp3_url:
        return ""
    name = os.path.basename(urlparse(mp3_url).path)
    dest = os.path.join(AUDIO_DIR, name)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest  # already have it
    r = get(session, mp3_url)
    if r is None:
        return ""
    with open(dest, "wb") as f:
        f.write(r.content)
    time.sleep(delay)
    return dest


def main():
    ap = argparse.ArgumentParser(description="Scrape ethiozeima.com into a track database.")
    ap.add_argument("--delay", type=float, default=3.0,
                    help="seconds to wait between requests (be polite; default 3)")
    ap.add_argument("--max-pages", type=int, default=50,
                    help="max archive pages to walk (default 50)")
    ap.add_argument("--no-audio", action="store_true",
                    help="metadata only; do NOT download MP3s")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    if not args.no_audio:
        os.makedirs(AUDIO_DIR, exist_ok=True)

    session = requests.Session()

    print("Step 1/3 — collecting post URLs…")
    post_urls = collect_post_urls(session, args.delay, args.max_pages)
    print(f"Collected {len(post_urls)} post URLs.\n")

    print("Step 2/3 — parsing posts" + ("" if args.no_audio else " and downloading audio") + "…")
    rows = []
    for i, url in enumerate(post_urls, 1):
        print(f"[{i}/{len(post_urls)}] {url}")
        track = parse_post(session, url)
        if track is None:
            continue
        track["track_id"] = f"t{i:04d}"
        if not args.no_audio and track["mp3_url"]:
            path = download_audio(session, track["mp3_url"], args.delay)
            track["local_audio_path"] = path
            print(f"    audio: {'saved ' + path if path else 'FAILED'}")
        rows.append(track)
        time.sleep(args.delay)

    print(f"\nStep 3/3 — writing {CSV_PATH}…")
    # utf-8-sig = UTF-8 with BOM, so Fidel renders correctly when opened in Excel
    with open(CSV_PATH, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in FIELDNAMES})

    missing_year = sum(1 for r in rows if not r["year"])
    missing_am = sum(1 for r in rows if not r["artist_amharic"])
    print(f"\nDone. {len(rows)} tracks → {CSV_PATH}")
    print(f"  • {missing_year} rows have no year — verify these by hand")
    print(f"  • {missing_am} rows have no Fidel artist name — verify these by hand")
    if not args.no_audio:
        print(f"  • audio saved under {AUDIO_DIR}/")
    print("\nReminder: tracks.csv is your usage log. Keep it for royalty reporting.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted — partial data may be in the output folder.")
        sys.exit(1)
