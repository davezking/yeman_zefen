"""EthiozeimaSource drives the legacy scraping code; here it reads HTML fixtures instead of the site."""

from datetime import date

from yz.source import EthiozeimaSource, Throttle

HOME = "https://ethiozeima.com/"


def archive(*hrefs):
    return "<html><body>" + "".join(f'<a href="{h}">post</a>' for h in hrefs) + '<a href="/about/">About</a></body></html>'


POST = """<html><head><meta property="og:title" content="Tizita Lyrics – Tilahun Gessesse"></head><body>
<p>አርቲስት: ጥላሁን ገሠሠ አልበም: ምርጥ ርእስ: ትዝታ</p><p>Album: Greatest Hits [1975]</p>
<audio src="https://ethiozeima.com/wp-content/uploads/tizita.mp3"></audio></body></html>"""


class Resp:
    def __init__(self, status=200, text="", content=b"", headers=None):
        self.status_code, self.text, self.content, self.headers = status, text, content, headers or {}


class SiteSession:
    def __init__(self, pages):
        self.pages = pages  # url -> Resp
        self.requested = []

    def get(self, url, headers=None, timeout=None):
        self.requested.append(url)
        return self.pages.get(url, Resp(404))

    def head(self, url, headers=None, timeout=None, allow_redirects=True):
        self.requested.append(("HEAD", url))
        return self.pages.get(url, Resp(404))


def site():
    new, mid, old = (f"{HOME}{d}/x/" for d in ("2024/05/02", "2023/06/01", "2020/01/10"))
    return SiteSession({
        HOME: Resp(text=archive(new, mid)),
        f"{HOME}page/2/": Resp(text=archive(old)),
        new: Resp(text=POST),
        "https://ethiozeima.com/wp-content/uploads/tizita.mp3": Resp(content=b"ID3data", headers={"Content-Length": "7"}),
    }), (new, mid, old)


def source(session, **kw):
    return EthiozeimaSource(delay=0, session=session, sleep=lambda s: None, **kw)


def test_walks_archive_pages_newest_first():
    session, (new, mid, old) = site()
    assert list(source(session).iter_urls()) == [new, mid, old]


def test_archive_pages_are_fetched_lazily():
    session, (new, *_) = site()
    assert next(iter(source(session).iter_urls())) == new
    assert session.requested == [HOME]  # --limit 1 does not walk page 2


def test_since_skips_old_posts_and_stops_walking():
    session, (new, mid, old) = site()
    session.pages[f"{HOME}page/3/"] = Resp(text=archive(f"{HOME}2019/01/01/y/"))
    assert list(source(session, since=date(2024, 1, 1)).iter_urls()) == [new]
    assert f"{HOME}page/2/" in session.requested  # page 1 still had a post to look at
    assert f"{HOME}page/3/" not in session.requested  # page 2 held nothing newer: stop


def test_parse_reads_latin_and_fidel_fields():
    session, (new, *_) = site()
    post = source(session).parse(new)
    assert post["title_latin"] == "Tizita" and post["artist_latin"] == "Tilahun Gessesse"
    assert post["artist_amharic"] == "ጥላሁን ገሠሠ" and post["title_amharic"] == "ትዝታ"
    assert post["album"] == "Greatest Hits" and post["year"] == "1975"
    assert post["mp3_url"].endswith("tizita.mp3") and post["source_url"] == new


def test_unfetchable_post_is_none():
    session, _ = site()
    assert source(session).parse(f"{HOME}2020/01/01/gone/") is None


def test_audio_size_and_download():
    session, _ = site()
    mp3 = "https://ethiozeima.com/wp-content/uploads/tizita.mp3"
    s = source(session)
    assert s.audio_size(mp3) == 7
    assert s.fetch_audio(mp3) == b"ID3data"
    assert s.audio_size("https://ethiozeima.com/missing.mp3") is None
    assert s.fetch_audio("https://ethiozeima.com/missing.mp3") is None


def test_throttle_keeps_the_configured_gap():
    now, slept = [100.0], []

    def sleep(s):
        slept.append(s)
        now[0] += s

    t = Throttle(2.0, clock=lambda: now[0], sleep=sleep)
    t.wait()  # first request: no wait
    now[0] += 0.5
    t.wait()  # 0.5 s since the last one: wait the other 1.5 s
    now[0] += 5
    t.wait()  # already longer than the delay: no wait
    assert slept == [1.5]
