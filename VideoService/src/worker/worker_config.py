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
    # Lease TTL for the global video-worker lock. Long enough to cover a tick's
    # setup, short enough that a crashed holder self-heals; the run is kept alive
    # past it by the heartbeat (renew).
    worker_lock_ttl_seconds: int = 900
    # Heartbeat interval — renew the lease this often while a run is in flight.
    worker_heartbeat_seconds: int = 300

    # --- scheduling / run caps ----------------------------------------------
    # There is no queue: each tick derives the highest-priority DUE gym from
    # run / spec / curation timestamps (worker_select_due_gym.sql). These knobs
    # tune that derivation.
    # Rolling window (hours) over which BOTH run caps below are counted.
    worker_cap_window_hours: int = 24
    # Max runs per gym within the window (a 3rd waits for the window to roll).
    worker_gym_run_cap: int = 2
    # Max runs across ALL gyms within the window — the global YouTube-quota /
    # Apify-transcript budget guard, separate from the per-gym cap.
    worker_system_run_cap: int = 5
    # Tier-2 batch settle: a manual curation triggers a run only once the most
    # recent manual curation is at least this old (owners curate in bursts, so
    # the delay batches a burst into a single run).
    worker_curation_batch_hours: int = 1
    # Tier-3 refresh floor: a gym whose last run is at least this many days old
    # is re-run even with no pending edit or curation.
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

    # --- concurrency ---------------------------------------------------------
    worker_scrape_concurrency: int = 4
    worker_enrich_concurrency: int = 8
    worker_scan_concurrency: int = 8

    # --- budgets -------------------------------------------------------------
    # Cap per query on the YouTube search (the API's search.list maxResults, ≤50).
    worker_max_results_per_query: int = 20
    # Hard cap on candidates scanned in one run (tier 1 first, then tier 2).
    scan_budget_per_run: int = 1000
    # Videos judged per scan LLM call.
    scan_batch_size: int = 12
    # Per-query top-k for the tier-2 RAG probes.
    rag_probe_top_k: int = 40
    # Head characters of transcript fed to the enrich call.
    enrich_transcript_char_budget: int = 8000

    # --- YouTube Data API + Apify transcripts --------------------------------
    # Google Cloud API key for the YouTube Data API v3 (discovery + metadata).
    # Free within the daily quota (10k units/day; search.list = 100 units).
    youtube_api_key: str = ""
    # Apify token for the transcript actor (transcripts are fetched lazily at
    # enrich, one actor run per video).
    apify_token: str = ""
    # pintostudio/youtube-transcript-scraper price per fetched video
    # ($10 / 1,000 results).
    apify_transcript_cost_per_video_usd: float = 0.01

    # --- models --------------------------------------------------------------
    # Multimodal classify+summarize call; provider-prefixed for litellm routing.
    enrich_model: str = "gemini/gemini-2.5-flash-lite"
    # Batched keep/drop scan call.
    scan_model: str = "gemini/gemini-2.5-flash-lite"
    # Summary embedding model. Its dimension is a cross-service contract with the
    # FastApiBackend readers — both pin the same model + dim.
    embedding_model: str = "openai/text-embedding-3-small"
    embedding_dim: int = 1536


settings = WorkerSettings()
