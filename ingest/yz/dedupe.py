"""Artist and track duplicate detection. Call site only for now (P1S2 task 4)."""

from __future__ import annotations


def flag_duplicates(records: list[dict]) -> list[dict]:
    """Pass-through stub. The real version checks a batch against the catalog snapshot and
    appends `possible_duplicate` flags to `record["flags"]`."""
    return records
