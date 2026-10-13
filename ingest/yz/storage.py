"""Source audio in the private R2 bucket `yz-source`, through R2's S3-compatible API."""

from __future__ import annotations

import hashlib
import logging

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


class SourceStore:
    def __init__(self, client, bucket: str = "yz-source"):
        self.client = client
        self.bucket = bucket

    @classmethod
    def from_config(cls, cfg: Config) -> SourceStore:
        import boto3  # imported here so --dry-run works without boto3 installed
        from botocore.config import Config as BotoConfig

        client = boto3.client(
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
        return cls(client, cfg.r2_bucket)

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
