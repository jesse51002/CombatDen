import sys

import boto3
from botocore.exceptions import ClientError

from config import BUCKET, DOMAIN, PROJECT_TAG, REGION, save_state


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
    for page in paginator.paginate(CertificateStatuses=["PENDING_VALIDATION", "ISSUED"]):
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
    import time

    for _ in range(20):
        desc = acm.describe_certificate(CertificateArn=cert_arn)["Certificate"]
        options = desc.get("DomainValidationOptions", [])
        if options and options[0].get("ResourceRecord"):
            rr = options[0]["ResourceRecord"]
            print()
            print("=" * 70)
            print("ADD THIS CNAME AT SQUARESPACE DNS:")
            print(f"  Host:   {rr['Name']}")
            print(f"  Type:   {rr['Type']}")
            print(f"  Value:  {rr['Value']}")
            print("=" * 70)
            print()
            print("Once added, wait ~5 min then run: make deploy-finalize")
            return
        time.sleep(3)
    print("[acm] validation record not yet available; re-run provision in a minute.")


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
