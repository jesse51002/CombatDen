---
name: refine-backend
description: >-
  The POST-BUILD audit for a backend domain build or heavy refactor (tables +
  services + routes + their CRM surface). Run it AFTER the build reaches "it
  works" and BEFORE hand-off: walk the audit passes over what was just built
  and fix what they catch. Distilled from the founder's real corrections across
  many heavy refactors (the VideoService→backend merge, the class-system build,
  the billing/memberships/discounts/Stripe-sync/reconciler/seed work, and the
  employees/roles + video-worker + rank + analytics/reports builds) — every
  item is something he actually flagged and will flag again. Domain-agnostic:
  the named systems appear only as examples. Trigger on "refine the backend",
  "audit what we built", "clean it up before the PR", "post-build pass", any
  billing / money / Stripe / sync / migration change, any auth / roles / RLS
  change, any background worker / pipeline / scheduled job, any derived status
  or analytics metric, finishing any task that added or reshaped a domain's
  tables + services + endpoints, or preparing such work for review.
---

# Refine Backend — the post-build audit

Run this when a domain build or refactor **works** and is about to be handed
off. It is not a build guide: it assumes the code exists and asks what the
founder's review would catch. Walk every pass; each item below was flagged in
a real refactor, so treat a hit as "will be flagged again", not a judgment
call. And every hit gets **fixed** in this pass — there is no "nit" tier and
no "pre-existing" exemption; a red test you didn't cause, a stale comment, a
convention-level miss all get fixed here rather than triaged into a list.
*("seems liek you shoudl fix all of them, there was nothing nto worth fixing";
"fix all tests even if you didnt cause them.")*

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
  for scan runs. A priced catalog is the same shape: identity + append-only
  immutable value versions, ≤1 active, each consumer pinning a version; an
  edit deactivates and inserts a new version, and the client always sends the
  COMPLETE value spec, never a partial merge onto the current one.)*
- **Do committed rows that carry an external-system id stay immutable and
  append-only?** Once a row holds a live external id (a subscription-item id,
  a charge id), a change to its identity-or-money fields (price, payer,
  quantity) is a NEW row — cancel-old + insert-new — never an in-place UPDATE;
  the external id is a permanent historical record, never nulled on cancel.
  Enforce with triggers that fire even at service-role, because the backend
  bypasses client-role RLS. *(price_id / stripe_item_id / paid_by_member_id
  became trigger-immutable once set: "i think we need to update the rules to
  make it fully immutable except for cancle date, end date and actual price";
  "I wanna keep the strap IDs because they are historical records for what's
  on the actual invoice.")*
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
- **Is each invariant enforced at every layer that can bypass the others?** A
  JSONB array has no FK, so validate its references at write time; a DB
  trigger that only blocks client roles is a false floor because the
  service-role backend sails past it, so add the service guard too; a UI
  hiding a button is not a backend guard, so the mutation must still reject
  server-side; an explicit `null` on a NOT NULL column is a 422 you raise, not
  a 500 you let the DB throw. And a guard belongs in the statement's WHERE,
  not a pre-read — two concurrent writes both pass the read (`AND archived_at
  IS NULL` in the UPDATE itself, not a check before it). Belt-and-suspenders
  is the default for anything billing-critical. *(a single-owner entity was
  pinned at DB trigger + service guard + API gate, all three; plan-attachable
  references validated at write time because the column is FK-less JSONB.)*
- **Are derived numbers clamped at read?** Internal over-draw may exist, but
  a count query never returns a negative — `GREATEST(x, 0)`. *("the count
  should never be negative when querying, max it at 0.")*
- **Are all schema types in schema files?** No dataclasses or type aliases
  defined inside service files — Pydantic models belong in the domain's
  `schema/` package. *(GateEvaluation and VideoAgentOutput were both moved.)*
- **Does the schema change reach the VIEWS that serve it?** Postgres freezes
  a `SELECT *` view's column list at creation time, so adding a column to the
  base table does **not** appear to any consumer reading through the view —
  the view must be recreated in the same migration. When you recreate it,
  re-state `security_invoker` in both the `WITH` clause and the `ALTER` (the
  same tenant-leak the auto-diff ban exists to prevent, arriving from the
  other direction). And because `CREATE OR REPLACE VIEW` only accepts new
  columns at the **end**, the declarative schema file's column order must
  match the physical order the migration produced. *(A migration that only
  ALTERed the base table shipped green and 500'd every read of the new column
  in production.)*
- **Does the migration apply cleanly on top of main, and does it fail before
  the point of no return?** Two branches that each grab the same day-zero
  timestamp merge without a conflict (separate files) and detonate at apply —
  before hand-off, confirm your version is unique and sorts after everything
  already applied, and renumber the **unmerged** side. Never edit an applied
  migration; a rename ships as a new `ALTER` migration. Inside the file,
  every destructive step needs its pre-check first (`RAISE` on the rows that
  would violate the new constraint) because a mid-file failure leaves the old
  shape dropped and the new one not yet established, with no way back. A new
  constraint must handle legacy rows (dedup + NULL semantics) before it's
  declared. Dropping a column means sweeping every policy and view that
  references it — Postgres tracks those as hard dependencies. *(One column
  drop required rewriting 32 policies across 25 files before the DDL could
  run: "add this to the db claude.md for merge conflicts and migriaotn stuff
  ot make sure stuff like this doesnt happen agian.")*
- **Were all migrations hand-written and correctly ordered?** (The rule lives
  in `Database/CLAUDE.md`.) The audit angle: auto-diff is banned not only for
  the convenience-target reason but because it silently strips
  `security_invoker`/RLS off recreated views (a tenant-leak) and revokes
  service-role grants; a hand-written migration also orders dependents right —
  DROP a view before ALTER-ing a column type it depends on — and don't leave
  convenience targets that tempt auto-diffing. *(a `db diff` "produced a
  destructive migration… stripped security_invoker off the recreated views";
  a replacement `migration new` Make target was rejected outright: "you can
  remove it dont replace it with anything.")*

## 2. Service-layout audit

- **Is any general service written FOR a special consumer?** An agent,
  worker, or job is a thin wrapper that *uses* the domain's regular services;
  nothing in the regular services exists strictly for it. *("Nothing the
  agent skills should be strictly for the agent.")*
- **Is the layering one-way with no cycles?** Wrapper → facade → concern
  services; the regular services never call back up into the wrapper
  *("video_feed_refiner should never call video_agent — never the other way
  around")*. A foundational engine never imports from a domain above it — a
  shared value model lives in its owning domain and the engine builds its own
  representation rather than reaching upward *("Payments and sync service
  ideally never import from anything above it, it should stay self
  ocntained")*; a scheduled caller (reconciler → memberships) holds the
  dependency, never the reverse.
- **Is the facade pure delegation — and does it earn its existence?** Zero
  business logic in the facade; logic lives in the concern services it
  composes ("all the methods should be facade like, it cant have logic"). And
  the inverse: a facade that only forwards to one or two seams shouldn't
  exist — delete it and let callers wire the seams via DI. *("checkin service
  shouldnt exist, just use the gate.")*
- **Does any "shared" service hold per-request state?** A service constructed
  once and reused across requests must never stash request-scoped lookups on
  `self` — concurrent requests clobber each other. Either pass scope in per
  call, or construct the loader per request and discard it. *(a member-detail
  loader stored `_profiles`/`_authorized_payers` on a shared instance: "isnt
  hits a shared service class. Why would it store infomraiton?… beaxcuse
  mutipe request can come at the same trime rigtrh?")*
- **Is the orchestrator thin, and has any one file or base grown too big?**
  The top service orchestrates focused sub-services and holds no deep logic;
  when a service file or a shared base grows past readability, split by
  concern — in the PR that crosses the line, not "later". *(an 800-line start
  file split into money-path / validation / preview — "the file is WAAAY to
  big now, 800 lines is ctazy"; a 597-line base got a `TransitionBase`
  intermediate instead of growing.)*
- **Is shared infrastructure in `src/shared/`?** The moment a second consumer
  is plausible, it isn't domain code anymore. *("litellm should be shared,
  not specific to videos.")*
- **Any bare functions or side-channel config?** Helpers live inside service
  classes, construction is wired in the DI container, and configuration comes
  from the global settings object — never per-domain key-loading helpers or
  `os.environ` tricks *("this should be in the di, why is it here… we have a
  config globally, why are we using this")*. Operational knobs — retry counts,
  lock TTLs, lookback windows, a lock-key prefix — are Settings fields too,
  tunable per deployment without a code change *("and the amount of retries
  shoudl be in config")*.
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
  `is_member` not `is_kiosk` — the subject matters, not the device.)* Name the
  concrete action, not an abstract pattern — a generic `settle()` became
  `sync_once_discounts`, an `absorb()` seam became `record()`: "lets nto call
  it settle lets cal lit what it acullty does."
- **Did any name outgrow its first case?** Generalize the moment a second
  case appears rather than minting a sibling column or enum.
  *(`rejection_type` → `curation_type` when accepts needed the same
  tracking: "it shouldnt be rejection… it needs to be generalized.")*
- **Conversely: is a rename actually worth it?** A 20-file cosmetic rename of
  internal-only identifiers was rejected as churn — "honestly its fine,
  checkin and sign up are close enough." Rename user-facing strings; leave
  internal names that are close enough alone. The counter-case: two
  *confusable* name families are always worth it, and the rename must be
  total. *(Template tables prefixed `video_gym_*` sat beside production's
  `gym_video_*` — a near-anagram nobody can read at a glance; all five
  tables, the enum, the Python type, and the schema filenames were renamed
  together through a new `ALTER` migration — no half-renames leaving old
  prefixes in derived identifiers.)*

## 4. API & flow audit (incl. LLM/agent surfaces)

- **Is everything that CAN be deterministic, deterministic?** Anything that
  runs as plain code after a user decision (diff-check → derived generation →
  save) is backend code, not an agent tool or an extra LLM step. The agent
  converses; the commit path is code. *("queries is not a tool, its something
  done always AFTER the conversation is done, the end user never sees it.")*
- **Is expensive derived work diff-gated?** Only regenerate when the accepted
  input actually changed. *("only run the query if there is actually a diff…
  to save money.")*
- **Does a preview run the REAL engine?** A dry-run stages the same rows,
  reads the same query (via a `preview` toggle), and runs the same math as the
  real op — differing only in what it refrains from committing; a preview that
  computes differently is a lie the staff act on. It stays honest about
  calendar money (don't report an amount "due now" when nothing is due) and
  strips external-leaked lines a customer-level preview returns. A read-only
  preview endpoint gets its own request schema — no mutating fields like an
  idempotency key. *("actualyl mkae preivew work, need to send a toggle into
  the sync func so it knows what to query"; "the fastapi doesnt return due now
  if prorate is false.")*
- **Did near-identical single-vs-batch (or by-X-vs-by-Y) methods collapse into
  one?** One list-native method handles both — a single op is a one-element
  list — and one itemized signature (price XOR amount, each carrying its own
  extras) replaces a fan of `create_by_price` / `create_by_amount` /
  `create_consolidated` variants. Two shapes doing one thing are a drift
  surface. *("it should natively allow cancle many, not two paths, one can do
  both"; "Everything will always be itemizewd from now on.")*
- **Is every caller-supplied range or window capped?** An unbounded date
  range, span, or expansion parameter is an authenticated denial-of-service —
  one request asking for year 1 to year 9999 pins CPU and memory. Cap it as a
  Settings value, enforce it at the single choke point every route passes
  through (staff and self-service alike), and return 400 on over-range or
  inverted input. *("Fix it, give it a max range of like a 2 months, i dont
  think anything shoudl do more than that right?")*
- **Are error responses typed, correctly coded, and leak-free?** Every error
  body a client parses is a contract: it gets a Pydantic model in the schema
  file so it lands in OpenAPI, not an inline dict the client casts blindly.
  Map exactly one typed exception per status — a route that catches the base
  exception class will happily turn an internal config fault into a 404. Use
  the semantically right code (an auth failure is 401, never 400). And write
  the message for the person who reads it: an external resource id surfacing
  in the slot reserved for "why the card was declined" tells staff nothing
  and exposes internals. *(A raw subscription id was rendered to the front
  desk as a decline reason; it became "This invoice is already settled —
  nothing left to collect", with the id logged instead.)*
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

## 5. Auth, roles & tenant isolation

Access control is the one layer where a miss is not a bug report but a
breach. These were all found *after* the feature worked.

- **Does every endpoint name its own role set — and do reads and writes get
  different ones?** Auth helpers take the allowed roles as a **required**
  argument with no default, because a default silently hands an endpoint a
  role set nobody chose and the wrong choice is invisible at the call site.
  Then split by operation: everyone who uses a thing may READ its config;
  only the config owners may CHANGE it. And when you widen one domain's
  gates, re-audit **every** endpoint in every router — a gating model that
  drifts in one place has usually drifted in three. *(A theme read gated to
  owner/admin 403'd every front-desk sign-in and flooded the audit log with
  "Unauthorized gym access attempt", making a real intrusion look routine:
  "they can get the current theme, just cant updat eit"; then "make sure that
  ALL, yes look at ALL the request to make sure htey ahve the rigth ownership
  level.")*
- **Did the identity change wake a dormant branch?** When the thing an
  identity is keyed on changes (a dead FK → a populated email claim), every
  branch that was previously unreachable goes live at once — audit each one
  as new code, not as existing code. A self-service branch on a shared guard
  is the classic case: it silently exposed a dozen staff endpoints to the
  subject themselves, including money mutations and a check-in call where the
  caller could set the staff flag and override every gate. The fix is two
  routes with two gates over one implementation, not one route with a
  cleverer guard. *("this likely means that we need requests, one for
  members, one for employees they'll call the same function underneath but
  this way its simplicity in terms of how we do auth.")*
- **Are the DB-side access controls load-bearing or inert?** Verify them
  against the live database, don't read them off the migration. Postgres
  cannot subtract a column privilege from a role that holds the table
  privilege, so a column-list `REVOKE` next to a table-level `GRANT` is
  decoration — check with `has_column_privilege(...)` and fix by revoking at
  the table. Then ask the bigger question: does the direct data surface have
  *any* legitimate consumer? If every real client goes through the backend,
  revoke the whole surface and let the policies stand as defence in depth
  behind a door nobody can reach. *(16 column-level REVOKEs were inert, so an
  admin could PATCH the REST surface to set their own role to owner: "is
  there even a need to allow anyone but the backend to be able to touch the
  supabase backend?… Yes remove it from all the tables.")*
- **Does the query prove the CALLER, not just the claim?** Match the token's
  subject id, not only the email it carries — proving that *some* confirmed
  account holds that address is not proving that *this* caller's account is
  confirmed. Normalize both sides of every identity comparison (a unique
  index on `lower(email)` still permits mixed-case rows). Never take the
  tenant key from the client when the resource already implies it — resolve
  the resource first (404), derive the scope from it. And when a single
  mutable field IS the identity, freeze the path that lets someone revoke
  their own access. *("an owner should not be albe to update their own emial,
  owner emial for now hsould be immutable, for simplicty, this way they wont
  ever essentialyl revoke their own acces to their own gym.")*
- **Do the identity gates fail closed?** A security-relevant startup check
  refuses to boot rather than logging and continuing, and it distinguishes
  "couldn't reach the dependency" (tolerate — a blip) from "reached it and
  couldn't read the answer" (fail — that's the ambiguous case an attacker
  gets to create). A setting that lives in an external console is not a
  guard: pair the committed config with a check the code itself enforces, so
  a dashboard toggle can't silently reopen the model. *("why warn not fail?
  cant we make it fail."; "yes this NEEDS to be fixed. Email verfication is
  as the core of this whole pipeline.")*

## 6. Behavior-semantics audit

These were flagged every time they were left implicit — check each one got an
explicit decision:

- **Do boundaries anchor on the real event, not a calendar convenience?**
  "Past" means *ended* (`start + duration <= now`) — not started, and not gym
  midnight. An in-session occurrence is current, not history. *("just include
  any class that is still ongoing, it has an end time.")* And both halves of a
  comparison must use the **same** clock: an overdue check compared a
  now-anchored status against an occurrence-anchored date, so a retro
  check-in of a currently-overdue member never warned; a conversion metric
  re-anchored off cohort start onto the event's actual end plus a grace
  window *("just only look at trials that have ended but not converted for
  lets say a week, dont look at trial start date that doesnt really make
  sense").*
- **Are similar-looking states actually distinct?** Sign-ups silently
  becoming "attended" at midnight was a caught design flaw — a reservation is
  not an attendance. Manual vs automatic termination are different facts too —
  `cancel_date` (a human/staff cancel) vs `end_date` (automatic
  expiry/depletion); collapsing them let an attendance-undo resurrect a
  staff-cancelled row *("end date is always automatic… while cancel is if you
  cancel it by yourself early")*. If two concepts share a table, the split
  must be explicit and visible.
- **Does every derived status or metric have exactly ONE definition, loaded
  from one text?** Not "documented once" — *loaded* once: one SQL fragment
  plus one code predicate in shared, and every badge, tally, filter, tab, and
  analytics query reads that same text. Two surfaces computing the same word
  from two predicates will disagree, and the disagreement surfaces as a user
  reporting that a filter finds nothing. When the rule can't be a row-level
  view (it aggregates over all of a subject's rows), the shared fragment
  injected into each consumer is the substitute — not a second copy. If a new
  status is display-only, prove it: grep the money paths and confirm none of
  them reads it. *(One status was defined in seven places with two families
  using conflicting predicates; another meant two different things on two
  screens — "in the gropwth veir it says ther is one dormant but when i look
  at it and try to fitler for it in member view nothing comes up.")*
- **Is the reported number honest about what it is?** The label must match
  the window and the math — "month to date" may not be a projection, and a
  subtitle saying "Current" over a 90-day window is a lie staff act on. If
  the semantics widen, rename the series key *and* the label *("i just
  relaized its specifally recurring revenue, it shouild just be all
  revenue")*. And unknown is not zero: a value that cannot exist yet must be
  nullable end to end and render as absent — a cohort too young to have a
  90-day number was rendering as 0% retention, which reads as catastrophe.
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
  `is_member` semantic flag, not as auth — and the flag is set by the
  **route**, never accepted from the caller it gates (once self-service
  identity went live, the subject could post the staff flag plus
  ignore-warnings and downgrade every gate; the fix was two routes over one
  gate implementation).
- **Does the UI re-guard anything the service allows?** If the backend
  permits cancelling any date, the UI adds no date window on top — "we dont
  need a ui guard, if they want to cancle let them cancle."

## 7. Money & external-system audit

When a domain moves money or mirrors its state into an external system of
record (a payment processor, a billing ledger, any third party the data must
converge with), a single wrong step charges a real person or silently desyncs
the two systems. The founder's billing reviews hit the same passes every time.

- **Do mutating money operations fail non-retryably?** A charge / cancel /
  refund / reprice / freeze that fails returns 500, never a 502/503/504 (the
  proxy auto-retry family), and a partial batch returns 207 with the per-item
  split parsed on the success path — so no gateway silently re-runs a money
  mutation. (The rule + rationale are canonical in `FastApiBackend/CLAUDE.md`;
  this is the audit check that the code actually follows it — every
  Stripe-failure 502 was swept to 500.)
- **Is every money op idempotent — safe to run twice?** A no-op converges to
  zero external mutations (no proration invoice even with `prorate=true`);
  every external write carries a deterministic idempotency key, with a
  synthetic one minted where the object has none; and dedup lives at the DB as
  a natural-key `ON CONFLICT`, never in an event-log, because a
  reconciler/backstop re-lists the same objects and must re-absorb them
  safely. *("just have to be careful about this to not bill someone by
  accident when porate is true"; the missed-webhook sweep re-lists invoices,
  so `ON CONFLICT` on the invoice id is what makes re-absorption safe.)*
- **Is desired state re-derived, converged one way, and verified-or-reverted?**
  The sync reads the DB as the single source of truth (no imperative
  `add_ids`/`cancel_ids` — that's a second source that drifts), pushes the
  external system onto it, then verifies the row reached its terminal status
  and reverts on failure. The op owns its own recovery and never leans on a
  task/retry layer — it may run from a batch, a CRM click, or a fix script.
  *("This transcation has nothing to do with tasks… We can't rely on the
  retry.")*
- **Does the op leave every surface correct before it returns?** Webhooks,
  sweeps and reconcilers are backstops for what you *missed*, not the
  mechanism for what you just did — a member must be off the overdue list
  when the response returns, not whenever async delivery lands. Record the
  exact object the mutation returned, **by value**: re-retrieving it by id
  reopens a stale-read window, and a "created since" sweep structurally
  misses an object created weeks ago. Then check what already updates: if the
  record path stamps the same field, don't also re-run a full re-derivation
  on top of it. *("after rety payment doesnt sync need ot be run so it
  updates everything? otherwise it just relies on the webhook / sweep, this
  isnt acceptable"; "why are we doing it? it doesnt make much sense when sync
  alr does it.")*
- **Does each kind of drift resolve to the right winner?** Config drift (what
  the CRM intends) → local wins, push it. Lifecycle drift (the external system
  cancelled or dunned a resource out from under you) → the external system
  wins: record reality with zero external calls, and never re-push a gone
  resource through the blessed mutate path — its pre-sync would raise on the
  missing resource and abort before recording the truth. *(the dead-sub
  absorber deliberately does NOT call the blessed `cancel()`, which would 404
  on the gone sub: "we record reality, never re-push or re-bill.")*
- **Does the writeback persist everything it can — and can nothing fail the
  op after the external side succeeded?** Mirroring the external result back
  into the DB is the load-bearing final step — wrap each write in its own
  try/except so one failed write logs and the rest still land; the
  verify/revert reads status independently. And once the external mutation
  has succeeded, no later step may fail the operation: a card charge
  succeeded and the in-request record step then threw, 500ing the call —
  staff read "failed settlement" and collected the money a second time. The
  record step logs and swallows; the backstops re-apply it. *("The writeback
  is obv very important… one failure doesnt break everything… it can write
  basck what it can.")*
- **Does only the boundary layer touch the external SDK?** Every other domain
  calls the integration layer's primitives; nothing reaches for the SDK
  directly to "save a hop." And prefer an explicit status read over depending
  on a shared function's raise behavior — an off-session charge can return
  the invoice still `open` with a requires-action payment intent and raise
  **nothing**; booking that as success clears the member off every overdue
  surface while no money moved. Assert the returned object's terminal status
  before recording success. *("we shoudl never be diredcrtlyt calling
  stroipe, add a funciton into the paymetns part not in the memberships.")*
- **Do you compute derived money yourself, in the right order, and clamped?**
  Don't trust the external system to stack or aggregate — it may apply
  discounts sequentially per item, so do the math yourself and attach in the
  order it applies (dollar → percent); a fixed amount applies once per line,
  not per unit; and bound every money value (percent ∈ (0,100], amount > 0,
  exactly-one-of) so an impossible computed value raises loudly instead of
  mis-billing. *("Actualy we cant do it stack either. becusae it needs to be
  sequentsi per each item. So we have to do the math ourself.")*
- **Is proration explicit, and is calendar/timezone money right?** Proration
  is a call-time parameter (default `none`), never inferred from row data
  *("prorate will be explictly passed in")*, and a downgrade forces no-charge
  regardless of what the caller passed; convert external timestamps into the
  entity's local timezone for billing anchors, not UTC — a UTC period-end read
  lands a day early for anyone east of UTC *("whya re we using UTC as
  enddate?")*.
- **Is the whole mutate-and-converge serialized per owner?** A lock keyed on
  the resolved billing owner (not one global lock, which blocks the whole
  tenant) wraps the entire read → mutate → converge so two concurrent syncs
  can't last-write-wins the external state; it's reentrant, an async
  context-manager only (no manual acquire/release to forget on an exception
  path), with a TTL below its lease. The lock is a generic shared primitive —
  the engine owns zero lock logic; callers wrap their op. *("why is family
  lock in paymetn sync. This payment sync shoudl not have worry abou this at
  all. it should be in same shared class for the lock.")*

## 8. Background work & pipelines

A worker's failure mode is silence: it looks like nothing happened. Every
item here was found because something quietly stopped, quietly re-paid, or
quietly could not be stopped.

- **Is every step independent, DB-derived, and drained whole per tick?**
  Steps hand off through the database, never in memory: each one selects its
  own outstanding work, processes all of it, and returns. Crash recovery is
  then free — an unclean stop just re-derives on the next start, so there is
  no resume logic to get wrong. Order the tick to drain the output end first
  and pull fresh input last (finish, then prepare, then ingest), so backlog
  stays bounded and the work nearest to serving gets done first; only the
  genuinely quota-bound step is capped, the rest drain. *("We need to mkae
  each step independent from each other… essentialyl everything that is
  needed should be in the db"; on the tick order reading backwards at first
  glance: "cause everythinh seems to be ordered backwords for some reason.")*
- **Does a failure cost only what actually failed?** Strike granularity is a
  design decision: a cheap sub-step failing must not invalidate the expensive
  one that already succeeded, so persist each result as it lands. Only a real
  error counts as a failure — a missing *optional* input is a degraded input,
  not a strike. And a step that throws must **fail its run**, never leave it
  parked in `running`: a stranded run blocks the next trigger and burns the
  user's request. Give every run a TTL to a terminal state so nothing wedges.
  *(A flaky embed batch struck all 64 videos whose expensive multimodal pass
  had already succeeded, forcing a full re-pay; a transient scrape error
  stranded an empty run and consumed the gym's trigger, so the owner's edited
  criteria went un-run for 20 days — the design goal was "so one failure
  doesnt make a whole feed useless.")*
- **Is every wait bounded, and is every lease sized to the work it guards?**
  No unbounded external call — an SDK that defaults to waiting forever parks
  a concurrency slot permanently. Confirm retry/timeout constants are
  actually **passed to the library**; a constant defined and never wired is
  false confidence. The kill path must reach in-flight work, not just the
  loop between ticks (a `make → poetry run → python` chain means killing the
  parent never reaches the process doing the work). For the lock: a batch
  sweep must not inherit the single-op default TTL — size the lease to
  outlive a full drain, and lock a regression test onto it. *(A hung provider
  call froze the whole gather; the worker became unkillable — "also i hjave a
  worker running but its unkillable with ctrl c"; "doesnt matter, logn lock
  holds are expected, maybe just boost the lock max time, to an 30 minutes
  even.")*
- **Does re-processing keep the surface live?** Re-judging existing work
  happens **in place** — flip a verdict only when it actually changes, never
  reset rows to a pending state that pulls them out of what consumers see.
  Serving slightly stale data beats flashing blank. Never overwrite a human
  decision with an automated one. Target the run consumers are actually
  reading (the completed one), or the zero-downtime promise silently fails
  while an ingest is in flight. And carry every watermark forward across
  cycles, or each run re-judges and re-pays for the whole set. *("Dont cahgne
  the scan status, this will amke the feed unavaibel it shuld have no down
  time.")*
- **Is the expensive work done once, capped, and accounted?** Do per-artifact
  work once and share it across every tenant that needs it — describe once,
  judge many — rather than re-paying per tenant; a shared enriched pool also
  means a newly-provisioned tenant serves on day one instead of waiting for a
  sweep. Cap the spend structurally: a hard per-run budget, and truncating
  validators on model list-output (clip, never reject, so the retry loop
  can't churn) with the ceiling also stated **in the prompt**. Write a cost
  row per stage keyed to tenant and run so spend is queryable. Before any
  paid full run, smoke-test one item end to end. And re-verify inherited cost
  estimates against live data before quoting them. *("can we test the make
  enrich-tempaltes work on just one thing? the reason why i si dont want to
  start to run the whol ething and it errors out"; an 18% assumption behind a
  $41 estimate turned out to be 0% — "where di we get teh 18% from?")*

## 9. Production-readiness audit

- **Any demo-only code path left?** A preset/demo/import works through the
  exact production write path and produces production-shaped data — "the
  preset should not work specially AT ALL. No custom logic for it. This is
  going to be prod code."
- **Any mock or placeholder data left?** Real entities end-to-end. *("no more
  demo anything, their videos need to be actual videos on youtube.")*
- **Does seed reproduce production side-effects, not just rows?** A seed that
  inserts money/points rows without the derived state the real write path
  produces reads as broken data: it must debit the balance a redemption would
  debit, stamp the sync status reality demands (a cancelled row is `deleted`,
  an expired-by-date row is `applied`), send `quantity: N` where the engine
  expects one row (not N duplicated rows), and fill every column a new
  constraint added — a direct DB insert bypasses the backend that would have
  populated them. *(seeded redemptions never decremented `points_balance`,
  inconsistent with the debit-on-request model; a direct seed INSERT tripped
  the new `paid_by_member_id` NOT NULL because it bypassed the backend.)*
- **Is seed/demo data realistic and complete?** Varied times, a month of
  history, a week of future state, an empty/light/busy mix, every status
  exercised (attended / reserved / no-show), populated queues, real images —
  the demo is the sales surface, so partial seeding reads as a broken product.
- **Was anything deleted because it "looked unused"?** Trace every consumer
  first; one "unused" field turned out to feed three surfaces. Looks-unused
  is not confirmed-dead. The counterweight: a seam with **zero callers
  today** does go — a never-wired endpoint, unused ranking weights, a
  concurrency knob for a strictly-sequential step (dead config actively
  misleads operators into thinking it's tunable), and a generic importer
  isn't built before there are real sources to learn from *("i cat make a
  script with no customers and i dont know specfically from where they are
  going to come from").*

## 10. Verification & hand-off

- **Did it run end-to-end against the REAL backend and REAL external system,
  not fakes?** Hit the real routes, then check the DB state they produced;
  run money ops against the real (test-mode) processor. Fakes shaped like last
  year's API hide the breaks that matter — a best-effort `getattr` of a moved
  field returns empty, not an error, so unit tests stay green while production
  silently writes nothing. A mocked-DB suite also hides **schema drift**: 62
  green tests while a query joined a table another branch's migration had
  dropped — every live read 500'd; money SQL never executed against Postgres
  would have shipped a gross-vs-net and a UTC-bucketing regression green.
  Keep a live-shape regression guard. *(a moved coupon field —
  `discount.coupon` → `discount.source.coupon` — silently wrote zero audit
  rows; only the real-Stripe E2E caught it.)*
- **Is the external API version pinned?** Pin the version the code is written
  against so an SDK upgrade can't silently reshape request/response payloads
  under you; a version bump then lands deliberately, next to the code that
  handles the new shape.
- **Is any test green for the wrong reason?** A silent skip is worse than a
  failure — a suite that skips ten tests depending on the time of day reports
  green on a machine where the window closed. A test that names a real file
  or registry entry asserts the directory's incidental state, not behaviour,
  and flips the moment that file lands — point it at something synthesised
  that can never exist. Anything reading the wall clock internally is
  time-fragile: inject `now` as a parameter so the test can pin past,
  current, and future cases. And keep unit and live suites as disjoint sets —
  a live-backend test outside the integration directory gets collected by the
  unit run and fails there.
- **Did money- or capacity-adjacent logic get the edge-case pass?**
  At-capacity, idempotent repeat, unlimited-never-blocks, override paths,
  no-show holds — plus the billing edges: mixed cash/card on one consolidated
  invoice, a downgrade forcing no-charge, a dunning-cancelled subscription, a
  once-off discount coexisting with an ongoing one (that coexistence shipped a
  real mis-bill because the lone-discount test didn't cover it). Verified AND
  locked with regression tests. "Just make sure all the edge cases are
  handled" is a standing order.
- **Do tests clean up exactly what they create — and is teardown FK-safe and
  external-aware?** Guard shared rows with existence checks; delete
  child/junction rows before parents in FK order (never null a FK to dodge a
  constraint); and when teardown also archives an external resource, archive
  ONLY after the DB row actually deletes — a swallowed DB-delete that still
  archives leaves a phantom (a live-looking row pointing at a dead external
  resource that 500s every later use). The test factory must build services
  exactly like production DI — a stale factory (missing a newly-injected
  dependency or a new column) throws false reds and hides real wiring gaps.
  *("does it not have a finally? or are you just killing it harshly" → archive
  gated behind a successful delete.)*
- **Did the FULL suite run, not just the feature's slice?** A model reshape
  ripples across domains — cherry-picking test dirs let a billing regression
  ship *("I didn't run them… scoped my test runs to two dirs and missed the
  third")*.
- **Is the hand-off report complete?** If review found 12 issues, the report
  lists 12 — not 7 with 5 bundled into one line. Truncation reads as
  concealment. *("you only outputed 7 of the 12 confirmed.")*

## 11. Docs-sync audit

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
