"""Comparison-key normalization for Amharic (Fidel) and Latin names.

Mirrors api/src/lib/normalize.ts; both are run against docs/fixtures/normalize.json and must give
identical output. Rules: docs/architecture.md §4, "Amharic normalization". The folded form is only a
comparison key. Stored names keep the spelling the admin or the source chose (see `clean_text`).
"""

from __future__ import annotations

import re
import unicodedata

# Whitespace is listed explicitly rather than with \s, because Python's and JavaScript's \s differ.
WHITESPACE = re.compile("[\t\n\u000b\u000c\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+")
APOSTROPHES = re.compile("['’‘ʼʻ`´]")

# Homophone series folded onto one form, each across the seven orders and the 8th ("wa") member:
# (first code point, last code point, shift onto the target series).
FOLD_RANGES = (
    (0x1210, 0x1217, -0x10),  # ሐ -> ሀ
    (0x1280, 0x1287, -0x80),  # ኀ -> ሀ
    (0x1220, 0x1227, +0x10),  # ሠ -> ሰ
    (0x12D0, 0x12D6, -0x30),  # ዐ -> አ
    (0x1340, 0x1347, -0x08),  # ፀ -> ጸ
)
_FOLD = {cp: cp + shift for lo, hi, shift in FOLD_RANGES for cp in range(lo, hi + 1)}
_FOLD_TABLE = str.maketrans({cp: chr(to) for cp, to in _FOLD.items()})

_ETHIOPIC = re.compile("[ሀ-᎟ⶀ-⷟꬀-꬯]")


def has_fidel(s: str) -> bool:
    return bool(_ETHIOPIC.search(s))


def _collapse(s: str) -> str:
    return WHITESPACE.sub(" ", s).strip(" ")


def clean_text(s: str) -> str:
    """NFC, collapse whitespace, trim. Keeps the spelling: this is the form that gets stored."""
    return _collapse(unicodedata.normalize("NFC", s))


def normalize_fidel(s: str) -> str:
    """Comparison key for a Fidel string: `clean_text`, then homophone series folded."""
    return clean_text(s).translate(_FOLD_TABLE)


def normalize_latin(s: str) -> str:
    """Comparison key for a Latin string: lowercase, diacritics and apostrophes stripped."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.category(c).startswith("M"))
    return _collapse(APOSTROPHES.sub("", s).lower())
