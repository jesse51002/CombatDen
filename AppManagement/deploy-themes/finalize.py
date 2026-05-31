import json
import sys
import time

import boto3
from botocore.exceptions import ClientError

from config import BUCKET, DOMAIN, PROJECT_TAG, REGION, load_state, save_state

CACHING_OPTIMIZED_POLICY_ID = "658327ea-f89d-4fab-a63d-7e88639e58f6"


def wait_for_cert_issued(acm, cert_arn: str) -> None:
    for i in range(40):
        desc = acm.describe_certificate(CertificateArn=cert_arn)["Certificate"]
        status = desc["Status"]
        if status == "ISSUED":
            print(f"[acm] cert ISSUED")
            return
        if status != "PENDING_VALIDATION":
            raise SystemExit(f"[acm] cert in unexpected status {status}")
        print(f"[acm] waiting for validation ({i + 1}/40) ...")
        time.sleep(15)
    raise SystemExit(
        "[acm] cert still PENDING_VALIDATION. Make sure the CNAME record is "
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


def find_existing_distribution(cloudfront) -> str | None:
    for page in cloudfront.get_paginator("list_distributions").paginate():
        items = page.get("DistributionList", {}).get("Items", []) or []
        for d in items:
            aliases = d.get("Aliases", {}).get("Items", []) or []
            if DOMAIN in aliases:
                return d["Id"]
    return None


def create_distribution(cloudfront, oac_id: str, cert_arn: str) -> dict:
    origin_id = "s3-origin"
    s3_domain = f"{BUCKET}.s3.{REGION}.amazonaws.com"
    config = {
        "CallerReference": f"{PROJECT_TAG}-{int(time.time())}",
        "Aliases": {"Quantity": 1, "Items": [DOMAIN]},
        "DefaultRootObject": "index.html",
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
            "CachePolicyId": CACHING_OPTIMIZED_POLICY_ID,
        },
        # Flutter web is a single-page app: a deep link / hard refresh hits a key
        # that doesn't exist in S3, so serve index.html (200) for 403/404 and let
        # the client router resolve the route.
        "CustomErrorResponses": {
            "Quantity": 2,
            "Items": [
                {
                    "ErrorCode": 403,
                    "ResponsePagePath": "/index.html",
                    "ResponseCode": "200",
                    "ErrorCachingMinTTL": 10,
                },
                {
                    "ErrorCode": 404,
                    "ResponsePagePath": "/index.html",
                    "ResponseCode": "200",
                    "ErrorCachingMinTTL": 10,
                },
            ],
        },
        "Comment": f"CombatDen AppManagement web app ({DOMAIN})",
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
        raise SystemExit("No cert_arn in state. Run `make deploy-provision` first.")

    session = boto3.Session(region_name=REGION)
    acm = session.client("acm", region_name="us-east-1")
    cloudfront = session.client("cloudfront")
    s3 = session.client("s3")

    wait_for_cert_issued(acm, cert_arn)
    oac_id = ensure_oac(cloudfront)

    dist_id = state.get("distribution_id") or find_existing_distribution(cloudfront)
    if dist_id:
        try:
            desc = cloudfront.get_distribution(Id=dist_id)["Distribution"]
            print(f"[cloudfront] reusing distribution: {dist_id}")
        except ClientError:
            desc = None
            dist_id = None

    if not dist_id:
        desc = create_distribution(cloudfront, oac_id, cert_arn)
        dist_id = desc["Id"]
        print(f"[cloudfront] created distribution: {dist_id}")

    dist_arn = desc["ARN"]
    dist_domain = desc["DomainName"]

    apply_bucket_policy(s3, dist_arn)
    save_state(distribution_id=dist_id, distribution_arn=dist_arn, distribution_domain=dist_domain)

    host = DOMAIN.split(".")[0]
    print()
    print("=" * 70)
    print("ADD THIS CNAME AT SQUARESPACE DNS:")
    print(f"  Host:   {host}")
    print(f"  Type:   CNAME")
    print(f"  Value:  {dist_domain}")
    print("=" * 70)
    print()
    print(f"Distribution status: {desc['Status']} (takes ~5 min to fully Deploy)")
    print("Once the CNAME is added and the distribution is Deployed, run: make deploy-upload")
    return 0


if __name__ == "__main__":
    sys.exit(main())
