"""Upload curated PRESET pool images to S3 under STABLE keys.

Unlike the live ``POST /api/v1/uploads/image`` endpoint (which mints a random
``{category}/{uuid}<ext>`` key + a ``?v=<hash>`` cache-buster), preset assets
need fixed, predictable keys so the URLs the seed / defaults hard-code always
resolve — e.g. ``https://cdn.combatden.net/membership/presets/activity-01.jpg``.
This one-off script puts a manifest of curated sources at those exact keys.

Run from the FastApiBackend/ root (mirrors scripts/generate_token.py):

    .venv/bin/python -m scripts.upload_preset_assets --manifest presets.json
    .venv/bin/python -m scripts.upload_preset_assets --manifest presets.json --dry-run

The manifest is a JSON object mapping each STABLE S3 key to its source — an
``http(s)://`` URL (downloaded) or a local file path (read). Example:

    {
        "membership/presets/activity-01.jpg": "https://example.com/a1.jpg",
        "member/presets/portrait-01.jpg": "./curated/portrait-01.jpg",
        "rank/presets/white.png": "./curated/white-belt.png",
        "rank/presets/medallion-01.png": "https://example.com/medallion-01.png"
    }

Objects are written into the ``assets_bucket`` (``combatden-assets``) at the
region + credentials from the standard boto3 env chain (same as the runtime
uploads service). ``--dry-run`` resolves + fetches nothing to S3: it only
reports what each key would receive, and needs no AWS credentials.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import sys
from pathlib import Path

import httpx

sys.path.append(".")
from src.core.config import settings  # noqa: E402

# Long cache: preset keys are stable and their bytes are curated once. A
# corrected preset is a rare, deliberate re-upload.
CACHE_CONTROL = "public, max-age=31536000"
DOWNLOAD_TIMEOUT_SECONDS = 30.0

# Explicit content-type per extension; mimetypes is the fallback.
_EXT_TO_CONTENT_TYPE: dict[str, str] = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".avif": "image/avif",
}


def _content_type_for_key(key: str) -> str:
    """Resolve the S3 ContentType from a key's extension."""
    ext = Path(key).suffix.lower()
    if ext in _EXT_TO_CONTENT_TYPE:
        return _EXT_TO_CONTENT_TYPE[ext]
    guessed, _ = mimetypes.guess_type(key)
    if guessed is None:
        raise ValueError(f"Cannot determine content-type for key {key!r}")
    return guessed


def _load_manifest(path: Path) -> dict[str, str]:
    """Load and validate the key -> source manifest."""
    raw = json.loads(path.read_text())
    if not isinstance(raw, dict) or not raw:
        raise ValueError("Manifest must be a non-empty JSON object of key -> source")
    for key, source in raw.items():
        if not isinstance(key, str) or not isinstance(source, str):
            raise ValueError(f"Manifest entries must be str -> str; got {key!r} -> {source!r}")
    return raw


def _read_source(source: str) -> bytes:
    """Fetch bytes for a source: an http(s) URL is downloaded, else a local file."""
    if source.startswith(("http://", "https://")):
        resp = httpx.get(source, timeout=DOWNLOAD_TIMEOUT_SECONDS, follow_redirects=True)
        resp.raise_for_status()
        return resp.content
    return Path(source).read_bytes()


def _upload(manifest: dict[str, str], *, dry_run: bool) -> None:
    """Put each manifest entry at its stable key (or report it under --dry-run)."""
    s3 = None
    if not dry_run:
        import boto3  # noqa: PLC0415 — only the real upload path needs boto3

        s3 = boto3.Session(region_name=settings.aws_region).client("s3")

    for key, source in manifest.items():
        content_type = _content_type_for_key(key)
        data = _read_source(source)
        cdn_url = f"{settings.assets_cdn_base_url.rstrip('/')}/{key}"

        if dry_run:
            print(
                f"[dry-run] would PUT {len(data):>8} bytes  "
                f"{content_type:<16} s3://{settings.assets_bucket}/{key}  "
                f"(from {source}) -> {cdn_url}"
            )
            continue

        s3.put_object(
            Bucket=settings.assets_bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            CacheControl=CACHE_CONTROL,
        )
        print(f"uploaded {len(data):>8} bytes -> {cdn_url}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upload curated preset images to S3 under stable keys.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="JSON file mapping each stable S3 key to a source URL or local path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be uploaded without writing to S3.",
    )
    args = parser.parse_args()

    manifest = _load_manifest(args.manifest)
    _upload(manifest, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
