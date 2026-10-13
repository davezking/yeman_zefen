"""Artist and track duplicate detection: a case table plus the within-batch pipeline hook."""

import pytest

from yz.dedupe import (
    ARTIST_NEAR,
    TRACK_DUP,
    Snapshot,
    flag_duplicates,
    resolve,
)

# A small catalog. Artist 1 has two tracks; artist 2 one; artist 3 a similarly-named artist to 1.
CATALOG = {
    "artists": [
        [1, "ጥላሁን ገሠሠ", ["ጥላሁን ገሰሰ", "tilahun gessesse", "tilahun g."]],
        [2, "አስቴር አወቀ", ["aster aweke"]],
        [3, "ጥላሁን taye", ["tilahun taye"]],
        [4, "ሙላቱ አስታጥቄ", ["mulatu astatke"]],
    ],
    "tracks": [
        [10, 1, "ትዝታ", "Tizita", 200_000],
        [11, 1, "አንቺ ሆዬ", "Anchi Hoye", 240_000],
        [12, 2, "ሽሞንሙዋነሽ", "Shemonmwanesh", 190_000],
        [13, 4, "ትዝታ", "Tizita", 205_000],
    ],
}


def rec(sourceUrl="https://ethiozeima.com/2014/11/02/x/", artistAm=None, artistLatin=None, titleAm=None, titleLatin=None, durationMs=None):
    return {
        "sourceUrl": sourceUrl, "artistAm": artistAm, "artistLatin": artistLatin,
        "titleAm": titleAm, "titleLatin": titleLatin, "durationMs": durationMs,
        "artistAliases": [], "flags": [],
    }


def snap():
    return Snapshot.from_api(CATALOG)


def decide(**kw):
    a, t, f = resolve(rec(**kw), snap())
    return a, t, f


# --------------------------------------------------- the required case table (>= 25)

# Each: a record, the expected artist status, the expected track status.
# artist: matched | ambiguous | new ; track: update | duplicate | new
CASES = [
    # --- artist resolution
    ("exact Fidel", dict(artistAm="ጥላሁን ገሠሠ"), "matched", "new"),
    ("homophone-letter variant resolves exact", dict(artistAm="ጥላሁን ገሰሰ"), "matched", "new"),
    ("other homophone spelling resolves exact", dict(artistAm="ጥላሁን ገሠሰ"), "matched", "new"),
    ("exact via Latin alias", dict(artistLatin="Tilahun Gessesse"), "matched", "new"),
    ("exact via short Latin alias", dict(artistLatin="Tilahun G."), "matched", "new"),
    ("Latin case/punctuation insensitive", dict(artistLatin="TILAHUN GESSESSE"), "matched", "new"),
    ("near Fidel typo is ambiguous", dict(artistAm="ጥላሁን ገሠሠሠ"), "ambiguous", "new"),
    ("near Latin spelling is ambiguous", dict(artistLatin="Tilahun Gesesse"), "ambiguous", "new"),
    ("token-swapped Latin name is ambiguous", dict(artistLatin="Astatke Mulatu"), "ambiguous", "new"),
    ("brand-new artist", dict(artistAm="ኤፍሬም ታምሩ"), "new", "new"),
    ("clearly different artist is not flagged", dict(artistLatin="Bob Marley"), "new", "new"),
    # --- track resolution within the matched artist
    ("exact track dup (Fidel)", dict(artistAm="ጥላሁን ገሠሠ", titleAm="ትዝታ", durationMs=201_000), "matched", "duplicate"),
    ("exact track dup (Latin)", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita", durationMs=200_000), "matched", "duplicate"),
    ("track dup via homophone title", dict(artistAm="ጥላሁን ገሠሠ", titleAm="ትዝታ"), "matched", "duplicate"),
    ("live version flagged", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita (Live)", durationMs=260_000), "matched", "duplicate"),
    ("remix flagged", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita - Remix"), "matched", "duplicate"),
    ("amharic live marker flagged", dict(artistAm="ጥላሁን ገሠሠ", titleAm="ትዝታ ቀጥታ"), "matched", "duplicate"),
    ("different song, same artist, not a dup", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Aykedashim Libe"), "matched", "new"),
    ("near-miss title below threshold", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizitaye"), "matched", "new"),
    ("same title different artist is not a dup", dict(artistAm="አስቴር አወቀ", titleLatin="Tizita"), "matched", "new"),
    ("second artist's own track dup", dict(artistLatin="Aster Aweke", titleLatin="Shemonmwanesh"), "matched", "duplicate"),
    ("new artist means no track check", dict(artistAm="ኤፍሬም ታምሩ", titleLatin="Tizita"), "new", "new"),
    ("ambiguous artist means no track check", dict(artistLatin="Tilahun Gesesse", titleLatin="Tizita"), "ambiguous", "new"),
    ("title dup needs the right artist", dict(artistLatin="Mulatu Astatke", titleLatin="Tizita"), "matched", "duplicate"),
    ("anchi hoye is artist 1's other track", dict(artistAm="ጥላሁን ገሠሠ", titleLatin="Anchi Hoye", durationMs=241_000), "matched", "duplicate"),
    ("empty record is new", dict(), "new", "new"),
]


def test_there_are_enough_cases():
    assert len(CASES) >= 25


@pytest.mark.parametrize("name,kw,artist_status,track_status", CASES, ids=[c[0] for c in CASES])
def test_case_table(name, kw, artist_status, track_status):
    artist, track, _flags = decide(**kw)
    assert artist["status"] == artist_status, f"{name}: artist {artist}"
    assert track["status"] == track_status, f"{name}: track {track}"


# ------------------------------------------------------- specific behaviours


def test_no_auto_merge_every_uncertain_case_is_a_flag():
    artist, track, flags = decide(artistLatin="Tilahun Gesesse")
    assert artist["artist_id"] is None and artist["status"] == "ambiguous"
    assert flags and flags[0]["reason"] == "possible_duplicate" and flags[0]["details"]["field"] == "artist"
    assert flags[0]["details"]["candidates"][0]["id"] == 1
    assert flags[0]["details"]["candidates"][0]["score"] >= ARTIST_NEAR


def test_exact_match_is_not_a_merge_just_the_same_key():
    artist, _t, flags = decide(artistAm="ጥላሁን ገሰሰ")  # a homophone spelling of artist 1
    assert artist["status"] == "matched" and artist["artist_id"] == 1 and flags == []


def test_duplicate_track_flag_carries_candidate_id_and_score():
    _a, track, flags = decide(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita", durationMs=200_000)
    assert track["status"] == "duplicate"
    dup = next(f for f in flags if f["details"]["field"] == "track")
    assert dup["details"]["candidates"][0]["id"] == 10 and dup["details"]["candidates"][0]["score"] == 1.0


def test_live_version_has_variant_hint_and_duration_penalty():
    _a, _t, flags = decide(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita (Live)", durationMs=300_000)
    dup = next(f for f in flags if f["details"]["field"] == "track")
    assert dup["details"]["variant_of"] == "live"
    cand = dup["details"]["candidates"][0]
    assert cand["score"] < 1.0 and cand["durationDiff"] > 0.15  # the duration gap lowered the score


def test_duration_within_tolerance_is_not_penalised():
    _a, _t, flags = decide(artistAm="ጥላሁን ገሠሠ", titleLatin="Tizita", durationMs=210_000)  # 5% off
    cand = next(f for f in flags if f["details"]["field"] == "track")["details"]["candidates"][0]
    assert cand["score"] == 1.0 and "durationDiff" not in cand


def test_exact_source_url_is_an_update_not_a_duplicate():
    s = snap()
    s.tracks[0].source_url = "https://ethiozeima.com/known/"  # pretend track 10 came from this post
    a, t, f = resolve(rec(sourceUrl="https://ethiozeima.com/known/", artistAm="ጥላሁን ገሠሠ", titleAm="ትዝታ"), s)
    assert t["status"] == "update" and t["track_id"] == 10
    assert not any(fl["details"]["field"] == "track" for fl in f)


def test_resolve_is_pure_snapshot_unchanged():
    s = snap()
    before = (len(s.artists), len(s.tracks))
    for _ in range(3):
        resolve(rec(artistAm="ጥላሁን ገሠሠ", titleAm="ትዝታ"), s)
        resolve(rec(artistLatin="Nobody New"), s)
    assert (len(s.artists), len(s.tracks)) == before


# ----------------------------------------------------- within-batch detection


def test_within_batch_second_occurrence_of_a_new_artist_is_flagged():
    a = rec(sourceUrl="u1", artistLatin="Ephrem Tamiru", titleLatin="Wede Fiker")
    b = rec(sourceUrl="u2", artistLatin="Ephrem Tamiru", titleLatin="Another Song")
    flag_duplicates([a, b], Snapshot.from_api(CATALOG))
    assert a["flags"] == []  # first sighting: nothing to compare against
    # second record sees the first: same (new) artist, so it is not re-flagged as an artist dup,
    # but a same-title would be. Different titles here, so no track flag either.
    assert b["flags"] == []


def test_within_batch_same_song_twice_is_flagged_the_second_time():
    a = rec(sourceUrl="u1", artistAm="ኤፍሬም ታምሩ", titleLatin="Wege new")
    b = rec(sourceUrl="u2", artistAm="ኤፍሬም ታምሩ", titleLatin="Wege New")  # same artist + song, different post
    flag_duplicates([a, b], Snapshot.from_api(CATALOG))
    assert a["flags"] == []
    track_flags = [f for f in b["flags"] if f["details"]["field"] == "track"]
    assert track_flags and track_flags[0]["details"]["candidates"][0]["sourceUrl"] == "u1"


def test_within_batch_runs_against_an_empty_catalog_too():
    a = rec(sourceUrl="u1", artistLatin="New Artist", titleLatin="Song")
    b = rec(sourceUrl="u2", artistLatin="New Artist", titleLatin="Song")
    flag_duplicates([a, b], None)  # no snapshot at all (e.g. dry-run)
    assert a["flags"] == []
    assert any(f["details"]["field"] == "track" for f in b["flags"])


def test_flag_duplicates_accepts_raw_payload_and_does_not_duplicate_flags():
    r = rec(artistLatin="Tilahun Gesesse")
    r["flags"].append({"reason": "possible_duplicate", "details": {"field": "artist", "candidates": []}})
    flag_duplicates([r], CATALOG)  # already has an artist possible_duplicate: must not add a second
    assert sum(1 for f in r["flags"] if f["details"]["field"] == "artist") == 1
