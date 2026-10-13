"""normalize_fidel / normalize_latin / clean_text against the fixture shared with the TypeScript side."""

import json
from pathlib import Path

import pytest

from yz.fidel import FOLD_RANGES, clean_text, has_fidel, normalize_fidel, normalize_latin

FIXTURES = json.loads((Path(__file__).resolve().parents[2] / "docs" / "fixtures" / "normalize.json").read_text(encoding="utf-8"))


def cases(kind):
    return [pytest.param(c["in"], c["out"], id=c["name"]) for c in FIXTURES[kind]]


@pytest.mark.parametrize("given,expected", cases("fidel"))
def test_normalize_fidel(given, expected):
    assert normalize_fidel(given) == expected


@pytest.mark.parametrize("given,expected", cases("latin"))
def test_normalize_latin(given, expected):
    assert normalize_latin(given) == expected


@pytest.mark.parametrize("given,expected", cases("clean"))
def test_clean_text(given, expected):
    assert clean_text(given) == expected


def test_normalizers_are_idempotent():
    for kind, fn in (("fidel", normalize_fidel), ("latin", normalize_latin)):
        for c in FIXTURES[kind]:
            assert fn(fn(c["in"])) == fn(c["in"]), c["name"]


def test_every_fold_maps_to_the_same_position_in_the_target_series():
    import unicodedata

    for lo, hi, shift in FOLD_RANGES:
        for cp in range(lo, hi + 1):
            src, dst = unicodedata.name(chr(cp)), unicodedata.name(chr(cp + shift))
            assert src.startswith("ETHIOPIC SYLLABLE") and dst.startswith("ETHIOPIC SYLLABLE")
    assert sum(hi - lo + 1 for lo, hi, _ in FOLD_RANGES) == 39  # 8 + 8 + 8 + 7 + 8


def test_homophone_spellings_of_a_name_share_one_key():
    assert normalize_fidel("ጥላሁን ገሠሠ") == normalize_fidel("ጥላሁን ገሰሰ")
    assert normalize_fidel("ሐገሬ") == normalize_fidel("ኀገሬ") == normalize_fidel("ሀገሬ")


def test_has_fidel():
    assert has_fidel("Tilahun ጥላሁን") and not has_fidel("Tilahun")
