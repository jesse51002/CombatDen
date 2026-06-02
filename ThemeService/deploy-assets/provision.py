"""Step 1: ensure the bucket exists (private) + request the ACM cert.

    cd deploy-assets && poetry run python provision.py

Idempotent — the bucket may already exist (the backfill creates it). Prints the
DNS validation record to add at Squarespace; once added + propagated, run
`finalize.py`.
"""

import sys
import time

import boto3
from botocore.exceptions import ClientError

from config import BUCKET, DOMAIN, PROJECT_TAG, REGION, save_state, squarespace_host


def ensure_bucket(s3) -> None:
    try:
        s3.head_bucket(Bucket=BUCKET)
        print(f"[s3] bucket already exists: {BUCKET}")
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code not in ("404", "NoSuchBucket", "NotFound"):
            raise
        kwargs = {"Bucket": BUCKET}
        if REGION != "us-east-1":
            kwargs["CreateBucketConfiguration"] = {"LocationConstraint": REGION}
        s3.create_bucket(**kwargs)
        print(f"[s3] created bucket: {BUCKET}")

    # Private: only CloudFront (via OAC) reads it; never public.
    s3.put_public_access_block(
        Bucket=BUCKET,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls": True,
            "IgnorePublicAcls": True,
            "BlockPublicPolicy": True,
            "RestrictPublicBuckets": True,
        },
    )
    s3.put_bucket_tagging(
        Bucket=BUCKET,
        Tagging={"TagSet": [{"Key": "project", "Value": PROJECT_TAG}]},
    )


def find_existing_cert(acm) -> str | None:
    paginator = acm.get_paginator("list_certificates")
    for page in paginator.paginate(
        CertificateStatuses=["PENDING_VALIDATION", "ISSUED"]
    ):
        for c in page["CertificateSummaryList"]:
            if c["DomainName"] == DOMAIN:
                return c["CertificateArn"]
    return None


def ensure_certificate(acm) -> str:
    arn = find_existing_cert(acm)
    if arn:
        print(f"[acm] reusing cert: {arn}")
        return arn
    resp = acm.request_certificate(
        DomainName=DOMAIN,
        ValidationMethod="DNS",
        Tags=[{"Key": "project", "Value": PROJECT_TAG}],
    )
    arn = resp["CertificateArn"]
    print(f"[acm] requested cert: {arn}")
    return arn


def print_validation_record(acm, cert_arn: str) -> None:
    # ACM populates DomainValidationOptions asynchronously; poll briefly.
    for _ in range(20):
        desc = acm.describe_certificate(CertificateArn=cert_arn)["Certificate"]
        options = desc.get("DomainValidationOptions", [])
        if options and options[0].get("ResourceRecord"):
            rr = options[0]["ResourceRecord"]
            print()
            print("=" * 70)
            print("ADD THIS CNAME AT SQUARESPACE DNS (cert validation):")
            print(f"  Host:   {squarespace_host(rr['Name'])}")
            print(f"  Type:   {rr['Type']}")
            print(f"  Value:  {rr['Value']}")
            print("=" * 70)
            print("  (Host is base-domain-relative — Squarespace appends")
            print("   combatden.net itself; do NOT add it. Value keeps its dot.)")
            print()
            print("Once added, wait ~5 min then run: make assets-finalize")
            return
        time.sleep(3)
    print("[acm] validation record not ready yet; re-run provision in a minute.")


def main() -> int:
    session = boto3.Session(region_name=REGION)
    s3 = session.client("s3")
    acm = session.client("acm", region_name="us-east-1")

    ensure_bucket(s3)
    cert_arn = ensure_certificate(acm)
    save_state(bucket=BUCKET, cert_arn=cert_arn)
    print_validation_record(acm, cert_arn)
    return 0


if __name__ == "__main__":
    sys.exit(main())
