"""Fidel <-> Latin transliteration with confidence flags. Call site only for now (P1S2 task 3)."""

from __future__ import annotations


def transliterate_record(record: dict) -> dict:
    """Pass-through stub. The real version fills in a missing Fidel or Latin side and appends
    `translit_uncertain` flags to `record["flags"]`."""
    return record
