"""Artist and track duplicate detection (FR-4, FR-2).

`resolve(record, snapshot)` is a pure function: given a scraped record and a catalog snapshot it decides
which existing artist the record belongs to, whether its track already exists, and what to flag. It
NEVER merges: an exact normalized match is treated as the same entity (that is not a merge, just the
same key), but anything fuzzy becomes a `possible_duplicate` flag for an admin to resolve by hand.
The snapshot is passed in, so there are no network calls here.

`flag_duplicates(records, index)` is the pipeline hook: it runs `resolve` against a growing index so
duplicates within one scrape batch are caught too, not just against the stored catalog.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .fidel import has_fidel, normalize_fidel, normalize_latin
from .transliterate import distance_ratio, loose_latin

# --- Thresholds. Admin-tunable; each is the point past which human judgement is cheaper than a mistake.
ARTIST_NEAR = 0.85  # fuzzy artist match: flag for review, never auto-attach (a wrong merge corrupts keys)
TRACK_DUP = 0.90  # title similarity that means "probably the same song" — higher than artists, titles are short
DURATION_TOLERANCE = 0.15  # durations within 15% are "the same length"; beyond it, likely a different cut
DURATION_PENALTY = 0.9  # a title match with a big duration gap is still flagged, but at a lower reported score

# Markers that make a title a known variant rather than the canonical recording (FR-4). Latin is matched
# on word boundaries (so "live" does not fire inside "deliver"); Amharic as a substring.
_LATIN_MARKERS = (
    "live", "remix", "cover", "version", "acoustic", "instrumental", "karaoke",
    "remaster", "remastered", "reprise", "unplugged", "edit", "demo", "medley",
)
_AMHARIC_MARKERS = ("ቀጥታ", "ኮቨር", "ሪሚክስ", "ኮፒ")
_LATIN_MARKER_RE = re.compile(r"\b(" + "|".join(_LATIN_MARKERS) + r")\b")


# ------------------------------------------------------------------ similarity


def _sim(a: str, b: str) -> float:
    """1.0 is identical, 0.0 nothing in common. Empty either side is 0 (an absent field matches nothing)."""
    if not a or not b:
        return 0.0
    return 1.0 - distance_ratio(a, b)


def _token_sorted(s: str) -> str:
    return " ".join(sorted(s.split()))


def _best_sim(a: str, b: str) -> float:
    """Token-order-insensitive: "Gigi Shibabaw" and "Shibabaw Gigi" score as the same name."""
    if not a or not b:
        return 0.0
    return max(_sim(a, b), _sim(_token_sorted(a), _token_sorted(b)))


_PUNCT_RE = re.compile(r"[^\w\s]", re.UNICODE)


def _core_title(title_fidel: str, title_latin: str) -> tuple[str, str]:
    """The title with variant markers and punctuation removed, so "Tizita (Live)" compares equal to
    "Tizita" (and is flagged as a variant), while genuinely different titles still differ."""
    latin = _LATIN_MARKER_RE.sub(" ", title_latin)
    fidel = title_fidel
    for marker in _AMHARIC_MARKERS:
        fidel = fidel.replace(marker, " ")
    clean = lambda t: " ".join(_PUNCT_RE.sub(" ", t).split())
    return clean(fidel), clean(latin)


def _variant_marker(title_fidel: str, title_latin: str) -> str | None:
    m = _LATIN_MARKER_RE.search(title_latin)
    if m:
        return m.group(1)
    for marker in _AMHARIC_MARKERS:
        if marker in title_fidel:
            return marker
    return None


# -------------------------------------------------------------------- snapshot


def _ref(entry) -> dict:
    """How a candidate names an entry: a catalog id, or a source URL for a record still in this batch."""
    return {"id": entry.id} if entry.id is not None else {"sourceUrl": entry.source_url}


@dataclass
class ArtistEntry:
    id: int | None  # None for a record added from the current batch (not yet in the catalog)
    source_url: str | None
    fidel_keys: frozenset[str]  # normalized name_am plus any Fidel aliases
    latin_keys: frozenset[str]  # normalized Latin aliases

    @property
    def key(self) -> tuple:
        return ("id", self.id) if self.id is not None else ("url", self.source_url)


@dataclass
class TrackEntry:
    id: int | None
    source_url: str | None
    artist_key: tuple
    title_fidel: str
    title_latin: str
    duration_ms: int | None


@dataclass
class Snapshot:
    artists: list[ArtistEntry] = field(default_factory=list)
    tracks: list[TrackEntry] = field(default_factory=list)

    @classmethod
    def from_api(cls, payload: dict | None) -> Snapshot:
        """Parse `GET /admin/ingest/catalog-snapshot` (positional rows named by `columns`)."""
        snap = cls()
        if not payload:
            return snap
        by_id: dict[int, ArtistEntry] = {}
        for aid, name_am, alias_norms in payload.get("artists", []):
            fidel = {normalize_fidel(name_am)} | {a for a in alias_norms if has_fidel(a)}
            latin = {a for a in alias_norms if a and not has_fidel(a)}
            entry = ArtistEntry(id=aid, source_url=None, fidel_keys=frozenset(f for f in fidel if f), latin_keys=frozenset(latin))
            snap.artists.append(entry)
            by_id[aid] = entry
        for tid, artist_id, title_am, title_latin, duration_ms in payload.get("tracks", []):
            owner = by_id.get(artist_id)
            snap.tracks.append(
                TrackEntry(
                    id=tid,
                    source_url=None,
                    artist_key=owner.key if owner else ("id", artist_id),
                    title_fidel=normalize_fidel(title_am or ""),
                    title_latin=loose_latin(title_latin or ""),
                    duration_ms=duration_ms,
                )
            )
        return snap

    def artist_by_key(self, key: tuple) -> ArtistEntry | None:
        return next((a for a in self.artists if a.key == key), None)

    def tracks_of(self, key: tuple) -> list[TrackEntry]:
        return [t for t in self.tracks if t.artist_key == key]

    def add_record(self, record: dict, artist_decision: dict) -> None:
        """Fold a just-resolved record into the index so later records in the batch can match it.

        A record that matched an existing artist is filed under that artist; otherwise it becomes a new
        batch artist (keyed by its source URL) so a second spelling later in the batch still collides."""
        url = record.get("sourceUrl")
        matched = artist_decision.get("artist_key")
        if matched is None:
            matched = ("url", url)
            if self.artist_by_key(matched) is None:
                self.artists.append(
                    ArtistEntry(
                        id=None,
                        source_url=url,
                        fidel_keys=frozenset(k for k in [normalize_fidel(record.get("artistAm") or "")] if k),
                        latin_keys=frozenset(k for k in [normalize_latin(record.get("artistLatin") or "")] if k),
                    )
                )
        self.tracks.append(
            TrackEntry(
                id=None,
                source_url=url,
                artist_key=matched,
                title_fidel=normalize_fidel(record.get("titleAm") or ""),
                title_latin=loose_latin(record.get("titleLatin") or ""),
                duration_ms=record.get("durationMs"),
            )
        )


# --------------------------------------------------------------------- resolve


def _resolve_artist(record: dict, snapshot: Snapshot) -> dict:
    r_fidel = normalize_fidel(record.get("artistAm") or "")
    r_latin = normalize_latin(record.get("artistLatin") or "")
    if not r_fidel and not r_latin:
        return {"status": "new", "artist_id": None, "artist_key": None, "candidates": []}

    # Exact: the normalized Fidel (homophones folded) or Latin key is already one of the artist's keys.
    for artist in snapshot.artists:
        if (r_fidel and r_fidel in artist.fidel_keys) or (r_latin and r_latin in artist.latin_keys):
            return {"status": "matched", "artist_id": artist.id, "artist_key": artist.key, "candidates": []}

    # Near: fuzzy, token-order-insensitive, on Fidel or Latin. Flag only; the admin decides (FR-4).
    candidates = []
    for artist in snapshot.artists:
        score = max(
            [_best_sim(r_fidel, k) for k in artist.fidel_keys] + [_best_sim(r_latin, k) for k in artist.latin_keys] + [0.0]
        )
        if score >= ARTIST_NEAR:
            candidates.append({**_ref(artist), "score": round(score, 3)})
    candidates.sort(key=lambda c: c["score"], reverse=True)
    status = "ambiguous" if candidates else "new"
    return {"status": status, "artist_id": None, "artist_key": None, "candidates": candidates}


def _resolve_track(record: dict, snapshot: Snapshot, artist_key: tuple) -> dict:
    url = record.get("sourceUrl")
    t_fidel, t_latin = _core_title(normalize_fidel(record.get("titleAm") or ""), loose_latin(record.get("titleLatin") or ""))
    duration = record.get("durationMs")

    candidates = []
    for track in snapshot.tracks_of(artist_key):
        if url and track.source_url == url:
            return {"status": "update", "track_id": track.id, "candidates": []}  # same post: an update, not a dup
        e_fidel, e_latin = _core_title(track.title_fidel, track.title_latin)
        score = max(_best_sim(t_fidel, e_fidel), _best_sim(t_latin, e_latin))
        if score < TRACK_DUP:
            continue
        note = {**_ref(track), "score": round(score, 3)}
        if duration and track.duration_ms:
            diff = abs(duration - track.duration_ms) / max(duration, track.duration_ms)
            if diff > DURATION_TOLERANCE:
                note["score"] = round(score * DURATION_PENALTY, 3)
                note["durationDiff"] = round(diff, 3)
        candidates.append(note)

    if not candidates:
        return {"status": "new", "track_id": None, "candidates": []}
    candidates.sort(key=lambda c: c["score"], reverse=True)
    return {"status": "duplicate", "track_id": None, "candidates": candidates}


def resolve(record: dict, snapshot: Snapshot) -> tuple[dict, dict, list[dict]]:
    """Decide artist and track for one record against `snapshot`. Returns
    `(artist_decision, track_decision, flags)`; `flags` are ready to append to `record["flags"]`.
    Pure: `snapshot` is not modified and nothing is fetched."""
    flags: list[dict] = []
    artist = _resolve_artist(record, snapshot)
    if artist["status"] == "ambiguous":
        flags.append({"reason": "possible_duplicate", "details": {"field": "artist", "candidates": artist["candidates"]}})

    track = {"status": "new", "track_id": None, "candidates": []}
    if artist["status"] == "matched":  # only look for a duplicate track once we know the artist
        track = _resolve_track(record, snapshot, artist["artist_key"])
        if track["status"] == "duplicate":
            details = {"field": "track", "candidates": track["candidates"]}
            marker = _variant_marker(
                normalize_fidel(record.get("titleAm") or ""), loose_latin(record.get("titleLatin") or "")
            )
            if marker:
                details["variant_of"] = marker
            flags.append({"reason": "possible_duplicate", "details": details})
    return artist, track, flags


# ----------------------------------------------------------------- pipeline hook


def _flag_key(flag: dict) -> str:
    details = flag["details"]
    return f"{flag['reason']}|{details.get('field')}"


def flag_duplicates(records: list[dict], index: Snapshot | dict | None = None) -> list[dict]:
    """Append `possible_duplicate` flags in place, against the catalog AND earlier records in the batch.

    `index` is the catalog snapshot (a Snapshot, or the raw API payload). It grows as records are
    processed so a duplicate that appears twice in one batch is caught the second time."""
    snapshot = index if isinstance(index, Snapshot) else Snapshot.from_api(index)
    for record in records:
        record.setdefault("flags", [])
        artist, _track, flags = resolve(record, snapshot)
        have = {_flag_key(f) for f in record["flags"]}
        for flag in flags:
            if _flag_key(flag) not in have:
                record["flags"].append(flag)
        snapshot.add_record(record, artist)
    return records
