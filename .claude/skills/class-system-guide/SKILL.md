---
name: class-system-guide
description: >-
  The single source of truth for the CombatDen CLASS SYSTEM — scheduling (the
  producer) + attendance/reservations (the consumer) across two FastApiBackend
  domains and the CRM schedule surfaces. THE CENTRAL SPLIT (§0): every occurrence
  is either MATERIALIZED (a class_history row, immutable, typically past) or
  VIRTUAL (expander-computed, typically future) — every feature must handle both
  sides, and getting only one is the recurring bug. Covers the virtual-occurrence
  model
  (gym_classes recurrence + class_instance/range_exceptions + the ONE pure
  ClassesExpander), materialization into class_history (the single
  ClassesMaterializer.materialize(gym,start,end) entry + materialize_current +
  settings.materialize_future_hours=2; lazy-at-check-in / board-read /
  reconciler-sweep; idempotent find_or_create_history ON CONFLICT), the
  past-from-history / future-from-expander board split, reschedule-to-any-date
  (time-aware collision + attendance wipe-future / keep-and-redate-past), the
  warn-first check-in gate (is_member kiosk-reject vs staff requires_confirmation
  unless ignore_warnings; the 2h early-check-in window; points award + repeat
  echo), the SIGN-UPS/reservations model (class_signups ≠ member_attendance;
  capacity-reserving distinct signed-up-or-attended union; the combined roster),
  and the shared CheckinReverser (the one deliberate classes→checkin dependency).
  Read before touching src/classes/, src/checkin/, or the CRM schedule feature.
---

# The Class System — scheduling + attendance + reservations

Two backend domains + the CRM schedule feature. **`src/classes/`** = the
**producer** (class CRUD, the recurrence/exception engine, the schedule board,
un-occur/reschedule, materialization). **`src/checkin/`** = the **consumer**
(the per-member gate + write, batch check-in, attendee roster, streak, cycle
usage, and **sign-ups/reservations**). The routes stayed `/api/v1/checkin*` +
`/api/v1/signup` + `/api/v1/streak` (a proposed `checkin→attendance` rename was
dropped — the domain is still `checkin`).

## 0. THE CENTRAL SPLIT — materialized vs virtual (read this first)
**Every occurrence is in one of two states, and this split is the center of the
whole system — every feature must handle BOTH cases:**

- **VIRTUAL** — no `class_history` row. The occurrence exists only as a
  computation from the recurrence + exceptions (the `ClassesExpander`). Default
  for future (and any not-yet-touched) occurrences. It follows the live class
  definition — edit the class and the virtual occurrence changes.
- **MATERIALIZED** — has a `class_history` row (`find_or_create_history`, created
  lazily at check-in / on a board read of an ENDED occurrence / by the reconciler
  sweep). Past/happened occurrences are materialized so they're an **immutable
  snapshot**; `member_attendance` references `class_history_id`. It no longer
  follows the class definition — editing the class does NOT change a past
  occurrence.

**How each part handles both sides — the load-bearing table:**

| Part | VIRTUAL (typically future) | MATERIALIZED (typically past) |
|---|---|---|
| Board read (§3) | expand the live definition | render from `class_history` (immutable) |
| Check-in (§5) | materialize the exact occurrence FIRST (any date), then gate | row exists → gate + write attendance |
| Edit / override (§2) | write only the exception; materialize-on-read applies it later | ALSO **sync the `class_history` snapshot** or the edit won't show |
| Reschedule (§4) | move the exception; no attendance to move | **wipe** (future target) or **keep + re-date** the history + attendance |
| Sign-ups (§6) | keyed by `(class_id, occurrence_date)` — needs NO `class_history` | same key; roster/capacity join attendance via `class_history` |
| Roster (§6) | sign-ups exist with no history row → don't short-circuit on missing history | sign-ups ∪ attendance |
| Capacity (§5) | count sign-ups by date | count sign-ups by date ∪ attendance via `class_history` |

**The recurring bug shape:** code that assumes an occurrence is EITHER always a
`class_history` row OR always an expander computation. It's neither universally —
which side you're on depends on whether it's been materialized yet. A past edit
that only writes an exception (forgetting the snapshot sync), a sign-up path that
short-circuits when `class_history` is absent, a board that re-expands the past —
all are the same mistake: handling one side and not the other.

## 1. The occurrence model — occurrences are VIRTUAL
A class's occurrences are not rows; they're computed. `gym_classes` embeds the
recurrence (start_date/end_date, recurring_interval, per-weekday time slots);
`class_instance_exceptions` (keyed `UNIQUE(class_id, original_date)`) overrides or
cancels ONE date (incl. `new_date` = reschedule target, `new_max_capacity`,
`new_class_time`, `new_instructor_id`, `new_duration_minutes`);
`class_range_exceptions` cancels/substitutes a continuous range.

**`ClassesExpander` (`src/classes/service/classes_expander.py`) is the ONE pure
recurrence+exception engine** (no I/O). It's used by CRUD reads, materialization,
reschedule-collision checks, AND mirrored by the demo seed — never re-derive
recurrence anywhere else. Instance-exception-wins-over-range precedence; monthly
last-day clamp; `ZoneInfo(gym.timezone)` DST; cancelled dropped. `instructor_for`
is public (weekday-slot lookup) so the snapshot-sync fallback can't drift from it.

## 2. Materialization — ONE entry, idempotent, called broadly
Materializing = writing a `class_history` row (append-only, `UNIQUE(class_id,
occurred_at)` — the idempotency anchor). **`ClassesMaterializer`
(`src/classes/service/classes_materializer.py`):**
- `find_or_create_history(...)` — the only writer, `INSERT … ON CONFLICT DO
  NOTHING`. Never insert `class_history` elsewhere (except the seed).
- `materialize(gym_id, start_date, end_date)` — the single range entry: load the
  gym's classes + exceptions, expand via `ClassesExpander`, find-or-create each
  non-cancelled occurrence, with a **forward cutoff `occurred_at <= now +
  settings.materialize_future_hours (=2)` applied inside** so a wide display
  window never freezes not-yet-started classes. `materialize_current(gym)` =
  `materialize(gym, today − class_history_lookback_days, today + future_hours)`.
- **Three callers route through it:** check-in (`CheckinClassResolver.resolve` →
  `materialize(gym, occurrence_date, occurrence_date)` then find-or-create the
  exact occurrence — **any date, incl. retroactive**, works because it's
  range-parameterized), the schedule board read, and the reconciler sweep
  (`ClassHistorySweep` → `materialize_current` per gym). Config is injected via
  the container (no `import settings` in the service).

**Editing a materialized occurrence syncs its `class_history` snapshot** —
`ClassesUndoService.sync_history_snapshot` updates `occurred_at + duration_minutes
+ instructor_id` (SQL `classes_history_snapshot_sync.sql`, service_role UPDATE).
Called by BOTH the same-date override (`ClassesExceptionsService`) AND the
reschedule keep-path. **Why it's load-bearing:** the past board renders from the
immutable `class_history` row, NOT by re-expanding, so a past edit that only wrote
an exception wouldn't show — the snapshot sync is what makes it show.

## 3. The board past/future split
The schedule board (`ClassesScheduleReaderService`, `GET /api/v1/classes/instances`)
splits at the occurrence's **END** time (`occurred_at + duration`, `_has_ended`):
a strictly-ENDED occurrence renders from **`class_history`** (immutable, incl.
soft-deleted classes — `classes_board_past_history.sql`); an in-session or future
one renders from the **live expander**. Opening the board (and the dashboard's
Upcoming Classes, whose window reaches ~7d into the recent past) MATERIALIZES
ended-but-unrecorded occurrences via `materialize`. Dedup is by (class_id, gym-local
day), so re-timing a class never doubles a past day.

## 4. Reschedule — any date, attendance follows
A move writes an instance exception with `new_date` (POST `/exceptions/instance`;
the forward-only DB CHECK was dropped — `new_date` is any date). `original_date`
is only the anchor. **One shared engine on `ClassesUndoService`**
(`ClassesExceptionsService` delegates); `assert_no_reschedule_conflict` is
**time-aware** — a move is rejected only if the exact target date+time
(`occurred_at`) is already taken (landing on a busy day at a different time is
fine). `apply_reschedule_attendance`: a **future** `new_date` **wipes** the moved
occurrence's check-ins (shared `_wipe_occurrence`, same teardown as
`cancel_occurrence`) + claws back points; a **today/past** `new_date` **keeps** them,
re-dated via the snapshot sync. All in one transaction with the exception write.

## 5. The check-in gate — warn-first
`CheckinMemberGate.checkin_member(resolved_class, member_id, is_member,
ignore_warnings)` (note: `ResolvedClass` is the resolved-occurrence type;
`CheckinClassResolver.resolve` produces it — NOT "OccurrenceContext"/"ctx"):
- **`is_member=True`** (kiosk / member self) — strict: a blocking condition
  (`no_membership | out_of_classes | ineligible_plan | over_capacity`) **rejects**
  (`skip_reason`, nothing written).
- **`is_member=False`** (staff, CRM default) — a clean check-in records, but a
  warned one is **NOT recorded**: `requires_confirmation=true` + `warnings`;
  resend with **`ignore_warnings=true`** to record (best-available / NULL
  attribution). The CRM offers "Check in anyway". Batch has a `needs_confirmation`
  item status.
- **2h early-check-in window** (`settings.checkin_opens_hours_before_start`):
  `CheckinClassResolver` rejects an occurrence starting >2h out before materializing.
- **Points** awarded on a NEW attendance row (membership or not → `member_attendance`
  `plan_id`/`item_id` nullable together, `chk_attendance_membership_pair`). An
  idempotent **repeat echoes `points_worth`** (reports it, balance untouched, not 0).
- **Capacity** = DISTINCT members **signed-up OR attended** vs the effective
  `max_capacity` (`signup_capacity_count.sql`, shared by the gate + sign-up create).

## 6. Sign-ups (reservations) — NEW, in the checkin domain
`class_signups(gym_id, class_id, member_id, occurrence_date)`,
`UNIQUE(class_id, member_id, occurrence_date)`. **A reservation is NOT attendance**
— `member_attendance` is still only written by a check-in; a signed-up member who
never checks in is a no-show. `POST`/`DELETE /api/v1/signup` (`SignupService`), auth
`verify_can_view_member` (staff-for-any-gym-member OR member-for-self; RLS has NO
authenticated write policy). Create **validates the occurrence** (real, active,
non-cancelled via the expander with `include_cancelled=True`, no materialization)
+ the union capacity gate + idempotent `ON CONFLICT DO NOTHING`. The **roster**
(`GET /api/v1/checkin/attendees`) returns everyone **signed-up ∪ attended**, each
flagged `signed_up`/`attended` (attendance fields null when not attended). The
board carries **`signup_count`** (future + past). Both the demo seed
(`generate_class_signups`) and the **preset import** (`PresetsService`) seed
realistic past+future reservations.

**User-facing wording is "Reserve"/"Reserved"** (the CRM), but code identifiers
stay `signup`/`signUp`/`signup_count`/`class_signups`.

## 7. The shared CheckinReverser (the one classes→checkin edge)
The per-member reversal (delete attendance + claw back points `GREATEST(bal-p,0)`
+ drop the `class_attended` activity + reverse a trial/one_time pack's auto-end)
lives ONCE in **`CheckinReverser`** (`src/checkin/`, operates on a known
`class_history_id`, imports nothing from `src.classes`). `CheckinRemover`
(`DELETE /api/v1/checkin`) is the thin single-member wrapper; `classes_undo`'s
`_wipe_occurrence` loops the reverser per attendee. **This is a deliberate,
documented `classes → checkin` dependency** — the OPPOSITE of the otherwise
one-way `checkin → classes` seam (chosen so the reversal isn't duplicated). DI
builds `checkin_reverser` before both consumers; no import cycle.

## 8. CRM surfaces
- **Schedule board** (`features/schedule`): week grid of `ClassCard`s; chip stacks
  "N reserved" / (past) "M attended" on separate lines; tap → chooser (This
  occurrence vs All future).
- **Occurrence screen** (`class_occurrence_screen.dart`): view-first (read-only
  details + **Edit** and **Cancel this class** side by side) / edit (override
  section incl. a **date** field = reschedule); a two-tab **Reserved | Attended**
  roster; a **Reserve members** action (future) + Update attendees (check-in, ≤2h).
- **Member page**: a **"Check in / Reserve"** popup — Check-in section (in-session
  + ≤2h) + a "Show past classes" toggle (recent→old) + Reserve section (any future
  not-yet-started; intentionally overlaps the 2h check-in window).

## 9. Gotchas / operational
- **The board 500s for everyone until `class_signups` exists** (it joins the table
  for `signup_count`). Run the migration.
- **Migrations are HAND-WRITTEN, never `supabase db diff`** (per `Database/CLAUDE.md`)
  — edit schema files, delegate migration authoring to a sub-agent, the USER runs
  `npx supabase migration up`.
- **Points/capacity are billing-adjacent** — the reversal touches
  `members.points_balance`; edit carefully.
- Undo's auto-end reversal can't distinguish an auto-end from a manual end on a
  below-capacity trial/one_time pack (no stored link) — a future `auto_ended` flag
  would make it airtight.

## Key files
- Producer: `src/classes/service/{classes_expander,classes_materializer,
  classes_schedule_reader_service,classes_undo_service,classes_exceptions_service,
  classes_crud_service}.py`.
- Consumer: `src/checkin/service/{checkin_class_resolver,checkin_member_gate,
  checkin_writer,checkin_reverser,checkin_remover,signup_service,
  checkin_attendees_service,cycle_counts_service,streak_service}.py` +
  `batch_checkin_service.py`.
- Schemas: `src/checkin/schema/{checkin_schema,signup_schema,batch_checkin_schema}.py`
  (`ResolvedClass`, `CheckinRequest/Response` + `ignore_warnings`/
  `requires_confirmation`/`class_streak_weeks`); `src/classes/schema/*`.
- DB: `Database/supabase/schemas/{gym_classes,class_instance_exceptions,
  class_range_exceptions,class_history,member_attendance,class_signups}.sql`.
- CRM: `CRM/lib/features/schedule/**`, `features/member_details/.../check_in/**`,
  `shared/widgets/class_row/**`.

## This skill is a living document
The class system changes often. When the occurrence/materialize/reschedule/gate/
sign-up model genuinely diverges (a new table, a renamed service, a changed rule),
update THIS file in the same change so it never goes stale.
