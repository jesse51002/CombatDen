"""Worker settings — the knobs, model ids, and Apify token for the background
worker, from env / ``.env``.

Kept separate from ``src/api/config.py`` (DB + lock) and ``src/core/config.py``
(LLM provider keys) so each concern owns its own ``Settings``, all reading the
same ``.env``. The worker composes all three: DB settings from the api config,
provider keys resolved by the LLM client via the core config, and these
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

    # --- concurrency ---------------------------------------------------------
    worker_scrape_concurrency: int = 4
    worker_enrich_concurrency: int = 8
    worker_scan_concurrency: int = 8

    # --- budgets -------------------------------------------------------------
    # Cap per query on the Apify scrape.
    worker_max_results_per_query: int = 20
    # Hard cap on candidates scanned in one run (tier 1 first, then tier 2).
    scan_budget_per_run: int = 1000
    # Videos judged per scan LLM call.
    scan_batch_size: int = 12
    # Per-query top-k for the tier-2 RAG probes.
    rag_probe_top_k: int = 40
    # Head characters of transcript fed to the enrich call.
    enrich_transcript_char_budget: int = 8000

    # --- Apify ---------------------------------------------------------------
    apify_token: str = ""
    # streamers/youtube-scraper price per returned video (~$2.40 / 1,000).
    apify_cost_per_video_usd: float = 0.0024

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
