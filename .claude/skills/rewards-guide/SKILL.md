---
name: rewards-guide
description: >-
  The single source of truth for the CombatDen REWARDS system — the
  gym-defined reward catalog (`gym_rewards`) and the member redemption
  lifecycle (`member_reward_redemptions`), a debit-on-request model where a
  member's `points_balance` is decremented the moment they request a
  redemption, not when staff approve it. Load this whenever you touch a
  reward or a redemption: catalog CRUD, the member-initiated redeem flow, the
  staff approval queue (approve / reject), staff redeem-for-member
  (including the `override` comp path), `points_balance` adjustments, or the
  reward-image upload path. Trigger on "reward", "redemption", "points
  balance", "approve redemption", "reject redemption", "redeem-for-member",
  "override" / "comp", "price_label", "requested_at", "resolved_at",
  "gym_rewards", "member_reward_redemptions", "points adjust", "reward image
  upload", or any change to the rewards data model, services, SQL, or
  endpoints.
---

# Rewards — catalog + debit-on-request redemption lifecycle

This is the deep domain knowledge for CombatDen's rewards system. It is the
**source of truth** for how the system behaves; `FastApiBackend/CLAUDE.md`
holds only the "how to work here" rules. When the rewards model changes,
**update this skill in the same change** (it is a living document — see the
bottom).

The domain lives entirely in `FastApiBackend/src/rewards/` — one router, two
services (`RewardsService` for the catalog, `RewardsRedemptionService` for
the lifecycle), and one `sql/` folder. Points storage and the checkin award
seam live in the `members` and `checkin` domains respectively — this guide
names those seams but defers their internals.

---

## 1. The catalog — `gym_rewards`

`Database/supabase/schemas/gym_rewards.sql`. A gym's redeemable reward menu.

| column | meaning |
| --- | --- |
| `reward_id` | PK |
| `gym_id` | scope (composite `UNIQUE (reward_id, gym_id)`) |
| `title` | `CHECK (title <> '')` |
| `price_label` | the member-app value badge (e.g. `"Free"`, `"30% off"`) — **NOT NULL**, purely cosmetic, never used in the points math; **required on create** (`RewardCreateRequest.price_label` has `min_length=1` — the client must supply it, no backend fallback on a live create call) |
| `image_url` | **NOT NULL** — optional on the create *request* (`RewardCreateRequest.image_url` stays `str \| None`); when omitted, `RewardsService.create_reward` fills the platform default (`settings.default_reward_image_url`, a "prize box" hand-off photo) before the INSERT, mirroring `gym_classes.image_url` / `ClassesCrudService` exactly. Set via the uploads domain (§6) when the creator does upload one. |
| `point_cost` | `CHECK (point_cost > 0)` — always positive; a reward can never cost 0 or negative points |
| `is_active` | soft-delete flag; default `true` |
| `created_at` | |

Both columns are NOT NULL as of `20260703010000_gym_rewards_image_and_label_required.sql`
(mirroring `20260702010000_gym_classes_image_url_not_null.sql` for
`gym_classes.image_url`) — every reward has an image and a value badge. On
**update**, both can be changed but never cleared: `RewardUpdateData` runs a
`field_validator` on `image_url` / `price_label` that raises when the client
sends an explicit `null` (422) — patch semantics stay "absent field = column
untouched"; there is no silent reset-to-default on update (unlike the classes
identity-update path, which resets a nulled `image_url` back to its platform
default instead of rejecting it — rewards deliberately diverges here per a
founder decision that the two required fields must never silently change
value out from under an explicit `null`).

**CRUD is plain and coupon-free** (`RewardsService`, `src/rewards/service/rewards_service.py`):
create / update / soft-delete (`deactivate_reward` = `update_reward(is_active=False)`)
/ get / list. `list_rewards` orders by `point_cost ASC` and defaults to
`include_inactive=False`. Update validates against `GYM_REWARDS` in
`immutable_columns.py` (`reward_id`, `gym_id`, `created_at` frozen). There is
**no versioning** here — unlike discounts/plans, a reward's `point_cost` and
`price_label` are edited **in place**; a redemption snapshots the cost at
request time (§2), so an in-place edit never rewrites history.

**Preset import also writes this table** — importing a gym's preset catalog
inserts `gym_rewards` rows through the same production insert path (no
demo-only shortcut).

---

## 2. The redemption lifecycle — `member_reward_redemptions`

`Database/supabase/schemas/member_reward_redemptions.sql`. **Debit-on-request,
not debit-on-approval.** A member's `redeem` call debits `points_balance`
**immediately** when the pending row is minted — not later, when staff
approve. This is the load-bearing design choice: if the debit waited for
approval, a member with just enough points for one reward could fire off
several redemption requests before any of them is reviewed, over-spending a
balance that only one request should have consumed. Debiting at request time
makes `points_balance` always reflect "points not already promised to a
pending or fulfilled redemption."

| column | meaning |
| --- | --- |
| `redemption_id` | PK |
| `gym_id`, `member_id`, `reward_id` | scope (composite FKs enforce gym match on both member and reward) |
| `point_cost` | **snapshot** of the reward's `point_cost` at redemption time — the live `gym_rewards.point_cost` may change later without touching past redemptions |
| `requested_at` | when the member (or staff, for redeem-for-member) requested it |
| `status` | `reward_redemption_status` enum: `pending` / `approved` / `rejected` |
| `resolved_at` | when staff decided it; **NULL iff `status = 'pending'`** (`CHECK resolved_matches_status`) |

**Naming is deliberate:** `requested_at` / `resolved_at`, not `redeemed_at` /
`decided_at` — the founder vetoed "decided"
(`20260703000000_rewards_label_and_timestamps.sql`, which also collapsed a
legacy `gym_rewards.amount_off` column into `price_label`). Don't reintroduce
either old name.

### The three transitions

All three are single SQL statements in `src/rewards/sql/`, each returning the
result row (or no row, which the service turns into an error):

- **`redeem_reward.sql`** (member-initiated, `auto_approve=False`) — locks the
  member row and the reward row (`FOR UPDATE`), then in one CTE chain: debits
  `points_balance` guarded on `balance >= point_cost AND reward.is_active`,
  then inserts the `pending` row **only if the debit happened**
  (`EXISTS (SELECT 1 FROM debited)`). Zero rows back means "insufficient
  points or inactive reward" → `ValueError` → 400.
- **`approve_redemption.sql`** — a plain guarded `UPDATE ... WHERE status =
  'pending'` to `approved` + `resolved_at = now()`. **Balance untouched** —
  the debit already happened at request time; approval is pure fulfillment
  confirmation. No row back → `RedemptionAlreadyDecidedError` → 409.
- **`reject_redemption.sql`** — guarded on `status = 'pending' FOR UPDATE`,
  refunds the row's **snapshot** `point_cost` (never the reward's current,
  possibly-changed cost) back onto `points_balance`, flips to `rejected` +
  `resolved_at`. Same 409-on-no-row behavior as approve.

**Approved rows can NEVER be refunded or reversed.** There is no "un-approve"
endpoint and no SQL path back from `approved`. Once staff confirm fulfillment,
it's final — matching the fact that whatever was handed over (item, discount,
perk) is already out the door.

**Every transition is pending-guarded in SQL, not just in Python.** Both
`approve_redemption.sql` and `reject_redemption.sql` filter on
`status = 'pending'` inside the query itself, so a double-approve, a
reject-after-approve, or a race between two staff members acting on the same
row all resolve to "0 rows returned" → 409, never a double-refund or a
silently-overwritten `resolved_at`.

---

## 3. Staff redeem-for-member — auto-approved, with an `override` comp path

`POST /{reward_id}/redeem-for-member` (`RedeemForMemberRequest{member_id,
override}`) is **always auto-approved** — the row lands as `status='approved'`
with `resolved_at=now()` immediately, no pending stage, because staff acting
in person are the approval.

- **`override=false`** → `redeem(auto_approve=True)` — same guarded debit as
  the member path (`redeem_reward.sql` with `status='approved'`): rejected if
  the balance is short or the reward is inactive.
- **`override=true`** → `redeem_reward_override.sql` (`RewardsRedemptionService.redeem_override`)
  — **a comp.** Drops the sufficiency guard entirely; debits
  `LEAST(points_balance, point_cost)` so the balance **drains to zero and
  never goes negative**, while the inserted row's `point_cost` still stores
  the reward's **nominal** cost (not the actual amount drained). **A comp
  redemption row is indistinguishable from a fully-paid one — by design**
  (bare counter, no ledger — §5; don't try to reconstruct "was this a comp"
  after the fact). The `is_active` guard still applies (an inactive reward
  can't even be comped).

---

## 4. The `is_active` debit-gate rule — CTE ordering matters

Every debit CTE (`redeem_reward.sql`, `redeem_reward_override.sql`) gates the
`UPDATE ... points_balance` step itself on `locked_reward.is_active`, **not
only** on the final `INSERT`'s `WHERE lr.is_active = TRUE`. This isn't
redundant defense — Postgres runs **every data-modifying CTE in a statement
exactly once**, regardless of whether downstream CTEs or the final SELECT
reference its result. An unguarded debit UPDATE would silently burn a
member's points on a soft-deleted reward while inserting no redemption row —
the "no record of why the balance dropped" bug class this prevents. When
touching either SQL file, keep the `is_active` check on **both** the debit
and the insert.

**Pending rows on a soft-deleted reward still list and resolve.** Neither
`approve_redemption.sql` nor `reject_redemption.sql` checks `gym_rewards.is_active`
— a reward deactivated after a redemption was requested doesn't strand the
pending row; staff can still approve or reject it normally.

---

## 5. Points — a bare counter, not a ledger

`members.points_balance` (`CHECK points_balance >= 0`) is the **entire**
points model — a single integer per member. This is an explicit, standing
founder decision: **no ledger table, no activity feed, no per-award audit
trail.** A manual staff award and a comp redemption both just move the
number, with no distinguishable trace beyond whatever row the mutating
operation itself wrote. Don't propose adding a ledger without raising it as
a real scope decision first.

**Three writers touch `points_balance`, all clamped at the DB layer:**

- **Checkin award** — `src/checkin/sql/classes_award_points.sql`, a plain
  `+= :points` run once per **new** attendance row (never on an idempotent
  `ON CONFLICT` repeat). Its reversal, `checkin_revert_points.sql`, claws
  back with `GREATEST(points_balance - :points, 0)` — floors at 0 rather
  than erroring. Both owned by the **checkin** domain
  (`class-system-guide` skill); this guide only names the seam.
- **Redeem debit / refund** — §2/§3 above.
- **Manual adjustment** — `POST /members/{id}/points`
  (`src/members/sql/adjust_points.sql`) — a signed `+= :amount` that locks
  the member row and only applies when `points_balance + :amount >= 0`; a
  would-go-negative adjustment returns no row (rejected) rather than
  clamping. Deliberately stricter than the checkin reversal: an automatic
  clawback should never fail loudly, but a staff-typed adjustment should
  surface an error if it doesn't make sense.

---

## 6. Uploads — reward images

`POST /api/v1/uploads/image` (`src/uploads/`) is a shared multipart proxy
into the `combatden-assets` S3 bucket, used for reward images among other
categories (`reward` / `member` / `class` — the category is the S3 key
prefix). Gated by `Auth.verify_staff_principal` (owner/admin of at least one
gym — the gym-agnostic staff bar, since the endpoint takes no `gym_id`).
Enforces `image/*` content-type and a 5 MB cap (checked on `file.size` before
buffering, then again on the read bytes as a backstop). Returns a CDN URL
(`cdn.combatden.net/<category>/<uuid><ext>?v=<sha256-prefix>`) that the CRM's
`ImageUploadPickerField` writes into `gym_rewards.image_url` on save. When the
creator skips the picker, `RewardsService.create_reward` fills
`settings.default_reward_image_url` instead (a Pexels "prize box" hand-off
photo — `src/core/config.py`) — the column is NOT NULL, so a reward is never
created without an image. The preset import (`PresetsService`) applies the
same fallback (plus a `"Free"` fallback for a template reward missing
`price_label`) so an imported gym's reward rows can never violate either
NOT NULL constraint. Full upload detail lives in `FastApiBackend/CLAUDE.md`'s
"Image upload domain" section — this guide only covers the reward-specific
angle.

---

## 7. Deliberate decisions (don't re-flag these in review)

- **S3 orphans are accepted.** Replacing/removing a reward's image never
  deletes the old S3 object; there is no cleanup job.
- **Frozen or lapsed members may still redeem.** Points are points —
  redemption isn't gated on membership status; staff control fulfillment at
  the approval step.
- **A departed member's pending rows linger.** No cascade, no
  auto-resolution job — they stay in the approval queue until staff act.
- **The pending queue is paginated in SQL; the CRM reads page 1.**
  `list_pending_redemptions.sql` takes `:limit`/`:offset` + a window-function
  `total`; the CRM currently only requests the first page.

---

## 8. CRM surfaces (brief — CRM/CLAUDE.md is the CRM-side source of truth)

- **Loyalty tab** (`CRM/lib/features/rewards/` — `RewardsBloc` +
  `RewardsRepository`): catalog CRUD (`reward_form_dialog.dart`,
  `reward_delete_dialog.dart`) and the gym-wide approval queue.
- **Member page** (`CRM/lib/features/member_details/`): pending-approval
  actions and the redeem-for-member dialog
  (`redeem_reward_dialog.dart`), which surfaces the drain-to-zero warning
  when staff pick the `override` comp path, plus a points-adjust control.
- **Member-app preview** (`CRM/lib/features/members/presentation/widgets/member_app/loyalty_tab/`):
  the reward grid / card / confirm-dialog widgets that mirror what a member
  sees in the mobile app.

---

## Key files (where the model actually lives)

- **Schema:** `Database/supabase/schemas/gym_rewards.sql`,
  `member_reward_redemptions.sql` (the `reward_redemption_status` enum +
  the `resolved_matches_status` CHECK). Access rules in
  `Database/supabase/access_rules/gym_rewards.sql` /
  `member_reward_redemptions.sql`.
- **Models/enums:** `Database/python_data/schema/gym_reward.py`,
  `member_reward_redemption.py` (`RewardRedemptionStatus`),
  `immutable_columns.py` (`GYM_REWARDS`, `MEMBER_REWARD_REDEMPTIONS`).
- **Backend domain:** `FastApiBackend/src/rewards/` — `rewards_router.py`;
  `service/rewards_service.py` (`RewardsService` — catalog CRUD, takes a
  `default_image_url` constructor arg, DI-wired from
  `settings.default_reward_image_url` in `src/core/config.py`);
  `service/rewards_redemption_service.py` (`RewardsRedemptionService` +
  `RedemptionAlreadyDecidedError`); `schema/rewards_schema.py`
  (`RewardCreateRequest.price_label` required, `image_url` optional;
  `RewardUpdateData`'s `field_validator` rejects an explicit `null` on
  either); SQL in `sql/` (`insert_reward`, `update_reward`, `get_reward`,
  `list_rewards`, `redeem_reward`, `redeem_reward_override`,
  `approve_redemption`, `reject_redemption`, `get_redemption`,
  `list_pending_redemptions`, `redemption_history`).
- **Points seams (owned elsewhere, do NOT duplicate):**
  `src/checkin/sql/classes_award_points.sql` +
  `checkin_revert_points.sql` (checkin domain, `class-system-guide` skill);
  `src/members/sql/adjust_points.sql` +
  `service/management/members_management_update.py::adjust_points` (members
  domain).
- **Uploads:** `FastApiBackend/src/uploads/` (`uploads_router.py`,
  `service/uploads_s3_service.py`) — full detail in
  `FastApiBackend/CLAUDE.md`.
- **CRM:** `CRM/lib/features/rewards/` (catalog + approval queue),
  `CRM/lib/features/member_details/presentation/dialogs/redeem_reward_dialog.dart`
  (redeem-for-member).

---

## This is a living document

This skill is the single source of truth for how the rewards system works.
Whenever the model genuinely changes — a new column, a changed lifecycle
transition, a ledger getting built, a renamed service or SQL file, a changed
endpoint — **update this skill in the same change** so it never goes stale.
