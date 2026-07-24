"""Worker settings — the knobs, model ids, the YouTube Data API key, and the
Apify (transcript) token for the background worker, from env / ``.env``.

Kept separate from ``src/shared/config.py`` (DB + lock) and ``src/core/config.py``
(LLM provider keys) so each concern owns its own ``Settings``, all reading the
same ``.env``. The worker composes all three: DB settings from the shared
config, provider keys resolved by the LLM client via the core config, and these
worker-specific fields.

The model ids are ``settings`` fields (env-overridable) rather than per-call
constants because the worker is a long-running process an operator may want to
retune without a redeploy. ``enrich_model`` / ``scan_model`` default to
``gemini/gemini-2.5-flash-lite`` — the gemini-flash id already wired as the
classification model across this monorepo (VideoService's retired classify pass,
ThemeService's complexity model) — so the worker matches the rest of the stack.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class WorkerSettings(BaseSettings):
    """Background-worker config. Env vars (or ``.env``) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # --- loop / lock ---------------------------------------------------------
    # Exit cleanly at startup when false (a kill switch without stopping the
    # process supervisor).
    worker_enabled: bool = True
    # Seconds between ticks when idle.
    worker_poll_seconds: int = 60
    # Lease TTL for the global video-worker lock (30 min). Long enough to cover a
    # long heavy-step drain, short enough that a crashed holder self-heals; the run
    # is kept alive past it by the heartbeat (renew), which MUST stay well under the
    # TTL (heartbeat 300s < TTL 1800s) so a live holder never lets the lease lapse.
    worker_lock_ttl_seconds: int = 1800
    # Heartbeat interval — renew the lease this often while a run is in flight.
    worker_heartbeat_seconds: int = 300

    # --- scheduling / run caps ----------------------------------------------
    # There is no queue: each tick derives the highest-priority DUE gym from
    # run / spec timestamps (worker_select_due_gym.sql). These knobs tune that
    # derivation. A manual gym_video_feed curation does not trigger a run.
    # Rolling window (hours) over which BOTH run caps below are counted.
    worker_cap_window_hours: int = 24
    # Max runs per gym within the window (a 3rd waits for the window to roll).
    worker_gym_run_cap: int = 2
    # Max runs across ALL gyms within the window — the global YouTube-quota /
    # Apify-transcript budget guard, separate from the per-gym cap.
    worker_system_run_cap: int = 5
    # Tier-3 refresh floor: a gym whose last run is at least this many days old
    # is re-run even with no pending edit.
    worker_weekly_refresh_days: int = 7

    # --- strike ceiling + run finalize --------------------------------------
    # Hard-error strike ceiling: the enrich/scan sweeps bump video.failure_count
    # on a hard error (an LLM/embed call raising) and reset it to 0 on success;
    # the per-tick cleanup deletes a video once it reaches this many strikes.
    worker_failure_max: int = 3
    # A 'running' run finalizes to 'completed' once at least this fraction of its
    # feed rows are terminal (scan_status accepted/rejected).
    worker_run_complete_fraction: float = 0.9
    # A 'running' run that has not reached the completion fraction by this age is
    # failed ('run ttl exceeded') — the stuck-run backstop.
    worker_run_ttl_hours: int = 24
    # Grace before a 'running' run with ZERO feed rows is failed ('no feed rows')
    # — lets a scrape whose rows land shortly after the run row not be failed
    # prematurely.
    worker_zero_row_grace_hours: int = 1
    # Feed-learning re-scan wait: the scan sweep re-judges a gym's 'automatic'
    # feed rows against a new 'feed_update' spec version only once that version has
    # settled at least this many hours (the coalescing window — a burst of manual
    # curations mints one feed_update, and the wait lets it quiesce before the
    # in-place re-scan runs). The immediate refine that mints the version lives in
    # the backend; this delay lives here in the worker.
    worker_feed_update_rescan_delay_hours: float = 1.0

    # --- concurrency ---------------------------------------------------------
    worker_scrape_concurrency: int = 4
    worker_enrich_concurrency: int = 8

    # --- budgets -------------------------------------------------------------
    # Cap per query on the YouTube search (the API's search.list maxResults, ≤50)
    # — pinned AT the cap, because maxResults does not affect quota: search.list
    # costs a flat 100 units per call at any page size, and the follow-up
    # videos.list batches ≤50 ids into one 1-unit call. A smaller page throws
    # away candidates already paid for at full price.
    worker_max_results_per_query: int = 50
    # Hard cap on candidates scanned in one run (tier 1 first, then tier 2).
    scan_budget_per_run: int = 1000
    # Videos judged per scan LLM call.
    scan_batch_size: int = 12
    # Enrich sweep batch: videos per sweep chunk == texts per embed call == the
    # transcript batch fetched up front per chunk. The provider caps batch size /
    # tokens; 64 short summaries per call keeps well under it while amortising the
    # request overhead. Also the granularity at which the abort flag is checked.
    worker_enrich_batch_size: int = 64
    # Per-query top-k for the tier-2 RAG probes.
    rag_probe_top_k: int = 40
    # Head characters of transcript fed to the enrich call.
    enrich_transcript_char_budget: int = 8000

    # --- LLM client (litellm, src/shared/services/llm_client.py) -------------
    # Per-attempt request timeout for every completion/embed call. Overrides
    # LiteLLMClient's DEFAULT_REQUEST_TIMEOUT_SECONDS for the worker's clients.
    llm_request_timeout_seconds: float = 90
    # Transport-level retries (litellm's own backoff) for a transient provider
    # failure. Overrides LiteLLMClient's DEFAULT_LLM_NUM_RETRIES.
    llm_num_retries: int = 5
    # Backoff (seconds) before each schema re-ask after a miss. Overrides
    # LiteLLMClient's DEFAULT_RETRY_BACKOFF_SECONDS.
    llm_retry_backoff_seconds: tuple[int, int] = (5, 15)

    # --- YouTube Data API + Apify transcripts --------------------------------
    # Google Cloud API key for the YouTube Data API v3 (discovery + metadata).
    # Free within the daily quota (10k units/day; search.list = 100 units).
    youtube_api_key: str = ""
    # Per-request timeout for the YouTube Data API httpx client (search.list /
    # videos.list).
    worker_youtube_timeout_seconds: float = 30.0
    # Apify token for the transcript actor. Transcripts are fetched lazily at
    # enrich, BATCHED: one actor run per chunk of cache-miss videos
    # (supreme_coder/youtube-transcript-scraper takes a list of urls).
    apify_token: str = ""
    # supreme_coder/youtube-transcript-scraper pricing: $0.0005 per transcript
    # scraped + $0.001 per actor start (per run). A batch costs
    # (transcripts_returned × per-transcript) + (1 × per-start).
    apify_transcript_cost_per_transcript_usd: float = 0.0005
    apify_actor_start_cost_usd: float = 0.001
    # Max video urls per batched transcript actor run — a chunk's miss-list is
    # split into runs of this size.
    apify_transcript_batch_size: int = 64
    # LONG/conservative Apify timeouts — one batched run of up to ~64 videos may
    # take several minutes and the ceiling is unknown, so both are generous.
    # Server-side wait passed to the actor `.call()` (the .call() default is to
    # wait INDEFINITELY, which froze the whole worker run — this bounds it).
    apify_run_wait_seconds: int = 900
    # Client-side deadline wrapping the whole fetch_batch (belt to the .call()
    # wait): on expiry the batch degrades to all-placeholder, no strike.
    apify_fetch_deadline_seconds: int = 1200
    # Generous retry count for the Apify HTTP client (transient API failures).
    apify_max_retries: int = 5

    # --- models --------------------------------------------------------------
    # Multimodal classify+summarize call; provider-prefixed for litellm routing.
    enrich_model: str = "gemini/gemini-2.5-flash-lite"
    # Batched keep/drop scan call.
    scan_model: str = "gemini/gemini-2.5-flash-lite"
    # Summary embedding model. Its dimension is a cross-service contract with the
    # FastApiBackend readers — both pin the same model + dim. gemini-embedding-001
    # outputs native 3072 (pre-normalized at 3072); stored full precision, HNSW
    # indexed as a halfvec cast (vector can't HNSW past 2000 dims).
    embedding_model: str = "gemini/gemini-embedding-001"
    embedding_dim: int = 3072


settings = WorkerSettings()
