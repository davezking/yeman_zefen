"""Fidel <-> Latin transliteration with confidence flags.

`fidel_to_latin` is deterministic and readable (SERA-inspired, simplified, lowercase ASCII only):
ሰላም -> "selam", ጥላሁን -> "tilahun". `latin_to_fidel` is best effort and returns a confidence,
because Latin spellings of Amharic names are inconsistent and Fidel carries distinctions that Latin
usually drops (ተ/ጠ, ከ/ቀ, the vowel orders). `transliterate_record` is the pipeline call site: when a
record has only one script it generates the other, and it flags anything it is not sure about.
"""

from __future__ import annotations

import re

from .fidel import has_fidel, normalize_latin

CONFIDENCE_MIN = 0.8  # Latin -> Fidel below this is flagged translit_uncertain
DISTANCE_MAX = 0.3  # source Latin vs Latin generated from the Fidel: more than this is flagged
MAX_ALIASES = 20  # the ingest API's limit per record

# ------------------------------------------------------------------ the table
#
# The Ethiopic block is laid out in rows of 8 code points: the seven orders (ä u i a e ə o) and an 8th
# member (the "wa" form). Labialized rows hold only five: wa, wi, waa, wee, we (offsets 0, 2, 3, 4, 5).
# A vowel of None is the 6th order, whose vowel depends on where it sits in the word (see _romanize_word).

_REGULAR = ("e", "u", "i", "a", "e", None, "o", "wa")
_GLOTTAL = ("a", "u", "i", "a", "e", "e", "o", "a")  # አ and ዐ: no consonant of their own
_LABIAL = {0: "e", 2: "i", 3: "a", 4: "e", 5: None}

# first code point of the row -> consonant
_REGULAR_ROWS = {
    0x1200: "h", 0x1208: "l", 0x1210: "h", 0x1218: "m", 0x1220: "s", 0x1228: "r", 0x1230: "s",
    0x1238: "sh", 0x1240: "q", 0x1250: "q", 0x1260: "b", 0x1268: "v", 0x1270: "t", 0x1278: "ch",
    0x1280: "h", 0x1290: "n", 0x1298: "ny", 0x12A8: "k", 0x12B8: "kh", 0x12C8: "w", 0x12D8: "z",
    0x12E0: "zh", 0x12E8: "y", 0x12F0: "d", 0x12F8: "dd", 0x1300: "j", 0x1308: "g", 0x1318: "ng",
    0x1320: "t", 0x1328: "ch", 0x1330: "p", 0x1338: "ts", 0x1340: "ts", 0x1348: "f", 0x1350: "p",
}
_GLOTTAL_ROWS = (0x12A0, 0x12D0)
_SEVEN_MEMBER_ROWS = frozenset({0x1250, 0x12B8, 0x12D0})  # no 8th member: ቐ, ኸ and ዐ rows
_LABIAL_ROWS = {0x1248: "qw", 0x1258: "qw", 0x1288: "hw", 0x12B0: "kw", 0x12C0: "khw", 0x1310: "gw"}
_EXTRA = {0x1358: ("r", "ya"), 0x1359: ("m", "ya"), 0x135A: ("f", "ya")}  # ፘ ፙ ፚ


def _build_syllables() -> dict[str, tuple[str, str | None]]:
    table: dict[str, tuple[str, str | None]] = {}
    for start, cons in _REGULAR_ROWS.items():
        for offset, vowel in enumerate(_REGULAR[: 7 if start in _SEVEN_MEMBER_ROWS else 8]):
            table[chr(start + offset)] = (cons, vowel)
    for start in _GLOTTAL_ROWS:
        for offset, vowel in enumerate(_GLOTTAL[: 7 if start in _SEVEN_MEMBER_ROWS else 8]):
            table[chr(start + offset)] = ("", vowel)
    for start, cons in _LABIAL_ROWS.items():
        for offset, vowel in _LABIAL.items():
            table[chr(start + offset)] = (cons, vowel)
    for cp, (cons, vowel) in _EXTRA.items():
        table[chr(cp)] = (cons, vowel)
    return table


SYLLABLES = _build_syllables()  # char -> (consonant, vowel | None for the 6th order)

PUNCTUATION = {
    "፠": "", "፡": " ", "።": ".", "፣": ",", "፤": ";",
    "፥": ":", "፦": ":", "፧": "?", "፨": "",
}
COMBINING_MARKS = frozenset("\u135d\u135e\u135f")  # gemination and vowel-length marks: dropped
_NUMBER = {chr(0x1369 + i): i + 1 for i in range(9)}  # ፩..፱
_NUMBER.update({chr(0x1372 + i): (i + 1) * 10 for i in range(9)})  # ፲..፺
_HUNDRED, _TEN_THOUSAND = "፻", "፼"  # ፻ ፼
NUMBER_CHARS = frozenset(_NUMBER) | {_HUNDRED, _TEN_THOUSAND}


def _parse_number(run: str) -> int:
    """Ethiopic numerals are not positional: ፳፻፲፭ is 20*100 + 10 + 5 = 2015."""
    total = group = current = 0
    for ch in run:
        if ch == _HUNDRED:
            group += (current or 1) * 100
            current = 0
        elif ch == _TEN_THOUSAND:
            total += (group + current or 1) * 10000
            group = current = 0
        else:
            current += _NUMBER[ch]
    return total + group + current


# ------------------------------------------------------------ Fidel -> Latin


def _romanize_word(run: str) -> str:
    """A run of syllables with no separator. The 6th order has no vowel of its own: it is written bare
    after a vowel (ሰላም -> selam), takes "i" at the start of a word (ጥላሁን -> tilahun) and where it would
    pile up consonants (ምስጥር -> mistir), and a final pair of consonants stays bare (ገብረመድኅን -> gebremedhin)."""
    last = len(run) - 1
    parts: list[str] = []
    bare_run = 0  # consecutive bare consonants just written
    for idx, char in enumerate(run):
        cons, vowel = SYLLABLES[char]
        if vowel is not None:
            parts.append(cons + vowel)
            bare_run = 0
        elif idx > 0 and (bare_run == 0 or (bare_run == 1 and idx == last)):
            parts.append(cons)
            bare_run += 1
        else:
            parts.append(cons + "i")
            bare_run = 0
    return "".join(parts)


def fidel_to_latin(text: str) -> str:
    """Latin for a string that may mix Fidel, punctuation, numerals and anything else (kept as is)."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in SYLLABLES or ch in NUMBER_CHARS:
            group = SYLLABLES if ch in SYLLABLES else NUMBER_CHARS
            j = i
            while j < n and text[j] in group:
                j += 1
            run = text[i:j]
            out.append(_romanize_word(run) if group is SYLLABLES else str(_parse_number(run)))
            i = j
            continue
        if ch not in COMBINING_MARKS:
            out.append(PUNCTUATION.get(ch, ch))
        i += 1
    return "".join(out)


# ------------------------------------------------------------ Latin -> Fidel

_CONS_ROW = {
    "h": 0x1200, "l": 0x1208, "m": 0x1218, "r": 0x1228, "s": 0x1230, "sh": 0x1238, "q": 0x1240,
    "b": 0x1260, "v": 0x1268, "t": 0x1270, "ch": 0x1278, "n": 0x1290, "ny": 0x1298, "k": 0x12A8,
    "kh": 0x12B8, "w": 0x12C8, "z": 0x12D8, "zh": 0x12E0, "y": 0x12E8, "d": 0x12F0, "j": 0x1300,
    "g": 0x1308, "ts": 0x1338, "f": 0x1348, "p": 0x1350,
}
_LABIAL_ROW = {"qw": 0x1248, "kw": 0x12B0, "gw": 0x1310, "hw": 0x1288}
_FALLBACK = {"c": "k", "x": "s"}  # letters Amharic does not use: a guess, at low confidence
_VOWEL_OFFSET = {"e": 0, "u": 1, "i": 2, "a": 3, "o": 6}  # 1st, 2nd, 3rd, 4th, 7th order
_LABIAL_OFFSET = {"e": 0, "i": 2, "a": 3}
_GLOTTAL_OFFSET = {"a": 0, "u": 1, "i": 2, "e": 5, "o": 6}
_BARE = 5  # 6th order
_DIGRAPHS = ("ch", "sh", "zh", "ny", "ts", "kh")
_VOWELS = "aeiou"

# Each factor is the chance that the reading is not the only plausible one.
_F_E = 0.95  # "e" is the 1st order (ሰ), the 5th (ሴ) or, bare, the 6th (ስ)
_F_A = 0.97  # "a" is the 4th order (ሳ), or the 1st (ሰ) written "a"
_F_INITIAL_I = 0.93  # "Ci..." at the start of a word may be a bare 6th order (ጥላሁን, ትዝታ)
_F_CONS_TWIN = 0.95  # t, ch, p, k each have an ejective twin (ተ/ጠ, ቸ/ጨ, ፐ/ጰ, ከ/ቀ)
_F_VOWEL_ONLY = 0.92  # a vowel with no consonant before it: አ, ዐ and the 4th order ኣ all sound alike
_F_HIATUS = 0.85  # two vowels in a row: often a glide that Latin leaves out (Haile = ኃይለ)
_F_BARE_FINAL = 0.99
_F_BARE_MEDIAL = 0.90
_F_GEMINATE = 0.95  # Fidel does not write doubled consonants, so "ss" reads the same as "s"
_F_UNKNOWN = 0.5


def _consonant_at(word: str, i: int) -> str | None:
    """The consonant token starting at word[i], or None if word[i] is a vowel."""
    if i >= len(word):
        return None
    two = word[i : i + 2]
    if two in _LABIAL_ROW and word[i + 2 : i + 3] in tuple(_LABIAL_OFFSET):
        return two
    if two in _DIGRAPHS:
        return two
    ch = word[i]
    return None if ch in _VOWELS else ch


def _fidel_word(word: str) -> tuple[str, float]:
    """One run of lowercase a-z."""
    out: list[str] = []
    confidence = 1.0
    i, n = 0, len(word)
    prev_vowel = False
    while i < n:
        cons = _consonant_at(word, i)
        if cons is None:  # a vowel with no consonant before it
            v = word[i]
            out.append(chr(0x12A0 + _GLOTTAL_OFFSET[v]))
            confidence *= _F_VOWEL_ONLY * (_F_HIATUS if prev_vowel else 1.0) * (_F_E if v == "e" else 1.0)
            prev_vowel = True
            i += 1
            continue

        i += len(cons)
        geminate = False
        while _consonant_at(word, i) == cons:  # "ss" -> one ሰ
            geminate = True
            i += len(cons)
        vowel = word[i] if i < n and word[i] in _VOWELS else None
        if vowel is not None:
            i += 1
        initial = not out

        if cons in _LABIAL_ROW:
            code = _LABIAL_ROW[cons] + _LABIAL_OFFSET[vowel]  # type: ignore[index]  # guaranteed by _consonant_at
        else:
            letter = _FALLBACK.get(cons, cons)
            if letter != cons:
                confidence *= _F_UNKNOWN
            code = _CONS_ROW[letter] + (_VOWEL_OFFSET[vowel] if vowel else _BARE)
            if letter in ("t", "ch", "p", "k"):
                confidence *= _F_CONS_TWIN
        out.append(chr(code))

        if geminate:
            confidence *= _F_GEMINATE
        if vowel == "e":
            confidence *= _F_E
        elif vowel == "a":
            confidence *= _F_A
        elif vowel == "i" and initial and i < n:
            confidence *= _F_INITIAL_I
        elif vowel is None:
            confidence *= _F_BARE_FINAL if i >= n else _F_BARE_MEDIAL
        prev_vowel = vowel is not None
    return "".join(out), confidence


def latin_to_fidel(text: str) -> tuple[str, float]:
    """Best-effort Fidel for a Latin string, and a confidence in [0, 1]. Anything that is not a letter
    (spaces, digits, punctuation) is kept. Text that is already Fidel comes back unchanged."""
    if has_fidel(text):
        return text, 1.0
    out: list[str] = []
    confidence = 1.0
    for piece in re.split(r"([a-z]+)", normalize_latin(text)):
        if piece and piece[0].isalpha() and piece.isascii():
            fidel, c = _fidel_word(piece)
            out.append(fidel)
            confidence *= c
        else:
            out.append(piece)
    return "".join(out), round(max(0.0, min(1.0, confidence)), 3)


# ------------------------------------------------------------------- distance


def loose_latin(s: str) -> str:
    """normalize_latin, minus spelling variation that Latin allows for the same Amharic sound: doubled
    letters (Fidel does not write gemination), q/k and ph/f. Used only to compare two Latin spellings."""
    s = normalize_latin(s).replace("ph", "f").replace("q", "k")
    return re.sub(r"([a-z])\1+", r"\1", s)


def edit_distance(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def distance_ratio(a: str, b: str) -> float:
    """Edit distance divided by the longer length: 0 is identical, 1 is nothing in common."""
    longest = max(len(a), len(b))
    return edit_distance(a, b) / longest if longest else 0.0


# ------------------------------------------------------------- pipeline hook

_FIELDS = (("artist", "artistAm", "artistLatin"), ("title", "titleAm", "titleLatin"))


def _flag(record: dict, **details: object) -> None:
    record["flags"].append({"reason": "translit_uncertain", "details": details})


def _add_alias(record: dict, alias: str, *, skip_if_name: bool = True) -> None:
    """Add a Latin spelling to the artist's aliases unless it is already there (or, by default, is the
    artist's Latin name, which the API keeps as an alias anyway)."""
    aliases = record.setdefault("artistAliases", [])
    key = normalize_latin(alias)
    known = {normalize_latin(a) for a in aliases}
    if skip_if_name:
        known.add(normalize_latin(record.get("artistLatin") or ""))
    if key and key not in known and len(aliases) < MAX_ALIASES:
        aliases.append(alias)


def transliterate_record(record: dict) -> dict:
    """Fill in whichever script a record is missing and flag what is uncertain (see module docstring).

    - Fidel only: Latin is generated, deterministically.
    - Latin only: Fidel is generated; flagged when the confidence is below CONFIDENCE_MIN. The source
      Latin stays as the record's Latin name and is kept as an alias of the artist.
    - Both: the Latin generated from the Fidel is compared with the source Latin (through loose_latin);
      flagged when the normalized edit distance is more than DISTANCE_MAX, otherwise the generated
      spelling is kept as an extra alias.
    """
    for label, am_key, latin_key in _FIELDS:
        am, latin = record.get(am_key), record.get(latin_key)
        if am and not latin:
            record[latin_key] = fidel_to_latin(am)
        elif latin and not am:
            fidel, confidence = latin_to_fidel(latin)
            record[am_key] = fidel
            if label == "artist":
                _add_alias(record, latin, skip_if_name=False)  # the source spelling, kept for matching
            if confidence < CONFIDENCE_MIN:
                _flag(record, field=label, source=latin, generated=fidel, confidence=confidence)
        elif am and latin:
            generated = fidel_to_latin(am)
            distance = distance_ratio(loose_latin(generated), loose_latin(latin))
            if distance > DISTANCE_MAX:
                _flag(record, field=label, source=latin, generated=generated, distance=round(distance, 3))
            elif label == "artist":
                _add_alias(record, generated)
    return record
