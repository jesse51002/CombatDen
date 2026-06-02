import re
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path

import boto3
from config import BUCKET, REGION, SITE_DIR, content_type_for, load_state

INCLUDE_GLOBS = [
    "*.html",
    "robots.txt",
    "sitemap.xml",
    "llms.txt",
    "hifi/**/*",
    "assets/**/*",
]

# Internal-only directories that must never be uploaded to the public bucket.
# Today nothing under these prefixes matches INCLUDE_GLOBS — but keep this as
# a defensive guard in case a future glob accidentally catches them.
#   onepager/  — sales leave-behind + design scratch (not a public page)
EXCLUDE_PREFIXES = ("onepager/",)


def iter_site_files():
    seen = set()
    for pattern in INCLUDE_GLOBS:
        for path in SITE_DIR.glob(pattern):
            if not path.is_file():
                continue
            rel = path.relative_to(SITE_DIR)
            rel_str = str(rel).replace("\\", "/")
            if any(rel_str.startswith(p) for p in EXCLUDE_PREFIXES):
                continue
            if rel in seen:
                continue
            seen.add(rel)
            yield path, rel


def cache_control_for(rel: Path) -> str:
    name = rel.name.lower()
    if name.endswith(".html"):
        return "no-cache, must-revalidate"
    if name in ("sitemap.xml", "robots.txt", "llms.txt"):
        return "public, max-age=300"
    if rel.parts and rel.parts[0] == "assets":
        return "public, max-age=86400"
    return "no-cache"


def refresh_sitemap_lastmod() -> None:
    """Rewrite <lastmod> in sitemap.xml to the mtime of the matching HTML file.

    Loose mapping by URL suffix:
      */              -> index.html
      */pricing.html  -> pricing.html
    """
    sitemap = SITE_DIR / "sitemap.xml"
    if not sitemap.exists():
        return
    text = sitemap.read_text()

    def mtime_date(filename: str) -> str:
        p = SITE_DIR / filename
        if not p.exists():
            return date.today().isoformat()
        ts = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
        return ts.date().isoformat()

    def replace_lastmod(loc_suffix: str, html_file: str) -> None:
        nonlocal text
        # Match a <url> block whose <loc> ends with loc_suffix, then replace the
        # first <lastmod> inside that block.
        pattern = re.compile(
            r"(<url>\s*<loc>[^<]*"
            + re.escape(loc_suffix)
            + r"</loc>\s*<lastmod>)[^<]*(</lastmod>)",
            re.DOTALL,
        )
        text = pattern.sub(r"\g<1>" + mtime_date(html_file) + r"\g<2>", text)

    replace_lastmod(".combatden.net/", "index.html")
    replace_lastmod("/pricing.html", "pricing.html")
    sitemap.write_text(text)
    print("[sitemap] refreshed lastmod from local file mtimes")


def upload_all(s3) -> int:
    count = 0
    for abs_path, rel in iter_site_files():
        key = str(rel).replace("\\", "/")
        s3.upload_file(
            str(abs_path),
            BUCKET,
            key,
            ExtraArgs={
                "ContentType": content_type_for(abs_path),
                "CacheControl": cache_control_for(rel),
            },
        )
        print(f"[s3] uploaded {key}")
        count += 1
    return count


def invalidate(cloudfront, dist_id: str) -> None:
    resp = cloudfront.create_invalidation(
        DistributionId=dist_id,
        InvalidationBatch={
            "Paths": {"Quantity": 1, "Items": ["/*"]},
            "CallerReference": f"upload-{int(time.time())}",
        },
    )
    print(f"[cloudfront] invalidation created: {resp['Invalidation']['Id']}")


def main() -> int:
    state = load_state()
    dist_id = state.get("distribution_id")
    if not dist_id:
        raise SystemExit(
            "No distribution_id in state. Run `make deploy-finalize` first."
        )

    refresh_sitemap_lastmod()

    session = boto3.Session(region_name=REGION)
    s3 = session.client("s3")
    cloudfront = session.client("cloudfront")

    n = upload_all(s3)
    print(f"[s3] {n} files uploaded")
    invalidate(cloudfront, dist_id)

    dist_domain = state.get("distribution_domain", "<unknown>")
    print()
    print(f"Done. Site: https://www.combatden.net  (CloudFront: {dist_domain})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
