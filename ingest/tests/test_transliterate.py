"""Fidel <-> Latin: table coverage, readable output, confidence, and the pipeline hook."""

import unicodedata

import pytest

from yz.transliterate import (
    CONFIDENCE_MIN,
    DISTANCE_MAX,
    MAX_ALIASES,
    SYLLABLES,
    distance_ratio,
    edit_distance,
    fidel_to_latin,
    latin_to_fidel,
    loose_latin,
    transliterate_record,
)
from yz.fidel import normalize_fidel


def record(**over):
    base = {"artistAm": None, "artistLatin": None, "titleAm": None, "titleLatin": None, "artistAliases": [], "flags": []}
    base.update(over)
    return base


# ------------------------------------------------------------------ coverage


def assigned(lo, hi, prefix=""):
    return [chr(cp) for cp in range(lo, hi + 1) if unicodedata.name(chr(cp), "").startswith(prefix)]


def test_every_ethiopic_syllable_is_in_the_table_and_nothing_else_is():
    syllables = set(assigned(0x1200, 0x139F, "ETHIOPIC SYLLABLE"))
    syllables -= set(assigned(0x1380, 0x139F))  # Ethiopic Supplement: other languages, not Amharic
    assert len(syllables) == 326  # Unicode: 358 assigned in the block, less 3 marks, 9 punctuation, 20 numerals
    assert set(SYLLABLES) == syllables


@pytest.mark.parametrize("char", sorted(SYLLABLES))
def test_every_syllable_romanizes_to_plain_letters(char):
    out = fidel_to_latin(char)
    assert out.isascii() and out.isalpha() and out == out.lower(), (char, unicodedata.name(char), out)


def test_nothing_in_the_ethiopic_block_passes_through_or_becomes_a_question_mark():
    for cp in range(0x1200, 0x1380):
        name = unicodedata.name(chr(cp), "")
        if not name or cp == 0x1367:  # ፧ is the question mark itself
            continue
        out = fidel_to_latin(chr(cp))
        assert not any(0x1200 <= ord(c) < 0x1380 for c in out), (hex(cp), name, out)
        assert "?" not in out, (hex(cp), name)


def test_fully_labialized_and_wa_forms():
    assert fidel_to_latin("ቋንቋ") == "qwanqwa"
    assert fidel_to_latin("ኳ") == "kwa" and fidel_to_latin("ሏ") == "lwa" and fidel_to_latin("ጓ") == "gwa"


# --------------------------------------------------------------- Fidel -> Latin


@pytest.mark.parametrize(
    "fidel,latin",
    [
        ("ሰላም", "selam"),  # the 6th order is bare at the end of a word
        ("ጥላሁን ገሠሠ", "tilahun gesese"),  # and takes "i" at the start
        ("ምስጥር", "mistir"),  # and where it would pile up consonants
        ("ገብረመድኅን", "gebremedhin"),
        ("ብርሃን", "birhan"),
        ("ማሕሙድ አሕመድ", "mahmud ahmed"),
        ("እረ መላ መላ", "ere mela mela"),
        ("ሰላም፣ ዓለም።", "selam, alem."),
        ("ሀገሬ ሐገሬ ኀገሬ", "hegere hegere hegere"),  # homophones read alike
        ("ጥላሁን Gessesse 5", "tilahun Gessesse 5"),  # other scripts pass through
        ("", ""),
    ],
)
def test_fidel_to_latin(fidel, latin):
    assert fidel_to_latin(fidel) == latin


@pytest.mark.parametrize("fidel,number", [("፩", 1), ("፲፭", 15), ("፳፻፲፭", 2015), ("፻", 100), ("፻፼", 1_000_000), ("፲", 10)])
def test_ethiopic_numerals(fidel, number):
    assert fidel_to_latin(fidel) == str(number)


def test_combining_marks_are_dropped():
    assert fidel_to_latin("ሰ\u135fላም") == "selam"


# --------------------------------------------------------------- Latin -> Fidel


def test_latin_to_fidel_confident_case():
    text, confidence = latin_to_fidel("selam")
    assert text == "ሰላም" and confidence >= CONFIDENCE_MIN


def test_latin_to_fidel_labialized_forms():
    assert latin_to_fidel("qwanqwa")[0] == "ቋንቋ"


def test_latin_to_fidel_keeps_non_letters_and_existing_fidel():
    assert latin_to_fidel("selam 5, selam")[0] == "ሰላም 5, ሰላም"
    assert latin_to_fidel("ሰላም") == ("ሰላም", 1.0)
    assert latin_to_fidel("") == ("", 1.0)


def test_homophone_spellings_are_not_what_the_guess_gets_wrong():
    # Fidel cannot tell ሠ from ሰ in Latin; the guess is right once the series are folded.
    assert normalize_fidel(latin_to_fidel("gessesse")[0]) == normalize_fidel("ገሠሠ")


@pytest.mark.parametrize("latin", ["Tilahun Gessesse", "Mulatu Astatke", "Haile Gebrselassie", "Ta'amrat", "Teddy Afro", "Aster Aweke"])
def test_ambiguous_names_get_low_confidence(latin):
    assert latin_to_fidel(latin)[1] < CONFIDENCE_MIN


def test_each_kind_of_ambiguity_lowers_confidence():
    base = latin_to_fidel("bu")[1]
    assert base == 1.0  # nothing ambiguous: ቡ
    assert latin_to_fidel("be")[1] < base  # "e": 1st or 5th order
    assert latin_to_fidel("ba")[1] < base  # "a": 4th or 1st order
    assert latin_to_fidel("tu")[1] < base  # ተ or ጠ
    assert latin_to_fidel("bub")[1] < base  # a bare 6th order at the end is a guess
    assert latin_to_fidel("bubu")[1] == base
    assert latin_to_fidel("bubbu")[1] < latin_to_fidel("bubu")[1]  # gemination is not written in Fidel
    assert latin_to_fidel("buu")[1] < base  # vowel hiatus
    assert latin_to_fidel("bux")[1] < latin_to_fidel("bus")[1]  # a letter Amharic does not use


def test_confidence_is_a_probability():
    for latin in ["", "a", "xxxxxxxxxxxxxxxx", "Haile Gebrselassie Wolde Giyorgis Tsegaye", "5 + 5"]:
        assert 0.0 <= latin_to_fidel(latin)[1] <= 1.0


# ---------------------------------------------------------- distance and keys


def test_edit_distance():
    assert edit_distance("kitten", "sitting") == 3
    assert edit_distance("", "abc") == 3 and edit_distance("abc", "abc") == 0
    assert distance_ratio("", "") == 0.0 and distance_ratio("abc", "xyz") == 1.0


def test_loose_latin_ignores_allowed_spelling_variation():
    assert loose_latin("Gessesse") == loose_latin("gesese")
    assert loose_latin("Ephrem") == loose_latin("Efrem")
    assert loose_latin("Qeleme") == loose_latin("Keleme")


# ----------------------------------------------------- real names, both ways

# (Fidel, Latin as it is usually written, is the pair consistent?)
CONSISTENT = [
    ("ጥላሁን ገሠሠ", "Tilahun Gessesse"), ("ማሕሙድ አሕመድ", "Mahmoud Ahmed"), ("አለማየሁ እሸቴ", "Alemayehu Eshete"),
    ("ሙላቱ አስታጥቄ", "Mulatu Astatke"), ("ኤፍሬም ታምሩ", "Ephrem Tamiru"), ("ቴዲ አፍሮ", "Teddy Afro"),
    ("አስቴር አወቀ", "Aster Aweke"), ("ብዙነሽ በቀለ", "Bizunesh Bekele"), ("ጸጋዬ ገብረመድኅን", "Tsegaye Gebremedhin"),
    ("ኢዮብ መኮንን", "Eyob Mekonnen"), ("ሄለን በርሔ", "Helen Berhe"), ("ሂሩት በቀለ", "Hirut Bekele"),
    ("ዘሪቱ ከበደ", "Zeritu Kebede"), ("አብነት አጎናፍር", "Abinet Agonafir"), ("ግርማ በየነ", "Girma Beyene"),
    ("ዋሊያስ ባንድ", "Walias Band"), ("ሙሉቀን መለሰ", "Muluken Melese"), ("ማሪቱ ለገሠ", "Maritu Legesse"),
    ("ትዝታ", "Tizita"), ("አምባሰል", "Ambassel"), ("ባቲ", "Bati"), ("አንቺ ሆዬ", "Anchi Hoye"), ("ሰላም", "Selam"),
    ("ሀገሬ", "Hagere"), ("ሙዚቃ", "Muzika"), ("ሻሸመኔ", "Shashemene"), ("አዲስ አበባ", "Addis Ababa"), ("ቡና", "Buna"),
    ("ጎጃም", "Gojjam"), ("ከተማ", "Ketema"), ("እናቴ", "Enate"), ("ፍቅር", "Fikir"), ("ወሎ", "Wollo"),
]
# Translations, an exonym and wrong pairings: the Latin is not a spelling of the Fidel.
MISMATCHED = [
    ("ኢትዮጵያ", "Ethiopia"), ("ፍቅር", "Love"), ("ሰላም", "Peace"),
    ("ጥላሁን ገሠሠ", "Mahmoud Ahmed"), ("አዲስ አበባ", "Nairobi"),
]


def test_there_are_enough_real_pairs():
    assert len(CONSISTENT) + len(MISMATCHED) >= 30


@pytest.mark.parametrize("fidel,latin", CONSISTENT)
def test_consistent_pairs_are_within_the_threshold(fidel, latin):
    assert distance_ratio(loose_latin(fidel_to_latin(fidel)), loose_latin(latin)) <= DISTANCE_MAX


@pytest.mark.parametrize("fidel,latin", MISMATCHED)
def test_mismatched_pairs_are_over_the_threshold(fidel, latin):
    assert distance_ratio(loose_latin(fidel_to_latin(fidel)), loose_latin(latin)) > DISTANCE_MAX


# --------------------------------------------------------- the pipeline hook


def reasons(rec):
    return [(f["reason"], f["details"]["field"]) for f in rec["flags"]]


@pytest.mark.parametrize("fidel,latin", CONSISTENT)
def test_a_consistent_pair_is_not_flagged(fidel, latin):
    rec = transliterate_record(record(artistAm=fidel, artistLatin=latin, titleAm=fidel, titleLatin=latin))
    assert rec["flags"] == [] and rec["artistLatin"] == latin  # the source spelling stays


@pytest.mark.parametrize("fidel,latin", MISMATCHED)
def test_a_mismatched_pair_is_flagged_and_nothing_is_overwritten(fidel, latin):
    rec = transliterate_record(record(artistAm=fidel, artistLatin=latin))
    assert reasons(rec) == [("translit_uncertain", "artist")]
    detail = rec["flags"][0]["details"]
    assert detail["source"] == latin and detail["generated"] == fidel_to_latin(fidel) and detail["distance"] > DISTANCE_MAX
    assert (rec["artistAm"], rec["artistLatin"]) == (fidel, latin) and rec["artistAliases"] == []


def test_fidel_only_gets_its_latin_generated_without_a_flag():
    rec = transliterate_record(record(artistAm="ጥላሁን ገሠሠ", titleAm="ሰላም"))
    assert (rec["artistLatin"], rec["titleLatin"]) == ("tilahun gesese", "selam") and rec["flags"] == []


def test_latin_only_gets_fidel_and_a_flag_when_unsure():
    rec = transliterate_record(record(artistLatin="Tilahun Gessesse", titleLatin="Selam"))
    assert rec["artistAm"] == "ቲላሁን ገሰሰ" and rec["titleAm"] == "ሰላም"
    assert reasons(rec) == [("translit_uncertain", "artist")]  # the title is fine, the artist is not
    flag = rec["flags"][0]["details"]
    assert flag["source"] == "Tilahun Gessesse" and flag["generated"] == "ቲላሁን ገሰሰ" and flag["confidence"] < CONFIDENCE_MIN
    assert rec["artistLatin"] == "Tilahun Gessesse"
    assert "Tilahun Gessesse" in rec["artistAliases"]  # the source Latin is stored as an alias


def test_latin_only_with_high_confidence_is_not_flagged():
    rec = transliterate_record(record(artistLatin="selam"))
    assert rec["artistAm"] == "ሰላም" and rec["flags"] == [] and rec["artistAliases"] == ["selam"]


def test_a_title_can_be_flagged_on_its_own():
    rec = transliterate_record(record(artistAm="ሰላም", artistLatin="Selam", titleLatin="Mulatu Astatke"))
    assert reasons(rec) == [("translit_uncertain", "title")]


def test_consistent_pair_keeps_the_generated_spelling_as_an_extra_alias():
    rec = transliterate_record(record(artistAm="ጥላሁን ገሠሠ", artistLatin="Tilahun Gessesse"))
    assert rec["artistAliases"] == ["tilahun gesese"]
    again = transliterate_record(rec)  # running it twice adds nothing
    assert again["artistAliases"] == ["tilahun gesese"] and again["flags"] == []


def test_an_identical_spelling_is_not_added_as_an_alias():
    assert transliterate_record(record(artistAm="ሰላም", artistLatin="Selam"))["artistAliases"] == []


def test_aliases_are_capped():
    rec = record(artistLatin="selam", artistAliases=[f"alias {i}" for i in range(MAX_ALIASES)])
    assert len(transliterate_record(rec)["artistAliases"]) == MAX_ALIASES


def test_a_record_with_neither_script_is_left_alone():
    rec = transliterate_record(record(album="Greatest Hits"))
    assert rec["artistAm"] is None and rec["titleAm"] is None and rec["flags"] == []
