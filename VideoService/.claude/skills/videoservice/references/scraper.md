# Worker ingest — scrape → funnel → enrich

The first half of the background **worker** (`src/worker`): turn a gym's spec into
enriched, scanned-ready candidates. This is no longer an operator script — it is a
self-scheduling loop with no job queue: each tick derives the single
highest-priority "due" gym straight from timestamps already in the schema (a fresh
`admin_update` spec version, a settled manual feed curation, or a weekly refresh
floor) and runs the whole pipeline under a global lock. Run it locally with
`make worker`. This guide covers the three ingest stages; the scan + feed-write
half is `scan.md`.

## Where it runs

`python -m src.worker.run` (`make worker`) is a long-running loop: one gym per
tick, then wait `worker_poll_seconds` (60). Each tick acquires the global
`"video_worker_run"` lock on the shared `resource_locks` table (TTL 900s, heartbeat
300s → one gym at a time across every instance), recovers any orphaned `running`
run (mark `failed`, no re-enqueue — the derivation re-selects the gym once it's
next due), checks the system-wide rolling run cap, then derives the due gym
(tier 1 = newer `admin_update` spec version, tier 2 = settled manual feed
curation, tier 3 = weekly refresh floor; per-gym + system run caps apply) — see
`CLAUDE.md`'s *Scheduling* section for the full tier/cap rules.

## Stage 1 — spec

Load the gym's latest spec from the `gym_video_spec_latest` view. Compute
`criteria_changed` by comparing the current `(videos_desc, avoid_desc)` against the
spec version in force at the gym's previous **completed** run — this drives
incremental (unchanged) vs fresh (changed) mode downstream.

## Stage 2 — scrape

One Apify `streamers/youtube-scraper` actor run **per spec query** (subtitles ride
inline — search + metadata + channel avatar + transcript in one call), concurrency
`worker_scrape_concurrency` (4), `worker_max_results_per_query` (20) each. A failed
query is dropped, not fatal. Results are **merge-upserted** into the shared `video`
pool: `source_queries` accumulate, `relevance_index` keeps the best, and `tag` /
`disciplines` are **never overwritten** — fresh scrapes land untagged and get their
tags at enrich.

## Stage 3 — funnel

Pick up to `scan_budget_per_run` (1000) candidates:

- **Tier 1** — pool rows whose `source_queries` overlap the spec queries AND match a
  gym discipline (or are untagged, so this run's fresh scrapes are included),
  relevance-ordered. In incremental mode, exclude the previous run's verdicted ids.
- **Tier 2** (only if Tier 1 leaves room) — embed all spec queries in one call, then
  a cosine top-`rag_probe_top_k` (40) probe over discipline-matched `video_rag` rows.
  A full Tier 1 skips Tier 2 entirely; only already-enriched videos (a `video_rag`
  row) can match a probe.

## Stage 4 — enrich

For each un-enriched candidate **and** the gym's owner-section videos, ONE
multimodal LLM call (`enrich_model`, `gemini/gemini-2.5-flash-lite`) over the
thumbnail image + metadata + a transcript slice (`enrich_transcript_char_budget`,
8000 chars) → `{genre tag, disciplines, prose summary, facets}`. The tag +
disciplines are written back onto the pool `video` row; the summary is embedded
(`embedding_model`, `openai/text-embedding-3-small` → `vector(1536)`, batched) and
stored as a `video_rag` row (`ON CONFLICT DO NOTHING`). This is the RAG layer the
FastApiBackend's member recs + semantic search rank against — the model + dimension
are a **cross-service contract** (`run.py` asserts `embedding_dim == 1536` at
startup).

Each stage logs spend to the generic `cost_log` table (`search` / `embed` / `enrich`,
`source='video'`), stamped with `run_id` (TEXT) + `gym_id` + `model` + `cost_usd`.

→ Continue with the scan + feed-write half in `scan.md`.
