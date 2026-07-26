# Worker tick + ingest — the tick order and the scrape step

The background **worker** (`src/worker`) runs a loop of DECOUPLED, DB-backed
steps — not a single per-gym pipeline. This guide covers the tick's always-run
prelude (cleanup + finalize) and the **scrape** step in depth (the only
quota-bound, per-gym, run-opening step). The **enrich + scan** half — the global
gym-agnostic sweeps that build the RAG layer and settle feed verdicts — is
`scan.md`.

## Where it runs

`python -m src.worker.run` (`make worker`) is a long-running loop: one tick, then
wait `worker_poll_seconds` (60). Each tick acquires the global `"video_worker_run"`
lock on the shared `resource_locks` table (non-blocking single-shot — a second
worker instance just no-ops; TTL 900s, heartbeat 300s renews it; a lost heartbeat
sets an abort flag and the current drain stops between videos/batches/gyms), then
runs everything below **under one lock hold**.

## Step 1 — cleanup (always, cheap)

`DELETE FROM video WHERE failure_count >= worker_failure_max` (3). The FK cascades
drop the video's feed rows, its `video_rag` row, and any member recs. Runs FIRST
so the finalize step's terminal-fraction denominators reflect the shrunk feed. See
`scan.md` for how `failure_count` gets bumped.

## Step 2 — finalize (always, cheap)

Completes or fails every `running` run purely from its feed rows — no in-memory run
bookkeeping, so crash recovery is free. Two SQL passes, in order (completion beats
the TTL fail):

1. **complete** — a `running` run whose terminal (`accepted`/`rejected`) fraction of
   ALL its feed rows reaches `worker_run_complete_fraction` (0.9).
2. **fail** — a `running` run with ZERO feed rows older than
   `worker_zero_row_grace_hours` (1h) → `failed`, `error='no feed rows'`; else a run
   older than `worker_run_ttl_hours` (24h) that never reached the completion
   fraction → `failed`, `error='run ttl exceeded'`.

**There is no orphan rule.** A `running` run is a legitimate long-lived
multi-tick state — full of `pending` rows the enrich + scan sweeps are still
chewing through — so it is never treated as dead on its own. Crash recovery is
free (every step is DB-derived + idempotent); the two guards above catch a
pathologically stuck run.

## Step 3 — one heavy step, first-with-work, drained fully

The tick checks **scan**, then **enrich**, then **scrape** (backlog first; scrape
is the quota-bound ingest, so it goes last) and drains the FIRST one that has
work completely before the tick ends. See `scan.md` for scan + enrich. If none of
the three has work, the tick ends after cleanup + finalize.

## The scrape step (per-gym, quota-bound, the only step that opens runs)

Because scrape is the only step that opens a `video_run`, the per-gym + system
rolling run caps bound exactly the quota-limited work — enrich and scan never
touch a run cap.

### Select the due gym

No job queue: `worker_select_due_gym.sql` *derives* the single highest-priority
DUE gym straight from timestamps already in the schema — a gym is due when its
latest `gym_video_spec` **`admin_update`** version (tier 1) or its last run ≥ 7
days ago (tier 3) is newer than its last `video_run`, **and it has no `running`
run** (never two in-flight runs for the same gym). A manual `gym_video_feed`
curation does not trigger a scrape run — only an `admin_update` spec edit or the
weekly refresh floor do. Tier-sorted; per-gym (2/24h) and system-wide (5/24h)
rolling run caps (counting runs of any status — the poison-loop guard, since a
failed run still advances the last-run watermark) stop the drain. The drain loop
repeats — select, scrape, select again — until the system cap is hit or no gym is
due, so one tick can drain several gyms' scrapes.

### Spec + incremental context

Load the gym's latest spec from `gym_video_spec_latest`. Compute
`criteria_changed` by comparing the current `(videos_desc, avoid_desc)` against
the spec version in force at the gym's previous **completed** run — this drives
incremental (unchanged) vs fresh (changed) carry-forward mode at feed-write time.

### Scrape → YouTube Data API v3

Two official calls **per spec query** — `search.list` for the video ids + snippet
(100 quota units), then a batched `videos.list` for stats + the ISO-8601 duration
(~1 unit) — concurrency `worker_scrape_concurrency` (4),
`worker_max_results_per_query` (50 — pinned AT the API's ≤50 cap, since page size
does not affect quota: `search.list` is a flat 100 units at any page size and the
`videos.list` batch stays one call) each. The API is
**free within the daily quota** (10k units/day ≈ 3 gym-scrapes/day). A failed
query is dropped, not fatal. Results are **merge-upserted** into the shared
`video` pool: `source_queries` accumulate, `relevance_index` keeps the best, and
`tag` / `disciplines` / `transcript` are **never overwritten** — fresh scrapes
land untagged and **transcript-less**. Transcripts are NOT fetched here; they are
a lazy fetch at enrich time (`scan.md`).

### Creator avatars — the third call, right after the merge

A search / videos snippet carries the channel **id** but no avatar, so a third
call resolves it: `channels.list?part=snippet&id=<≤50 ids>` →
`snippet.thumbnails` (`high` → `medium` → `default`), **1 quota unit per call
regardless of batch size** (`src/worker/worker_avatars.py`). It runs AFTER the
merge — the rows must exist to be written — and writes by **`channel_url`, never
by video id**: the avatar is a per-CHANNEL value stored redundantly on each of the
channel's ~2 pool rows, so a video-keyed write would leave the rest of the channel
stale.

It **refreshes, not just fills**. A `yt3.ggpht.com` URL rotates when a creator
changes their picture and the old one eventually 404s, so every channel the scrape
touched is re-resolved, not only the uncovered ones. Every gym re-scrapes at least
weekly (tier 3), so a channel that still surfaces in any gym's queries is refreshed
at least weekly for ~nothing: ~600 distinct channels per run ≈ **12 quota units**
against the ~2,500 that run spends on `search.list`. `worker_avatar_max_batches`
(40) hard-caps the calls; when it binds, channels with NO avatar go first. A 403 on
a batch is logged and dropped — the run never fails over an avatar, and an
unresolved avatar just stays empty (the member UI omits it).

The pre-existing pool is filled once by `make backfill-avatars` (see
`VideoService/CLAUDE.md` — it also upgrades the legacy `@handle` channel URLs to
the canonical `/channel/UC…` id form, which is why the pool needs no `channel_id`
column: the id is always recoverable from the stored URL).

### Funnel

Pick up to `scan_budget_per_run` (1500) candidates:

- **Tier 1** — pool rows whose `source_queries` overlap the spec queries AND match
  a gym discipline (or are untagged, so this scrape's fresh results are included),
  relevance-ordered. In incremental mode, exclude the previous run's verdicted ids.
- **Tier 2** (only if Tier 1 leaves room) — embed all spec queries in one call,
  then a cosine top-`rag_probe_top_k` (40) probe over discipline-matched
  `video_rag` rows. A full Tier 1 skips Tier 2 entirely; only already-enriched
  videos (a `video_rag` row) can match a probe.

### write_feed — the scrape step's ONLY feed write

In one transaction: open the `video_run` (`status='running'`), then:

1. **Carry forward** the previous completed run's feed rows FIRST — ALL rows in
   incremental mode (criteria unchanged), only the owner's **manual-curation**
   rows in a fresh run (criteria changed).
2. Insert every funnel candidate as a **`pending`** row (`curation_type='automatic'`)
   `ON CONFLICT (video_run_id, video_id) DO NOTHING`. Because carried rows are
   inserted first, they win — **the owner's manual keep/reject always beats a
   fresh automatic candidate.**

The run is left `running` — nothing is enriched, scanned, or completed here. The
enrich + scan sweeps and the finalize step (above) take it from there.

### Cost logging (scrape)

Two rows to the generic `cost_log` table, both stamped that gym + run: `search`
(**free** — the YouTube Data API within quota; the quota units ride in
`breakdown` as the run TOTAL, `search.list` plus the avatar pass's
`channels.list`, with the avatar share broken out as `avatar_quota_units` /
`channels_resolved` so the pass is never uncounted quota) and `embed` (the tier-2
funnel probe's query embeddings).

→ Continue with the enrich + scan half in `scan.md`.
