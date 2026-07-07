"""The VideoService background worker.

A standalone asyncio process (``python -m src.worker.run``) that consumes a
gym's video spec and produces its scanned feed. Under a global TTL-lease lock it
*derives* the highest-priority due gym from run/spec/curation timestamps (no
queue — ``worker_select_due_gym.sql``, under per-gym + system rolling run caps),
then runs the pipeline: scrape (Apify) → funnel (discipline pool + RAG probes) →
enrich (one multimodal classify+summarize+embed call per video) → scan (batched
keep/drop) → feed write (carry-forward + verdicts). Every stage is its own class;
``WorkerService`` orchestrates them.
"""
