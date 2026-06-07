# NOTE: byte-identical twin across this app's deploy/ and deploy-themes/ trees
# (only config.py differs per target). Apply any fix to every copy.
import sys
import time
from pathlib import Path

import boto3
from config import BUCKET, DOMAIN, REGION, SITE_DIR, content_type_for, load_state


def cache_control_for(rel: Path) -> str:
    name = rel.name.lower()
    # Never cache the entrypoint or the service worker, so a redeploy is picked
    # up immediately instead of being pinned by the browser/CDN. Everything else
    # (canvaskit wasm, main.dart.js, fonts, bundled images) is content the SW
    # versions, so a day-long cache is safe.
    if name in ("index.html", "flutter_service_worker.js"):
        return "no-cache, must-revalidate"
    return "public, max-age=86400"


def iter_site_files():
    for path in SITE_DIR.rglob("*"):
        if path.is_file():
            yield path, path.relative_to(SITE_DIR)


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
    if not SITE_DIR.exists():
        raise SystemExit(
            f"{SITE_DIR} missing. Build first: make build-web (in CRM/)."
        )

    session = boto3.Session(region_name=REGION)
    s3 = session.client("s3")
    cloudfront = session.client("cloudfront")

    n = upload_all(s3)
    print(f"[s3] {n} files uploaded")
    invalidate(cloudfront, dist_id)

    dist_domain = state.get("distribution_domain", "<unknown>")
    print()
    print(f"Done. App: https://{DOMAIN}  (CloudFront: {dist_domain})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
