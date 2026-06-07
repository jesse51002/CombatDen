DEFAULT_PASSWORD = "abcd1234"
# Seed for Python's `random` and Faker, set once at the top of seed().
# Keeping this constant means every run picks the same names, emails, plan
# selections, and journey choices — which lets the idempotency layer in
# api_creation/upsert.py look up records by stable keys (email, plan_name,
# discount_name) and skip the Stripe-backed POST on re-runs.
SEED = 42
# Shared Stripe Connect test account — same one the backend's integration
# tests use. All seeded gyms point at it (gyms.stripe_account_id) so the
# backend can create real test-mode products/prices/customers/subscriptions
# on their behalf.
STRIPE_TEST_ACCOUNT_ID = "acct_1TLWP5LArmKROnJ8"
# gyms.stripe_account_id is UNIQUE (one Stripe Connect account per gym) and we
# have a single test connect account, so the seed provisions ONE gym with the
# full live-Stripe billing path. Bump this only if you add a connect account
# per extra gym.
NUM_GYMS = 1
MEMBERS_PER_GYM = 100
# Members (per gym) that get a real Supabase auth login (the rest are
# staff-managed CRM rows with no auth account).
AUTH_MEMBERS_PER_GYM = 5
# Linked-account families (mirrors the original CRM seed). ~LINKED_FAMILY_FRACTION
# of each gym's members are partitioned into families: a paying parent (root)
# plus 1-MAX_LINKED_CHILDREN_PER_PARENT children covered under it. Children carry
# no membership of their own (cardless, paid for by the parent). Set the fraction
# to 0 to skip linked families entirely. (Distinct from AUTH_MEMBERS_PER_GYM —
# the original seed's LINKED_MEMBERS_PER_GYM was actually the auth-login count.)
LINKED_FAMILY_FRACTION = 0.5
MAX_LINKED_CHILDREN_PER_PARENT = 5
PLANS_PER_GYM = 7
# Regular discount presets created per gym (the catalog members can be given).
# Must be <= len(DISCOUNT_NAMES) in api_creation/discounts.py.
DISCOUNTS_PER_GYM = 10
# At membership creation each live membership is given a random number of
# distinct discounts from the gym's catalog, uniformly in [0, this] inclusive.
DISCOUNTS_PER_MEMBERSHIP_MAX = 3
OVERDUE_MEMBERS_PER_GYM = 2
REWARDS_PER_GYM = 4
EXTRA_EMPLOYEES_PER_GYM = 2
CLASSES_PER_GYM = 7
ACTIVITIES_PER_MEMBER = 5
HISTORY_DAYS = 30

# Days per billing-cycle unit, used to space historical invoices/charges.
UNIT_DAYS = {"week": 7, "month": 30, "year": 365}

# Worker count for the seed's concurrent loops (member creation + the
# family-grouped membership/discount pipeline). Concurrency is across families
# (disjoint paying-parent lock keys); within a family ops stay sequential, so
# the per-parent lock never contends. Keep <= the backend db_pool_size (10): a
# concurrent family holds a connection across its slow Stripe sync.
SEED_WORKERS = 5
