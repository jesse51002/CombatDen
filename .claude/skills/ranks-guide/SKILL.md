---
name: ranks-guide
description: >-
  The single source of truth for how CombatDen's rank system works — the
  two-level model (ONE gym_ranks row per MAIN rank, each optionally carrying a
  count of derived sub-rank positions), the per-gym sub_rank_type (stripes|div)
  whose labels are derived and never stored, the leaf-assignment invariant
  (a member is pinned to current_rank_id + current_sub_index; if a rank has
  sub-ranks you can never sit "in the main rank" generically), the
  classes_to_next_major headline threshold with per-step denominators derived,
  the rank_changed progress anchor, persist-only belt-image overrides, and the
  three rank presets. Load this whenever you touch anything rank-shaped:
  gym_ranks / rank_presets / gyms.sub_rank_type / members.current_sub_index,
  the RanksService facade + its concern services (RanksMembers / RanksGroups /
  RanksReads / RanksPresets), the /api/v1/ranks routes, promote/set-member-rank,
  the ready-to-promote or members-in-rank reads, the member_details rank block,
  the seed's rank generators, or the CRM rank UI (ladder / rank-detail /
  promotion dialog / edit page / preset picker). Trigger on "rank", "belt",
  "stripe", "division", "sub-rank", "promote a member", "rank up", "classes to
  next rank", "rank preset", "sub_rank_type", or any change to the rank data
  model, endpoints, progress math, or rank UI.
---

# Ranks — the two-level, leaf-assignment model

This is the deep domain knowledge for CombatDen's rank system (v2). It is the
**source of truth** for how ranks behave; the various CLAUDE.md files hold only
the "how to work here" rules. When the rank model changes, **update this skill in
the same change** (it is a living document — see the bottom).

**The shape in one breath:** a gym has a *ladder* of **main ranks** (White Belt,
Blue Belt, … or Beginner, Novice, …). A main rank may optionally have a number of
**sub-rank positions** (BJJ stripes, or numbered divisions). A member is always
pinned to a **leaf** — either a main rank that has no sub-ranks, or a specific
sub-position of a main rank that has them. You can never sit "in the main rank"
generically once that rank has sub-ranks.

---

## 1. One row per MAIN rank (not per leaf)

`Database/supabase/schemas/gym_ranks.sql` — **one row per main rank**:

```
rank_id, gym_id,
main_rank_num_order,          -- ladder position (0-based), the only reorderable column
name,                         -- the main rank's name ("Blue Belt")
image_url,                    -- the belt image (USER-WRITABLE, nullable)
classes_to_next_major,        -- headline threshold to reach the NEXT main rank
sub_rank_count,               -- 0 = no sub-ranks (the main rank IS the leaf);
                              --  N>=1 = N leaf sub-positions
sub_rank_image_overrides,     -- JSONB sparse {sub_index: url}; PERSIST-ONLY
created_at
UNIQUE (gym_id, main_rank_num_order)   -- ladder position
UNIQUE (rank_id, gym_id)               -- for the members composite FK
```

There is **no** `color`, **no** `sub_name`, **no** `sub_rank_num_order`. A flat
ladder (no sub-ranks anywhere) is just N main rows with `sub_rank_count = 0`. A
BJJ "belts + stripes" ladder is 5 main rows each with `sub_rank_count = 5`.

> This is deliberately different from the pre-v2 model, which stored one row per
> *leaf* with `main_name`/`sub_name` denormalized onto every row and mandatory
> sub-ranks. If you find code assuming "every rank is a `(main, sub)` pair," it is
> stale.

## 2. Sub-rank TYPE is one per-gym setting; labels are DERIVED

`gyms.sub_rank_type` is an enum **`none | stripes | div`** (`NOT NULL DEFAULT
'none'`) — a single choice for the whole gym, **not** per rank. Each main rank
only chooses its `sub_rank_count`. The type is **writable via the ordinary
gym-update path** (`PUT /api/v1/gyms/{id}` → `GymUpdateData.sub_rank_type`, a
mutable column that rejects an explicit null); `from_preset` also sets it from the
preset's implied type.

**`'none'` = sub-ranks disabled gym-wide, and it's the DEFAULT** (most gyms have
main belts with NO sub-positions). It is a **view/label state layered over the
persisted per-rank `sub_rank_count`, never a destructive wipe**: switching a gym
TO `'none'` keeps every `sub_rank_count` / `sub_rank_image_overrides` on the rows,
so they reactivate if the gym switches back to stripes/div. The thing we never
want here: a switch to `'none'` that zeroes the per-rank counts.

The **EFFECTIVE sub-rank count** is what ALL leaf math uses: `0` whenever the gym
is `'none'`, else the stored `sub_rank_count`. In Python it's
`RanksBase._effective_sub_count(rank, sub_rank_type)`; in SQL it's `CASE WHEN
g.sub_rank_type = 'none' THEN 0 ELSE gr.sub_rank_count END` (every leaf-math query
joins `gyms`). So on a `'none'` gym every rank behaves as its own leaf — members
carry `current_sub_index NULL`, promotion is main-to-main, and the step
denominator is the full major threshold.

Sub-rank **labels are derived, never stored** — the one labeler lives in
`Database/python_data/schema/gym_rank.py` and is shared by the seed, the backend
reads, activity naming, and member-details:

- `sub_rank_label(sub_rank_type, sub_index) -> str | None`
  - none: always `None` (a `'none'` gym has no sub-positions; guarded so a stray
    index never produces a phantom label).
  - stripes: `0 -> None` (the bare belt, just earned), `1 -> "1 Stripe"`,
    `k -> "k Stripes"`.
  - div: `i -> "Div {i+1}"` (Div 1, Div 2, …).
- `rank_display_name(name, sub_rank_type, sub_index) -> str` → `"Blue Belt"` at a
  leaf/base position (and always on a `'none'` gym), else `"Blue Belt · 2
  Stripes"`.

The CRM mirrors this exactly in `RankSubType.subLabel(index)`.

**`sub_rank_count` is the LEAF count, not the stripe count.** A "4-stripe" belt is
`sub_rank_count = 5` (base + 4 stripes); a div with N divisions is `N`. Combined
with the effective count above, `current_sub_index ∈ [0, effective_count-1]` and
`effective_count == 0 ⇔ sub_index IS NULL` is a single uniform invariant. So
switching `stripes ↔ div` is a pure re-label on read, never a member rewrite —
but crossing the `none` boundary (none ↔ stripes/div) DOES change the effective
count, so members are reconciled (see §10).

## 3. The leaf-assignment invariant

Members reference their leaf via **`members.current_rank_id`** (→ the main row) +
**`members.current_sub_index`** (nullable int). The invariant, enforced by the
ranks service on **every** assign/promote/backfill path (and mirrored in the
seed), reads the **EFFECTIVE** count (§2 — `0` on a `'none'` gym):

- `effective_count > 0` ⇒ `current_sub_index` is **required** and in
  `[0, effective_count-1]`. You can never sit "in the main rank" generically when
  it has sub-ranks.
- `effective_count == 0` ⇒ `current_sub_index` is **NULL** (the main rank is
  itself the leaf; ALWAYS the case on a `'none'` gym). Assigning a sub-index to a
  rank on a `'none'` gym forces `NULL` (matches the subless-rank coercion, not a
  400).

Only the ranks endpoints write `current_rank_id` / `current_sub_index` — both are
in the `MEMBERS` immutable-columns frozenset, so the generic member update can
never touch them (there is no rank "side door").

## 4. Progress: `classes_to_next_major`, derived per-step, and the `rank_changed` anchor

`classes_to_next_major` on the main rank is the **headline** number the CRM ladder
shows ("N classes to next rank"). The per-sub-**step** denominator is **derived**,
not stored: `ceil(classes_to_next_major / effective_count)` when
`effective_count > 0`, else `classes_to_next_major` (so on a `'none'` gym the step
is always the full major threshold). That derived step is a member's immediate
progress denominator.

The progress **numerator** is anchored on the member's last rank change. In
`FastApiBackend/src/members/sql/member_details/member_details.sql`, the
`rank_classes_since` subquery counts:

```
member_attendance.occurred_at
  > COALESCE(MAX(member_activities.time WHERE activity_type='rank_changed'),
             members.created_at)
```

So "classes since rank" = attendance rows after the most recent `rank_changed`
activity, falling back to the join date. **This anchor is load-bearing** — it is
why every rank change MUST log a `rank_changed` activity, and why the rank
columns are write-locked to the ranks endpoints. The same anchor subquery is
reused verbatim in `list_members_ready_to_promote.sql`.

`rank_changed` (`RANK_CHANGED_ACTIVITY_TYPE = "rank_changed"`) is logged on every
promote, explicit set, and backfill (via `insert_rank_activity.sql` /
`backfill_lowest_rank.sql`). `activity_info` is
`{old_rank_id, new_rank_id, old_rank_name, new_rank_name}`, where the names are the
derived `Main · SubLabel`. A **sub-only** promotion (same main rank, next
sub-index) still logs — only a no-op (identical rank_id AND sub_index) skips.
Delete-reassignment is deliberately activity-**silent** (a deletion is not a
promotion; progress must not reset).

## 5. Belt images: user-writable, persist-only overrides

`image_url` on the main rank is **user-writable** (uploaded in the CRM edit page).
Per-sub images live in `sub_rank_image_overrides`, a sparse `{sub_index: url}` map.

- **Effective sub image** = `overrides[sub_index]` if present, else the main
  `image_url`. In SQL: `COALESCE(sub_rank_image_overrides ->> CAST(idx AS TEXT),
  image_url)` (member_details resolves the leaf image this way).
- **The override map is PERSIST-ONLY.** Shrinking `sub_rank_count`, switching the
  gym's `sub_rank_type`, or any other "revert" **never prunes the map** — overrides
  for now-hidden indices go dormant and reactivate if the count grows back.
  `update_rank`'s count-shrink path clamps *member* sub-indices
  (`clamp_member_sub_index.sql`) but never touches the overrides JSONB. The CRM edit
  UI only ever *writes* overrides, never deletes a key.

> **Reversed rule:** the pre-v2 design treated belt art as "generation-owned"
> (a deferred ThemeService/AI pipeline) and forbade a manual image field. That is
> reversed — images are a plain user field now. The AI-generation spec
> (`FastApiBackend/rank_belt_image_build_spec.md`) is kept as a *possible future*,
> marked superseded, not the current design.

## 6. The three presets (`rank_preset_kind`)

`rank_presets` mirrors the main-row shape, keyed by a `rank_preset_kind` enum
(the old Postgres `gym_type` enum was dropped). Applying a preset clones its main
rows into `gym_ranks` (`from_preset` / `insert_ranks_from_preset.sql`, idempotent
`ON CONFLICT (gym_id, main_rank_num_order) DO NOTHING`), sets the gym's
`sub_rank_type` to the preset's implied style (every kind implies a **concrete**
style now — see below), then reconciles existing members' sub-index to it and
runs the lowest-rank backfill.

- **`bjj_belts`** — White→Black, `sub_rank_count = 0` (flat belts),
  `implied_sub_rank_type = none`.
- **`bjj_belts_stripes`** — the same belts, `sub_rank_count = 5` (base + 4
  stripes), `implied_sub_rank_type = stripes`.
- **`flat`** — Beginner→Elite tiers, `sub_rank_count = 0`,
  `implied_sub_rank_type = none`.

The BJJ presets seed alternating placeholder belt images
(`cdn.combatden.net/ranks/presets/{white,blue}.png` — real art uploaded later).
The preset *data* is authored in the seed generators (`generators/ranks.py`), but
rank presets are a **first-class ranks feature** (a real CRM picker screen backed
by `GET /ranks/presets[/grouped]` + `POST /ranks/from-preset`) — NOT part of the
demo/showcase `PresetsService` (that importer never touches ranks).

## 7. Service layout (facade + concerns)

`FastApiBackend/src/ranks/` — a facade over concern services (DI in
`core/dependencies.py`, container `DependencyInjector`):

- **`RanksService`** (facade, `RanksBase`) — single-rank CRUD (`create`/`update`/
  `get`/`list`/`delete`) + the enable toggle; delegates the rest. `update_rank`
  builds the dynamic SET with **per-column casts** (`CAST(:sub_rank_image_overrides
  AS JSONB)` — never `:x::jsonb`) and runs `clamp_member_sub_index.sql` when
  `sub_rank_count` changes (overrides untouched). `list_ranks` also returns the
  gym's `sub_rank_type` on `RankListResponse`.
- **`RanksBase`** — shared reads: `_list_ranks_in_session`, `_gym_sub_rank_type`,
  `_effective_sub_count(rank, sub_rank_type)` (`0` on a `'none'` gym, else the
  stored count — the single source of the effective-count rule), and `_next_leaf`
  (enumerate leaves per main via the EFFECTIVE count; rank-less → lowest leaf; top
  main + top sub → `ValueError("highest rank")`; on a `'none'` gym every rank is
  effective-subless so promotion is main-to-main).
- **`RanksMembers`** — the only member-writing paths: `promote_member`,
  `set_member_rank` (validates the leaf invariant against the effective count),
  `_apply_member_rank` (writes + logs `rank_changed` with derived names),
  `backfill_lowest_for_gym`, and the sub-index **reconcile** for a gym
  `sub_rank_type` change — `reconcile_sub_index_for_gym` (own-session, the gyms
  edge) / `reconcile_sub_index_in_session` (in-session, `from_preset`) →
  `reconcile_member_sub_index_for_gym.sql`.
- **`RanksGroups`** — only the main-only two-phase `reorder_ranks` (+`REORDER_SHIFT_OFFSET`
  guard against the non-deferrable `UNIQUE (gym_id, main_rank_num_order)`). There is
  no more group rename/delete (a "group" is now a main rank → plain update/delete).
- **`RanksReads`** — the two paginated member reads (`COUNT(*) OVER()` +
  `start_index`/`count`): `list_ready_to_promote` (active, ranked, not
  top-of-ladder members sorted by classes **REMAINING** to the next leaf,
  ascending — `ORDER BY (step_denominator - classes_since) ASC, classes_since
  DESC, member_id ASC`, so the closest-to-promotion members come first and
  at/over-threshold members sort to the very top; `member_id` is the
  deterministic pagination tiebreaker — the promotion board) and
  `list_members_in_rank` (the roster for one main rank). Both compute the step
  denominator from the EFFECTIVE count.
- **`RanksPresets`** — `from_preset` (also sets the gym `sub_rank_type`), plus the
  preset list/grouped reads.

**No inline SQL** — every query is its own `.sql` file loaded via `load_sql`, with
`CAST(:x AS T)` binds (never `:x::t`).

## 8. Routes (`/api/v1/ranks`)

CRUD (`GET /`, `POST /`, `GET /{id}`, `PUT /{id}`, `DELETE /{id}`) ·
`POST /from-preset` (`preset_kind`) · `GET /presets` + `GET /presets/grouped` ·
`GET /enabled` + `PUT /enabled` · `POST /promote-member` · `POST /set-member-rank`
(`rank_id?` + `sub_index?`) · `POST /reorder` (main-only) · **`GET /ready-to-promote`**
· **`GET /{rank_id}/members`**. The static routes are declared before `/{rank_id}`.
**Removed:** `PUT /rename-group`, `DELETE /group`. `_rank_http_error` maps
`"highest rank"`→409, `"not found"`→404, else 400.

## 9. Promotion semantics

On a `'none'` gym there is no "next sub" at all — the effective count is `0`
everywhere, so `promote-member` is purely main-to-main (top main → 409) and the
only meaningful ops are "next major" and "choose a rank".

- **Next sub-rank** — advance `current_sub_index` by one within the main rank.
  `promote-member` does this (and, at the top sub, rolls over to the next main's
  base leaf); the CRM only offers "next sub" while `current_sub_index <
  effective_count-1`.
- **Next major rank** — jump straight to the next main rank's base leaf, skipping
  any remaining sub-positions. The CRM does this via `set-member-rank` (to the next
  main's base index) rather than a backend `kind` param — a clean use of the
  existing endpoint. It logs `rank_changed` and resets the progress anchor.
- **Choose a rank** — explicit `set-member-rank` to any `(rank_id, sub_index)`, or
  `rank_id = null` to unassign (both columns null).

The CRM encapsulates all three in `RanksRepository.applyPromotion(PromotionChoice)`
and surfaces them through ONE bloc-agnostic `PromotionDialog`
(`CRM/lib/shared/widgets/promotion_dialog.dart`) reused by the member-detail page,
the rank-detail screen, and the ready-to-promote board.

## 10. Edge cases (and where they're handled)

- **count shrinks below a member's sub_index** → `clamp_member_sub_index.sql` runs
  inside `update_rank` (`LEAST(current_sub_index, count-1)`); the override map is
  NOT pruned.
- **promote at top sub of a main** → advance to the next main's base leaf.
- **promote at top main + top sub** → `ValueError("highest rank")` → 409.
- **unassign** (`set-member-rank rank_id=null`) → both columns null, logs `rank_changed`.
- **assign to an effective-`count>0` rank with no sub_index** → 400 (invariant).
- **assign to an effective-`count==0` rank with a sub_index** (a subless rank, or
  ANY rank on a `'none'` gym) → sub_index forced to NULL.
- **delete a main rank** → neighbor-reassign members to the replacement's base leaf
  (lower → higher → NULL), silent (no activity), FK never dangles. The base leaf
  uses the effective count (NULL on a `'none'` gym).
- **change `gyms.sub_rank_type`** → members are reconciled to stay leaf-valid
  (`reconcile_member_sub_index_for_gym.sql`, run by BOTH the gym-update path and
  `from_preset`, no `rank_changed` logged): **stripes ↔ div** is a pure re-label,
  members are NOT moved (an already-valid index is preserved); **→ `'none'`**
  clears every `current_sub_index`; **`'none'` → stripes/div** fills a NULL
  sub-index with the base leaf `0` on ranks that have sub-ranks. The persisted
  `sub_rank_count` / `sub_rank_image_overrides` are never touched.

## 11. CRM surface (brief)

Ranks tab (tab of the Gym catalog) = a view switcher **Rank ladder | Ready to
promote**. The ladder redesign inverts the old hierarchy: a prominent
`main_rank_card.dart` (large `RankBeltImage` + name + classes-to-next-major, the
whole card tappable → the deep-linkable rank-detail screen) with a horizontal
`sub_rank_strip.dart` of smaller sub-belts beneath it; the granular steps live in
the full-screen `edit_rank_screen.dart` (main + per-sub images, sub defaults to the
main). `RankBeltImage` (`shared/widgets/`) is the one belt renderer (image →
neutral belt-glyph fallback; **no color swatch** — color was removed). The
People-tab members filter gained a rank dimension (`rank_ids`, filtering
`members.current_rank_id`). See `CRM/CLAUDE.md` for the full CRM wiring.

**Belt image upload** uses the backend `rank` `UploadCategory` (S3 `rank/`
prefix); the preset placeholder art lives under `rank/presets/` in the same
`combatden-assets` bucket / `cdn.combatden.net` CDN.

---

## Living document

This skill tracks the rank system **as it currently is** — not a changelog. When
the rank model, endpoints, progress math, presets, or rank UI change, update this
skill in the **same** change so it never drifts. If you touch anything rank-shaped
and find a statement here that no longer matches the code, fix the skill (or the
code) so they agree before you finish. Related skills: `memberships-guide`,
`reconciler-guide`, `qa-crm`.
