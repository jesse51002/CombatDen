"""Step 2: create the CloudFront distribution (OAC + cache-key on ?v= + CORS).

    cd deploy-assets && poetry run python finalize.py

Waits for the ACM cert to validate, ensures the OAC + a custom cache policy that
keys on the ``v`` query string + a CORS response-headers policy (so Flutter web
can decode the cross-origin images), creates the distribution, and locks the
bucket policy to it. Idempotent — safe to re-run to patch a live distribution
(e.g. to attach the CORS policy that was added after the fact). Prints the final
`cdn` CNAME to add at Squarespace.
"""

import json
import sys
import time

import boto3
from botocore.exceptions import ClientError

from config import (
    BUCKET,
    DOMAIN,
    PROJECT_TAG,
    REGION,
    load_state,
    save_state,
    squarespace_host,
)


def wait_for_cert_issued(acm, cert_arn: str) -> None:
    for i in range(40):
        desc = acm.describe_certificate(CertificateArn=cert_arn)["Certificate"]
        status = desc["Status"]
        if status == "ISSUED":
            print("[acm] cert ISSUED")
            return
        if status != "PENDING_VALIDATION":
            raise SystemExit(f"[acm] cert in unexpected status {status}")
        print(f"[acm] waiting for validation ({i + 1}/40) ...")
        time.sleep(15)
    raise SystemExit(
        "[acm] cert still PENDING_VALIDATION. Make sure the validation CNAME is "
        "added at Squarespace DNS and has propagated, then re-run."
    )


def ensure_oac(cloudfront) -> str:
    name = f"{PROJECT_TAG}-oac"
    for page in cloudfront.get_paginator("list_origin_access_controls").paginate():
        for item in page.get("OriginAccessControlList", {}).get("Items", []) or []:
            if item["Name"] == name:
                print(f"[cloudfront] reusing OAC: {item['Id']}")
                return item["Id"]
    resp = cloudfront.create_origin_access_control(
        OriginAccessControlConfig={
            "Name": name,
            "Description": f"OAC for {DOMAIN}",
            "SigningProtocol": "sigv4",
            "SigningBehavior": "always",
            "OriginAccessControlOriginType": "s3",
        }
    )
    oac_id = resp["OriginAccessControl"]["Id"]
    print(f"[cloudfront] created OAC: {oac_id}")
    return oac_id


def ensure_cache_policy(cloudfront) -> str:
    """A cache policy that includes the ``v`` query string in the cache key.

    The API serves content-fingerprinted ``...png?v=<hash>`` URLs; a new hash must
    be a fresh fetch. AWS's managed CachingOptimized policy IGNORES query strings,
    which would pin stale bytes — so we key on ``v`` explicitly. Long TTLs are safe
    precisely because ``v`` changes whenever the bytes do.
    """
    name = f"{PROJECT_TAG}-v"
    existing = cloudfront.list_cache_policies(Type="custom").get("CachePolicyList", {})
    for item in existing.get("Items", []) or []:
        if item["CachePolicy"]["CachePolicyConfig"]["Name"] == name:
            pid = item["CachePolicy"]["Id"]
            print(f"[cloudfront] reusing cache policy: {pid}")
            return pid
    resp = cloudfront.create_cache_policy(
        CachePolicyConfig={
            "Name": name,
            "Comment": "Key on ?v= so regenerated assets bust cache; long TTL otherwise.",
            "DefaultTTL": 86400,
            "MaxTTL": 31536000,
            "MinTTL": 0,
            "ParametersInCacheKeyAndForwardedToOrigin": {
                "EnableAcceptEncodingGzip": True,
                "EnableAcceptEncodingBrotli": True,
                "HeadersConfig": {"HeaderBehavior": "none"},
                "CookiesConfig": {"CookieBehavior": "none"},
                "QueryStringsConfig": {
                    "QueryStringBehavior": "whitelist",
                    "QueryStrings": {"Quantity": 1, "Items": ["v"]},
                },
            },
        }
    )
    pid = resp["CachePolicy"]["Id"]
    print(f"[cloudfront] created cache policy (keys on ?v=): {pid}")
    return pid


def ensure_response_headers_policy(cloudfront) -> str:
    """A response-headers policy that adds permissive CORS (`Access-Control-Allow-
    Origin: *`) to every asset response.

    Flutter web's CanvasKit renderer fetches each image via XHR and decodes the
    bytes, which the browser BLOCKS cross-origin unless the response carries a
    CORS header. S3/CloudFront don't add one by default, so the theme browser
    (served from a different origin than `cdn.combatden.net`) shows broken-image
    placeholders even though the PNG returns 200. Adding the header at the edge
    fixes it — applied on cache hits too, so no invalidation is needed. Long TTLs
    stay safe because the cache key still keys on `?v=` (see ensure_cache_policy).
    """
    name = f"{PROJECT_TAG}-cors"
    existing = cloudfront.list_response_headers_policies(Type="custom").get(
        "ResponseHeadersPolicyList", {}
    )
    for item in existing.get("Items", []) or []:
        cfg = item["ResponseHeadersPolicy"]["ResponseHeadersPolicyConfig"]
        if cfg["Name"] == name:
            pid = item["ResponseHeadersPolicy"]["Id"]
            print(f"[cloudfront] reusing response headers policy: {pid}")
            return pid
    resp = cloudfront.create_response_headers_policy(
        ResponseHeadersPolicyConfig={
            "Name": name,
            "Comment": "Permissive CORS so Flutter web (CanvasKit) can decode cross-origin images.",
            "CorsConfig": {
                "AccessControlAllowOrigins": {"Quantity": 1, "Items": ["*"]},
                "AccessControlAllowHeaders": {"Quantity": 1, "Items": ["*"]},
                "AccessControlAllowMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                },
                "AccessControlAllowCredentials": False,
                "OriginOverride": True,
            },
        }
    )
    pid = resp["ResponseHeadersPolicy"]["Id"]
    print(f"[cloudfront] created response headers policy (CORS *): {pid}")
    return pid


def ensure_distribution_response_headers(
    cloudfront, dist_id: str, rh_policy_id: str
) -> None:
    """Attach the CORS response-headers policy to an existing distribution's
    default behavior (idempotent — no-op if already set). Needed because the
    distribution is created once, but the CORS policy was added later; re-running
    finalize patches the live distribution without recreating it."""
    cfg = cloudfront.get_distribution_config(Id=dist_id)
    etag = cfg["ETag"]
    config = cfg["DistributionConfig"]
    behavior = config["DefaultCacheBehavior"]
    if behavior.get("ResponseHeadersPolicyId") == rh_policy_id:
        print("[cloudfront] CORS response headers policy already attached")
        return
    behavior["ResponseHeadersPolicyId"] = rh_policy_id
    cloudfront.update_distribution(
        Id=dist_id, DistributionConfig=config, IfMatch=etag
    )
    print(f"[cloudfront] attached CORS policy {rh_policy_id} to {dist_id}")


def find_existing_distribution(cloudfront) -> str | None:
    for page in cloudfront.get_paginator("list_distributions").paginate():
        items = page.get("DistributionList", {}).get("Items", []) or []
        for d in items:
            aliases = d.get("Aliases", {}).get("Items", []) or []
            if DOMAIN in aliases:
                return d["Id"]
    return None


def create_distribution(
    cloudfront,
    oac_id: str,
    cert_arn: str,
    cache_policy_id: str,
    response_headers_policy_id: str,
) -> dict:
    origin_id = "s3-origin"
    s3_domain = f"{BUCKET}.s3.{REGION}.amazonaws.com"
    config = {
        "CallerReference": f"{PROJECT_TAG}-{int(time.time())}",
        "Aliases": {"Quantity": 1, "Items": [DOMAIN]},
        # No DefaultRootObject / no SPA error-rewrite: this is an asset CDN, a
        # missing key should 404 honestly, not return an HTML page.
        "Origins": {
            "Quantity": 1,
            "Items": [
                {
                    "Id": origin_id,
                    "DomainName": s3_domain,
                    "OriginAccessControlId": oac_id,
                    "S3OriginConfig": {"OriginAccessIdentity": ""},
                    "CustomHeaders": {"Quantity": 0},
                    "ConnectionAttempts": 3,
                    "ConnectionTimeout": 10,
                    "OriginShield": {"Enabled": False},
                }
            ],
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": origin_id,
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"],
                "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
            },
            "Compress": True,
            "CachePolicyId": cache_policy_id,
            "ResponseHeadersPolicyId": response_headers_policy_id,
        },
        "Comment": f"CombatDen theme assets CDN ({DOMAIN})",
        "Enabled": True,
        "PriceClass": "PriceClass_100",
        "ViewerCertificate": {
            "ACMCertificateArn": cert_arn,
            "SSLSupportMethod": "sni-only",
            "MinimumProtocolVersion": "TLSv1.2_2021",
            "CertificateSource": "acm",
        },
        "HttpVersion": "http2",
        "IsIPV6Enabled": True,
    }
    resp = cloudfront.create_distribution_with_tags(
        DistributionConfigWithTags={
            "DistributionConfig": config,
            "Tags": {"Items": [{"Key": "project", "Value": PROJECT_TAG}]},
        }
    )
    return resp["Distribution"]


def apply_bucket_policy(s3, distribution_arn: str) -> None:
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowCloudFrontServicePrincipal",
                "Effect": "Allow",
                "Principal": {"Service": "cloudfront.amazonaws.com"},
                "Action": "s3:GetObject",
                "Resource": f"arn:aws:s3:::{BUCKET}/*",
                "Condition": {"StringEquals": {"AWS:SourceArn": distribution_arn}},
            }
        ],
    }
    s3.put_bucket_policy(Bucket=BUCKET, Policy=json.dumps(policy))
    print(f"[s3] bucket policy applied for distribution {distribution_arn}")


def main() -> int:
    state = load_state()
    cert_arn = state.get("cert_arn")
    if not cert_arn:
        raise SystemExit("No cert_arn in state. Run `make assets-provision` first.")

    session = boto3.Session(region_name=REGION)
    acm = session.client("acm", region_name="us-east-1")
    cloudfront = session.client("cloudfront")
    s3 = session.client("s3")

    wait_for_cert_issued(acm, cert_arn)
    oac_id = ensure_oac(cloudfront)
    cache_policy_id = ensure_cache_policy(cloudfront)
    rh_policy_id = ensure_response_headers_policy(cloudfront)

    dist_id = state.get("distribution_id") or find_existing_distribution(cloudfront)
    desc = None
    if dist_id:
        try:
            desc = cloudfront.get_distribution(Id=dist_id)["Distribution"]
            print(f"[cloudfront] reusing distribution: {dist_id}")
        except ClientError:
            dist_id = None

    if not dist_id:
        desc = create_distribution(
            cloudfront, oac_id, cert_arn, cache_policy_id, rh_policy_id
        )
        dist_id = desc["Id"]
        print(f"[cloudfront] created distribution: {dist_id}")

    # Attach the CORS policy to the (possibly pre-existing) distribution. The
    # distribution was created before this policy existed, so re-running finalize
    # patches it in place — this is what fixes broken cross-origin images on a
    # live CDN without recreating it.
    ensure_distribution_response_headers(cloudfront, dist_id, rh_policy_id)

    dist_arn = desc["ARN"]
    dist_domain = desc["DomainName"]

    apply_bucket_policy(s3, dist_arn)
    save_state(
        distribution_id=dist_id,
        distribution_arn=dist_arn,
        distribution_domain=dist_domain,
        cache_policy_id=cache_policy_id,
        response_headers_policy_id=rh_policy_id,
    )

    print()
    print("=" * 70)
    print("ADD THIS CNAME AT SQUARESPACE DNS:")
    print(f"  Host:   {squarespace_host(DOMAIN)}")
    print("  Type:   CNAME")
    print(f"  Value:  {dist_domain}")
    print("=" * 70)
    print("  (Host is base-domain-relative — Squarespace appends combatden.net")
    print("   itself; do NOT add it.)")
    print()
    print(f"Distribution status: {desc['Status']} (~5 min to fully Deploy).")
    print(
        "Once the CNAME is added + Deployed, verify (expect 200 AND an\n"
        "access-control-allow-origin header — the latter is what lets Flutter\n"
        "web render the image):\n"
        f"  curl -I -H 'Origin: https://themes.combatden.net' "
        f"https://{DOMAIN}/themes/combatden/ZenBJJ/images/celebration_image.png"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
