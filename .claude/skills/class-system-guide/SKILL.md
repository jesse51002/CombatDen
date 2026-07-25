---
name: class-system-guide
description: >-
  The single source of truth for the CombatDen CLASS SYSTEM — scheduling (the
  producer) + attendance/reservations (the consumer) across two FastApiBackend
  domains and the CRM schedule surfaces. THE CENTER (§0): the recurring
  schedule is APPEND-ONLY VERSIONED rows (gym_class_schedules — identity +
  immutable versions, each freezing its timezone) and every occurrence is
  COMPUTED, never stored; an occurrence's permanent identity is its ORIGINAL
  slot (class_id + original_date + original_time — the owning version's
  pre-exception slot), which is what attendance, sign-ups, and instance
  exceptions key. The schedule shape is weekday_slots JSONB (day -> ordered
  slot list, several times per day legal, per-slot instructor; daily/monthly
  use the reserved "all" key). Covers the version-ownership model
  (effective_from windows, first-version-owns-the-past, SLOT-level dedup,
  the ONE pure ClassesExpander wrapped by
  ClassesVersionExpander), the MINT engine (ClassesVersionsService — schedule
  edits mint a version effective NOW and wipe future-keyed rows unless the
  exact wall-clock slot survives; soft-delete wipes everything future; a gym
  timezone change re-mints per class), exceptions binding to original slots
  (reschedule-to-any-date, time-aware collision, attendance wipe-future /
  keep-and-resync-past), the warn-first check-in gate (unsigned-waiver legal gate included; is_member kiosk-reject
  vs staff requires_confirmation; the 2h early window; points award + repeat
  echo), the SIGN-UPS/reservations model (class_signups ≠ member_attendance;
  the signed-up-or-attended capacity union; the combined roster), and the
  shared CheckinReverser (the one deliberate classes→checkin dependency) plus
  the gyms→classes tz-remint edge. Read before touching src/classes/,
  src/checkin/, gym_class_schedules, or the CRM schedule feature.
---

# The Class System — versioned scheduling + attendance + reservations

Two backend domains + the CRM schedule feature. **`src/classes/`** = the
**producer** (class CRUD, the versioned recurrence/exception engine, the
schedule board, cancel/reschedule, the version mint+wipe). **`src/checkin/`**
= the **consumer** (the per-member gate + write, batch check-in, attendee
roster, streak, cycle usage, and **sign-ups/reservations**). Routes:
`/api/v1/classes*`, `/api/v1/checkin*`, `/api/v1/signup`, `/api/v1/streak`.

## 0. THE CENTER — versioned schedules, computed occurrences (read first)

**A class = one IDENTITY row + append-only SCHEDULE VERSIONS.**

- **`gym_classes`** (identity): name, description, `allowed_plan_ids`,
  `max_capacity`, `image_url` (**NOT NULL — every class has an image**;
  create/update/preset-import fill `settings.default_class_image_url`, a
  generic people-in-a-gym photo, when none is provided), `points_worth`,
  `is_active`, `is_deleted`. Identity applies across all time — a rename
  renames the past too.
- **`gym_class_schedules`** (versions): the schedule shape —
  `duration_minutes`, recurrence (`recurring_unit`/`interval`),
  `start_date`/`end_date` (the recurrence range), and **`weekday_slots`
  (JSONB)** — the WHEN: day → ordered slot list, so a class may occur
  SEVERAL times on one day, each slot with its own optional instructor.
  Weekly uses `sun`..`sat` keys (`{"mon": [{"time": "06:00",
  "instructor_id": "<uuid|null>"}, {"time": "18:30", ...}]}` — a day occurs
  iff its key holds a non-empty list); daily/monthly use exactly the
  reserved `"all"` key. Times are "HH:MM", unique per day, stored sorted.
  Deep validation lives in ONE shared canonicalizer
  (`classes_expander_schema.canonicalize_weekday_slots`) run by both the API
  schema and the DB-row contract; SQL only guards coarse structure. Slot
  `instructor_id`s can't be FK-enforced inside JSONB — the mint validates
  them against `gym_employees` instead (`_assert_instructors_in_gym`).
  Plus `effective_from` (the version boundary, a timestamptz: many edits can
  land in one day) and `timezone` (the gym's IANA zone FROZEN at mint). Rows
  are write-once; there is no `effective_until` — a version's coverage
  window is `[effective_from, next version's effective_from)`, derived. The
  `gym_class_schedules_current` view surfaces the latest version per class
  (used by class CRUD reads; window reads always load ALL versions).

**Occurrences are never stored.** Every read — past and future — computes
them from the versions + exceptions. The past is immutable because past
versions never change: re-expanding them is deterministic (each version
expands in its OWN frozen timezone, so nothing can re-derive differently).

**Occurrence identity = the ORIGINAL slot**: `(class_id, original_date,
original_time)` — the date + the owning version's slot time, BEFORE
exceptions, gym-local wall clock. `member_attendance`, `class_signups`, AND
`class_instance_exceptions` key on the full slot (their UNIQUEs include
`original_time` — with several slots per day legal, date alone is
ambiguous); an exception (retime / reschedule / cancel) NEVER re-keys
anything, so sign-ups and attendance follow the occurrence wherever it
moves. **Every API call addresses an occurrence by `class_id +
occurrence_date + occurrence_time` — the ORIGINAL date AND time** (the board
row carries `original_date` + `original_time` for exactly this; `class_date`
/ `resolved_class_time` are the effective display values).

**Version ownership rule** (the pure `ClassesVersionExpander`):
a version owns candidate slot `(D, T)` iff its original instant —
`combine(D, T, ZoneInfo(version.timezone))` — falls in the version's window
(T ranges over the day's slot list). Three refinements:
1. The FIRST version owns back to −∞ (its `effective_from` is just its mint
   stamp), so a class created with a backdated `start_date` renders its past.
2. The LAST version owns to +∞ — there is exactly one present/future owner
   (a mint is always effective NOW; future-dated takeovers don't exist).
3. **Slot-level dedup, NOT day-level**: when two versions both produce a
   candidate at the same exact `(original_date, original_time)`, the EARLIER
   version wins. ≤1 ORIGINAL occurrence per class per exact SLOT is the
   invariant — what makes date+time API addressing and the
   `UNIQUE(..., original_date, original_time)` keys unambiguous. A version
   BOUNDARY day can legitimately show occurrences from BOTH versions at
   different times (old 06:00 already ran before a mid-day mint + new 18:30
   upcoming) — with multi-slot days legal that is honest rendering, not
   doubling. (Effective-date doubling via reschedule remains allowed too.)

**`ClassesExpander` is still the ONE pure recurrence+exception engine** (no
I/O; each candidate date FANS OUT over its slot list — the weekday key for
weekly, `"all"` for daily/monthly — and each slot resolves independently
against ITS OWN instance exception; instance-wins-over-range precedence, a
range covers EVERY slot of its covered dates, monthly last-day clamp, DST
via `ZoneInfo`, cancelled dropped or emitted flagged;
`instructor_for(gym_class, when, slot_time)` public — per-slot).
`ClassesVersionExpander` wraps it per version and adds ownership windowing +
the slot dedup, tagging each `EffectiveOccurrence` with `original_time`, the
owning `schedule_id`, and `original_start_at`. The demo seed MIRRORS both —
never re-derive recurrence anywhere else.

## 1. The MINT engine — how a schedule ever changes

**`ClassesVersionsService` (`src/classes/service/classes_versions_service.py`)
is the only writer of `gym_class_schedules`.** A mint runs in ONE transaction:

1. **Deep-equal no-op**: a submission equal to the current version (all shape
   fields AND the timezone) mints nothing, wipes nothing. `weekday_slots`
   compares on the canonicalized parsed form, so key/list reordering can
   never fake a change.
2. Insert the version, `effective_from` = server now, `timezone` = the gym's
   current zone (slot instructors validated against `gym_employees` first —
   the JSONB replacement for the old per-weekday FKs).
3. **The WIPE decides per occurrence SLOT** — `(original_date,
   original_time)`; two same-day occurrences are decided independently. A
   slot is a candidate when its ORIGINAL instant is at/after the mint (a
   slot that already started is never touched; the old version owns it
   forever). A candidate is then LEFT ALONE when any of these hold:
   - its exception is a **CANCELLATION** — slot-keyed intent ("this
     occurrence is off") that survives any shape change; deleting it would
     silently revive the cancelled occurrence;
   - its **EFFECTIVE start** (the reschedule/retime target) is before the
     mint — the occurrence already RAN (rescheduled into the past); its
     attendance is real and the exception row anchors it;
   - the new version still emits the date with a slot at the exact same
     wall-clock `original_time` (the exact-slot match — dropping a day's
     18:00 slot wipes only ITS rows; the surviving 06:00 keeps everything).
   Otherwise the slot is torn down via the undo service's shared
   `teardown_occurrence` — attendance reversed per member through the one
   `CheckinReverser` implementation (billing-adjacent: points clawback
   floored at 0 + activity drop + pack auto-end reversal), sign-ups deleted
   — and its (non-cancelled) instance exception DELETEd. **Range exceptions
   are untouched** — date-range semantics survive any shape.

Consumers of the engine:
- **Class create** → identity INSERT + the first version (no rows yet, no
  wipe). A future `start_date` is the supported way to launch a class ahead
  of time.
- **`PUT /classes/{id}`** — the update request is split by destination
  (the discounts identity/values precedent): `identity` (partial, in-place
  UPDATE) + `schedule` (a COMPLETE shape → mint). Responses stay flat
  (identity + current version), so the CRM form shape is unchanged.
- **Soft delete** (`DELETE /classes/{id}`) → flips the flags AND runs the
  wipe with nothing surviving (a dead class produces no future slots). Its
  past renders forever (the board includes deleted classes, past-only).
  `is_deleted` is NOT accepted via PUT — deletion must go through the
  endpoint so the wipe runs.
- **Gym timezone change** — `GymsService.update_gym` detects a `timezone`
  change and calls `remint_timezone(gym_id, new_tz)`: a same-shape mint (new
  tz) per live class that **never wipes** (identical shape ⇒ every wall-clock
  slot survives by construction; the instant-based wipe would only
  false-positive inside the tz-delta window around the re-mint moment).
  Existing versions keep their frozen zones so the past never moves. Known
  narrow limitation: a slot whose instant falls between the new-tz and
  old-tz reading of the re-mint moment sits in an ownership gap and may not
  render for that ONE day — its rows are deliberately left untouched. This
  is the documented **gyms → classes** DI edge.

## 2. Exceptions — per-occurrence changes on top of versions

`class_instance_exceptions` (keyed `UNIQUE(class_id, original_date,
original_time)` — one row per exact SLOT, so two same-day occurrences are
overridden independently) overrides or cancels ONE original slot (incl.
`new_date` = reschedule target — any date, `new_max_capacity`,
`new_class_time`, `new_instructor_id`, `new_duration_minutes`);
`class_range_exceptions` cancels/substitutes a continuous range — a range
covers EVERY slot of its covered dates, and a CANCEL range additionally
tears down the slots it actually cancels, per-slot, in the same transaction
as the range insert (§4). Override fallbacks (duration / the slot
instructor) resolve against the OWNING version — a retro edit on an
old-version slot falls back to THAT version's defaults
(`ClassesUndoService.owning_version` / `resolve_default_instructor`, both
slot-time-aware).

**Range exceptions have a full CRUD surface**: `POST` create,
`GET /{class_id}/exceptions/range` (every range ever created for the class,
newest first — no window filter, no client-supplied `gym_id`; the caller's
gym is resolved from the class like every other `/{class_id}/exceptions/*`
route), `PUT .../range/{exception_id}` (move `start_date`/`end_date` only —
`is_cancelled`/`new_instructor_id` are fixed at creation; for a CANCEL range
this re-runs the SAME teardown as create over the range's NEW coverage,
atomically with the date update, via the shared private seam
`_write_range_and_teardown`), `DELETE .../range/{exception_id}` (removes the
row outright). Dates that fall OUT of a range's coverage — narrowed by a PUT
or freed by a DELETE — are never explicitly restored; they simply stop being
covered on the next expansion (anything already torn down while covered stays
torn down). The expander threads WHICH range cancelled an occurrence onto
`EffectiveOccurrence.cancelling_range_id` (→
`EffectiveClassInstanceResponse.cancelling_range_id` on the board) — set only
when a RANGE (not an instance) exception is what cancelled it, letting the
CRM jump straight from a cancelled occurrence to editing its governing range.

**"Immutable past" applies to schedule-VERSION edits only.** Past-dated
exceptions, cancel-past, reschedule-to-past, and retroactive check-ins are
all supported — the exception layer is how the past gets corrected.

## 3. The board — one computation for everything

`ClassesScheduleReaderService` (`GET /api/v1/classes/instances`): load every
class (deleted included) + ALL versions + the window's exceptions
(concurrently, via `asyncio.gather`), expand via `ClassesVersionExpander`
with `include_cancelled=True`, enrich with instructor names, per-SLOT
capacity overrides / instance-exception flags, and the attendance / sign-up
counts (everything keyed `(class_id, original_date, original_time)` — plain
GROUP BYs, no joins; two same-day slots enrich independently). No
stored-occurrence side, no past/live split, no dedup pass.
**Cross-window reschedules render via WIDENING**: the exception load also
returns rows whose `new_date` falls in the window; each class expands over
bounds stretched to its exceptions' original/target dates; the result is
filtered back to the view window by EFFECTIVE date — a moved-in occurrence
renders here (counts still load, keyed by its out-of-window original date),
a moved-out one renders only in its target window. The one time-dependent
rule: a soft-deleted class emits only occurrences whose END (`occurred_at`
+ duration) is at/before now. Board rows carry `original_date` +
`original_time` (addressing) alongside `class_date` / `resolved_class_time`
(display).

**Paused is a QUERY PARAM, and its default is fail-CLOSED.** `is_active` and
`is_deleted` are two INDEPENDENT rules — never entangle them:

| flag | rule |
| --- | --- |
| `is_deleted = true` (soft-DELETED) | past-only, **always** — unaffected by `include_inactive` |
| `is_active = false` (PAUSED) | **no occurrences at all** — not past, not future — unless `include_inactive=true` |

`GET /api/v1/classes/instances?…&include_inactive=` (default **false**) is the
switch, mirroring the identical param on `GET /api/v1/classes`
(`classes_list.sql`). The reader drops paused rows in
`ClassesScheduleReaderService._visible_classes` **before expansion**, so a
class nobody asked for costs no expansion work.

**The two rules are independent, but the two COLUMNS are not — and that is a
trap.** `classes_soft_delete.sql` writes `is_deleted = TRUE` **and**
`is_active = FALSE` in one statement, so a soft-deleted class is ALWAYS also
`is_active = false` on disk; there is no such row as deleted-and-active. Any
"is this class visible" test must therefore read **both** columns
(`_visible_classes` keeps a row when `is_active OR is_deleted`). An
`is_active`-only test silently applies the PAUSED rule to deleted classes and
takes their whole past — occurrences, attendance / sign-up counts, and staff's
only route to correcting one of those check-ins — off the board.

The default is the point. **Check-in and sign-up REJECT a paused
occurrence** — `CheckinClassResolver.resolve` raises
`CheckinClassInactiveError("Class is not active")`
(`checkin_class_resolver.py`) and `SignupService.create` does the same
(`signup_service.py`) — a `ValueError` subclass from
`src/checkin/checkin_exceptions.py` that the API surfaces as
`400 {"detail": "Class is not active", "code": "class_inactive"}`. So the CRM
dashboard, the kiosk (check-in grid + Get-the-App showcase), the member-detail
check-in/reserve dialog, and the member portal get the safe answer **without
asking for it and without being able to forget**, and the typed rejection
stays as the backstop underneath. **Never re-add a client-side `is_active`
filter** — a client-side rule is one every future surface has to remember;
this one they inherit.

`include_inactive=true` belongs to class MANAGEMENT only — the surface where a
paused class must stay visible because it is the only route to un-pausing it.
In the CRM that is the **schedule board / classes page**, and it opts in on
**two** reads:
- `ScheduleRepository.listClasses(gymId, includeInactive: true)` — the class
  CATALOG read served by `ClassesCrudService` (a DIFFERENT read from the
  reader/expander), which populates the instructor picker and the
  edit-a-definition path.
- `ScheduleRepository.listEffectiveInstances(..., includeInactive: true)` —
  the OCCURRENCE feed, so a paused class's cards actually appear on the week
  board. This is the ONE occurrence-feed caller that passes the flag; every
  other call site (dashboard, kiosk, member check-in dialog, member portal)
  uses the paused-free default.

Because that board read is the one response that MIXES paused and live rows,
**`EffectiveClassInstanceResponse.is_active` is on the wire** — populated from
`gym_classes.is_active`, always true on every other surface's read. The board
marks an `is_active = false` card "Paused"
(`ClassCard(isPaused: !entry.isActive)` → an amber `ClassMetaChip`) and
`schedule_screen.dart`'s `_onInstanceTap` routes a paused card's tap straight
to `ClassFormScreen` — no occurrence chooser, no check-in/reserve/cancel, all
of which the backend would reject anyway. Front desk / trainer (no
`canEditSchedule`) get an inert tap on a paused card rather than a dead end.

## 4. Cancel / reschedule — any date, keys never change

One shared engine on `ClassesUndoService` (`ClassesExceptionsService`
delegates its `new_date` upserts to it, so the two entry points can't
diverge):

- **Cancel** — TWO entry points, ONE teardown: the dedicated
  `DELETE /{class_id}/occurrences/{original_date}?occurrence_time=` endpoint
  AND an exception upsert with `is_cancelled=true` (the CRM's "Cancel this
  class") both run `ClassesUndoService.teardown_occurrence` — reverse the
  exact SLOT's attendance (points clawed back), DELETE its sign-ups (a
  cancelled occurrence can't be attended — dead rows otherwise; a same-day
  sibling slot is untouched) — then write the cancelled exception, all in
  one transaction.
- **Range cancel** (`POST .../exceptions/range` with `is_cancelled=true`) —
  a THIRD `teardown_occurrence` consumer (`ClassesExceptionsService
  ._teardown_covered_occurrences`): in the SAME transaction as the range
  insert, every SLOT in `[start_date, end_date]` still carrying a
  reservation or attendance row is re-resolved THROUGH the just-inserted
  range (a same-session read) and left alone when an instance exception
  governs that exact slot instead (override or moved elsewhere — an
  instance exception always wins over any range) or an earlier-created
  covering range still renders it; otherwise it tears down ONLY when its
  original slot instant is still at/after now — so a covered multi-slot day
  can split (the already-run 06:00 keeps its attendance; the upcoming 18:30
  is torn down). An already-run occurrence covered by
  a retroactive range cancel KEEPS its attendance — deliberately asymmetric
  with the single-occurrence cancel above, which tears down regardless of
  instant (mass-clawing-back historical points from one bulk range action
  is a shock hazard; a gym wanting that cancels the single occurrence).
- **Reschedule** (`POST .../reschedule` or an exception upsert with
  `new_date`): upsert the exception's `new_date`. **Reservations (sign-ups)
  always carry** (identity key untouched). Attendance follows the move,
  decided by the new EFFECTIVE start INSTANT — never the calendar day: a
  target instant still ahead of now (including later TODAY) wipes the
  occurrence's check-ins (same reversal as cancel — the class hasn't
  happened at its new slot); an already-past target instant keeps them with
  their denormalized `occurred_at` re-synced
  (`sync_attendance_occurred_at` — also called by a plain same-date retime
  override on an attended occurrence). All instants compute in the OWNING
  version's frozen timezone. **A re-sent unchanged landing is
  a no-op move** (`is_landing_unchanged`) — attendance handling is skipped,
  so the CRM's preserve-the-move re-send (its override save re-sends the
  current effective date, judged against `originalDate`) never re-wipes
  early check-ins.
- **`assert_no_reschedule_conflict` is time-aware** — rejected only when the
  exact target instant (date + effective time) is already taken: other
  reschedules targeting the date are resolved per-candidate against each
  candidate's own owning version, plus a single-day expansion check.

## 5. The check-in gate — warn-first, no writes on resolve

`CheckinClassResolver.resolve(class_id, gym_id, occurrence_date,
occurrence_time)` loads the class identity, resolves the occurrence through
the shared **`CheckinOccurrenceResolution.resolve_original`** — the ONE
original-SLOT resolution algorithm (versions + exceptions → the version
expander, with the reschedule window-widening; the match is the exact
`(original_date, original_time)` pair) that the sign-up service also
injects, so check-in and sign-up can never disagree about whether an
occurrence exists — and returns a `ResolvedClass` (`occurrence_date` +
`original_time` = the original slot, effective `occurred_at`, effective
capacity, points, plan gate inputs). Purely a read — nothing is written until the gate records.
The **2h early-check-in window** (`settings.checkin_opens_hours_before_start`)
rejects an occurrence starting >2h out. Retroactive any-date check-ins work
(the resolver validates against whichever version owned that date).

`CheckinMemberGate.checkin_member(resolved_class, member_id, is_member,
ignore_warnings)`:
- **`is_member=True`** (kiosk / member self) — strict: a blocking condition
  (`no_membership | out_of_classes | ineligible_plan | over_capacity |
  unsigned_waiver`) **rejects** (`skip_reason`, nothing written). What blocks
  is `GateEvaluation.blocked`, **not** membership of `CheckinWarning` —
  `overdue` is a warning that deliberately does NOT block (see below).
- **`is_member=False`** (staff, CRM default) — a clean check-in records, but
  a warned one is **NOT recorded**: `requires_confirmation=true` +
  `warnings`; resend with **`ignore_warnings=true`** to record
  (best-available / NULL attribution). Batch has a `needs_confirmation` item
  status. EVERY reason warns staff, including `overdue`.
- **The overdue warning** (`overdue`): the attributed membership is past due
  — evaluated with the ONE shared rule in
  `src/shared/membership_status.py` (`is_membership_overdue`, active-only),
  the same text the members-list Overdue tab, its tally, its filter and the
  growth revenue tiles use. It compares `renew_date` to `gym_today` (the gym-local CURRENT date,
  carried on `MembershipUsage`) — NOT to the occurrence's date. "Does this
  member owe money" is a question about the present, and `status` is
  now-anchored too, so both halves of the test share one clock. (Coverage and
  usage stay occurrence-anchored via `covers_reference` / `reference_date`;
  only this one check is now-anchored, deliberately.) It tests EVERY covering
  membership, not just the attribution target — overdue is member-level, so an
  overdue recurring plan sitting behind a higher-priority trial pack still
  warns. **Blocks a kiosk** like every other reason (it IS in
  `GateEvaluation.blocked`): an unpaid member is sent to the front desk rather
  than self-admitting, and `ignore_warnings` never loosens the kiosk. Staff keep
  the override — the CRM holds the check-in and records it on "Check in anyway".
  Known caveat: `next_due_date` can read past-due while Stripe shows everything
  paid (a missed webhook the reconciler has not yet swept), so a kiosk rejection
  is occasionally a false alarm the desk has to clear.
  It sorts LAST in `_REASON_PRIORITY` — a coverage problem is more actionable.
  Sign-ups are NOT gated by it, matching the waiver precedent. **Every**
  `CheckinWarning` member must appear in `_REASON_PRIORITY`; that tuple is
  ordered by `.index`, which raises on a missing member.
- **The waiver gate** (`unsigned_waiver`,
  `checkin/sql/checkin_unsigned_waivers.sql`): a waiver required by any of
  the member's CURRENT (active/frozen) memberships' plans that they haven't
  signed at a version >= its `requires_resign` floor — the same set the
  member-detail Waivers section shows (see the `waivers-guide` skill).
  Evaluated for the member NOW, independent of the occurrence's coverage.
  Sign-ups/reservations are deliberately NOT waiver-gated — only the
  check-in.
- **Points** awarded on a NEW attendance row (`plan_id`/`item_id` nullable
  together, `chk_attendance_membership_pair`). An idempotent **repeat echoes
  `points_worth`** (reports it, balance untouched, not 0).
- **Capacity** = DISTINCT members **signed-up OR attended** for the original
  slot vs the effective `max_capacity` (`signup_capacity_count.sql`, shared
  by the gate + sign-up create — a plain two-key union, no day-window math).

`member_attendance` rows carry the identity key + a denormalized
**`occurred_at`** (the EFFECTIVE start instant) whose ONLY consumers are the
time-window SQL — streak (`streak_weeks.sql`), cycle counts
(`classes_all_memberships.sql`), `last_class`. **Streak weeks bucket in the
gym's CURRENT-local timezone, not UTC** (`streak_weeks.sql` truncates on
`occurred_at AT TIME ZONE gyms.timezone`, joined by `gym_id`; the Python
current-week anchor uses `gym_today`, mirroring the members-list gym-local
date idiom) — a live gamification convention, so it reads the gym's present
zone rather than any frozen per-version zone. It is re-synced by the two
keep-paths (same-date override; reschedule-to-past).

## 6. Sign-ups (reservations) — in the checkin domain

`class_signups(gym_id, class_id, member_id, original_date, original_time)`,
`UNIQUE(class_id, member_id, original_date, original_time)`. **A reservation
is NOT attendance** — `member_attendance` is only written by a check-in; a
signed-up member who never checks in is a no-show. `POST`/`DELETE
/api/v1/signup` (`SignupService`), auth `verify_can_view_member`
(admin/owner-for-any-gym-member OR member-for-self — trainers have no
accounts; RLS has NO authenticated write
policy). Create validates the occurrence via the version expander (real,
active, non-cancelled), stamps `original_time` from the resolved slot, runs
the union capacity gate, and is idempotent (`ON CONFLICT DO NOTHING`). The
**roster** (`GET /api/v1/checkin/attendees`) returns everyone **signed-up ∪
attended** by the original slot, each flagged `signed_up`/`attended`
(attendance fields null when not attended). The board carries
**`signup_count`** (future + past). **The member-scoped history feed**
(`GET /api/v1/checkin/history?member_id&gym_id&limit&offset`,
`CheckinHistoryService`) powers the member page's Class-history card:
`upcoming` (open reservations — occurrences not yet ENDED, soonest first,
unpaginated) + a paginated newest-first `history` of attended rows and
NO-SHOWS (a sign-up whose occurrence ended — original slot instant + the
CURRENT version's duration in its frozen tz — with no matching attendance
on the exact slot; the current-version ended-ness is a documented
approximation). Auth `verify_can_view_member`, same as streak/sign-up.

**User-facing wording is "Reserve"/"Reserved"** (the CRM), but code
identifiers stay `signup`/`signUp`/`signup_count`/`class_signups`.

## 7. The shared CheckinReverser (the one classes→checkin edge)

The per-member reversal (delete the attendance row by key + claw back points
`GREATEST(bal−p,0)` + drop the `class_attended` activity + reverse a
trial/one_time pack's auto-end) lives ONCE in **`CheckinReverser`**
(`src/checkin/`, signature `reverse(session, member_id, gym_id, class_id,
original_date, original_time, points_worth)` — the full slot key, so a
same-day sibling occurrence's row is never touched; imports nothing from
`src.classes`). Consumers: `CheckinRemover` (`DELETE /api/v1/checkin`, the
thin single-member wrapper) and `ClassesUndoService`, whose
`teardown_occurrence` (reverse attendance + delete sign-ups for one exact
slot) is itself the single teardown the cancel entry points, the
future-reschedule path, AND the versions service's wipe all route through. **This is a deliberate, documented
`classes → checkin` dependency** — the OPPOSITE of the otherwise one-way
`checkin → classes` seam — chosen so the reversal isn't duplicated. DI
builds `checkin_reverser` before all consumers; no import cycle.

## 8. CRM surfaces

- **Schedule board** (`features/schedule`): week grid of `ClassCard`s; chip
  stacks "N reserved" / (past) "M attended"; tap → chooser (This occurrence
  vs All future occurrences). Rows carry `originalDate` + `originalTime`
  (addressing) + `classDate`/`resolvedClassTime` (display) — every mutation
  call sends the full original slot.
- **Occurrence screen** (`class_occurrence_screen.dart`): view-first /
  edit (override section incl. a **date** field = reschedule); a two-tab
  **Reserved | Attended** roster; Reserve members (future) + Update
  attendees (check-in, ≤2h). When the viewed occurrence is cancelled AND
  `cancellingRangeId != null` (a range, not an instance, cancelled it), a
  **"Cancelled by a range"** section (a self-contained side read finding the
  governing range by id) replaces the read-only details block with the
  range's `start – end` plus **Edit range** / **Remove range cancellation** —
  both run through the screen's own mutation lifecycle (success dialog, then
  pop back to the reloaded board, exactly like "Cancel this class"), since
  either action can change whether this occurrence is still cancelled at all.
- **Class form** (`class_form_screen.dart`): submits the split update —
  `identity` (partial) + `schedule` (the complete shape; a no-change
  schedule is a backend no-op). Edit mode shows a **"Cancelled ranges"**
  section (`ClassCancelledRangesSection`, hidden when empty) listing the
  class's CANCEL ranges whose `end_date` is today or later, each row with
  Edit / Remove — a self-contained side read (mirrors the attendee roster's
  own-repository pattern) whose mutations dispatch through the shared
  `ScheduleBloc` (so the board reloads consistently) and confirm via a
  SnackBar rather than a full success dialog, since editing one range doesn't
  invalidate the rest of the form the way it does the occurrence screen.
  Editing a range that WIDENS coverage warns first (newly covered upcoming
  dates lose their reservations/check-ins, points reversed); removing warns
  that covered dates come back but nothing already torn down is restored.
- **Member page**: a **"Check in / Reserve"** popup — Check-in section
  (in-session + ≤2h) + past-classes toggle + Reserve section (any future
  not-yet-started).
- **Dashboard Live Attendance card** (`features/home/.../live_attendance_card/`
  + `live_attendance_*` bloc): the IN-SESSION occurrence(s)' combined
  signed-up ∪ attended roster (`/classes/instances` split by `occurredAt` +
  duration, then `/checkin/attendees` per shown occurrence) — green Checked
  In / red Not Here, falling forward to the next occurrence's reservations
  (blue Reserved) when nothing is live; 60s silent poll. Hosts its own
  loaded `ScheduleBloc` so its footer opens the REAL batch check-in dialog
  (2h window) and occurrence screen for the shown occurrence.

## 9. Gotchas / operational

- **Editing a schedule near class time is destructive by design**: a mint
  CAN move/remove a slot starting in 30 minutes — its future-keyed sign-ups
  and early check-ins are wiped (points clawed back) unless the exact slot
  survives. In-session/past occurrences are automatically safe (old-version
  ownership).
- **Accepted residual race**: a check-in that resolves against the old
  version but commits after the mint's wipe collection can strand one
  attendance row on a dead slot. `resource_locks` (per-class key) is the
  escalation path if it ever bites.
- **Migrations are HAND-WRITTEN, never `supabase db diff`** (per
  `Database/CLAUDE.md`) — edit schema files, delegate migration authoring to
  a sub-agent, the USER runs `npx supabase migration up`.
- **Points/capacity are billing-adjacent** — the reversal touches
  `members.points_balance`; edit carefully.
- **`end_date` = automatic, `cancel_date` = manual** (the terminal-date
  convention on `member_memberships`): the depletion auto-end and the
  purchase-stamped duration expiry write `end_date`; a human ending a pack
  early writes `cancel_date` (the one-time/trial `POST
  /memberships/cancel-one-time` op — `cancel_one_time` — included). The check-in reversal's un-end only ever touches
  `end_date` — restoring the duration-derived expiry (or NULL for a pure
  class-count pack), never blind-NULLing — so a manually-terminated pack
  can never be resurrected by removing an attendance.
- **The membership gate is occurrence-time-aware**: coverage
  (`covers_reference`) and cycle usage evaluate at the occurrence's
  effective start instant, so a retro check-in attributes to the
  membership that covered THAT class (an ended trial included) and counts
  against the billing cycle CONTAINING it. Current occurrences behave
  exactly as before. Historical freezes are invisible (only the current
  freeze window is stored) — a documented best-effort limit.
- The version-mint race (two edits of one class in the same instant) is
  guarded by `UNIQUE(class_id, effective_from)` → a retryable 400.

## Key files

- Producer: `src/classes/service/{classes_expander,classes_version_expander,
  classes_versions_service,classes_schedule_reader_service,
  classes_undo_service,classes_exceptions_service,classes_crud_service}.py`.
- Consumer: `src/checkin/service/{checkin_class_resolver,checkin_member_gate,
  checkin_writer,checkin_reverser,checkin_remover,signup_service,
  checkin_attendees_service,cycle_counts_service,streak_service}.py` +
  `batch_checkin_service.py`.
- Schemas: `src/classes/schema/{classes_crud_schema,classes_expander_schema,
  classes_undo_schema}.py` (`ExpanderScheduleVersion`,
  `EffectiveOccurrence.original_time/schedule_id/original_start_at`,
  `GymClassScheduleFields`, the split `GymClassUpdateRequest`);
  `src/checkin/schema/{checkin_schema,signup_schema,batch_checkin_schema}.py`
  (`ResolvedClass` — no stored-occurrence id anywhere).
- DB: `Database/supabase/schemas/{gym_classes,gym_class_schedules,
  class_instance_exceptions,class_range_exceptions,member_attendance,
  class_signups}.sql`.
- CRM: `CRM/lib/features/schedule/**`,
  `features/member_details/.../check_in/**`, `shared/widgets/class_row/**`.

## This skill is a living document

The class system changes often. When the version/mint/exception/gate/sign-up
model genuinely diverges (a new table, a renamed service, a changed rule),
update THIS file in the same change so it never goes stale.
