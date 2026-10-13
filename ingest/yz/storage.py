"""Source audio in the private R2 bucket `yz-source`, through R2's S3-compatible API."""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path

from .config import Config

log = logging.getLogger(__name__)

NOT_FOUND_CODES = frozenset({"404", "NoSuchKey", "NotFound"})


def source_key(source_url: str) -> str:
    """Stable object key for a post: `source/{sha1(source_url)}.mp3`."""
    digest = hashlib.sha1(source_url.encode("utf-8"), usedforsecurity=False).hexdigest()
    return f"source/{digest}.mp3"


def _is_not_found(exc: Exception) -> bool:
    # botocore's ClientError carries the S3 error in `.response`; duck-typed so botocore is not imported here.
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return False
    code = str(response.get("Error", {}).get("Code", ""))
    status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")
    return code in NOT_FOUND_CODES or status == 404


def r2_client(cfg: Config):
    """An S3 client for R2. One API token can cover both buckets, so source and clips share it."""
    import boto3  # imported here so --dry-run works without boto3 installed
    from botocore.config import Config as BotoConfig

    return boto3.client(
        "s3",
        endpoint_url=cfg.r2_endpoint,
        aws_access_key_id=cfg.r2_access_key_id,
        aws_secret_access_key=cfg.r2_secret_access_key,
        region_name="auto",
        config=BotoConfig(
            signature_version="s3v4",
            # boto3 >= 1.36 adds CRC checksums by default, which R2 does not accept on every call.
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
        ),
    )


class SourceStore:
    def __init__(self, client, bucket: str = "yz-source"):
        self.client = client
        self.bucket = bucket

    @classmethod
    def from_config(cls, cfg: Config) -> SourceStore:
        return cls(r2_client(cfg), cfg.r2_bucket)

    def download(self, key: str, dest: str | Path) -> bool:
        """Stream the object to `dest`. False when it does not exist; other failures propagate."""
        try:
            body = self.client.get_object(Bucket=self.bucket, Key=key)["Body"]
        except Exception as exc:
            if _is_not_found(exc):
                return False
            raise
        with open(dest, "wb") as f:
            for chunk in body.iter_chunks(1 << 20):
                f.write(chunk)
        return True

    def size(self, key: str) -> int | None:
        """Size in bytes of the stored object, or None when it does not exist.
        Any other failure (bad credentials, network) propagates."""
        try:
            head = self.client.head_object(Bucket=self.bucket, Key=key)
        except Exception as exc:
            if _is_not_found(exc):
                return None
            raise
        return int(head["ContentLength"])

    def ensure(self, key: str, data: bytes) -> bool:
        """Upload `data` unless an object with the same size is already there. True if uploaded."""
        if self.size(key) == len(data):
            return False
        self.client.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType="audio/mpeg")
        log.info("uploaded %s (%d bytes)", key, len(data))
        return True


class ClipStore:
    """The public clips bucket `yz-clips`. Keys carry the clip version, so an object is never rewritten
    once it is registered, and can be cached forever."""

    CACHE_CONTROL = "public, max-age=31536000, immutable"

    def __init__(self, client, bucket: str = "yz-clips"):
        self.client = client
        self.bucket = bucket

    @classmethod
    def from_config(cls, cfg: Config) -> ClipStore:
        return cls(r2_client(cfg), cfg.r2_clips_bucket)

    def upload(self, key: str, data: bytes) -> None:
        """Always writes. Only ever called for a key that is not registered yet (a new version), where
        replacing an earlier half-finished upload is correct and skipping on a matching size is not:
        the registered checksum has to be the checksum of what is stored."""
        self.client.put_object(
            Bucket=self.bucket, Key=key, Body=data, ContentType="audio/mpeg", CacheControl=self.CACHE_CONTROL
        )
        log.info("uploaded %s (%d bytes)", key, len(data))
