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
# Age band a seeded ADULT member's date_of_birth is drawn from (every member
# who is not a linked child — see LINKED_CHILD_* below). The column is
# nullable (the kiosk signup captures it as an optional detail), but a seeded
# roster with it blank leaves "Date of birth" empty on every CRM member page —
# a surface that gets demoed — so the seed always fills it. Spread wide enough
# that a combat-sports roster looks like one rather than a single cohort. Not a
# validation rule: the backend imposes no bounds on date_of_birth, these only
# shape the generated data.
MEMBER_MIN_AGE_YEARS = 18
MEMBER_MAX_AGE_YEARS = 65
# Age band a seeded LINKED CHILD's date_of_birth is drawn from. A parent-paid
# child is a minor, and the family/payer surfaces are exactly where an age gets
# read, so a child must never carry an adult date of birth. The ceiling sits one
# year under MEMBER_MIN_AGE_YEARS so the two bands never overlap; the floor is
# the youngest age the seeded class roster actually teaches (the "Kids Martial
# Arts" template in generators/classes.py is ages 6-12).
LINKED_CHILD_MIN_AGE_YEARS = 6
LINKED_CHILD_MAX_AGE_YEARS = 17
# Linked-account families (mirrors the original CRM seed). ~LINKED_FAMILY_FRACTION
# of each gym's members are partitioned into families: a paying parent (root)
# plus 1-MAX_LINKED_CHILDREN_PER_PARENT children linked under it. Every child
# carries their own recurring membership; ~CHILD_SELF_PAY_FRACTION of children
# SELF-PAY it (their own card + own subscription, billed to them), the rest are
# paid by the parent. Set the fraction to 0 to skip linked families entirely.
# (Distinct from AUTH_MEMBERS_PER_GYM — the original seed's LINKED_MEMBERS_PER_GYM
# was actually the auth-login count.)
LINKED_FAMILY_FRACTION = 0.5
MAX_LINKED_CHILDREN_PER_PARENT = 5
# Of the linked children, the fraction who pay for their OWN membership
# (paid_by_member_id = themselves) on their own card, rather than the parent
# paying. The link stays — it is the authorization layer, not the billing key.
CHILD_SELF_PAY_FRACTION = 0.5
PLANS_PER_GYM = 7
# Regular discount presets created per gym (the catalog members can be given).
# Must be <= len(DISCOUNT_NAMES) in api_creation/discounts.py.
DISCOUNTS_PER_GYM = 10
# At membership creation each live membership is given a random number of
# distinct discounts from the gym's catalog, uniformly in [0, this] inclusive.
DISCOUNTS_PER_MEMBERSHIP_MAX = 3
# Probability that a live membership also receives one inline custom discount
# (a one-shot DiscountValue minted at start, applied before the first charge).
# Keep this modest so they're visible but not dominant.
CUSTOM_DISCOUNT_PROBABILITY = 0.15
OVERDUE_MEMBERS_PER_GYM = 2
REWARDS_PER_GYM = 4
# Deterministic staff (beyond the owner) so every employee_type/account-state
# combo exists as a real, addressable seeded row for backend role-matrix
# tests: admin + front_desk + trainer, each with a verified auth login
# (adminN@test.com / frontdeskN@test.com / trainerN@test.com), plus one
# account-less "pending" trainer (legacy instructor data, no login). See
# generators/employees.generate_accounted / generate_pending_trainer and
# bootstrap/gyms.create_all.
EXTRA_EMPLOYEES_PER_GYM = 4
CLASSES_PER_GYM = 7
# Most attendance rows one member can be given across all of their gym's
# already-occurred class occurrences. This is the knob that decides how much
# training history a seeded member has, and with it what they can afford:
# points are EARNED per class attended (see generators/classes.
# award_attendance_points), and the preset reward ladder is priced in classes —
# 1000 / 1500 / 2000 / 2500 points at the platform's 50 points per class is
# 20 / 30 / 40 / 50 classes. At 40, a member averages ~20 classes, about 1.2 a
# week across the 60-200 days of class history the seed lays down, which puts
# the lower rungs of the ladder in reach for a good share of the roster and the
# top rung in reach for the most active members. Raise it for a busier reward
# queue and denser attendance; lower it for a thinner roster.
MAX_CLASSES_ATTENDED_PER_MEMBER = 40
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
