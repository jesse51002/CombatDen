"""One-time cutover: load the EXISTING YAML data into SQL (no re-scrape/re-scan).

    poetry run python -m scripts.import_yaml.run

Loads, in order:
  1. the shared pool ``videos/<id>.yaml`` -> ``video`` (streamed in batches),
  2. the template enrich sidecar ``video_rag/video_rag.jsonl`` -> ``video_rag``
     (the pre-paid summaries + embeddings, so a reset reproduces enriched
     templates without re-running the LLM; absent sidecar -> warn + skip),
  3. each gym's existing ``good_video_ids`` / ``rejected_video_ids`` ->
     ``template_gym_feed`` (ids not in the pool are skipped),
  4. ``cost_log.yaml`` -> ``cost_log`` (the generic spend-ledger table).

Run AFTER the migration and ``sync-gyms`` (the gyms must already exist in SQL for
the feed FK). Idempotent: videos upsert by id and feeds are rewritten per gym, so
re-running is safe. The cost log is append-only, so only run that step once (use
``--skip-cost-log`` to re-run the rest without duplicating ledger rows).
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

import yaml

try:
    from yaml import CSafeLoader as _FAST_LOADER
except ImportError:  # pragma: no cover
    from yaml import SafeLoader as _FAST_LOADER

from schema import CostEntry, VideoOutput
from scripts.shared.db_target import build_write_pool
from scripts.shared.gym_yaml_store import list_gym_ids, load_gym_yaml
from scripts.shared.video_db_writer import VideoDbWriter
from scripts.shared.video_rag_sidecar import VideoRagRecord, VideoRagSidecar

logger = logging.getLogger(__name__)

_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent
VIDEOS_DIRNAME = "videos"
COST_LOG_FILENAME = "cost_log.yaml"
# Upsert the ~22k pool in batches so we never hold the whole pool in memory.
BATCH_SIZE = 500


async def _import_pool(writer: VideoDbWriter, root: Path) -> int:
    """Stream ``videos/*.yaml`` into ``video`` in batches. Returns rows written."""
    videos_dir = root / VIDEOS_DIRNAME
    if not videos_dir.is_dir():
        logger.warning("no pool dir at %s — skipping pool import", videos_dir)
        return 0
    files = sorted(videos_dir.glob("*.yaml"))
    logger.info("importing %d pooled videos from %s ...", len(files), videos_dir)
    written = 0
    batch: list[VideoOutput] = []
    for path in files:
        try:
            data = yaml.load(path.read_text(encoding="utf-8"), Loader=_FAST_LOADER)
            batch.append(VideoOutput.model_validate(data))
        except (OSError, yaml.YAMLError, ValueError) as exc:
            logger.warning("skipping %s: %s", path.name, exc)
            continue
        if len(batch) >= BATCH_SIZE:
            written += await writer.upsert_videos(batch)
            batch.clear()
            logger.info("  ... %d videos imported", written)
    if batch:
        written += await writer.upsert_videos(batch)
    logger.info("pool import done: %d videos", written)
    return written


async def _import_video_rag(writer: VideoDbWriter, root: Path) -> int:
    """Load the template enrich sidecar (``video_rag/video_rag.jsonl``) into
    ``video_rag`` in batches. Absent sidecar (a fresh checkout without the
    untracked-local artifact) -> warn + skip. Returns rows attempted."""
    sidecar = VideoRagSidecar(root)
    if not sidecar.exists():
        logger.warning(
            "no RAG sidecar at %s — skipping video_rag load (templates serve only "
            "once the worker enriches; run enrich-templates or fetch the sidecar, "
            "see VideoService/CLAUDE.md)",
            sidecar.path,
        )
        return 0
    logger.info("importing video_rag rows from %s ...", sidecar.path)
    written = 0
    batch: list[VideoRagRecord] = []
    for record in sidecar.read_all():
        batch.append(record)
        if len(batch) >= BATCH_SIZE:
            written += await writer.upsert_video_rag(batch)
            batch.clear()
            logger.info("  ... %d video_rag rows imported", written)
    if batch:
        written += await writer.upsert_video_rag(batch)
    logger.info("video_rag import done: %d rows", written)
    return written


async def _import_feeds(writer: VideoDbWriter, root: Path) -> int:
    """Load each gym's good/rejected id-lists from YAML into ``template_gym_feed``."""
    gym_ids = list_gym_ids(root)
    for gid in gym_ids:
        gym = load_gym_yaml(root, gid)
        await writer.set_gym_feed(
            gid, gym.videos.good_video_ids, gym.videos.rejected_video_ids
        )
        logger.info(
            "feed %s: %d good / %d rejected",
            gid,
            len(gym.videos.good_video_ids),
            len(gym.videos.rejected_video_ids),
        )
    return len(gym_ids)


async def _import_cost_log(writer: VideoDbWriter, root: Path) -> int:
    """Append ``cost_log.yaml`` entries into ``cost_log`` (no gym attribution
    — the old global log didn't record which gym a scan was for)."""
    log_file = root / COST_LOG_FILENAME
    if not log_file.is_file():
        logger.info("no %s — skipping cost-log import", COST_LOG_FILENAME)
        return 0
    loaded = yaml.safe_load(log_file.read_text(encoding="utf-8")) or []
    for raw in loaded:
        await writer.append_cost(CostEntry.model_validate(raw))
    logger.info("cost log import done: %d entries", len(loaded))
    return len(loaded)


async def run(*, root: Path, skip_cost_log: bool) -> None:
    pool = build_write_pool()
    writer = VideoDbWriter(pool)
    try:
        await _import_pool(writer, root)
        await _import_video_rag(writer, root)
        await _import_feeds(writer, root)
        if not skip_cost_log:
            await _import_cost_log(writer, root)
    finally:
        await pool.dispose()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    parser.add_argument(
        "--skip-cost-log",
        action="store_true",
        help="don't import cost_log.yaml (it's append-only — avoid duplicates)",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(run(root=args.root, skip_cost_log=args.skip_cost_log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
