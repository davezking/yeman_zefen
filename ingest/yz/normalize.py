"""Record cleanup before transliteration: NFC, collapsed whitespace, empty strings to None.

This does not fold homophones. Stored names keep the spelling the source used; the folded form
(yz.fidel.normalize_fidel) is only a comparison key, and the API builds it.
"""

from __future__ import annotations

from .fidel import clean_text

TEXT_FIELDS = ("titleAm", "titleLatin", "artistAm", "artistLatin", "album")


def normalize_record(record: dict) -> dict:
    for field in TEXT_FIELDS:
        value = record.get(field)
        if isinstance(value, str):
            record[field] = clean_text(value) or None
    record["artistAliases"] = [a for a in (clean_text(x) for x in record.get("artistAliases", [])) if a]
    return record
