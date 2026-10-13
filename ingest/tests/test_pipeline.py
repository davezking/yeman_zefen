"""Pipeline end to end with a fake source, API and R2: dry run, uploads, re-runs, resume, failures."""

import json
import os

import pytest

from fakes import FakeApi, FakeS3, FakeSource, parsed, url
from yz.api_client import ApiError
from yz.pipeline import Pipeline, PipelineError, build_record, validate_record
from yz.storage import SourceStore, source_key


@pytest.fixture
def paths(tmp_path):
    return {"out_path": str(tmp_path / "out.jsonl"), "checkpoint_path": str(tmp_path / "checkpoint.json")}


def real_run(source, paths, api=None, s3=None, **kw):
    api = api if api is not None else FakeApi()
    s3 = s3 if s3 is not None else FakeS3()
    p = Pipeline(source, api=api, store=SourceStore(s3), job_id=7, **paths, **kw)
    return p, api, s3


# ------------------------------------------------------------------ dry run


def test_dry_run_writes_valid_jsonl_and_touches_nothing(paths):
    src = FakeSource(5)
    # No api and no store: any attempt to post or upload would blow up.
    stats = Pipeline(src, dry_run=True, limit=5, **paths).run()

    with open(paths["out_path"], encoding="utf-8") as f:
        records = [json.loads(line) for line in f]
    assert len(records) == 5 and stats.scraped == 5
    assert all(validate_record(r) is None for r in records)
    assert records[0]["artistAm"] == "ጥላሁን ገሠሠ"  # Fidel is written as is, not \u-escaped
    assert records[0]["sourceAudioKey"] == source_key(url(1))
    assert src.fetched == [] and src.sized == []  # no audio downloaded
    assert not os.path.exists(paths["checkpoint_path"])


def test_dry_run_ignores_an_existing_checkpoint(paths):
    json.dump({"lastUrl": url(2)}, open(paths["checkpoint_path"], "w"))
    src = FakeSource(3)
    Pipeline(src, dry_run=True, **paths).run()
    assert src.parsed == [url(1), url(2), url(3)]
    assert os.path.exists(paths["checkpoint_path"])  # left as it was


def test_limit_stops_after_n_posts(paths):
    src = FakeSource(5)
    Pipeline(src, dry_run=True, limit=2, **paths).run()
    assert src.parsed == [url(1), url(2)]


# ---------------------------------------------------------------- real runs


def test_real_run_uploads_audio_posts_in_batches_and_reports_status(paths):
    src = FakeSource(3)
    p, api, s3 = real_run(src, paths, batch_size=2)
    stats = p.run()

    assert [len(b) for b in api.posts] == [2, 1]
    assert [s for s, _ in api.statuses] == ["running", "succeeded"]
    summary = api.statuses[-1][1]
    assert (summary["scraped"], summary["created"], summary["updated"], summary["flagged"], summary["errors"]) == (3, 3, 0, 0, 0)
    assert stats.audio_uploaded == 3
    for i, record in enumerate(api.posts[0] + api.posts[1], 1):
        key = source_key(url(i))
        assert record["sourceAudioKey"] == key and s3.objects[key] == f"mp3-bytes-{i}".encode()
    assert not os.path.exists(paths["checkpoint_path"])  # finished: nothing to resume


def test_rerun_does_not_download_or_upload_existing_audio(paths):
    s3 = FakeS3()
    real_run(FakeSource(3), paths, s3=s3)[0].run()
    assert len(s3.puts) == 3

    again = FakeSource(3)
    p, api, _ = real_run(again, paths, s3=s3)
    stats = p.run()
    assert len(s3.puts) == 3 and again.fetched == []  # not even re-downloaded from the site
    assert stats.audio_uploaded == 0 and stats.audio_unchanged == 3
    assert all(r["sourceAudioKey"] for batch in api.posts for r in batch)  # still registered


def test_same_size_in_r2_is_not_reuploaded_when_the_site_gives_no_size(paths):
    s3 = FakeS3()
    real_run(FakeSource(1), paths, s3=s3)[0].run()
    again = FakeSource(1)
    again.audio_size = lambda mp3: None  # HEAD told us nothing: download, compare, skip the upload
    real_run(again, paths, s3=s3)[0].run()
    assert len(again.fetched) == 1 and len(s3.puts) == 1


def test_changed_audio_is_reuploaded(paths):
    s3 = FakeS3()
    s3.objects[source_key(url(1))] = b"old"
    src = FakeSource(1)
    stats = real_run(src, paths, s3=s3)[0].run()
    assert stats.audio_uploaded == 1 and s3.objects[source_key(url(1))] == b"mp3-bytes-1"


def test_post_without_an_mp3_link_is_flagged_missing_audio(paths):
    src = FakeSource(posts={url(1): parsed(1, mp3_url="")})
    p, api, _ = real_run(src, paths)
    stats = p.run()
    record = api.posts[0][0]
    assert record["sourceAudioKey"] is None
    assert record["flags"] == [{"reason": "missing_audio", "details": {"cause": "no_mp3_link"}}]
    assert (stats.flagged, stats.errors) == (1, 0)


def test_failed_audio_download_is_flagged_and_counted_but_the_track_is_still_sent(paths):
    src = FakeSource(posts={url(1): parsed(1)}, audio={})
    p, api, s3 = real_run(src, paths)
    stats = p.run()
    assert api.posts[0][0]["flags"][0]["details"] == {"cause": "download_failed"}
    assert (stats.errors, stats.flagged, s3.puts) == (1, 1, [])


def test_post_with_no_artist_name_at_all_is_skipped_not_sent(paths):
    src = FakeSource(posts={url(1): parsed(1, artist_amharic="", artist_latin=""), url(2): parsed(2)})
    p, api, _ = real_run(src, paths)
    stats = p.run()
    assert [r["sourceUrl"] for b in api.posts for r in b] == [url(2)]
    assert stats.errors == 1 and "no Fidel artist" in stats.error_samples[0]
    assert api.statuses[-1][0] == "succeeded"


def test_post_with_only_a_latin_artist_gets_fidel_generated_and_is_flagged(paths):
    src = FakeSource(posts={url(1): parsed(1, artist_amharic="")})
    p, api, _ = real_run(src, paths)
    stats = p.run()
    record = api.posts[0][0]
    assert record["artistAm"] == "ቲላሁን ገሰሰ" and record["artistLatin"] == "Tilahun Gessesse"
    assert "Tilahun Gessesse" in record["artistAliases"]
    flag = record["flags"][0]
    assert flag["reason"] == "translit_uncertain" and flag["details"]["field"] == "artist"
    assert (stats.flagged, stats.errors) == (1, 0)


def test_post_with_only_fidel_gets_latin_generated(paths):
    src = FakeSource(posts={url(1): parsed(1, artist_latin="", title_latin="")})
    p, api, _ = real_run(src, paths)
    stats = p.run()
    record = api.posts[0][0]
    assert (record["artistLatin"], record["titleLatin"]) == ("tilahun gesese", "zefen 1") and record["flags"] == []
    assert stats.flagged == 0


def test_mismatched_latin_title_is_flagged_but_still_sent_as_scraped(paths):
    src = FakeSource(posts={url(1): parsed(1, title_latin="Love Song")})
    p, api, _ = real_run(src, paths)
    stats = p.run()
    record = api.posts[0][0]
    assert record["titleLatin"] == "Love Song" and record["flags"][0]["details"]["field"] == "title"
    assert stats.flagged == 1


def test_names_are_cleaned_but_not_folded_before_sending(paths):
    src = FakeSource(posts={url(1): parsed(1, artist_amharic="  ጥላሁን   ገሠሠ ")})
    p, api, _ = real_run(src, paths)
    p.run()
    assert api.posts[0][0]["artistAm"] == "ጥላሁን ገሠሠ"  # spelling kept; the API folds its own key


def test_unfetchable_post_is_counted_and_the_run_continues(paths):
    src = FakeSource(posts={url(1): None, url(2): parsed(2)})
    stats = real_run(src, paths)[0].run()
    assert (stats.scraped, stats.errors) == (1, 1)


def test_a_run_where_nothing_could_be_scraped_fails_the_job(paths):
    src = FakeSource(posts={url(1): None, url(2): None})
    p, api, _ = real_run(src, paths)
    with pytest.raises(PipelineError):
        p.run()
    assert [s for s, _ in api.statuses] == ["running", "failed"]


# ---------------------------------------------------------------- failures


def test_api_failure_marks_the_job_failed_and_keeps_a_checkpoint(paths):
    src = FakeSource(5)
    p, api, _ = real_run(src, paths, api=FakeApi(fail_on_post=2), batch_size=2)
    with pytest.raises(ApiError):
        p.run()
    assert [s for s, _ in api.statuses] == ["running", "failed"]
    assert "boom" in api.statuses[-1][1]["failure"]
    assert json.load(open(paths["checkpoint_path"]))["lastUrl"] == url(2)  # the first batch went through


def test_failure_report_errors_do_not_hide_the_original_error(paths):
    p, api, _ = real_run(FakeSource(2), paths, api=FakeApi(fail_on_post=1, fail_status_report=True))
    with pytest.raises(ApiError, match="boom"):
        p.run()


def test_storage_errors_fail_the_job_instead_of_counting_per_record(paths):
    from fakes import AccessDenied

    s3 = FakeS3()
    s3.fail_with = AccessDenied()
    p, api, _ = real_run(FakeSource(2), paths, s3=s3)
    with pytest.raises(AccessDenied):
        p.run()
    assert [s for s, _ in api.statuses] == ["running", "failed"]


# ---------------------------------------------------------------- resume


def test_resume_continues_after_the_checkpoint(paths):
    with pytest.raises(ApiError):
        real_run(FakeSource(5), paths, api=FakeApi(fail_on_post=2), batch_size=2)[0].run()

    resumed = FakeSource(5)
    p, api, _ = real_run(resumed, paths, batch_size=2)
    p.run()
    assert resumed.parsed == [url(3), url(4), url(5)]
    assert [r["sourceUrl"] for b in api.posts for r in b] == [url(3), url(4), url(5)]
    assert not os.path.exists(paths["checkpoint_path"])


def test_unknown_checkpoint_url_processes_everything(paths):
    json.dump({"lastUrl": "https://ethiozeima.com/2000/01/01/gone/"}, open(paths["checkpoint_path"], "w"))
    src = FakeSource(3)
    real_run(src, paths)[0].run()
    assert src.parsed == [url(1), url(2), url(3)]


def test_fresh_ignores_the_checkpoint(paths):
    json.dump({"lastUrl": url(2)}, open(paths["checkpoint_path"], "w"))
    src = FakeSource(3)
    real_run(src, paths, resume=False)[0].run()
    assert src.parsed == [url(1), url(2), url(3)]


def test_a_real_run_needs_api_store_and_job_id(paths):
    with pytest.raises(ValueError):
        Pipeline(FakeSource(1), **paths)


# ---------------------------------------------------------------- records


def test_build_record_matches_the_api_contract():
    r = build_record(parsed(1, year="1975", album="  Greatest Hits ", title_latin=""))
    assert r == {
        "sourceUrl": url(1), "titleAm": "ዘፈን 1", "titleLatin": None, "artistAm": "ጥላሁን ገሠሠ",
        "artistLatin": "Tilahun Gessesse", "artistAliases": [], "album": "Greatest Hits",
        "releaseYear": 1975, "genres": [], "durationMs": None, "sourceAudioKey": None, "flags": [],
    }


@pytest.mark.parametrize("year,expected", [("1975", 1975), ("", None), ("19x5", None), ("1500", None), ("2200", None)])
def test_release_year_is_only_kept_when_the_api_would_accept_it(year, expected):
    assert build_record(parsed(1, year=year))["releaseYear"] == expected


def test_overlong_text_is_trimmed_to_the_api_limits():
    r = build_record(parsed(1, title_latin="x" * 500, artist_amharic="ም" * 300, album="a" * 400))
    assert len(r["titleLatin"]) == 300 and len(r["artistAm"]) == 200 and len(r["album"]) == 300


def test_validate_record_rejects_what_the_api_would_400_on():
    good = build_record(parsed(1))
    assert validate_record(good) is None
    assert validate_record({**good, "artistAm": None}) == "no Fidel artist name"
    assert validate_record({**good, "sourceUrl": "not a url"}) == "invalid sourceUrl"
    assert validate_record({**good, "flags": [{}] * 11}) == "too many flags"
