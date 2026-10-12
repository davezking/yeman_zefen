"""Smoke tests: the two scripts import, and the scraper's parsing regexes match real post formats."""

import clip_maker
import ethiozeima_scraper as scraper


def test_post_url_pattern():
    assert scraper.POST_URL_RE.search("/2014/11/02/some-slug/")
    assert not scraper.POST_URL_RE.search("/page/2/")


def test_year_and_fidel_title():
    assert scraper.YEAR_RE.search("Album: Ere Mela Mela [1975]").group(1) == "1975"
    assert scraper.TITLE_AM_RE.search("ርእስ: ትዝታ").group(1).strip() == "ትዝታ"
    assert scraper.TITLE_AM_RE.search("ርአስ： ትዝታ").group(1).strip() == "ትዝታ"


def test_clip_maker_paths():
    assert clip_maker.CSV_IN.endswith("tracks.csv")
