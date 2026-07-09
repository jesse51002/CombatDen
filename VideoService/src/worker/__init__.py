"""The VideoService background worker.

A standalone asyncio process (``python -m src.worker.run``) that keeps every gym's
video feed and the shared RAG layer current. It is DB-backed and step-decoupled:
each tick, under a global TTL-lease lock, runs CLEANUP (drop strike-maxed videos),
FINALIZE (complete / fail 'running' runs from their feed rows), then the first
heavy step with work — SCAN, else ENRICH, else SCRAPE — drained fully.

Feed rows are written at SCRAPE time as ``pending``; the global ENRICH sweep gives
every un-enriched video a ``video_rag`` row; the global SCAN sweep settles each
``pending`` row to accepted/rejected. There is no queue (the SCRAPE step derives
the due gym from run/spec/curation timestamps under per-gym + system run caps) and
no orphan rule ('running' is a legitimate long-lived state). Each step is its own
class; ``WorkerService`` orchestrates the tick.
"""
