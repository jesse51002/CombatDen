DEFAULT_PASSWORD = "abcd1234"
# Seed for Python's `random` and Faker, set once at the top of seed().
# Keeping this constant means every run picks the same names, emails, plan
# selections, and journey choices — which in turn lets the idempotency layer
# look up records by stable keys (email, plan_name, discount_name).
SEED = 42
# Shared Stripe Connect test account — same one used by the backend's
# integration tests (see FastApiBackend/tests/conftest.py). All seeded gyms
# point at it so the backend can create real test-mode products/prices/
# subscriptions on their behalf.
STRIPE_TEST_ACCOUNT_ID = "acct_1TLWP5LArmKROnJ8"
NUM_GYMS = 3
MEMBERS_PER_GYM = 100
LINKED_MEMBERS_PER_GYM = 5
PLANS_PER_GYM = 10
DISCOUNTS_PER_GYM = 2
REWARDS_PER_GYM = 4
EXTRA_EMPLOYEES_PER_GYM = 2
CLASSES_PER_GYM = 7
ACTIVITIES_PER_MEMBER = 5
HISTORY_DAYS = 30
