"""Create a persistent Stripe Custom Connect account for integration tests.

Run this once, then paste the account ID into tests/conftest.py.

Usage:
    poetry run python tests/scripts/create_test_account.py

Production uses Express accounts — Custom is used here only so we can
programmatically fill all onboarding requirements and enable charges.
All individual/bank values are Stripe test-mode tokens.
https://docs.stripe.com/connect/testing
"""

import asyncio
import time

import stripe

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings


async def main() -> None:
    client = stripe.StripeClient(settings.stripe_secret_key)

    print("Creating Stripe Custom Connect account...")
    account = await client.v1.accounts.create_async(
        params={
            "type": "custom",
            "country": "US",
            "capabilities": {
                "card_payments": {"requested": True},
                "transfers": {"requested": True},
            },
            "business_type": "individual",
            "business_profile": {
                "mcc": "7941",
                "url": "https://www.testgym.com",
            },
            "individual": {
                "first_name": "Test",
                "last_name": "Gym",
                "dob": {"day": 1, "month": 1, "year": 1990},
                "address": {
                    "line1": "address_full_match",
                    "city": "San Francisco",
                    "state": "CA",
                    "postal_code": "94103",
                },
                "email": "test@example.com",
                "phone": "+18005551234",
                "ssn_last_4": "0000",
                "id_number": "000000000",
                "verification": {
                    "document": {"front": "file_identity_document_success"},
                },
            },
            "external_account": {
                "object": "bank_account",
                "country": "US",
                "currency": "usd",
                "routing_number": "110000000",
                "account_number": "000123456789",
            },
            "tos_acceptance": {"date": int(time.time()), "ip": "127.0.0.1"},
        },
    )
    print(f"Account created: {account.id}")

    print("Waiting for Stripe to verify (up to 90s)...")
    for i in range(30):
        await asyncio.sleep(3)
        acct = await client.v1.accounts.retrieve_async(account.id)
        if acct.charges_enabled:
            print(f"Charges enabled after {(i + 1) * 3}s")
            break
    else:
        print("TIMEOUT — account may still be verifying.")
        print(f"Check: https://dashboard.stripe.com/test/connect/accounts/{account.id}")

    print()
    print("Paste this into tests/conftest.py:")
    print(f'STRIPE_TEST_ACCOUNT_ID = "{account.id}"')


if __name__ == "__main__":
    asyncio.run(main())
