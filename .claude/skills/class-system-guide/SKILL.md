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
  pre-exception slot), which is what attendance and sign-ups key. Covers the
  version-ownership model (effective_from windows, first-version-owns-the-past,
  no-day-doubling dedup, the ONE pure ClassesExpander wrapped by
  ClassesVersionExpander), the MINT engine (ClassesVersionsService — schedule
  edits mint a version effective NOW and wipe future-keyed rows unless the
  exact wall-clock slot survives; soft-delete wipes everything future; a gym
  timezone change re-mints per class), exceptions binding to original slots
  (reschedule-to-any-date, time-aware collision, attendance wipe-future /
  keep-and-resync-past), the warn-first check-in gate (is_member kiosk-reject
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
  `max_capacity`, `image_url`, `points_worth`, `is_active`, `is_deleted`.
  Identity applies across all time — a rename renames the past too.
- **`gym_class_schedules`** (versions): the schedule shape — `class_time`,
  `duration_minutes`, recurrence (`recurring_unit`/`interval`, the 7 weekday
  flags + 7 per-weekday instructor slots), `start_date`/`end_date` (the
  recurrence range) — plus `effective_from` (the version boundary, a
  timestamptz: many edits can land in one day) and `timezone` (the gym's
  IANA zone FROZEN at mint). Rows are write-once; there is no
  `effective_until` — a version's coverage window is
  `[effective_from, next version's effective_from)`, derived. The
  `gym_class_schedules_current` view surfaces the latest version per class
  (used by class CRUD reads; window reads always load ALL versions).

**Occurrences are never stored.** Every read — past and future — computes
them from the versions + exceptions. The past is immutable because past
versions never change: re-expanding them is deterministic (each version
expands in its OWN frozen timezone, so nothing can re-derive differently).

**Occurrence identity = the ORIGINAL slot**: `(class_id, original_date,
original_time)` — the date + the owning version's `class_time`, BEFORE
exceptions, gym-local wall clock. `member_attendance` and `class_signups`
store this key verbatim; an exception (retime / reschedule / cancel) NEVER
re-keys anything, so sign-ups and attendance follow the occurrence wherever
it moves. **Every API call addresses an occurrence by `class_id +
occurrence_date` where the date is the ORIGINAL date** (the board row carries
`original_date` for exactly this; `class_date` is the effective display
date).

**Version ownership rule** (the pure `ClassesVersionExpander`):
a version owns candidate `(D, class_time)` iff its original instant —
`combine(D, class_time, ZoneInfo(version.timezone))` — falls in the
version's window. Three refinements:
1. The FIRST version owns back to −∞ (its `effective_from` is just its mint
   stamp), so a class created with a backdated `start_date` renders its past.
2. The LAST version owns to +∞ — there is exactly one present/future owner
   (a mint is always effective NOW; future-dated takeovers don't exist).
3. **No day doubling**: when two adjacent versions both produce a candidate
   on the same gym-local date (the old one already started before the mint),
   the EARLIER version wins the date. ≤1 ORIGINAL occurrence per class per
   gym-local date is a formal invariant — it's what makes date-only API
   addressing and the `UNIQUE(..., original_date)` keys unambiguous.
   (Effective-date doubling via reschedule — two occurrences *displayed* on
   one day with different original dates — remains allowed.)

**`ClassesExpander` is still the ONE pure recurrence+exception engine** (no
I/O; instance-wins-over-range precedence, monthly last-day clamp, DST via
`ZoneInfo`, cancelled dropped or emitted flagged; `instructor_for` public).
`ClassesVersionExpander` wraps it per version and adds ownership windowing +
the date dedup, tagging each `EffectiveOccurrence` with `original_time`, the
owning `schedule_id`, and `original_start_at`. The demo seed MIRRORS both —
never re-derive recurrence anywhere else.

## 1. The MINT engine — how a schedule ever changes

**`ClassesVersionsService` (`src/classes/service/classes_versions_service.py`)
is the only writer of `gym_class_schedules`.** A mint runs in ONE transaction:

1. **Deep-equal no-op**: a submission equal to the current version (all shape
   fields AND the timezone) mints nothing, wipes nothing.
2. Insert the version, `effective_from` = server now, `timezone` = the gym's
   current zone.
3. **The WIPE decides per occurrence DATE.** A date is a candidate when its
   ORIGINAL slot instant is at/after the mint (a slot that already started
   is never touched; the old version owns it forever). A candidate is then
   LEFT ALONE when any of these hold:
   - its exception is a **CANCELLATION** — date-keyed intent ("this date is
     off") that survives any shape change; deleting it would silently
     revive the cancelled occurrence;
   - its **EFFECTIVE start** (the reschedule/retime target) is before the
     mint — the occurrence already RAN (rescheduled into the past); its
     attendance is real and the exception row anchors it;
   - the new version still emits the date at the exact same wall-clock
     `original_time` (the exact-slot match).
   Otherwise the date is torn down via the undo service's shared
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

`class_instance_exceptions` (keyed `UNIQUE(class_id, original_date)`)
overrides or cancels ONE original slot (incl. `new_date` = reschedule target
— any date, `new_max_capacity`, `new_class_time`, `new_instructor_id`,
`new_duration_minutes`); `class_range_exceptions` cancels/substitutes a
continuous range. An exception binds to whatever slot the owning version
defines on its `original_date`; override fallbacks (time / duration / the
weekday instructor) resolve against the OWNING version — a retro edit on an
old-version date falls back to THAT version's defaults
(`ClassesUndoService.owning_version` / `resolve_default_instructor`).

**"Immutable past" applies to schedule-VERSION edits only.** Past-dated
exceptions, cancel-past, reschedule-to-past, and retroactive check-ins are
all supported — the exception layer is how the past gets corrected.

## 3. The board — one computation for everything

`ClassesScheduleReaderService` (`GET /api/v1/classes/instances`): load every
class (deleted included) + ALL versions + the window's exceptions
(concurrently, via `asyncio.gather`), expand via `ClassesVersionExpander`
with `include_cancelled=True`, enrich with instructor names, per-date
capacity overrides, and the attendance / sign-up counts (both keyed
`(class_id, original_date)` — plain GROUP BYs, no joins). No
stored-occurrence side, no past/live split, no dedup pass.
**Cross-window reschedules render via WIDENING**: the exception load also
returns rows whose `new_date` falls in the window; each class expands over
bounds stretched to its exceptions' original/target dates; the result is
filtered back to the view window by EFFECTIVE date — a moved-in occurrence
renders here (counts still load, keyed by its out-of-window original date),
a moved-out one renders only in its target window. The one time-dependent
rule: a soft-deleted class emits only occurrences whose END (`occurred_at`
+ duration) is at/before now. Board rows carry `original_date` (addressing)
alongside `class_date` (display).

## 4. Cancel / reschedule — any date, keys never change

One shared engine on `ClassesUndoService` (`ClassesExceptionsService`
delegates its `new_date` upserts to it, so the two entry points can't
diverge):

- **Cancel** — TWO entry points, ONE teardown: the dedicated
  `DELETE /{class_id}/occurrences/{original_date}` endpoint AND an exception
  upsert with `is_cancelled=true` (the CRM's "Cancel this class") both run
  `ClassesUndoService.teardown_occurrence` — reverse the occurrence's
  attendance (points clawed back), DELETE its sign-ups (a cancelled
  occurrence can't be attended — dead rows otherwise) — then write the
  cancelled exception, all in one transaction.
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

`CheckinClassResolver.resolve(class_id, gym_id, occurrence_date)` loads the
class identity, resolves the occurrence through the shared
**`CheckinOccurrenceResolution.resolve_original`** — the ONE original-date
resolution algorithm (versions + exceptions → the version expander, with
the reschedule window-widening) that the sign-up service also injects, so
check-in and sign-up can never disagree about whether an occurrence exists —
and returns a `ResolvedClass` (`occurrence_date` = original date,
`original_time`, effective `occurred_at`, effective capacity, points, plan
gate inputs). Purely a read — nothing is written until the gate records.
The **2h early-check-in window** (`settings.checkin_opens_hours_before_start`)
rejects an occurrence starting >2h out. Retroactive any-date check-ins work
(the resolver validates against whichever version owned that date).

`CheckinMemberGate.checkin_member(resolved_class, member_id, is_member,
ignore_warnings)`:
- **`is_member=True`** (kiosk / member self) — strict: a blocking condition
  (`no_membership | out_of_classes | ineligible_plan | over_capacity`)
  **rejects** (`skip_reason`, nothing written).
- **`is_member=False`** (staff, CRM default) — a clean check-in records, but
  a warned one is **NOT recorded**: `requires_confirmation=true` +
  `warnings`; resend with **`ignore_warnings=true`** to record
  (best-available / NULL attribution). Batch has a `needs_confirmation` item
  status.
- **Points** awarded on a NEW attendance row (`plan_id`/`item_id` nullable
  together, `chk_attendance_membership_pair`). An idempotent **repeat echoes
  `points_worth`** (reports it, balance untouched, not 0).
- **Capacity** = DISTINCT members **signed-up OR attended** for the original
  slot vs the effective `max_capacity` (`signup_capacity_count.sql`, shared
  by the gate + sign-up create — a plain two-key union, no day-window math).

`member_attendance` rows carry the identity key + a denormalized
**`occurred_at`** (the EFFECTIVE start instant) whose ONLY consumers are the
time-window SQL — streak (`streak_weeks.sql`), cycle counts
(`classes_all_memberships.sql`), `last_class` — all joins-free now. It is
re-synced by the two keep-paths (same-date override; reschedule-to-past).

## 6. Sign-ups (reservations) — in the checkin domain

`class_signups(gym_id, class_id, member_id, original_date, original_time)`,
`UNIQUE(class_id, member_id, original_date)`. **A reservation is NOT
attendance** — `member_attendance` is only written by a check-in; a
signed-up member who never checks in is a no-show. `POST`/`DELETE
/api/v1/signup` (`SignupService`), auth `verify_can_view_member`
(staff-for-any-gym-member OR member-for-self; RLS has NO authenticated write
policy). Create validates the occurrence via the version expander (real,
active, non-cancelled), stamps `original_time` from the resolved slot, runs
the union capacity gate, and is idempotent (`ON CONFLICT DO NOTHING`). The
**roster** (`GET /api/v1/checkin/attendees`) returns everyone **signed-up ∪
attended** by the original slot, each flagged `signed_up`/`attended`
(attendance fields null when not attended). The board carries
**`signup_count`** (future + past).

**User-facing wording is "Reserve"/"Reserved"** (the CRM), but code
identifiers stay `signup`/`signUp`/`signup_count`/`class_signups`.

## 7. The shared CheckinReverser (the one classes→checkin edge)

The per-member reversal (delete the attendance row by key + claw back points
`GREATEST(bal−p,0)` + drop the `class_attended` activity + reverse a
trial/one_time pack's auto-end) lives ONCE in **`CheckinReverser`**
(`src/checkin/`, signature `reverse(session, member_id, gym_id, class_id,
original_date, points_worth)`, imports nothing from `src.classes`).
Consumers: `CheckinRemover` (`DELETE /api/v1/checkin`, the thin single-member
wrapper) and `ClassesUndoService`, whose `teardown_occurrence` (reverse
attendance + delete sign-ups for one date) is itself the single teardown the
cancel entry points, the future-reschedule path, AND the versions service's
wipe all route through. **This is a deliberate, documented
`classes → checkin` dependency** — the OPPOSITE of the otherwise one-way
`checkin → classes` seam — chosen so the reversal isn't duplicated. DI
builds `checkin_reverser` before all consumers; no import cycle.

## 8. CRM surfaces

- **Schedule board** (`features/schedule`): week grid of `ClassCard`s; chip
  stacks "N reserved" / (past) "M attended"; tap → chooser (This occurrence
  vs All future occurrences). Rows carry `originalDate` (addressing) +
  `classDate` (display) — every mutation call sends `originalDate`.
- **Occurrence screen** (`class_occurrence_screen.dart`): view-first /
  edit (override section incl. a **date** field = reschedule); a two-tab
  **Reserved | Attended** roster; Reserve members (future) + Update
  attendees (check-in, ≤2h).
- **Class form** (`class_form_screen.dart`): submits the split update —
  `identity` (partial) + `schedule` (the complete shape; a no-change
  schedule is a backend no-op).
- **Member page**: a **"Check in / Reserve"** popup — Check-in section
  (in-session + ≤2h) + past-classes toggle + Reserve section (any future
  not-yet-started).

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
- Undo's auto-end reversal can't distinguish an auto-end from a manual end
  on a below-capacity trial/one_time pack (no stored link) — a future
  `auto_ended` flag would make it airtight.
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
