# Worker judgment — scan → feed-write

The second half of the background **worker** (`src/worker`): turn the enriched
candidates into the gym's served feed. Continues from `scraper.md` (scrape →
funnel → enrich) as part of the same `make worker` pipeline — not a separate
command.

## Stage 5 — scan

Load the funnel candidates joined to `video_rag` (a candidate whose enrich failed —
no `video_rag` row — is simply not scanned). Judge them in batches of
`scan_batch_size` (≈12 summaries per LLM call, `scan_model`
`gemini/gemini-2.5-flash-lite`, concurrency `worker_scan_concurrency`) against the
spec's `videos_desc` / `avoid_desc` → a keep/drop verdict per video. A missing or
hallucinated verdict defaults to **rejected**.

## Stage 6 — feed write (carry-forward)

In one transaction, open a new `video_run` (`status='running'`) and:

1. **Carry forward** the previous completed run's feed rows FIRST — ALL rows in
   incremental mode (criteria unchanged), only the owner's **manual-curation** rows
   in a fresh run (criteria changed).
2. Insert the fresh **automatic** verdicts `ON CONFLICT (video_run_id, video_id) DO
   NOTHING`. Because carried rows are inserted first, they win — **the owner's
   manual keep/reject always beats a fresh automatic verdict.**
3. Complete the run (`status='completed'`, `finished_at`). Only a completed run is
   ever served: every "latest run" read filters `status='completed'`, so a
   mid-flight `running` run never becomes latest and blanks the gym's feed.

A `scan` row is written to the generic `cost_log` table for the run (`source='video'`,
stamped `run_id` (TEXT) + `gym_id` + `model` + `cost_usd`).

## Failure semantics

Any stage exception marks the run `failed` (with the error). There is no
re-enqueue — a failed run's `created_at` still counts as the gym's last-run
watermark, so a deterministic failure does not hot-loop (poison guard): the gym
simply waits for a new tier-1/2 trigger or the tier-3 weekly floor to become due
again. A crash that leaves a run stuck `running` is recovered (marked `failed`,
same no-re-enqueue rule) by the next tick's orphan sweep.

## Sequential by design

The global `"video_worker_run"` lock means the worker processes **one gym at a
time** across every instance; within a gym, provider calls fan out only to the
configured `worker_*_concurrency`. Never bypass the lock.
