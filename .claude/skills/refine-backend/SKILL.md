---
name: refine-backend
description: >-
  The POST-BUILD audit for a backend domain build or heavy refactor (tables +
  services + routes + their CRM surface). Run it AFTER the build reaches "it
  works" and BEFORE hand-off: walk the audit passes over what was just built
  and fix what they catch. Distilled from the founder's real corrections
  across two heavy refactors (the VideoService→backend merge and the
  class-system build) — every item is something he actually flagged and will
  flag again. Domain-agnostic: video/classes appear only as examples. Trigger
  on "refine the backend", "audit what we built", "clean it up before the
  PR", "post-build pass", finishing any task that added or reshaped a
  domain's tables + services + endpoints, or preparing such work for review.
---

# Refine Backend — the post-build audit

Run this when a domain build or refactor **works** and is about to be handed
off. It is not a build guide: it assumes the code exists and asks what the
founder's review would catch. Walk every pass; each item below was flagged in
a real refactor, so treat a hit as "will be flagged again", not a judgment
call.

The house rules themselves (service-file layout, no inline SQL/prompts, DI,
enums, naming prefixes, the pre-build gates) live in the root and per-system
CLAUDE.md files — this skill doesn't restate them. It covers the layer above:
the design shapes that real builds drifted into even while following the
rules.

---

## 1. Schema audit

The recurring direction is **fewer tables, fewer columns, more history**.

- **Could any table collapse into a column?** No junction table when a JSONB
  column does the job. *(Search queries became a JSONB list on the spec row —
  the separate `gym_video_query` table was the flagged shape: "it shouldnt
  even be a separate table, it should just be a jsonb string list.")*
- **Could any column pair collapse into one generalized column?** Split
  per-case columns are the smell. *(`rejection_type` + `acceptance_type`
  collapsed into one `curation_type`; `reject_reason` + `accept_reason` into
  one `curation_reason` — the status column already tells reject from
  accept.)*
- **Is config-like data versioned instead of mutated?** Append-only version
  rows + a `latest` view beat in-place upserts: full audit trail, readers
  always hit the view, and automated writers (refiners, imports) mint
  versions transparently. *(gym_video_spec + gym_video_spec_latest; video_run
  for scan runs.)*
- **Does every field live where its property lives?** *(Deletability was a
  property of the video, not the feed row — `added_via` moved to the pool
  table: "it should be on the video table, and that's how you mark what can
  be removed.")* Source/ownership belongs on the source entity, not on the
  relationship.
- **Is the audit trail in-row and flip-proof?** No separate removal-log
  table; the audit fields (`curation_type`, reason, timestamp) sit on the row
  itself and **survive state flips** — re-accepting keeps the prior rejection
  audit so the back-and-forth history stays legible. *(The
  `gym_video_feed_removal` side table was dropped for exactly this shape.)*
- **Do attribution columns track HOW, not WHO, when mechanism is the
  load-bearing fact?** *(A `rejected_by` UUID became an `(automatic|manual)`
  enum — the question that matters is scan-vs-human, not which human.)*
- **Are optional attributions nullable-with-CHECK, not forced?**
  *(Attendance without a membership: `plan_id`/`item_id` nullable with a
  both-or-neither CHECK; a CHECK forcing `rejection_type` present when the
  status is rejected. Constraints encode the shape; reading queries skip the
  NULL rows.)*
- **Are derived numbers clamped at read?** Internal over-draw may exist, but
  a count query never returns a negative — `GREATEST(x, 0)`. *("the count
  should never be negative when querying, max it at 0.")*
- **Are all schema types in schema files?** No dataclasses or type aliases
  defined inside service files — Pydantic models belong in the domain's
  `schema/` package. *(GateEvaluation and VideoAgentOutput were both moved.)*
- **Were all migrations hand-written?** (The rule lives in
  `Database/CLAUDE.md`.) The audit angle: don't leave convenience targets
  that tempt auto-diffing either. *(A replacement `migration new` Make target
  was rejected: "you can remove it dont replace it with anything.")*

## 2. Service-layout audit

- **Is any general service written FOR a special consumer?** An agent,
  worker, or job is a thin wrapper that *uses* the domain's regular services;
  nothing in the regular services exists strictly for it. *("Nothing the
  agent skills should be strictly for the agent.")*
- **Is the layering one-way with no cycles?** Wrapper → facade → concern
  services; the regular services never call back up into the wrapper.
  *("video_feed_refiner should never call video_agent — never the other way
  around.")*
- **Is the facade pure delegation — and does it earn its existence?** Zero
  business logic in the facade; logic lives in the concern services it
  composes ("all the methods should be facade like, it cant have logic"). And
  the inverse: a facade that only forwards to one or two seams shouldn't
  exist — delete it and let callers wire the seams via DI. *("checkin service
  shouldnt exist, just use the gate.")*
- **Is shared infrastructure in `src/shared/`?** The moment a second consumer
  is plausible, it isn't domain code anymore. *("litellm should be shared,
  not specific to videos.")*
- **Any bare functions or side-channel config?** Helpers live inside service
  classes, construction is wired in the DI container, and configuration comes
  from the global settings object — never per-domain key-loading helpers or
  `os.environ` tricks. *("this should be in the di, why is it here… we have a
  config globally, why are we using this.")*
- **Does every feature sit in the domain that owns its concern?** Working
  code in the wrong domain still gets flagged. *(Showcase moved out of videos
  into a net-new theme domain — "I had nothing to do with videos, having it
  here is bad and confusing"; the template catalog moved from videos to
  presets.)*
- **Is every deliberate layering exception named where it lives?** One
  classes→checkin call reverses the documented one-way rule because every
  alternative was worse — "sub ideal, but cleanest in this situation." Fine,
  but only if the doc says so; never smuggle the exception.

## 3. Naming audit

- **Do names describe semantics, not mechanism?** *(`web_query` not `preset`
  — the videos come from the scrape's queries, the preset just copies them;
  `is_member` not `is_kiosk` — the subject matters, not the device.)*
- **Did any name outgrow its first case?** Generalize the moment a second
  case appears rather than minting a sibling column or enum.
  *(`rejection_type` → `curation_type` when accepts needed the same
  tracking: "it shouldnt be rejection… it needs to be generalized.")*
- **Conversely: is a rename actually worth it?** A 20-file cosmetic rename of
  internal-only identifiers was rejected as churn — "honestly its fine,
  checkin and sign up are close enough." Rename user-facing strings; leave
  internal names that are close enough alone.

## 4. API & flow audit (incl. LLM/agent surfaces)

- **Is everything that CAN be deterministic, deterministic?** Anything that
  runs as plain code after a user decision (diff-check → derived generation →
  save) is backend code, not an agent tool or an extra LLM step. The agent
  converses; the commit path is code. *("queries is not a tool, its something
  done always AFTER the conversation is done, the end user never sees it.")*
- **Is expensive derived work diff-gated?** Only regenerate when the accepted
  input actually changed. *("only run the query if there is actually a diff…
  to save money.")*
- **Is the LLM provider swappable, and is each call on the right layer?**
  Single-shot structured calls on the plain LLM client; an agent framework
  only for the conversation. Don't unify frameworks for tidiness. *("litellm
  is for the api regular communication with llm, pydantic is simply for the
  agent.")*
- **Is anything silent or terminal in a conversational flow?** Every proposal
  pairs with a message; every outcome (save/reject/error) lands as a
  persistent record in the chat/UI, not a vanishing banner; a successful save
  invites the next edit instead of ending the session. *("the convo can
  continue and the agent should ask if it can do anything else.")*
- **Are model outputs the UI must render bounded?** *(Multi-choice options
  capped at 6 via `Field(max_length=6)`.)*
- **Is pagination in SQL?** `LIMIT/OFFSET` + `COUNT(*) OVER()` in the query —
  never load-all-then-slice in Python. *(`videos[offset:offset+limit]` over a
  full feed load was the flagged shape.)*

## 5. Behavior-semantics audit

These were flagged every time they were left implicit — check each one got an
explicit decision:

- **Do boundaries anchor on the real event, not a calendar convenience?**
  "Past" means *ended* (`start + duration <= now`) — not started, and not gym
  midnight. An in-session occurrence is current, not history. *("just include
  any class that is still ongoing, it has an end time.")*
- **Are similar-looking states actually distinct?** Sign-ups silently
  becoming "attended" at midnight was a caught design flaw — a reservation is
  not an attendance. If two concepts share a table, the split must be
  explicit and visible.
- **Are overlapping windows allowed where they're correct?** Reserve = any
  future occurrence; check-in = in-session + a short look-ahead. The overlap
  is intentional — don't force mutual exclusivity for tidiness. *("no you can
  reserve even for any class in the future at all.")*
- **Is every irreversibility decided consciously?** Points, once awarded, are
  never clawed back — they may already be spent. Uncancel restores the slot
  but not the wiped attendees. And every destructive action warns that it is
  **not restorable**, "no matter what."
- **Do gates block members but warn staff?** Hard gates (capacity, coverage)
  error on member/kiosk paths; staff paths always record, with the same
  failures downgraded to warnings plus an override. Model it as an
  `is_member` semantic flag, not as auth.
- **Does the UI re-guard anything the service allows?** If the backend
  permits cancelling any date, the UI adds no date window on top — "we dont
  need a ui guard, if they want to cancle let them cancle."

## 6. Production-readiness audit

- **Any demo-only code path left?** A preset/demo/import works through the
  exact production write path and produces production-shaped data — "the
  preset should not work specially AT ALL. No custom logic for it. This is
  going to be prod code."
- **Any mock or placeholder data left?** Real entities end-to-end. *("no more
  demo anything, their videos need to be actual videos on youtube.")*
- **Is seed/demo data realistic and complete?** Varied times, a month of
  history, a week of future state, an empty/light/busy mix — the demo is the
  sales surface, so partial seeding reads as a broken product.
- **Was anything deleted because it "looked unused"?** Trace every consumer
  first; one "unused" field turned out to feed three surfaces. Looks-unused
  is not confirmed-dead.

## 7. Verification & hand-off

- **Did it run end-to-end against the live backend?** Hit the real routes,
  then check the DB state they produced. Ownership, cascade, and removal
  semantics only prove out e2e — unit tests and lint don't catch a data
  contract that's wrong in practice.
- **Did money- or capacity-adjacent logic get the edge-case pass?**
  At-capacity, idempotent repeat, unlimited-never-blocks, override paths,
  no-show holds — verified AND locked with regression tests. "Just make sure
  all the edge cases are handled" is a standing order.
- **Do tests clean up exactly what they create — and only that?** Guard
  shared rows with existence checks; never delete seed data something else
  still references.
- **Is the hand-off report complete?** If review found 12 issues, the report
  lists 12 — not 7 with 5 bundled into one line. Truncation reads as
  concealment. *("you only outputed 7 of the 12 confirmed.")*

## 8. Docs-sync audit

- **Did every doc that describes the changed system update in this change?**
  The domain's CLAUDE.md, the relevant skill, both README graphs +
  `architecture.mermaid`, and any memory notes. Stale docs cause false review
  findings and mislead the next contributor.
- **Does every rule have exactly one home?** Never restate a CLAUDE.md rule
  in a skill, memory, or second doc — point to it instead. *("why do we need
  a memory for this, its alr in the claude.md.")* Duplication is drift
  waiting to happen.

---

*This skill is a living document. When a build's review surfaces a new
recurring flag — or reality outgrows an item here — update this file in the
same change.*
