"""SourceStore and key derivation, against an in-memory S3 stand-in."""

import hashlib

import pytest

from fakes import AccessDenied, FakeS3, NotFound
from yz.config import Config, ConfigError
from yz.storage import SourceStore, source_key


def test_key_is_sha1_of_the_source_url():
    url = "https://ethiozeima.com/2014/11/02/some-slug/"
    assert source_key(url) == f"source/{hashlib.sha1(url.encode()).hexdigest()}.mp3"
    assert source_key(url) == source_key(url)
    assert source_key(url) != source_key(url + "x")


def test_uploads_a_new_object_as_audio_mpeg():
    s3 = FakeS3()
    assert SourceStore(s3).ensure("source/a.mp3", b"abc") is True
    assert s3.puts == [("yz-source", "source/a.mp3", "audio/mpeg")]


def test_skips_when_the_object_exists_with_the_same_size():
    s3 = FakeS3()
    s3.objects["source/a.mp3"] = b"xyz"
    assert SourceStore(s3).ensure("source/a.mp3", b"abc") is False
    assert s3.puts == []


def test_reuploads_when_the_size_differs():
    s3 = FakeS3()
    s3.objects["source/a.mp3"] = b"short"
    assert SourceStore(s3).ensure("source/a.mp3", b"longer data") is True
    assert s3.objects["source/a.mp3"] == b"longer data"


@pytest.mark.parametrize("code", ["404", "NoSuchKey", "NotFound"])
def test_missing_object_has_no_size(code):
    s3 = FakeS3()
    s3.head_object = lambda Bucket, Key: (_ for _ in ()).throw(NotFound(code))
    assert SourceStore(s3).size("source/a.mp3") is None


def test_other_storage_errors_propagate():
    s3 = FakeS3()
    s3.fail_with = AccessDenied()
    with pytest.raises(AccessDenied):
        SourceStore(s3).size("source/a.mp3")


ENV = {
    "API_BASE": "https://api.test/", "CF_ACCESS_CLIENT_ID": "i", "CF_ACCESS_CLIENT_SECRET": "s",
    "R2_ENDPOINT": "https://acct.r2.cloudflarestorage.com", "R2_ACCESS_KEY_ID": "k",
    "R2_SECRET_ACCESS_KEY": "v", "JOB_ID": "12",
}


def test_config_reads_the_environment():
    cfg = Config.from_env({**ENV, "GITHUB_SERVER_URL": "https://github.com", "GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "99"})
    assert cfg.job_id == 12 and cfg.api_base == "https://api.test" and cfg.r2_bucket == "yz-source"
    assert cfg.gh_run_url == "https://github.com/o/r/actions/runs/99"


def test_config_names_every_missing_variable():
    with pytest.raises(ConfigError) as e:
        Config.from_env({"API_BASE": "x"})
    assert "JOB_ID" in str(e.value) and "R2_ENDPOINT" in str(e.value)


@pytest.mark.parametrize("bad", ["abc", "0", "-3"])
def test_config_rejects_a_bad_job_id(bad):
    with pytest.raises(ConfigError):
        Config.from_env({**ENV, "JOB_ID": bad})


def test_from_config_builds_an_s3_client_for_r2():
    store = SourceStore.from_config(Config.from_env(ENV))
    assert store.bucket == "yz-source"
    assert store.client.meta.endpoint_url == "https://acct.r2.cloudflarestorage.com"


# ------------------------------------------------------------- clips and downloads


def test_download_writes_the_object_to_disk(tmp_path):
    from yz.storage import SourceStore

    s3 = FakeS3()
    s3.objects["source/a.mp3"] = b"x" * (3 << 20) + b"tail"  # more than one chunk
    dest = tmp_path / "a.src"
    assert SourceStore(s3).download("source/a.mp3", dest) is True
    assert dest.read_bytes() == s3.objects["source/a.mp3"]


def test_download_of_a_missing_object_is_false_and_writes_nothing(tmp_path):
    from yz.storage import SourceStore

    dest = tmp_path / "gone.src"
    assert SourceStore(FakeS3()).download("source/gone.mp3", dest) is False
    assert not dest.exists()


def test_download_lets_other_errors_through(tmp_path):
    from yz.storage import SourceStore

    s3 = FakeS3()
    s3.fail_with = AccessDenied()
    with pytest.raises(AccessDenied):
        SourceStore(s3).download("source/a.mp3", tmp_path / "a.src")


def test_clip_upload_is_public_immutable_audio_and_always_writes():
    from yz.storage import ClipStore

    s3 = FakeS3()
    store = ClipStore(s3)
    store.upload("clips/1/intro-v1.mp3", b"aaa")
    store.upload("clips/1/intro-v1.mp3", b"bbb")  # same key, same size: still written (see ClipStore.upload)
    assert s3.objects["clips/1/intro-v1.mp3"] == b"bbb" and len(s3.put_calls) == 2
    assert s3.put_calls[0] == {
        "Bucket": "yz-clips", "Key": "clips/1/intro-v1.mp3", "ContentType": "audio/mpeg",
        "CacheControl": "public, max-age=31536000, immutable",
    }


def test_config_reads_the_clips_bucket():
    assert Config.from_env(ENV).r2_clips_bucket == "yz-clips"
    assert Config.from_env({**ENV, "R2_CLIPS_BUCKET": "my-clips"}).r2_clips_bucket == "my-clips"
