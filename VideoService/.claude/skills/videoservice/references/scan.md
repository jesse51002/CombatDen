# Worker judgment + RAG build — enrich, scan, and the strike mechanic

The other half of the background **worker** (`src/worker`): two GLOBAL,
gym-agnostic sweeps — **enrich** (build the RAG layer) and **scan** (settle feed
verdicts) — plus the per-video strike/cleanup mechanic they both feed. Continues
from `scraper.md` (the tick order + the scrape step); these are steps 2 and 3 of
"one heavy step, first-with-work" — **scan is tried FIRST, then enrich** (backlog
before fresh ingest), so read them in tick-priority order below even though this
file's own name matches the older "judgment" half.

Neither sweep is tied to any single gym or run — each drains its WHOLE target set
across every gym in one pass, unlike the per-gym `scraper.md` step.

## Scan (tried first — global sweep, per-gym batches, TEXT-ONLY)

**Targets** (`worker_scan_targets.sql`): each gym's latest-non-failed-run feed rows
whose video already has a `video_rag` row (enriched) and is under the strike ceiling,
grouped by gym, matching **either arm**:

- **Arm A — first scan.** `scan_status = 'pending'` rows: a candidate the worker wrote
  but has not yet verdicted.
- **Arm B — the feed-learning RE-SCAN.** `curation_type = 'automatic'` rows (pending
  OR already accepted/rejected) whose `scanned_at` predates a gym `feed_update`
  `gym_video_spec` version that has **settled** ≥ `worker_feed_update_rescan_delay_hours`
  (1h) — `s.created_at <= now() - :rescan_delay_hours` AND `s.created_at >
  COALESCE(scanned_at, '-infinity')`. This re-judges the gym's existing auto feed rows
  in place against the new criteria after an owner's manual curation folds into a
  `feed_update` version. Arm B **never** includes a `curation_type = 'manual'` row, so
  an owner's explicit keep/reject is never re-scanned.

Per gym: load that gym's **LATEST** spec **at scan time** (`worker_spec_load_latest.sql`
— judged against the CURRENT criteria, i.e. the `feed_update` folded in the owner's
manual signals, not whatever spec was in force when the candidate was scraped), batch
the candidates (`scan_batch_size`, 12), and run a **text-only** keep/drop (`scan_model`,
`gemini/gemini-2.5-flash-lite`) on each candidate's **summary + structured enrich
outputs** (genre, disciplines, facets). NO thumbnail is re-sent: the enrich step
already did the multimodal pass and folded the visual detail into the detailed summary,
so scan reads that instead. This is cheaper AND scale-correct — scan runs per-gym (a
video in many feeds is scanned many times) while enrich runs once per video.

**Verdicts are written by UPDATE** (`worker_update_verdict.sql`), not by a fresh
feed insert — there is no per-run scan-write. An automatic row is flipped to
`accepted`/`rejected` (arm B flips accepted↔rejected only when the judgment changes)
and stamped `scanned_at = now()`, guarded by `curation_type <> 'manual'` so an owner's
explicit keep/reject is never overwritten and a row is **never flipped to `pending`**
(which would blank it from the served feed). `scanned_at = now()` marks the row judged
so the same `feed_update` never re-triggers it. A verdicted video's strike counter is
reset to 0.

**The `feed_update` auto-learn loop (zero downtime).** Arm B is the WORKER half of the
loop; the BACKEND half is an immediate, per-gym-coalesced auto-refine fired the moment a
gym owner manually rejects or keeps a feed video (FastApiBackend `videos` domain —
`VideoFeedRefineRunner` → `VideoFeedRefiner`), which mints the `feed_update` version.
The ≥1h settle wait lives HERE in the worker (arm B's `:rescan_delay_hours`), letting a
burst of curations coalesce into one `feed_update` before the in-place re-scan sweeps
similar videos in or out — the served feed is never blanked, since rows only flip
between `accepted`/`rejected`, never to `pending`.

**Strike semantics — no default-to-rejected.** A batch whose LLM call raises bumps
`failure_count` for EVERY video in the batch and leaves the rows `pending`
(retried next sweep, by this gym or a later sweep); a video the model omits from an
otherwise-successful batch is bumped alone and stays `pending`. A missing verdict
is never silently rejected.

One `scan` cost row is logged per gym per sweep (`source='video'`, that gym + its
latest run, `scan_model`, the batched LLM spend).

## Enrich (tried second, if scan had no work — global, gym-agnostic sweep)

**Targets** (`worker_enrich_targets.sql`): every video that still LACKS a
`video_rag` row and is under the strike ceiling, drawn from each gym's latest
non-failed run (`pending`/`accepted` rows — `rejected` rows are skipped;
`accepted`-without-rag rows are imported presets or pre-RAG carry-forwards that
still need an embedding) **∪ ALL owner-section rows** (`video_run_id IS NULL`). Not
tied to any single gym or run.

The sweep processes targets in chunks (`EMBED_BATCH_SIZE`, 64). **Transcripts are
fetched BATCHED, up front, per chunk**: the chunk's cache-MISS videos (rows with an
empty stored `transcript`) are fetched in ONE **Apify**
`supreme_coder/youtube-transcript-scraper` actor run — a batched actor that takes a
LIST of watch urls and returns one dataset item per url, mapped back to its video by
the `?v=<id>` in `inputUrl` (`WorkerEnricher.fetch_chunk_transcripts`; a miss-list
longer than `apify_transcript_batch_size` (64) is split into multiple runs). The
`.call()` is bounded — `apify_run_wait_seconds` (900s) caps the server-side wait and
`asyncio.wait_for` wraps the whole fetch with `apify_fetch_deadline_seconds` (1200s);
BOTH are long/conservative because one batched run of up to ~64 videos can take
several minutes (the old un-bounded single-video `.call()` waited indefinitely and
froze the whole worker run). Each fetched transcript is **cached back onto
`video.transcript`** so a later sweep reuses it instead of re-paying Apify. A
transcript miss/failure/timeout degrades that video to a no-transcript placeholder
and is **NOT a strike**.

Then per video, ONE multimodal call (`enrich_model`, `gemini/gemini-2.5-flash-lite`)
over the thumbnail image + metadata + its transcript slice
(`enrich_transcript_char_budget`, 8000 chars) → `{genre tag, disciplines, prose
summary, facets}` — `enrich_one` RECEIVES the transcript (it no longer fetches its
own). The primary thumbnail is the pool's stored `thumbnail_url` (scrape prefers
YouTube's `maxres` variant — see `scraper.md`), falling back to a constructed
`hqdefault` URL when the row has none. `maxresdefault` only exists for HD uploads,
so a non-HD/older video 404s on it — litellm surfaces that as an image-fetch
`BadRequestError`, which `WorkerEnricher.enrich_one` catches and retries ONCE against
the constructed `hqdefault` URL (YouTube always serves that resolution) before
treating the video as a hard failure.

Transcript spend is priced per the batched actor: `apify_transcript_cost_per_transcript_usd`
($0.0005) per transcript actually scraped + `apify_actor_start_cost_usd` ($0.001)
per actor run started.

The tag + disciplines are written back onto the pool `video` row; summaries are
batch-embedded (`embedding_model`, `gemini/gemini-embedding-001` → `vector(3072)`,
chunks of `EMBED_BATCH_SIZE`, 64) and inserted as `video_rag` rows. This is the
RAG layer the FastApiBackend's unified feed and member recs rank against — the
model + dimension are a **cross-service contract** (`run.py` asserts
`embedding_dim == 3072` at startup; the served feed's `INNER JOIN video_rag` is
the enriched-gate every client reads through — see "the served feed" below).

**Strike semantics — hard errors only.** A video whose multimodal call OR whose
chunk's embed call raises gets `failure_count += 1` and is skipped; a video that
enriches successfully gets `failure_count` reset to 0. A missing transcript is
never a strike.

Spend is logged once at the end of the sweep as **POOL-LEVEL** cost rows
(`gym_id`/`run_id` NULL — a swept video is shared across gyms, so per-gym
attribution would be arbitrary): `transcript` (the lazy Apify spend),
`enrich` (the multimodal calls), `embed` (the summary embeddings).

## The strike / cleanup mechanic (`video.failure_count`)

Both sweeps share one counter on the pool `video` row: bumped on a hard failure,
reset to 0 on success. The tick's **cleanup** step (`scraper.md`, step 1) deletes
any video at `worker_failure_max` (3) strikes every tick, before finalize runs —
FK cascades remove its feed rows, its `video_rag` row, and any member recs.

## Failure semantics (runs, not videos)

A run's completion/failure is decided by the tick's **finalize** step
(`scraper.md`, step 2), purely from the run's feed rows — there is no per-stage
run-failure and no orphan sweep. See `scraper.md` for the complete/fail rules.

## The served feed (how the backend reads this work)

Not part of the worker, but the reason enrich + scan exist: the FastApiBackend's
**unified feed** (`GET /gyms/{id}/videos`) always merges the owner section with the
gym's latest **COMPLETED** run and serves ONLY **enriched-AND-accepted** videos
(`INNER JOIN video_rag` — an `accepted` row with no embedding stays invisible until
the enrich sweep reaches it). A **separate, ungated** owner-management listing
(`GET /gyms/{id}/videos/owner`) shows an owner-added video the instant it's added,
before enrichment, so the CRM can badge it "processing…" while the worker catches
up. See `FastApiBackend/CLAUDE.md`'s `videos` domain section for the full ranking
model (σ-scaled owner boost + decayed watch-penalty).

## Sequential by design (within a gym; global across sweeps)

The global `"video_worker_run"` lock means only one worker instance ticks at a
time. Within the scan/enrich sweeps, provider calls fan out only to the configured
`worker_*_concurrency` (`worker_enrich_concurrency`, `worker_scan_concurrency`).
Never bypass the lock or run two workers concurrently.
