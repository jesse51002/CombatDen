"""Mirror all generated theme assets to S3 — the backfill / repair command.

    poetry run python -m scripts.sync_assets.run
    poetry run python -m scripts.sync_assets.run --apps-root apps

Walks every run's ``final_images/*.png`` + ``icons/*.svg`` under the apps root
and uploads each to S3 under the CDN key scheme (``themes/<app>/<run>/...``),
skipping objects already present with identical bytes. The on-generation Writer
hook keeps new runs current; this is the one-shot backfill and the repair tool.

No CloudFront invalidation is needed: the API serves content-addressed
``?v=<hash>`` URLs and CloudFront keys on ``v``, so re-uploaded bytes surface
under a new ``?v=`` automatically. Requires boto3 + AWS creds + ``ASSETS_BUCKET``.
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from src.core.asset_urls import ICON_SUFFIX, IMAGE_SUFFIX, icon_key, image_key
from src.core.asset_uploader import s3_client, upload_file
from src.core.config import settings
from src.core.run_context import FINAL_IMAGES_DIRNAME, ICONS_DIRNAME

logger = logging.getLogger(__name__)

_DEFAULT_APPS_ROOT = Path(__file__).resolve().parents[2] / "apps"
_WORKERS = 24


def _local_md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def _needs_upload(s3: Any, key: str, path: Path) -> bool:
    """True unless an object with identical bytes already exists at ``key``.
    ETag == MD5 for single-part uploads, and these files are far under the
    multipart threshold, so the comparison is reliable."""
    try:
        head = s3.head_object(Bucket=settings.assets_bucket, Key=key)
    except Exception:  # noqa: BLE001 - missing (or transient) -> (re)upload
        return True
    return head.get("ETag", "").strip('"') != _local_md5(path)


def _entries(apps_root: Path) -> list[tuple[Path, str]]:
    """Every deliverable asset under ``apps_root`` as ``(local_path, s3_key)``.
    Only ``final_images/`` + ``icons/`` (the raw ``images/`` intermediates are
    never served, so never uploaded)."""
    out: list[tuple[Path, str]] = []
    for app_dir in sorted(p for p in apps_root.iterdir() if p.is_dir()):
        app_id = app_dir.name
        for run_dir in sorted(p for p in app_dir.iterdir() if p.is_dir()):
            run_id = run_dir.name
            for png in sorted(
                (run_dir / FINAL_IMAGES_DIRNAME).glob(f"*{IMAGE_SUFFIX}")
            ):
                out.append((png, image_key(app_id, run_id, png.stem)))
            for svg in sorted((run_dir / ICONS_DIRNAME).glob(f"*{ICON_SUFFIX}")):
                out.append((svg, icon_key(app_id, run_id, svg.stem)))
    return out


def run(apps_root: Path) -> int:
    """Mirror missing/changed assets; returns the number uploaded."""
    if not settings.assets_bucket:
        raise SystemExit("ASSETS_BUCKET is not set")
    if not apps_root.is_dir():
        raise SystemExit(f"no apps root at {apps_root}")
    s3 = s3_client()
    entries = _entries(apps_root)
    logger.info("found %d deliverable asset(s) under %s", len(entries), apps_root)

    def _one(entry: tuple[Path, str]) -> int:
        path, key = entry
        if _needs_upload(s3, key, path):
            upload_file(s3, path, key)
            logger.info("uploaded %s", key)
            return 1
        return 0

    with ThreadPoolExecutor(max_workers=_WORKERS) as pool:
        uploaded = sum(pool.map(_one, entries))
    logger.info(
        "sync complete: %d uploaded, %d unchanged", uploaded, len(entries) - uploaded
    )
    return uploaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    run(args.apps_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
