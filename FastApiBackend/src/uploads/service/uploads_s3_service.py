"""S3 upload service for the uploads domain.

Proxies raw image bytes to the shared private S3 bucket and returns a
CloudFront CDN URL with a content-hash cache-buster (?v=<sha256[:16]>).
CloudFront is configured to key its cache on the ``v`` query parameter, so
the bytes behind a given URL never change — they can be cached hard.

boto3 is imported lazily so the rest of the app (and any tests that don't
exercise the upload path) never need it imported.
"""

import asyncio
import hashlib
import logging
import uuid

logger = logging.getLogger(__name__)

CACHE_CONTROL: str = "public, max-age=31536000"

# Canonical extension per MIME type for the S3 object key.
_CONTENT_TYPE_TO_EXT: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/svg+xml": ".svg",
    "image/bmp": ".bmp",
    "image/tiff": ".tiff",
    "image/avif": ".avif",
    "image/heic": ".heic",
}


class UploadsS3Service:
    """Uploads image bytes to S3 and returns the CloudFront CDN URL."""

    def __init__(
        self,
        assets_bucket: str,
        aws_region: str,
        assets_cdn_base_url: str,
    ) -> None:
        self._bucket = assets_bucket
        self._region = aws_region
        self._cdn_base = assets_cdn_base_url.rstrip("/")

    # ------------------------------------------------------------------
    # Public async API
    # ------------------------------------------------------------------

    async def upload_image(
        self,
        data: bytes,
        content_type: str,
        category: str,
    ) -> str:
        """Upload image bytes; return the CDN URL with content-hash cache-bust.

        Args:
            data: Raw image bytes.
            content_type: MIME type (e.g. ``image/jpeg``).
            category: S3 key prefix — ``reward``, ``member``, or ``class``.

        Returns:
            Absolute CDN URL: ``{cdn_base}/{category}/{uuid}<ext>?v=<hash>``.
        """
        ext = _CONTENT_TYPE_TO_EXT.get(content_type, ".bin")
        content_hash = hashlib.sha256(data).hexdigest()[:16]
        key = f"{category}/{uuid.uuid4()}{ext}"

        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._put_object, data, key, content_type)

        cdn_url = f"{self._cdn_base}/{key}?v={content_hash}"
        logger.info("uploaded image: key=%s cdn_url=%s", key, cdn_url)
        return cdn_url

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _put_object(self, data: bytes, key: str, content_type: str) -> None:
        """Blocking S3 put_object — run inside a thread executor."""
        import boto3  # noqa: PLC0415 — lazy import; only the upload path needs it

        s3 = boto3.Session(region_name=self._region).client("s3")
        s3.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            CacheControl=CACHE_CONTROL,
        )
