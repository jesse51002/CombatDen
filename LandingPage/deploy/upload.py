import sys
import time
from pathlib import Path

import boto3

from config import BUCKET, REGION, SITE_DIR, content_type_for, load_state

INCLUDE_GLOBS = [
    "index.html",
    "hifi/**/*",
    "assets/**/*",
]


def iter_site_files():
    seen = set()
    for pattern in INCLUDE_GLOBS:
        for path in SITE_DIR.glob(pattern):
            if not path.is_file():
                continue
            rel = path.relative_to(SITE_DIR)
            if rel in seen:
                continue
            seen.add(rel)
            yield path, rel


def cache_control_for(rel: Path) -> str:
    return "no-cache"


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
        raise SystemExit("No distribution_id in state. Run `make deploy-finalize` first.")

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
