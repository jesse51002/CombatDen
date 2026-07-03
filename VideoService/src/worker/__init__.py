"""The VideoService background worker.

A standalone asyncio process (``python -m src.worker.run``) that consumes a
gym's video spec and produces its scanned feed. It pops the oldest gym from
``video_worker_queue`` under a global TTL-lease lock, then runs the pipeline:
scrape (Apify) → funnel (discipline pool + RAG probes) → enrich (one multimodal
classify+summarize+embed call per video) → scan (batched keep/drop) → feed write
(carry-forward + verdicts). Every stage is its own class; ``WorkerService``
orchestrates them.
"""
