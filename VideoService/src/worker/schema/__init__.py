"""Worker-internal LLM I/O schemas.

These are the structured request/response models for the worker's own LLM calls
(enrich, scan). They are deliberately separate from the top-level ``schema/``
package, which is the public ``videos_config.yaml`` contract — these never leave
the worker.
"""
