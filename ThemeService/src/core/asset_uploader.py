"""Move a run's generated images/icons to S3 (served via CloudFront).

``boto3`` is imported lazily so the read API and the test suite don't need it
installed — only the actual write paths (the Writer's opt-in on-generation hook
and the ``sync-assets`` mirror) pull it in. The object-key + URL scheme lives in
``asset_urls``; this module just moves bytes.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from src.core.asset_urls import ICON_SUFFIX, IMAGE_SUFFIX, icon_key, image_key
from src.core.config import settings

logger = logging.getLogger(__name__)

# Each served URL is content-addressed via ?v=<content-hash> and CloudFront keys
# on v, so the bytes behind a given URL never change — cache them hard.
CACHE_CONTROL = "public, max-age=31536000"
CONTENT_TYPE = {IMAGE_SUFFIX: "image/png", ICON_SUFFIX: "image/svg+xml"}
# Sized to comfortably cover the sync mirror's worker pool so concurrent uploads
# don't churn connections ("Connection pool is full" warnings).
_MAX_POOL_CONNECTIONS = 32


def s3_client() -> Any:
    """A boto3 S3 client. Lazy import: boto3 is only needed on the write path,
    never by the read API or tests."""
    import boto3  # noqa: PLC0415 - intentionally lazy
    from botocore.config import Config  # noqa: PLC0415 - intentionally lazy

    return boto3.Session(region_name=settings.aws_region).client(
        "s3", config=Config(max_pool_connections=_MAX_POOL_CONNECTIONS)
    )


def upload_file(s3: Any, local_path: Path, key: str) -> None:
    """Put one local asset at ``key`` with the right content-type + cache headers."""
    s3.upload_file(
        str(local_path),
        settings.assets_bucket,
        key,
        ExtraArgs={
            "ContentType": CONTENT_TYPE[local_path.suffix],
            "CacheControl": CACHE_CONTROL,
        },
    )


def upload_run_assets(
    app_id: str,
    run_id: str,
    image_slots: list[str],
    icon_slots: list[str],
    final_image_dir: Path,
    icon_dir: Path,
    *,
    s3: Any | None = None,
) -> int:
    """Upload the named image/icon slot files for one run; returns how many were
    uploaded (a slot whose local file is absent is skipped). No-op (0) when no
    bucket is configured."""
    if not settings.assets_bucket:
        logger.warning("assets_bucket unset — skipping asset upload")
        return 0
    s3 = s3 or s3_client()
    count = 0
    for slot in image_slots:
        path = final_image_dir / f"{slot}{IMAGE_SUFFIX}"
        if path.is_file():
            upload_file(s3, path, image_key(app_id, run_id, slot))
            count += 1
    for slot in icon_slots:
        path = icon_dir / f"{slot}{ICON_SUFFIX}"
        if path.is_file():
            upload_file(s3, path, icon_key(app_id, run_id, slot))
            count += 1
    logger.debug("uploaded %d asset(s) for %s/%s", count, app_id, run_id)
    return count
